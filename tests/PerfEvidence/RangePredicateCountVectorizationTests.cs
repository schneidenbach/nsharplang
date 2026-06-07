using System;
using System.Reflection;
using Xunit;
using NSharpLang.Runtime;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P2(b): the masked-SIMD range-predicate count codegen (the count-ascii kernel). When enabled, the
/// compiler lowers `[v := a[i];] if a[i] >= lo && a[i] <= hi { count++ }` over an int[] to a call to
/// NSharpLang.Runtime.SimdReductions.CountInRangeInt32 (packed compare + masked accumulate). These tests pin
/// (a) value-IDENTITY with the scalar loop across lengths incl. SIMD tails and inclusive boundaries, (b) that
/// the optimization fires (a helper call replaces the scalar element-load loop), and (c) the conservative
/// fall-backs (non-int lo/hi, non-int[] array, out-of-range bound) so it can never change results.
/// </summary>
[Trait("Category", "Simd")]
public class RangePredicateCountVectorizationTests
{
    private static readonly MethodInfo s_setFlag =
        typeof(Compiler.ILCompiler.ILCompiler).GetMethod(
            "SetReductionVectorizationForCurrentThread", BindingFlags.Static | BindingFlags.NonPublic)!;

    private static void Vectorize(bool? enabled) => s_setFlag.Invoke(null, new object?[] { enabled });

    private static object Run(string src, string fn, bool? flag, object[] args)
    {
        Vectorize(flag);
        try
        {
            return ILShapeInspector.Compile(src, asm =>
                ILShapeInspector.GetProgramMethod(asm, fn).Invoke(null, args)!);
        }
        finally
        {
            Vectorize(null);
        }
    }

    private static int Calls(string src, string fn, bool? flag)
    {
        Vectorize(flag);
        try
        {
            return ILShapeInspector.Compile(src, asm =>
                ILShapeInspector.CountCall(ILShapeInspector.GetProgramMethod(asm, fn)));
        }
        finally
        {
            Vectorize(null);
        }
    }

    // Deterministic input spanning below/at/above the [32,126] range, incl. the inclusive boundaries.
    private static int[] AsciiLike(int n)
    {
        var data = new int[n];
        for (var k = 0; k < n; k++) data[k] = ((k * 17) + 3) & 0xff; // 0..255: mix in-range and out-of-range
        if (n > 0) data[0] = 32;    // exactly lo (inclusive)
        if (n > 1) data[1] = 126;   // exactly hi (inclusive)
        if (n > 2) data[2] = 31;    // just below
        if (n > 3) data[3] = 127;   // just above
        return data;
    }

    // The count-ascii benchmark shape: for-form, temp subject, literal inclusive bounds.
    private const string ForTempLiteral = @"
func countAscii(a: int[], n: int): int {
    count := 0
    for i := 0; i < n; i++ {
        value := a[i]
        if value >= 32 && value <= 126 {
            count = count + 1
        }
    }
    return count
}";

    // for-form, inlined subject, parameter bounds, count++.
    private const string ForInlinedParam = @"
func cnt(a: int[], n: int, lo: int, hi: int): int {
    count := 0
    for i := 0; i < n; i++ {
        if a[i] >= lo && a[i] <= hi {
            count++
        }
    }
    return count
}";

    // while-form, temp subject, count += 1.
    private const string WhileTemp = @"
func cntW(a: int[], n: int, lo: int, hi: int): int {
    count := 0
    i := 0
    while i < n {
        value := a[i]
        if value >= lo && value <= hi {
            count += 1
        }
        i = i + 1
    }
    return count
}";

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(7)]
    [InlineData(8)]
    [InlineData(15)]
    [InlineData(16)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedCountAscii_IsValueIdenticalToScalar(int n)
    {
        var data = AsciiLike(n);
        Assert.Equal(
            Run(ForTempLiteral, "countAscii", false, new object[] { data, n }),
            Run(ForTempLiteral, "countAscii", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(8)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedRangeCount_InlinedAndWhileForms_MatchScalar(int n)
    {
        var data = AsciiLike(n);
        Assert.Equal(
            Run(ForInlinedParam, "cnt", false, new object[] { data, n, 32, 126 }),
            Run(ForInlinedParam, "cnt", true, new object[] { data, n, 32, 126 }));
        Assert.Equal(
            Run(WhileTemp, "cntW", false, new object[] { data, n, 32, 126 }),
            Run(WhileTemp, "cntW", true, new object[] { data, n, 32, 126 }));
    }

    [Theory]
    [InlineData(ForTempLiteral, "countAscii")]   // for-form
    [InlineData(WhileTemp, "cntW")]              // while-form
    public void RangeCount_LowersToHelperCall_OnlyWhenEnabled(string src, string fn)
    {
        Assert.Equal(0, Calls(src, fn, false));
        Assert.True(Calls(src, fn, true) >= 1, "range-count must lower to a SIMD helper call when enabled");
    }

    [Fact]
    public void RangeCount_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar()
    {
        var data = new int[10];
        Vectorize(true);
        try
        {
            var ex = Assert.Throws<TargetInvocationException>(() =>
                ILShapeInspector.Compile(ForTempLiteral, asm =>
                    ILShapeInspector.GetProgramMethod(asm, "countAscii").Invoke(null, new object[] { data, 100 })));
            Assert.IsType<IndexOutOfRangeException>(ex.InnerException);
        }
        finally
        {
            Vectorize(null);
        }
    }

    [Theory]
    [InlineData(int.MinValue)]
    [InlineData(-1)]
    [InlineData(0)]
    public void RangeCount_EmptyOrNegativeBound_MatchesScalar_NoOutOfBoundsRead(int n)
    {
        var data = AsciiLike(100);
        var scalar = (int)Run(ForTempLiteral, "countAscii", false, new object[] { data, n });
        var vector = (int)Run(ForTempLiteral, "countAscii", true, new object[] { data, n });
        Assert.Equal(0, scalar);
        Assert.Equal(scalar, vector);
    }

    // Non-int lo (long) must NOT vectorize (the helper compares int lanes; a long comparison promotes the
    // element). The scalar fallback stays correct and emits no helper call.
    private const string ForLongLo = @"
func cntLongLo(a: int[], n: int, lo: long, hi: int): int {
    count := 0
    for i := 0; i < n; i++ {
        if a[i] >= lo && a[i] <= hi {
            count++
        }
    }
    return count
}";

    [Fact]
    public void RangeCount_NonIntBound_DoesNotVectorize_ButMatchesScalar()
    {
        var data = AsciiLike(64);
        Assert.Equal(0, Calls(ForLongLo, "cntLongLo", true)); // long lo → falls back to scalar (no helper call)
        Assert.Equal(
            Run(ForLongLo, "cntLongLo", false, new object[] { data, 64, 32L, 126 }),
            Run(ForLongLo, "cntLongLo", true, new object[] { data, 64, 32L, 126 }));
    }

    // Non-int[] array (long[]) must NOT vectorize via the int helper.
    private const string ForLongArray = @"
func cntLongArr(a: long[], n: int, lo: int, hi: int): int {
    count := 0
    for i := 0; i < n; i++ {
        if a[i] >= lo && a[i] <= hi {
            count++
        }
    }
    return count
}";

    [Fact]
    public void RangeCount_NonIntArray_DoesNotVectorize_ButMatchesScalar()
    {
        var data = new long[64];
        for (var k = 0; k < data.Length; k++) data[k] = ((k * 17) + 3) & 0xff;
        Assert.Equal(0, Calls(ForLongArray, "cntLongArr", true));
        Assert.Equal(
            Run(ForLongArray, "cntLongArr", false, new object[] { data, 64, 32, 126 }),
            Run(ForLongArray, "cntLongArr", true, new object[] { data, 64, 32, 126 }));
    }
}

/// <summary>
/// Direct edge-case coverage of the masked-count helper <see cref="SimdReductions.CountInRangeInt32"/>,
/// exercising the SIMD masked-compare PATH (not just the scalar tail) for ranges the codegen tests don't
/// stress with SIMD-sized signed input: lo&gt;hi (empty), lo==hi (single value), negative ranges, and the
/// int.MinValue / int.MaxValue boundaries. 200 elements guarantee multiple Vector&lt;int&gt; chunks plus a
/// scalar tail on every lane width.
/// </summary>
public class CountInRangeHelperEdgeCaseTests
{
    private static int ScalarCount(int[] a, int lo, int hi)
    {
        var c = 0;
        for (var i = 0; i < a.Length; i++)
            if (a[i] >= lo && a[i] <= hi)
                c++;
        return c;
    }

    [Theory]
    [InlineData(150, 100)]                    // lo > hi -> empty set
    [InlineData(105, 105)]                    // lo == hi -> single value
    [InlineData(-50, 50)]                     // negative .. positive
    [InlineData(int.MinValue, 0)]             // MinValue boundary
    [InlineData(0, int.MaxValue)]             // MaxValue boundary
    [InlineData(int.MinValue, int.MaxValue)]  // whole range -> all
    public void CountInRangeInt32_SimdPath_MatchesScalar(int lo, int hi)
    {
        var seeds = new[] { int.MinValue, -100, -50, -1, 0, 1, 50, 100, 105, 126, int.MaxValue };
        var data = new int[200];
        for (var k = 0; k < data.Length; k++) data[k] = seeds[k % seeds.Length];

        Assert.Equal(ScalarCount(data, lo, hi), SimdReductions.CountInRangeInt32(data, 0, data.Length, lo, hi));
    }
}

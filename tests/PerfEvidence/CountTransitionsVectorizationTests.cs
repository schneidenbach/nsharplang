using System;
using System.Reflection;
using Xunit;
using NSharpLang.Runtime;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P-ctrans (b): the shifted-compare SIMD adjacent-difference count (the count-transitions kernel, the
/// last ~2.5–4.5× Rust gap). When enabled, the compiler lowers
/// `current := a[i]; if current != previous { count++ }; previous = current` over an int[] to a call to
/// NSharpLang.Runtime.SimdReductions.CountTransitionsInt32 (packed not-equal compare of a[i] vs a[i-1] + masked
/// accumulate, seeded with the carried `previous`). These tests pin (a) value-IDENTITY with the scalar loop
/// across lengths incl. SIMD tails (count AND the restored terminal `previous`), (b) that it fires (one helper
/// call replaces the element-load loop), and (c) the conservative fall-backs (non-int[] array, out-of-range
/// bound) so it can never change results.
/// </summary>
[Trait("Category", "Simd")]
public class CountTransitionsVectorizationTests
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

    // Deterministic data with frequent adjacent repeats (runs) AND transitions, plus int extremes mid-array, and
    // a seed (a[0]) distinct from a[1] so the first comparison is a transition.
    private static int[] RunsLike(int n)
    {
        var data = new int[n];
        for (var k = 0; k < n; k++) data[k] = (((k * 1103515245) + 12345) >> 16) & 0x3; // 0..3, frequent repeats
        if (n > 4) data[4] = int.MinValue;
        if (n > 9) data[9] = int.MaxValue;
        if (n > 0) data[0] = 7;
        return data;
    }

    // The count-transitions benchmark shape: for-form, temp subject, seeded from a[0], loop over [1, n).
    private const string ForCount = @"
func countTransitions(a: int[], n: int): int {
    if n == 0 {
        return 0
    }
    count := 0
    previous := a[0]
    for i := 1; i < n; i++ {
        current := a[i]
        if current != previous {
            count = count + 1
        }
        previous = current
    }
    return count
}";

    // while-form, count++.
    private const string WhileCount = @"
func ctW(a: int[], n: int): int {
    if n == 0 {
        return 0
    }
    count := 0
    previous := a[0]
    i := 1
    while i < n {
        current := a[i]
        if current != previous {
            count++
        }
        previous = current
        i = i + 1
    }
    return count
}";

    // Returns the TERMINAL `previous` (= a[n-1] for n>=1) — pins that the emitter restores the carried scalar.
    private const string ForLastPrev = @"
func lastPrev(a: int[], n: int): int {
    count := 0
    previous := a[0]
    for i := 1; i < n; i++ {
        current := a[i]
        if current != previous {
            count = count + 1
        }
        previous = current
    }
    return previous
}";

    private const string WhileMutablePreviousBound = @"
func mutablePreviousBound(a: int[]): int {
    count := 0
    previous := 4
    i := 0
    while i < previous {
        current := a[i]
        if current != previous {
            count = count + 1
        }
        previous = current
        i = i + 1
    }
    return count * 1000 + i * 10 + previous
}";

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(7)]
    [InlineData(8)]
    [InlineData(15)]
    [InlineData(16)]
    [InlineData(17)]
    [InlineData(33)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedCountTransitions_IsValueIdenticalToScalar(int n)
    {
        var data = RunsLike(n);
        Assert.Equal(
            Run(ForCount, "countTransitions", false, new object[] { data, n }),
            Run(ForCount, "countTransitions", true, new object[] { data, n }));
        Assert.Equal(
            Run(WhileCount, "ctW", false, new object[] { data, n }),
            Run(WhileCount, "ctW", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(8)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedCountTransitions_RestoresTerminalPrevious(int n)
    {
        var data = RunsLike(n);
        Assert.Equal(
            Run(ForLastPrev, "lastPrev", false, new object[] { data, n }),
            Run(ForLastPrev, "lastPrev", true, new object[] { data, n }));
    }

    [Fact]
    public void CountTransitions_LowersToOneHelperCall_OnlyWhenEnabled()
    {
        Assert.Equal(0, Calls(ForCount, "countTransitions", false));
        Assert.Equal(1, Calls(ForCount, "countTransitions", true)); // CountTransitionsInt32
        Assert.Equal(0, Calls(WhileCount, "ctW", false));
        Assert.Equal(1, Calls(WhileCount, "ctW", true));
    }

    [Fact]
    public void CountTransitions_MutableBoundFallsBackToScalar()
    {
        var data = new[] { 3, 2, 2, 2 };
        Assert.Equal(0, Calls(WhileMutablePreviousBound, "mutablePreviousBound", true));

        var scalar = Run(WhileMutablePreviousBound, "mutablePreviousBound", false, new object[] { data });
        var vectorizationEnabled = Run(WhileMutablePreviousBound, "mutablePreviousBound", true, new object[] { data });
        Assert.Equal(2022, scalar);
        Assert.Equal(scalar, vectorizationEnabled);
    }

    [Fact]
    public void CountTransitions_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar()
    {
        var data = new int[10];
        Vectorize(true);
        try
        {
            var ex = Assert.Throws<TargetInvocationException>(() =>
                ILShapeInspector.Compile(ForCount, asm =>
                    ILShapeInspector.GetProgramMethod(asm, "countTransitions").Invoke(null, new object[] { data, 100 })));
            Assert.IsType<IndexOutOfRangeException>(ex.InnerException);
        }
        finally
        {
            Vectorize(null);
        }
    }

    // Non-int[] array (long[]) must NOT vectorize via the int helper; scalar fallback stays correct.
    private const string ForLongArray = @"
func ctLong(a: long[], n: int): int {
    count := 0
    previous := a[0]
    for i := 1; i < n; i++ {
        current := a[i]
        if current != previous {
            count = count + 1
        }
        previous = current
    }
    return count
}";

    [Fact]
    public void CountTransitions_NonIntArray_DoesNotVectorize_ButMatchesScalar()
    {
        var data = new long[64];
        for (var k = 0; k < data.Length; k++) data[k] = (((long)k * 6364136223846793005L) >> 33) & 0x3;
        data[0] = 7;
        Assert.Equal(0, Calls(ForLongArray, "ctLong", true)); // long[] → falls back to scalar (no helper call)
        Assert.Equal(
            Run(ForLongArray, "ctLong", false, new object[] { data, 64 }),
            Run(ForLongArray, "ctLong", true, new object[] { data, 64 }));
    }
}

/// <summary>
/// Direct edge-case coverage of the shifted-compare helper <see cref="SimdReductions.CountTransitionsInt32"/>,
/// exercising the SIMD masked-compare PATH (not just the scalar tail) with SIMD-sized input: all-equal (0
/// transitions), all-different, runs, int extremes, a seed equal vs unequal to a[start], and partial ranges. 200
/// elements guarantee multiple Vector&lt;int&gt; chunks plus a scalar tail on every lane width.
/// </summary>
public class CountTransitionsHelperEdgeCaseTests
{
    private static (int Count, int LastPrevious) Scalar(int[] a, int start, int end, int seedPrevious)
    {
        var count = 0;
        var prev = seedPrevious;
        for (var i = start; i < end; i++)
        {
            if (a[i] != prev) count++;
            prev = a[i];
        }
        return (count, prev);
    }

    private static int[] Runs()
    {
        var data = new int[200];
        for (var k = 0; k < data.Length; k++) data[k] = (((k * 1103515245) + 12345) >> 16) & 0x7;
        data[40] = int.MinValue;
        data[41] = int.MinValue; // an equal pair at the extreme
        data[120] = int.MaxValue;
        return data;
    }

    [Theory]
    [InlineData(7)]          // seed != a[0]
    [InlineData(0)]          // seed possibly == a[0]
    [InlineData(int.MinValue)]
    [InlineData(int.MaxValue)]
    public void CountTransitionsInt32_SimdPath_MatchesScalar_AcrossSeeds(int seed)
    {
        var data = Runs();
        Assert.Equal(Scalar(data, 0, data.Length, seed), SimdReductions.CountTransitionsInt32(data, 0, data.Length, seed));
    }

    [Theory]
    [InlineData(1, 200)]   // the count-transitions shape: non-zero start, SIMD tail
    [InlineData(0, 200)]
    [InlineData(3, 197)]
    [InlineData(50, 150)]
    public void CountTransitionsInt32_PartialRange_MatchesScalar(int start, int end)
    {
        var data = Runs();
        Assert.Equal(Scalar(data, start, end, data[start == 0 ? 0 : start - 1]),
            SimdReductions.CountTransitionsInt32(data, start, end, data[start == 0 ? 0 : start - 1]));
    }

    [Fact]
    public void CountTransitionsInt32_AllEqual_IsZeroTransitions()
    {
        var data = new int[200];
        Array.Fill(data, 42);
        // seed == the value → 0 transitions; terminal previous == 42.
        Assert.Equal((0, 42), SimdReductions.CountTransitionsInt32(data, 0, data.Length, 42));
        // seed != the value → exactly 1 transition (the first element), then all equal.
        Assert.Equal((1, 42), SimdReductions.CountTransitionsInt32(data, 0, data.Length, 7));
    }

    [Fact]
    public void CountTransitionsInt32_AllDifferent_CountsEveryElement()
    {
        var data = new int[200];
        for (var k = 0; k < data.Length; k++) data[k] = k; // strictly increasing → every adjacent pair differs
        // seed (-1) != a[0]=0, then all 200 elements differ from their predecessor → 200 transitions.
        Assert.Equal((200, 199), SimdReductions.CountTransitionsInt32(data, 0, data.Length, -1));
    }

    [Fact]
    public void CountTransitionsInt32_EmptyRange_ReturnsSeed()
    {
        var data = Runs();
        Assert.Equal((0, 99), SimdReductions.CountTransitionsInt32(data, 5, 5, 99));   // empty
        Assert.Equal((0, 99), SimdReductions.CountTransitionsInt32(data, 10, 3, 99));  // negative range
    }
}

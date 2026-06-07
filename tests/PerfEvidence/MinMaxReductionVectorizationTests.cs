using System;
using System.Reflection;
using Xunit;
using NSharpLang.Runtime;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P-minmax (b): the lane-wise SIMD min/max reduction codegen (the min-max-delta kernel, the ~10.5×
/// Rust gap). When enabled, the compiler lowers `if a[i] &lt; min { min = a[i] }` / `if a[i] &gt; max { max = a[i] }`
/// over an int[] to calls to NSharpLang.Runtime.SimdReductions.MinInt32 / MaxInt32 (Vector.Min/Vector.Max). These
/// tests pin (a) value-IDENTITY with the scalar loop across lengths incl. SIMD tails and signed extremes, (b) that
/// the optimization fires (one helper call per reduction), and (c) the conservative fall-backs (non-int[] array,
/// non-int accumulator, out-of-range bound) so it can never change results.
/// </summary>
[Trait("Category", "Simd")]
public class MinMaxReductionVectorizationTests
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

    // Deterministic signed input spanning negatives, zero, positives, and the int extremes at known positions, so
    // the min/max are non-trivial and the seed (a[0]) is neither the global min nor max.
    private static int[] SignedLike(int n)
    {
        var data = new int[n];
        for (var k = 0; k < n; k++) data[k] = (((k * 1103515245) + 12345) & 0x7fffffff) - 0x40000000; // pseudo signed
        if (n > 3) data[3] = int.MinValue;  // global min mid-array
        if (n > 5) data[5] = int.MaxValue;  // global max mid-array
        if (n > 0) data[0] = 7;             // seed is an interior value
        return data;
    }

    // The min-max-delta benchmark shape: for-form, temp subject, seeded from a[0], loop over [1, n).
    private const string ForTempMinMax = @"
func minMaxDelta(a: int[], n: int): int {
    if n == 0 {
        return 0
    }
    min := a[0]
    max := a[0]
    for i := 1; i < n; i++ {
        value := a[i]
        if value < min {
            min = value
        }
        if value > max {
            max = value
        }
    }
    return max - min
}";

    // for-form, inlined subject, a.Length bound, full [0, len) range.
    private const string ForInlinedMinMax = @"
func mmd(a: int[]): int {
    if a.Length == 0 {
        return 0
    }
    min := a[0]
    max := a[0]
    for i := 0; i < a.Length; i++ {
        if a[i] < min {
            min = a[i]
        }
        if a[i] > max {
            max = a[i]
        }
    }
    return max - min
}";

    // while-form, temp subject.
    private const string WhileTempMinMax = @"
func mmw(a: int[], n: int): int {
    if n == 0 {
        return 0
    }
    min := a[0]
    max := a[0]
    i := 1
    while i < n {
        value := a[i]
        if value < min {
            min = value
        }
        if value > max {
            max = value
        }
        i = i + 1
    }
    return max - min
}";

    // min-only reduction (single helper call).
    private const string ForMinOnly = @"
func minOf(a: int[], n: int): int {
    min := a[0]
    for i := 1; i < n; i++ {
        if a[i] < min {
            min = a[i]
        }
    }
    return min
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
    public void VectorizedMinMaxDelta_IsValueIdenticalToScalar(int n)
    {
        var data = SignedLike(n);
        Assert.Equal(
            Run(ForTempMinMax, "minMaxDelta", false, new object[] { data, n }),
            Run(ForTempMinMax, "minMaxDelta", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(8)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedMinMax_InlinedAndWhileForms_MatchScalar(int n)
    {
        var data = SignedLike(n);
        Assert.Equal(
            Run(ForInlinedMinMax, "mmd", false, new object[] { data }),
            Run(ForInlinedMinMax, "mmd", true, new object[] { data }));
        Assert.Equal(
            Run(WhileTempMinMax, "mmw", false, new object[] { data, n }),
            Run(WhileTempMinMax, "mmw", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(8)]
    [InlineData(17)]
    [InlineData(64)]
    public void VectorizedMinOnly_MatchesScalar(int n)
    {
        var data = SignedLike(n);
        Assert.Equal(
            Run(ForMinOnly, "minOf", false, new object[] { data, n }),
            Run(ForMinOnly, "minOf", true, new object[] { data, n }));
    }

    [Fact]
    public void MinMax_LowersToOneFusedHelperCall_OnlyWhenEnabled()
    {
        // P-minmax(c): the [1 min, 1 max] body fuses into a SINGLE MinMaxInt32 call (one scan computes both),
        // not two separate MinInt32 + MaxInt32 scans.
        Assert.Equal(0, Calls(ForTempMinMax, "minMaxDelta", false));
        Assert.Equal(1, Calls(ForTempMinMax, "minMaxDelta", true)); // fused MinMaxInt32
        Assert.Equal(0, Calls(WhileTempMinMax, "mmw", false));
        Assert.Equal(1, Calls(WhileTempMinMax, "mmw", true));
    }

    [Fact]
    public void MinOnly_LowersToOneHelperCall_OnlyWhenEnabled()
    {
        Assert.Equal(0, Calls(ForMinOnly, "minOf", false));
        Assert.Equal(1, Calls(ForMinOnly, "minOf", true)); // MinInt32 only (no max → not fused)
    }

    [Fact]
    public void MinMax_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar()
    {
        var data = new int[10];
        Vectorize(true);
        try
        {
            var ex = Assert.Throws<TargetInvocationException>(() =>
                ILShapeInspector.Compile(ForTempMinMax, asm =>
                    ILShapeInspector.GetProgramMethod(asm, "minMaxDelta").Invoke(null, new object[] { data, 100 })));
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
    [InlineData(1)]
    public void MinMax_EmptyOrNegativeBound_MatchesScalar_NoOutOfBoundsRead(int n)
    {
        var data = SignedLike(100);
        Assert.Equal(
            Run(ForTempMinMax, "minMaxDelta", false, new object[] { data, n }),
            Run(ForTempMinMax, "minMaxDelta", true, new object[] { data, n }));
    }

    // Non-int[] array (long[]) must NOT vectorize via the int helper; scalar fallback stays correct.
    private const string ForLongArray = @"
func mmLong(a: long[], n: int): long {
    min := a[0]
    max := a[0]
    for i := 1; i < n; i++ {
        if a[i] < min {
            min = a[i]
        }
        if a[i] > max {
            max = a[i]
        }
    }
    return max - min
}";

    [Fact]
    public void MinMax_NonIntArray_DoesNotVectorize_ButMatchesScalar()
    {
        var data = new long[64];
        for (var k = 0; k < data.Length; k++) data[k] = (((long)k * 2862933555777941757L) + 3037000493L) & 0x7fffffff;
        data[0] = 7;
        Assert.Equal(0, Calls(ForLongArray, "mmLong", true)); // long[] → falls back to scalar (no helper call)
        Assert.Equal(
            Run(ForLongArray, "mmLong", false, new object[] { data, 64 }),
            Run(ForLongArray, "mmLong", true, new object[] { data, 64 }));
    }
}

/// <summary>
/// Direct edge-case coverage of the min/max helpers <see cref="SimdReductions.MinInt32"/> /
/// <see cref="SimdReductions.MaxInt32"/>, exercising the SIMD reduce PATH (not just the scalar tail) with
/// SIMD-sized signed input where the answer lives on a non-tail lane: the int.MinValue / int.MaxValue extremes,
/// all-equal data, a seed that is the global extremum, and partial ranges. 200 elements guarantee multiple
/// Vector&lt;int&gt; chunks plus a scalar tail on every lane width.
/// </summary>
public class MinMaxHelperEdgeCaseTests
{
    private static int ScalarMin(int[] a, int start, int end, int seed)
    {
        var m = seed;
        for (var i = start; i < end; i++)
            if (a[i] < m) m = a[i];
        return m;
    }

    private static int ScalarMax(int[] a, int start, int end, int seed)
    {
        var m = seed;
        for (var i = start; i < end; i++)
            if (a[i] > m) m = a[i];
        return m;
    }

    private static int[] Mixed()
    {
        var seeds = new[] { int.MinValue, -100, -50, -1, 0, 1, 50, 100, 105, 126, int.MaxValue };
        var data = new int[200];
        for (var k = 0; k < data.Length; k++) data[k] = seeds[k % seeds.Length];
        return data;
    }

    [Theory]
    [InlineData(int.MinValue)]
    [InlineData(-1000)]
    [InlineData(0)]
    [InlineData(7)]
    [InlineData(int.MaxValue)]
    public void MinMaxInt32_SimdPath_MatchesScalar_AcrossSeeds(int seed)
    {
        var data = Mixed();
        Assert.Equal(ScalarMin(data, 0, data.Length, seed), SimdReductions.MinInt32(data, 0, data.Length, seed));
        Assert.Equal(ScalarMax(data, 0, data.Length, seed), SimdReductions.MaxInt32(data, 0, data.Length, seed));
    }

    [Theory]
    [InlineData(0, 200)]
    [InlineData(1, 200)]   // non-zero start (the min-max-delta shape), SIMD tail
    [InlineData(3, 197)]   // both ends off the SIMD stride
    [InlineData(50, 150)]
    public void MinMaxInt32_PartialRange_MatchesScalar(int start, int end)
    {
        var data = Mixed();
        Assert.Equal(ScalarMin(data, start, end, 0), SimdReductions.MinInt32(data, start, end, 0));
        Assert.Equal(ScalarMax(data, start, end, 0), SimdReductions.MaxInt32(data, start, end, 0));
    }

    [Fact]
    public void MinMaxInt32_AllEqual_ReturnsThatValue()
    {
        var data = new int[200];
        Array.Fill(data, -42);
        Assert.Equal(-42, SimdReductions.MinInt32(data, 0, data.Length, int.MaxValue));
        Assert.Equal(-42, SimdReductions.MaxInt32(data, 0, data.Length, int.MinValue));
    }

    [Fact]
    public void MinMaxInt32_EmptyRange_ReturnsSeed()
    {
        var data = Mixed();
        Assert.Equal(99, SimdReductions.MinInt32(data, 5, 5, 99));   // empty
        Assert.Equal(99, SimdReductions.MaxInt32(data, 5, 5, 99));
        Assert.Equal(99, SimdReductions.MinInt32(data, 10, 3, 99));  // negative range
        Assert.Equal(99, SimdReductions.MaxInt32(data, 10, 3, 99));
    }

    // ---- P-minmax(c): the FUSED single-pass MinMaxInt32 helper ------------------------------------------

    [Theory]
    [InlineData(int.MinValue, int.MaxValue)] // wide seeds (don't bias the result)
    [InlineData(0, 0)]                       // both seeds 0
    [InlineData(7, 7)]                       // interior seed (the min-max-delta a[0] case)
    [InlineData(int.MaxValue, int.MinValue)] // identity seeds (min starts high, max starts low)
    public void FusedMinMaxInt32_SimdPath_MatchesSeparateAndScalar(int seedMin, int seedMax)
    {
        var data = Mixed();
        var (fmin, fmax) = SimdReductions.MinMaxInt32(data, 0, data.Length, seedMin, seedMax);
        // Fused == the two separate helpers == the scalar fold.
        Assert.Equal(SimdReductions.MinInt32(data, 0, data.Length, seedMin), fmin);
        Assert.Equal(SimdReductions.MaxInt32(data, 0, data.Length, seedMax), fmax);
        Assert.Equal(ScalarMin(data, 0, data.Length, seedMin), fmin);
        Assert.Equal(ScalarMax(data, 0, data.Length, seedMax), fmax);
    }

    [Theory]
    [InlineData(0, 200)]
    [InlineData(1, 200)]   // the min-max-delta shape: non-zero start + SIMD tail
    [InlineData(3, 197)]
    [InlineData(50, 150)]
    public void FusedMinMaxInt32_PartialRange_MatchesScalar(int start, int end)
    {
        var data = Mixed();
        var (fmin, fmax) = SimdReductions.MinMaxInt32(data, start, end, data[start], data[start]);
        Assert.Equal(ScalarMin(data, start, end, data[start]), fmin);
        Assert.Equal(ScalarMax(data, start, end, data[start]), fmax);
    }

    [Fact]
    public void FusedMinMaxInt32_EmptyAndNegativeRange_ReturnsSeeds()
    {
        var data = Mixed();
        Assert.Equal((11, 22), SimdReductions.MinMaxInt32(data, 5, 5, 11, 22));   // empty
        Assert.Equal((11, 22), SimdReductions.MinMaxInt32(data, 10, 3, 11, 22));  // negative range
    }

    [Fact]
    public void FusedMinMaxInt32_AllEqual_ReturnsThatValue()
    {
        var data = new int[200];
        Array.Fill(data, -42);
        Assert.Equal((-42, -42), SimdReductions.MinMaxInt32(data, 0, data.Length, int.MaxValue, int.MinValue));
    }
}

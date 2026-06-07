using System;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// RUST-PERF P1(b): the counted-reduction auto-vectorization codegen. When enabled, the compiler lowers
/// <c>while i &lt; n { acc = acc + a[i]; i = i + 1 }</c> on an <c>int[]</c> to a call to
/// <c>NSharpLang.Runtime.SimdReductions.SumInt32</c> (the unrolled Vector&lt;int&gt; reduction). These tests
/// pin (a) value-IDENTITY with the scalar loop across many lengths — including 0 and lengths not a multiple
/// of the SIMD width, exercising the scalar tail — and (b) that the optimization actually fires (the scalar
/// element-load loop is replaced by a call). The flag is off by default and thread-local, so it cannot affect
/// any other test or production.
/// </summary>
[Trait("Category", "Simd")]
public class VectorizedReductionTests
{
    private const string SumSource = @"
func sum(a: int[], n: int): int {
    acc := 0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";

    private static readonly MethodInfo s_setFlag =
        typeof(Compiler.ILCompiler.ILCompiler).GetMethod(
            "SetReductionVectorizationForCurrentThread", BindingFlags.Static | BindingFlags.NonPublic)!;

    private static void Vectorize(bool? enabled) => s_setFlag.Invoke(null, new object?[] { enabled });

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(3)]
    [InlineData(7)]
    [InlineData(8)]
    [InlineData(15)]
    [InlineData(16)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedSum_IsValueIdenticalToScalar(int n)
    {
        var data = new int[n];
        var expected = 0;
        for (var k = 0; k < n; k++)
        {
            data[k] = k * 3 - 7; // deterministic, includes negatives to exercise wrapping
            expected += data[k];
        }

        Vectorize(true);
        try
        {
            var actual = ILShapeInspector.Compile(SumSource, asm =>
                (int)ILShapeInspector.GetProgramMethod(asm, "sum").Invoke(null, new object[] { data, n })!);
            Assert.Equal(expected, actual);
        }
        finally
        {
            Vectorize(null);
        }
    }

    // Pins the post-loop index value: the lowering must leave the index at the scalar loop's exact terminal
    // value (max(start, bound)), including when the loop never runs (bound <= 0), not unconditionally = bound.
    private const string LastIndexSource = @"
func lastIndex(a: int[], n: int): int {
    acc := 0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return i
}";

    [Theory]
    [InlineData(-3)]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(17)]
    public void VectorizedReduction_LeavesIndexAtScalarTerminalValue(int n)
    {
        var data = new int[n < 0 ? 0 : n];
        for (var k = 0; k < data.Length; k++) data[k] = k;
        var expected = n > 0 ? n : 0; // scalar: i ends at max(0, n)

        Vectorize(true);
        try
        {
            var actual = ILShapeInspector.Compile(LastIndexSource, asm =>
                (int)ILShapeInspector.GetProgramMethod(asm, "lastIndex").Invoke(null, new object[] { data, n })!);
            Assert.Equal(expected, actual);
        }
        finally
        {
            Vectorize(null);
        }
    }

    // The array.Length bound path (pure ldlen): must vectorize AND stay value-identical (37 = non-multiple of
    // the SIMD width, exercising the scalar tail).
    [Fact]
    public void VectorizedSum_ArrayLengthBound_VectorizesAndMatchesScalar()
    {
        const string src = @"
func sumAll(a: int[]): int {
    acc := 0
    i := 0
    while i < a.Length {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";
        var data = new int[37];
        var expected = 0;
        for (var k = 0; k < data.Length; k++)
        {
            data[k] = k * 7 - 3;
            expected += data[k];
        }

        Vectorize(true);
        try
        {
            var result = ILShapeInspector.Compile(src, asm =>
            {
                var method = ILShapeInspector.GetProgramMethod(asm, "sumAll");
                var value = (int)method.Invoke(null, new object[] { data })!;
                var ldelem = ILShapeInspector.CountOpcode(method, OpCodes.Ldelem_I4);
                return (value, ldelem);
            });
            Assert.Equal(expected, result.value);
            Assert.Equal(0, result.ldelem); // vectorized: the scalar element-load loop is gone
        }
        finally
        {
            Vectorize(null);
        }
    }

    [Fact]
    public void Vectorization_ReplacesScalarLoopWithCall_OnlyWhenEnabled()
    {
        (int Ldelem, int Call) Shape(bool? flag)
        {
            Vectorize(flag);
            try
            {
                return ILShapeInspector.Compile(SumSource, asm =>
                {
                    var method = ILShapeInspector.GetProgramMethod(asm, "sum");
                    return (ILShapeInspector.CountOpcode(method, OpCodes.Ldelem_I4),
                            ILShapeInspector.CountOpcode(method, OpCodes.Call));
                });
            }
            finally
            {
                Vectorize(null);
            }
        }

        var off = Shape(false);
        Assert.True(off.Ldelem >= 1, "scalar loop must load array elements (ldelem.i4)");

        var on = Shape(true);
        Assert.Equal(0, on.Ldelem); // the scalar element-load loop is gone, folded into the helper
        Assert.True(on.Call >= 1, "the reduction must be lowered to a SIMD helper call");
    }

    // ---- RUST-PERF P1(d): widen the vectorized reduction to long / uint / ulong --------------------------
    // Integer wrapping add is associative (mod 2^32 for int/uint, mod 2^64 for long/ulong), so the unrolled
    // SIMD reduction is value-identical to the scalar loop for every length. float/double must NOT vectorize
    // (FP addition is not associative). Each integer type asserts: (1) vectorized result == scalar result
    // (the absolute correctness bar), and (2) the reduction actually lowered to a helper Call (so it is not
    // silently falling back). The sum functions contain no other calls, so a Call count of 0 (scalar) vs
    // >=1 (vectorized) is a robust, type-agnostic "the optimization fired" signal.

    private const string SumLongSrc = @"
func sumL(a: long[], n: int): long {
    acc: long = (long)0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";

    private const string SumUIntSrc = @"
func sumU(a: uint[], n: int): uint {
    acc: uint = (uint)0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";

    private const string SumULongSrc = @"
func sumUL(a: ulong[], n: int): ulong {
    acc: ulong = (ulong)0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";

    private const string SumFloatSrc = @"
func sumF(a: float[], n: int): float {
    acc: float = (float)0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";

    private const string SumDoubleSrc = @"
func sumD(a: double[], n: int): double {
    acc: double = (double)0
    i := 0
    while i < n {
        acc = acc + a[i]
        i = i + 1
    }
    return acc
}";

    private static object RunReduction(string src, string fn, bool? flag, object[] args)
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

    private static int CallCount(string src, string fn, bool? flag)
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

    [Fact]
    public void SuffixedLongLiteralBound_FallsBackToScalar_NoInvalidIl()
    {
        // H2: a suffixed long literal bound (100L) must NOT be vectorized — emitting int64 into the
        // int32 bound temp is unverifiable IL. With vectorization on, the emitter declines and
        // falls back to the scalar loop, producing the same value (and not throwing
        // InvalidProgramException). The data is 1..128, so the [0,100) sum is 5050.
        const string src = @"
func sumTo(a: int[]): int {
    sum := 0
    i := 0
    while i < 100L {
        sum = sum + a[i]
        i = i + 1
    }
    return sum
}";
        var data = new int[128];
        for (var k = 0; k < data.Length; k++)
            data[k] = k + 1;

        Assert.Equal(
            RunReduction(src, "sumTo", false, new object[] { data }),
            RunReduction(src, "sumTo", true, new object[] { data }));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(7)]
    [InlineData(8)]
    [InlineData(9)]
    [InlineData(16)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedSumLong_IsValueIdenticalToScalar(int n)
    {
        var data = new long[n];
        for (var k = 0; k < n; k++)
            data[k] = (long)k * 1_000_000_007L - 7; // large 64-bit magnitudes

        Assert.Equal(
            RunReduction(SumLongSrc, "sumL", false, new object[] { data, n }),
            RunReduction(SumLongSrc, "sumL", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(3)]
    [InlineData(8)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedSumUInt_IsValueIdenticalToScalar_IncludingWraparound(int n)
    {
        var data = new uint[n];
        for (var k = 0; k < n; k++)
            data[k] = unchecked((uint)(k * 2_000_000_011)); // deliberately overflows uint → exercises mod-2^32 wrap

        Assert.Equal(
            RunReduction(SumUIntSrc, "sumU", false, new object[] { data, n }),
            RunReduction(SumUIntSrc, "sumU", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(3)]
    [InlineData(8)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedSumULong_IsValueIdenticalToScalar_IncludingWraparound(int n)
    {
        var data = new ulong[n];
        for (var k = 0; k < n; k++)
            data[k] = unchecked((ulong)k * 2_000_000_000_000_000_000UL); // sums past 2^64 → exercises mod-2^64 wrap

        Assert.Equal(
            RunReduction(SumULongSrc, "sumUL", false, new object[] { data, n }),
            RunReduction(SumULongSrc, "sumUL", true, new object[] { data, n }));
    }

    [Theory]
    [InlineData(SumLongSrc, "sumL")]
    [InlineData(SumUIntSrc, "sumU")]
    [InlineData(SumULongSrc, "sumUL")]
    public void IntegerReduction_LowersToHelperCall_OnlyWhenEnabled(string src, string fn)
    {
        Assert.Equal(0, CallCount(src, fn, false));     // scalar loop: no calls in the body
        Assert.True(CallCount(src, fn, true) >= 1, "the reduction must lower to a SIMD helper call when enabled");
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void FloatReduction_NeverVectorizes(bool flag)
    {
        // No float SIMD helper exists (FP add is not associative), so the body must stay a scalar element-load
        // loop (ldelem.r4) with no helper call, regardless of the flag — and stay numerically correct.
        var n = 64;
        var data = new float[n];
        var expected = 0f;
        for (var k = 0; k < n; k++) { data[k] = k * 0.5f - 1f; expected += data[k]; }

        Vectorize(flag);
        try
        {
            var result = ILShapeInspector.Compile(SumFloatSrc, asm =>
            {
                var m = ILShapeInspector.GetProgramMethod(asm, "sumF");
                var value = (float)m.Invoke(null, new object[] { data, n })!;
                return (value, ldelem: ILShapeInspector.CountOpcode(m, OpCodes.Ldelem_R4), call: ILShapeInspector.CountCall(m));
            });
            Assert.Equal(expected, result.value, 3);
            Assert.True(result.ldelem >= 1, "float reduction must keep the scalar element-load loop");
            Assert.Equal(0, result.call); // never lowered to a SIMD helper
        }
        finally
        {
            Vectorize(null);
        }
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void DoubleReduction_NeverVectorizes(bool flag)
    {
        var n = 64;
        var data = new double[n];
        var expected = 0d;
        for (var k = 0; k < n; k++) { data[k] = k * 0.25 - 2; expected += data[k]; }

        Vectorize(flag);
        try
        {
            var result = ILShapeInspector.Compile(SumDoubleSrc, asm =>
            {
                var m = ILShapeInspector.GetProgramMethod(asm, "sumD");
                var value = (double)m.Invoke(null, new object[] { data, n })!;
                return (value, ldelem: ILShapeInspector.CountOpcode(m, OpCodes.Ldelem_R8), call: ILShapeInspector.CountCall(m));
            });
            Assert.Equal(expected, result.value, 6);
            Assert.True(result.ldelem >= 1, "double reduction must keep the scalar element-load loop");
            Assert.Equal(0, result.call);
        }
        finally
        {
            Vectorize(null);
        }
    }

    // ---- Degenerate / out-of-bounds bound parity (regression for the adversarial-review findings) ----------
    // The bound `n` is a runtime parameter, so the helper — not the emitter — must match scalar semantics for
    // EVERY n, including extreme-negative (which would overflow `end - step` in the helper) and out-of-range
    // (which must throw IndexOutOfRangeException, NOT the Vector ctor's ArgumentOutOfRangeException).

    [Theory]
    [InlineData(int.MinValue)]      // end - step overflows to a large positive if unguarded
    [InlineData(int.MinValue + 1)]
    [InlineData(int.MinValue + 8)]
    [InlineData(-1)]
    [InlineData(-100)]
    [InlineData(0)]
    public void VectorizedSum_ExtremeOrEmptyBound_MatchesScalar_NoOutOfBoundsRead(int n)
    {
        var data = new int[100];
        for (var k = 0; k < data.Length; k++) data[k] = k + 1;

        // scalar `while i < n` with i = 0 and n <= 0 never runs → 0; the vectorized helper must also return 0
        // (no out-of-bounds SIMD read), not throw and not sum phantom elements.
        var scalar = (int)RunReduction(SumSource, "sum", false, new object[] { data, n });
        var vector = (int)RunReduction(SumSource, "sum", true, new object[] { data, n });
        Assert.Equal(0, scalar);
        Assert.Equal(scalar, vector);
    }

    [Theory]
    [InlineData(SumSource, "sum", typeof(int))]
    [InlineData(SumLongSrc, "sumL", typeof(long))]
    [InlineData(SumUIntSrc, "sumU", typeof(uint))]
    [InlineData(SumULongSrc, "sumUL", typeof(ulong))]
    public void VectorizedReduction_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar(string src, string fn, Type elementType)
    {
        // Array of 10, bound of 100 → the scalar loop reads array[10] and throws IndexOutOfRangeException.
        // The vectorized path must throw the SAME exception type (it would be ArgumentOutOfRangeException if the
        // helper let new Vector<T>(array, i) read past the end).
        var data = Array.CreateInstance(elementType, 10);

        Vectorize(true);
        try
        {
            var ex = Assert.Throws<TargetInvocationException>(() =>
                ILShapeInspector.Compile(src, asm =>
                    ILShapeInspector.GetProgramMethod(asm, fn).Invoke(null, new object[] { data, 100 })));
            Assert.IsType<IndexOutOfRangeException>(ex.InnerException);
        }
        finally
        {
            Vectorize(null);
        }
    }

    // ---- RUST-PERF P1(f): the SAME vectorization fires on the `for`-form (what the benchmarks + idiomatic N#
    // actually use). Before P1(f), `for i := 0; i < n; i++ { acc += a[i] }` compiled scalar (0 helper calls)
    // while only the while-form vectorized — so the measured win never reached the benchmark. -----------------

    private const string ForSumSource = @"
func sumFor(a: int[], n: int): int {
    acc := 0
    for i := 0; i < n; i++ {
        acc = acc + a[i]
    }
    return acc
}";

    private const string ForSumLongSrc = @"
func sumForL(a: long[], n: int): long {
    acc: long = (long)0
    for i := 0; i < n; i++ {
        acc = acc + a[i]
    }
    return acc
}";

    private const string ForSumUIntSrc = @"
func sumForU(a: uint[], n: int): uint {
    acc: uint = (uint)0
    for i := 0; i < n; i++ {
        acc = acc + a[i]
    }
    return acc
}";

    private const string ForSumULongSrc = @"
func sumForUL(a: ulong[], n: int): ulong {
    acc: ulong = (ulong)0
    for i := 0; i < n; i++ {
        acc = acc + a[i]
    }
    return acc
}";

    private const string ForSumFromSrc = @"
func sumFrom(a: int[], start: int, n: int): int {
    acc := 0
    for i := start; i < n; i++ {
        acc = acc + a[i]
    }
    return acc
}";

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(7)]
    [InlineData(8)]
    [InlineData(15)]
    [InlineData(16)]
    [InlineData(17)]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedForSum_IsValueIdenticalToScalar(int n)
    {
        var data = new int[n];
        for (var k = 0; k < n; k++) data[k] = k * 3 - 7;

        Assert.Equal(
            RunReduction(ForSumSource, "sumFor", false, new object[] { data, n }),
            RunReduction(ForSumSource, "sumFor", true, new object[] { data, n }));
    }

    [Fact]
    public void ForFormReduction_NowVectorizes_WhenEnabled()
    {
        // The regression that motivated P1(f): the for-form must lower to a helper call when enabled (it did
        // not before — only the while-form vectorized), and stay scalar (no call) when disabled.
        Assert.Equal(0, CallCount(ForSumSource, "sumFor", false));
        Assert.True(CallCount(ForSumSource, "sumFor", true) >= 1, "for-form reduction must vectorize when enabled");
    }

    [Theory]
    [InlineData(ForSumLongSrc, "sumForL")]
    [InlineData(ForSumUIntSrc, "sumForU")]
    [InlineData(ForSumULongSrc, "sumForUL")]
    public void ForFormReduction_WidenedTypes_LowerToHelperCall(string src, string fn)
    {
        Assert.Equal(0, CallCount(src, fn, false));
        Assert.True(CallCount(src, fn, true) >= 1, "widened for-form reduction must vectorize when enabled");
    }

    [Theory]
    [InlineData(64)]
    [InlineData(1000)]
    public void VectorizedForSum_WidenedTypes_AreValueIdenticalToScalar(int n)
    {
        var longData = new long[n];
        var uintData = new uint[n];
        var ulongData = new ulong[n];
        for (var k = 0; k < n; k++)
        {
            longData[k] = (long)k * 1_000_000_007L - 7;
            uintData[k] = unchecked((uint)(k * 2_000_000_011));            // overflow → mod-2^32 wrap
            ulongData[k] = unchecked((ulong)k * 2_000_000_000_000_000_000UL); // → mod-2^64 wrap
        }

        Assert.Equal(
            RunReduction(ForSumLongSrc, "sumForL", false, new object[] { longData, n }),
            RunReduction(ForSumLongSrc, "sumForL", true, new object[] { longData, n }));
        Assert.Equal(
            RunReduction(ForSumUIntSrc, "sumForU", false, new object[] { uintData, n }),
            RunReduction(ForSumUIntSrc, "sumForU", true, new object[] { uintData, n }));
        Assert.Equal(
            RunReduction(ForSumULongSrc, "sumForUL", false, new object[] { ulongData, n }),
            RunReduction(ForSumULongSrc, "sumForUL", true, new object[] { ulongData, n }));
    }

    [Theory]
    [InlineData(0, 64)]
    [InlineData(3, 64)]   // non-zero start: the helper sums [start, n)
    [InlineData(5, 17)]
    [InlineData(60, 64)]
    [InlineData(64, 64)]  // empty range (start == n)
    [InlineData(70, 64)]  // start > n: empty
    public void VectorizedForSum_NonZeroStart_MatchesScalar(int start, int n)
    {
        var data = new int[64];
        for (var k = 0; k < data.Length; k++) data[k] = k * 5 - 11;

        Assert.Equal(
            RunReduction(ForSumFromSrc, "sumFrom", false, new object[] { data, start, n }),
            RunReduction(ForSumFromSrc, "sumFrom", true, new object[] { data, start, n }));
    }

    [Fact]
    public void VectorizedForSum_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar()
    {
        var data = new int[10];
        Vectorize(true);
        try
        {
            var ex = Assert.Throws<TargetInvocationException>(() =>
                ILShapeInspector.Compile(ForSumSource, asm =>
                    ILShapeInspector.GetProgramMethod(asm, "sumFor").Invoke(null, new object[] { data, 100 })));
            Assert.IsType<IndexOutOfRangeException>(ex.InnerException);
        }
        finally
        {
            Vectorize(null);
        }
    }

    // Pins the for-form terminal index explicitly (the emitter's `index = max(index, bound)` must equal the
    // scalar for-loop's exit value max(start, n)). `i` is declared before the loop so it is readable afterwards.
    private const string ForLastIndexSrc = @"
func lastIndexFor(a: int[], start: int, n: int): int {
    acc := 0
    i := 0
    for i = start; i < n; i++ {
        acc = acc + a[i]
    }
    return i
}";

    [Theory]
    [InlineData(0, 64)]
    [InlineData(3, 64)]
    [InlineData(64, 64)]  // start == n: loop never runs, i stays start
    [InlineData(70, 64)]  // start > n: i stays start
    public void VectorizedForReduction_LeavesIndexAtScalarTerminalValue(int start, int n)
    {
        var data = new int[64];
        for (var k = 0; k < data.Length; k++) data[k] = k;
        var expected = start < n ? n : start; // scalar for-loop exits with i == max(start, n)

        var scalar = (int)RunReduction(ForLastIndexSrc, "lastIndexFor", false, new object[] { data, start, n });
        var vector = (int)RunReduction(ForLastIndexSrc, "lastIndexFor", true, new object[] { data, start, n });
        Assert.Equal(expected, scalar);
        Assert.Equal(scalar, vector);
    }

    [Fact]
    public void VectorizedForSum_BracelessBody_VectorizesAndMatchesScalar()
    {
        // A braceless single-statement for body (pins TryGetSingleBodyStatement's ExpressionStatement arm).
        const string src = "func sumBare(a: int[], n: int): int {\n    acc := 0\n    for i := 0; i < n; i++ acc = acc + a[i]\n    return acc\n}";
        var data = new int[37];
        for (var k = 0; k < data.Length; k++) data[k] = k * 7 - 3;

        Assert.Equal(
            RunReduction(src, "sumBare", false, new object[] { data, data.Length }),
            RunReduction(src, "sumBare", true, new object[] { data, data.Length }));
    }
}

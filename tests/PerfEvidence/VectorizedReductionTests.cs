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
}

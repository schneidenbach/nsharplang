using System;
using System.Linq;
using System.Numerics;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression coverage for N#'s explicit SIMD support (System.Numerics vector types).
///
/// Unit 13 ("SIMD / auto-vectorization recognition") has two parts. Part (1) — recognizing
/// <see cref="Vector{T}"/> / <see cref="Vector2"/> / <see cref="Vector3"/> / <see cref="Vector4"/>
/// arithmetic and emitting direct, verifiable, allocation-free intrinsic IL — is satisfied today
/// by the compiler's operator-overload resolution: <c>a + b</c> on a vector type resolves the
/// runtime's static <c>op_Addition</c>/<c>op_Multiply</c>/... method and emits a direct
/// <c>call</c> with the value types kept on the evaluation stack (no boxing). These tests pin that
/// shape so it cannot silently regress into generic dispatch or boxing.
///
/// Part (2) — compiler-driven auto-vectorization of scalar element-wise loops into strided
/// <see cref="Vector{T}"/> loops — is intentionally deferred. See
/// <c>docs/design/performance-compiler-refactor.md</c> (SIMD section) for the rationale and the
/// acceptance criteria for reopening it.
///
/// The <c>Simd</c> trait lets CI run these in isolation (including the amd64 SIMD-codegen lane),
/// matching the E2E recipe's <c>--filter Simd</c>.
/// </summary>
[Trait("Category", "Simd")]
public class SimdVectorShapeTests
{
    // ==================== IL-shape: no boxing, direct intrinsic calls ====================

    [Fact]
    public void VectorGeneric_Addition_EmitsDirectOperatorCall_NoBoxing()
    {
        const string source = @"
import System.Numerics

func vadd(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a + b
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "vadd");

            // Value-type vector arithmetic must stay on the stack: no box, no newobj, no virtual dispatch.
            ILShapeInspector.AssertNoBoxing(method);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 0);

            // Exactly one direct call: Vector<int>.op_Addition.
            AssertSingleDirectCallTo(method, "op_Addition", typeof(Vector<int>));
            return 0;
        });
    }

    [Fact]
    public void VectorGeneric_OperatorChain_EmitsDirectCalls_NoBoxing()
    {
        const string source = @"
import System.Numerics

func vop(a: Vector<int>, b: Vector<int>, c: Vector<int>): Vector<int> {
    return a * b - c
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "vop");

            ILShapeInspector.AssertNoBoxing(method);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 0);

            // Two direct intrinsic calls: op_Multiply then op_Subtraction, both on Vector<int>.
            var callNames = ResolveDirectCallNames(method);
            Assert.Equal(new[] { "op_Multiply", "op_Subtraction" }, callNames);
            return 0;
        });
    }

    [Fact]
    public void VectorGeneric_Float_Addition_EmitsDirectOperatorCall_NoBoxing()
    {
        // Float vectors are still legal as *explicit* SIMD: the programmer asked for vector adds,
        // so there is no float-reassociation hazard (we are not silently reordering scalar adds).
        const string source = @"
import System.Numerics

func vadd(a: Vector<float>, b: Vector<float>): Vector<float> {
    return a + b
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "vadd");

            ILShapeInspector.AssertNoBoxing(method);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            AssertSingleDirectCallTo(method, "op_Addition", typeof(Vector<float>));
            return 0;
        });
    }

    [Theory]
    [InlineData("Vector2", "+", "op_Addition")]
    [InlineData("Vector3", "+", "op_Addition")]
    [InlineData("Vector4", "*", "op_Multiply")]
    public void FixedSizeVectors_EmitDirectOperatorCall_NoBoxing(string typeName, string op, string expectedOperator)
    {
        var source = $@"
import System.Numerics

func vop(a: {typeName}, b: {typeName}): {typeName} {{
    return a {op} b
}}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "vop");

            ILShapeInspector.AssertNoBoxing(method);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 0);

            var callNames = ResolveDirectCallNames(method);
            Assert.Equal(new[] { expectedOperator }, callNames);
            return 0;
        });
    }

    [Fact]
    public void VectorGeneric_CtorFromArray_EmitsNewobj_NoBoxing()
    {
        // Loading a Vector<int> lane from an array uses the public ctor directly (verifiable),
        // with the value type left on the stack — no boxing.
        const string source = @"
import System.Numerics

func load(a: int[]): Vector<int> {
    return new Vector<int>(a)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "load");

            ILShapeInspector.AssertNoBoxing(method);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 1);
            return 0;
        });
    }

    // ==================== Behavioral: results match scalar / C# equivalent ====================

    [Fact]
    public void VectorGeneric_Addition_IsBitIdenticalToScalar()
    {
        // c = a + b across a full Vector<int> width, written out via CopyTo, must be bit-identical
        // to a per-element scalar add. This proves the explicit SIMD lowering is numerically exact.
        const string source = @"
import System.Numerics

func vaddCopy(a: int[], b: int[], outArr: int[]) {
    va := new Vector<int>(a)
    vb := new Vector<int>(b)
    vc := va + vb
    vc.CopyTo(outArr)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "vaddCopy");

            var width = Vector<int>.Count;
            var a = Enumerable.Range(0, width).Select(i => i * 7 - 3).ToArray();
            var b = Enumerable.Range(0, width).Select(i => (i % 2 == 0 ? 1 : -1) * (i + 11)).ToArray();
            var actual = new int[width];

            method.Invoke(null, new object[] { a, b, actual });

            var expected = new int[width];
            for (int i = 0; i < width; i++)
            {
                // unchecked: vector int add wraps, identical to N#'s scalar `add` opcode.
                expected[i] = unchecked(a[i] + b[i]);
            }

            Assert.Equal(expected, actual);
            return 0;
        });
    }

    [Fact]
    public void VectorGeneric_Multiply_WrapsIdenticallyToScalar()
    {
        const string source = @"
import System.Numerics

func vmulCopy(a: int[], b: int[], outArr: int[]) {
    va := new Vector<int>(a)
    vb := new Vector<int>(b)
    vc := va * vb
    vc.CopyTo(outArr)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "vmulCopy");

            var width = Vector<int>.Count;
            // Deliberately include large magnitudes so the multiply overflows and must wrap.
            var a = Enumerable.Range(0, width).Select(i => 100_000 + i * 13).ToArray();
            var b = Enumerable.Range(0, width).Select(i => 90_000 - i * 17).ToArray();
            var actual = new int[width];

            method.Invoke(null, new object[] { a, b, actual });

            var expected = new int[width];
            for (int i = 0; i < width; i++)
            {
                expected[i] = unchecked(a[i] * b[i]);
            }

            Assert.Equal(expected, actual);
            return 0;
        });
    }

    [Fact]
    public void Vector3_Addition_MatchesRuntimeSemantics()
    {
        // Build two Vector3s, add them, and read each component back. Compares against the
        // BCL's own Vector3 addition to prove component semantics are preserved.
        const string source = @"
import System.Numerics

func vaddX(a: Vector3, b: Vector3): float {
    c := a + b
    return c.X
}

func vaddY(a: Vector3, b: Vector3): float {
    c := a + b
    return c.Y
}

func vaddZ(a: Vector3, b: Vector3): float {
    c := a + b
    return c.Z
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var a = new Vector3(1.5f, -2.25f, 3.0f);
            var b = new Vector3(0.5f, 4.0f, -1.0f);
            var expected = a + b;

            var x = (float)ILShapeInspector.GetProgramMethod(assembly, "vaddX").Invoke(null, new object[] { a, b })!;
            var y = (float)ILShapeInspector.GetProgramMethod(assembly, "vaddY").Invoke(null, new object[] { a, b })!;
            var z = (float)ILShapeInspector.GetProgramMethod(assembly, "vaddZ").Invoke(null, new object[] { a, b })!;

            Assert.Equal(expected.X, x);
            Assert.Equal(expected.Y, y);
            Assert.Equal(expected.Z, z);
            return 0;
        });
    }

    // ==================== Fallback: ordinary scalar loops stay scalar ====================

    [Fact]
    public void ScalarElementWiseLoop_StaysScalar_NoVectorTypesEmitted()
    {
        // Deferred-feature guard: the compiler must NOT auto-vectorize a plain scalar element-wise
        // loop. It should emit the straightforward scalar lowering (ldelem/add/stelem), with no
        // System.Numerics vector calls and no boxing. This pins the conservative fallback.
        const string source = @"
func addArrays(a: int[], b: int[], c: int[], n: int) {
    i: int = 0
    while i < n {
        c[i] = a[i] + b[i]
        i = i + 1
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "addArrays");

            ILShapeInspector.AssertNoBoxing(method);

            // Scalar lowering: an integer add via ldelem.i4 / stelem.i4, no vector intrinsics.
            Assert.True(ILShapeInspector.CountOpcode(method, OpCodes.Ldelem_I4) >= 2,
                "Expected scalar ldelem.i4 loads in the fallback loop.");
            Assert.True(ILShapeInspector.CountOpcode(method, OpCodes.Stelem_I4) >= 1,
                "Expected a scalar stelem.i4 store in the fallback loop.");

            Assert.Empty(ResolveDirectCallTargets(method)
                .Where(m => m.DeclaringType?.Namespace == "System.Numerics"));
            return 0;
        });
    }

    [Fact]
    public void ScalarElementWiseLoop_ProducesCorrectResults()
    {
        const string source = @"
func addArrays(a: int[], b: int[], c: int[], n: int) {
    i: int = 0
    while i < n {
        c[i] = a[i] + b[i]
        i = i + 1
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "addArrays");

            // Use an odd length that would straddle a vector boundary, to make sure the scalar
            // path covers every element (no missing remainder).
            const int n = 37;
            var a = Enumerable.Range(0, n).Select(i => i * 3 - 5).ToArray();
            var b = Enumerable.Range(0, n).Select(i => i * -2 + 9).ToArray();
            var c = new int[n];

            method.Invoke(null, new object[] { a, b, c, n });

            var expected = new int[n];
            for (int i = 0; i < n; i++)
            {
                expected[i] = unchecked(a[i] + b[i]);
            }

            Assert.Equal(expected, c);
            return 0;
        });
    }

    // ==================== helpers ====================

    private static void AssertSingleDirectCallTo(MethodInfo method, string expectedMethodName, Type expectedDeclaringTypeDefinition)
    {
        var targets = ResolveDirectCallTargets(method);
        Assert.Single(targets);
        var target = targets[0];
        Assert.Equal(expectedMethodName, target.Name);

        var declaring = target.DeclaringType;
        Assert.NotNull(declaring);
        var declaringDefinition = declaring!.IsGenericType ? declaring.GetGenericTypeDefinition() : declaring;
        var expectedDefinition = expectedDeclaringTypeDefinition.IsGenericType
            ? expectedDeclaringTypeDefinition.GetGenericTypeDefinition()
            : expectedDeclaringTypeDefinition;
        Assert.Equal(expectedDefinition, declaringDefinition);
    }

    private static string[] ResolveDirectCallNames(MethodInfo method) =>
        ResolveDirectCallTargets(method).Select(m => m.Name).ToArray();

    private static MethodBase[] ResolveDirectCallTargets(MethodInfo method)
    {
        var module = method.Module;
        var typeArgs = method.DeclaringType?.GetGenericArguments() ?? Type.EmptyTypes;
        var methodArgs = method.IsGenericMethod ? method.GetGenericArguments() : Type.EmptyTypes;

        var targets = new System.Collections.Generic.List<MethodBase>();
        foreach (var instruction in ILShapeInspector.Decode(method))
        {
            if (instruction.OpCode != OpCodes.Call || instruction.MetadataToken is not { } token)
            {
                continue;
            }

            try
            {
                if (module.ResolveMethod(token, typeArgs, methodArgs) is { } resolved)
                {
                    targets.Add(resolved);
                }
            }
            catch (ArgumentException)
            {
                // Unresolvable token; ignore for shape assertions.
            }
        }

        return targets.ToArray();
    }
}

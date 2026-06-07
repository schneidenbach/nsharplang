using System;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    // RUST-PERF P1(b)/(e): auto-vectorize counted reductions. ON by default (P1(e), once the lowering was
    // proven value-identical to the scalar loop and adversarially reviewed); set NSHARP_VECTORIZE_REDUCTIONS=0
    // to opt out. A thread-local override exists for tests (it keeps the per-test choice safe under xUnit's
    // parallel collections — setting it on one test's thread never leaks into another's compile).
    [ThreadStatic] private static bool t_vectorizeReductions;
    [ThreadStatic] private static bool t_vectorizeReductionsSet;

    private static readonly bool s_vectorizeReductionsDefault =
        Environment.GetEnvironmentVariable("NSHARP_VECTORIZE_REDUCTIONS") != "0";

    internal static bool ReductionVectorizationEnabled =>
        t_vectorizeReductionsSet ? t_vectorizeReductions : s_vectorizeReductionsDefault;

    /// <summary>Override the reduction-vectorization flag for the current thread (null = clear the override).</summary>
    internal static void SetReductionVectorizationForCurrentThread(bool? enabled)
    {
        if (enabled is null)
        {
            t_vectorizeReductionsSet = false;
            return;
        }

        t_vectorizeReductions = enabled.Value;
        t_vectorizeReductionsSet = true;
    }

    private static MethodInfo ResolveReductionHelper(string name) =>
        typeof(Runtime.SimdReductions).GetMethod(name)
        ?? throw new InvalidOperationException($"NSharpLang.Runtime.SimdReductions.{name} not found.");

    private static readonly MethodInfo s_sumInt32Reduction = ResolveReductionHelper(nameof(Runtime.SimdReductions.SumInt32));
    private static readonly MethodInfo s_sumInt64Reduction = ResolveReductionHelper(nameof(Runtime.SimdReductions.SumInt64));
    private static readonly MethodInfo s_sumUInt32Reduction = ResolveReductionHelper(nameof(Runtime.SimdReductions.SumUInt32));
    private static readonly MethodInfo s_sumUInt64Reduction = ResolveReductionHelper(nameof(Runtime.SimdReductions.SumUInt64));

    // P1(d): maps a vectorizable array element type to its unrolled SIMD reduction helper. INTEGER ONLY —
    // int/long/uint/ulong wrapping add is associative (mod 2^32 / 2^64), so reordering across SIMD lanes and
    // accumulators is value-preserving. float/double are intentionally absent: FP addition is NOT associative
    // (reassociation changes the result), so float/double reductions fall through to the scalar loop.
    private static MethodInfo? ReductionHelperForElementType(Type elementType)
    {
        if (elementType == typeof(int)) return s_sumInt32Reduction;
        if (elementType == typeof(long)) return s_sumInt64Reduction;
        if (elementType == typeof(uint)) return s_sumUInt32Reduction;
        if (elementType == typeof(ulong)) return s_sumUInt64Reduction;
        return null;
    }

    /// <summary>
    /// If <paramref name="loop"/> is an integer-array counted reduction (ReductionLoopShape), lower it to a SIMD
    /// helper call and return true; otherwise return false (caller emits the normal scalar loop). The loop
    /// <c>while index &lt; bound { acc = acc + array[index]; index = index + 1 }</c> becomes
    /// <c>acc = acc + SimdReductions.Sum…(array, index, bound); index = max(index, bound)</c> — value-identical
    /// (integer wrapping add is associative) and faster (~4.5× for int). Fires only for an <c>int</c>/<c>long</c>/
    /// <c>uint</c>/<c>ulong</c> array+accumulator (P1(d)), an int index, an int side-effect-free bound, and the
    /// default unchecked-arithmetic context (a <c>checked</c> reduction would throw rather than wrap).
    /// </summary>
    private bool TryEmitVectorizedReduction(WhileStatement loop)
    {
        if (_currentIL == null)
            return false;

        var shape = ReductionLoopShape.TryMatch(loop);
        if (shape == null)
            return false;

        // Inside `checked { }` the scalar `acc = acc + a[i]` emits add.ovf (THROWS on overflow); the SIMD helpers
        // wrap (unchecked). Vectorizing a checked reduction would replace a throw with a wrapped value — not
        // value-preserving — so only vectorize in the default unchecked context; otherwise emit the scalar loop.
        if (_overflowCheckingEnabled)
            return false;

        var arrayType = GetIdentifierType(shape.ArrayRef);
        if (!arrayType.IsArray)
            return false;
        var elementType = arrayType.GetElementType()!;
        var reductionMethod = ReductionHelperForElementType(elementType);
        if (reductionMethod == null)
            return false;

        // The accumulator must be exactly the array element type so `acc + helper(...)` is width-correct; the
        // index and bound are int (array indexing is int). A bound that is not provably side-effect-free int is
        // rejected (the vectorized form evaluates it a different number of times than the scalar loop).
        if (GetIdentifierType(shape.AccumulatorRef) != elementType)
            return false;
        if (GetIdentifierType(shape.IndexRef) != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(shape.Bound))
            return false;

        // Evaluate the bound EXACTLY ONCE into a temp. The bound is side-effect-free (int local/param read,
        // int literal, or array.Length = the pure ldlen intrinsic), so evaluating it once here is value-
        // identical to the scalar loop re-evaluating the condition each iteration. (A side-effecting bound,
        // e.g. a custom .Count getter, would observe a different evaluation count and is rejected above.)
        var boundLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpression(shape.Bound);
        _currentIL.Emit(OpCodes.Stloc, boundLocal);

        // acc = acc + SimdReductions.Sum…(array, index, bound) — helper chosen by element type. The IL `add`
        // infers width from the stack operands (int32 for int/uint, int64 for long/ulong) and wraps, matching
        // the unchecked scalar add.
        EmitIdentifier(shape.AccumulatorRef);
        EmitIdentifier(shape.ArrayRef);
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        _currentIL.Emit(OpCodes.Call, reductionMethod);
        _currentIL.Emit(OpCodes.Add);
        StoreIdentifier(shape.AccumulatorRef);

        // index = max(index, bound) -- the scalar loop's exact terminal value, so subsequent reads of the
        // index are correct even when the loop body never ran (bound <= index, e.g. an empty or negative
        // bound), where the scalar loop leaves index unchanged rather than setting it to bound.
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Bge, keepIndexLabel); // signed: if index >= bound, keep index unchanged
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        StoreIdentifier(shape.IndexRef);
        _currentIL.MarkLabel(keepIndexLabel);
        return true;
    }

    // The bound feeds the helper's int `end` parameter and the terminal index store. It must be int AND
    // provably side-effect-free, since the vectorized form evaluates it a different number of times than the
    // scalar loop. Accepted: an int local/parameter read, an int literal, or `.Length` on an ARRAY receiver
    // (the pure `ldlen` intrinsic). `.Count` and `.Length` on non-arrays are rejected (a custom property
    // getter may have side effects), falling back to the scalar loop.
    private bool IsSideEffectFreeInt32Bound(Expression bound) => bound switch
    {
        IdentifierExpression id => GetIdentifierType(id) == typeof(int),
        IntLiteralExpression => true,
        MemberAccessExpression { MemberName: "Length", Object: IdentifierExpression receiver }
            => GetIdentifierType(receiver).IsArray,
        _ => false,
    };
}

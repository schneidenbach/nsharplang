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

    private static readonly MethodInfo s_sumInt32Reduction =
        typeof(Runtime.SimdReductions).GetMethod(nameof(Runtime.SimdReductions.SumInt32))
        ?? throw new InvalidOperationException("NSharpLang.Runtime.SimdReductions.SumInt32 not found.");

    /// <summary>
    /// If <paramref name="loop"/> is an <c>int[]</c> counted reduction (ReductionLoopShape), lower it to a SIMD
    /// helper call and return true; otherwise return false (caller emits the normal scalar loop). The loop
    /// <c>while index &lt; bound { acc = acc + array[index]; index = index + 1 }</c> becomes
    /// <c>acc = acc + SimdReductions.SumInt32(array, index, bound); index = bound</c> — value-identical (int
    /// wrapping add is associative) and ~4.5× faster. Only fires for int accumulator / int[] array / int index
    /// / int bound (the helper is int-specialized; other element types are P1(d)).
    /// </summary>
    private bool TryEmitVectorizedReduction(WhileStatement loop)
    {
        if (_currentIL == null)
            return false;

        var shape = ReductionLoopShape.TryMatch(loop);
        if (shape == null)
            return false;

        if (GetIdentifierType(shape.AccumulatorRef) != typeof(int))
            return false;
        if (GetIdentifierType(shape.ArrayRef) != typeof(int[]))
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

        // acc = acc + SimdReductions.SumInt32(array, index, bound)
        EmitIdentifier(shape.AccumulatorRef);
        EmitIdentifier(shape.ArrayRef);
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        _currentIL.Emit(OpCodes.Call, s_sumInt32Reduction);
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

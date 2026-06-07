using System;
using System.Collections.Generic;
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

    /// <summary>While-form entry (P1(b)): <c>while index &lt; bound { acc = acc + array[index]; index = index + 1 }</c>.
    /// The index is already set by preceding code, so the shared core emits directly. See <see cref="TryEmitMatchedReduction"/>.</summary>
    private bool TryEmitVectorizedReduction(WhileStatement loop)
        => TryEmitMatchedReduction(ReductionLoopShape.TryMatch(loop));

    /// <summary>For-form entry (P1(f)): <c>for index := start; index &lt; bound; index++ { acc = acc + array[index] }</c>.
    /// EmitFor emits the initializer BEFORE calling this, so the index holds its start value here exactly as in the
    /// while-form — the shared core is identical for both. See <see cref="TryEmitMatchedReduction"/>.</summary>
    private bool TryEmitVectorizedReduction(ForStatement loop)
        => TryEmitMatchedReduction(ReductionLoopShape.TryMatch(loop));

    /// <summary>
    /// If <paramref name="shape"/> is a matched integer-array counted reduction, lower it to a SIMD helper call
    /// and return true; otherwise return false (caller emits the normal scalar loop). The reduction becomes
    /// <c>acc = acc + SimdReductions.Sum…(array, index, bound); index = max(index, bound)</c> — value-identical
    /// (integer wrapping add is associative) and faster (~4.5× for int). The terminal <c>index = max(index, bound)</c>
    /// matches BOTH a while-loop and a counted for-loop's exit value. Fires only for an <c>int</c>/<c>long</c>/
    /// <c>uint</c>/<c>ulong</c> array+accumulator (P1(d)), an int index, an int side-effect-free bound, and the
    /// default unchecked-arithmetic context (a <c>checked</c> reduction would throw rather than wrap).
    /// </summary>
    private bool TryEmitMatchedReduction(ReductionLoopShape? shape)
    {
        if (_currentIL == null || shape == null)
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

    // ---- RUST-PERF P2(b): masked-SIMD range-predicate count (the count-ascii kernel) ----------------------

    private static readonly MethodInfo s_countInRangeInt32 =
        ResolveReductionHelper(nameof(Runtime.SimdReductions.CountInRangeInt32));

    /// <summary>While-form entry (P2(b)): <c>while i &lt; bound { [v := a[i];] if a[i] &gt;= lo &amp;&amp; a[i] &lt;= hi { count++ } }</c>.</summary>
    private bool TryEmitVectorizedRangeCount(WhileStatement loop)
        => TryEmitMatchedRangeCount(RangePredicateCountShape.TryMatch(loop));

    /// <summary>For-form entry (P2(b)). EmitFor emits the initializer first, so the index holds its start value
    /// here exactly as in the while-form — the shared core is identical for both.</summary>
    private bool TryEmitVectorizedRangeCount(ForStatement loop)
        => TryEmitMatchedRangeCount(RangePredicateCountShape.TryMatch(loop));

    /// <summary>
    /// If <paramref name="shape"/> is a matched int[] range-predicate count, lower it to a masked SIMD helper
    /// call and return true; otherwise return false (caller emits the scalar loop). The loop becomes
    /// <c>count = count + SimdReductions.CountInRangeInt32(array, index, bound, lo, hi); index = max(index, bound)</c>
    /// — value-identical (counts are order-independent) and faster (packed compare + masked accumulate). Fires
    /// only for an int[] array, int counter/index, int side-effect-free bound and int side-effect-free lo/hi, in
    /// the default unchecked-arithmetic context.
    /// </summary>
    private bool TryEmitMatchedRangeCount(RangePredicateCountShape? shape)
    {
        if (_currentIL == null || shape == null)
            return false;

        // Consistent with the reduction: do not fire in a checked context (currently unreachable — N# `checked`
        // is expression-only and a while/for is a statement). A count cannot overflow (count <= end <= int.Max),
        // so this is a conservative invariant rather than a correctness requirement.
        if (_overflowCheckingEnabled)
            return false;

        if (GetIdentifierType(shape.ArrayRef) != typeof(int[]))
            return false;
        if (GetIdentifierType(shape.CounterRef) != typeof(int))
            return false;
        if (GetIdentifierType(shape.IndexRef) != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(shape.Bound))
            return false;
        // lo/hi feed the helper's int parameters and must match the scalar `int a[i]` comparison exactly, so
        // they must be int and side-effect-free (the vectorized form evaluates them once, not per iteration).
        if (!IsSideEffectFreeInt32Operand(shape.Lo) || !IsSideEffectFreeInt32Operand(shape.Hi))
            return false;

        // Evaluate bound, lo, hi EXACTLY ONCE into temps. All three are side-effect-free, so evaluating once
        // here is value-identical to the scalar loop re-evaluating them each iteration.
        var boundLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpression(shape.Bound);
        _currentIL.Emit(OpCodes.Stloc, boundLocal);
        var loLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpression(shape.Lo);
        _currentIL.Emit(OpCodes.Stloc, loLocal);
        var hiLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpression(shape.Hi);
        _currentIL.Emit(OpCodes.Stloc, hiLocal);

        // count = count + SimdReductions.CountInRangeInt32(array, index, bound, lo, hi)
        EmitIdentifier(shape.CounterRef);
        EmitIdentifier(shape.ArrayRef);
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        _currentIL.Emit(OpCodes.Ldloc, loLocal);
        _currentIL.Emit(OpCodes.Ldloc, hiLocal);
        _currentIL.Emit(OpCodes.Call, s_countInRangeInt32);
        _currentIL.Emit(OpCodes.Add);
        StoreIdentifier(shape.CounterRef);

        // index = max(index, bound) -- the scalar loop's exact terminal index value (matches both while- and
        // counted for-loops), even when the loop body never ran (bound <= index).
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Bge, keepIndexLabel);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        StoreIdentifier(shape.IndexRef);
        _currentIL.MarkLabel(keepIndexLabel);
        return true;
    }

    // A range bound (lo/hi) operand for the count helper: int literal or an int local/parameter read. Unlike the
    // loop bound, `.Length` is not accepted (lo/hi are values, not lengths). `.Count`/custom properties are
    // excluded (possible side effects + non-int).
    private bool IsSideEffectFreeInt32Operand(Expression operand) => operand switch
    {
        IdentifierExpression id => GetIdentifierType(id) == typeof(int),
        IntLiteralExpression => true,
        _ => false,
    };

    // ---- RUST-PERF P-minmax: lane-wise SIMD min/max reduction (the min-max-delta kernel) ------------------

    private static readonly MethodInfo s_minInt32Reduction =
        ResolveReductionHelper(nameof(Runtime.SimdReductions.MinInt32));
    private static readonly MethodInfo s_maxInt32Reduction =
        ResolveReductionHelper(nameof(Runtime.SimdReductions.MaxInt32));

    // P-minmax(c): the FUSED single-pass helper for the canonical [1 min, 1 max] body (min-max-delta). Returns
    // (min, max) so one scan computes both. ValueTuple<int,int>.Item1/Item2 are public fields read via ldfld.
    private static readonly MethodInfo s_minMaxInt32Reduction =
        ResolveReductionHelper(nameof(Runtime.SimdReductions.MinMaxInt32));
    private static readonly FieldInfo s_valueTupleItem1 =
        typeof(ValueTuple<int, int>).GetField("Item1")
        ?? throw new InvalidOperationException("ValueTuple<int,int>.Item1 not found.");
    private static readonly FieldInfo s_valueTupleItem2 =
        typeof(ValueTuple<int, int>).GetField("Item2")
        ?? throw new InvalidOperationException("ValueTuple<int,int>.Item2 not found.");

    // P-ctrans: the adjacent-difference (count-transitions) shifted-compare helper. Returns (count, lastPrevious)
    // via ValueTuple<int,int> — Item1/Item2 read with the same s_valueTupleItem1/Item2 fields above.
    private static readonly MethodInfo s_countTransitionsInt32 =
        ResolveReductionHelper(nameof(Runtime.SimdReductions.CountTransitionsInt32));

    /// <summary>While-form entry (P-minmax): <c>while i &lt; bound { [v := a[i];] if a[i] &lt; min { min = a[i] }
    /// [if a[i] &gt; max { max = a[i] }] }</c>.</summary>
    private bool TryEmitVectorizedMinMaxReduction(WhileStatement loop)
        => TryEmitMatchedMinMaxReduction(MinMaxReductionLoopShape.TryMatch(loop));

    /// <summary>For-form entry (P-minmax). EmitFor emits the initializer first, so the index holds its start
    /// value here exactly as in the while-form — the shared core is identical for both.</summary>
    private bool TryEmitVectorizedMinMaxReduction(ForStatement loop)
        => TryEmitMatchedMinMaxReduction(MinMaxReductionLoopShape.TryMatch(loop));

    /// <summary>
    /// If <paramref name="shape"/> is a matched int[] min/max conditional reduction, lower each reduction to a
    /// lane-wise SIMD helper call and return true; otherwise return false (caller emits the scalar loop). The loop
    /// becomes <c>min = SimdReductions.MinInt32(array, index, bound, min); [max = SimdReductions.MaxInt32(...);]
    /// index = max(index, bound)</c> — value-identical (integer min/max are associative + commutative) and faster
    /// (lane-wise Vector.Min/Vector.Max). Each helper is seeded with the pre-loop accumulator value and scans the
    /// same [index, bound) range. Fires only for an int[] array, int accumulator(s)/index, and an int
    /// side-effect-free bound, in the default unchecked-arithmetic context.
    /// </summary>
    private bool TryEmitMatchedMinMaxReduction(MinMaxReductionLoopShape? shape)
    {
        if (_currentIL == null || shape == null)
            return false;

        // Consistent with the sum reduction / range count: do not fire in a checked context. The matched body has
        // NO arithmetic (only comparisons and assignments), so checked vs unchecked cannot change it — this is a
        // conservative invariant pinning the no-arithmetic shape, not a correctness requirement.
        if (_overflowCheckingEnabled)
            return false;

        if (GetIdentifierType(shape.ArrayRef) != typeof(int[]))
            return false;
        if (GetIdentifierType(shape.IndexRef) != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(shape.Bound))
            return false;
        foreach (var reduction in shape.Reductions)
            if (GetIdentifierType(reduction.AccumulatorRef) != typeof(int))
                return false;

        // Evaluate the bound EXACTLY ONCE into a temp (side-effect-free, so value-identical to the scalar loop's
        // per-iteration re-evaluation). Each reduction reads the same [index, bound) range; the index is not
        // modified until the terminal store, so every helper sees the same start value.
        var boundLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpression(shape.Bound);
        _currentIL.Emit(OpCodes.Stloc, boundLocal);

        if (TryGetMinMaxPair(shape.Reductions, out var minReduction, out var maxReduction))
        {
            // P-minmax(c) FUSED single pass for the canonical [1 min, 1 max] body (min-max-delta): one scan loads
            // each element once and computes both, halving memory traffic vs two MinInt32 + MaxInt32 passes.
            // (min, max) = SimdReductions.MinMaxInt32(array, index, bound, seedMin=min, seedMax=max).
            var tupleLocal = _currentIL.DeclareLocal(typeof(ValueTuple<int, int>));
            EmitIdentifier(shape.ArrayRef);
            EmitIdentifier(shape.IndexRef);
            _currentIL.Emit(OpCodes.Ldloc, boundLocal);
            EmitIdentifier(minReduction.AccumulatorRef);
            EmitIdentifier(maxReduction.AccumulatorRef);
            _currentIL.Emit(OpCodes.Call, s_minMaxInt32Reduction);
            _currentIL.Emit(OpCodes.Stloc, tupleLocal);

            // min = result.Item1 ; max = result.Item2 (ldloca + ldfld reads each field from the struct local).
            _currentIL.Emit(OpCodes.Ldloca, tupleLocal);
            _currentIL.Emit(OpCodes.Ldfld, s_valueTupleItem1);
            StoreIdentifier(minReduction.AccumulatorRef);
            _currentIL.Emit(OpCodes.Ldloca, tupleLocal);
            _currentIL.Emit(OpCodes.Ldfld, s_valueTupleItem2);
            StoreIdentifier(maxReduction.AccumulatorRef);
        }
        else
        {
            // One reduction (min-only/max-only) or an uncommon homogeneous pair: a separate scan per reduction.
            foreach (var reduction in shape.Reductions)
            {
                // acc = SimdReductions.Min/MaxInt32(array, index, bound, acc) -- seeded with the pre-loop accumulator.
                var helper = reduction.IsMin ? s_minInt32Reduction : s_maxInt32Reduction;
                EmitIdentifier(shape.ArrayRef);
                EmitIdentifier(shape.IndexRef);
                _currentIL.Emit(OpCodes.Ldloc, boundLocal);
                EmitIdentifier(reduction.AccumulatorRef);
                _currentIL.Emit(OpCodes.Call, helper);
                StoreIdentifier(reduction.AccumulatorRef);
            }
        }

        // index = max(index, bound) -- the scalar loop's exact terminal index value (matches both while- and
        // counted for-loops), even when the loop body never ran (bound <= index).
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Bge, keepIndexLabel);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        StoreIdentifier(shape.IndexRef);
        _currentIL.MarkLabel(keepIndexLabel);
        return true;
    }

    // True iff <paramref name="reductions"/> is exactly one min and one max reduction — the canonical
    // min-max-delta body that the fused single-pass MinMaxInt32 helper handles. min-only/max-only or an
    // uncommon homogeneous pair (e.g. two mins) fall through to the per-reduction MinInt32/MaxInt32 path.
    private static bool TryGetMinMaxPair(IReadOnlyList<MinMaxReduction> reductions, out MinMaxReduction min, out MinMaxReduction max)
    {
        min = null!;
        max = null!;
        if (reductions.Count != 2 || reductions[0].IsMin == reductions[1].IsMin)
            return false;
        min = reductions[0].IsMin ? reductions[0] : reductions[1];
        max = reductions[0].IsMin ? reductions[1] : reductions[0];
        return true;
    }

    // ---- RUST-PERF P-ctrans: shifted-compare SIMD count of adjacent transitions (the count-transitions kernel) -

    /// <summary>While-form entry (P-ctrans): <c>while i &lt; bound { current := a[i]; if current != previous
    /// { count++ }; previous = current }</c>.</summary>
    private bool TryEmitVectorizedCountTransitions(WhileStatement loop)
        => TryEmitMatchedCountTransitions(CountTransitionsShape.TryMatch(loop));

    /// <summary>For-form entry (P-ctrans). EmitFor emits the initializer first, so the index holds its start value
    /// here exactly as in the while-form.</summary>
    private bool TryEmitVectorizedCountTransitions(ForStatement loop)
        => TryEmitMatchedCountTransitions(CountTransitionsShape.TryMatch(loop));

    /// <summary>
    /// If <paramref name="shape"/> is a matched int[] adjacent-difference count, lower it to the shifted-compare
    /// SIMD helper and return true; otherwise return false (caller emits the scalar loop). The loop becomes
    /// <c>(count_delta, last) = SimdReductions.CountTransitionsInt32(array, index, bound, previous);
    /// count = count + count_delta; previous = last; index = max(index, bound)</c> — value-identical (each
    /// <c>a[i] != a[i-1]</c> comparison is independent; the carried <c>previous</c> is passed as the helper's seed
    /// so its pre-loop value need not be analyzed) and faster (packed compare + masked accumulate). The terminal
    /// <c>previous = last</c> restores the carried scalar to its scalar-loop exit value (<c>a[bound-1]</c>, or the
    /// seed when the loop never ran) so any later read is correct. Fires only for an int[] array and int
    /// counter/index/previous and an int side-effect-free bound, in the default unchecked-arithmetic context.
    /// </summary>
    private bool TryEmitMatchedCountTransitions(CountTransitionsShape? shape)
    {
        if (_currentIL == null || shape == null)
            return false;

        // Consistent with the other shapes: do not fire in a checked context. A count cannot overflow
        // (count <= end <= int.Max), so this is a conservative invariant rather than a correctness requirement.
        if (_overflowCheckingEnabled)
            return false;

        if (GetIdentifierType(shape.ArrayRef) != typeof(int[]))
            return false;
        if (GetIdentifierType(shape.CounterRef) != typeof(int))
            return false;
        if (GetIdentifierType(shape.IndexRef) != typeof(int))
            return false;
        if (GetIdentifierType(shape.PreviousRef) != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(shape.Bound))
            return false;

        // Evaluate the bound EXACTLY ONCE into a temp (side-effect-free, so value-identical to the scalar loop's
        // per-iteration re-evaluation).
        var boundLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpression(shape.Bound);
        _currentIL.Emit(OpCodes.Stloc, boundLocal);

        // (count_delta, last) = CountTransitionsInt32(array, index, bound, previous) -- previous passed as the seed.
        var tupleLocal = _currentIL.DeclareLocal(typeof(ValueTuple<int, int>));
        EmitIdentifier(shape.ArrayRef);
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        EmitIdentifier(shape.PreviousRef);
        _currentIL.Emit(OpCodes.Call, s_countTransitionsInt32);
        _currentIL.Emit(OpCodes.Stloc, tupleLocal);

        // count = count + result.Item1
        EmitIdentifier(shape.CounterRef);
        _currentIL.Emit(OpCodes.Ldloca, tupleLocal);
        _currentIL.Emit(OpCodes.Ldfld, s_valueTupleItem1);
        _currentIL.Emit(OpCodes.Add);
        StoreIdentifier(shape.CounterRef);

        // previous = result.Item2  (the scalar loop's terminal carried value)
        _currentIL.Emit(OpCodes.Ldloca, tupleLocal);
        _currentIL.Emit(OpCodes.Ldfld, s_valueTupleItem2);
        StoreIdentifier(shape.PreviousRef);

        // index = max(index, bound) -- the scalar loop's exact terminal index value.
        EmitIdentifier(shape.IndexRef);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Bge, keepIndexLabel);
        _currentIL.Emit(OpCodes.Ldloc, boundLocal);
        StoreIdentifier(shape.IndexRef);
        _currentIL.MarkLabel(keepIndexLabel);
        return true;
    }
}

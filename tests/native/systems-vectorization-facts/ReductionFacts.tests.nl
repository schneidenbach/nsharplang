namespace NSharpLang.SystemsVectorizationFacts.Tests


// SHAPE 1 OF 4: THE COUNTED INTEGER REDUCTION.
//
// `ColumnarIlEmitter.TryMatchWhileReduction` / `TryMatchForReduction` accept
//
//     while i < bound { acc = acc + a[i]; i = i + 1 }        (or `acc += a[i]` / `i += 1`)
//     for i := start; i < bound; i++ { acc = acc + a[i] }    (or `i = i + 1` / `i += 1`)
//
// and `EmitVectorizedReduction` replaces the whole loop with
//
//     acc = acc + SimdReductions.Sum<T>(a, i, bound);  if (i < bound) { i = bound }
//
// where <T> is chosen by `ReductionHelperForColumnarElementType`: int -> SumInt32, uint -> SumUInt32,
// long -> SumInt64, ulong -> SumUInt64, and NOTHING else (float and double have no helper, because floating
// addition is not associative and re-ordering the lanes would change the result).
//
// THE GUARDS `TryBuildReductionShape` IMPOSES, each of which has a negative below: the accumulator, the array
// and the index must be three distinct names; the bound must not read the accumulator; all three must be
// plain locals or parameters (not lifted or boxed captures); the index must be `int`; the array must be a
// single-dimensional array whose element type has a helper; the accumulator's type must EQUAL that element
// type; and the bound must be a side-effect-free int (a literal, an int local/parameter that is not the
// index, or `<array>.Length`).
//
// ONE ASYMMETRY IS DELIBERATE IN THE EMITTER AND PINNED HERE: the while-form calls
// `TryMatchUnitIndexIncrement(..., allowPostfix: false)`, so `while i < n { acc = acc + a[i]; i++ }` does NOT
// vectorize, while the for-form's iterator may be `i++`.
//
// WHY THIS ROUTE IS STRONGER THAN THE DELETED ONE. The deleted tests compiled a source STRING through an
// emit-only entry with a thread-local flag flipped on, then counted opcodes in the result. The IL reading is
// the same; what changed is what is being read. Here the kernels are ordinary project source: `nlc test`
// runs the analyser and the columnar emitter over them exactly as a user's build would, a decline is a BUILD
// FAILURE with a decline site rather than one false assertion, and the flag is gone — this is the shipping
// default path, not an opt-in experiment. The contracts then read BOTH the emitted IL and the computed
// values, so a shape claim and a correctness claim are made about the same compiled method.
//
// HOW THE SHAPE CONTRACTS ARE MEASURED. Every "lowers to X" / "stays scalar" block below asks `IlShape`,
// which takes the kernel's own emitted `MethodInfo`, DECODES its IL, and resolves the metadata token of
// every `call` — the same instrument `tests/PerfEvidence/ILShapeInspector.cs` was, rebuilt in N#. So a
// positive names the exact helper the emitted method calls, a negative reads "" because no call token in
// that body resolves onto `SimdReductions`, and neither answer depends on the kernel being RUN: shapes whose
// loop body can never execute are read like any other. `IlShapeFacts.tests.nl` pins the decoder first.
//
// LANE WIDTH. `Vector<int>.Count` is 4 on this arm64 machine. It cannot be read from N# (`Vector<int>`
// declines at emit.declaration.method-return / method-param — see the report), so the length sweeps below
// spell the interesting lengths out: 0, one below a width, exactly one width, width + 1, two widths, two
// widths + 3, and the large 64 / 1000 cases the deleted rows used.
//
// MAPPING — VectorizedReductionTests.cs (21 methods / 80 rows):
//   VectorizedSum_IsValueIdenticalToScalar[0,1,3,7,8,15,16,17,64,1000]
//       -> "the vectorized while-form int sum equals the scalar reference at every deleted length"
//   VectorizedReduction_LeavesIndexAtScalarTerminalValue[-3,0,1,17]
//       -> "the while form leaves the index at the scalar loop's terminal value"
//   VectorizedSum_ArrayLengthBound_VectorizesAndMatchesScalar
//       -> "an a.Length bound vectorizes in both loop forms" + "...equals the scalar reference..."
//   Vectorization_ReplacesScalarLoopWithCall_OnlyWhenEnabled
//       -> "the canonical while-form counted reduction over int[] lowers to SumInt32"
//   SuffixedLongLiteralBound_FallsBackToScalar_NoInvalidIl
//       -> "a suffixed long-literal bound falls back to the scalar loop and still sums correctly"
//   VectorizedSumLong_IsValueIdenticalToScalar[0,1,2,3,7,8,9,16,17,64,1000]
//   VectorizedSumUInt_IsValueIdenticalToScalar_IncludingWraparound[0,1,3,8,17,64,1000]
//   VectorizedSumULong_IsValueIdenticalToScalar_IncludingWraparound[0,1,3,8,17,64,1000]
//       -> "the widened element types equal their scalar references at every deleted length, wrap included"
//   IntegerReduction_LowersToHelperCall_OnlyWhenEnabled[long,uint,ulong]
//   ForFormReduction_WidenedTypes_LowerToHelperCall[long,uint,ulong]
//       -> "each widened element type lowers to its own helper in both loop forms"
//   FloatReduction_NeverVectorizes[true,false] / DoubleReduction_NeverVectorizes[true,false]
//       -> "float and double reductions never vectorize and stay numerically correct"
//   VectorizedSum_ExtremeOrEmptyBound_MatchesScalar_NoOutOfBoundsRead[MinValue,MinValue+1,MinValue+8,-1,-100,0]
//       -> "an empty or extreme-negative bound reads nothing in either loop form"
//   VectorizedReduction_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar[int,long,uint,ulong]
//   VectorizedForSum_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar
//       -> "a bound past the end throws IndexOutOfRangeException for every element type and both forms"
//   VectorizedForSum_IsValueIdenticalToScalar[0,1,7,8,15,16,17,64,1000]
//   VectorizedForSum_WidenedTypes_AreValueIdenticalToScalar[64,1000]
//       -> "the vectorized for-form sums equal the scalar reference at every deleted length"
//   ForFormReduction_NowVectorizes_WhenEnabled
//       -> "every accepted for-form iterator spelling lowers to SumInt32"
//   VectorizedForSum_NonZeroStart_MatchesScalar[(0,64),(3,64),(5,17),(60,64),(64,64),(70,64)]
//       -> "a non-zero start sums exactly [start, bound) and an empty or inverted range sums nothing"
//   VectorizedForReduction_LeavesIndexAtScalarTerminalValue[(0,64),(3,64),(64,64),(70,64)]
//       -> "the for form leaves the index at max(start, bound)"
//   VectorizedForSum_BracelessBody_VectorizesAndMatchesScalar
//       -> "every accepted for-form iterator spelling lowers to SumInt32" + the length sweep
//
// MAPPING — ReductionLoopShapeTests.cs (6 methods / 23 rows):
//   Matches_CanonicalReduction     -> "the canonical while-form counted reduction over int[] lowers to SumInt32"
//   Matches_CompoundAssignmentForms-> "the compound-assignment while form lowers to SumInt32"
//   Matches_LengthBound            -> "an a.Length bound vectorizes in both loop forms"
//   Matches_ForFormReductions[i++, i = i + 1, i += 1, a.Length, start 4]
//                                  -> "every accepted for-form iterator spelling lowers to SumInt32"
//   Matches_ForFormReductions[++i] -> NOT PORTABLE: a pre-increment for-iterator is a hard columnar decline
//                                     (NL103 emit.expression-statement.unsupported), not a scalar fallback,
//                                     so it cannot be compiled into this project at all. Recorded, not asserted.
//   Rejects_NonReductionShapes[stride 2, a[i]*2, a[i]+b[i], a[j], i <= n, extra statement, break,
//                              increment first, bound is the accumulator]
//                                  -> "the nine while-form near misses stay scalar"
//                                     + "the while-form near misses still compute their scalar values"
//   Rejects_NonReductionForShapes[i += 2, i--, a[i]*2, a[i]+b[i], a[j], i <= n, extra statement,
//                                 bound is the accumulator]
//                                  -> "the eight for-form near misses stay scalar"
//                                     + "the for-form near misses still compute their scalar values"
//
// MAPPING — SimdVectorShapeTests.cs (10 methods / 3 rows). Only its two SCALAR-FALLBACK methods are portable:
//   ScalarElementWiseLoop_StaysScalar_NoVectorTypesEmitted -> "a scalar element-wise loop is not vectorized"
//   ScalarElementWiseLoop_ProducesCorrectResults           -> "...and writes the element-wise sums"
// The other eight are the EXPLICIT `System.Numerics` vector surface, and the columnar backend declines every
// spelling of it, so no `SimdVectorShapeFacts.tests.nl` exists. Measured, with the decline sites:
//   `func f(a: Vector<int>): Vector<int>` -> NL103 emit.declaration.method-return:
//                                           static method return type 'Vector<int>' could not be resolved
//   `func f(a: Vector3, b: Vector3)`      -> NL103 emit.declaration.method-param:
//                                           static method parameter type 'Vector3' could not be resolved
//   `Vector<int>.Count`                   -> NL202 / NL305: `Vector` is parsed as a comparison, not a type
// so these eight have NO native contract and are recorded here instead:
//   VectorGeneric_Addition_EmitsDirectOperatorCall_NoBoxing
//   VectorGeneric_OperatorChain_EmitsDirectCalls_NoBoxing
//   VectorGeneric_Float_Addition_EmitsDirectOperatorCall_NoBoxing
//   FixedSizeVectors_EmitDirectOperatorCall_NoBoxing[Vector2 +, Vector3 +, Vector4 *]
//   VectorGeneric_CtorFromArray_EmitsNewobj_NoBoxing
//   VectorGeneric_Addition_IsBitIdenticalToScalar
//   VectorGeneric_Multiply_WrapsIdenticallyToScalar
//   Vector3_Addition_MatchesRuntimeSemantics
// They pinned operator-overload resolution on the BCL vector types, which is a separate feature from the
// auto-vectorizer this project pins; restoring them needs the backend to model System.Numerics vectors first.

class ReductionShapes {
    // ReductionLoopShapeTests.Matches_CanonicalReduction.
    static func WhileCanonicalInt(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // ReductionLoopShapeTests.Matches_CompoundAssignmentForms: `acc += a[i]` with `i += 1`.
    static func WhileCompoundInt(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc += a[i]
            i += 1
        }
        return acc
    }

    // ReductionLoopShapeTests.Matches_LengthBound: the pure `ldlen` bound.
    static func WhileLengthBoundInt(a: int[]): int {
        acc := 0
        i := 0
        while i < a.Length {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // The post-loop index the emitter must preserve: `max(0, n)`, not unconditionally `n`.
    static func WhileTerminalIndexInt(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return i + acc - acc
    }

    static func WhileLong(a: long[], n: int): long {
        acc: long = 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    static func WhileUInt(a: uint[], n: int): uint {
        acc: uint = 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    static func WhileULong(a: ulong[], n: int): ulong {
        acc: ulong = 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // The four accepted for-form iterator spellings.
    static func ForPostfixInt(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForAssignIteratorInt(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i = i + 1 {
            acc += a[i]
        }
        return acc
    }

    static func ForCompoundIteratorInt(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i += 1 {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForLengthBoundInt(a: int[]): int {
        acc := 0
        for i := 0; i < a.Length; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    // The a.Length bound entered from a caller-supplied start. It carries the negative-start contract:
    // `SimdReductions` takes the loop's `[start, bound)` unchanged, so a start below zero must skip the
    // in-bounds SIMD fast path and reproduce the scalar loop's read of `a[-1]`.
    static func ForLengthBoundFromStartInt(a: int[], start: int): int {
        acc := 0
        for i := start; i < a.Length; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    // A braceless single-statement body — the emitter's `TryGetSingleReductionBodyStatement` bare
    // ExpressionStatement arm (node kind 23) rather than the Block arm (kind 25).
    static func ForBracelessInt(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i++ acc = acc + a[i]
        return acc
    }

    // An arbitrary start: the helper is handed `[start, bound)`, so a non-zero start is a supported shape
    // rather than a near miss.
    static func ForFromStartInt(a: int[], start: int, n: int): int {
        acc := 0
        for i := start; i < n; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    // `i` is declared before the loop so its terminal value is readable afterwards: max(start, bound).
    static func ForTerminalIndexInt(a: int[], start: int, n: int): int {
        acc := 0
        i := 0
        for i = start; i < n; i++ {
            acc = acc + a[i]
        }
        return i + acc - acc
    }

    static func ForLong(a: long[], n: int): long {
        acc: long = 0
        for i := 0; i < n; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForUInt(a: uint[], n: int): uint {
        acc: uint = 0
        for i := 0; i < n; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForULong(a: ulong[], n: int): ulong {
        acc: ulong = 0
        for i := 0; i < n; i++ {
            acc = acc + a[i]
        }
        return acc
    }
}

class ReductionNearMisses {
    static func BoundOf(n: int): int {
        return n
    }

    // Stride 2: `TryMatchUnitIndexIncrement` requires a literal 1.
    static func WhileStrideTwo(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 2
        }
        return acc
    }

    // `a[i] * 2` is not a plain element read, so `TryMatchArrayIndexByIdentifier` rejects the update.
    static func WhileScaledElement(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i] * 2
            i = i + 1
        }
        return acc
    }

    // Two arrays in one update: the right operand of `+` is not a single indexed read.
    static func WhileTwoArrays(a: int[], b: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i] + b[i]
            i = i + 1
        }
        return acc
    }

    // Indexed by a binding that is not the loop index.
    static func WhileIndexedByOther(a: int[], n: int, j: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[j]
            i = i + 1
        }
        return acc
    }

    // `<=` changes the trip count; `TryMatchReductionCondition` accepts only `<`.
    static func WhileInclusiveBound(a: int[], n: int): int {
        acc := 0
        i := 0
        while i <= n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // A third body statement: the while matcher requires exactly two.
    static func WhileExtraStatement(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
            acc = acc + 1
        }
        return acc
    }

    // `break` is a third body statement AND irregular control flow.
    static func WhileBreak(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
            break
        }
        return acc
    }

    // The increment runs first, so the loop reads a[1..bound] rather than a[0..bound).
    static func WhileIncrementFirst(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            i = i + 1
            acc = acc + a[i]
        }
        return acc
    }

    // H1: the bound IS the accumulator, rewritten every iteration. The helper would snapshot it once and
    // scan a different element set, so `BoundReadsIdentifier` rejects the shape.
    static func WhileBoundIsAccumulator(a: int[]): int {
        acc := 1
        i := 0
        while i < acc {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // The closest legal aliasing shape: the accumulator and the index are the SAME binding, which
    // `TryBuildReductionShape` rejects with `accumulatorName == indexName`. (Aliasing the ARRAY with either
    // is unreachable in N# — a second binding of a visible name is a redeclaration error, not a loop shape.)
    static func WhileAliasedIndexAndAccumulator(a: int[], n: int): int {
        i := 0
        while i < n {
            i = i + a[i]
            i = i + 1
        }
        return i
    }

    // A suffixed long literal bound: emitting int64 into the int32 bound temp would be unverifiable IL, so
    // `IsSideEffectFreeInt32Bound` refuses it and the scalar loop stands.
    static func WhileSuffixedLongBound(a: int[]): int {
        acc := 0
        i := 0
        while i < 100L {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // A `checked(...)` update: the update expression is no longer a bare `+`, so `TryMatchReductionUpdate`
    // rejects it — which is what the documented guard in website/docs/systems.md promises.
    static func WhileCheckedUpdate(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = checked(acc + a[i])
            i = i + 1
        }
        return acc
    }

    // Element-type mismatch: a `long` accumulator over an `int[]`. `TryBuildReductionShape` requires
    // `accumulatorType == elementType`, so widening in the loop is not a reduction it will lower.
    static func WhileWideAccumulator(a: int[], n: int): long {
        acc: long = 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // No float helper exists: floating addition is not associative.
    static func WhileFloat(a: float[], n: int): float {
        acc: float = 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    static func WhileDouble(a: double[], n: int): double {
        acc: double = 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // An impure bound: a call is not a literal, an int binding or `<array>.Length`, so the emitter cannot
    // prove that snapshotting it once preserves the scalar trip count.
    static func WhileCallBound(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < BoundOf(n) {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // Postfix `++` as the WHILE increment: accepted for a for-iterator, refused here
    // (`allowPostfix: false`), so this near miss exists only in the while form.
    static func WhilePostfixIncrement(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i++
        }
        return acc
    }

    static func ForStrideTwo(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i += 2 {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForDecrement(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i-- {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForScaledElement(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i++ {
            acc = acc + a[i] * 2
        }
        return acc
    }

    static func ForTwoArrays(a: int[], b: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i++ {
            acc = acc + a[i] + b[i]
        }
        return acc
    }

    static func ForIndexedByOther(a: int[], n: int, j: int): int {
        acc := 0
        for i := 0; i < n; i++ {
            acc = acc + a[j]
        }
        return acc
    }

    static func ForInclusiveBound(a: int[], n: int): int {
        acc := 0
        for i := 0; i <= n; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    static func ForExtraStatement(a: int[], n: int): int {
        acc := 0
        for i := 0; i < n; i++ {
            acc = acc + a[i]
            acc = acc + 1
        }
        return acc
    }

    static func ForBoundIsAccumulator(a: int[]): int {
        acc := 1
        for i := 0; i < acc; i++ {
            acc = acc + a[i]
        }
        return acc
    }

    // SimdVectorShapeTests' deferred-feature guard: an element-wise store loop is not a reduction and must
    // keep its scalar `ldelem`/`stelem` lowering.
    static func ElementWiseAdd(a: int[], b: int[], c: int[], n: int) {
        i: int = 0
        while i < n {
            c[i] = a[i] + b[i]
            i = i + 1
        }
    }
}

// The oracles. Neither shape can reach a matcher: `DescendingSum*` compares with `>=` and steps with `i--`,
// and `PairStrideSum` has a compound condition whose left operand is not a bare identifier. Both facts are
// asserted below rather than assumed, so the value contracts are compared against a loop that is provably
// still scalar.
class ScalarReference {
    static func DescendingSumInt(a: int[], n: int): int {
        acc := 0
        for i := n - 1; i >= 0; i-- {
            acc = acc + a[i]
        }
        return acc
    }

    static func DescendingSumLong(a: long[], n: int): long {
        acc: long = 0
        for i := n - 1; i >= 0; i-- {
            acc = acc + a[i]
        }
        return acc
    }

    static func DescendingSumUInt(a: uint[], n: int): uint {
        acc: uint = 0
        for i := n - 1; i >= 0; i-- {
            acc = acc + a[i]
        }
        return acc
    }

    static func DescendingSumULong(a: ulong[], n: int): ulong {
        acc: ulong = 0
        for i := n - 1; i >= 0; i-- {
            acc = acc + a[i]
        }
        return acc
    }

    // Reads the array two elements at a time, then the odd tail.
    static func PairStrideSumInt(a: int[], n: int): int {
        acc := 0
        i := 0
        while i + 1 < n {
            acc = acc + a[i] + a[i + 1]
            i = i + 2
        }
        if i < n {
            acc = acc + a[i]
        }

        return acc
    }
}

// ---- Sweeps -------------------------------------------------------------------------------------------

// The first length in [0, limit] at which the while form disagrees with the descending oracle, or -1.
func FirstWhileMismatch(limit: int): int {
    for n := 0; n <= limit; n++ {
        data := SampleData.Ints(n)
        if ReductionShapes.WhileCanonicalInt(data, n) != ScalarReference.DescendingSumInt(data, n) {
            return n
        }

        if ReductionShapes.WhileCompoundInt(data, n) != ScalarReference.PairStrideSumInt(data, n) {
            return n
        }
    }
    return -1
}

// The same sweep for the for form, over all four accepted iterator spellings and the braceless body.
func FirstForMismatch(limit: int): int {
    for n := 0; n <= limit; n++ {
        data := SampleData.Ints(n)
        expected := ScalarReference.DescendingSumInt(data, n)
        if ReductionShapes.ForPostfixInt(data, n) != expected {
            return n
        }

        if ReductionShapes.ForAssignIteratorInt(data, n) != expected {
            return n
        }

        if ReductionShapes.ForCompoundIteratorInt(data, n) != expected {
            return n
        }

        if ReductionShapes.ForBracelessInt(data, n) != expected {
            return n
        }

        if ReductionShapes.ForLengthBoundInt(data) != expected {
            return n
        }
    }
    return -1
}

// The same sweep for the three widened element types.
func FirstWidenedMismatch(limit: int): int {
    for n := 0; n <= limit; n++ {
        longs := SampleData.Longs(n)
        uints := SampleData.UInts(n)
        ulongs := SampleData.ULongs(n)
        if ReductionShapes.WhileLong(longs, n) != ScalarReference.DescendingSumLong(longs, n) {
            return n
        }

        if ReductionShapes.ForLong(longs, n) != ScalarReference.DescendingSumLong(longs, n) {
            return n
        }

        if ReductionShapes.WhileUInt(uints, n) != ScalarReference.DescendingSumUInt(uints, n) {
            return n
        }

        if ReductionShapes.ForUInt(uints, n) != ScalarReference.DescendingSumUInt(uints, n) {
            return n
        }

        if ReductionShapes.WhileULong(ulongs, n) != ScalarReference.DescendingSumULong(ulongs, n) {
            return n
        }

        if ReductionShapes.ForULong(ulongs, n) != ScalarReference.DescendingSumULong(ulongs, n) {
            return n
        }
    }
    return -1
}

// The first start in [0, limit] at which `for i := start; i < bound; i++` disagrees with the oracle over
// exactly [start, bound). The oracle is the descending sum of the whole prefix minus the skipped head.
func FirstStartMismatch(bound: int, limit: int): int {
    data := SampleData.IntsFive(bound)
    for start := 0; start <= limit; start++ {
        expected := 0
        for k := start; k < bound; k++ {
            expected = expected + data[k]
        }
        if ReductionShapes.ForFromStartInt(data, start, bound) != expected {
            return start
        }
    }
    return -1
}

func ScalarTerminalIndex(start: int, bound: int): int {
    if start < bound {
        return bound
    }

    return start
}

// ---- Shapes: what the emitted IL actually calls -----------------------------------------------------

test "the canonical while-form counted reduction over int[] lowers to SumInt32" {
    assert IlShape.SimdCalls(typeof(ReductionShapes), "WhileCanonicalInt") == "SumInt32"
    // The deleted case read the same method two ways: exactly one call replaced the loop, and the scalar
    // element-load loop is gone with it.
    assert IlShape.CallCount(typeof(ReductionShapes), "WhileCanonicalInt") == 1
    assert IlShape.OpcodeCount(typeof(ReductionShapes), "WhileCanonicalInt", IlEncoding.LdelemI4()) == 0
    assert IlShape.DecodesToRet(typeof(ReductionShapes), "WhileCanonicalInt")
}

test "the compound-assignment while form lowers to SumInt32" {
    assert IlShape.SimdCalls(typeof(ReductionShapes), "WhileCompoundInt") == "SumInt32"
    assert IlShape.OpcodeCount(typeof(ReductionShapes), "WhileCompoundInt", IlEncoding.LdelemI4()) == 0
}

test "an a.Length bound vectorizes in both loop forms" {
    assert IlShape.SimdCalls(typeof(ReductionShapes), "WhileLengthBoundInt") == "SumInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForLengthBoundInt") == "SumInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForLengthBoundFromStartInt") == "SumInt32"
}

test "every accepted for-form iterator spelling lowers to SumInt32" {
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForPostfixInt") == "SumInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForAssignIteratorInt") == "SumInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForCompoundIteratorInt") == "SumInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForBracelessInt") == "SumInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForFromStartInt") == "SumInt32"
    assert IlShape.OpcodeCount(typeof(ReductionShapes), "ForPostfixInt", IlEncoding.LdelemI4()) == 0
}

test "each widened element type lowers to its own helper in both loop forms" {
    assert IlShape.SimdCalls(typeof(ReductionShapes), "WhileLong") == "SumInt64"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForLong") == "SumInt64"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "WhileUInt") == "SumUInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForUInt") == "SumUInt32"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "WhileULong") == "SumUInt64"
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForULong") == "SumUInt64"
    // Each widened form also loses its own element-load opcode, so none of them is quietly falling back.
    assert IlShape.OpcodeCount(typeof(ReductionShapes), "ForLong", IlEncoding.LdelemI8()) == 0
    assert IlShape.OpcodeCount(typeof(ReductionShapes), "ForUInt", IlEncoding.LdelemU4()) == 0
}

test "the nine while-form near misses stay scalar and keep their element loads" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileStrideTwo") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileScaledElement") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileTwoArrays") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileIndexedByOther") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileInclusiveBound") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileExtraStatement") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileBreak") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileIncrementFirst") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileBoundIsAccumulator") == ""
    // A rejected loop keeps the scalar element load the accepted one folded away, and makes no call at all.
    assert IlShape.OpcodeCount(typeof(ReductionNearMisses), "WhileScaledElement", IlEncoding.LdelemI4()) == 1
    assert IlShape.CallCount(typeof(ReductionNearMisses), "WhileScaledElement") == 0
    assert IlShape.DecodesToRet(typeof(ReductionNearMisses), "WhileBreak")
    assert IlShape.DecodesToRet(typeof(ReductionNearMisses), "WhileBoundIsAccumulator")
}

test "the eight for-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForStrideTwo") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForDecrement") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForScaledElement") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForTwoArrays") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForIndexedByOther") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForInclusiveBound") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForExtraStatement") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ForBoundIsAccumulator") == ""
    assert IlShape.CallCount(typeof(ReductionNearMisses), "ForStrideTwo") == 0
    assert IlShape.DecodesToRet(typeof(ReductionNearMisses), "ForDecrement")
}

test "the four documented guards keep the loop scalar" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileCheckedUpdate") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileWideAccumulator") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileAliasedIndexAndAccumulator") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileCallBound") == ""
    // The impure bound keeps its own call to the bound function, which is not a SimdReductions call.
    assert IlShape.CallCount(typeof(ReductionNearMisses), "WhileCallBound") == 1
    assert IlShape.CallCount(typeof(ReductionNearMisses), "WhileCheckedUpdate") == 0
}

test "float and double reductions never vectorize and keep their element loads" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileFloat") == ""
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileDouble") == ""
    assert IlShape.CallCount(typeof(ReductionNearMisses), "WhileFloat") == 0
    assert IlShape.CallCount(typeof(ReductionNearMisses), "WhileDouble") == 0
    assert IlShape.OpcodeCount(typeof(ReductionNearMisses), "WhileFloat", IlEncoding.LdelemR4()) == 1
    assert IlShape.OpcodeCount(typeof(ReductionNearMisses), "WhileDouble", IlEncoding.LdelemR8()) == 1
    // ...and stay numerically correct.
    assert ReductionNearMisses.WhileFloat(SampleData.Floats(8), 8) == 6.0f
    assert ReductionNearMisses.WhileDouble(SampleData.Doubles(8), 8) == -9.0
}

test "a postfix increment keeps the while form scalar even though it is accepted as a for iterator" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhilePostfixIncrement") == ""
    assert IlShape.SimdCalls(typeof(ReductionShapes), "ForPostfixInt") == "SumInt32"
    assert ReductionNearMisses.WhilePostfixIncrement(SampleData.Ints(8), 8) == 28
}

test "a suffixed long-literal bound falls back to the scalar loop and still sums correctly" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "WhileSuffixedLongBound") == ""
    assert IlShape.OpcodeCount(typeof(ReductionNearMisses), "WhileSuffixedLongBound", IlEncoding.LdelemI4()) == 1
    assert ReductionNearMisses.WhileSuffixedLongBound(SampleData.IntsSeven(128)) == ScalarReference.DescendingSumInt(SampleData.IntsSeven(128), 100)
}

test "a scalar element-wise loop is not vectorized and writes the element-wise sums" {
    assert IlShape.SimdCalls(typeof(ReductionNearMisses), "ElementWiseAdd") == ""
    // The deleted case also asked that no `System.Numerics` vector call appear. Nothing at all is called
    // here, which answers that and more, and the scalar `ldelem.i4` loads survive.
    assert IlShape.CallCount(typeof(ReductionNearMisses), "ElementWiseAdd") == 0
    assert IlShape.OpcodeCount(typeof(ReductionNearMisses), "ElementWiseAdd", IlEncoding.LdelemI4()) == 2
    sums := new int[8]
    ReductionNearMisses.ElementWiseAdd(SampleData.Ints(8), SampleData.IntsSeven(8), sums, 8)
    assert sums[0] == -10
    assert sums[3] == 20
    assert sums[7] == 60
}

test "both scalar oracles are themselves free of any SimdReductions call" {
    assert IlShape.SimdCalls(typeof(ScalarReference), "DescendingSumInt") == ""
    assert IlShape.SimdCalls(typeof(ScalarReference), "PairStrideSumInt") == ""
    assert IlShape.SimdCalls(typeof(ScalarReference), "DescendingSumLong") == ""
    assert IlShape.SimdCalls(typeof(ScalarReference), "DescendingSumUInt") == ""
    assert IlShape.SimdCalls(typeof(ScalarReference), "DescendingSumULong") == ""
    assert IlShape.OpcodeCount(typeof(ScalarReference), "DescendingSumInt", IlEncoding.LdelemI4()) == 1
    assert IlShape.OpcodeCount(typeof(ScalarReference), "PairStrideSumInt", IlEncoding.LdelemI4()) == 3
}

// ---- Values: the lowering is value-identical to the scalar loop -------------------------------------

test "the vectorized while-form int sum equals the scalar reference at every deleted length" {
    data1000 := SampleData.Ints(1000)
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(0), 0) == 0
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(1), 1) == -7
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(3), 3) == -12
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(7), 7) == 14
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(8), 8) == 28
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(15), 15) == 210
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(16), 16) == 248
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(17), 17) == 289
    assert ReductionShapes.WhileCanonicalInt(SampleData.Ints(64), 64) == 5600
    assert ReductionShapes.WhileCanonicalInt(data1000, 1000) == ScalarReference.DescendingSumInt(data1000, 1000)
}

test "the vectorized while and for forms agree with the scalar oracles at every length through two vector widths plus three" {
    assert FirstWhileMismatch(11) == -1
    assert FirstForMismatch(11) == -1
}

test "the vectorized for-form sums equal the scalar reference at every deleted length" {
    assert FirstForMismatch(17) == -1
    data64 := SampleData.Ints(64)
    data1000 := SampleData.Ints(1000)
    assert ReductionShapes.ForPostfixInt(data64, 64) == ScalarReference.DescendingSumInt(data64, 64)
    assert ReductionShapes.ForPostfixInt(data1000, 1000) == ScalarReference.DescendingSumInt(data1000, 1000)
}

test "the widened element types equal their scalar references at every deleted length, wrap included" {
    assert FirstWidenedMismatch(17) == -1
    longs64 := SampleData.Longs(64)
    uints64 := SampleData.UInts(64)
    ulongs64 := SampleData.ULongs(64)
    longs1000 := SampleData.Longs(1000)
    uints1000 := SampleData.UInts(1000)
    ulongs1000 := SampleData.ULongs(1000)
    assert ReductionShapes.WhileLong(longs64, 64) == ScalarReference.DescendingSumLong(longs64, 64)
    assert ReductionShapes.ForLong(longs1000, 1000) == ScalarReference.DescendingSumLong(longs1000, 1000)
    assert ReductionShapes.WhileUInt(uints64, 64) == ScalarReference.DescendingSumUInt(uints64, 64)
    assert ReductionShapes.ForUInt(uints1000, 1000) == ScalarReference.DescendingSumUInt(uints1000, 1000)
    assert ReductionShapes.WhileULong(ulongs64, 64) == ScalarReference.DescendingSumULong(ulongs64, 64)
    assert ReductionShapes.ForULong(ulongs1000, 1000) == ScalarReference.DescendingSumULong(ulongs1000, 1000)
}

test "the uint and ulong accumulators wrap rather than saturate" {
    // Two lanes of 2^31 sum to 2^32, which is 0 in a uint accumulator; two lanes of 2^63 sum to 2^64, which
    // is 0 in a ulong accumulator. Wrapping is what makes the reduction associative, and therefore what makes
    // reordering it across SIMD lanes value-identical to the scalar loop; a saturating or silently widening
    // accumulator would answer differently here.
    halfUInt: uint = (uint)65536 * (uint)32768
    wrappingUInts := new uint[2]
    wrappingUInts[0] = halfUInt
    wrappingUInts[1] = halfUInt
    assert ReductionShapes.ForUInt(wrappingUInts, 2) == (uint)0
    assert ReductionShapes.WhileUInt(wrappingUInts, 2) == (uint)0
    halfULong: ulong = (ulong)65536 * (ulong)65536 * (ulong)65536 * (ulong)32768
    wrappingULongs := new ulong[2]
    wrappingULongs[0] = halfULong
    wrappingULongs[1] = halfULong
    assert ReductionShapes.ForULong(wrappingULongs, 2) == (ulong)0
    assert ReductionShapes.WhileULong(wrappingULongs, 2) == (ulong)0
    // And the same wrap over a full 1000-element sweep still tracks the scalar loop exactly.
    uints := SampleData.UInts(1000)
    ulongs := SampleData.ULongs(1000)
    assert ReductionShapes.ForUInt(uints, 1000) == ScalarReference.DescendingSumUInt(uints, 1000)
    assert ReductionShapes.ForULong(ulongs, 1000) == ScalarReference.DescendingSumULong(ulongs, 1000)
}

test "randomized input including both int extremes reduces exactly like the scalar loop" {
    for n := 0; n <= 40; n++ {
        data := SampleData.Randomized(n)
        assert ReductionShapes.WhileCanonicalInt(data, n) == ScalarReference.DescendingSumInt(data, n)
    }
    big := SampleData.Randomized(1000)
    assert ReductionShapes.ForPostfixInt(big, 1000) == ScalarReference.DescendingSumInt(big, 1000)
}

test "a non-zero start sums exactly the start-to-bound range and an empty or inverted range sums nothing" {
    assert FirstStartMismatch(64, 64) == -1
    data := SampleData.IntsFive(64)
    assert ReductionShapes.ForFromStartInt(data, 64, 64) == 0
    assert ReductionShapes.ForFromStartInt(data, 70, 64) == 0
    assert ReductionShapes.ForFromStartInt(SampleData.IntsFive(17), 5, 17) == ScalarReference.DescendingSumInt(SampleData.IntsFive(17), 17) - ScalarReference.DescendingSumInt(SampleData.IntsFive(17), 5)
}

test "an empty or extreme-negative bound reads nothing in either loop form" {
    data := SampleData.Ints(100)
    assert ReductionShapes.WhileCanonicalInt(data, int.MinValue) == 0
    assert ReductionShapes.WhileCanonicalInt(data, int.MinValue + 1) == 0
    assert ReductionShapes.WhileCanonicalInt(data, int.MinValue + 8) == 0
    assert ReductionShapes.WhileCanonicalInt(data, -1) == 0
    assert ReductionShapes.WhileCanonicalInt(data, -100) == 0
    assert ReductionShapes.WhileCanonicalInt(data, 0) == 0
    assert ReductionShapes.ForPostfixInt(data, int.MinValue) == 0
    assert ReductionShapes.ForPostfixInt(data, -1) == 0
    assert ReductionShapes.ForPostfixInt(data, 0) == 0
}

test "the while form leaves the index at the scalar loop's terminal value" {
    assert ReductionShapes.WhileTerminalIndexInt(SampleData.Ints(0), -3) == 0
    assert ReductionShapes.WhileTerminalIndexInt(SampleData.Ints(0), 0) == 0
    assert ReductionShapes.WhileTerminalIndexInt(SampleData.Ints(1), 1) == 1
    assert ReductionShapes.WhileTerminalIndexInt(SampleData.Ints(17), 17) == 17
}

test "the for form leaves the index at max(start, bound)" {
    data := SampleData.Ints(64)
    assert ReductionShapes.ForTerminalIndexInt(data, 0, 64) == ScalarTerminalIndex(0, 64)
    assert ReductionShapes.ForTerminalIndexInt(data, 3, 64) == ScalarTerminalIndex(3, 64)
    assert ReductionShapes.ForTerminalIndexInt(data, 64, 64) == ScalarTerminalIndex(64, 64)
    assert ReductionShapes.ForTerminalIndexInt(data, 70, 64) == ScalarTerminalIndex(70, 64)
}

test "a bound past the end throws IndexOutOfRangeException for every element type and both loop forms" {
    assert KernelRuns.ThrownTypeOf(() => ReductionShapes.WhileCanonicalInt(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => (int)ReductionShapes.WhileLong(new long[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => (int)ReductionShapes.WhileUInt(new uint[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => (int)ReductionShapes.WhileULong(new ulong[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => ReductionShapes.ForPostfixInt(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => ScalarReference.DescendingSumInt(new int[10], 100)) == "System.IndexOutOfRangeException"
}

test "the while-form near misses still compute their scalar values" {
    data := SampleData.Ints(8)
    assert ReductionShapes.WhileCanonicalInt(data, 8) == 28
    assert ReductionNearMisses.WhileStrideTwo(data, 8) == 8
    assert ReductionNearMisses.WhileScaledElement(data, 8) == 56
    assert ReductionNearMisses.WhileTwoArrays(data, data, 8) == 56
    assert ReductionNearMisses.WhileIndexedByOther(data, 8, 0) == -56
    assert ReductionNearMisses.WhileInclusiveBound(data, 7) == 28
    assert ReductionNearMisses.WhileExtraStatement(data, 8) == 36
    assert ReductionNearMisses.WhileBreak(data, 8) == -7
    assert ReductionNearMisses.WhileIncrementFirst(data, 7) == 35
    assert ReductionNearMisses.WhileBoundIsAccumulator(data) == -6
    assert ReductionNearMisses.WhileCheckedUpdate(data, 8) == 28
    assert ReductionNearMisses.WhileWideAccumulator(data, 8) == (long)28
    assert ReductionNearMisses.WhileCallBound(data, 8) == 28
    assert ReductionNearMisses.WhileAliasedIndexAndAccumulator(SampleData.AsciiLike(8), 8) == 33
}

test "the for-form near misses still compute their scalar values" {
    data := SampleData.Ints(8)
    assert ReductionNearMisses.ForStrideTwo(data, 8) == 8
    assert ReductionNearMisses.ForDecrement(data, 0) == 0
    assert ReductionNearMisses.ForScaledElement(data, 8) == 56
    assert ReductionNearMisses.ForTwoArrays(data, data, 8) == 56
    assert ReductionNearMisses.ForIndexedByOther(data, 8, 0) == -56
    assert ReductionNearMisses.ForInclusiveBound(data, 7) == 28
    assert ReductionNearMisses.ForExtraStatement(data, 8) == 36
    assert ReductionNearMisses.ForBoundIsAccumulator(data) == -6
}

test "a start below zero reads a[-1] exactly as the scalar loop does" {
    // `SimdReductions` is handed the loop's `[start, bound)` unchanged, and its in-bounds SIMD fast path is
    // guarded by `start >= 0 && end <= array.Length`. A negative start must therefore fall through to the
    // helper's scalar tail and throw the same IndexOutOfRangeException the scalar loop would — not the
    // ArgumentOutOfRangeException a `new Vector<T>(array, i)` would raise.
    assert KernelRuns.ThrownTypeOf(() => ReductionShapes.ForLengthBoundFromStartInt(SampleData.Ints(8), -1)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => ScalarReference.DescendingSumInt(SampleData.Ints(8), 8)) == "no-exception"
    // A start at or past the bound is an empty range: nothing is read and the seed value stands.
    assert ReductionShapes.ForLengthBoundFromStartInt(SampleData.Ints(8), 8) == 0
    assert ReductionShapes.ForLengthBoundFromStartInt(SampleData.Ints(8), 12) == 0
    assert ReductionShapes.ForLengthBoundFromStartInt(SampleData.Ints(8), 0) == ScalarReference.DescendingSumInt(SampleData.Ints(8), 8)
}

namespace NSharpLang.SystemsVectorizationFacts.Tests


// SHAPE 3 OF 4: THE LANE-WISE MIN/MAX REDUCTION (the min-max-delta kernel).
//
// `ColumnarIlEmitter.TryMatchWhileMinMax` / `TryMatchForMinMax` accept a unit-stride counted loop whose body
// is one or two conditional-assignment `if`s over the same subject, optionally preceded by a temp:
//
//     value := a[i];  if value < min { min = value }  [ if value > max { max = value } ]
//     if a[i] < min { min = a[i] }                    [ if a[i] > max { max = a[i] } ]
//
// with either operand order (`value < min` or `min > value`), and `EmitVectorizedMinMax` replaces the loop
// with helper calls seeded by the accumulators' current values:
//
//     one min + one max  ->  (min, max) = SimdReductions.MinMaxInt32(a, i, bound, min, max)   [FUSED]
//     otherwise          ->  min = SimdReductions.MinInt32(a, i, bound, min)                  (per reduction)
//                            max = SimdReductions.MaxInt32(a, i, bound, max)
//     then, in both cases: if (i < bound) { i = bound }
//
// FUSION IS THE POINT OF THIS SHAPE: `TryGetMinMaxPair` fires only when there are exactly two reductions and
// they differ in direction, so one scan computes both. The deleted tests proved that by counting calls (1,
// not 2). This project proves it by NAME — a fused pair enters `MinMaxInt32`, an unfused one enters
// `MinInt32` — which is a stronger claim than a count, because a count of 1 could also be one helper doing
// half the work.
//
// THE GUARDS, each of which has a negative below. The comparison must be STRICT (`<` / `>`); the `if` must
// have no else and exactly one statement in its body; the assigned value must be the compared subject
// itself; the two `if`s must write DIFFERENT accumulators; every `if` must read the same array through the
// loop index (or the same temp); the body is at most a temp plus two `if`s; the bound must not read an
// accumulator or the temp; the increment must be a unit step and, in the while form, the LAST statement;
// and — from `TryBuildMinMaxShape` — the array must be exactly `int[]` and the index and every accumulator
// must be `int`.
//
// HOW THE SHAPE CONTRACTS ARE MEASURED. Every "lowers to X" / "stays scalar" block below asks `IlShape`,
// which takes the kernel's own emitted `MethodInfo`, DECODES its IL, and resolves the metadata token of
// every `call` — the same instrument `tests/PerfEvidence/ILShapeInspector.cs` was, rebuilt in N#. So a
// positive names the exact helper the emitted method calls, a negative reads "" because no call token in
// that body resolves onto `SimdReductions`, and neither answer depends on the kernel being RUN: shapes whose
// loop body can never execute are read like any other. `IlShapeFacts.tests.nl` pins the decoder first.
//
// THE HELPER EDGE CASES REACH THE HELPER THROUGH THE PRODUCT PATH. `MinMaxHelperEdgeCaseTests` called
// `SimdReductions.MinInt32` / `MaxInt32` / `MinMaxInt32` directly with explicit seeds, starts and ends. N#
// cannot import the runtime assembly (NL704), so the kernels below take the seed and the start as PARAMETERS
// — the emitter passes both straight through to the helper, so the same (array, start, end, seed) calls are
// made, and the emitter's own argument order is pinned at the same time.
//
// MAPPING — MinMaxReductionLoopShapeTests.cs (6 methods / 21 rows):
//   Matches_ForFormMinMax[temp subject, inlined + a.Length bound, reversed operand order]
//       -> "all three accepted for-form min/max bodies fuse into MinMaxInt32"
//   Matches_WhileFormMinMax[temp subject, inlined + i++]
//       -> "both accepted while-form min/max bodies fuse into MinMaxInt32"
//   Matches_MinOnly_BracelessFor -> "a lone min reduction lowers to MinInt32 and a lone max to MaxInt32"
//   Matches_MaxOnly_Temp         -> "a lone min reduction lowers to MinInt32 and a lone max to MaxInt32"
//   Rejects_NonMinMaxForShapes[non-strict <=, else branch, min = value + 1, a[j], two arrays,
//                              temp but the predicate compares another variable, both ifs write one
//                              accumulator, extra loop-body statement, extra if-body statement,
//                              non-unit increment, condition against a constant, the bound IS the
//                              accumulator]
//       -> "the thirteen for-form near misses stay scalar"
//          + "the for-form near misses still compute their scalar min and max"
//   Rejects_NonMinMaxForShapes[loop-variant bound `i < i`]
//       -> "a self-referential bound never runs the loop body" (see that block: the loop body cannot be
//          entered at all, so the frame instrument has nothing to observe; the rejection is structural —
//          `IsSideEffectFreeInt32Bound` refuses a bound whose name IS the index — and the value is pinned)
//   Rejects_NonMinMaxWhileShapes[missing increment, increment by 2, increment not last]
//       -> "the three while-form near misses stay scalar"
//
// MAPPING — MinMaxReductionVectorizationTests.cs (16 methods / 39 rows):
//   VectorizedMinMaxDelta_IsValueIdenticalToScalar[1,2,7,8,15,16,17,33,64,1000]
//       -> "the fused min-max delta equals the scalar reference at every deleted length"
//   VectorizedMinMax_InlinedAndWhileForms_MatchScalar[1,8,17,64,1000]
//       -> "the inlined and while forms agree with the scalar reference"
//   VectorizedMinOnly_MatchesScalar[8,17,64]
//       -> "a lone min reduction equals the scalar reference"
//   MinMax_LowersToOneFusedHelperCall_OnlyWhenEnabled
//       -> "all three accepted for-form min/max bodies fuse into MinMaxInt32"
//          + "both accepted while-form min/max bodies fuse into MinMaxInt32"
//   MinOnly_LowersToOneHelperCall_OnlyWhenEnabled
//       -> "a lone min reduction lowers to MinInt32 and a lone max to MaxInt32"
//   MinMax_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar
//       -> "a bound past the end throws IndexOutOfRangeException exactly as the scalar loop does"
//   MinMax_EmptyOrNegativeBound_MatchesScalar_NoOutOfBoundsRead[int.MinValue,-1,0,1]
//       -> "an empty or extreme-negative bound leaves both accumulators at their seeds"
//   MinMax_NonIntArray_DoesNotVectorize_ButMatchesScalar
//       -> "a long[] array keeps the loop scalar and still computes the delta"
//   MinMaxHelperEdgeCaseTests.MinMaxInt32_SimdPath_MatchesScalar_AcrossSeeds[MinValue,-1000,0,7,MaxValue]
//       -> "seeded min and max scans match the scalar fold for every seed"
//   MinMaxHelperEdgeCaseTests.MinMaxInt32_PartialRange_MatchesScalar[(0,200),(1,200),(3,197),(50,150)]
//   FusedMinMaxInt32_PartialRange_MatchesScalar[(0,200),(1,200),(3,197),(50,150)]
//       -> "partial ranges scan exactly the requested window"
//   MinMaxInt32_AllEqual_ReturnsThatValue / FusedMinMaxInt32_AllEqual_ReturnsThatValue
//       -> "an all-equal array collapses both accumulators onto that value"
//   MinMaxInt32_EmptyRange_ReturnsSeed / FusedMinMaxInt32_EmptyAndNegativeRange_ReturnsSeeds
//       -> "an empty or inverted range returns the seeds untouched"
//   FusedMinMaxInt32_SimdPath_MatchesSeparateAndScalar[(MinValue,MaxValue),(0,0),(7,7),(MaxValue,MinValue)]
//       -> "the fused pair agrees with the two separate scans and with the scalar fold"

class MinMaxShapes {
    // The min-max-delta benchmark shape: for, temp subject, seeded from a[0], scanning [1, n).
    static func ForTempDelta(a: int[], n: int): int {
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
    }

    // for, inlined subject, a.Length bound, the whole [0, len) range.
    static func ForInlinedDelta(a: int[]): int {
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
    }

    // for, temp subject, reversed operand order (`min > value` / `max < value`).
    static func ForReversedOperands(a: int[], n: int): int {
        min := a[0]
        max := a[0]
        for i := 1; i < n; i++ {
            value := a[i]
            if min > value {
                min = value
            }

            if max < value {
                max = value
            }
        }
        return max - min
    }

    // while, temp subject, `i = i + 1`.
    static func WhileTempDelta(a: int[], n: int): int {
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
    }

    // while, inlined subject, a.Length bound, postfix `i++` (which the min/max while matcher DOES accept,
    // unlike the plain-reduction while matcher).
    static func WhileInlinedDelta(a: int[]): int {
        min := a[0]
        max := a[0]
        i := 0
        while i < a.Length {
            if a[i] < min {
                min = a[i]
            }

            if a[i] > max {
                max = a[i]
            }

            i++
        }
        return max - min
    }

    // The a.Length-bound body again, but entered from a caller-supplied start and seed. It carries the
    // negative-start contract: `SimdReductions` takes the loop's `[start, bound)` unchanged, so a start below
    // zero must skip the in-bounds SIMD fast path and reproduce the scalar loop's read of `a[-1]`.
    static func ForInlinedFromStart(a: int[], start: int, seed: int): int {
        min := seed
        max := seed
        for i := start; i < a.Length; i++ {
            if a[i] < min {
                min = a[i]
            }

            if a[i] > max {
                max = a[i]
            }
        }
        return max - min
    }

    // TWO minima over the same array, into two accumulators. Accepted (the two `if`s write different
    // accumulators), but `TryGetMinMaxPair` requires the pair to differ in DIRECTION, so this one does not
    // fuse: it is the unfused control the fusion contract is measured against.
    static func ForTwoMinima(a: int[], n: int): int {
        low := a[0]
        other := a[0]
        for i := 1; i < n; i++ {
            if a[i] < low {
                low = a[i]
            }

            if a[i] < other {
                other = a[i]
            }
        }
        return low - other
    }

    // A lone min reduction: one reduction, so no fusion.
    static func ForMinOnly(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    // A lone max reduction through the temp form.
    static func ForMaxOnly(a: int[], n: int): int {
        max := a[0]
        for i := 1; i < n; i++ {
            value := a[i]
            if value > max {
                max = value
            }
        }
        return max
    }

    // The seeded, partial-range forms: `start` and `seed` are handed straight to the helper, so these reach
    // MinInt32 / MaxInt32 / MinMaxInt32 with exactly the arguments the deleted helper tests passed.
    static func SeededMin(a: int[], start: int, n: int, seed: int): int {
        min := seed
        for i := start; i < n; i++ {
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    static func SeededMax(a: int[], start: int, n: int, seed: int): int {
        max := seed
        for i := start; i < n; i++ {
            if a[i] > max {
                max = a[i]
            }
        }
        return max
    }

    static func FusedMin(a: int[], start: int, n: int, seedMin: int, seedMax: int): int {
        min := seedMin
        max := seedMax
        for i := start; i < n; i++ {
            value := a[i]
            if value < min {
                min = value
            }

            if value > max {
                max = value
            }
        }
        return min
    }

    static func FusedMax(a: int[], start: int, n: int, seedMin: int, seedMax: int): int {
        min := seedMin
        max := seedMax
        for i := start; i < n; i++ {
            value := a[i]
            if value < min {
                min = value
            }

            if value > max {
                max = value
            }
        }
        return max
    }
}

class MinMaxNearMisses {
    // `<=` is not the strict comparison the matcher requires.
    static func ForNonStrict(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            value := a[i]
            if value <= min {
                min = value
            }
        }
        return min
    }

    // An else branch.
    static func ForElseBranch(a: int[], n: int): int {
        min := a[0]
        max := a[0]
        for i := 1; i < n; i++ {
            if a[i] < min {
                min = a[i]
            } else {
                max = a[i]
            }
        }
        return max - min
    }

    // The assigned value is not the compared subject.
    static func ForAssignsOffsetValue(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            value := a[i]
            if value < min {
                min = value + 1
            }
        }
        return min
    }

    // Indexed by a binding that is not the loop index.
    static func ForIndexedByOther(a: int[], n: int, j: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            if a[j] < min {
                min = a[j]
            }
        }
        return min
    }

    // Two different arrays across the two reductions.
    static func ForTwoArrays(a: int[], b: int[], n: int): int {
        min := a[0]
        max := a[0]
        for i := 0; i < n; i++ {
            if a[i] < min {
                min = a[i]
            }

            if b[i] > max {
                max = b[i]
            }
        }
        return max - min
    }

    // A temp subject whose predicate compares a different variable.
    static func ForTempWithForeignSubject(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            value := a[i]
            if i < min {
                min = i
            }
        }
        return min + a[0] - a[0]
    }

    // Both `if`s write the SAME accumulator, which `seenAccumulators` refuses.
    static func ForSameAccumulatorTwice(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            if a[i] < min {
                min = a[i]
            }

            if a[i] > min {
                min = a[i]
            }
        }
        return min
    }

    // A fourth statement in the loop body (temp + two ifs is the maximum).
    static func ForExtraStatementInBody(a: int[], n: int): int {
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

            min = min + 0
        }
        return max - min
    }

    // Two statements inside one `if` body.
    static func ForExtraStatementInIf(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            if a[i] < min {
                min = a[i]
                min = a[i]
            }
        }
        return min
    }

    // A self-referential bound: the loop can never run, and `IsSideEffectFreeInt32Bound` refuses a bound
    // whose name IS the index.
    static func ForSelfBound(a: int[]): int {
        min := a[0]
        for i := 1; i < i; i++ {
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    // A non-unit increment.
    static func ForStrideTwo(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i += 2 {
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    // The condition compares the subject against a CONSTANT, not against the accumulator, so this is a
    // "last element below 5" filter rather than a min reduction.
    static func ForConstantCondition(a: int[], n: int): int {
        min := a[0]
        for i := 1; i < n; i++ {
            if a[i] < 5 {
                min = a[i]
            }
        }
        return min
    }

    // H1: the bound IS the accumulator, which the body rewrites.
    static func ForBoundIsAccumulator(a: int[]): int {
        min := a[0]
        for i := 1; i < min; i++ {
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    // while: no index increment at all.
    static func WhileMissingIncrement(a: int[], n: int): int {
        min := a[0]
        i := 1
        while i < n {
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    // while: increment by 2.
    static func WhileStrideTwo(a: int[], n: int): int {
        min := a[0]
        i := 1
        while i < n {
            if a[i] < min {
                min = a[i]
            }

            i = i + 2
        }
        return min
    }

    // while: the increment is not the last statement.
    static func WhileIncrementFirst(a: int[], n: int): int {
        min := a[0]
        i := 1
        while i < n {
            i = i + 1
            if a[i] < min {
                min = a[i]
            }
        }
        return min
    }

    // A long[] array: `TryBuildMinMaxShape` requires exactly `int[]`.
    static func ForLongDelta(a: long[], n: int): long {
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
    }
}

// The oracle: the same folds in descending index order, which no matcher accepts.
class ScalarMinMaxReference {
    static func DescendingMin(a: int[], start: int, n: int, seed: int): int {
        m := seed
        for i := n - 1; i >= start; i-- {
            if a[i] < m {
                m = a[i]
            }
        }
        return m
    }

    static func DescendingMax(a: int[], start: int, n: int, seed: int): int {
        m := seed
        for i := n - 1; i >= start; i-- {
            if a[i] > m {
                m = a[i]
            }
        }
        return m
    }

    static func DescendingDelta(a: int[], n: int): int {
        return DescendingMax(a, 1, n, a[0]) - DescendingMin(a, 1, n, a[0])
    }

    static func DescendingDeltaLong(a: long[], n: int): long {
        low := a[0]
        high := a[0]
        for i := n - 1; i >= 1; i-- {
            if a[i] < low {
                low = a[i]
            }

            if a[i] > high {
                high = a[i]
            }
        }
        return high - low
    }
}

// The first length in [1, limit] at which any accepted min/max form disagrees with the oracle, or -1.
func FirstMinMaxMismatch(limit: int): int {
    for n := 1; n <= limit; n++ {
        data := SampleData.SignedLike(n)
        expected := ScalarMinMaxReference.DescendingDelta(data, n)
        if MinMaxShapes.ForTempDelta(data, n) != expected {
            return n
        }

        if MinMaxShapes.ForReversedOperands(data, n) != expected {
            return n
        }

        if MinMaxShapes.WhileTempDelta(data, n) != expected {
            return n
        }

        if MinMaxShapes.ForInlinedDelta(data) != expected {
            return n
        }

        if MinMaxShapes.WhileInlinedDelta(data) != expected {
            return n
        }

        if MinMaxShapes.ForMinOnly(data, n) != ScalarMinMaxReference.DescendingMin(data, 1, n, data[0]) {
            return n
        }

        if MinMaxShapes.ForMaxOnly(data, n) != ScalarMinMaxReference.DescendingMax(data, 1, n, data[0]) {
            return n
        }
    }
    return -1
}

// ---- Shapes: what the emitted IL actually calls -----------------------------------------------------

test "all three accepted for-form min/max bodies fuse into MinMaxInt32" {
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForTempDelta") == "MinMaxInt32"
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForInlinedDelta") == "MinMaxInt32"
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForReversedOperands") == "MinMaxInt32"
    assert IlShape.DecodesToRet(typeof(MinMaxShapes), "ForTempDelta")
}

test "both accepted while-form min/max bodies fuse into MinMaxInt32" {
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "WhileTempDelta") == "MinMaxInt32"
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "WhileInlinedDelta") == "MinMaxInt32"
}

test "a min and a max over one scan fuse into a single helper call, and two mins do not" {
    // The deleted case counted calls: the [1 min, 1 max] body must fuse into a SINGLE MinMaxInt32 rather
    // than two scans. Reading the resolved NAMES says more than a count. `TryGetMinMaxPair` fires only when
    // the two reductions differ in DIRECTION, so two minima over the same array stay two separate MinInt32
    // scans — and that contrast is what shows the fusion is a real single pass rather than a smaller number.
    assert IlShape.CallCount(typeof(MinMaxShapes), "ForTempDelta") == 1
    assert IlShape.CallCount(typeof(MinMaxShapes), "WhileTempDelta") == 1
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForTwoMinima") == "MinInt32,MinInt32"
    assert IlShape.CallCount(typeof(MinMaxShapes), "ForTwoMinima") == 2
    // Both kernels keep exactly the two `a[0]` seed reads that sit OUTSIDE the loop, and nothing else: the
    // loop's own element load is gone in each. (A min/max kernel is seeded from the array, so its element
    // load count falls to the seeds rather than to zero.)
    assert IlShape.OpcodeCount(typeof(MinMaxShapes), "ForTempDelta", IlEncoding.LdelemI4()) == 2
    assert IlShape.OpcodeCount(typeof(MinMaxShapes), "ForTwoMinima", IlEncoding.LdelemI4()) == 2
}

test "a lone min reduction lowers to MinInt32 and a lone max to MaxInt32" {
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForMinOnly") == "MinInt32"
    assert IlShape.CallCount(typeof(MinMaxShapes), "ForMinOnly") == 1
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForMaxOnly") == "MaxInt32"
    assert IlShape.CallCount(typeof(MinMaxShapes), "ForMaxOnly") == 1
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "SeededMin") == "MinInt32"
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "SeededMax") == "MaxInt32"
}

test "the seeded fused kernels reach the fused helper rather than two separate scans" {
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "FusedMin") == "MinMaxInt32"
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "FusedMax") == "MinMaxInt32"
    assert IlShape.SimdCalls(typeof(MinMaxShapes), "ForInlinedFromStart") == "MinMaxInt32"
}

test "the thirteen for-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForNonStrict") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForElseBranch") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForAssignsOffsetValue") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForIndexedByOther") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForTwoArrays") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForTempWithForeignSubject") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForSameAccumulatorTwice") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForExtraStatementInBody") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForExtraStatementInIf") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForStrideTwo") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForConstantCondition") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForBoundIsAccumulator") == ""
    // The self-referential bound `for i := 1; i < i; i++`. Its body can never RUN, so nothing about it is
    // observable from behaviour — but its IL is emitted all the same, and reading it shows the scalar loop
    // standing where a helper call would be. `IsSideEffectFreeInt32Bound` refuses a bound whose identifier
    // IS the index.
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForSelfBound") == ""
    assert IlShape.OpcodeCount(typeof(MinMaxNearMisses), "ForSelfBound", IlEncoding.LdelemI4()) == 3
    assert IlShape.CallCount(typeof(MinMaxNearMisses), "ForNonStrict") == 0
    assert IlShape.DecodesToRet(typeof(MinMaxNearMisses), "ForSelfBound")
}

test "the three while-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "WhileMissingIncrement") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "WhileStrideTwo") == ""
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "WhileIncrementFirst") == ""
    assert IlShape.DecodesToRet(typeof(MinMaxNearMisses), "WhileMissingIncrement")
}

test "a long[] array keeps the loop scalar and still computes the delta" {
    assert IlShape.SimdCalls(typeof(MinMaxNearMisses), "ForLongDelta") == ""
    assert IlShape.OpcodeCount(typeof(MinMaxNearMisses), "ForLongDelta", IlEncoding.LdelemI8()) == 6
    longs := SampleData.SignedLongs(64)
    assert MinMaxNearMisses.ForLongDelta(longs, 64) == ScalarMinMaxReference.DescendingDeltaLong(longs, 64)
}

test "the min and max oracles are themselves free of any SimdReductions call" {
    assert IlShape.SimdCalls(typeof(ScalarMinMaxReference), "DescendingMin") == ""
    assert IlShape.SimdCalls(typeof(ScalarMinMaxReference), "DescendingMax") == ""
    assert IlShape.OpcodeCount(typeof(ScalarMinMaxReference), "DescendingMin", IlEncoding.LdelemI4()) == 2
}

// ---- Values: the lowering is value-identical to the scalar loop -------------------------------------

test "the fused min-max delta equals the scalar reference at every deleted length" {
    assert FirstMinMaxMismatch(33) == -1
    signed64 := SampleData.SignedLike(64)
    signed1000 := SampleData.SignedLike(1000)
    assert MinMaxShapes.ForTempDelta(signed64, 64) == ScalarMinMaxReference.DescendingDelta(signed64, 64)
    assert MinMaxShapes.ForTempDelta(signed1000, 1000) == ScalarMinMaxReference.DescendingDelta(signed1000, 1000)
}

test "the inlined and while forms agree with the scalar reference" {
    signed64 := SampleData.SignedLike(64)
    signed1000 := SampleData.SignedLike(1000)
    assert MinMaxShapes.ForInlinedDelta(signed64) == ScalarMinMaxReference.DescendingDelta(signed64, 64)
    assert MinMaxShapes.WhileTempDelta(signed64, 64) == ScalarMinMaxReference.DescendingDelta(signed64, 64)
    assert MinMaxShapes.ForInlinedDelta(signed1000) == ScalarMinMaxReference.DescendingDelta(signed1000, 1000)
    assert MinMaxShapes.WhileTempDelta(signed1000, 1000) == ScalarMinMaxReference.DescendingDelta(signed1000, 1000)
}

test "a lone min reduction equals the scalar reference" {
    signed8 := SampleData.SignedLike(8)
    signed17 := SampleData.SignedLike(17)
    signed64 := SampleData.SignedLike(64)
    assert MinMaxShapes.ForMinOnly(signed8, 8) == ScalarMinMaxReference.DescendingMin(signed8, 1, 8, signed8[0])
    assert MinMaxShapes.ForMinOnly(signed17, 17) == ScalarMinMaxReference.DescendingMin(signed17, 1, 17, signed17[0])
    assert MinMaxShapes.ForMinOnly(signed64, 64) == ScalarMinMaxReference.DescendingMin(signed64, 1, 64, signed64[0])
}

test "the planted extremes are found even though they sit on interior lanes" {
    // SignedLike plants int.MinValue at index 3 and int.MaxValue at index 5, and seeds a[0] with 7, so
    // neither extreme is the seed and neither can be reached by a tail-only scan.
    signed := SampleData.SignedLike(200)
    assert MinMaxShapes.ForMinOnly(signed, 200) == int.MinValue
    assert MinMaxShapes.ForMaxOnly(signed, 200) == int.MaxValue
}

test "seeded min and max scans match the scalar fold for every seed" {
    mixed := SampleData.MixedExtremes(200)
    assert MinMaxShapes.SeededMin(mixed, 0, 200, int.MinValue) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, int.MinValue)
    assert MinMaxShapes.SeededMin(mixed, 0, 200, -1000) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, -1000)
    assert MinMaxShapes.SeededMin(mixed, 0, 200, 0) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, 0)
    assert MinMaxShapes.SeededMin(mixed, 0, 200, 7) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, 7)
    assert MinMaxShapes.SeededMin(mixed, 0, 200, int.MaxValue) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, int.MaxValue)
    assert MinMaxShapes.SeededMax(mixed, 0, 200, int.MinValue) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, int.MinValue)
    assert MinMaxShapes.SeededMax(mixed, 0, 200, -1000) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, -1000)
    assert MinMaxShapes.SeededMax(mixed, 0, 200, 0) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, 0)
    assert MinMaxShapes.SeededMax(mixed, 0, 200, 7) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, 7)
    assert MinMaxShapes.SeededMax(mixed, 0, 200, int.MaxValue) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, int.MaxValue)
}

test "partial ranges scan exactly the requested window" {
    mixed := SampleData.MixedExtremes(200)
    assert MinMaxShapes.SeededMin(mixed, 0, 200, 0) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, 0)
    assert MinMaxShapes.SeededMin(mixed, 1, 200, 0) == ScalarMinMaxReference.DescendingMin(mixed, 1, 200, 0)
    assert MinMaxShapes.SeededMin(mixed, 3, 197, 0) == ScalarMinMaxReference.DescendingMin(mixed, 3, 197, 0)
    assert MinMaxShapes.SeededMin(mixed, 50, 150, 0) == ScalarMinMaxReference.DescendingMin(mixed, 50, 150, 0)
    assert MinMaxShapes.FusedMin(mixed, 3, 197, mixed[3], mixed[3]) == ScalarMinMaxReference.DescendingMin(mixed, 3, 197, mixed[3])
    assert MinMaxShapes.FusedMax(mixed, 3, 197, mixed[3], mixed[3]) == ScalarMinMaxReference.DescendingMax(mixed, 3, 197, mixed[3])
    assert MinMaxShapes.FusedMin(mixed, 50, 150, mixed[50], mixed[50]) == ScalarMinMaxReference.DescendingMin(mixed, 50, 150, mixed[50])
    assert MinMaxShapes.FusedMax(mixed, 50, 150, mixed[50], mixed[50]) == ScalarMinMaxReference.DescendingMax(mixed, 50, 150, mixed[50])
}

test "the fused pair agrees with the two separate scans and with the scalar fold" {
    mixed := SampleData.MixedExtremes(200)
    assert MinMaxShapes.FusedMin(mixed, 0, 200, int.MinValue, int.MaxValue) == MinMaxShapes.SeededMin(mixed, 0, 200, int.MinValue)
    assert MinMaxShapes.FusedMax(mixed, 0, 200, int.MinValue, int.MaxValue) == MinMaxShapes.SeededMax(mixed, 0, 200, int.MaxValue)
    assert MinMaxShapes.FusedMin(mixed, 0, 200, 0, 0) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, 0)
    assert MinMaxShapes.FusedMax(mixed, 0, 200, 0, 0) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, 0)
    assert MinMaxShapes.FusedMin(mixed, 0, 200, 7, 7) == ScalarMinMaxReference.DescendingMin(mixed, 0, 200, 7)
    assert MinMaxShapes.FusedMax(mixed, 0, 200, 7, 7) == ScalarMinMaxReference.DescendingMax(mixed, 0, 200, 7)
    assert MinMaxShapes.FusedMin(mixed, 0, 200, int.MaxValue, int.MinValue) == int.MinValue
    assert MinMaxShapes.FusedMax(mixed, 0, 200, int.MaxValue, int.MinValue) == int.MaxValue
}

test "an all-equal array collapses both accumulators onto that value" {
    equal := new int[200]
    for k := 0; k < 200; k++ {
        equal[k] = -42
    }
    assert MinMaxShapes.SeededMin(equal, 0, 200, int.MaxValue) == -42
    assert MinMaxShapes.SeededMax(equal, 0, 200, int.MinValue) == -42
    assert MinMaxShapes.FusedMin(equal, 0, 200, int.MaxValue, int.MinValue) == -42
    assert MinMaxShapes.FusedMax(equal, 0, 200, int.MaxValue, int.MinValue) == -42
    assert MinMaxShapes.ForTempDelta(equal, 200) == 0
}

test "an empty or inverted range returns the seeds untouched" {
    mixed := SampleData.MixedExtremes(200)
    assert MinMaxShapes.SeededMin(mixed, 5, 5, 99) == 99
    assert MinMaxShapes.SeededMax(mixed, 5, 5, 99) == 99
    assert MinMaxShapes.SeededMin(mixed, 10, 3, 99) == 99
    assert MinMaxShapes.SeededMax(mixed, 10, 3, 99) == 99
    assert MinMaxShapes.FusedMin(mixed, 5, 5, 11, 22) == 11
    assert MinMaxShapes.FusedMax(mixed, 5, 5, 11, 22) == 22
    assert MinMaxShapes.FusedMin(mixed, 10, 3, 11, 22) == 11
    assert MinMaxShapes.FusedMax(mixed, 10, 3, 11, 22) == 22
}

test "an empty or extreme-negative bound leaves both accumulators at their seeds" {
    signed := SampleData.SignedLike(100)
    assert MinMaxShapes.ForTempDelta(signed, int.MinValue) == 0
    assert MinMaxShapes.ForTempDelta(signed, -1) == 0
    assert MinMaxShapes.ForTempDelta(signed, 0) == 0
    assert MinMaxShapes.ForTempDelta(signed, 1) == 0
    assert MinMaxShapes.WhileTempDelta(signed, int.MinValue) == 0
    assert MinMaxShapes.WhileTempDelta(signed, 1) == 0
}

test "a bound past the end throws IndexOutOfRangeException exactly as the scalar loop does" {
    assert KernelRuns.ThrownTypeOf(() => MinMaxShapes.ForTempDelta(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => MinMaxShapes.WhileTempDelta(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => ScalarMinMaxReference.DescendingMin(new int[10], 0, 100, 0)) == "System.IndexOutOfRangeException"
}

test "the for-form near misses still compute their scalar min and max" {
    signed := SampleData.SignedLike(8)
    ascii := SampleData.AsciiLike(8)
    trueMin := ScalarMinMaxReference.DescendingMin(signed, 1, 8, signed[0])
    trueMax := ScalarMinMaxReference.DescendingMax(signed, 1, 8, signed[0])
    // A non-strict comparison still folds to the same minimum: it only differs in which equal element wins.
    assert MinMaxNearMisses.ForNonStrict(signed, 8) == trueMin
    // The offset assignment stores one more than the element that beat the running minimum.
    assert MinMaxNearMisses.ForAssignsOffsetValue(signed, 8) == int.MinValue + 1
    assert MinMaxNearMisses.ForIndexedByOther(signed, 8, 0) == signed[0]
    assert MinMaxNearMisses.ForTwoArrays(signed, signed, 8) == trueMax - trueMin
    assert MinMaxNearMisses.ForSameAccumulatorTwice(signed, 8) == signed[7]
    assert MinMaxNearMisses.ForExtraStatementInBody(signed, 8) == trueMax - trueMin
    assert MinMaxNearMisses.ForExtraStatementInIf(signed, 8) == trueMin
    assert MinMaxNearMisses.ForConstantCondition(ascii, 8) == ascii[0]
    assert MinMaxNearMisses.ForStrideTwo(signed, 8) == ScalarMinMaxReference.DescendingMin(signed, 1, 8, signed[0])
}

test "a start below zero reads a[-1] exactly as the scalar loop does" {
    // The helper's in-bounds fast path is guarded by `start >= 0 && end <= array.Length`, so a negative
    // start falls through to its scalar tail and throws what the scalar loop throws.
    assert KernelRuns.ThrownTypeOf(() => MinMaxShapes.ForInlinedFromStart(SampleData.SignedLike(8), -1, 0)) == "System.IndexOutOfRangeException"
    assert MinMaxShapes.ForInlinedFromStart(SampleData.SignedLike(8), 8, 99) == 0
    assert MinMaxShapes.ForInlinedFromStart(SampleData.SignedLike(8), 0, 7) == ScalarMinMaxReference.DescendingMax(SampleData.SignedLike(8), 0, 8, 7) - ScalarMinMaxReference.DescendingMin(SampleData.SignedLike(8), 0, 8, 7)
}

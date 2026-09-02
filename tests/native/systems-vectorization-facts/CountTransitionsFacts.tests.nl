namespace NSharpLang.SystemsVectorizationFacts.Tests


// SHAPE 4 OF 4: THE SHIFTED-COMPARE ADJACENT-TRANSITION COUNT (the count-transitions kernel).
//
// `ColumnarIlEmitter.TryMatchWhileCountTransitions` / `TryMatchForCountTransitions` accept a unit-stride
// counted loop whose body is EXACTLY three statements (four in the while form, counting the increment):
//
//     current := a[i]
//     if current != previous { count++ }     (either operand order; count++ / count += 1 / count = count + 1)
//     previous = current
//
// and `EmitVectorizedCountTransitions` replaces the loop with
//
//     (added, lastPrevious) = SimdReductions.CountTransitionsInt32(a, i, bound, previous)
//     count = count + added;  previous = lastPrevious;  if (i < bound) { i = bound }
//
// so BOTH carried scalars are restored: the count and the terminal `previous`. That second restore is what
// makes the lowering observationally equivalent for code that reads `previous` after the loop, and it has its
// own contract below.
//
// THE GUARDS, each of which has a negative below. The temp declaration must come first and read `a[index]`;
// its name must not already be a visible binding; the comparison must be `!=` between the temp and a carried
// identifier; the `if` must have no else and exactly one unit-count statement; the carry must be
// `previous = current` — the temp itself, not a re-read of `a[i]`, and not some other variable; counter,
// array, index, previous and current must be five DISTINCT names; the bound must not read the counter, the
// previous or the current; and — from `TryBuildCountTransitionsShape` — the counter, index and previous must
// be `int` and the array must be exactly `int[]`.
//
// HOW THE SHAPE CONTRACTS ARE MEASURED. Every "lowers to X" / "stays scalar" block below asks `IlShape`,
// which takes the kernel's own emitted `MethodInfo`, DECODES its IL, and resolves the metadata token of
// every `call` — the same instrument `tests/PerfEvidence/ILShapeInspector.cs` was, rebuilt in N#. So a
// positive names the exact helper the emitted method calls, a negative reads "" because no call token in
// that body resolves onto `SimdReductions`, and neither answer depends on the kernel being RUN: shapes whose
// loop body can never execute are read like any other. `IlShapeFacts.tests.nl` pins the decoder first.
//
// THE HELPER EDGE CASES REACH THE HELPER THROUGH THE PRODUCT PATH, for the reason recorded in
// `MinMaxFacts.tests.nl`: N# cannot import `NSharpLang.Runtime` (NL704), so the seed and the start are
// kernel PARAMETERS and the emitter passes both straight into the helper call.
//
// MAPPING — CountTransitionsShapeTests.cs (6 methods / 19 rows):
//   Matches_ForFormCountTransitions[count = count + 1, a.Length bound + count++,
//                                   reversed compare + count += 1]
//       -> "all three accepted for-form transition counts lower to CountTransitionsInt32"
//   Matches_WhileFormCountTransitions
//       -> "the accepted while-form transition count lowers to CountTransitionsInt32"
//   Rejects_NonCountTransitionsForShapes[else branch, == instead of !=, count += 2, missing carry,
//                                        carry re-reads a[i], carry writes another variable,
//                                        compare against a[i], a[j], extra body statement,
//                                        non-unit increment]
//       -> "the eleven for-form near misses stay scalar"
//          + "the for-form near misses still compute their scalar counts"
//   Rejects_NonCountTransitionsForShapes[loop-variant bound `i < i`]
//       -> "the eleven for-form near misses stay scalar" (its body can never RUN, so it is unobservable
//          from behaviour, but its IL is emitted all the same and the walker reads it like any other)
//   Rejects_BoundsWrittenByMatchedForLoopBody[previous, count]
//       -> "a bound the loop body rewrites keeps the loop scalar"
//   Rejects_BoundsWrittenByMatchedForLoopBody[current]
//       -> NOT PORTABLE: the deleted row needed an OUTER `current := 4` next to the loop's own
//          `current := a[i]`, and N# rejects the inner declaration as shadowing (NL316) before any matcher
//          runs. The guard itself is still covered by the `previous` and `count` rows, which take the same
//          `BoundReadsIdentifier` path. Recorded, not asserted.
//   Rejects_NonCountTransitionsWhileShapes[increment not last, missing carry]
//   Rejects_BoundsWrittenByMatchedWhileLoopBody
//       -> "the three while-form near misses stay scalar"
//
// MAPPING — CountTransitionsVectorizationTests.cs (11 methods / 23 rows):
//   VectorizedCountTransitions_IsValueIdenticalToScalar[1,2,7,8,15,16,17,33,64,1000]
//       -> "the vectorized transition count equals the scalar reference at every deleted length"
//   VectorizedCountTransitions_RestoresTerminalPrevious[1,8,17,64,1000]
//       -> "the lowering restores the carried previous as well as the count"
//   CountTransitions_LowersToOneHelperCall_OnlyWhenEnabled
//       -> the two "lower to CountTransitionsInt32" blocks
//   CountTransitions_MutableBoundFallsBackToScalar
//       -> "a bound the loop body rewrites keeps the loop scalar" (the 2022 case, value included)
//   CountTransitions_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar
//       -> "a bound past the end throws IndexOutOfRangeException exactly as the scalar loop does"
//   CountTransitions_NonIntArray_DoesNotVectorize_ButMatchesScalar
//       -> "a long[] array keeps the loop scalar and still counts transitions"
//   CountTransitionsHelperEdgeCaseTests.CountTransitionsInt32_SimdPath_MatchesScalar_AcrossSeeds[7,0,
//                                       MinValue,MaxValue]
//       -> "seeded transition scans match the scalar fold for every seed"
//   CountTransitionsInt32_PartialRange_MatchesScalar[(1,200),(0,200),(3,197),(50,150)]
//       -> "partial ranges scan exactly the requested window"
//   CountTransitionsInt32_AllEqual_IsZeroTransitions
//       -> "an all-equal array has no transitions unless the seed differs"
//   CountTransitionsInt32_AllDifferent_CountsEveryElement
//       -> "a strictly increasing array transitions on every element"
//   CountTransitionsInt32_EmptyRange_ReturnsSeed
//       -> "an empty or inverted range counts nothing and returns the seed"

class TransitionShapes {
    // The count-transitions benchmark shape: for, seeded from a[0], scanning [1, n).
    static func ForCount(a: int[], n: int): int {
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
    }

    // for, a.Length bound, `count++`.
    static func ForLengthBound(a: int[]): int {
        count := 0
        previous := a[0]
        for i := 1; i < a.Length; i++ {
            current := a[i]
            if current != previous {
                count++
            }

            previous = current
        }
        return count
    }

    // The a.Length bound entered from a caller-supplied start, so it can be driven past its START (an
    // a.Length bound can never be driven past the END of its own array).
    static func ForLengthBoundFromStart(a: int[], start: int, seed: int): int {
        count := 0
        previous := seed
        for i := start; i < a.Length; i++ {
            current := a[i]
            if current != previous {
                count++
            }

            previous = current
        }
        return count
    }

    // for, reversed compare operand order, `count += 1`.
    static func ForReversedCompare(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if previous != current {
                count += 1
            }

            previous = current
        }
        return count
    }

    static func WhileCount(a: int[], n: int): int {
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
    }

    // Returns the TERMINAL `previous`, which the lowering must restore from the helper's second result.
    static func ForTerminalPrevious(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return previous + count - count
    }

    // The seeded, partial-range forms: `start` and `seed` reach the helper unchanged.
    static func SeededCount(a: int[], start: int, n: int, seed: int): int {
        count := 0
        previous := seed
        for i := start; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    static func SeededPrevious(a: int[], start: int, n: int, seed: int): int {
        count := 0
        previous := seed
        for i := start; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return previous + count - count
    }
}

class TransitionNearMisses {
    static func ForElseBranch(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            } else {
                count = count - 1
            }

            previous = current
        }
        return count
    }

    // `==` counts equal adjacents — a different predicate entirely.
    static func ForEqualityCompare(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current == previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    static func ForCounterStepTwo(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count += 2
            }

            previous = current
        }
        return count
    }

    // No carry: `previous` never advances, so this counts elements differing from a[0].
    static func ForMissingCarry(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }
        }
        return count
    }

    // The carry re-reads the array instead of reusing the temp, which the matcher requires.
    static func ForCarryRereadsArray(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = a[i]
        }
        return count
    }

    // The carry writes some other variable, so `previous` is not actually carried.
    static func ForCarryWritesOther(a: int[], n: int): int {
        count := 0
        previous := a[0]
        other := 0
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            other = current
        }
        return count + other - other
    }

    // The comparison's right operand is an indexed read, not a carried identifier, so nothing is shifted.
    static func ForComparesArrayDirectly(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != a[i] {
                count = count + 1
            }

            previous = current
        }
        return count + previous - previous
    }

    static func ForIndexedByOther(a: int[], n: int, j: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[j]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    // A fourth statement in the loop body.
    static func ForExtraStatement(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
            count = count + 0
        }
        return count
    }

    // A self-referential bound: the body can never be entered.
    static func ForSelfBound(a: int[]): int {
        count := 0
        previous := a[0]
        for i := 1; i < i; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    static func ForStrideTwo(a: int[], n: int): int {
        count := 0
        previous := a[0]
        for i := 1; i < n; i += 2 {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    // The bound IS the carried value, which the body rewrites every iteration.
    static func ForBoundIsPrevious(a: int[]): int {
        count := 0
        previous := 4
        for i := 0; i < previous; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    // The bound IS the counter, which the body rewrites when it counts.
    static func ForBoundIsCounter(a: int[], seed: int): int {
        count := 2
        previous := seed
        for i := 0; i < count; i++ {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            previous = current
        }
        return count
    }

    // The deleted `mutablePreviousBound` fact, spelled exactly: a while-form loop whose bound is the carried
    // value, returning a packed `count * 1000 + i * 10 + previous` so all three carried scalars are pinned.
    static func WhileBoundIsPrevious(a: int[]): int {
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
    }

    // while: the increment is not last (the carry follows it).
    static func WhileIncrementBeforeCarry(a: int[], n: int): int {
        count := 0
        previous := a[0]
        i := 1
        while i < n {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            i = i + 1
            previous = current
        }
        return count
    }

    // while: no carry at all.
    static func WhileMissingCarry(a: int[], n: int): int {
        count := 0
        previous := a[0]
        i := 1
        while i < n {
            current := a[i]
            if current != previous {
                count = count + 1
            }

            i = i + 1
        }
        return count
    }

    // A long[] array.
    static func ForLongArray(a: long[], n: int): int {
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
    }
}

// The oracle: the same adjacent-pair predicate walked in descending index order, comparing each element with
// its PREDECESSOR (or with the seed at the window's first element). No matcher accepts a `>=` condition.
class ScalarTransitionReference {
    static func DescendingCount(a: int[], start: int, n: int, seed: int): int {
        count := 0
        for i := n - 1; i >= start; i-- {
            predecessor := seed
            if i > start {
                predecessor = a[i - 1]
            }

            if a[i] != predecessor {
                count = count + 1
            }
        }
        return count
    }

    static func TerminalPrevious(a: int[], start: int, n: int, seed: int): int {
        if n > start {
            return a[n - 1]
        }

        return seed
    }

    static func DescendingCountLong(a: long[], start: int, n: int, seed: long): int {
        count := 0
        for i := n - 1; i >= start; i-- {
            predecessor := seed
            if i > start {
                predecessor = a[i - 1]
            }

            if a[i] != predecessor {
                count = count + 1
            }
        }
        return count
    }
}

// The first length in [1, limit] at which any accepted transition-count form disagrees with the oracle, or -1.
func FirstTransitionMismatch(limit: int): int {
    for n := 1; n <= limit; n++ {
        data := SampleData.RunsLike(n)
        expected := ScalarTransitionReference.DescendingCount(data, 1, n, data[0])
        if TransitionShapes.ForCount(data, n) != expected {
            return n
        }

        if TransitionShapes.ForReversedCompare(data, n) != expected {
            return n
        }

        if TransitionShapes.WhileCount(data, n) != expected {
            return n
        }

        if TransitionShapes.ForLengthBound(data) != expected {
            return n
        }

        if TransitionShapes.ForTerminalPrevious(data, n) != ScalarTransitionReference.TerminalPrevious(data, 1, n, data[0]) {
            return n
        }

        runs := SampleData.RunsWithRepeats(n)
        if TransitionShapes.ForCount(runs, n) != ScalarTransitionReference.DescendingCount(runs, 1, n, runs[0]) {
            return n
        }

        if TransitionShapes.WhileCount(runs, n) != ScalarTransitionReference.DescendingCount(runs, 1, n, runs[0]) {
            return n
        }
    }
    return -1
}

// ---- Shapes: what the emitted IL actually calls -----------------------------------------------------

test "all three accepted for-form transition counts lower to CountTransitionsInt32" {
    assert IlShape.SimdCalls(typeof(TransitionShapes), "ForCount") == "CountTransitionsInt32"
    assert IlShape.SimdCalls(typeof(TransitionShapes), "ForReversedCompare") == "CountTransitionsInt32"
    assert IlShape.SimdCalls(typeof(TransitionShapes), "ForLengthBound") == "CountTransitionsInt32"
    assert IlShape.SimdCalls(typeof(TransitionShapes), "ForLengthBoundFromStart") == "CountTransitionsInt32"
    assert IlShape.CallCount(typeof(TransitionShapes), "ForCount") == 1
    // `ForCount` keeps exactly the one `a[0]` seed read that sits OUTSIDE the loop; the loop's own
    // `current := a[i]` load is gone. `ForLengthBoundFromStart` takes its seed as a parameter instead, so it
    // has no element load left at all.
    assert IlShape.OpcodeCount(typeof(TransitionShapes), "ForCount", IlEncoding.LdelemI4()) == 1
    assert IlShape.OpcodeCount(typeof(TransitionShapes), "ForLengthBoundFromStart", IlEncoding.LdelemI4()) == 0
    assert IlShape.DecodesToRet(typeof(TransitionShapes), "ForCount")
}

test "the accepted while-form transition count lowers to CountTransitionsInt32" {
    assert IlShape.SimdCalls(typeof(TransitionShapes), "WhileCount") == "CountTransitionsInt32"
    assert IlShape.SimdCalls(typeof(TransitionShapes), "SeededCount") == "CountTransitionsInt32"
    assert IlShape.SimdCalls(typeof(TransitionShapes), "SeededPrevious") == "CountTransitionsInt32"
    assert IlShape.SimdCalls(typeof(TransitionShapes), "ForTerminalPrevious") == "CountTransitionsInt32"
    assert IlShape.CallCount(typeof(TransitionShapes), "WhileCount") == 1
}

test "the eleven for-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForElseBranch") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForEqualityCompare") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForCounterStepTwo") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForMissingCarry") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForCarryRereadsArray") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForCarryWritesOther") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForComparesArrayDirectly") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForIndexedByOther") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForExtraStatement") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForStrideTwo") == ""
    // The self-referential bound `for i := 1; i < i; i++`. Its body can never RUN, so nothing about it is
    // observable from behaviour — but its IL is emitted all the same, and reading it shows the scalar loop
    // standing where a helper call would be.
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForSelfBound") == ""
    assert IlShape.OpcodeCount(typeof(TransitionNearMisses), "ForSelfBound", IlEncoding.LdelemI4()) == 2
    assert IlShape.CallCount(typeof(TransitionNearMisses), "ForElseBranch") == 0
    assert IlShape.DecodesToRet(typeof(TransitionNearMisses), "ForSelfBound")
}

test "a bound the loop body rewrites keeps the loop scalar" {
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForBoundIsPrevious") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForBoundIsCounter") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "WhileBoundIsPrevious") == ""
    // The deleted `CountTransitions_MutableBoundFallsBackToScalar` case, value for value: over {3,2,2,2} the
    // scalar loop makes two transitions, stops with i == 2 and previous == 2, so the packed answer is 2022.
    mutableData := new int[4]
    mutableData[0] = 3
    mutableData[1] = 2
    mutableData[2] = 2
    mutableData[3] = 2
    assert TransitionNearMisses.WhileBoundIsPrevious(mutableData) == 2022
}

test "the three while-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "WhileIncrementBeforeCarry") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "WhileMissingCarry") == ""
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "WhileBoundIsPrevious") == ""
    assert IlShape.DecodesToRet(typeof(TransitionNearMisses), "WhileMissingCarry")
}

test "a long[] array keeps the loop scalar and still counts transitions" {
    assert IlShape.SimdCalls(typeof(TransitionNearMisses), "ForLongArray") == ""
    assert IlShape.OpcodeCount(typeof(TransitionNearMisses), "ForLongArray", IlEncoding.LdelemI8()) == 2
    runs := SampleData.RunsLongs(64)
    assert TransitionNearMisses.ForLongArray(runs, 64) == ScalarTransitionReference.DescendingCountLong(runs, 1, 64, runs[0])
}

test "the transition oracle is itself free of any SimdReductions call" {
    assert IlShape.SimdCalls(typeof(ScalarTransitionReference), "DescendingCount") == ""
    assert IlShape.SimdCalls(typeof(ScalarTransitionReference), "DescendingCountLong") == ""
    assert IlShape.OpcodeCount(typeof(ScalarTransitionReference), "DescendingCount", IlEncoding.LdelemI4()) == 2
}

// ---- Values: the lowering is value-identical to the scalar loop -------------------------------------

test "the vectorized transition count equals the scalar reference at every deleted length" {
    assert FirstTransitionMismatch(33) == -1
    runs64 := SampleData.RunsLike(64)
    runs1000 := SampleData.RunsLike(1000)
    assert TransitionShapes.ForCount(runs64, 64) == ScalarTransitionReference.DescendingCount(runs64, 1, 64, runs64[0])
    assert TransitionShapes.WhileCount(runs64, 64) == ScalarTransitionReference.DescendingCount(runs64, 1, 64, runs64[0])
    assert TransitionShapes.ForCount(runs1000, 1000) == ScalarTransitionReference.DescendingCount(runs1000, 1, 1000, runs1000[0])
    assert TransitionShapes.WhileCount(runs1000, 1000) == ScalarTransitionReference.DescendingCount(runs1000, 1, 1000, runs1000[0])
}

test "the lowering restores the carried previous as well as the count" {
    runs1 := SampleData.RunsLike(1)
    runs8 := SampleData.RunsLike(8)
    runs17 := SampleData.RunsLike(17)
    runs64 := SampleData.RunsLike(64)
    runs1000 := SampleData.RunsLike(1000)
    assert TransitionShapes.ForTerminalPrevious(runs1, 1) == runs1[0]
    assert TransitionShapes.ForTerminalPrevious(runs8, 8) == runs8[7]
    assert TransitionShapes.ForTerminalPrevious(runs17, 17) == runs17[16]
    assert TransitionShapes.ForTerminalPrevious(runs64, 64) == runs64[63]
    assert TransitionShapes.ForTerminalPrevious(runs1000, 1000) == runs1000[999]
    // An empty window leaves the carried value at its seed rather than at some element.
    assert TransitionShapes.SeededPrevious(runs8, 5, 5, 99) == 99
    assert TransitionShapes.SeededPrevious(runs8, 8, 3, 99) == 99
}

test "seeded transition scans match the scalar fold for every seed" {
    mixed := SampleData.MixedExtremes(200)
    assert TransitionShapes.SeededCount(mixed, 0, 200, 7) == ScalarTransitionReference.DescendingCount(mixed, 0, 200, 7)
    assert TransitionShapes.SeededCount(mixed, 0, 200, 0) == ScalarTransitionReference.DescendingCount(mixed, 0, 200, 0)
    assert TransitionShapes.SeededCount(mixed, 0, 200, int.MinValue) == ScalarTransitionReference.DescendingCount(mixed, 0, 200, int.MinValue)
    assert TransitionShapes.SeededCount(mixed, 0, 200, int.MaxValue) == ScalarTransitionReference.DescendingCount(mixed, 0, 200, int.MaxValue)
    assert TransitionShapes.SeededPrevious(mixed, 0, 200, 7) == mixed[199]
}

test "partial ranges scan exactly the requested window" {
    mixed := SampleData.MixedExtremes(200)
    assert TransitionShapes.SeededCount(mixed, 1, 200, mixed[0]) == ScalarTransitionReference.DescendingCount(mixed, 1, 200, mixed[0])
    assert TransitionShapes.SeededCount(mixed, 0, 200, mixed[0]) == ScalarTransitionReference.DescendingCount(mixed, 0, 200, mixed[0])
    assert TransitionShapes.SeededCount(mixed, 3, 197, mixed[2]) == ScalarTransitionReference.DescendingCount(mixed, 3, 197, mixed[2])
    assert TransitionShapes.SeededCount(mixed, 50, 150, mixed[49]) == ScalarTransitionReference.DescendingCount(mixed, 50, 150, mixed[49])
}

test "an all-equal array has no transitions unless the seed differs" {
    equal := new int[200]
    for k := 0; k < 200; k++ {
        equal[k] = 42
    }
    assert TransitionShapes.SeededCount(equal, 0, 200, 42) == 0
    assert TransitionShapes.SeededPrevious(equal, 0, 200, 42) == 42
    assert TransitionShapes.SeededCount(equal, 0, 200, 7) == 1
    assert TransitionShapes.SeededPrevious(equal, 0, 200, 7) == 42
}

test "a strictly increasing array transitions on every element" {
    increasing := new int[200]
    for k := 0; k < 200; k++ {
        increasing[k] = k
    }
    assert TransitionShapes.SeededCount(increasing, 0, 200, -1) == 200
    assert TransitionShapes.SeededPrevious(increasing, 0, 200, -1) == 199
}

test "an empty or inverted range counts nothing and returns the seed" {
    mixed := SampleData.MixedExtremes(200)
    assert TransitionShapes.SeededCount(mixed, 5, 5, 99) == 0
    assert TransitionShapes.SeededPrevious(mixed, 5, 5, 99) == 99
    assert TransitionShapes.SeededCount(mixed, 10, 3, 99) == 0
    assert TransitionShapes.SeededPrevious(mixed, 10, 3, 99) == 99
}

test "a bound past the end throws IndexOutOfRangeException exactly as the scalar loop does" {
    assert KernelRuns.ThrownTypeOf(() => TransitionShapes.ForCount(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => TransitionShapes.WhileCount(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => ScalarTransitionReference.DescendingCount(new int[10], 0, 100, 7)) == "System.IndexOutOfRangeException"
}

test "the for-form near misses still compute their scalar counts" {
    // A dataset with real runs, so "counts differing ADJACENT pairs" and "counts elements differing from
    // a[0]" give different answers and the missing-carry near miss is actually distinguishable.
    runs := SampleData.RunsWithRepeats(24)
    transitions := ScalarTransitionReference.DescendingCount(runs, 1, 24, runs[0])
    assert transitions == 9
    assert TransitionNearMisses.ForElseBranch(runs, 24) == transitions - (23 - transitions)
    assert TransitionNearMisses.ForEqualityCompare(runs, 24) == 23 - transitions
    assert TransitionNearMisses.ForCounterStepTwo(runs, 24) == 2 * transitions
    assert TransitionNearMisses.ForMissingCarry(runs, 24) == 18
    assert TransitionNearMisses.ForCarryWritesOther(runs, 24) == 18
    assert TransitionNearMisses.ForCarryRereadsArray(runs, 24) == transitions
    assert TransitionNearMisses.ForComparesArrayDirectly(runs, 24) == 0
    assert TransitionNearMisses.ForIndexedByOther(runs, 24, 0) == 0
    assert TransitionNearMisses.ForExtraStatement(runs, 24) == transitions
    assert TransitionNearMisses.ForStrideTwo(runs, 24) == 7
}

test "a bound that is the counter is read live on every iteration" {
    // The counter starts at 2 and the body raises it whenever it counts, so a seed that differs from the
    // first element buys the loop one extra iteration. A snapshotted bound would stop one short.
    equal := new int[4]
    for k := 0; k < 4; k++ {
        equal[k] = 5
    }
    assert TransitionNearMisses.ForBoundIsCounter(equal, 5) == 2
    assert TransitionNearMisses.ForBoundIsCounter(equal, 9) == 3
}

test "genuine runs are counted as adjacent differences rather than as distinct elements" {
    runs := SampleData.RunsWithRepeats(24)
    // Three-element runs over 24 elements give 7 boundaries, plus the two the planted int.MinValue pair adds
    // at positions 7 and 9 — and the pair itself is NOT a transition, which is what a shifted compare must
    // get right.
    assert TransitionShapes.ForCount(runs, 24) == 9
    assert runs[7] == runs[8]
    assert TransitionShapes.ForCount(runs, 24) == ScalarTransitionReference.DescendingCount(runs, 1, 24, runs[0])
    assert TransitionShapes.WhileCount(runs, 24) == 9
    big := SampleData.RunsWithRepeats(1000)
    assert TransitionShapes.ForCount(big, 1000) == ScalarTransitionReference.DescendingCount(big, 1, 1000, big[0])
    assert TransitionShapes.ForTerminalPrevious(big, 1000) == big[999]
}

test "a start below zero reads a[-1] exactly as the scalar loop does" {
    // The helper's in-bounds fast path is guarded by `start >= 0 && end <= array.Length`, so a negative
    // start falls through to its scalar tail and throws what the scalar loop throws.
    assert KernelRuns.ThrownTypeOf(() => TransitionShapes.ForLengthBoundFromStart(SampleData.RunsWithRepeats(8), -1, 0)) == "System.IndexOutOfRangeException"
    assert TransitionShapes.ForLengthBoundFromStart(SampleData.RunsWithRepeats(8), 8, 99) == 0
    assert TransitionShapes.ForLengthBoundFromStart(SampleData.RunsWithRepeats(8), 0, SampleData.RunsWithRepeats(8)[0]) == ScalarTransitionReference.DescendingCount(SampleData.RunsWithRepeats(8), 0, 8, SampleData.RunsWithRepeats(8)[0])
}

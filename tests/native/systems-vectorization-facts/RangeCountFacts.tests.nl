namespace NSharpLang.SystemsVectorizationFacts.Tests


// SHAPE 2 OF 4: THE MASKED-SIMD RANGE-PREDICATE COUNT (the count-ascii kernel).
//
// `ColumnarIlEmitter.TryMatchWhileRangeCount` / `TryMatchForRangeCount` accept a unit-stride counted loop
// whose body is either
//
//     value := a[i];  if value >= lo && value <= hi { count++ }        (the temp-subject form)
//     if a[i] >= lo && a[i] <= hi { count++ }                          (the inlined-subject form)
//
// with the counter incremented by exactly one (`count++`, `count += 1` or `count = count + 1`), and
// `EmitVectorizedRangeCount` replaces the loop with
//
//     count = count + SimdReductions.CountInRangeInt32(a, i, bound, lo, hi);  if (i < bound) { i = bound }
//
// evaluating `bound`, `lo` and `hi` into temporaries ONCE, in that order, before the call.
//
// THE GUARDS, each of which has a negative below. The predicate must be `&&` of a `>=` and a `<=` in that
// order (so the matched set is exactly the helper's inclusive range); the `if` must have no else and exactly
// one statement in its body; the loop body must be the `if` alone or a temp declaration plus the `if` (plus
// the increment, in the while form); both comparisons must read the SAME array through the loop index, or
// both must read the temp; `lo` and `hi` must be loop-invariant (not the index, the counter or the temp);
// counter, array and index must be three distinct names, none of them the temp; the bound must not read the
// counter or the temp; and — from `TryBuildRangeCountShape` — the counter and index must be `int` and the
// array must be exactly `int[]`.
//
// The temp form additionally requires that the temp's name is not already a visible binding
// (`IsVisibleBindingName`), which is why the accepted kernels below declare `value` inside the loop.
//
// WHY THIS ROUTE IS STRONGER. `RangePredicateCountShapeTests` asserted `TryMatch(...) != null` on a parsed
// AST — a detector answer with no emission behind it. Here the kernels are compiled by the product build,
// their emitted IL is read back, and they are then RUN, so an accepted shape has to survive analysis,
// emission AND execution, and a rejection is pinned by what the emitter actually produced rather than by
// what a detector said about a syntax tree.
//
// HOW THE SHAPE CONTRACTS ARE MEASURED. Every "lowers to X" / "stays scalar" block below asks `IlShape`,
// which takes the kernel's own emitted `MethodInfo`, DECODES its IL, and resolves the metadata token of
// every `call` — the same instrument `tests/PerfEvidence/ILShapeInspector.cs` was, rebuilt in N#. So a
// positive names the exact helper the emitted method calls, a negative reads "" because no call token in
// that body resolves onto `SimdReductions`, and neither answer depends on the kernel being RUN: shapes whose
// loop body can never execute are read like any other. `IlShapeFacts.tests.nl` pins the decoder first.
//
// THE DIRECT-HELPER TESTS ARE COVERED THROUGH THE PRODUCT PATH. `CountInRangeHelperEdgeCaseTests` called
// `SimdReductions.CountInRangeInt32` itself; N# cannot (`import NSharpLang.Runtime` reports NL704 — the
// runtime assembly is not an importable namespace on this emit path), so those six ranges are driven through
// a vectorized kernel instead, which reaches the same helper with the same arguments and additionally proves
// the emitter passes `lo` and `hi` through in the right order.
//
// MAPPING — RangePredicateCountShapeTests.cs (4 methods / 21 rows):
//   Matches_WhileFormRangeCount[temp + literal bounds + count = count + 1,
//                               inlined + param bounds + count += 1,
//                               temp + a.Length bound + count++]
//       -> "all three accepted while-form range counts lower to CountInRangeInt32"
//   Matches_ForFormRangeCount[temp + literal bounds, inlined + param bounds + count++,
//                             a.Length bound + count += 1]
//       -> "all three accepted for-form range counts lower to CountInRangeInt32"
//   Rejects_NonRangeCountForShapes[else branch, exclusive comparisons, OR, count += 2, count = count + 2,
//                                  extra statement in the if body, extra statement in the loop body,
//                                  a[j], two arrays, lo reads the loop index, temp but the predicate compares
//                                  another variable, the bound IS the counter]
//       -> "the twelve for-form near misses stay scalar"
//          + "the for-form near misses still compute their scalar counts"
//   Rejects_NonRangeCountWhileShapes[missing increment, count += 2, the bound IS the counter]
//       -> "the three while-form near misses stay scalar"
//
// MAPPING — RangePredicateCountVectorizationTests.cs (8 methods / 25 rows):
//   VectorizedCountAscii_IsValueIdenticalToScalar[0,1,2,7,8,15,16,17,64,1000]
//       -> "the vectorized ascii count equals the scalar reference at every deleted length"
//   VectorizedRangeCount_InlinedAndWhileForms_MatchScalar[8,17,64,1000]
//       -> "the inlined-subject and while forms agree with the scalar reference"
//   RangeCount_LowersToHelperCall_OnlyWhenEnabled[for, while]
//       -> the two "lower to CountInRangeInt32" blocks
//   RangeCount_BoundExceedsLength_ThrowsIndexOutOfRange_LikeScalar
//       -> "a bound past the end throws IndexOutOfRangeException exactly as the scalar loop does"
//   RangeCount_EmptyOrNegativeBound_MatchesScalar_NoOutOfBoundsRead[int.MinValue,-1,0]
//       -> "an empty or extreme-negative bound counts nothing and reads nothing"
//   RangeCount_NonIntBound_DoesNotVectorize_ButMatchesScalar
//   RangeCount_NonIntArray_DoesNotVectorize_ButMatchesScalar
//       -> "a long bound and a long[] array both keep the loop scalar and still count correctly"
//   CountInRangeHelperEdgeCaseTests.CountInRangeInt32_SimdPath_MatchesScalar[(150,100),(105,105),(-50,50),
//                                   (MinValue,0),(0,MaxValue),(MinValue,MaxValue)]
//       -> "the six helper edge ranges count identically through the vectorized kernel"
class RangeCountShapes {

    // while, temp subject, literal inclusive bounds, `count = count + 1` — the count-ascii kernel.
    static func WhileTempLiteral(a: int[], n: int): int {
        count := 0
        i := 0
        while i < n {
            value := a[i]
            if value >= 32 && value <= 126 {
                count = count + 1
            }

            i = i + 1
        }
        return count
    }

    // while, inlined subject, parameter bounds, `count += 1`.
    static func WhileInlinedParam(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        i := 0
        while i < n {
            if a[i] >= lo && a[i] <= hi {
                count += 1
            }

            i = i + 1
        }
        return count
    }

    // while, temp subject, a.Length bound, `count++`.
    static func WhileLengthBound(a: int[], lo: int, hi: int): int {
        count := 0
        i := 0
        while i < a.Length {
            value := a[i]
            if value >= lo && value <= hi {
                count++
            }

            i = i + 1
        }
        return count
    }

    // The a.Length bound entered from a caller-supplied start. It carries the negative-start contract:
    // `SimdReductions` takes the loop's `[start, bound)` unchanged, so a start below zero must skip the
    // in-bounds SIMD fast path and reproduce the scalar loop's read of `a[-1]`.
    static func ForLengthBoundFromStart(a: int[], start: int, lo: int, hi: int): int {
        count := 0
        for i := start; i < a.Length; i++ {
            value := a[i]
            if value >= lo && value <= hi {
                count += 1
            }
        }
        return count
    }

    // for, temp subject, literal inclusive bounds.
    static func ForTempLiteral(a: int[], n: int): int {
        count := 0
        for i := 0; i < n; i++ {
            value := a[i]
            if value >= 32 && value <= 126 {
                count = count + 1
            }
        }
        return count
    }

    // for, inlined subject, parameter bounds, `count++`.
    static func ForInlinedParam(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count++
            }
        }
        return count
    }

    // for, temp subject, a.Length bound, `count += 1`.
    static func ForLengthBound(a: int[], lo: int, hi: int): int {
        count := 0
        for i := 0; i < a.Length; i++ {
            value := a[i]
            if value >= lo && value <= hi {
                count += 1
            }
        }
        return count
    }
}

class RangeCountNearMisses {

    // An else branch: the `if` node must have exactly two children.
    static func ForElseBranch(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count++
            } else {
                count = count - 1
            }
        }
        return count
    }

    // `>` / `<` select a different set than the helper's inclusive compare.
    static func ForExclusiveComparisons(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] > lo && a[i] < hi {
                count++
            }
        }
        return count
    }

    // `||` is a union, not a range.
    static func ForDisjunction(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo || a[i] <= hi {
                count++
            }
        }
        return count
    }

    // `count += 2` is not a unit count.
    static func ForCounterStepTwo(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count += 2
            }
        }
        return count
    }

    // `count = count + 2` — the same rejection through the assignment spelling.
    static func ForCounterPlusTwo(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count = count + 2
            }
        }
        return count
    }

    // Two statements in the if body.
    static func ForExtraStatementInIf(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count++
                count++
            }
        }
        return count
    }

    // A third statement in the loop body, beyond the temp and the `if`.
    static func ForExtraStatementInBody(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            value := a[i]
            if value >= lo && value <= hi {
                count++
            }

            count = count + 0
        }
        return count
    }

    // Indexed by a binding that is not the loop index.
    static func ForIndexedByOther(a: int[], n: int, lo: int, hi: int, j: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[j] >= lo && a[j] <= hi {
                count++
            }
        }
        return count
    }

    // The two comparisons read two different arrays.
    static func ForTwoArrays(a: int[], b: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && b[i] <= hi {
                count++
            }
        }
        return count
    }

    // A loop-variant lower bound: `lo` is the index itself.
    static func ForLoopVariantBound(a: int[], n: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= i && a[i] <= hi {
                count++
            }
        }
        return count
    }

    // A temp subject whose upper comparison is against a different variable, so the two halves of the
    // predicate do not describe one element. (The deleted row compared BOTH halves against `i`; that shape
    // would leave `value` written and never read, which N# reports as an unused binding, so the closest
    // legal spelling keeps the lower half on the temp.)
    static func ForTempWithForeignSubject(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            value := a[i]
            if value >= lo && i <= hi {
                count++
            }
        }
        return count
    }

    // H1: the bound IS the counter, which the body rewrites — the helper would snapshot it once and scan a
    // different element set than the scalar loop.
    static func ForBoundIsCounter(a: int[], lo: int, hi: int): int {
        count := 4
        for i := 0; i < count; i++ {
            if a[i] >= lo && a[i] <= hi {
                count++
            }
        }
        return count
    }

    // while: the last body statement is not the index increment (there is no increment at all).
    static func WhileMissingIncrement(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        i := 0
        while i < n {
            if a[i] >= lo && a[i] <= hi {
                count++
            }
        }
        return count
    }

    // while: `count += 2`.
    static func WhileCounterStepTwo(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        i := 0
        while i < n {
            if a[i] >= lo && a[i] <= hi {
                count += 2
            }

            i = i + 1
        }
        return count
    }

    // while: the bound IS the counter.
    static func WhileBoundIsCounter(a: int[], lo: int, hi: int): int {
        count := 4
        i := 0
        while i < count {
            if a[i] >= lo && a[i] <= hi {
                count++
            }

            i = i + 1
        }
        return count
    }

    // A `long` lower bound promotes the comparison, so `IsSideEffectFreeInt32Operand` refuses it: the helper
    // compares int lanes.
    static func ForLongBound(a: int[], n: int, lo: long, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count++
            }
        }
        return count
    }

    // A `long[]` array: `TryBuildRangeCountShape` requires exactly `int[]`.
    static func ForLongArray(a: long[], n: int, lo: int, hi: int): int {
        count := 0
        for i := 0; i < n; i++ {
            if a[i] >= lo && a[i] <= hi {
                count++
            }
        }
        return count
    }
}

// The oracle: the same inclusive predicate counted in descending index order, which no matcher accepts
// (`TryMatchReductionCondition` requires `<`). Its scalar-ness is asserted below.
class ScalarRangeReference {
    static func DescendingCount(a: int[], n: int, lo: int, hi: int): int {
        count := 0
        for i := n - 1; i >= 0; i-- {
            if a[i] >= lo && a[i] <= hi {
                count = count + 1
            }
        }
        return count
    }

    static func DescendingCountLong(a: long[], n: int, lo: int, hi: int): int {
        count := 0
        for i := n - 1; i >= 0; i-- {
            if a[i] >= lo && a[i] <= hi {
                count = count + 1
            }
        }
        return count
    }
}

// The first length in [0, limit] at which any accepted range-count form disagrees with the oracle, or -1.
func FirstRangeCountMismatch(limit: int): int {
    for n := 0; n <= limit; n++ {
        data := SampleData.AsciiLike(n)
        expected := ScalarRangeReference.DescendingCount(data, n, 32, 126)
        if RangeCountShapes.WhileTempLiteral(data, n) != expected {
            return n
        }

        if RangeCountShapes.ForTempLiteral(data, n) != expected {
            return n
        }

        if RangeCountShapes.WhileInlinedParam(data, n, 32, 126) != expected {
            return n
        }

        if RangeCountShapes.ForInlinedParam(data, n, 32, 126) != expected {
            return n
        }

        if RangeCountShapes.WhileLengthBound(data, 32, 126) != expected {
            return n
        }

        if RangeCountShapes.ForLengthBound(data, 32, 126) != expected {
            return n
        }
    }
    return -1
}

// ---- Shapes: what the emitted IL actually calls -----------------------------------------------------

test "all three accepted while-form range counts lower to CountInRangeInt32" {
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "WhileTempLiteral") == "CountInRangeInt32"
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "WhileInlinedParam") == "CountInRangeInt32"
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "WhileLengthBound") == "CountInRangeInt32"
    assert IlShape.CallCount(typeof(RangeCountShapes), "WhileTempLiteral") == 1
    assert IlShape.OpcodeCount(typeof(RangeCountShapes), "WhileTempLiteral", IlEncoding.LdelemI4()) == 0
    assert IlShape.DecodesToRet(typeof(RangeCountShapes), "WhileTempLiteral")
}

test "all three accepted for-form range counts lower to CountInRangeInt32" {
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "ForTempLiteral") == "CountInRangeInt32"
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "ForInlinedParam") == "CountInRangeInt32"
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "ForLengthBound") == "CountInRangeInt32"
    assert IlShape.SimdCalls(typeof(RangeCountShapes), "ForLengthBoundFromStart") == "CountInRangeInt32"
    assert IlShape.CallCount(typeof(RangeCountShapes), "ForTempLiteral") == 1
    assert IlShape.OpcodeCount(typeof(RangeCountShapes), "ForTempLiteral", IlEncoding.LdelemI4()) == 0
}

test "the twelve for-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForElseBranch") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForExclusiveComparisons") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForDisjunction") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForCounterStepTwo") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForCounterPlusTwo") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForExtraStatementInIf") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForExtraStatementInBody") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForIndexedByOther") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForTwoArrays") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForLoopVariantBound") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForTempWithForeignSubject") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForBoundIsCounter") == ""
    // A rejected loop keeps the scalar element load and makes no call at all.
    assert IlShape.CallCount(typeof(RangeCountNearMisses), "ForElseBranch") == 0
    assert IlShape.OpcodeCount(typeof(RangeCountNearMisses), "ForElseBranch", IlEncoding.LdelemI4()) == 2
    assert IlShape.DecodesToRet(typeof(RangeCountNearMisses), "ForBoundIsCounter")
}

test "the three while-form near misses stay scalar" {
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "WhileMissingIncrement") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "WhileCounterStepTwo") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "WhileBoundIsCounter") == ""
    // The missing-increment loop is an infinite loop at run time, which is exactly why reading its IL is the
    // only way to assert its shape: the deleted detector test could inspect it because it never ran it.
    assert IlShape.CallCount(typeof(RangeCountNearMisses), "WhileMissingIncrement") == 0
    assert IlShape.DecodesToRet(typeof(RangeCountNearMisses), "WhileMissingIncrement")
}

test "a long bound and a long[] array both keep the loop scalar and still count correctly" {
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForLongBound") == ""
    assert IlShape.SimdCalls(typeof(RangeCountNearMisses), "ForLongArray") == ""
    assert IlShape.OpcodeCount(typeof(RangeCountNearMisses), "ForLongArray", IlEncoding.LdelemI8()) == 2
    ascii := SampleData.AsciiLike(64)
    assert RangeCountNearMisses.ForLongBound(ascii, 64, (long)32, 126) == ScalarRangeReference.DescendingCount(ascii, 64, 32, 126)
    runs := SampleData.RunsLongs(64)
    assert RangeCountNearMisses.ForLongArray(runs, 64, 0, 2) == ScalarRangeReference.DescendingCountLong(runs, 64, 0, 2)
}

test "the range-count oracle is itself free of any SimdReductions call" {
    assert IlShape.SimdCalls(typeof(ScalarRangeReference), "DescendingCount") == ""
    assert IlShape.SimdCalls(typeof(ScalarRangeReference), "DescendingCountLong") == ""
    assert IlShape.OpcodeCount(typeof(ScalarRangeReference), "DescendingCount", IlEncoding.LdelemI4()) == 2
}

// ---- Values: the lowering is value-identical to the scalar loop -------------------------------------

test "the vectorized ascii count equals the scalar reference at every deleted length" {
    assert FirstRangeCountMismatch(17) == -1
    assert RangeCountShapes.ForTempLiteral(SampleData.AsciiLike(0), 0) == 0
    assert RangeCountShapes.ForTempLiteral(SampleData.AsciiLike(1), 1) == 1
    assert RangeCountShapes.ForTempLiteral(SampleData.AsciiLike(2), 2) == 2
    assert RangeCountShapes.ForTempLiteral(SampleData.AsciiLike(4), 4) == 2
    ascii64 := SampleData.AsciiLike(64)
    ascii1000 := SampleData.AsciiLike(1000)
    assert RangeCountShapes.ForTempLiteral(ascii64, 64) == ScalarRangeReference.DescendingCount(ascii64, 64, 32, 126)
    assert RangeCountShapes.ForTempLiteral(ascii1000, 1000) == ScalarRangeReference.DescendingCount(ascii1000, 1000, 32, 126)
}

test "the inlined-subject and while forms agree with the scalar reference" {
    ascii8 := SampleData.AsciiLike(8)
    ascii17 := SampleData.AsciiLike(17)
    ascii64 := SampleData.AsciiLike(64)
    ascii1000 := SampleData.AsciiLike(1000)
    assert RangeCountShapes.ForInlinedParam(ascii8, 8, 32, 126) == ScalarRangeReference.DescendingCount(ascii8, 8, 32, 126)
    assert RangeCountShapes.WhileTempLiteral(ascii17, 17) == ScalarRangeReference.DescendingCount(ascii17, 17, 32, 126)
    assert RangeCountShapes.ForInlinedParam(ascii64, 64, 32, 126) == ScalarRangeReference.DescendingCount(ascii64, 64, 32, 126)
    assert RangeCountShapes.WhileInlinedParam(ascii1000, 1000, 32, 126) == ScalarRangeReference.DescendingCount(ascii1000, 1000, 32, 126)
}

test "the inclusive boundaries and their neighbours are counted the way the scalar predicate counts them" {
    // AsciiLike plants exactly lo, exactly hi, one below lo and one above hi at positions 0..3.
    boundaries := SampleData.AsciiLike(4)
    assert RangeCountShapes.ForInlinedParam(boundaries, 4, 32, 126) == 2
    assert RangeCountShapes.ForInlinedParam(boundaries, 4, 31, 127) == 4
    assert RangeCountShapes.ForInlinedParam(boundaries, 4, 33, 125) == 0
}

test "the six helper edge ranges count identically through the vectorized kernel" {
    mixed := SampleData.MixedExtremes(200)
    assert RangeCountShapes.ForInlinedParam(mixed, 200, 150, 100) == ScalarRangeReference.DescendingCount(mixed, 200, 150, 100)
    assert RangeCountShapes.ForInlinedParam(mixed, 200, 105, 105) == ScalarRangeReference.DescendingCount(mixed, 200, 105, 105)
    assert RangeCountShapes.ForInlinedParam(mixed, 200, -50, 50) == ScalarRangeReference.DescendingCount(mixed, 200, -50, 50)
    assert RangeCountShapes.ForInlinedParam(mixed, 200, int.MinValue, 0) == ScalarRangeReference.DescendingCount(mixed, 200, int.MinValue, 0)
    assert RangeCountShapes.ForInlinedParam(mixed, 200, 0, int.MaxValue) == ScalarRangeReference.DescendingCount(mixed, 200, 0, int.MaxValue)
    assert RangeCountShapes.ForInlinedParam(mixed, 200, int.MinValue, int.MaxValue) == 200
    // lo > hi is an empty set, and lo == hi is a single value that occurs once every eleven elements.
    assert RangeCountShapes.ForInlinedParam(mixed, 200, 150, 100) == 0
    assert RangeCountShapes.ForInlinedParam(mixed, 200, 105, 105) == 18
}

test "an empty or extreme-negative bound counts nothing and reads nothing" {
    data := SampleData.AsciiLike(100)
    assert RangeCountShapes.ForTempLiteral(data, int.MinValue) == 0
    assert RangeCountShapes.ForTempLiteral(data, -1) == 0
    assert RangeCountShapes.ForTempLiteral(data, 0) == 0
    assert RangeCountShapes.WhileTempLiteral(data, int.MinValue) == 0
    assert RangeCountShapes.WhileTempLiteral(data, -1) == 0
    assert RangeCountShapes.WhileTempLiteral(data, 0) == 0
}

test "a bound past the end throws IndexOutOfRangeException exactly as the scalar loop does" {
    assert KernelRuns.ThrownTypeOf(() => RangeCountShapes.ForTempLiteral(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => RangeCountShapes.WhileTempLiteral(new int[10], 100)) == "System.IndexOutOfRangeException"
    assert KernelRuns.ThrownTypeOf(() => ScalarRangeReference.DescendingCount(new int[10], 100, 32, 126)) == "System.IndexOutOfRangeException"
}

test "the for-form near misses still compute their scalar counts" {
    data := SampleData.AsciiLike(8)
    inRange := ScalarRangeReference.DescendingCount(data, 8, 32, 126)
    assert inRange == 6
    assert RangeCountNearMisses.ForElseBranch(data, 8, 32, 126) == inRange - (8 - inRange)
    assert RangeCountNearMisses.ForExclusiveComparisons(data, 8, 32, 126) == 4
    assert RangeCountNearMisses.ForDisjunction(data, 8, 32, 126) == 8
    assert RangeCountNearMisses.ForCounterStepTwo(data, 8, 32, 126) == 2 * inRange
    assert RangeCountNearMisses.ForCounterPlusTwo(data, 8, 32, 126) == 2 * inRange
    assert RangeCountNearMisses.ForExtraStatementInIf(data, 8, 32, 126) == 2 * inRange
    assert RangeCountNearMisses.ForExtraStatementInBody(data, 8, 32, 126) == inRange
    assert RangeCountNearMisses.ForIndexedByOther(data, 8, 32, 126, 0) == 8
    assert RangeCountNearMisses.ForTwoArrays(data, data, 8, 32, 126) == inRange
    assert RangeCountNearMisses.ForLoopVariantBound(data, 8, 126) == 7
    assert RangeCountNearMisses.ForTempWithForeignSubject(data, 8, 32, 126) == 7
    // The counter is read live, so raising it inside the body extends the loop: with a single matching
    // element the loop runs one iteration further than its initial bound of 4.
    assert RangeCountNearMisses.ForBoundIsCounter(data, 32, 32) == 5
}

test "the while-form near misses still compute their scalar counts" {
    data := SampleData.AsciiLike(8)
    assert RangeCountNearMisses.WhileCounterStepTwo(data, 8, 32, 126) == 12
    assert RangeCountNearMisses.WhileBoundIsCounter(data, 32, 32) == 5
    assert RangeCountNearMisses.WhileMissingIncrement(new int[0], 0, 32, 126) == 0
}

test "a start below zero reads a[-1] exactly as the scalar loop does" {
    // The helper's in-bounds fast path is guarded by `start >= 0 && end <= array.Length`, so a negative
    // start falls through to its scalar tail and throws what the scalar loop throws.
    assert KernelRuns.ThrownTypeOf(() => RangeCountShapes.ForLengthBoundFromStart(SampleData.AsciiLike(8), -1, 32, 126)) == "System.IndexOutOfRangeException"
    assert RangeCountShapes.ForLengthBoundFromStart(SampleData.AsciiLike(8), 8, 32, 126) == 0
    assert RangeCountShapes.ForLengthBoundFromStart(SampleData.AsciiLike(8), 0, 32, 126) == ScalarRangeReference.DescendingCount(SampleData.AsciiLike(8), 8, 32, 126)
}

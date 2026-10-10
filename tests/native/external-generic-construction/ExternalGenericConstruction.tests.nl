namespace NSharpLang.ExternalGenericConstruction.Tests

import System

// Every row below EXECUTES the emitted IL. The lane count is never written down: it is read from
// `System.Numerics.Vector<int>.Count` through reflection, because the width is a property of the
// machine the test runs on and a hardcoded number would silently pass on one and fail on another.
func ScalarAdd(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        result[index] = unchecked(left[index] + right[index])
        index = index + 1
    }

    return result
}

func ScalarSubtract(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        result[index] = unchecked(left[index] - right[index])
        index = index + 1
    }

    return result
}

func ScalarMultiply(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        result[index] = unchecked(left[index] * right[index])
        index = index + 1
    }

    return result
}

func ScalarAnd(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        result[index] = left[index] & right[index]
        index = index + 1
    }

    return result
}

func ScalarOr(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        result[index] = left[index] | right[index]
        index = index + 1
    }

    return result
}

func ScalarXor(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        result[index] = left[index] ^ right[index]
        index = index + 1
    }

    return result
}

func ScalarComplement(values: int[]): int[] {
    result := new int[](values.Length)
    index := 0
    while index < values.Length {
        result[index] = ~values[index]
        index = index + 1
    }

    return result
}

func ScalarNegate(values: int[]): int[] {
    result := new int[](values.Length)
    index := 0
    while index < values.Length {
        result[index] = unchecked(0 - values[index])
        index = index + 1
    }

    return result
}

func ScalarAbsolute(values: int[]): int[] {
    result := new int[](values.Length)
    index := 0
    while index < values.Length {
        if values[index] < 0 {
            result[index] = unchecked(0 - values[index])
        } else {
            result[index] = values[index]
        }
        index = index + 1
    }

    return result
}

func ScalarMinimum(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        if left[index] < right[index] {
            result[index] = left[index]
        } else {
            result[index] = right[index]
        }
        index = index + 1
    }

    return result
}

func ScalarMaximum(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        if left[index] > right[index] {
            result[index] = left[index]
        } else {
            result[index] = right[index]
        }
        index = index + 1
    }

    return result
}

// The all-bits-set / all-bits-clear masks Vector's comparisons produce for an Int32 element.
func ScalarEqualityMask(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        if left[index] == right[index] {
            result[index] = -1
        } else {
            result[index] = 0
        }
        index = index + 1
    }

    return result
}

func ScalarAtLeastMask(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        if left[index] >= right[index] {
            result[index] = -1
        } else {
            result[index] = 0
        }
        index = index + 1
    }

    return result
}

func ScalarMaskedValues(left: int[], right: int[]): int[] {
    result := new int[](left.Length)
    index := 0
    while index < left.Length {
        if left[index] == right[index] {
            result[index] = 0
        } else {
            result[index] = left[index]
        }
        index = index + 1
    }

    return result
}

func ScalarDot(left: int[], right: int[]): int {
    total := 0
    index := 0
    while index < left.Length {
        total = unchecked(total + left[index] * right[index])
        index = index + 1
    }

    return total
}

func EdgeValues(lanes: int): int[] {
    values := new int[](lanes)
    index := 0
    while index < lanes {
        if index == 0 {
            values[index] = Int32.MinValue
        } else {
            if index == 1 {
                values[index] = Int32.MaxValue
            } else {
                if index == 2 {
                    values[index] = 0
                } else {
                    values[index] = unchecked(0 - index * 7)
                }
            }
        }
        index = index + 1
    }

    return values
}

// ---------------------------------------------------------------------- construction

test "constructing a closed external generic loads exactly the block a scalar loop reads" {
    lanes := LaneCount()
    values := PseudoRandom(lanes * 3, 20260910)

    assert ArraysEqual(LanesOf(LoadBlock(values, 0), lanes), Slice(values, 0, lanes))
    assert ArraysEqual(LanesOf(LoadBlock(values, lanes), lanes), Slice(values, lanes, lanes))
    assert ArraysEqual(LanesOf(LoadBlockDirect(values, lanes * 2), lanes), Slice(values, lanes * 2, lanes))

    // An index that is not a multiple of the lane count still reads from exactly there.
    assert ArraysEqual(LanesOf(LoadBlock(values, 1), lanes), Slice(values, 1, lanes))

    edges := EdgeValues(lanes)
    assert ArraysEqual(LanesOf(LoadBlockDirect(edges, 0), lanes), edges)
}

test "constructing a closed external generic over long reads the same block" {
    longLanes := LongLaneCount()
    values := LongRamp(longLanes * 3, 900000000000L)

    assert LongArraysEqual(LongLanesOf(LoadLongBlock(values, 0, longLanes), longLanes), LongSlice(values, longLanes, longLanes))
    assert LongLane(BroadcastLong(-5L), 0) == -5L
}

test "a broadcast fills every lane and a bare construction is the zero value" {
    lanes := LaneCount()

    broadcast := LanesOf(Broadcast(-9), lanes)
    index := 0
    while index < lanes {
        assert broadcast[index] == -9
        index = index + 1
    }

    zero := LanesOf(ZeroBlock(), lanes)
    index = 0
    while index < lanes {
        assert zero[index] == 0
        index = index + 1
    }

    // The same construction as a call argument and as a field store.
    values := Ramp(lanes, 4)
    assert SumOfBlockArgument(values, 0) == ScalarSum(values, 0, lanes)
    holder := BroadcastFieldHolder(3)
    assert Lane(holder.Value, 0) == 3
}

test "an out-of-range block construction throws the BCL's own ArgumentOutOfRangeException" {
    lanes := LaneCount()
    values := Ramp(lanes * 2, 1)
    assert LoadPastEnd(values)
}

// ---------------------------------------------------------------------- operators

test "arithmetic and bitwise operators on a constructed external generic match the scalar loop" {
    lanes := LaneCount()
    left := PseudoRandom(lanes, 11)
    right := PseudoRandom(lanes, 29)
    a := LoadBlockDirect(left, 0)
    b := LoadBlockDirect(right, 0)

    assert ArraysEqual(LanesOf(AddVectors(a, b), lanes), ScalarAdd(left, right))
    assert ArraysEqual(LanesOf(SubtractVectors(a, b), lanes), ScalarSubtract(left, right))
    assert ArraysEqual(LanesOf(MultiplyVectors(a, b), lanes), ScalarMultiply(left, right))
    assert ArraysEqual(LanesOf(AndVectors(a, b), lanes), ScalarAnd(left, right))
    assert ArraysEqual(LanesOf(OrVectors(a, b), lanes), ScalarOr(left, right))
    assert ArraysEqual(LanesOf(XorVectors(a, b), lanes), ScalarXor(left, right))
    assert ArraysEqual(LanesOf(ComplementVector(a), lanes), ScalarComplement(left))
    assert ArraysEqual(LanesOf(NegateVector(a), lanes), ScalarNegate(left))
}

test "unchecked wrap at the integer edges matches the scalar loop exactly" {
    lanes := LaneCount()
    edges := EdgeValues(lanes)
    ones := Ramp(lanes, 1)
    a := LoadBlockDirect(edges, 0)
    b := LoadBlockDirect(ones, 0)

    assert ArraysEqual(LanesOf(AddVectors(a, b), lanes), ScalarAdd(edges, ones))
    assert ArraysEqual(LanesOf(SubtractVectors(a, b), lanes), ScalarSubtract(edges, ones))
    assert ArraysEqual(LanesOf(MultiplyVectors(a, b), lanes), ScalarMultiply(edges, ones))
    assert ArraysEqual(LanesOf(NegateVector(a), lanes), ScalarNegate(edges))
    assert ArraysEqual(LanesOf(Magnitude(a), lanes), ScalarAbsolute(edges))
}

test "the equality operators on a constructed external generic compare every lane" {
    lanes := LaneCount()
    values := PseudoRandom(lanes, 7)
    other := PseudoRandom(lanes, 8)
    a := LoadBlockDirect(values, 0)
    b := LoadBlockDirect(values, 0)
    c := LoadBlockDirect(other, 0)

    assert VectorsEqual(a, b)
    assert !VectorsNotEqual(a, b)
    assert !VectorsEqual(a, c)
    assert VectorsNotEqual(a, c)
}

test "operators on non-generic external types resolve through the same lookup" {
    start := new DateTime(2026, 9, 10, 8, 0, 0)
    finish := new DateTime(2026, 9, 10, 9, 30, 0)
    elapsed := Elapsed(start, finish)
    assert elapsed == new TimeSpan(1, 30, 0)
    assert Shift(start, elapsed) == finish
    assert Money(6m, 4m) == 30m
}

// ---------------------------------------------------------------------- indexer

test "the indexer on a constructed external generic reads lanes and keeps the BCL's bounds error" {
    lanes := LaneCount()
    values := Ramp(lanes, 100)
    block := LoadBlockDirect(values, 0)

    index := 0
    while index < lanes {
        assert Lane(block, index) == values[index]
        index = index + 1
    }

    assert LaneOutOfRangeExceptionName(block, lanes) == "System.ArgumentOutOfRangeException"
    assert LaneOutOfRangeExceptionName(block, -1) == "System.ArgumentOutOfRangeException"
}

// ---------------------------------------------------------------------- generic static calls

test "generic static reductions bind their type parameter from the constructed argument" {
    lanes := LaneCount()
    values := PseudoRandom(lanes, 3)
    other := PseudoRandom(lanes, 4)
    a := LoadBlockDirect(values, 0)
    b := LoadBlockDirect(other, 0)

    total := 0
    index := 0
    while index < lanes {
        total = unchecked(total + values[index])
        index = index + 1
    }
    assert Reduce(a) == total

    assert ArraysEqual(LanesOf(MinOf(a, b), lanes), ScalarMinimum(values, other))
    assert ArraysEqual(LanesOf(MaxOf(a, b), lanes), ScalarMaximum(values, other))
    assert ArraysEqual(LanesOf(EqualityMask(a, a), lanes), ScalarEqualityMask(values, values))
    assert ArraysEqual(LanesOf(EqualityMask(a, b), lanes), ScalarEqualityMask(values, other))
    assert ArraysEqual(LanesOf(InequalityMaskedValues(a, b), lanes), ScalarMaskedValues(values, other))
    assert ArraysEqual(LanesOf(AtLeast(a, b), lanes), ScalarAtLeastMask(values, other))
    assert ArraysEqual(LanesOf(AtMost(b, a), lanes), ScalarAtLeastMask(values, other))
    assert ArraysEqual(LanesOf(Inverted(a), lanes), ScalarNegate(values))
    assert DotProduct(a, b) == ScalarDot(values, other)

    // ConditionalSelect keeps the left value where the mask is all-ones.
    chosen := LanesOf(Chosen(EqualityMask(a, a), a, b), lanes)
    assert ArraysEqual(chosen, values)

    // A different element type binds a different type argument from the same call site shape.
    longLanes := LongLaneCount()
    longValues := LongRamp(longLanes, 5L)
    longTotal := 0L
    longIndex := 0
    while longIndex < longLanes {
        longTotal = longTotal + longValues[longIndex]
        longIndex = longIndex + 1
    }
    assert ReduceLong(LoadLongBlock(longValues, 0, 0)) == longTotal
}

// ---------------------------------------------------------------------- compound assignment

test "compound assignment on a local runs the type's own operators" {
    lanes := LaneCount()
    values := PseudoRandom(lanes, 17)
    other := PseudoRandom(lanes, 19)
    a := LoadBlockDirect(values, 0)
    b := LoadBlockDirect(other, 0)

    assert ArraysEqual(LanesOf(Accumulate(a, b), lanes), values)
}

test "compound assignment on a field runs the type's own operators" {
    lanes := LaneCount()
    values := PseudoRandom(lanes, 23)
    b := LoadBlockDirect(values, 0)

    holder := BroadcastFieldHolder(0)
    AccumulateIntoField(holder, b)
    AccumulateIntoField(holder, b)
    assert ArraysEqual(LanesOf(holder.Value, lanes), ScalarAdd(values, values))

    SubtractFromField(holder, b)
    assert ArraysEqual(LanesOf(holder.Value, lanes), values)

    // The same arm, on a decimal field: `decimal` has no IL opcode either, and its `op_Addition` is
    // reached by exactly the lookup the vector uses.
    AccumulateMoneyField(holder, 2.5m)
    AccumulateMoneyField(holder, 0.25m)
    assert holder.Money == 2.75m
}

test "compound assignment on an array element evaluates the array and index once" {
    totals := new int[](3)
    totals[1] = 10
    AccumulateIntoIntElement(totals, 1, 7)
    AccumulateIntoIntElement(totals, 1, 5)
    assert totals[0] == 0
    assert totals[1] == 22
    assert totals[2] == 0
}

test "compound assignment through a collection indexer keeps working" {
    map := BuildMap("a", 1)
    BumpMapValue(map, "a", 41)
    assert map["a"] == 42
}

test "the four-accumulator reduction matches the scalar sum at every length" {
    lanes := LaneCount()

    empty := new int[](0)
    assert AccumulateFourWay(empty, lanes) == 0

    short := Ramp(lanes - 1, 1)
    assert AccumulateFourWay(short, lanes) == ScalarSumAll(short)

    exact := Ramp(lanes * 4, 1)
    assert AccumulateFourWay(exact, lanes) == ScalarSumAll(exact)

    ragged := Ramp(lanes * 4 + 3, 1)
    assert AccumulateFourWay(ragged, lanes) == ScalarSumAll(ragged)

    negatives := PseudoRandom(lanes * 9 + 5, 31)
    assert AccumulateFourWay(negatives, lanes) == ScalarSumAll(negatives)

    edges := EdgeValues(lanes)
    assert AccumulateFourWay(edges, lanes) == ScalarSumAll(edges)
}

test "the masked in-range count matches the scalar predicate loop" {
    lanes := LaneCount()

    values := PseudoRandom(lanes * 5 + 2, 41)
    assert CountInRange(values, lanes, -1000000, 1000000) == ScalarCountInRange(values, -1000000, 1000000)

    ramp := Ramp(lanes * 3 + 1, -4)
    assert CountInRange(ramp, lanes, 0, 5) == ScalarCountInRange(ramp, 0, 5)
    assert CountInRange(ramp, lanes, 100, 200) == ScalarCountInRange(ramp, 100, 200)

    empty := new int[](0)
    assert CountInRange(empty, lanes, 0, 1) == 0
}

// ---------------------------------------------------------------------- evaluation order

test "arguments evaluate left to right exactly once" {
    lanes := LaneCount()
    values := Ramp(lanes * 2, 1)

    constructionLog := new EvaluationLog()
    block := ConstructInEvaluationOrder(constructionLog, values, lanes)
    assert constructionLog.Tags.Count == 2
    assert constructionLog.Tags[0] == 1
    assert constructionLog.Tags[1] == 2
    assert ArraysEqual(LanesOf(block, lanes), Slice(values, lanes, lanes))

    callLog := new EvaluationLog()
    left := LoadBlockDirect(values, 0)
    right := LoadBlockDirect(values, lanes)
    reduced := ReduceInEvaluationOrder(callLog, left, right)
    assert callLog.Tags.Count == 2
    assert callLog.Tags[0] == 1
    assert callLog.Tags[1] == 2
    assert ArraysEqual(LanesOf(reduced, lanes), ScalarMinimum(Slice(values, 0, lanes), Slice(values, lanes, lanes)))
}

// ---------------------------------------------------------------------- ordinary BCL generic control

test "an ordinary constructed BCL generic uses the same construction path" {
    values := BuildList(8, 3, 4)
    assert values.Count == 2
    assert values[0] == 3
    assert values[1] == 4

    copied := CopyList(values)
    assert copied.Count == 2
    assert copied[1] == 4

    map := BuildMap("key", 5)
    assert map["key"] == 5
    copiedMap := CopyMap(map)
    assert copiedMap.Count == 1
    assert copiedMap["key"] == 5

    set := BuildSet(values)
    assert set.Count == 2
    assert set.Contains(3)
    assert !set.Contains(9)
}

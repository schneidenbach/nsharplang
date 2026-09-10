namespace NSharpLang.SimdReductions.Tests

import System
import System.Numerics
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.SimdReductionsOriginal

// THE CANONICAL EXECUTION EVIDENCE FOR THE `SimdReductions.cs` TRANSLATION.
//
// Every row below RUNS the emitted IL of `SimdReductions.nl` and compares it against two independent
// references on identical inputs:
//
//   1. A SCALAR ORACLE written here in N# -- literally the loop each helper's documentation claims to be
//      value-identical to. This is the semantic contract.
//   2. THE REAL `NSharpLang.Runtime.SimdReductions`, the C# original, loaded from the runtime assembly the
//      project references. This is the translation contract: the two implementations must not merely both
//      be "correct", they must agree element for element, exception for exception, on every input.
//
// NOTHING ABOUT THE MACHINE IS WRITTEN DOWN. The lane count comes from `Vector<int>.Count` /
// `Vector<long>.Count` at run time, because the vector width is a property of the CPU the test executes on
// -- a hardcoded 4 would pass on this arm64 machine and silently stop covering the four-accumulator unrolled
// body on a 256-bit one. Every length sweep is expressed in lanes: 0 through 4*lanes+3 covers the empty
// range, every partial vector, exactly one unrolled step, and an unrolled step plus a ragged tail.
//
// THE SWEEPS ARE EXHAUSTIVE IN (start, end), NOT SAMPLED. For each length the rows walk every start in
// [0, length] and every end in [0, length], so the empty ranges (end <= start), the pure-tail ranges, the
// misaligned starts and the full ranges are all covered by construction rather than by a chosen handful.

// ---------------------------------------------------------------------- scalar oracles
//
// The loop from each helper's documentation, transcribed. These are the definition of "correct" here.
func ScalarSumInt32(values: int[], start: int, end: int): int {
    total := 0
    i := start
    while i < end {
        total += values[i]
        i += 1
    }

    return total
}

func ScalarSumInt64(values: long[], start: int, end: int): long {
    total := 0L
    i := start
    while i < end {
        total += values[i]
        i += 1
    }

    return total
}

func ScalarSumUInt32(values: uint[], start: int, end: int): uint {
    total := 0u
    i := start
    while i < end {
        total += values[i]
        i += 1
    }

    return total
}

func ScalarSumUInt64(values: ulong[], start: int, end: int): ulong {
    total := 0uL
    i := start
    while i < end {
        total += values[i]
        i += 1
    }

    return total
}

func ScalarCountInRangeInt32(values: int[], start: int, end: int, lo: int, hi: int): int {
    count := 0
    i := start
    while i < end {
        if values[i] >= lo && values[i] <= hi {
            count += 1
        }
        i += 1
    }

    return count
}

func ScalarMinInt32(values: int[], start: int, end: int, seed: int): int {
    result := seed
    i := start
    while i < end {
        if values[i] < result {
            result = values[i]
        }
        i += 1
    }

    return result
}

func ScalarMaxInt32(values: int[], start: int, end: int, seed: int): int {
    result := seed
    i := start
    while i < end {
        if values[i] > result {
            result = values[i]
        }
        i += 1
    }

    return result
}

func ScalarMinMaxInt32(values: int[], start: int, end: int, seedMin: int, seedMax: int): (Min: int, Max: int) {
    min := seedMin
    max := seedMax
    i := start
    while i < end {
        v := values[i]
        if v < min {
            min = v
        }
        if v > max {
            max = v
        }
        i += 1
    }

    return (min, max)
}

func ScalarCountTransitionsInt32(values: int[], start: int, end: int, seedPrevious: int): (Count: int, LastPrevious: int) {
    count := 0
    prev := seedPrevious
    i := start
    while i < end {
        if values[i] != prev {
            count += 1
        }
        prev = values[i]
        i += 1
    }

    return (count, prev)
}

// ---------------------------------------------------------------------- deterministic inputs
//
// Seeded `Random`, so a failure is reproducible from the row that reported it rather than from a lucky draw.

func RandomInt32Array(length: int, seed: int): int[] {
    rng := new Random(seed)
    values := new int[](length)
    i := 0
    while i < length {
        values[i] = rng.Next(-1000000, 1000000)
        i += 1
    }

    return values
}

// Values crowded against int.MaxValue so that ANY range longer than one element wraps -- the unchecked
// wraparound the helpers rely on for their associativity argument.
func WrappingInt32Array(length: int, seed: int): int[] {
    rng := new Random(seed)
    values := new int[](length)
    i := 0
    while i < length {
        values[i] = 2147483647 - rng.Next(0, 8)
        i += 1
    }

    return values
}

func RandomInt64Array(length: int, seed: int): long[] {
    rng := new Random(seed)
    values := new long[](length)
    i := 0
    while i < length {
        values[i] = ((long)rng.Next(-1000000, 1000000)) * 4294967296L + (long)rng.Next(0, 1000000)
        i += 1
    }

    return values
}

func WrappingInt64Array(length: int, seed: int): long[] {
    rng := new Random(seed)
    values := new long[](length)
    i := 0
    while i < length {
        values[i] = 9223372036854775807L - (long)rng.Next(0, 8)
        i += 1
    }

    return values
}

func RandomUInt32Array(length: int, seed: int): uint[] {
    rng := new Random(seed)
    values := new uint[](length)
    i := 0
    while i < length {
        values[i] = (uint)rng.Next(-2147483648, 2147483647)
        i += 1
    }

    return values
}

func RandomUInt64Array(length: int, seed: int): ulong[] {
    rng := new Random(seed)
    values := new ulong[](length)
    i := 0
    while i < length {
        values[i] = ((ulong)(uint)rng.Next(-2147483648, 2147483647)) * 4294967296uL + (ulong)(uint)rng.Next(-2147483648, 2147483647)
        i += 1
    }

    return values
}

// A small alphabet, so adjacent elements repeat often and the transition count is interesting rather than
// "every element differs from the last".
func RunLengthInt32Array(length: int, seed: int): int[] {
    rng := new Random(seed)
    values := new int[](length)
    i := 0
    while i < length {
        values[i] = rng.Next(0, 3)
        i += 1
    }

    return values
}

// ---------------------------------------------------------------------- exception observation
//
// An out-of-bounds range must reach the caller as the SCALAR loop's `IndexOutOfRangeException`, never as the
// `ArgumentOutOfRangeException` a `new Vector<int>(array, i)` load would have raised. The exception TYPE is
// what proves the SIMD fast path was skipped rather than entered: the two paths are indistinguishable by
// value (both abort), and an `int[]` cannot record which elements were read, so the type is the observable.
// Each helper gets its own probe, and the same probe shape is applied to the scalar oracle and to the real
// runtime implementation so all three answers can be compared.

func SumInt32ThrowName(values: int[], start: int, end: int): string {
    try {
        return "no throw: " + SimdReductionsPort.SumInt32(values, start, end).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func ScalarSumInt32ThrowName(values: int[], start: int, end: int): string {
    try {
        return "no throw: " + ScalarSumInt32(values, start, end).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func RuntimeSumInt32ThrowName(values: int[], start: int, end: int): string {
    try {
        return "no throw: " + OriginalSumInt32(values, start, end).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func SumInt64ThrowName(values: long[], start: int, end: int): string {
    try {
        return "no throw: " + SimdReductionsPort.SumInt64(values, start, end).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func SumUInt32ThrowName(values: uint[], start: int, end: int): string {
    try {
        return "no throw: " + SimdReductionsPort.SumUInt32(values, start, end).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func SumUInt64ThrowName(values: ulong[], start: int, end: int): string {
    try {
        return "no throw: " + SimdReductionsPort.SumUInt64(values, start, end).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func CountInRangeThrowName(values: int[], start: int, end: int, lo: int, hi: int): string {
    try {
        return "no throw: " + SimdReductionsPort.CountInRangeInt32(values, start, end, lo, hi).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func RuntimeCountInRangeThrowName(values: int[], start: int, end: int, lo: int, hi: int): string {
    try {
        return "no throw: " + OriginalCountInRangeInt32(values, start, end, lo, hi).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func MinThrowName(values: int[], start: int, end: int, seed: int): string {
    try {
        return "no throw: " + SimdReductionsPort.MinInt32(values, start, end, seed).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func MaxThrowName(values: int[], start: int, end: int, seed: int): string {
    try {
        return "no throw: " + SimdReductionsPort.MaxInt32(values, start, end, seed).ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func MinMaxThrowName(values: int[], start: int, end: int, seedMin: int, seedMax: int): string {
    try {
        result := SimdReductionsPort.MinMaxInt32(values, start, end, seedMin, seedMax)
        return "no throw: " + result.Min.ToString() + "/" + result.Max.ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func RuntimeMinMaxThrowName(values: int[], start: int, end: int, seedMin: int, seedMax: int): string {
    try {
        result := OriginalMinMaxInt32(values, start, end, seedMin, seedMax)
        return "no throw: " + result.Min.ToString() + "/" + result.Max.ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func CountTransitionsThrowName(values: int[], start: int, end: int, seedPrevious: int): string {
    try {
        result := SimdReductionsPort.CountTransitionsInt32(values, start, end, seedPrevious)
        return "no throw: " + result.Count.ToString() + "/" + result.LastPrevious.ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

func RuntimeCountTransitionsThrowName(values: int[], start: int, end: int, seedPrevious: int): string {
    try {
        result := OriginalCountTransitionsInt32(values, start, end, seedPrevious)
        return "no throw: " + result.Count.ToString() + "/" + result.LastPrevious.ToString()
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

// ---------------------------------------------------------------------- Sum: the four element types

test "SumInt32 equals the scalar loop and the C# original for every (start, end) at every length through four unrolled vectors" {
    lanes := Vector<int>.Count
    assert lanes > 0

    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomInt32Array(length, 7001 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                expected := ScalarSumInt32(values, start, end)
                assert SimdReductionsPort.SumInt32(values, start, end) == expected
                assert OriginalSumInt32(values, start, end) == expected
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "SumInt64 equals the scalar loop and the C# original for every (start, end) at every length through four unrolled vectors" {
    lanes := Vector<long>.Count
    assert lanes > 0

    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomInt64Array(length, 7101 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                expected := ScalarSumInt64(values, start, end)
                assert SimdReductionsPort.SumInt64(values, start, end) == expected
                assert OriginalSumInt64(values, start, end) == expected
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "SumUInt32 equals the scalar loop and the C# original for every (start, end) at every length through four unrolled vectors" {
    lanes := Vector<uint>.Count
    assert lanes > 0

    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomUInt32Array(length, 7201 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                expected := ScalarSumUInt32(values, start, end)
                assert SimdReductionsPort.SumUInt32(values, start, end) == expected
                assert OriginalSumUInt32(values, start, end) == expected
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "SumUInt64 equals the scalar loop and the C# original for every (start, end) at every length through four unrolled vectors" {
    lanes := Vector<ulong>.Count
    assert lanes > 0

    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomUInt64Array(length, 7301 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                expected := ScalarSumUInt64(values, start, end)
                assert SimdReductionsPort.SumUInt64(values, start, end) == expected
                assert OriginalSumUInt64(values, start, end) == expected
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

// The associativity argument the C# file rests on, exercised rather than asserted: reducing across lanes and
// four accumulators only reproduces the sequential sum because integer addition WRAPS (mod 2^32 / mod 2^64).
// The arrays below are crowded against MaxValue so every range beyond one element overflows repeatedly.
test "the sums wrap unchecked exactly like the scalar loop" {
    assert ScalarSumInt32([2147483647, 2147483647], 0, 2) == -2
    assert SimdReductionsPort.SumInt32([2147483647, 2147483647], 0, 2) == -2

    lanes := Vector<int>.Count
    length := 0
    while length <= lanes * 4 + 3 {
        values := WrappingInt32Array(length, 7401 + length)
        start := 0
        while start <= length {
            expected := ScalarSumInt32(values, start, length)
            assert SimdReductionsPort.SumInt32(values, start, length) == expected
            assert OriginalSumInt32(values, start, length) == expected
            start += 1
        }
        length += 1
    }

    longLanes := Vector<long>.Count
    longLength := 0
    while longLength <= longLanes * 4 + 3 {
        longValues := WrappingInt64Array(longLength, 7501 + longLength)
        longStart := 0
        while longStart <= longLength {
            longExpected := ScalarSumInt64(longValues, longStart, longLength)
            assert SimdReductionsPort.SumInt64(longValues, longStart, longLength) == longExpected
            assert OriginalSumInt64(longValues, longStart, longLength) == longExpected
            longStart += 1
        }
        longLength += 1
    }
}

// ---------------------------------------------------------------------- CountInRange

test "CountInRangeInt32 equals the scalar loop and the C# original for every (start, end) and several bounds" {
    lanes := Vector<int>.Count
    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomInt32Array(length, 7601 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                // A window that excludes everything, one that includes everything, and one that splits the
                // draw roughly in half, so both the all-ones and the all-zeros lane masks are exercised.
                assert SimdReductionsPort.CountInRangeInt32(values, start, end, 5000000, 6000000) == ScalarCountInRangeInt32(values, start, end, 5000000, 6000000)
                assert SimdReductionsPort.CountInRangeInt32(values, start, end, -2000000, 2000000) == ScalarCountInRangeInt32(values, start, end, -2000000, 2000000)
                assert SimdReductionsPort.CountInRangeInt32(values, start, end, 0, 1000000) == ScalarCountInRangeInt32(values, start, end, 0, 1000000)
                assert OriginalCountInRangeInt32(values, start, end, 0, 1000000) == ScalarCountInRangeInt32(values, start, end, 0, 1000000)
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "CountInRangeInt32 counts an inclusive window at its exact boundaries" {
    lanes := Vector<int>.Count
    length := lanes * 4 + 3
    values := new int[](length)
    i := 0
    while i < length {
        values[i] = i
        i += 1
    }

    // lo and hi are both INCLUSIVE: the window [2, length-3] holds length-4 elements.
    assert SimdReductionsPort.CountInRangeInt32(values, 0, length, 2, length - 3) == length - 4
    assert SimdReductionsPort.CountInRangeInt32(values, 0, length, 0, length - 1) == length
    assert SimdReductionsPort.CountInRangeInt32(values, 0, length, 7, 7) == 1
    assert SimdReductionsPort.CountInRangeInt32(values, 0, length, 7, 6) == 0
    assert OriginalCountInRangeInt32(values, 0, length, 2, length - 3) == length - 4
}

// ---------------------------------------------------------------------- Min / Max / fused MinMax

test "MinInt32 and MaxInt32 equal the scalar folds and the C# original for every (start, end) and several seeds" {
    lanes := Vector<int>.Count
    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomInt32Array(length, 7701 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                // A seed below everything, a seed above everything, and a seed inside the draw -- the third
                // is the only one where the lane accumulators and the scalar tail can disagree.
                assert SimdReductionsPort.MinInt32(values, start, end, -2147483648) == ScalarMinInt32(values, start, end, -2147483648)
                assert SimdReductionsPort.MinInt32(values, start, end, 2147483647) == ScalarMinInt32(values, start, end, 2147483647)
                assert SimdReductionsPort.MinInt32(values, start, end, 0) == ScalarMinInt32(values, start, end, 0)
                assert SimdReductionsPort.MaxInt32(values, start, end, -2147483648) == ScalarMaxInt32(values, start, end, -2147483648)
                assert SimdReductionsPort.MaxInt32(values, start, end, 2147483647) == ScalarMaxInt32(values, start, end, 2147483647)
                assert SimdReductionsPort.MaxInt32(values, start, end, 0) == ScalarMaxInt32(values, start, end, 0)
                assert OriginalMinInt32(values, start, end, 0) == ScalarMinInt32(values, start, end, 0)
                assert OriginalMaxInt32(values, start, end, 0) == ScalarMaxInt32(values, start, end, 0)
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "MinMaxInt32 returns both folds in one pass, element for element with the separate scans and with the C# original" {
    lanes := Vector<int>.Count
    length := 0
    while length <= lanes * 4 + 3 {
        values := RandomInt32Array(length, 7801 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                fused := SimdReductionsPort.MinMaxInt32(values, start, end, 0, 0)
                expected := ScalarMinMaxInt32(values, start, end, 0, 0)
                assert fused.Min == expected.Min
                assert fused.Max == expected.Max

                // The fused pass must also agree with the two independent scans it replaces.
                assert fused.Min == SimdReductionsPort.MinInt32(values, start, end, 0)
                assert fused.Max == SimdReductionsPort.MaxInt32(values, start, end, 0)

                original := OriginalMinMaxInt32(values, start, end, 0, 0)
                assert original.Min == fused.Min
                assert original.Max == fused.Max
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "MinMaxInt32 carries asymmetric seeds through both folds independently" {
    lanes := Vector<int>.Count
    length := lanes * 4 + 3
    values := RandomInt32Array(length, 7901)

    // A min seed nothing can beat and a max seed nothing can beat: both must survive untouched.
    pinned := SimdReductionsPort.MinMaxInt32(values, 0, length, -2147483648, 2147483647)
    assert pinned.Min == -2147483648
    assert pinned.Max == 2147483647

    // Seeds inside the draw: each fold moves only if the data crosses it.
    mixed := SimdReductionsPort.MinMaxInt32(values, 0, length, 0, 0)
    expected := ScalarMinMaxInt32(values, 0, length, 0, 0)
    assert mixed.Min == expected.Min
    assert mixed.Max == expected.Max
    assert mixed.Min <= 0
    assert mixed.Max >= 0
}

test "the named elements of the fused result deconstruct in declaration order" {
    lanes := Vector<int>.Count
    values := RandomInt32Array(lanes * 4 + 3, 8001)

    low, high := SimdReductionsPort.MinMaxInt32(values, 0, values.Length, 0, 0)
    named := SimdReductionsPort.MinMaxInt32(values, 0, values.Length, 0, 0)
    assert low == named.Min
    assert high == named.Max

    count, lastPrevious := SimdReductionsPort.CountTransitionsInt32(values, 0, values.Length, values[0])
    carried := SimdReductionsPort.CountTransitionsInt32(values, 0, values.Length, values[0])
    assert count == carried.Count
    assert lastPrevious == carried.LastPrevious
}

// ---------------------------------------------------------------------- CountTransitions

test "CountTransitionsInt32 equals the scalar loop and the C# original for every (start, end) and several seeds" {
    lanes := Vector<int>.Count
    length := 0
    while length <= lanes * 4 + 3 {
        values := RunLengthInt32Array(length, 8101 + length)
        start := 0
        while start <= length {
            end := 0
            while end <= length {
                seed := 0
                while seed < 4 {
                    observed := SimdReductionsPort.CountTransitionsInt32(values, start, end, seed)
                    expected := ScalarCountTransitionsInt32(values, start, end, seed)
                    assert observed.Count == expected.Count
                    assert observed.LastPrevious == expected.LastPrevious

                    original := OriginalCountTransitionsInt32(values, start, end, seed)
                    assert original.Count == expected.Count
                    assert original.LastPrevious == expected.LastPrevious
                    seed += 1
                }
                end += 1
            }
            start += 1
        }
        length += 1
    }
}

test "CountTransitionsInt32 reads only array[start .. end) -- the first element compares against the seed, never against array[start - 1]" {
    lanes := Vector<int>.Count
    length := lanes * 4 + 4
    values := new int[](length)
    i := 0
    while i < length {
        values[i] = 5
        i += 1
    }

    // Everything from index 1 on is identical, so the ONLY possible transition is the seeded first
    // comparison. A seed equal to values[start] must count zero even though values[start - 1] differs.
    values[0] = 99
    matching := SimdReductionsPort.CountTransitionsInt32(values, 1, length, 5)
    assert matching.Count == 0
    assert matching.LastPrevious == 5

    differing := SimdReductionsPort.CountTransitionsInt32(values, 1, length, 99)
    assert differing.Count == 1
    assert differing.LastPrevious == 5

    assert OriginalCountTransitionsInt32(values, 1, length, 5).Count == 0
    assert OriginalCountTransitionsInt32(values, 1, length, 99).Count == 1
}

test "CountTransitionsInt32 counts every adjacent change when no two neighbours match" {
    lanes := Vector<int>.Count
    length := lanes * 4 + 3
    values := new int[](length)
    i := 0
    while i < length {
        values[i] = i % 2
        i += 1
    }

    // Alternating 0,1,0,1,...: every element differs from its predecessor, and the seed matches values[0],
    // so the count is exactly length - 1.
    alternating := SimdReductionsPort.CountTransitionsInt32(values, 0, length, 0)
    assert alternating.Count == length - 1
    assert alternating.LastPrevious == values[length - 1]
    assert alternating.Count == ScalarCountTransitionsInt32(values, 0, length, 0).Count
}

// ---------------------------------------------------------------------- empty and negative ranges

// `end <= start` returns the identity BEFORE any read. The rows prove "no reads" the only way an `int[]`
// allows: the range is placed entirely outside the array, so a single load would throw. A helper that
// computed `end - step` first (the unchecked wrap the early-out exists to prevent) would run the SIMD loop
// over elements the scalar loop never touches, and `int.MinValue` is exactly the `end` that triggers it.
test "an empty or negative range returns the identity without reading the array" {
    lanes := Vector<int>.Count
    values := RandomInt32Array(lanes * 4 + 3, 8201)
    longValues := RandomInt64Array(Vector<long>.Count * 4 + 3, 8202)
    uintValues := RandomUInt32Array(Vector<uint>.Count * 4 + 3, 8203)
    ulongValues := RandomUInt64Array(Vector<ulong>.Count * 4 + 3, 8204)

    assert SimdReductionsPort.SumInt32(values, 5, -2147483648) == 0
    assert SimdReductionsPort.SumInt32(values, -1, -5) == 0
    assert SimdReductionsPort.SumInt32(values, values.Length + 100, values.Length) == 0
    assert SimdReductionsPort.SumInt64(longValues, 5, -2147483648) == 0L
    assert SimdReductionsPort.SumUInt32(uintValues, 5, -2147483648) == 0u
    assert SimdReductionsPort.SumUInt64(ulongValues, 5, -2147483648) == 0uL

    assert SimdReductionsPort.CountInRangeInt32(values, 5, -2147483648, -1000000, 1000000) == 0
    assert SimdReductionsPort.MinInt32(values, 5, -2147483648, 42) == 42
    assert SimdReductionsPort.MaxInt32(values, 5, -2147483648, 42) == 42

    fused := SimdReductionsPort.MinMaxInt32(values, 5, -2147483648, 11, 22)
    assert fused.Min == 11
    assert fused.Max == 22

    carried := SimdReductionsPort.CountTransitionsInt32(values, 5, -2147483648, 33)
    assert carried.Count == 0
    assert carried.LastPrevious == 33

    // The C# original answers identically, including for the int.MinValue end.
    assert OriginalSumInt32(values, 5, -2147483648) == 0
    assert OriginalMinInt32(values, 5, -2147483648, 42) == 42
    assert OriginalMaxInt32(values, 5, -2147483648, 42) == 42
    assert OriginalCountTransitionsInt32(values, 5, -2147483648, 33).LastPrevious == 33
}

// ---------------------------------------------------------------------- out-of-bounds ranges

test "an out-of-bounds range throws IndexOutOfRangeException -- the scalar loop's exception, not the Vector constructor's" {
    lanes := Vector<int>.Count
    values := RandomInt32Array(lanes * 4 + 3, 8301)
    longValues := RandomInt64Array(Vector<long>.Count * 4 + 3, 8302)
    uintValues := RandomUInt32Array(Vector<uint>.Count * 4 + 3, 8303)
    ulongValues := RandomUInt64Array(Vector<ulong>.Count * 4 + 3, 8304)

    // `end` past the end. The scalar tail reads values[start .. Length-1] and throws at Length. Had the
    // in-bounds guard been missing, `new Vector<int>(values, i)` would have raised
    // ArgumentOutOfRangeException instead -- a DIFFERENT, observable type.
    assert SumInt32ThrowName(values, 0, values.Length + 1) == "System.IndexOutOfRangeException"
    assert ScalarSumInt32ThrowName(values, 0, values.Length + 1) == "System.IndexOutOfRangeException"
    assert RuntimeSumInt32ThrowName(values, 0, values.Length + 1) == "System.IndexOutOfRangeException"

    // `start` before the beginning: the very first read throws.
    assert SumInt32ThrowName(values, -1, values.Length) == "System.IndexOutOfRangeException"
    assert ScalarSumInt32ThrowName(values, -1, values.Length) == "System.IndexOutOfRangeException"
    assert RuntimeSumInt32ThrowName(values, -1, values.Length) == "System.IndexOutOfRangeException"

    // A range long enough that the unrolled SIMD body WOULD have run had the guard not skipped it.
    assert SumInt32ThrowName(values, 0, values.Length + lanes * 4) == "System.IndexOutOfRangeException"
    assert SumInt32ThrowName(values, -lanes * 4, values.Length) == "System.IndexOutOfRangeException"

    assert SumInt64ThrowName(longValues, 0, longValues.Length + 1) == "System.IndexOutOfRangeException"
    assert SumInt64ThrowName(longValues, -1, longValues.Length) == "System.IndexOutOfRangeException"
    assert SumUInt32ThrowName(uintValues, 0, uintValues.Length + 1) == "System.IndexOutOfRangeException"
    assert SumUInt32ThrowName(uintValues, -1, uintValues.Length) == "System.IndexOutOfRangeException"
    assert SumUInt64ThrowName(ulongValues, 0, ulongValues.Length + 1) == "System.IndexOutOfRangeException"
    assert SumUInt64ThrowName(ulongValues, -1, ulongValues.Length) == "System.IndexOutOfRangeException"

    assert CountInRangeThrowName(values, 0, values.Length + 1, 0, 10) == "System.IndexOutOfRangeException"
    assert CountInRangeThrowName(values, -1, values.Length, 0, 10) == "System.IndexOutOfRangeException"
    assert RuntimeCountInRangeThrowName(values, 0, values.Length + 1, 0, 10) == "System.IndexOutOfRangeException"

    assert MinThrowName(values, 0, values.Length + 1, 0) == "System.IndexOutOfRangeException"
    assert MinThrowName(values, -1, values.Length, 0) == "System.IndexOutOfRangeException"
    assert MaxThrowName(values, 0, values.Length + 1, 0) == "System.IndexOutOfRangeException"
    assert MaxThrowName(values, -1, values.Length, 0) == "System.IndexOutOfRangeException"

    assert MinMaxThrowName(values, 0, values.Length + 1, 0, 0) == "System.IndexOutOfRangeException"
    assert MinMaxThrowName(values, -1, values.Length, 0, 0) == "System.IndexOutOfRangeException"
    assert RuntimeMinMaxThrowName(values, 0, values.Length + 1, 0, 0) == "System.IndexOutOfRangeException"

    assert CountTransitionsThrowName(values, 0, values.Length + 1, 0) == "System.IndexOutOfRangeException"
    assert CountTransitionsThrowName(values, -1, values.Length, 0) == "System.IndexOutOfRangeException"
    assert RuntimeCountTransitionsThrowName(values, 0, values.Length + 1, 0) == "System.IndexOutOfRangeException"
}

test "an in-bounds range beside an out-of-bounds one still computes the scalar answer" {
    lanes := Vector<int>.Count
    values := RandomInt32Array(lanes * 4 + 3, 8401)

    // The guard is `start >= 0 && end <= Length`, so the widest legal range is exactly the whole array --
    // one element further in either direction is the throwing case pinned above.
    assert SumInt32ThrowName(values, 0, values.Length) == "no throw: " + ScalarSumInt32(values, 0, values.Length).ToString()
    assert SumInt32ThrowName(values, 1, values.Length) == "no throw: " + ScalarSumInt32(values, 1, values.Length).ToString()
    assert MinMaxThrowName(values, 0, values.Length, 0, 0) == RuntimeMinMaxThrowName(values, 0, values.Length, 0, 0)
    assert CountTransitionsThrowName(values, 0, values.Length, 7) == RuntimeCountTransitionsThrowName(values, 0, values.Length, 7)
}

// ---------------------------------------------------------------------- CLR metadata

// The translation is not merely value-equal to the C# original: it presents the SAME signatures. The rows
// below read both types' metadata side by side rather than asserting a shape only the translation has.
//
// Reflection PROPERTIES are spelled as their accessor calls (`get_Name()` rather than `.Name`) throughout:
// the columnar emitter models the accessor call on `System.Reflection` types but declines the property
// syntax (see the stream report), and the compiler's own kernels are written the same way.

func MethodOf(owner: Type, name: string): MethodInfo {
    found := owner.GetMethod(name)
    if found == null {
        throw new InvalidOperationException("'" + owner.FullName + "." + name + "' was not found.")
    }

    return found
}

// The element names a method's NAMED tuple return declares, read out of CLR metadata as
// "first/second", or "" when the return carries no `TupleElementNamesAttribute` at all.
func ReturnTupleElementNames(method: MethodInfo): string {
    returnParameter := method.get_ReturnParameter()
    attributes := returnParameter.GetCustomAttributes(typeof(TupleElementNamesAttribute), false)
    if attributes.Length != 1 {
        return ""
    }

    declared := attributes[0] as TupleElementNamesAttribute
    if declared == null {
        return ""
    }

    // The attribute's transform names are exactly the tuple's arity, and both helpers return 2-tuples --
    // the `ValueTuple<int, int>` return type is pinned by its own row above, so reading two elements here
    // cannot silently read past the end.
    transformed := declared.get_TransformNames()
    return transformed[0] + "/" + transformed[1]
}

// THE ROW THAT KEEPS THE PARITY HONEST. Every "and the C# original" assertion in this file is worthless if
// the original side is secretly the translation: the comparison would pass by construction. N# resolves an
// unqualified type name to any same-named type declared in the compilation regardless of namespace, so a
// source class named `SimdReductions` WOULD have captured every `Original*` forwarder -- this file caught
// exactly that before the translation's class was renamed to `SimdReductionsPort`. This row pins the fix
// in metadata terms: the original is a different type, in the C# namespace, from a different assembly.
test "the original side of every parity row is the C# type from the runtime assembly, not the translation" {
    original := OriginalType()
    assert original != typeof(SimdReductionsPort)
    assert original.get_Namespace() == "NSharpLang.Runtime"
    assert original.get_Name() == "SimdReductions"
    assert original.get_Assembly() != typeof(SimdReductionsPort).get_Assembly()
    assert typeof(SimdReductionsPort).get_Namespace() == "NSharpLang.SimdReductions.Tests"

    // And the forwarders really route to it: the C# original is what answers, so a value the translation
    // could not have produced on its own is not what is being compared -- both must equal the oracle.
    values := RandomInt32Array(Vector<int>.Count * 4 + 3, 8501)
    expected := ScalarSumInt32(values, 0, values.Length)
    assert OriginalSumInt32(values, 0, values.Length) == expected
    assert SimdReductionsPort.SumInt32(values, 0, values.Length) == expected
}

test "the translated helpers carry the same CLR signatures as the C# original" {
    translated := typeof(SimdReductionsPort)
    original := OriginalType()

    names := ["SumInt32", "SumInt64", "SumUInt32", "SumUInt64", "CountInRangeInt32", "MinInt32", "MaxInt32", "MinMaxInt32", "CountTransitionsInt32"]
    i := 0
    while i < names.Length {
        translatedMethod := MethodOf(translated, names[i])
        originalMethod := MethodOf(original, names[i])
        assert translatedMethod.get_IsStatic()
        assert originalMethod.get_IsStatic()
        assert translatedMethod.get_ReturnType() == originalMethod.get_ReturnType()

        translatedParameters := translatedMethod.GetParameters()
        originalParameters := originalMethod.GetParameters()
        assert translatedParameters.Length == originalParameters.Length
        j := 0
        while j < translatedParameters.Length {
            assert translatedParameters[j].get_ParameterType() == originalParameters[j].get_ParameterType()
            assert translatedParameters[j].get_Name() == originalParameters[j].get_Name()
            j += 1
        }
        i += 1
    }
}

test "the fused min-max and transition helpers return ValueTuple, exactly as the C# original does" {
    translated := typeof(SimdReductionsPort)
    original := OriginalType()

    minMax := MethodOf(translated, "MinMaxInt32")
    assert minMax.get_ReturnType() == typeof(ValueTuple<int, int>)
    assert minMax.get_ReturnType() == MethodOf(original, "MinMaxInt32").get_ReturnType()

    transitions := MethodOf(translated, "CountTransitionsInt32")
    assert transitions.get_ReturnType() == typeof(ValueTuple<int, int>)
    assert transitions.get_ReturnType() == MethodOf(original, "CountTransitionsInt32").get_ReturnType()
}

// The row that justifies the two positional forwarders in `SimdReductionsOriginal.nl`: a named tuple's
// element names live in metadata, and this reads them off the C# original rather than assuming the order.
// If the C# author ever swapped `(int Min, int Max)` for `(int Max, int Min)`, this fails before any
// parity row could quietly compare the wrong halves.
test "the C# original's named tuple element names are Min/Max and Count/LastPrevious, in that order" {
    original := OriginalType()
    assert ReturnTupleElementNames(MethodOf(original, "MinMaxInt32")) == "Min/Max"
    assert ReturnTupleElementNames(MethodOf(original, "CountTransitionsInt32")) == "Count/LastPrevious"
}

// AND THE TRANSLATION PRESENTS THE SAME PUBLIC CONTRACT, not merely the same values. A named tuple has
// no CLR identity of its own -- `(int Min, int Max)` IS `ValueTuple<int, int>` -- so the element names a
// C# consumer sees live in a `TupleElementNamesAttribute` on the return position. When this file was
// written N# emitted none, so a C# consumer of the translation would have seen a bare `ValueTuple` with
// only `Item1`/`Item2` while the same consumer of the original saw `Min`/`Max`: a faithful translation
// that was not a faithful LIBRARY. Both sides are read the same way here, so the rows are equal only if
// the emitted attribute matches the C# compiler's byte for byte in name, order and arity.
test "the translated helpers carry the same tuple element names as the C# original, member for member" {
    translated := typeof(SimdReductionsPort)
    original := OriginalType()

    assert ReturnTupleElementNames(MethodOf(translated, "MinMaxInt32")) == ReturnTupleElementNames(MethodOf(original, "MinMaxInt32"))
    assert ReturnTupleElementNames(MethodOf(translated, "CountTransitionsInt32")) == ReturnTupleElementNames(MethodOf(original, "CountTransitionsInt32"))
    assert ReturnTupleElementNames(MethodOf(translated, "MinMaxInt32")) == "Min/Max"
    assert ReturnTupleElementNames(MethodOf(translated, "CountTransitionsInt32")) == "Count/LastPrevious"

    // A helper whose return is NOT a tuple carries no attribute on either side -- the negative half of
    // the same claim, so "both sides are empty" cannot pass for "both sides agree".
    assert ReturnTupleElementNames(MethodOf(translated, "SumInt32")) == ""
    assert ReturnTupleElementNames(MethodOf(original, "SumInt32")) == ""
}

// ---------------------------------------------------------------------- the compiler contracts this needed
//
// Translating the C# file turned up two emitter holes, both fixed in this stream. The rows below are the
// general contracts, not the SimdReductions-shaped corners of them, so a later regression is caught here
// rather than through a mysterious decline in the translation.

class UnsignedTotals {
    Total: uint
    LongTotal: ulong
}

// (1) COMPOUND ASSIGNMENT ON AN UNSIGNED ACCUMULATOR. `SumUInt32`'s `sum += array[i]` declined at
// emit.statement.block-child while the spelled-out `sum = sum + array[i]` emitted fine -- `uint` was simply
// missing from the IL-primitive arm that already carried int / long / ulong / double / float. The two
// spellings must agree, and DIVISION must be the unsigned opcode: every `/=` below is chosen so that a
// signed `div` would produce a different, visible answer.
test "compound assignment on an unsigned accumulator matches the spelled-out operator, with unsigned division" {
    added := 0u
    added += 3u
    spelledAdded := 0u
    spelledAdded = spelledAdded + 3u
    assert added == 3u
    assert added == spelledAdded

    // Wrapping subtraction below zero and wrapping multiplication past 2^32.
    subtracted := 1u
    subtracted -= 2u
    assert subtracted == 4294967295u

    multiplied := 3000000000u
    multiplied *= 3u
    assert multiplied == 410065408u

    // 4000000000 has bit 31 set: read as a SIGNED int it is -294967296, and `div` would answer 4147483648u.
    divided := 4000000000u
    divided /= 2u
    assert divided == 2000000000u

    longAdded := 0uL
    longAdded += 3uL
    assert longAdded == 3uL

    longDivided := 18000000000000000000uL
    longDivided /= 2uL
    assert longDivided == 9000000000000000000uL

    // The same operator on an ARRAY ELEMENT and on a FIELD, the other two compound targets.
    totals := new uint[](2)
    totals[0] = 4000000000u
    totals[0] += 1u
    totals[1] = 4000000000u
    totals[1] /= 2u
    assert totals[0] == 4000000001u
    assert totals[1] == 2000000000u

    holder := new UnsignedTotals()
    holder.Total = 4000000000u
    holder.Total /= 2u
    holder.LongTotal = 18000000000000000000uL
    holder.LongTotal /= 2uL
    assert holder.Total == 2000000000u
    assert holder.LongTotal == 9000000000000000000uL
}

class TupleReturns {
    Offset: int

    constructor(offset: int) {
        Offset = offset
    }

    func Shifted(low: int, high: int): (Low: int, High: int) {
        return (low + Offset, high + Offset)
    }

    static func Pair(low: int, high: int): (Low: int, High: int) {
        return (low, high)
    }
}

func FreeFunctionPair(low: int, high: int): (Low: int, High: int) {
    return (low, high)
}

// (2) NAMED TUPLE ELEMENT NAMES FROM A METHOD DECLARED ON A TYPE. The names of a tuple return are erased by
// `ValueTuple` at the IL level, so `pair.Low` is only emittable if the declaration's names reach the access.
// They did for a FREE FUNCTION and nowhere else: `MinMaxInt32` and `CountTransitionsInt32` are static
// methods on a class, and every element access on their results declined at emit.return.expression even
// though the analyser had resolved them. Static and instance methods now carry the names the same way.
test "a named tuple returned by a method declared on a type keeps its element names" {
    fromStatic := TupleReturns.Pair(1, 2)
    assert fromStatic.Low == 1
    assert fromStatic.High == 2

    instance := new TupleReturns(10)
    fromInstance := instance.Shifted(1, 2)
    assert fromInstance.Low == 11
    assert fromInstance.High == 12

    // The free-function path that already worked, kept beside them so a regression in either is visible.
    fromFree := FreeFunctionPair(3, 4)
    assert fromFree.Low == 3
    assert fromFree.High == 4

    // Positional deconstruction and the raw `ItemN` fields answer the same values, in the same order.
    staticLow, staticHigh := TupleReturns.Pair(5, 6)
    assert staticLow == 5
    assert staticHigh == 6
    assert fromStatic.Item1 == fromStatic.Low
    assert fromStatic.Item2 == fromStatic.High
}

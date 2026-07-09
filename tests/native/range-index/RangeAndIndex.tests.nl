namespace NSharpLang.RangeIndex.Tests

import System

enum RangeBound {
    Zero = 0,
    One = 1,
    Four = 4
}

func ReadFromEnd(values: int[], count: int): int {
    return values[^count]
}

func SliceArray(values: int[], start: int, end: int): int[] {
    return values[start..end]
}

func SliceString(value: string, start: int, end: int): string {
    return value[start..end]
}

test "range-index reads arrays and strings from the end" {
    values := [10, 20, 30, 40, 50]
    text := "abcdef"

    assert values[^1] == 50
    assert values[^3] == 30
    assert text[^1] == 'f'
    assert text[^3] == 'd'
}

test "range-index slices arrays with every endpoint shape" {
    values := [10, 20, 30, 40, 50]

    closed := values[1..4]
    assert closed.Length == 3
    assert closed[0] == 20
    assert closed[^1] == 40

    fromStart := values[..3]
    assert fromStart.Length == 3
    assert fromStart[0] == 10
    assert fromStart[^1] == 30

    toEnd := values[2..]
    assert toEnd.Length == 3
    assert toEnd[0] == 30
    assert toEnd[^1] == 50

    all := values[..]
    assert all.Length == 5
    assert all[0] == 10
    assert all[^1] == 50

    fromEnd := values[^4..^1]
    assert fromEnd.Length == 3
    assert fromEnd[0] == 20
    assert fromEnd[^1] == 40
}

test "range-index array slices are independent copies" {
    values := [10, 20, 30]
    copy := values[..]

    copy[0] = 99

    assert copy[0] == 99
    assert values[0] == 10
}

test "range-index slices strings with every endpoint shape" {
    text := "abcdef"

    assert text[1..4] == "bcd"
    assert text[..3] == "abc"
    assert text[2..] == "cdef"
    assert text[..] == "abcdef"
    assert text[^4..^1] == "cde"
}

test "range-index slices reference arrays" {
    words := ["zero", "one", "two", "three"]

    middle := words[1..^1]

    assert middle.Length == 2
    assert middle[0] == "one"
    assert middle[1] == "two"
}

test "range-index supports typed Index and Range values" {
    values := [10, 20, 30, 40, 50]
    text := "abcdef"
    last: Index = ^2
    window: Range = 1..^1

    assert values[last] == 40
    assert text[last] == 'e'

    windowValues := values[window]
    assert windowValues.Length == 3
    assert windowValues[0] == 20
    assert windowValues[^1] == 40
    assert text[window] == "bcde"
}

test "range-index widens small integer endpoints and preserves parentheses" {
    values := [10, 20, 30, 40, 50]
    text := "abcdef"
    start: byte = 1
    end: short = 4
    fromEndCount: byte = 2

    smallBounds := values[start..end]
    parenthesizedStart := values[(start)..end]

    assert smallBounds.Length == 3
    assert smallBounds[0] == 20
    assert smallBounds[^1] == 40
    assert parenthesizedStart.Length == 3
    assert parenthesizedStart[0] == 20
    assert parenthesizedStart[^1] == 40
    assert values[^fromEndCount] == 40
    assert text[^fromEndCount] == 'e'
}

test "range-index accepts Index-typed range endpoints" {
    values := [10, 20, 30, 40, 50]
    rangeStart: Index = ^4
    rangeEnd: Index = ^1

    bounded := values[rangeStart..rangeEnd]

    assert bounded.Length == 3
    assert bounded[0] == 20
    assert bounded[^1] == 40
}

test "range-index preserves conditional Index and Range values" {
    values := [10, 20, 30, 40, 50]
    chooseLast := true

    selectedValue := values[chooseLast ? ^1 : ^2]
    selectedRange := values[chooseLast ? (1..^1) : (..)]

    assert selectedValue == 50
    assert selectedRange[0] == 20
    assert selectedRange[^1] == 40

    chooseLast = false
    alternateValue := values[chooseLast ? ^1 : ^2]
    alternateRange := values[chooseLast ? (1..^1) : (..)]

    assert alternateValue == 40
    assert alternateRange[0] == 10
    assert alternateRange[^1] == 50
}

test "range-index accepts enum endpoints and from-end counts" {
    values := [10, 20, 30, 40, 50]

    bounded := values[RangeBound.One..RangeBound.Four]

    assert bounded.Length == 3
    assert bounded[0] == 20
    assert bounded[^1] == 40
    assert values[^RangeBound.One] == 50
}

test "range-index rejects a negative from-end count at runtime" {
    values := [10, 20, 30]

    assert throws ArgumentOutOfRangeException {
        ReadFromEnd(values, -1)
    }
}

test "range-index rejects the end sentinel as an element index" {
    values := [10, 20, 30]

    assert throws IndexOutOfRangeException {
        ReadFromEnd(values, 0)
    }
}

test "range-index rejects reversed array and string ranges" {
    values := [10, 20, 30]

    assert throws ArgumentOutOfRangeException {
        SliceArray(values, 2, 1)
    }
    assert throws ArgumentOutOfRangeException {
        SliceString("abc", 2, 1)
    }
}

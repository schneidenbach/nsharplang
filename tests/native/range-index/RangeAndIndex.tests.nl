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

func ReadFromEndByIndexedCount(values: int[], counts: int[]): int {
    return values[^counts[0]]
}

func ReadFromEndByStringCount(values: int[], counts: string): int {
    return values[^counts[0]]
}

func ReadFromEndOfFirstRow(matrix: int[][]): int {
    return matrix[0][^1]
}

func SliceArray(values: int[], start: int, end: int): int[] {
    return values[start..end]
}

func SliceString(value: string, start: int, end: int): string {
    return value[start..end]
}

func ReadAt(values: int[], at: Index): int {
    return values[at]
}

func SliceAt(values: int[], window: Range): int[] {
    return values[window]
}

func ReadLast<T>(values: T[]): T {
    return values[^1]
}

func SliceAll<T>(values: T[]): T[] {
    return values[..]
}

test "range-index reads arrays and strings from the end" {
    values := [10, 20, 30, 40, 50]
    text := "abcdef"

    assert values[^1] == 50
    assert values[^3] == 30
    assert text[^1] == 'f'
    assert text[^3] == 'd'
}

test "range-index owns ordinary Int32 indexing beneath from-end roots" {
    values := [10, 20, 30, 40, 50]
    counts := [2]
    first := [10, 20, 30]
    second := [40, 50]
    matrix: int[][] = [first, second]
    stringCounts := new string((char)2, 1)

    assert values[^counts[0]] == 40
    assert values[^stringCounts[0]] == 40
    assert matrix[0][^1] == 30
    assert ReadFromEndByIndexedCount(values, counts) == 40
    assert ReadFromEndByStringCount(values, stringCounts) == 40
    assert ReadFromEndOfFirstRow(matrix) == 30
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

    explicitEnd := values[1..^0]
    assert explicitEnd.Length == 4
    assert explicitEnd[0] == 20
    assert explicitEnd[^1] == 50
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
    genericCopy := SliceAll(words)

    assert middle.Length == 2
    assert middle[0] == "one"
    assert middle[1] == "two"
    assert words[^1] == "three"

    middle[0] = "changed"
    genericCopy[1] = "changed"

    assert words[1] == "one"
    assert genericCopy[^1] == "three"
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
    assert ReadAt(values, last) == 40
    viaParameter := SliceAt(values, window)
    assert viaParameter.Length == 3
    assert viaParameter[0] == 20
    assert viaParameter[^1] == 40
}

test "range-index loads every primitive and generic array element family" {
    bools: bool[] = [false, true]
    chars: char[] = ['a', 'z']
    uints: uint[] = [1, 9]
    longs: long[] = [2, 10]
    ulongs: ulong[] = [3, 11]
    floats: float[] = [(float)1.5, (float)2.5]
    doubles: double[] = [3.5, 4.5]
    bytes: byte[] = [4, 12]
    sbytes: sbyte[] = [5, 13]
    shorts: short[] = [6, 14]
    ushorts: ushort[] = [7, 15]
    words: string[] = ["first", "last"]

    assert bools[^1]
    assert chars[^1] == 'z'
    assert uints[^1] == (uint)9
    assert longs[^1] == 10
    assert ulongs[^1] == (ulong)11
    assert floats[^1] == (float)2.5
    assert doubles[^1] == 4.5
    assert bytes[^1] == 12
    assert sbytes[^1] == 13
    assert shorts[^1] == 14
    assert ushorts[^1] == 15
    assert words[^1] == "last"
    assert ReadLast(words) == "last"
    assert ReadLast(uints) == (uint)9
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

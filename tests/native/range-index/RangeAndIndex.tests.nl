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

func ReturnBoundParameter(value: int): int {
    return value
}

func ReturnBoundLocal(value: int): int {
    local := value
    return local
}

func ReadFromEndByLocal(values: int[]): int {
    count := 2
    return values[^count]
}

func ReadFromEndByLiftedLocal(values: int[]): int {
    count := 1
    reader: Func<int[], int> = input => input[^count]
    count = 2
    outer := values[^count]
    return (outer * 100) + reader(values)
}

func ReadFromEndByLiftedParameter(values: int[], count: int): int {
    reader: Func<int[], int> = input => input[^count]
    count = 3
    outer := values[^count]
    return (outer * 100) + reader(values)
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

func ReturnEnvironmentNewLine(): string {
    return Environment.NewLine
}

func ReturnInterpolatedEnvironmentNewLine(): string {
    return $"{Environment.NewLine}"
}

func ReturnUnixEpochYear(): int {
    return DateTime.UnixEpoch.Year
}

func ReadEnvironmentNewLineLast(): char {
    return Environment.NewLine[^1]
}

func SliceCurrentDirectoryPrefix(): string {
    return Environment.CurrentDirectory[0..1]
}

func ReadEnvironmentArrayFirst(): string {
    values := [Environment.NewLine]
    return values[0]
}

class ExternalStaticMemberReader {
    func ReadNewLine(): string {
        return Environment.NewLine
    }
}

class ExplicitThisRangeReader {
    count: int

    constructor(initialCount: int) {
        this.count = initialCount
    }

    func ReadWithTriviaBeforeDot(values: int[], count: string): int {
        if count == "" {
            throw new ArgumentOutOfRangeException("count")
        }
        return values[^this .count]
    }

    func ReadWithTriviaAfterDot(values: int[], count: int): int {
        if count < 0 {
            throw new ArgumentOutOfRangeException("count")
        }
        return values[^this. count]
    }

    func SetWithCommentTrivia(count: int) {
        this /* field, not the parameter */ . count = count
    }
}

class CurrentClassRangeReader {
    count: int
    start: int

    constructor(initialCount: int, initialStart: int) {
        this.count = initialCount
        this.start = initialStart
    }

    Count: int => count
    Start: int => start

    func ReadBareField(): int {
        return count
    }

    func ReadExplicitField(): int {
        return this.count
    }

    func ReadBareProperty(): int {
        return Count
    }

    func ReadExplicitProperty(): int {
        return this.Count
    }

    func ReadByBareField(values: int[]): int {
        return values[^count]
    }

    func ReadByExplicitField(values: int[]): int {
        return values[^this.count]
    }

    func ReadByBareProperty(values: int[]): int {
        return values[^Count]
    }

    func ReadByExplicitProperty(values: int[]): int {
        return values[^this.Count]
    }

    func SliceByBareProperties(values: int[]): int[] {
        return values[Start..^Count]
    }

    func SliceByExplicitProperties(values: int[]): int[] {
        return values[this.Start..^this.Count]
    }

    func ReadFromNestedSlice(values: int[]): int {
        return values[Start..^Count][^count]
    }
}

struct CurrentStructRangeReader {
    count: int
    start: int

    constructor(initialCount: int, initialStart: int) {
        this.count = initialCount
        this.start = initialStart
    }

    Count: int => count
    Start: int => start

    func ReadBareField(): int {
        return count
    }

    func ReadExplicitField(): int {
        return this.count
    }

    func ReadBareProperty(): int {
        return Count
    }

    func ReadExplicitProperty(): int {
        return this.Count
    }

    func ReadByBareField(values: int[]): int {
        return values[^count]
    }

    func ReadByExplicitField(values: int[]): int {
        return values[^this.count]
    }

    func ReadByBareProperty(values: int[]): int {
        return values[^Count]
    }

    func ReadByExplicitProperty(values: int[]): int {
        return values[^this.Count]
    }

    func SliceByBareProperties(values: int[]): int[] {
        return values[Start..^Count]
    }

    func SliceByExplicitProperties(values: int[]): int[] {
        return values[this.Start..^this.Count]
    }
}

class GenericCurrentClassReader<T> {
    value: T
    count: int

    constructor(initialValue: T, initialCount: int) {
        this.value = initialValue
        this.count = initialCount
    }

    Value: T => value
    Count: int => count

    func ReadField(): T {
        return value
    }

    func ReadProperty(): T {
        return Value
    }

    func ReadFromEnd(values: int[]): int {
        return values[^Count]
    }
}

struct GenericCurrentStructReader<T> {
    value: T
    count: int

    constructor(initialValue: T, initialCount: int) {
        this.value = initialValue
        this.count = initialCount
    }

    Value: T => value
    Count: int => count

    func ReadField(): T {
        return value
    }

    func ReadProperty(): T {
        return Value
    }

    func ReadFromEnd(values: int[]): int {
        return values[^Count]
    }
}

class CurrentSourceValue {
    code: int

    constructor(value: int) {
        this.code = value
    }

    func Read(): int {
        return code
    }
}

class CurrentSourcePropertyReader {
    value: CurrentSourceValue

    constructor(initialValue: CurrentSourceValue) {
        this.value = initialValue
    }

    Value: CurrentSourceValue => value

    func ReadProperty(): CurrentSourceValue {
        return Value
    }
}

class SnapshotCurrentReader {
    count: int

    constructor(initialCount: int) {
        this.count = initialCount
    }

    func Read(): int {
        return count
    }
}

func ReadSnapshotCaptures(values: int[]): int {
    count := 2
    reader := new SnapshotCurrentReader(3)
    readCount: Func<int> = () => reader.Read()
    readValue: Func<int[], int> = input => input[^count]
    return (readCount() * 100) + readValue(values)
}

class InheritedRangeBase {
    inheritedCount: int
    inheritedStart: int

    constructor(initialCount: int, initialStart: int) {
        this.inheritedCount = initialCount
        this.inheritedStart = initialStart
    }

    InheritedCount: int => inheritedCount
    InheritedStart: int => inheritedStart
}

class InheritedRangeReader: InheritedRangeBase {
    constructor(initialCount: int, initialStart: int): base(initialCount, initialStart) {}

    func ReadBareField(): int {
        return inheritedCount
    }

    func ReadExplicitField(): int {
        return this.inheritedCount
    }

    func ReadBareProperty(): int {
        return InheritedCount
    }

    func ReadExplicitProperty(): int {
        return this.InheritedCount
    }

    func ReadByBareField(values: int[]): int {
        return values[^inheritedCount]
    }

    func ReadByExplicitField(values: int[]): int {
        return values[^this.inheritedCount]
    }

    func ReadByBareProperty(values: int[]): int {
        return values[^InheritedCount]
    }

    func ReadByExplicitProperty(values: int[]): int {
        return values[^this.InheritedCount]
    }

    func SliceByBareProperties(values: int[]): int[] {
        return values[InheritedStart..^InheritedCount]
    }

    func SliceByExplicitProperties(values: int[]): int[] {
        return values[this.InheritedStart..^this.InheritedCount]
    }
}

test "range-index reads arrays and strings from the end" {
    values := [10, 20, 30, 40, 50]
    text := "abcdef"

    assert values[^1] == 50
    assert values[^3] == 30
    assert text[^1] == 'f'
    assert text[^3] == 'd'
}

test "bound identifier plans persist every lexical storage form" {
    values := [10, 20, 30, 40, 50]

    assert ReturnBoundParameter(41) == 41
    assert ReturnBoundLocal(42) == 42
    assert ReadFromEnd(values, 1) == 50
    assert ReadFromEndByLocal(values) == 40
    assert ReadFromEndByLiftedLocal(values) == 4040
    assert ReadFromEndByLiftedParameter(values, 1) == 3030
}

test "external static fields and properties execute through N sharp plans" {
    newLine := ReturnEnvironmentNewLine()
    currentDirectory := Environment.CurrentDirectory
    reader := new ExternalStaticMemberReader()

    assert newLine.Length > 0
    assert newLine == Environment.NewLine
    assert ReturnInterpolatedEnvironmentNewLine() == newLine
    assert reader.ReadNewLine() == newLine
    assert ReadEnvironmentArrayFirst() == newLine
    assert ReturnUnixEpochYear() == 1970
    assert ReadEnvironmentNewLineLast() == '\n'
    assert currentDirectory.Length > 0
    assert SliceCurrentDirectoryPrefix().Length == 1
    assert SliceCurrentDirectoryPrefix()[0] == currentDirectory[0]
}

test "explicit-this fields remain distinct from same-named parameters across trivia" {
    values := [10, 20, 30, 40]
    reader := new ExplicitThisRangeReader(1)

    assert reader.ReadWithTriviaBeforeDot(values, "shadow") == 40
    assert reader.ReadWithTriviaAfterDot(values, 2) == 40

    reader.SetWithCommentTrivia(3)
    assert reader.ReadWithTriviaBeforeDot(values, "still shadowed") == 20
}

test "current class fields and properties persist as direct and recursive identifier reads" {
    values := [10, 20, 30, 40, 50, 60]
    reader := new CurrentClassRangeReader(2, 1)

    assert reader.ReadBareField() == 2
    assert reader.ReadExplicitField() == 2
    assert reader.ReadBareProperty() == 2
    assert reader.ReadExplicitProperty() == 2
    assert reader.ReadByBareField(values) == 50
    assert reader.ReadByExplicitField(values) == 50
    assert reader.ReadByBareProperty(values) == 50
    assert reader.ReadByExplicitProperty(values) == 50

    bareSlice := reader.SliceByBareProperties(values)
    explicitSlice := reader.SliceByExplicitProperties(values)
    assert bareSlice.Length == 3
    assert bareSlice[0] == 20
    assert bareSlice[^1] == 40
    assert explicitSlice.Length == 3
    assert explicitSlice[0] == 20
    assert explicitSlice[^1] == 40
    assert reader.ReadFromNestedSlice(values) == 30
}

test "value-type current instances preserve address loads for fields and properties" {
    values := [10, 20, 30, 40, 50, 60]
    reader := new CurrentStructRangeReader(1, 2)

    assert reader.ReadBareField() == 1
    assert reader.ReadExplicitField() == 1
    assert reader.ReadBareProperty() == 1
    assert reader.ReadExplicitProperty() == 1
    assert reader.ReadByBareField(values) == 60
    assert reader.ReadByExplicitField(values) == 60
    assert reader.ReadByBareProperty(values) == 60
    assert reader.ReadByExplicitProperty(values) == 60

    bareSlice := reader.SliceByBareProperties(values)
    explicitSlice := reader.SliceByExplicitProperties(values)
    assert bareSlice.Length == 3
    assert bareSlice[0] == 30
    assert bareSlice[^1] == 50
    assert explicitSlice.Length == 3
    assert explicitSlice[0] == 30
    assert explicitSlice[^1] == 50
}

test "generic current classes preserve open receiver identity" {
    values := [10, 20, 30, 40]
    classReader := new GenericCurrentClassReader<string>("class", 1)

    assert classReader.ReadField() == "class"
    assert classReader.ReadProperty() == "class"
    assert classReader.ReadFromEnd(values) == 40
}

test "generic current structs preserve open receiver identity" {
    values := [10, 20, 30, 40]
    structReader := new GenericCurrentStructReader<string>("struct", 2)

    assert structReader.ReadField() == "struct"
    assert structReader.ReadProperty() == "struct"
    assert structReader.ReadFromEnd(values) == 30
}

test "current source-type properties preserve unbaked return identity" {
    reader := new CurrentSourcePropertyReader(new CurrentSourceValue(47))
    value := reader.ReadProperty()

    assert value.Read() == 47
}

test "snapshot closure fields remain exact current-instance bindings" {
    values := [10, 20, 30, 40]
    assert ReadSnapshotCaptures(values) == 330
}

test "current-instance lookup reaches inherited fields and properties" {
    values := [10, 20, 30, 40, 50, 60]
    reader := new InheritedRangeReader(2, 1)

    assert reader.ReadBareField() == 2
    assert reader.ReadExplicitField() == 2
    assert reader.ReadBareProperty() == 2
    assert reader.ReadExplicitProperty() == 2
    assert reader.ReadByBareField(values) == 50
    assert reader.ReadByExplicitField(values) == 50
    assert reader.ReadByBareProperty(values) == 50
    assert reader.ReadByExplicitProperty(values) == 50

    bareSlice := reader.SliceByBareProperties(values)
    explicitSlice := reader.SliceByExplicitProperties(values)
    assert bareSlice.Length == 3
    assert bareSlice[0] == 20
    assert bareSlice[^1] == 40
    assert explicitSlice.Length == 3
    assert explicitSlice[0] == 20
    assert explicitSlice[^1] == 40
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

test "range-index owns constant and nameof receivers and character endpoints" {
    values := [10, 20, 30]

    assert "values"[^1] == 's'
    assert "values"[1..^1] == "alue"
    assert nameof(values) == "values"
    assert nameof(values.Length) == "Length"
    assert nameof(values)[^1] == 's'
    assert nameof(values.Length)[^1] == 'h'

    text := new string('x', 68)
    assert text[^'A'] == 'x'
    characterWindow := text['A'..'C']
    assert characterWindow.Length == 2
    assert characterWindow == "xx"
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
    assert throws ArgumentOutOfRangeException {
        _ignored := values[^-1]
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

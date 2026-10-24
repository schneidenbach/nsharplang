namespace NSharpLang.CensusParameterDefaults.Tests

import System

enum Level {
    Low,
    High
}

enum Access {
    None = 0,
    Read = 1,
    Write = 2,
    Execute = 4
}

struct Span {
    Start: int
    Length: int
}

// One declaration per constant kind a parameter default can hold. The calls that omit them live in
// `Calls.nl`, so every one is filled from ANOTHER file of the same project.
func longDefault(value: long = 5000000000L): long {
    return value
}

func negativeLongDefault(value: long = -9000000000L): long {
    return value
}

func adoptedLongDefault(value: long = 42): long {
    return value
}

func byteDefault(value: byte = 255): byte {
    return value
}

func sbyteDefault(value: sbyte = -128): sbyte {
    return value
}

func shortDefault(value: short = -32768): short {
    return value
}

func ushortDefault(value: ushort = 65535): ushort {
    return value
}

func uintDefault(value: uint = 4000000000u): uint {
    return value
}

func ulongDefault(value: ulong = 18446744073709551615UL): ulong {
    return value
}

func negativeIntDefault(value: int = -2147483648): int {
    return value
}

func hexIntDefault(value: int = 0x7F): int {
    return value
}

func charDefault(value: char = 'z'): char {
    return value
}

func escapedCharDefault(value: char = '\n'): char {
    return value
}

func floatDefault(value: float = 1.5f): float {
    return value
}

func doubleDefault(value: double = 2.5): double {
    return value
}

func negativeDoubleDefault(value: double = -0.125): double {
    return value
}

func integerDoubleDefault(value: double = 3): double {
    return value
}

func decimalDefault(value: decimal = 1.25m): decimal {
    return value
}

func negativeDecimalDefault(value: decimal = -0.5m): decimal {
    return value
}

func nullableIntDefault(value: int? = null): string {
    return value == null ? "none" : "some"
}

func nullableValueDefault(value: int? = 12): int {
    return value ?? -1
}

func nullableDecimalDefault(value: decimal? = 2.5m): decimal {
    return value ?? -1m
}

func dateDefault(value: DateTime = default): long {
    return value.Ticks
}

func intZeroDefault(value: int = default): int {
    return value
}

func decimalZeroDefault(value: decimal = default): decimal {
    return value
}

func enumZeroDefault(value: Level = default): Level {
    return value
}

func structZeroDefault(value: Span = default): int {
    return value.Start + value.Length
}

func stringNullDefault(value: string? = default): string {
    return value ?? "null"
}

func nullableDateDefault(value: DateTime? = default): string {
    return value == null ? "none" : "some"
}

// CONSTANT EXPRESSIONS, folded at compile time exactly as C# folds them.
func productDefault(value: int = 2 * 3): int {
    return value
}

func maskDefault(value: long = (1L << 40) - 1): long {
    return value
}

func widenedDefault(value: long = 2 * 3): long {
    return value
}

func ratioDefault(value: double = 1.0 / 4): double {
    return value
}

func truncatedDefault(value: double = 1 / 2): double {
    return value
}

func moneyDefault(value: decimal = 10m * 1.5m): decimal {
    return value
}

func joinedDefault(value: string = "ab" + "cd"): string {
    return value
}

func negatedDefault(value: int = -(3 + 4)): int {
    return value
}

func xorDefault(value: uint = 0xFFu ^ 0x0Fu): uint {
    return value
}

func flagsDefault(value: Access = Access.Read | Access.Write): Access {
    return value
}

func maskedFlagsDefault(value: Access = ~Access.Read & (Access.Write | Access.Execute)): Access {
    return value
}

func nullableFlagsDefault(value: Access? = Access.Write | Access.Execute): Access {
    return value ?? Access.None
}

func zeroFlagsDefault(value: Access = 0): Access {
    return value
}

class Meter {
    Width: long
    Ratio: decimal
    Mark: char
    Limit: int?
    Moment: DateTime

    constructor(width: long = 5000000000L, ratio: decimal = 1.25m, mark: char = 'm', limit: int? = null, moment: DateTime = default) {
        Width = width
        Ratio = ratio
        Mark = mark
        Limit = limit
        Moment = moment
    }

    func Factor(factor: double = 0.5): double {
        return factor
    }

    func Offset(offset: decimal = 10m): decimal {
        return offset
    }

    static func Pick(first: byte = 1, second: char = 'b', third: float = 0.75f): bool {
        return first == 1 && second == 'b' && third == 0.75f
    }
}

struct Gauge {
    Scale: double
    Extra: uint

    constructor(scale: double = -1.5, extra: uint = 7u) {
        Scale = scale
        Extra = extra
    }
}

class Window(width: long = 640L, ratio: decimal = 1.5m, title: char = 'w') {
    func Width(): long {
        return width
    }

    func Ratio(): decimal {
        return ratio
    }

    func Title(): char {
        return title
    }
}

class Grant {
    Mode: Access
    Size: int

    constructor(mode: Access = Access.Read | Access.Execute, size: int = 4 * 1024) {
        Mode = mode
        Size = size
    }
}

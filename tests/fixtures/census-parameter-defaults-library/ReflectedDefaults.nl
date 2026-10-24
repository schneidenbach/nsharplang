namespace NSharpLang.CensusParameterDefaults.Library

import System

enum Tone {
    Quiet,
    Loud
}

// Every constant kind a parameter default can hold, compiled into a SEPARATE assembly, so a call that
// omits the argument reads the default back out of metadata rather than out of source.
class ReflectedDefaults {
    Width: long
    Ratio: decimal
    Mark: char
    Limit: int?

    constructor(width: long = 5000000000L, ratio: decimal = 1.25m, mark: char = 'm', limit: int? = null) {
        Width = width
        Ratio = ratio
        Mark = mark
        Limit = limit
    }

    static func Long(value: long = -5000000000L): long {
        return value
    }

    static func Byte(value: byte = 200): byte {
        return value
    }

    static func UInt(value: uint = 4000000000u): uint {
        return value
    }

    static func ULong(value: ulong = 18446744073709551615UL): ulong {
        return value
    }

    static func Char(value: char = 'q'): char {
        return value
    }

    static func Float(value: float = 0.25f): float {
        return value
    }

    static func Double(value: double = -2.5): double {
        return value
    }

    static func Decimal(value: decimal = -79.125m): decimal {
        return value
    }

    static func NullableInt(value: int? = null): string {
        return value == null ? "none" : "some"
    }

    static func NullableLong(value: long? = 7L): long {
        return value ?? -1L
    }

    static func Date(value: DateTime = default): long {
        return value.Ticks
    }

    static func ToneDefault(value: Tone = default): Tone {
        return value
    }

    // GENERIC declarations with a defaulted tail. A call that writes only the value infers `T` from
    // it and fills the rest from metadata, the shape of `JsonSerializer.Serialize(value)`.
    static func Tag<T>(value: T, label: string = "tag"): string {
        return $"{label}:{value}"
    }

    func Join<T>(first: T, second: T, separator: char = '|'): string {
        return $"{first}{separator}{second}"
    }

    func Factor(factor: double = 0.5): double {
        return factor
    }

    func Offset(offset: decimal = 10m): decimal {
        return offset
    }
}

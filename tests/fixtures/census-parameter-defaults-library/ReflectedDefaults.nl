namespace NSharpLang.CensusParameterDefaults.Library

import System

enum Tone {
    Quiet,
    Loud
}

enum Rights {
    None = 0,
    Read = 1,
    Write = 2
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

    static func Mask(value: long = (1L << 40) - 1): long {
        return value
    }

    static func Both(value: Rights = Rights.Read | Rights.Write): Rights {
        return value
    }

    static func Scaled(value: decimal = 10m * 1.5m): decimal {
        return value
    }

    func Factor(factor: double = 0.5): double {
        return factor
    }

    func Offset(offset: decimal = 10m): decimal {
        return offset
    }
}

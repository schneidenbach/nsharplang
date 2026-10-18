namespace NSharpLang.CensusEmitShapes.Tests

// Unsuffixed literals use the first of int, uint, long, ulong that holds the value.
func UnsuffixedIntLiteral(): int {
    value := 2147483647
    return value
}

func UnsuffixedLongMask(): long {
    mask: long = 4294967295
    return mask
}

func UnsuffixedUlongMask(): ulong {
    mask: ulong = 18446744073709551615
    return mask
}

func UnsuffixedUintLiteral(): uint {
    value := 4294967295
    typed: uint = value
    return typed / 2
}

func UnsuffixedLongLiteral(): long {
    value := 5000000000
    typed: long = value
    return typed + 1
}

func UnsuffixedUlongLiteral(): ulong {
    value := 9223372036854775808
    typed: ulong = value
    return typed
}

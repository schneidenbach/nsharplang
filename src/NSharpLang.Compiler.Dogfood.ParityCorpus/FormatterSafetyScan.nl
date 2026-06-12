// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/FormatterSafetyScan.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func FormatterSafetyErrorIndicesChecksumInto(
    severities: int[],
    resultIndices: int[]): int {
    resultCount := FormatterSafetyErrorIndicesInto(severities, resultIndices)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultIndices.Length {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + (i + 1) * 13
        i = i + 1
    }

    return checksum
}

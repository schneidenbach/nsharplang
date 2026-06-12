// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/PathMatching.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CodeIntelligencePathMatchChecksumInto(
    fullPaths: string[],
    queryPaths: string[],
    resultFlags: int[]): int {
    count := CodeIntelligencePathMatchFlagsInto(fullPaths, queryPaths, resultFlags)
    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultFlags[i] * (i + 1) * 31
        i = i + 1
    }

    return checksum
}

// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/ProjectSourceFilter.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

// Order-stable checksum over the kept indices. Used to assert parity cheaply in benchmark setup
// without materializing the kept string set on the managed side.
func ProjectSourceFilterKeptChecksumInto(
    relativePaths: string[],
    excludePatterns: string[],
    includeTests: int,
    resultIndices: int[]): int {
    count := ProjectSourceFilterKeptIndicesInto(
        relativePaths,
        excludePatterns,
        includeTests,
        resultIndices)
    checksum := count
    i := 0
    while i < count {
        checksum = checksum + (resultIndices[i] + 1) * (i + 1) * 31
        i = i + 1
    }

    return checksum
}

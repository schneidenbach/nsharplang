// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/AnonymousUnionShims.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func AnonymousUnionDeclaresPublicShimChecksum(parameterFlags: int[], count: int): int {
    result := AnonymousUnionDeclaresPublicShim(parameterFlags, count)
    if result < 0 {
        return result
    }

    checksum := result * 17 + count
    i := 0
    while i < count {
        checksum = checksum + parameterFlags[i] * 31 + (i + 1) * 7
        i = i + 1
    }

    return checksum
}

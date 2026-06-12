// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/LexerTokenKindScanner.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func ParserTokenCompactionChecksumInto(tokenKinds: int[], resultIndices: int[]): int {
    length := tokenKinds.Length
    if resultIndices.Length < length {
        compactedCount := ParserTokenCompactionIndicesInto(tokenKinds, resultIndices)
        checksum := compactedCount

        i := 0
        while i < compactedCount {
            index := resultIndices[i]
            checksum = checksum + (i + 1) * 97 + tokenKinds[index] * 17
            i = i + 1
        }

        return checksum
    }

    compactedCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        if tokenKinds[i] != 136 {
            resultIndices[compactedCount] = i
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[i] * 17
            compactedCount = compactedCount + 1
        }

        next := i + 1
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 2
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 3
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 4
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 5
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 6
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 7
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        i = i + 8
    }

    while i < length {
        if tokenKinds[i] != 136 {
            resultIndices[compactedCount] = i
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[i] * 17
            compactedCount = compactedCount + 1
        }

        i = i + 1
    }

    return checksum + compactedCount
}

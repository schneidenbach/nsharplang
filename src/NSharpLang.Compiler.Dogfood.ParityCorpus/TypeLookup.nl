// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/TypeLookup.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

struct DeclaredTypeExactNameTable {
    Names: string[]
    TailHashes: int[]
}

func DeclaredTypeExactNameCapacity(types: &DeclaredTypeExactNameTable): int {
    return TypeLookupMinInt(types.Names.Length, types.TailHashes.Length)
}

func DeclaredTypeExactNameFirstIndex(
    names: string[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int): int {
    types := new DeclaredTypeExactNameTable { Names: names, TailHashes: tailHashes }
    return DeclaredTypeExactNameFirstIndexCore(ref types, typeName, queryTailHash, count)
}

func DeclaredTypeExactNameFirstIndexCore(
    types: &DeclaredTypeExactNameTable,
    typeName: string,
    queryTailHash: int,
    count: int): int {
    if count < 0 || count > DeclaredTypeExactNameCapacity(ref types) {
        return -2
    }

    useTailHash := typeName.Length > 0
    i := 0
    while i < count {
        if (!useTailHash || types.TailHashes[i] == queryTailHash)
            && types.Names[i] == typeName {
            return i + 1
        }

        i = i + 1
    }

    return 0
}

func DeclaredTypeUniqueSuffixValueRankChecksum(
    keys: string[],
    valueRanks: int[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int,
    rankWeights: int[]): int {
    rank := DeclaredTypeUniqueSuffixValueRank(keys, valueRanks, tailHashes, typeName, queryTailHash, count)
    if rank <= 0 {
        return rank
    }

    weight := 0
    if rank < rankWeights.Length {
        weight = rankWeights[rank]
    }

    return rank * 97 + weight * 31
}

func DeclaredTypeNameCandidateChecksum(
    names: string[],
    importedNamespaceFlags: int[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int,
    nameWeights: int[]): int {
    index := DeclaredTypeNameCandidateIndex(names, importedNamespaceFlags, tailHashes, typeName, queryTailHash, count)
    if index <= 0 {
        return index
    }

    weight := 0
    if index - 1 < nameWeights.Length {
        weight = nameWeights[index - 1]
    }

    return index * 97 + weight * 31
}

func TypeCreationOrderChecksumInto(
    keys: string[],
    count: int,
    dotCounts: int[],
    depthCounts: int[],
    depthOffsets: int[],
    resultIndices: int[],
    keyWeights: int[]): int {
    orderedCount := TypeCreationOrderIndicesInto(keys, count, dotCounts, depthCounts, depthOffsets, resultIndices)
    if orderedCount < 0 {
        return orderedCount
    }

    checksum := orderedCount
    i := 0
    while i < orderedCount {
        sourceIndex := resultIndices[i]
        weight := 0
        if sourceIndex >= 0 && sourceIndex < keyWeights.Length {
            weight = keyWeights[sourceIndex]
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + dotCounts[sourceIndex] * 17 + weight * 13
        i = i + 1
    }

    return checksum
}

func DeclaredTypeExactNameFirstChecksum(
    names: string[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int,
    nameWeights: int[]): int {
    index := DeclaredTypeExactNameFirstIndex(names, tailHashes, typeName, queryTailHash, count)
    if index <= 0 {
        return index
    }

    weight := 0
    if index - 1 < nameWeights.Length {
        weight = nameWeights[index - 1]
    }

    return index * 97 + weight * 31
}

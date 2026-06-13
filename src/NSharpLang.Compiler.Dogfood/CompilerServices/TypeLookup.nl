struct DeclaredTypeValueRankTable {
    Keys: string[]
    ValueRanks: int[]
    TailHashes: int[]
}

struct DeclaredTypeNameCandidateTable {
    Names: string[]
    ImportedNamespaceFlags: int[]
    TailHashes: int[]
}

struct DeclaredTypeExactNameTable {
    Names: string[]
    TailHashes: int[]
}

struct TypeCreationOrderTable {
    Keys: string[]
    DotCounts: int[]
    DepthCounts: int[]
    DepthOffsets: int[]
    ResultIndices: int[]
}

func DeclaredTypeValueRankCapacity(types: &DeclaredTypeValueRankTable): int {
    count := TypeLookupMinInt(types.Keys.Length, types.ValueRanks.Length)
    count = TypeLookupMinInt(count, types.TailHashes.Length)
    return count
}

func DeclaredTypeNameCandidateCapacity(types: &DeclaredTypeNameCandidateTable): int {
    count := TypeLookupMinInt(types.Names.Length, types.ImportedNamespaceFlags.Length)
    count = TypeLookupMinInt(count, types.TailHashes.Length)
    return count
}

func DeclaredTypeExactNameCapacity(types: &DeclaredTypeExactNameTable): int {
    return TypeLookupMinInt(types.Names.Length, types.TailHashes.Length)
}

func TypeCreationOrderInputCapacity(order: &TypeCreationOrderTable): int {
    count := TypeLookupMinInt(order.Keys.Length, order.DotCounts.Length)
    count = TypeLookupMinInt(count, order.ResultIndices.Length)
    return count
}

func DeclaredTypeUniqueSuffixValueRank(
    keys: string[],
    valueRanks: int[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int): int {
    types := new DeclaredTypeValueRankTable { Keys: keys, ValueRanks: valueRanks, TailHashes: tailHashes }
    return DeclaredTypeUniqueSuffixValueRankCore(ref types, typeName, queryTailHash, count)
}

func DeclaredTypeUniqueSuffixValueRankCore(
    types: &DeclaredTypeValueRankTable,
    typeName: string,
    queryTailHash: int,
    count: int): int {
    if count < 0 || count > DeclaredTypeValueRankCapacity(ref types) {
        return -2
    }

    resultRank := 0
    useTailHash := typeName.Length > 0
    i := 0
    while i < count {
        rank := types.ValueRanks[i]
        if rank > 0
            && (!useTailHash || types.TailHashes[i] == queryTailHash)
            && DeclaredTypeKeyMatches(types.Keys[i], typeName) {
            if resultRank == 0 {
                resultRank = rank
            } else if resultRank != rank {
                return -1
            }
        }

        i = i + 1
    }

    return resultRank
}

func DeclaredTypeNameCandidateIndex(
    names: string[],
    importedNamespaceFlags: int[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int): int {
    types := new DeclaredTypeNameCandidateTable { Names: names, ImportedNamespaceFlags: importedNamespaceFlags, TailHashes: tailHashes }
    return DeclaredTypeNameCandidateIndexCore(ref types, typeName, queryTailHash, count)
}

func DeclaredTypeNameCandidateIndexCore(
    types: &DeclaredTypeNameCandidateTable,
    typeName: string,
    queryTailHash: int,
    count: int): int {
    if count < 0 || count > DeclaredTypeNameCandidateCapacity(ref types) {
        return -2
    }

    matchIndex := -1
    matchCount := 0
    importedIndex := -1
    importedCount := 0
    useTailHash := typeName.Length > 0

    i := 0
    while i < count {
        if (!useTailHash || types.TailHashes[i] == queryTailHash)
            && DeclaredTypeKeyMatches(types.Names[i], typeName) {
            matchCount = matchCount + 1
            if matchCount == 1 {
                matchIndex = i
            }

            if types.ImportedNamespaceFlags[i] != 0 {
                importedCount = importedCount + 1
                if importedCount == 1 {
                    importedIndex = i
                } else {
                    return 0
                }
            }
        }

        i = i + 1
    }

    if importedCount == 1 {
        return importedIndex + 1
    }

    if matchCount == 1 {
        return matchIndex + 1
    }

    return 0
}

func TypeCreationOrderIndicesInto(
    keys: string[],
    count: int,
    dotCounts: int[],
    depthCounts: int[],
    depthOffsets: int[],
    resultIndices: int[]): int {
    order := new TypeCreationOrderTable { Keys: keys, DotCounts: dotCounts, DepthCounts: depthCounts, DepthOffsets: depthOffsets, ResultIndices: resultIndices }
    return TypeCreationOrderIndicesCore(ref order, count)
}

func TypeCreationOrderIndicesCore(order: &TypeCreationOrderTable, count: int): int {
    if count < 0 || count > TypeCreationOrderInputCapacity(ref order) {
        return -1
    }

    maxDepth := 0
    i := 0
    while i < count {
        key := order.Keys[i]
        depth := 0
        j := 0
        while j < key.Length {
            if key[j] == '.' {
                depth = depth + 1
            }

            j = j + 1
        }

        order.DotCounts[i] = depth
        if depth > maxDepth {
            maxDepth = depth
        }

        i = i + 1
    }

    bucketCount := maxDepth + 1
    if bucketCount > order.DepthCounts.Length || bucketCount > order.DepthOffsets.Length {
        return -1
    }

    depth := 0
    while depth < bucketCount {
        order.DepthCounts[depth] = 0
        order.DepthOffsets[depth] = 0
        depth = depth + 1
    }

    i = 0
    while i < count {
        order.DepthCounts[order.DotCounts[i]] = order.DepthCounts[order.DotCounts[i]] + 1
        i = i + 1
    }

    offset := 0
    depth = maxDepth
    while depth >= 0 {
        order.DepthOffsets[depth] = offset
        offset = offset + order.DepthCounts[depth]
        depth = depth - 1
    }

    i = 0
    while i < count {
        depth = order.DotCounts[i]
        writeIndex := order.DepthOffsets[depth]
        order.ResultIndices[writeIndex] = i
        order.DepthOffsets[depth] = writeIndex + 1
        i = i + 1
    }

    return count
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

func TypeLookupMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

func DeclaredTypeKeyMatches(key: string, typeName: string): bool {
    if key == typeName {
        return true
    }

    keyLength := key.Length
    typeLength := typeName.Length
    if keyLength <= typeLength {
        return false
    }

    separatorIndex := keyLength - typeLength - 1
    if key[separatorIndex] != '.' {
        return false
    }

    suffixStart := separatorIndex + 1
    i := typeLength - 1
    while i >= 0 {
        if key[suffixStart + i] != typeName[i] {
            return false
        }

        i = i - 1
    }

    return true
}

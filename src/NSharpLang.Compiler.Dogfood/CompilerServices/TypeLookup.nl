func DeclaredTypeUniqueSuffixValueRank(
    keys: string[],
    valueRanks: int[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int): int {
    if count < 0 || count > keys.Length || count > valueRanks.Length || count > tailHashes.Length {
        return -2
    }

    resultRank := 0
    useTailHash := typeName.Length > 0
    i := 0
    while i < count {
        rank := valueRanks[i]
        if rank > 0
            && (!useTailHash || tailHashes[i] == queryTailHash)
            && DeclaredTypeKeyMatches(keys[i], typeName) {
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

func DeclaredTypeNameCandidateIndex(
    names: string[],
    importedNamespaceFlags: int[],
    tailHashes: int[],
    typeName: string,
    queryTailHash: int,
    count: int): int {
    if count < 0 || count > names.Length || count > importedNamespaceFlags.Length || count > tailHashes.Length {
        return -2
    }

    matchIndex := -1
    matchCount := 0
    importedIndex := -1
    importedCount := 0
    useTailHash := typeName.Length > 0

    i := 0
    while i < count {
        if (!useTailHash || tailHashes[i] == queryTailHash)
            && DeclaredTypeKeyMatches(names[i], typeName) {
            matchCount = matchCount + 1
            if matchCount == 1 {
                matchIndex = i
            }

            if importedNamespaceFlags[i] != 0 {
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

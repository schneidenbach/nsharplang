struct DocQueryTypeCandidateTable {
    Scores: int[]
    NamespaceLengths: int[]
    FullNames: string[]
    Count: int
}

struct DocQueryMemberRankTable {
    KindRanks: int[]
    NameRanks: int[]
}

struct DocQueryBucketTable {
    Counts: int[]
    Offsets: int[]
}

struct DocQueryIndexTable {
    Indices: int[]
}

func DocQueryBestTypeIndex(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
    candidates := new DocQueryTypeCandidateTable { Scores: scores, NamespaceLengths: namespaceLengths, FullNames: fullNames, Count: count }
    return DocQueryBestTypeIndexCore(ref candidates)
}

func DocQueryBestTypeIndexCore(candidates: &DocQueryTypeCandidateTable): int {
    if candidates.Count <= 0 {
        return -1
    }

    if candidates.Scores.Length < candidates.Count || candidates.NamespaceLengths.Length < candidates.Count || candidates.FullNames.Length < candidates.Count {
        return -1
    }

    bestIndex := 0
    bestScore := candidates.Scores[0]
    bestNamespaceLength := candidates.NamespaceLengths[0]
    i := 1
    unrolledLimit := candidates.Count - 8

    while i <= unrolledLimit {
        score := candidates.Scores[i]
        if score > bestScore {
            bestIndex = i
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[i]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[i]
            if namespaceLength < bestNamespaceLength {
                bestIndex = i
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[i], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = i
                }
            }
        }

        candidateIndex := i + 1
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 2
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 3
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 4
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 5
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 6
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 7
        score = candidates.Scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[candidateIndex], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        i = i + 8
    }

    while i < candidates.Count {
        score := candidates.Scores[i]
        if score > bestScore {
            bestIndex = i
            bestScore = score
            bestNamespaceLength = candidates.NamespaceLengths[i]
        } else if score == bestScore {
            namespaceLength := candidates.NamespaceLengths[i]
            if namespaceLength < bestNamespaceLength {
                bestIndex = i
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(candidates.FullNames[i], candidates.FullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = i
                }
            }
        }

        i = i + 1
    }

    return bestIndex
}

func DocQueryMemberOrderIndicesInto(
    kindRanks: int[],
    nameRanks: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    ranks := new DocQueryMemberRankTable { KindRanks: kindRanks, NameRanks: nameRanks }
    nameBuckets := new DocQueryBucketTable { Counts: nameCounts, Offsets: nameOffsets }
    kindBuckets := new DocQueryBucketTable { Counts: kindCounts, Offsets: kindOffsets }
    temp := new DocQueryIndexTable { Indices: tempIndices }
    result := new DocQueryIndexTable { Indices: resultIndices }
    return DocQueryMemberOrderIndicesCore(ref ranks, ref nameBuckets, ref kindBuckets, ref temp, ref result)
}

func DocQueryMemberOrderIndicesCore(
    ranks: &DocQueryMemberRankTable,
    nameBuckets: &DocQueryBucketTable,
    kindBuckets: &DocQueryBucketTable,
    temp: &DocQueryIndexTable,
    result: &DocQueryIndexTable): int {
    count := DocQueryMinInt(ranks.KindRanks.Length, ranks.NameRanks.Length)
    nameBucketCount := DocQueryMinInt(nameBuckets.Counts.Length, nameBuckets.Offsets.Length)
    kindBucketCount := DocQueryMinInt(kindBuckets.Counts.Length, kindBuckets.Offsets.Length)

    if temp.Indices.Length < count || result.Indices.Length < count {
        return -1
    }

    i := 0
    while i < nameBucketCount {
        nameBuckets.Counts[i] = 0
        nameBuckets.Offsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < kindBucketCount {
        kindBuckets.Counts[i] = 0
        kindBuckets.Offsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        nameRank := ranks.NameRanks[i]
        kindRank := ranks.KindRanks[i]
        if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
            return -1
        }

        nameBuckets.Counts[nameRank] = nameBuckets.Counts[nameRank] + 1
        kindBuckets.Counts[kindRank] = kindBuckets.Counts[kindRank] + 1
        i = i + 1
    }

    offset := 0
    rank := 0
    while rank < nameBucketCount {
        nameBuckets.Offsets[rank] = offset
        offset = offset + nameBuckets.Counts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        nameRank := ranks.NameRanks[i]
        writeIndex := nameBuckets.Offsets[nameRank]
        temp.Indices[writeIndex] = i
        nameBuckets.Offsets[nameRank] = writeIndex + 1
        i = i + 1
    }

    offset = 0
    rank = 0
    while rank < kindBucketCount {
        kindBuckets.Offsets[rank] = offset
        offset = offset + kindBuckets.Counts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        sourceIndex := temp.Indices[i]
        kindRank := ranks.KindRanks[sourceIndex]
        writeIndex := kindBuckets.Offsets[kindRank]
        result.Indices[writeIndex] = sourceIndex
        kindBuckets.Offsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    return count
}

func DocQueryCompareOrdinalIgnoreCase(left: string, right: string): int {
    length := DocQueryMinInt(left.Length, right.Length)
    i := 0

    while i < length {
        leftChar := Char.ToLowerInvariant(left[i])
        rightChar := Char.ToLowerInvariant(right[i])

        if leftChar < rightChar {
            return -1
        }

        if leftChar > rightChar {
            return 1
        }

        i = i + 1
    }

    if left.Length < right.Length {
        return -1
    }

    if left.Length > right.Length {
        return 1
    }

    return 0
}

func DocQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

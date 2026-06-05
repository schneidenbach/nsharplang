func DocQueryBestTypeIndex(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
    if count <= 0 {
        return -1
    }

    if scores.Length < count || namespaceLengths.Length < count || fullNames.Length < count {
        return -1
    }

    bestIndex := 0
    bestScore := scores[0]
    bestNamespaceLength := namespaceLengths[0]
    i := 1
    unrolledLimit := count - 8

    while i <= unrolledLimit {
        score := scores[i]
        if score > bestScore {
            bestIndex = i
            bestScore = score
            bestNamespaceLength = namespaceLengths[i]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[i]
            if namespaceLength < bestNamespaceLength {
                bestIndex = i
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[i], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = i
                }
            }
        }

        candidateIndex := i + 1
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 2
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 3
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 4
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 5
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 6
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        candidateIndex = i + 7
        score = scores[candidateIndex]
        if score > bestScore {
            bestIndex = candidateIndex
            bestScore = score
            bestNamespaceLength = namespaceLengths[candidateIndex]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[candidateIndex]
            if namespaceLength < bestNamespaceLength {
                bestIndex = candidateIndex
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[candidateIndex], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = candidateIndex
                }
            }
        }

        i = i + 8
    }

    while i < count {
        score := scores[i]
        if score > bestScore {
            bestIndex = i
            bestScore = score
            bestNamespaceLength = namespaceLengths[i]
        } else if score == bestScore {
            namespaceLength := namespaceLengths[i]
            if namespaceLength < bestNamespaceLength {
                bestIndex = i
                bestNamespaceLength = namespaceLength
            } else if namespaceLength == bestNamespaceLength {
                comparison := DocQueryCompareOrdinalIgnoreCase(fullNames[i], fullNames[bestIndex])
                if comparison < 0 {
                    bestIndex = i
                }
            }
        }

        i = i + 1
    }

    return bestIndex
}

func DocQueryBestTypeChecksumInto(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
    bestIndex := DocQueryBestTypeIndex(scores, namespaceLengths, fullNames, count)
    if bestIndex < 0 {
        return bestIndex
    }

    return (bestIndex + 1) * 97 + scores[bestIndex] * 31 + namespaceLengths[bestIndex] * 17
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
    count := DocQueryMinInt(kindRanks.Length, nameRanks.Length)
    nameBucketCount := DocQueryMinInt(nameCounts.Length, nameOffsets.Length)
    kindBucketCount := DocQueryMinInt(kindCounts.Length, kindOffsets.Length)

    if tempIndices.Length < count || resultIndices.Length < count {
        return -1
    }

    i := 0
    while i < nameBucketCount {
        nameCounts[i] = 0
        nameOffsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < kindBucketCount {
        kindCounts[i] = 0
        kindOffsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        nameRank := nameRanks[i]
        kindRank := kindRanks[i]
        if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
            return -1
        }

        nameCounts[nameRank] = nameCounts[nameRank] + 1
        kindCounts[kindRank] = kindCounts[kindRank] + 1
        i = i + 1
    }

    offset := 0
    rank := 0
    while rank < nameBucketCount {
        nameOffsets[rank] = offset
        offset = offset + nameCounts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        nameRank := nameRanks[i]
        writeIndex := nameOffsets[nameRank]
        tempIndices[writeIndex] = i
        nameOffsets[nameRank] = writeIndex + 1
        i = i + 1
    }

    offset = 0
    rank = 0
    while rank < kindBucketCount {
        kindOffsets[rank] = offset
        offset = offset + kindCounts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        sourceIndex := tempIndices[i]
        kindRank := kindRanks[sourceIndex]
        writeIndex := kindOffsets[kindRank]
        resultIndices[writeIndex] = sourceIndex
        kindOffsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    return count
}

func DocQueryMemberOrderChecksumInto(
    kindRanks: int[],
    nameRanks: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    orderedCount := DocQueryMemberOrderIndicesInto(
        kindRanks,
        nameRanks,
        nameCounts,
        nameOffsets,
        kindCounts,
        kindOffsets,
        tempIndices,
        resultIndices)
    checksum := orderedCount

    i := 0
    while i < orderedCount {
        index := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + kindRanks[index] * 17 + nameRanks[index] * 13
        i = i + 1
    }

    return checksum
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

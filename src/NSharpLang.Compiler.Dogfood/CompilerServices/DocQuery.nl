import System
import System.Text

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

func DocQueryStripGenericArity(name: string): string {
    if name.IndexOf('`') < 0 {
        return name
    }

    builder := new StringBuilder(name.Length)
    i := 0
    while i < name.Length {
        if name[i] == '`' {
            i = i + 1
            while i < name.Length && DocQueryIsDigit(name[i]) {
                i = i + 1
            }

            continue
        }

        builder.Append(name[i])
        i = i + 1
    }

    return builder.ToString()
}

func DocQueryTypeMatchScore(
    strippedQuery: string,
    qualifiedName: string,
    simpleName: string,
    namespaceName: string,
    isNested: int): int {
    score := 0

    if DocQueryEqualsIgnoreCase(qualifiedName, strippedQuery) {
        score = score + 1000
    }

    if DocQueryEndsWithSegmentIgnoreCase(qualifiedName, strippedQuery) {
        score = score + 400
    }

    lastSegmentStart := DocQueryLastSegmentStart(strippedQuery)
    if DocQueryEqualsSubstringIgnoreCase(simpleName, 0, simpleName.Length, strippedQuery, lastSegmentStart, strippedQuery.Length - lastSegmentStart) {
        score = score + 250
    }

    queryNamespaceLength := DocQueryQueryNamespaceLength(strippedQuery)
    if queryNamespaceLength > 0 && DocQueryEndsWithSubstringIgnoreCase(namespaceName, strippedQuery, 0, queryNamespaceLength) {
        score = score + 300
    }

    score = score + DocQueryNamespacePriority(namespaceName)

    if isNested == 0 {
        score = score + 10
    }

    return score
}

func DocQueryNamespacePriority(ns: string): int {
    if ns.Length == 0 {
        return 0
    }

    if DocQueryEqualsIgnoreCase(ns, "System") {
        return 200
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Collections") {
        return 199
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Collections.Generic") {
        return 198
    }

    if DocQueryEqualsIgnoreCase(ns, "System.IO") {
        return 197
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Linq") {
        return 196
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Net") {
        return 195
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Net.Http") {
        return 194
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Text") {
        return 193
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Text.Json") {
        return 192
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Text.RegularExpressions") {
        return 191
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Threading") {
        return 190
    }

    if DocQueryEqualsIgnoreCase(ns, "System.Threading.Tasks") {
        return 189
    }

    if DocQueryStartsWithIgnoreCase(ns, "System.") {
        return 120
    }

    if DocQueryEqualsIgnoreCase(ns, "Microsoft") || DocQueryStartsWithIgnoreCase(ns, "Microsoft.") {
        return 60
    }

    return 10
}

func DocQueryLastSegmentStart(text: string): int {
    i := text.Length - 1
    while i >= 0 {
        if text[i] == '.' {
            return i + 1
        }

        i = i - 1
    }

    return 0
}

func DocQueryQueryNamespaceLength(text: string): int {
    i := text.Length - 1
    while i >= 0 {
        if text[i] == '.' {
            return i
        }

        i = i - 1
    }

    return 0
}

func DocQueryEqualsIgnoreCase(left: string, right: string): bool {
    return left.Length == right.Length && String.Compare(left, right, StringComparison.OrdinalIgnoreCase) == 0
}

func DocQueryStartsWithIgnoreCase(text: string, prefix: string): bool {
    if prefix.Length > text.Length {
        return false
    }

    return String.Compare(text, 0, prefix, 0, prefix.Length, StringComparison.OrdinalIgnoreCase) == 0
}

func DocQueryEndsWithSegmentIgnoreCase(text: string, suffix: string): bool {
    if suffix.Length >= text.Length {
        return false
    }

    start := text.Length - suffix.Length
    if text[start - 1] != '.' {
        return false
    }

    return String.Compare(text, start, suffix, 0, suffix.Length, StringComparison.OrdinalIgnoreCase) == 0
}

func DocQueryEndsWithSubstringIgnoreCase(text: string, query: string, queryStart: int, queryLength: int): bool {
    if queryLength <= 0 || queryLength > text.Length {
        return false
    }

    textStart := text.Length - queryLength
    return String.Compare(text, textStart, query, queryStart, queryLength, StringComparison.OrdinalIgnoreCase) == 0
}

func DocQueryEqualsSubstringIgnoreCase(left: string, leftStart: int, leftLength: int, right: string, rightStart: int, rightLength: int): bool {
    if leftLength != rightLength {
        return false
    }

    return String.Compare(left, leftStart, right, rightStart, leftLength, StringComparison.OrdinalIgnoreCase) == 0
}

func DocQueryIsDigit(ch: char): bool {
    return ch >= '0' && ch <= '9'
}

func DocQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

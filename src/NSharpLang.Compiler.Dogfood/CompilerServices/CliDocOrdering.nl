import System

struct CliDocSymbolOrderRankTable {
    KindRanks: int[]
    NameRanks: int[]
    IncludeFlags: int[]
}

struct CliDocOrderBucketTable {
    Counts: int[]
    Offsets: int[]
}

struct CliDocOrderIndexTable {
    Indices: int[]
}

struct CliDocSlugTable {
    RawSlugs: string[]
    ResultSlugs: string[]
}

struct CliDocSlugBufferTable {
    Chars: char[]
}

struct CliDocSymbolKindFilterTable {
    KindIds: int[]
    TargetKindId: int
}

func CliDocSymbolOrderCountingIndicesInto(
    kindRanks: int[],
    nameRanks: int[],
    includeFlags: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    ranks := new CliDocSymbolOrderRankTable { KindRanks: kindRanks, NameRanks: nameRanks, IncludeFlags: includeFlags }
    nameBuckets := new CliDocOrderBucketTable { Counts: nameCounts, Offsets: nameOffsets }
    kindBuckets := new CliDocOrderBucketTable { Counts: kindCounts, Offsets: kindOffsets }
    temp := new CliDocOrderIndexTable { Indices: tempIndices }
    result := new CliDocOrderIndexTable { Indices: resultIndices }
    return CliDocSymbolOrderCountingIndicesCore(ref ranks, ref nameBuckets, ref kindBuckets, ref temp, ref result)
}

func CliDocSymbolOrderCountingIndicesCore(
    ranks: &CliDocSymbolOrderRankTable,
    nameBuckets: &CliDocOrderBucketTable,
    kindBuckets: &CliDocOrderBucketTable,
    temp: &CliDocOrderIndexTable,
    result: &CliDocOrderIndexTable): int {
    count := CliDocOrderingMinInt(ranks.KindRanks.Length, ranks.NameRanks.Length)
    count = CliDocOrderingMinInt(count, ranks.IncludeFlags.Length)
    nameBucketCount := CliDocOrderingMinInt(nameBuckets.Counts.Length, nameBuckets.Offsets.Length)
    kindBucketCount := CliDocOrderingMinInt(kindBuckets.Counts.Length, kindBuckets.Offsets.Length)

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

    includedCount := 0
    i = 0
    while i < count {
        kindId := ranks.KindRanks[i]
        if ranks.IncludeFlags[i] != 0 || CliDocSymbolKindIsDocumented(kindId) {
            nameRank := ranks.NameRanks[i]
            kindRank := CliDocSymbolKindOrderRank(kindId)
            if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
                return -1
            }

            if includedCount >= temp.Indices.Length || includedCount >= result.Indices.Length {
                return -1
            }

            nameBuckets.Counts[nameRank] = nameBuckets.Counts[nameRank] + 1
            kindBuckets.Counts[kindRank] = kindBuckets.Counts[kindRank] + 1
            includedCount = includedCount + 1
        }

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
        kindId := ranks.KindRanks[i]
        if ranks.IncludeFlags[i] != 0 || CliDocSymbolKindIsDocumented(kindId) {
            nameRank := ranks.NameRanks[i]
            writeIndex := nameBuckets.Offsets[nameRank]
            temp.Indices[writeIndex] = i
            nameBuckets.Offsets[nameRank] = writeIndex + 1
        }

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
    while i < includedCount {
        sourceIndex := temp.Indices[i]
        kindRank := CliDocSymbolKindOrderRank(ranks.KindRanks[sourceIndex])
        writeIndex := kindBuckets.Offsets[kindRank]
        result.Indices[writeIndex] = sourceIndex
        kindBuckets.Offsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    return includedCount
}

func CliDocSymbolKindIsDocumented(kindId: int): bool {
    if kindId == 10 || kindId == 11 {
        return false
    }

    return true
}

func CliDocSymbolKindOrderRank(kindId: int): int {
    if kindId == 1 {
        return 1
    }

    if kindId == 12 {
        return 2
    }

    if kindId == 5 {
        return 3
    }

    if kindId == 13 {
        return 4
    }

    if kindId == 8 {
        return 5
    }

    if kindId == 0 {
        return 6
    }

    if kindId == 4 {
        return 7
    }

    if kindId == 9 {
        return 8
    }

    if kindId == 11 {
        return 9
    }

    if kindId == 7 {
        return 10
    }

    if kindId == 3 {
        return 11
    }

    if kindId == 2 {
        return 12
    }

    if kindId == 15 {
        return 13
    }

    if kindId == 14 {
        return 14
    }

    if kindId == 6 {
        return 15
    }

    if kindId == 10 {
        return 16
    }

    return 0
}

func CliDocSlugsInto(rawSlugs: string[], resultSlugs: string[]): int {
    slugs := new CliDocSlugTable { RawSlugs: rawSlugs, ResultSlugs: resultSlugs }
    return CliDocSlugsCore(ref slugs)
}

func CliDocSlugsCore(slugs: &CliDocSlugTable): int {
    count := CliDocOrderingMinInt(slugs.RawSlugs.Length, slugs.ResultSlugs.Length)
    bufferLength := 0
    if count > 0 {
        bufferLength = 128
    }

    buffer := new char[](bufferLength)
    slugBuffer := new CliDocSlugBufferTable { Chars: buffer }
    i := 0
    while i < count {
        raw := slugs.RawSlugs[i]
        length := raw.Length
        if length > bufferLength {
            bufferLength = length
            buffer = new char[](length)
            slugBuffer.Chars = buffer
        }

        slugs.ResultSlugs[i] = CliDocSlugCore(raw, length, ref slugBuffer)
        i = i + 1
    }

    return count
}

func CliDocSlugCore(raw: string, length: int, buffer: &CliDocSlugBufferTable): string {
    i := 0
    slugLength := 0
    while i < length {
        ch := raw[i]
        code := (int)ch
        if code >= 65 && code <= 90 {
            buffer.Chars[slugLength] = (char)(code + 32)
            slugLength = slugLength + 1
        } else if (code >= 97 && code <= 122) || (code >= 48 && code <= 57) {
            buffer.Chars[slugLength] = ch
            slugLength = slugLength + 1
        } else if code > 127 && Char.IsLetterOrDigit(ch) {
            buffer.Chars[slugLength] = Char.ToLowerInvariant(ch)
            slugLength = slugLength + 1
        }

        i = i + 1
    }

    return new string(buffer.Chars, 0, slugLength)
}

func SymbolKindFilterIndicesInto(kindIds: int[], targetKindId: int, resultIndices: int[]): int {
    symbols := new CliDocSymbolKindFilterTable { KindIds: kindIds, TargetKindId: targetKindId }
    result := new CliDocOrderIndexTable { Indices: resultIndices }
    return SymbolKindFilterIndicesCore(ref symbols, ref result)
}

func SymbolKindFilterIndicesCore(symbols: &CliDocSymbolKindFilterTable, result: &CliDocOrderIndexTable): int {
    count := 0
    length := symbols.KindIds.Length
    i := 0

    if result.Indices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if symbols.KindIds[i] == symbols.TargetKindId {
                result.Indices[count] = i
                count = count + 1
            }

            next := i + 1
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 2
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 3
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 4
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 5
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 6
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 7
            if symbols.KindIds[next] == symbols.TargetKindId {
                result.Indices[count] = next
                count = count + 1
            }

            i = i + 8
        }

        while i < length {
            if symbols.KindIds[i] == symbols.TargetKindId {
                result.Indices[count] = i
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    while i < length {
        if symbols.KindIds[i] == symbols.TargetKindId {
            if count >= result.Indices.Length {
                return -1
            }

            result.Indices[count] = i
            count = count + 1
        }

        i = i + 1
    }

    return count
}

func CliDocOrderingMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

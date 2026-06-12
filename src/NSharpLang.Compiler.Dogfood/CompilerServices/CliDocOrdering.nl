import System

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
    count := CliDocOrderingMinInt(kindRanks.Length, nameRanks.Length)
    count = CliDocOrderingMinInt(count, includeFlags.Length)
    nameBucketCount := CliDocOrderingMinInt(nameCounts.Length, nameOffsets.Length)
    kindBucketCount := CliDocOrderingMinInt(kindCounts.Length, kindOffsets.Length)

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

    includedCount := 0
    i = 0
    while i < count {
        if includeFlags[i] != 0 {
            nameRank := nameRanks[i]
            kindRank := kindRanks[i]
            if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
                return -1
            }

            if includedCount >= tempIndices.Length || includedCount >= resultIndices.Length {
                return -1
            }

            nameCounts[nameRank] = nameCounts[nameRank] + 1
            kindCounts[kindRank] = kindCounts[kindRank] + 1
            includedCount = includedCount + 1
        }

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
        if includeFlags[i] != 0 {
            nameRank := nameRanks[i]
            writeIndex := nameOffsets[nameRank]
            tempIndices[writeIndex] = i
            nameOffsets[nameRank] = writeIndex + 1
        }

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
    while i < includedCount {
        sourceIndex := tempIndices[i]
        kindRank := kindRanks[sourceIndex]
        writeIndex := kindOffsets[kindRank]
        resultIndices[writeIndex] = sourceIndex
        kindOffsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    return includedCount
}

func CliDocSlugsInto(rawSlugs: string[], resultSlugs: string[]): int {
    count := CliDocOrderingMinInt(rawSlugs.Length, resultSlugs.Length)
    bufferLength := 0
    if count > 0 {
        bufferLength = 128
    }

    buffer := new char[](bufferLength)
    i := 0
    while i < count {
        raw := rawSlugs[i]
        length := raw.Length
        if length > bufferLength {
            bufferLength = length
            buffer = new char[](length)
        }

        resultSlugs[i] = CliDocSlugInto(raw, length, buffer)
        i = i + 1
    }

    return count
}

func CliDocSlugInto(raw: string, length: int, buffer: char[]): string {
    i := 0
    slugLength := 0
    while i < length {
        ch := raw[i]
        code := (int)ch
        if code >= 65 && code <= 90 {
            buffer[slugLength] = (char)(code + 32)
            slugLength = slugLength + 1
        } else if (code >= 97 && code <= 122) || (code >= 48 && code <= 57) {
            buffer[slugLength] = ch
            slugLength = slugLength + 1
        } else if code > 127 && Char.IsLetterOrDigit(ch) {
            buffer[slugLength] = Char.ToLowerInvariant(ch)
            slugLength = slugLength + 1
        }

        i = i + 1
    }

    return new string(buffer, 0, slugLength)
}

func SymbolKindFilterIndicesInto(kindIds: int[], targetKindId: int, resultIndices: int[]): int {
    count := 0
    length := kindIds.Length
    i := 0

    if resultIndices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if kindIds[i] == targetKindId {
                resultIndices[count] = i
                count = count + 1
            }

            next := i + 1
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            next = i + 2
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            next = i + 3
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            next = i + 4
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            next = i + 5
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            next = i + 6
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            next = i + 7
            if kindIds[next] == targetKindId {
                resultIndices[count] = next
                count = count + 1
            }

            i = i + 8
        }

        while i < length {
            if kindIds[i] == targetKindId {
                resultIndices[count] = i
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    while i < length {
        if kindIds[i] == targetKindId {
            if count >= resultIndices.Length {
                return -1
            }

            resultIndices[count] = i
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

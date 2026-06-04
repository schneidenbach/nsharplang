func DiagnosticDeduplicateCompactInto(
    codeIds: int[],
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    count := DiagnosticDeduplicationMinInt(codeIds.Length, fileRanks.Length)
    count = DiagnosticDeduplicationMinInt(count, lineNumbers.Length)
    count = DiagnosticDeduplicationMinInt(count, columns.Length)
    count = DiagnosticDeduplicationMinInt(count, messageIds.Length)

    maxResults := resultIndices.Length
    capacity := slotIndices.Length
    if count == 0 || maxResults == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        slotIndices[i] = -1
        i = i + 1
    }

    uniqueCount := 0
    index := 0
    while index < count {
        hash := HashDiagnosticDeduplicationKey(
            codeIds[index],
            fileRanks[index],
            lineNumbers[index],
            columns[index],
            messageIds[index])
        slot := DiagnosticDeduplicationPositiveModulo(hash, capacity)
        probes := 0
        duplicate := false

        while probes < capacity {
            candidateIndex := slotIndices[slot]
            if candidateIndex < 0 {
                break
            }

            if DiagnosticDeduplicationKeysEqual(
                index,
                candidateIndex,
                codeIds,
                fileRanks,
                lineNumbers,
                columns,
                messageIds) {
                duplicate = true
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        if !duplicate {
            if uniqueCount >= maxResults || probes >= capacity {
                SortDiagnosticDeduplicationIndices(resultIndices, uniqueCount, fileRanks, lineNumbers, columns)
                return uniqueCount
            }

            slotIndices[slot] = index
            resultIndices[uniqueCount] = index
            uniqueCount = uniqueCount + 1
        }

        index = index + 1
    }

    SortDiagnosticDeduplicationIndices(resultIndices, uniqueCount, fileRanks, lineNumbers, columns)
    return uniqueCount
}

func DiagnosticDeduplicateCompactChecksumInto(
    codeIds: int[],
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := DiagnosticDeduplicateCompactInto(
        codeIds,
        fileRanks,
        lineNumbers,
        columns,
        messageIds,
        slotIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + lineNumbers[index] * 17 + columns[index] * 13
        i = i + 1
    }

    return checksum
}

func DiagnosticDeduplicateStableInto(
    codeIds: int[],
    fileIds: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    count := DiagnosticDeduplicationMinInt(codeIds.Length, fileIds.Length)
    count = DiagnosticDeduplicationMinInt(count, lineNumbers.Length)
    count = DiagnosticDeduplicationMinInt(count, columns.Length)
    count = DiagnosticDeduplicationMinInt(count, messageIds.Length)

    maxResults := resultIndices.Length
    capacity := slotIndices.Length
    if count == 0 || maxResults == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        slotIndices[i] = -1
        i = i + 1
    }

    uniqueCount := 0
    index := 0
    while index < count {
        hash := HashDiagnosticDeduplicationKey(
            codeIds[index],
            fileIds[index],
            lineNumbers[index],
            columns[index],
            messageIds[index])
        slot := DiagnosticDeduplicationPositiveModulo(hash, capacity)
        probes := 0
        duplicate := false

        while probes < capacity {
            candidateIndex := slotIndices[slot]
            if candidateIndex < 0 {
                break
            }

            if DiagnosticDeduplicationKeysEqual(
                index,
                candidateIndex,
                codeIds,
                fileIds,
                lineNumbers,
                columns,
                messageIds) {
                duplicate = true
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        if !duplicate {
            if uniqueCount >= maxResults || probes >= capacity {
                return uniqueCount
            }

            slotIndices[slot] = index
            resultIndices[uniqueCount] = index
            uniqueCount = uniqueCount + 1
        }

        index = index + 1
    }

    return uniqueCount
}

func DiagnosticDeduplicateStableChecksumInto(
    codeIds: int[],
    fileIds: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := DiagnosticDeduplicateStableInto(
        codeIds,
        fileIds,
        lineNumbers,
        columns,
        messageIds,
        slotIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + lineNumbers[index] * 17 + columns[index] * 13
        i = i + 1
    }

    return checksum
}

func ReferenceDeduplicateCompactInto(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    count := DiagnosticDeduplicationMinInt(fileRanks.Length, lineNumbers.Length)
    count = DiagnosticDeduplicationMinInt(count, columns.Length)

    maxResults := resultIndices.Length
    capacity := slotIndices.Length
    if count == 0 || maxResults == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        slotIndices[i] = -1
        i = i + 1
    }

    uniqueCount := 0
    index := 0
    while index < count {
        hash := HashReferenceDeduplicationKey(
            fileRanks[index],
            lineNumbers[index],
            columns[index])
        slot := DiagnosticDeduplicationPositiveModulo(hash, capacity)
        probes := 0
        duplicate := false

        while probes < capacity {
            candidateIndex := slotIndices[slot]
            if candidateIndex < 0 {
                break
            }

            if ReferenceDeduplicationKeysEqual(
                index,
                candidateIndex,
                fileRanks,
                lineNumbers,
                columns) {
                duplicate = true
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        if !duplicate {
            if uniqueCount >= maxResults || probes >= capacity {
                SortDiagnosticDeduplicationIndices(resultIndices, uniqueCount, fileRanks, lineNumbers, columns)
                return uniqueCount
            }

            slotIndices[slot] = index
            resultIndices[uniqueCount] = index
            uniqueCount = uniqueCount + 1
        }

        index = index + 1
    }

    SortDiagnosticDeduplicationIndices(resultIndices, uniqueCount, fileRanks, lineNumbers, columns)
    return uniqueCount
}

func ReferenceDeduplicateCompactChecksumInto(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := ReferenceDeduplicateCompactInto(
        fileRanks,
        lineNumbers,
        columns,
        slotIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + lineNumbers[index] * 17 + columns[index] * 13
        i = i + 1
    }

    return checksum
}

func ReferenceFileSummaryRanksInto(
    fileRanks: int[],
    uniqueFileCount: int,
    countsByRank: int[],
    resultRanks: int[]): int {
    clearCount := uniqueFileCount + 1
    if clearCount > countsByRank.Length {
        clearCount = countsByRank.Length
    }

    i := 0
    while i < clearCount {
        countsByRank[i] = 0
        i = i + 1
    }

    i = 0
    while i < fileRanks.Length {
        rank := fileRanks[i]
        if rank > 0 && rank <= uniqueFileCount && rank < countsByRank.Length {
            countsByRank[rank] = countsByRank[rank] + 1
        }

        i = i + 1
    }

    resultCount := 0
    rank := 1
    while rank <= uniqueFileCount && rank < countsByRank.Length {
        if countsByRank[rank] > 0 {
            if resultCount < resultRanks.Length {
                resultRanks[resultCount] = rank
            }

            resultCount = resultCount + 1
        }

        rank = rank + 1
    }

    return resultCount
}

func ReferenceFileSummaryChecksumInto(
    fileRanks: int[],
    uniqueFileCount: int,
    countsByRank: int[],
    resultRanks: int[],
    fileLengthsByRank: int[]): int {
    resultCount := ReferenceFileSummaryRanksInto(
        fileRanks,
        uniqueFileCount,
        countsByRank,
        resultRanks)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultRanks.Length {
        rank := resultRanks[i]
        length := 0
        if rank >= 0 && rank < fileLengthsByRank.Length {
            length = fileLengthsByRank[rank]
        }

        checksum = checksum + rank * 31 + length * 17 + (i + 1) * 13
        i = i + 1
    }

    return checksum
}

func HashDiagnosticDeduplicationKey(
    codeId: int,
    fileId: int,
    line: int,
    column: int,
    messageId: int): int {
    hash := 17
    hash = hash * 31 + codeId
    hash = hash * 31 + fileId
    hash = hash * 31 + line
    hash = hash * 31 + column
    hash = hash * 31 + messageId
    return hash
}

func HashReferenceDeduplicationKey(
    fileId: int,
    line: int,
    column: int): int {
    hash := 17
    hash = hash * 31 + fileId
    hash = hash * 31 + line
    hash = hash * 31 + column
    return hash
}

func DiagnosticDeduplicationKeysEqual(
    left: int,
    right: int,
    codeIds: int[],
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[]): bool {
    return codeIds[left] == codeIds[right]
        && fileRanks[left] == fileRanks[right]
        && lineNumbers[left] == lineNumbers[right]
        && columns[left] == columns[right]
        && messageIds[left] == messageIds[right]
}

func ReferenceDeduplicationKeysEqual(
    left: int,
    right: int,
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[]): bool {
    return fileRanks[left] == fileRanks[right]
        && lineNumbers[left] == lineNumbers[right]
        && columns[left] == columns[right]
}

func SortDiagnosticDeduplicationIndices(
    resultIndices: int[],
    count: int,
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[]): void {
    if count < 2 {
        return
    }

    start := count / 2 - 1
    while start >= 0 {
        SiftDownDiagnosticDeduplicationIndices(resultIndices, start, count - 1, fileRanks, lineNumbers, columns)
        start = start - 1
    }

    end := count - 1
    while end > 0 {
        temp := resultIndices[end]
        resultIndices[end] = resultIndices[0]
        resultIndices[0] = temp

        end = end - 1
        SiftDownDiagnosticDeduplicationIndices(resultIndices, 0, end, fileRanks, lineNumbers, columns)
    }
}

func SiftDownDiagnosticDeduplicationIndices(
    resultIndices: int[],
    start: int,
    end: int,
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[]): void {
    root := start

    while root * 2 + 1 <= end {
        child := root * 2 + 1
        swapIndex := root

        if IsDiagnosticDeduplicationIndexBefore(resultIndices[swapIndex], resultIndices[child], fileRanks, lineNumbers, columns) {
            swapIndex = child
        }

        if child + 1 <= end && IsDiagnosticDeduplicationIndexBefore(resultIndices[swapIndex], resultIndices[child + 1], fileRanks, lineNumbers, columns) {
            swapIndex = child + 1
        }

        if swapIndex == root {
            return
        }

        temp := resultIndices[root]
        resultIndices[root] = resultIndices[swapIndex]
        resultIndices[swapIndex] = temp
        root = swapIndex
    }
}

func IsDiagnosticDeduplicationIndexBefore(
    left: int,
    right: int,
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[]): bool {
    if fileRanks[left] != fileRanks[right] {
        return fileRanks[left] < fileRanks[right]
    }

    if lineNumbers[left] != lineNumbers[right] {
        return lineNumbers[left] < lineNumbers[right]
    }

    if columns[left] != columns[right] {
        return columns[left] < columns[right]
    }

    return left < right
}

func DiagnosticDeduplicationPositiveModulo(value: int, divisor: int): int {
    result := value % divisor
    if result < 0 {
        return result + divisor
    }

    return result
}

func DiagnosticDeduplicationMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

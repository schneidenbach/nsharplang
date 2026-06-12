// Mirrors Formatter.Format import/using ordering: "System* first, then namespace
// alphabetical". The production C# shape is
//   ast.Imports
//     .OrderByDescending(i => i.Namespace.StartsWith("System"))
//     .ThenBy(i => i.Namespace)
//     .ToList()
// LINQ OrderBy/OrderByDescending are stable, so identical namespaces keep their
// input order. The host compacts each import to a dense ordinal namespace rank
// (1-based) plus a System-prefix flag (1/0); the kernel performs a two-pass
// stable counting sort and writes the resulting permutation into a caller-owned
// int[] — no public string materialization across the boundary.

func FormatterImportOrderIndicesInto(
    systemFlags: int[],
    nameRanks: int[],
    nameRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    count := FormatterImportOrderMinInt(systemFlags.Length, nameRanks.Length)

    if count > tempIndices.Length || count > resultIndices.Length {
        return -1
    }

    i := 0
    while i < count {
        tempIndices[i] = i
        i = i + 1
    }

    // Pass 1: stable ascending sort by namespace rank (the ThenBy key).
    namePass := FormatterImportOrderNamePass(
        tempIndices,
        resultIndices,
        count,
        nameRanks,
        nameRankCount,
        bucketCounts,
        bucketOffsets)
    if namePass < 0 {
        return -1
    }

    // Pass 2: stable sort placing System* (flag 1) before non-System (flag 0),
    // preserving the ascending-name order established above.
    systemPass := FormatterImportOrderSystemPass(
        resultIndices,
        tempIndices,
        count,
        systemFlags,
        bucketCounts,
        bucketOffsets)
    if systemPass < 0 {
        return -1
    }

    i = 0
    while i < count {
        resultIndices[i] = tempIndices[i]
        i = i + 1
    }

    return count
}

func FormatterImportOrderNamePass(
    sourceIndices: int[],
    targetIndices: int[],
    count: int,
    nameRanks: int[],
    nameRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[]): int {
    bucketCapacity := FormatterImportOrderMinInt(bucketCounts.Length, bucketOffsets.Length)
    if nameRankCount <= 0 || nameRankCount + 1 > bucketCapacity || count > sourceIndices.Length || count > targetIndices.Length {
        return -1
    }

    i := 0
    while i <= nameRankCount {
        bucketCounts[i] = 0
        bucketOffsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        sourceIndex := sourceIndices[i]
        if sourceIndex < 0 || sourceIndex >= nameRanks.Length {
            return -1
        }

        rank := nameRanks[sourceIndex]
        if rank <= 0 || rank > nameRankCount {
            return -1
        }

        bucketCounts[rank] = bucketCounts[rank] + 1
        i = i + 1
    }

    offset := 0
    bucketIndex := 0
    while bucketIndex <= nameRankCount {
        bucketOffsets[bucketIndex] = offset
        offset = offset + bucketCounts[bucketIndex]
        bucketIndex = bucketIndex + 1
    }

    i = 0
    while i < count {
        sourceIndex := sourceIndices[i]
        rank := nameRanks[sourceIndex]
        writeIndex := bucketOffsets[rank]
        targetIndices[writeIndex] = sourceIndex
        bucketOffsets[rank] = writeIndex + 1
        i = i + 1
    }

    return count
}

func FormatterImportOrderSystemPass(
    sourceIndices: int[],
    targetIndices: int[],
    count: int,
    systemFlags: int[],
    bucketCounts: int[],
    bucketOffsets: int[]): int {
    bucketCapacity := FormatterImportOrderMinInt(bucketCounts.Length, bucketOffsets.Length)
    if bucketCapacity < 2 || count > sourceIndices.Length || count > targetIndices.Length {
        return -1
    }

    bucketCounts[0] = 0
    bucketCounts[1] = 0

    i := 0
    while i < count {
        sourceIndex := sourceIndices[i]
        if sourceIndex < 0 || sourceIndex >= systemFlags.Length {
            return -1
        }

        // System* (flag 1) sorts first -> bucket 0; non-System (flag 0) -> bucket 1.
        bucket := 1
        if systemFlags[sourceIndex] != 0 {
            bucket = 0
        }

        bucketCounts[bucket] = bucketCounts[bucket] + 1
        i = i + 1
    }

    bucketOffsets[0] = 0
    bucketOffsets[1] = bucketCounts[0]

    i = 0
    while i < count {
        sourceIndex := sourceIndices[i]
        bucket := 1
        if systemFlags[sourceIndex] != 0 {
            bucket = 0
        }

        writeIndex := bucketOffsets[bucket]
        targetIndices[writeIndex] = sourceIndex
        bucketOffsets[bucket] = writeIndex + 1
        i = i + 1
    }

    return count
}

func FormatterImportOrderMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

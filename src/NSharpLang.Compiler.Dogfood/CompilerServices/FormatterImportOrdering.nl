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

struct FormatterImportSortKeyTable {
    SystemFlags: int[]
    NameRanks: int[]
    NameRankCount: int
}

struct FormatterImportBucketTable {
    Counts: int[]
    Offsets: int[]
}

struct FormatterImportIndexTable {
    Indices: int[]
}

func FormatterImportOrderIndicesInto(
    systemFlags: int[],
    nameRanks: int[],
    nameRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    keys := new FormatterImportSortKeyTable { SystemFlags: systemFlags, NameRanks: nameRanks, NameRankCount: nameRankCount }
    buckets := new FormatterImportBucketTable { Counts: bucketCounts, Offsets: bucketOffsets }
    temp := new FormatterImportIndexTable { Indices: tempIndices }
    result := new FormatterImportIndexTable { Indices: resultIndices }
    return FormatterImportOrderIndicesCore(ref keys, ref buckets, ref temp, ref result)
}

func FormatterImportOrderIndicesCore(
    keys: &FormatterImportSortKeyTable,
    buckets: &FormatterImportBucketTable,
    temp: &FormatterImportIndexTable,
    result: &FormatterImportIndexTable): int {
    count := FormatterImportOrderMinInt(keys.SystemFlags.Length, keys.NameRanks.Length)
    if count == 0 {
        return 0
    }

    if count > temp.Indices.Length || count > result.Indices.Length {
        return -1
    }

    i := 0
    while i < count {
        temp.Indices[i] = i
        i = i + 1
    }

    // Pass 1: stable ascending sort by namespace rank (the ThenBy key).
    namePass := FormatterImportOrderNamePassCore(ref temp, ref result, count, ref keys, ref buckets)
    if namePass < 0 {
        return -1
    }

    // Pass 2: stable sort placing System* (flag 1) before non-System (flag 0),
    // preserving the ascending-name order established above.
    systemPass := FormatterImportOrderSystemPassCore(ref result, ref temp, count, ref keys, ref buckets)
    if systemPass < 0 {
        return -1
    }

    i = 0
    while i < count {
        result.Indices[i] = temp.Indices[i]
        i = i + 1
    }

    return count
}

func FormatterImportOrderNamePassCore(
    source: &FormatterImportIndexTable,
    target: &FormatterImportIndexTable,
    count: int,
    keys: &FormatterImportSortKeyTable,
    buckets: &FormatterImportBucketTable): int {
    bucketCapacity := FormatterImportOrderMinInt(buckets.Counts.Length, buckets.Offsets.Length)
    if keys.NameRankCount <= 0 || keys.NameRankCount + 1 > bucketCapacity || count > source.Indices.Length || count > target.Indices.Length {
        return -1
    }

    i := 0
    while i <= keys.NameRankCount {
        buckets.Counts[i] = 0
        buckets.Offsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        sourceIndex := source.Indices[i]
        if sourceIndex < 0 || sourceIndex >= keys.NameRanks.Length {
            return -1
        }

        rank := keys.NameRanks[sourceIndex]
        if rank <= 0 || rank > keys.NameRankCount {
            return -1
        }

        buckets.Counts[rank] = buckets.Counts[rank] + 1
        i = i + 1
    }

    offset := 0
    bucketIndex := 0
    while bucketIndex <= keys.NameRankCount {
        buckets.Offsets[bucketIndex] = offset
        offset = offset + buckets.Counts[bucketIndex]
        bucketIndex = bucketIndex + 1
    }

    i = 0
    while i < count {
        sourceIndex := source.Indices[i]
        rank := keys.NameRanks[sourceIndex]
        writeIndex := buckets.Offsets[rank]
        target.Indices[writeIndex] = sourceIndex
        buckets.Offsets[rank] = writeIndex + 1
        i = i + 1
    }

    return count
}

func FormatterImportOrderSystemPassCore(
    source: &FormatterImportIndexTable,
    target: &FormatterImportIndexTable,
    count: int,
    keys: &FormatterImportSortKeyTable,
    buckets: &FormatterImportBucketTable): int {
    bucketCapacity := FormatterImportOrderMinInt(buckets.Counts.Length, buckets.Offsets.Length)
    if bucketCapacity < 2 || count > source.Indices.Length || count > target.Indices.Length {
        return -1
    }

    buckets.Counts[0] = 0
    buckets.Counts[1] = 0

    i := 0
    while i < count {
        sourceIndex := source.Indices[i]
        if sourceIndex < 0 || sourceIndex >= keys.SystemFlags.Length {
            return -1
        }

        // System* (flag 1) sorts first -> bucket 0; non-System (flag 0) -> bucket 1.
        bucket := 1
        if keys.SystemFlags[sourceIndex] != 0 {
            bucket = 0
        }

        buckets.Counts[bucket] = buckets.Counts[bucket] + 1
        i = i + 1
    }

    buckets.Offsets[0] = 0
    buckets.Offsets[1] = buckets.Counts[0]

    i = 0
    while i < count {
        sourceIndex := source.Indices[i]
        bucket := 1
        if keys.SystemFlags[sourceIndex] != 0 {
            bucket = 0
        }

        writeIndex := buckets.Offsets[bucket]
        target.Indices[writeIndex] = sourceIndex
        buckets.Offsets[bucket] = writeIndex + 1
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

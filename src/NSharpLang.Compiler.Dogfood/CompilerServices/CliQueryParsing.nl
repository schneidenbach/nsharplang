import System.Numerics

struct CliBatchDuplicateIdRankTable {
    IdRanks: int[]
    UniqueIdCount: int
}

struct CliBatchDuplicateScratchTable {
    CountsByRank: int[]
    ResultRanks: int[]
}

struct CliBatchResultWordTable {
    OkWords: ulong[]
    ItemCount: int
}

func CliBatchDuplicateIdRanksInto(
    idRanks: int[],
    uniqueIdCount: int,
    countsByRank: int[],
    resultRanks: int[]): int {
    ranks := new CliBatchDuplicateIdRankTable { IdRanks: idRanks, UniqueIdCount: uniqueIdCount }
    scratch := new CliBatchDuplicateScratchTable { CountsByRank: countsByRank, ResultRanks: resultRanks }
    return CliBatchDuplicateIdRanksCore(ref ranks, ref scratch)
}

func CliBatchDuplicateIdRanksCore(ranks: &CliBatchDuplicateIdRankTable, scratch: &CliBatchDuplicateScratchTable): int {
    clearCount := ranks.UniqueIdCount + 1
    if clearCount > scratch.CountsByRank.Length {
        clearCount = scratch.CountsByRank.Length
    }

    i := 0
    while i < clearCount {
        scratch.CountsByRank[i] = 0
        i = i + 1
    }

    i = 0
    while i < ranks.IdRanks.Length {
        rank := ranks.IdRanks[i]
        if rank > 0 && rank <= ranks.UniqueIdCount && rank < scratch.CountsByRank.Length {
            scratch.CountsByRank[rank] = scratch.CountsByRank[rank] + 1
        }

        i = i + 1
    }

    duplicateCount := 0
    rank := 1
    while rank <= ranks.UniqueIdCount && rank < scratch.CountsByRank.Length {
        if scratch.CountsByRank[rank] > 1 {
            if duplicateCount < scratch.ResultRanks.Length {
                scratch.ResultRanks[duplicateCount] = rank
            }

            duplicateCount = duplicateCount + 1
        }

        rank = rank + 1
    }

    return duplicateCount
}

func CliBatchResultPackedSuccessCount(okWords: ulong[], itemCount: int): int {
    results := new CliBatchResultWordTable { OkWords: okWords, ItemCount: itemCount }
    return CliBatchResultPackedSuccessCountCore(ref results)
}

func CliBatchResultPackedSuccessCountCore(results: &CliBatchResultWordTable): int {
    if results.ItemCount <= 0 {
        return 0
    }

    fullWordCount := results.ItemCount >> 6
    if fullWordCount > results.OkWords.Length {
        fullWordCount = results.OkWords.Length
    }

    successCount := 0
    i := 0
    while i < fullWordCount {
        successCount = successCount + CliBatchResultPopCount64(results.OkWords[i])
        i = i + 1
    }

    lastBits := results.ItemCount & 63
    if lastBits != 0 && fullWordCount < results.OkWords.Length {
        shift := 64 - lastBits
        lastWord := (results.OkWords[fullWordCount] << shift) >> shift
        successCount = successCount + CliBatchResultPopCount64(lastWord)
    }

    return successCount
}

func CliBatchResultPopCount64(value: ulong): int {
    return BitOperations.PopCount(value)
}

func CliQueryDaemonParameterSummaryInto(args: string[], resultIndices: int[]): int {
    if resultIndices.Length < 7 {
        return -1
    }

    resultIndices[0] = -1
    resultIndices[1] = -1
    resultIndices[2] = -1
    resultIndices[3] = -1
    resultIndices[4] = -1
    resultIndices[5] = 0
    resultIndices[6] = 0

    i := 0
    while i < args.Length {
        arg := args[i]
        if arg == "--file" {
            if resultIndices[0] < 0 && i + 1 < args.Length {
                resultIndices[0] = i + 1
            }
        } else if arg == "--pos" {
            if resultIndices[1] < 0 && i + 1 < args.Length {
                resultIndices[1] = i + 1
            }
        } else if arg == "--name" {
            if resultIndices[2] < 0 && i + 1 < args.Length {
                resultIndices[2] = i + 1
            }
        } else if arg == "--kind" {
            if resultIndices[3] < 0 && i + 1 < args.Length {
                resultIndices[3] = i + 1
            }
        } else if arg == "--severity" {
            if resultIndices[4] < 0 && i + 1 < args.Length {
                resultIndices[4] = i + 1
            }
        } else if arg == "--include-keywords" {
            resultIndices[5] = 1
        } else if arg == "--clusters" {
            resultIndices[6] = 1
        }

        i = i + 1
    }

    return 0
}

// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CliQueryParsing.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CliQueryPositionChecksumInto(
    positions: string[],
    resultLines: int[],
    resultColumns: int[]): int {
    count := CliQueryMinInt(positions.Length, resultLines.Length)
    count = CliQueryMinInt(count, resultColumns.Length)
    results := new CliQueryPositionResultTable { Lines: resultLines, Columns: resultColumns }
    checksum := count
    i := 0

    while i < count {
        parsed := CliTryParsePositionPartsCore(positions[i], ref results, i, i)
        checksum = checksum + parsed * 97 + resultLines[i] * 31 + resultColumns[i] * 17
        i = i + 1
    }

    return checksum
}

func CliBatchDuplicateIdRankChecksumInto(
    idRanks: int[],
    uniqueIdCount: int,
    countsByRank: int[],
    resultRanks: int[],
    idLengthsByRank: int[]): int {
    duplicateCount := CliBatchDuplicateIdRanksInto(
        idRanks,
        uniqueIdCount,
        countsByRank,
        resultRanks)

    checksum := duplicateCount
    i := 0
    while i < duplicateCount && i < resultRanks.Length {
        rank := resultRanks[i]
        length := 0
        if rank >= 0 && rank < idLengthsByRank.Length {
            length = idLengthsByRank[rank]
        }

        checksum = checksum + rank * 31 + length * 17
        i = i + 1
    }

    return checksum
}

func CliBatchResultPackedCountChecksum(okWords: ulong[], itemCount: int): int {
    successCount := CliBatchResultPackedSuccessCount(okWords, itemCount)
    failureCount := itemCount - successCount
    return itemCount * 31 + successCount * 17 + failureCount * 13
}

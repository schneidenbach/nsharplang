// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CliArguments.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CliWatchForwardedArgIndicesInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliWatchForwardedArgIndicesCore(ref arguments, ref results)
}

func CliWatchForwardedArgIndicesCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    resultCount := 0
    i := 1

    while i < args.Args.Length {
        arg := args.Args[i]
        if CliWatchArgumentIsOptionWithValue(arg) {
            i = i + 2
            continue
        }

        if arg == "--help" || arg == "-h" {
            i = i + 1
            continue
        }

        if resultCount < resultIndices.Indices.Length {
            resultIndices.Indices[resultCount] = i
        }

        resultCount = resultCount + 1
        i = i + 1
    }

    return resultCount
}

func CliWatchArgumentIsOptionWithValue(arg: string): bool {
    return arg == "--project" || arg == "--debounce-ms" || arg == "--max-runs"
}

func CliWatchForwardedArgChecksumInto(args: string[], resultIndices: int[]): int {
    resultCount := CliWatchForwardedArgIndicesInto(args, resultIndices)
    checksum := resultCount
    i := 0

    while i < resultCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + args[sourceIndex].Length * 17
        i = i + 1
    }

    return checksum
}

func CliTestOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 10 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = -1
    resultIndices.Indices[4] = 0
    resultIndices.Indices[5] = 0
    resultIndices.Indices[6] = 0
    resultIndices.Indices[7] = 0
    resultIndices.Indices[8] = 0
    resultIndices.Indices[9] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        length := arg.Length
        kind := 0
        if length == 2 {
            if arg[0] == '-' && arg[1] == 'h' {
                kind = 1
            }
        } else if length == 4 {
            if arg[0] == 'h' && arg[1] == 'e' && arg[2] == 'l' && arg[3] == 'p' {
                kind = 2
            }
        } else if length == 6 {
            if arg[0] == '-' && arg[1] == '-' {
                if arg[2] == 'h'
                    && arg[3] == 'e'
                    && arg[4] == 'l'
                    && arg[5] == 'p' {
                    kind = 1
                } else if arg[2] == 'j'
                    && arg[3] == 's'
                    && arg[4] == 'o'
                    && arg[5] == 'n' {
                    kind = 8
                }
            }
        } else if length == 8 {
            if arg[0] == '-'
                && arg[1] == '-'
                && arg[2] == 'f'
                && arg[3] == 'i'
                && arg[4] == 'l'
                && arg[5] == 't'
                && arg[6] == 'e'
                && arg[7] == 'r' {
                kind = 4
            }
        } else if length == 9 {
            if arg[0] == '-' && arg[1] == '-' {
                if arg[2] == 'p'
                    && arg[3] == 'r'
                    && arg[4] == 'o'
                    && arg[5] == 'j'
                    && arg[6] == 'e'
                    && arg[7] == 'c'
                    && arg[8] == 't' {
                    kind = 3
                } else if arg[2] == 'v'
                    && arg[3] == 'e'
                    && arg[4] == 'r'
                    && arg[5] == 'b'
                    && arg[6] == 'o'
                    && arg[7] == 's'
                    && arg[8] == 'e' {
                    kind = 7
                } else if arg[2] == 't'
                    && arg[3] == 'i'
                    && arg[4] == 'm'
                    && arg[5] == 'e'
                    && arg[6] == 'o'
                    && arg[7] == 'u'
                    && arg[8] == 't' {
                    kind = 5
                } else if arg[2] == 'b'
                    && arg[3] == 'a'
                    && arg[4] == 'c'
                    && arg[5] == 'k'
                    && arg[6] == 'e'
                    && arg[7] == 'n'
                    && arg[8] == 'd' {
                    kind = 6
                }
            }
        } else if length == 10 {
            if arg[0] == '-' && arg[1] == '-' {
                if arg[2] == 'c'
                    && arg[3] == 'o'
                    && arg[4] == 'v'
                    && arg[5] == 'e'
                    && arg[6] == 'r'
                    && arg[7] == 'a'
                    && arg[8] == 'g'
                    && arg[9] == 'e' {
                    kind = 10
                } else if arg[2] == 'n'
                    && arg[3] == 'o'
                    && arg[4] == '-'
                    && arg[5] == 'c'
                    && arg[6] == 'a'
                    && arg[7] == 'c'
                    && arg[8] == 'h'
                    && arg[9] == 'e' {
                    kind = 11
                }
            }
        } else if length == 17 {
            if arg[0] == '-'
                && arg[1] == '-'
                && arg[2] == 'c'
                && arg[3] == 'o'
                && arg[4] == 'v'
                && arg[5] == 'e'
                && arg[6] == 'r'
                && arg[7] == 'a'
                && arg[8] == 'g'
                && arg[9] == 'e'
                && arg[10] == '-'
                && arg[11] == 'r'
                && arg[12] == 'e'
                && arg[13] == 'p'
                && arg[14] == 'o'
                && arg[15] == 'r'
                && arg[16] == 't' {
                kind = 9
            }
        }

        if kind == 1 || (i == 0 && kind == 2) {
            resultIndices.Indices[9] = 1
        } else if kind == 3 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 4 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 5 {
            if resultIndices.Indices[2] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[2] = i + 1
            }
        } else if kind == 6 {
            if resultIndices.Indices[3] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[3] = i + 1
            }
        } else if kind == 7 {
            resultIndices.Indices[4] = 1
        } else if kind == 8 {
            resultIndices.Indices[5] = 1
        } else if kind == 9 {
            resultIndices.Indices[6] = 1
        } else if kind == 10 {
            resultIndices.Indices[7] = 1
        } else if kind == 11 {
            resultIndices.Indices[8] = 1
        }

        i = i + 1
    }

    return 0
}

func CliTestOptionSummaryChecksumInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    code := CliTestOptionSummaryCore(ref arguments, ref results)
    if code < 0 {
        return code
    }

    checksum := args.Length + 17
    i := 0
    while i < 10 {
        value := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (value + 1) * 31
        if value >= 0 && value < args.Length {
            checksum = checksum + args[value].Length * 13
        }

        i = i + 1
    }

    return checksum
}

func CliLintFileArgChecksumInto(
    args: string[],
    projectValueIndices: int[],
    resultIndices: int[]): int {
    resultCount := CliLintFileArgIndicesInto(args, projectValueIndices, resultIndices)
    checksum := resultCount
    i := 0
    while i < resultCount {
        index := resultIndices[i]
        length := 0
        if index >= 0 && index < args.Length {
            length = args[index].Length
        }

        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + length * 17
        i = i + 1
    }

    return checksum
}

func CliTidyDependencyStatusRankChecksumInto(
    packageNames: string[],
    importNamespaces: string[],
    resultStatusRanks: int[]): int {
    count := CliTidyDependencyStatusRanksInto(packageNames, importNamespaces, resultStatusRanks)
    checksum := count
    i := 0
    while i < count && i < resultStatusRanks.Length {
        rank := resultStatusRanks[i]
        checksum = checksum + (i + 1) * 97 + rank * 31 + packageNames[i].Length * 17
        i = i + 1
    }

    return checksum
}

func CliTidyRemovalLineKeepChecksumInto(lines: string[], packageNames: string[], resultFlags: int[]): int {
    count := CliTidyRemovalLineKeepFlagsInto(lines, packageNames, resultFlags)
    checksum := count
    i := 0
    while i < count && i < resultFlags.Length {
        checksum = checksum + (i + 1) * 97 + resultFlags[i] * 31 + lines[i].Length * 17
        i = i + 1
    }

    return checksum
}

func CliBuildOperandSummaryInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    kinds := new CliBuildArgumentKindTable { Kinds: kindIds }
    links := new CliBuildArgumentLinkTable {
        NextIndices: nextIndices,
        PreviousIndices: previousIndices,
        NextOptionIndices: nextOptionIndices
    }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliBuildOperandSummaryCore(ref arguments, ref kinds, ref links, ref results)
}

func CliBuildOperandIndicesInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    kinds := new CliBuildArgumentKindTable { Kinds: kindIds }
    links := new CliBuildArgumentLinkTable {
        NextIndices: nextIndices,
        PreviousIndices: previousIndices,
        NextOptionIndices: nextOptionIndices
    }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliBuildOperandIndicesCore(ref arguments, ref kinds, ref links, ref results)
}

func CliBuildOperandIndicesCore(
    args: &CliArgumentTable,
    kindIds: &CliBuildArgumentKindTable,
    links: &CliBuildArgumentLinkTable,
    resultIndices: &CliIndexResultTable): int {
    count := CliBuildOperandSummaryCore(ref args, ref kindIds, ref links, ref resultIndices)
    if count <= 0 {
        return count
    }

    sourceIndex := resultIndices.Indices[0]
    resultCount := 0
    while sourceIndex >= 0 {
        resultIndices.Indices[resultCount] = sourceIndex
        resultCount = resultCount + 1
        sourceIndex = links.NextIndices[sourceIndex]
    }

    return resultCount
}

func CliBuildOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliBuildOptionSummaryCore(ref arguments, ref results)
}

func CliBuildOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 9 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = 0
    resultIndices.Indices[4] = 0
    resultIndices.Indices[5] = 0
    resultIndices.Indices[6] = 0
    resultIndices.Indices[7] = 0
    resultIndices.Indices[8] = 0

    outputLongIndex := -1
    outputShortIndex := -1
    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[8] = 1
        }

        kind := CliBuildOptionSummaryKind(arg)
        if kind == 1 {
            if outputLongIndex < 0 && i + 1 < args.Args.Length {
                outputLongIndex = i + 1
            }
        } else if kind == 2 {
            if outputShortIndex < 0 && i + 1 < args.Args.Length {
                outputShortIndex = i + 1
            }
        } else if kind == 3 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 4 {
            if resultIndices.Indices[2] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[2] = i + 1
            }
        } else if kind == 5 {
            resultIndices.Indices[3] = 1
        } else if kind == 6 {
            resultIndices.Indices[4] = 1
        } else if kind == 7 {
            resultIndices.Indices[5] = 1
        } else if kind == 8 {
            resultIndices.Indices[6] = 1
        } else if kind == 9 {
            resultIndices.Indices[7] = 1
        } else if kind == 10 {
            resultIndices.Indices[8] = 1
        }

        i = i + 1
    }

    if outputLongIndex >= 0 {
        resultIndices.Indices[0] = outputLongIndex
    } else {
        resultIndices.Indices[0] = outputShortIndex
    }

    return 0
}

func CliBuildOptionSummaryKind(arg: string): int {
    length := arg.Length
    if length == 2 {
        if arg[0] != '-' {
            return 0
        }

        if arg[1] == 'o' {
            return 2
        }

        if arg[1] == 'h' {
            return 10
        }

        return 0
    }

    if length < 5 || arg[0] != '-' || arg[1] != '-' {
        return 0
    }

    if length == 5 {
        if arg[2] == 'a' && arg[3] == 'o' && arg[4] == 't' {
            return 9
        }

        return 0
    }

    if length == 6 {
        if arg[2] == 'h'
            && arg[3] == 'e'
            && arg[4] == 'l'
            && arg[5] == 'p' {
            return 10
        }

        return 0
    }

    if length == 8 {
        if arg[2] == 'o'
            && arg[3] == 'u'
            && arg[4] == 't'
            && arg[5] == 'p'
            && arg[6] == 'u'
            && arg[7] == 't' {
            return 1
        }

        return 0
    }

    if length == 9 {
        marker := arg[2]
        if marker == 'b'
            && arg[3] == 'a'
            && arg[4] == 'c'
            && arg[5] == 'k'
            && arg[6] == 'e'
            && arg[7] == 'n'
            && arg[8] == 'd' {
            return 3
        }

        if marker == 'p'
            && arg[3] == 'r'
            && arg[4] == 'o'
            && arg[5] == 'j'
            && arg[6] == 'e'
            && arg[7] == 'c'
            && arg[8] == 't' {
            return 4
        }

        if marker == 'r'
            && arg[3] == 'e'
            && arg[4] == 'l'
            && arg[5] == 'e'
            && arg[6] == 'a'
            && arg[7] == 's'
            && arg[8] == 'e' {
            return 5
        }

        if marker == 't'
            && arg[3] == 'i'
            && arg[4] == 'm'
            && arg[5] == 'i'
            && arg[6] == 'n'
            && arg[7] == 'g'
            && arg[8] == 's' {
            return 7
        }

        if marker == 'v'
            && arg[3] == 'e'
            && arg[4] == 'r'
            && arg[5] == 'b'
            && arg[6] == 'o'
            && arg[7] == 's'
            && arg[8] == 'e' {
            return 6
        }

        return 0
    }

    if length == 13
        && arg[2] == 'p'
        && arg[3] == 'e'
        && arg[4] == 'r'
        && arg[5] == 'f'
        && arg[6] == '-'
        && arg[7] == 'r'
        && arg[8] == 'e'
        && arg[9] == 'p'
        && arg[10] == 'o'
        && arg[11] == 'r'
        && arg[12] == 't' {
        return 8
    }

    return 0
}

func CliBuildOptionSummaryChecksumInto(args: string[], resultIndices: int[]): int {
    code := CliBuildOptionSummaryInto(args, resultIndices)
    if code < 0 {
        return code
    }

    checksum := args.Length + 23
    i := 0
    while i < 9 {
        value := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (value + 1) * 31
        if i < 3 && value >= 0 && value < args.Length {
            checksum = checksum + args[value].Length * 13
        }

        i = i + 1
    }

    return checksum
}

func CliFixSafetyFilterChecksumInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    length := safetyRanks.Length
    if resultIndices.Length < length {
        matchCount := CliFixSafetyFilterIndicesInto(safetyRanks, includeReviewNeeded, resultIndices)
        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            index := resultIndices[i]
            rank := 0
            if index >= 0 && index < length {
                rank = safetyRanks[index]
            }

            checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + rank * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next := i + 1
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 2
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 3
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 4
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 5
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 6
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 7
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        i = i + 8
    }

    while i < length {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return checksum + matchCount
}

struct CliFixEditCountTable {
    Counts: int[]
}

struct CliFixEditFlattenResultTable {
    ActionIndices: int[]
    EditIndices: int[]
}

func CliFixEditFlattenIndicesInto(
    editCounts: int[],
    resultActionIndices: int[],
    resultEditIndices: int[]): int {
    editCountTable := new CliFixEditCountTable { Counts: editCounts }
    results := new CliFixEditFlattenResultTable {
        ActionIndices: resultActionIndices,
        EditIndices: resultEditIndices
    }
    return CliFixEditFlattenIndicesCore(ref editCountTable, ref results)
}

func CliFixEditFlattenIndicesCore(
    editCountTable: &CliFixEditCountTable,
    result: &CliFixEditFlattenResultTable): int {
    editCounts := editCountTable.Counts
    resultActionIndices := result.ActionIndices
    resultEditIndices := result.EditIndices
    resultIndex := 0
    actionIndex := 0
    actionCount := editCounts.Length

    while actionIndex < actionCount {
        editCount := editCounts[actionIndex]
        if editCount < 0 {
            return -1
        }

        nextResultIndex := resultIndex + editCount
        if nextResultIndex > resultActionIndices.Length || nextResultIndex > resultEditIndices.Length {
            return -1
        }

        if editCount == 1 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
        } else if editCount == 2 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
        } else if editCount == 3 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
            next = resultIndex + 2
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 2
        } else if editCount == 4 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
            next = resultIndex + 2
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 2
            next = resultIndex + 3
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 3
        } else if editCount == 5 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
            next = resultIndex + 2
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 2
            next = resultIndex + 3
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 3
            next = resultIndex + 4
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 4
        } else if editCount == 6 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
            next = resultIndex + 2
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 2
            next = resultIndex + 3
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 3
            next = resultIndex + 4
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 4
            next = resultIndex + 5
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 5
        } else if editCount == 7 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
            next = resultIndex + 2
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 2
            next = resultIndex + 3
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 3
            next = resultIndex + 4
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 4
            next = resultIndex + 5
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 5
            next = resultIndex + 6
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 6
        } else if editCount == 8 {
            resultActionIndices[resultIndex] = actionIndex
            resultEditIndices[resultIndex] = 0
            next := resultIndex + 1
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 1
            next = resultIndex + 2
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 2
            next = resultIndex + 3
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 3
            next = resultIndex + 4
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 4
            next = resultIndex + 5
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 5
            next = resultIndex + 6
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 6
            next = resultIndex + 7
            resultActionIndices[next] = actionIndex
            resultEditIndices[next] = 7
        } else {
            editIndex := 0
            while editIndex < editCount {
                targetIndex := resultIndex + editIndex
                resultActionIndices[targetIndex] = actionIndex
                resultEditIndices[targetIndex] = editIndex
                editIndex = editIndex + 1
            }
        }

        resultIndex = nextResultIndex
        actionIndex = actionIndex + 1
    }

    return resultIndex
}

func CliFixEditFlattenChecksumInto(
    editCounts: int[],
    resultActionIndices: int[],
    resultEditIndices: int[]): int {
    flattenedCount := CliFixEditFlattenIndicesInto(editCounts, resultActionIndices, resultEditIndices)
    if flattenedCount < 0 {
        return flattenedCount
    }

    checksum := flattenedCount
    i := 0
    while i < flattenedCount {
        actionIndex := resultActionIndices[i]
        editIndex := resultEditIndices[i]
        editCount := 0
        if actionIndex >= 0 && actionIndex < editCounts.Length {
            editCount = editCounts[actionIndex]
        }

        checksum = checksum + (i + 1) * 97 + (actionIndex + 1) * 31 + (editIndex + 1) * 17 + editCount * 13
        i = i + 1
    }

    return checksum
}

func CliFixSkippedChecksumInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    skippedCount := CliFixSkippedIndicesInto(safetyRanks, includeReviewNeeded, resultIndices)
    checksum := skippedCount
    i := 0
    while i < skippedCount && i < resultIndices.Length {
        index := resultIndices[i]
        rank := 0
        if index >= 0 && index < safetyRanks.Length {
            rank = safetyRanks[index]
        }

        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + rank * 17
        i = i + 1
    }

    return checksum
}

func CliFixAppliedFileGroupChecksumInto(
    fileRanks: int[],
    uniqueFileRankCount: int,
    countsByRank: int[],
    offsetsByRank: int[],
    writeOffsetsByRank: int[],
    resultRanks: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    groupCount := CliFixAppliedFileGroupsInto(
        fileRanks,
        uniqueFileRankCount,
        countsByRank,
        offsetsByRank,
        writeOffsetsByRank,
        resultRanks,
        resultStarts,
        resultCounts,
        resultIndices)

    checksum := groupCount
    groupIndex := 0
    while groupIndex < groupCount {
        rank := resultRanks[groupIndex]
        start := resultStarts[groupIndex]
        count := resultCounts[groupIndex]
        checksum = checksum + (groupIndex + 1) * 97 + rank * 31 + (start + 1) * 17 + count * 13

        i := 0
        while i < count {
            sourceIndex := resultIndices[start + i]
            checksum = checksum + (sourceIndex + 1) * 11 + fileRanks[sourceIndex] * 7 + (i + 1) * 5
            i = i + 1
        }

        groupIndex = groupIndex + 1
    }

    return checksum
}

func CliUnifiedDiffHunkRangeChecksumInto(
    kindIds: int[],
    oldLines: int[],
    newLines: int[],
    contextLines: int,
    resultStarts: int[],
    resultLengths: int[],
    resultOldStarts: int[],
    resultOldCounts: int[],
    resultNewStarts: int[],
    resultNewCounts: int[]): int {
    hunkCount := CliUnifiedDiffHunkRangesInto(
        kindIds,
        oldLines,
        newLines,
        contextLines,
        resultStarts,
        resultLengths,
        resultOldStarts,
        resultOldCounts,
        resultNewStarts,
        resultNewCounts)

    checksum := hunkCount
    i := 0
    while i < hunkCount {
        checksum = checksum
            + (i + 1) * 97
            + (resultStarts[i] + 1) * 31
            + resultLengths[i] * 17
            + resultOldStarts[i] * 13
            + resultOldCounts[i] * 11
            + resultNewStarts[i] * 7
            + resultNewCounts[i] * 5
        i = i + 1
    }

    return checksum
}

func CliCleanArtifactDirectoryChecksumInto(
    kindRanks: int[],
    nodeModuleFlags: int[],
    pathRanks: int[],
    pathLengths: int[],
    seenPathRanks: int[],
    lengthCounts: int[],
    lengthOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    orderedCount := CliCleanArtifactDirectoryIndicesInto(
        kindRanks,
        nodeModuleFlags,
        pathRanks,
        pathLengths,
        seenPathRanks,
        lengthCounts,
        lengthOffsets,
        tempIndices,
        resultIndices)
    if orderedCount < 0 {
        return orderedCount
    }

    checksum := orderedCount
    i := 0
    while i < orderedCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        kindRank := 0
        pathRank := 0
        pathLength := 0
        if sourceIndex >= 0 && sourceIndex < kindRanks.Length {
            kindRank = kindRanks[sourceIndex]
            pathRank = pathRanks[sourceIndex]
            pathLength = pathLengths[sourceIndex]
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + kindRank * 17 + pathRank * 13 + pathLength * 7
        i = i + 1
    }

    return checksum
}

func CliUpdateAllNuGetDependencyChecksumInto(
    nugetFlags: int[],
    resultIndices: int[]): int {
    length := nugetFlags.Length
    if resultIndices.Length < length {
        matchCount := CliUpdateAllNuGetDependencyIndicesInto(nugetFlags, resultIndices)
        if matchCount < 0 {
            return matchCount
        }

        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            sourceIndex := resultIndices[i]
            flag := 0
            if sourceIndex >= 0 && sourceIndex < length {
                flag = nugetFlags[sourceIndex]
            }

            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + flag * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 16
    while i <= unrolledLimit {
        if nugetFlags[i] != 0 {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + 17
        }

        next := i + 1
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 2
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 3
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 4
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 5
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 6
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 7
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 8
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 9
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 10
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 11
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 12
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 13
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 14
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 15
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        i = i + 16
    }

    while i < length {
        if nugetFlags[i] != 0 {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + 17
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliUpdateTargetNuGetDependencyChecksumInto(
    nameRanks: int[],
    targetNameRank: int,
    resultIndices: int[]): int {
    if targetNameRank <= 0 {
        return 0
    }

    length := nameRanks.Length
    if resultIndices.Length < length {
        matchCount := CliUpdateTargetNuGetDependencyIndicesInto(nameRanks, targetNameRank, resultIndices)
        if matchCount < 0 {
            return matchCount
        }

        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            sourceIndex := resultIndices[i]
            nameRank := 0
            if sourceIndex >= 0 && sourceIndex < length {
                nameRank = nameRanks[sourceIndex]
            }

            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + 17 + nameRank * 13
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := matchCount
    i := 0
    targetScore := 17 + targetNameRank * 13

    unrolledLimit := length - 16
    while i <= unrolledLimit {
        if nameRanks[i] == targetNameRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        next := i + 1
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 2
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 3
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 4
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 5
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 6
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 7
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 8
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 9
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 10
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 11
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 12
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 13
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 14
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 15
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        i = i + 16
    }

    while i < length {
        if nameRanks[i] == targetNameRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliReferenceTypeFilterChecksumInto(
    typeRanks: int[],
    targetTypeRank: int,
    resultIndices: int[]): int {
    if targetTypeRank <= 0 {
        return 0
    }

    length := typeRanks.Length
    if resultIndices.Length < length {
        matchCount := CliReferenceTypeFilterIndicesInto(typeRanks, targetTypeRank, resultIndices)
        if matchCount < 0 {
            return matchCount
        }

        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            sourceIndex := resultIndices[i]
            typeRank := 0
            if sourceIndex >= 0 && sourceIndex < length {
                typeRank = typeRanks[sourceIndex]
            }

            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + typeRank * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := matchCount
    i := 0
    targetScore := targetTypeRank * 17

    unrolledLimit := length - 16
    while i <= unrolledLimit {
        if typeRanks[i] == targetTypeRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        next := i + 1
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 2
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 3
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 4
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 5
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 6
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 7
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 8
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 9
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 10
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 11
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 12
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 13
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 14
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 15
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        i = i + 16
    }

    while i < length {
        if typeRanks[i] == targetTypeRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliStableDistinctRankChecksumInto(
    ranks: int[],
    uniqueRankCount: int,
    seenRanks: int[],
    resultIndices: int[],
    rankWeights: int[]): int {
    resultCount := CliStableDistinctRankIndicesInto(
        ranks,
        uniqueRankCount,
        seenRanks,
        resultIndices)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        rank := 0
        weight := 0
        if sourceIndex >= 0 && sourceIndex < ranks.Length {
            rank = ranks[sourceIndex]
            if rank >= 0 && rank < rankWeights.Length {
                weight = rankWeights[rank]
            }
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + rank * 17 + weight * 13
        i = i + 1
    }

    return checksum
}

func CliReferenceResolutionBestScoreChecksum(scores: int[], weights: int[], count: int): int {
    bestIndex := CliReferenceResolutionBestScoreIndex(scores, count)
    if bestIndex < 0 {
        return bestIndex
    }

    weight := 0
    if bestIndex < weights.Length {
        weight = weights[bestIndex]
    }

    return (bestIndex + 1) * 97 + scores[bestIndex] * 31 + weight * 17
}

func CliPositionalArgIndicesInto(
    args: string[],
    optionsWithValues: string[],
    resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    options := new CliOptionValueTable { Options: optionsWithValues }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliPositionalArgIndicesCore(ref arguments, ref options, ref results)
}

func CliPositionalArgIndicesCore(
    args: &CliArgumentTable,
    optionsWithValues: &CliOptionValueTable,
    resultIndices: &CliIndexResultTable): int {
    resultCount := 0
    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if CliArgumentIsOptionWithValueCore(arg, ref optionsWithValues) {
            i = i + 2
            continue
        }

        if CliArgumentIsValueLessFlag(arg) {
            i = i + 1
            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            if resultCount < resultIndices.Indices.Length {
                resultIndices.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliPositionalArgChecksumInto(
    args: string[],
    optionsWithValues: string[],
    resultIndices: int[]): int {
    count := CliPositionalArgIndicesInto(args, optionsWithValues, resultIndices)
    checksum := count
    i := 0
    while i < count && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        length := 0
        if sourceIndex >= 0 && sourceIndex < args.Length {
            length = args[sourceIndex].Length
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + length * 17
        i = i + 1
    }

    return checksum
}

func CliExportCSharpFirstOperandChecksumInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    sourceIndex := CliExportCSharpFirstOperandIndexInto(
        args,
        kindIds,
        nextIndices,
        previousIndices,
        nextOptionIndices,
        resultIndices)
    checksum := sourceIndex + 1
    if sourceIndex >= 0 && sourceIndex < args.Length {
        arg := args[sourceIndex]
        checksum = checksum + arg.Length * 31
        i := 0
        while i < arg.Length {
            checksum = checksum + arg[i] * (i + 1)
            i = i + 1
        }
    }

    return checksum
}

func CliTidyDependencyStatusSummaryChecksumInto(statusRanks: int[], resultCounts: int[]): int {
    count := CliTidyDependencyStatusSummaryInto(statusRanks, resultCounts)
    if count < 0 {
        return count
    }

    okValue := 13
    if resultCounts[0] == 0 {
        okValue = 7
    }

    return count + okValue + resultCounts[0] * 31 + resultCounts[1] * 17
}

func CliTestOutcomeSummaryChecksumInto(outcomeRanks: int[], count: int, resultCounts: int[]): int {
    count = CliTestOutcomeSummaryInto(outcomeRanks, count, resultCounts)
    if count < 0 {
        return count
    }

    okValue := 7
    if resultCounts[3] != 0 {
        okValue = 13
    }

    return count + okValue + resultCounts[0] * 31 + resultCounts[1] * 17 + resultCounts[2] * 11 + resultCounts[3] * 5
}

struct CliPathTable {
    Paths: string[]
}

func CliFormatDiscoveredPathFlagsCore(
    paths: &CliPathTable,
    flags: &CliFlagResultTable): int {
    relativePaths := paths.Paths
    resultFlags := flags.Flags
    count := relativePaths.Length
    if count > resultFlags.Length {
        count = resultFlags.Length
    }

    i := 0
    while i < count {
        resultFlags[i] = CliShouldFormatDiscoveredPath(relativePaths[i])
        i = i + 1
    }

    return count
}

func CliFormatDiscoveredPathChecksumInto(relativePaths: string[], resultFlags: int[]): int {
    paths := new CliPathTable { Paths: relativePaths }
    flags := new CliFlagResultTable { Flags: resultFlags }
    count := CliFormatDiscoveredPathFlagsCore(ref paths, ref flags)
    checksum := count
    i := 0

    while i < count {
        checksum = checksum + (i + 1) * 31 + resultFlags[i] * 17 + relativePaths[i].Length * 7
        i = i + 1
    }

    return checksum
}

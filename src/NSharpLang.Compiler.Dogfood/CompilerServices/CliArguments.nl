struct CliArgumentTable {
    Args: string[]
}

struct CliOptionValueTable {
    Options: string[]
}

struct CliIndexResultTable {
    Indices: int[]
}

struct CliProjectOptionValueIndexTable {
    Indices: int[]
}

struct CliPackageNameTable {
    Names: string[]
}

struct CliImportNamespaceTable {
    Namespaces: string[]
}

struct CliStatusRankResultTable {
    Ranks: int[]
}

struct CliLineTable {
    Lines: string[]
}

struct CliFlagResultTable {
    Flags: int[]
}

struct CliSymbolNameTable {
    Names: string[]
}

struct CliBuildArgumentKindTable {
    Kinds: int[]
}

struct CliBuildArgumentLinkTable {
    NextIndices: int[]
    PreviousIndices: int[]
    NextOptionIndices: int[]
}

struct CliFixSafetyRankTable {
    Ranks: int[]
}

struct CliFixFileRankTable {
    Ranks: int[]
}

struct CliFixRankBucketTable {
    CountsByRank: int[]
    OffsetsByRank: int[]
    WriteOffsetsByRank: int[]
}

struct CliFixAppliedFileGroupResultTable {
    Ranks: int[]
    Starts: int[]
    Counts: int[]
    Indices: int[]
}

struct CliUnifiedDiffLineTable {
    Kinds: int[]
    OldLines: int[]
    NewLines: int[]
}

struct CliUnifiedDiffHunkResultTable {
    Starts: int[]
    Lengths: int[]
    OldStarts: int[]
    OldCounts: int[]
    NewStarts: int[]
    NewCounts: int[]
}

struct CliCleanArtifactInputTable {
    KindRanks: int[]
    NodeModuleFlags: int[]
    PathRanks: int[]
    PathLengths: int[]
}

struct CliCleanArtifactScratchTable {
    SeenPathRanks: int[]
    LengthCounts: int[]
    LengthOffsets: int[]
    TempIndices: int[]
}

struct CliFlagTable {
    Flags: int[]
}

struct CliRankTable {
    Ranks: int[]
}

struct CliSeenRankTable {
    Ranks: int[]
}

struct CliCountResultTable {
    Counts: int[]
}

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

func CliFirstPositionalArgIndex(args: string[], optionsWithValues: string[]): int {
    arguments := new CliArgumentTable { Args: args }
    options := new CliOptionValueTable { Options: optionsWithValues }
    return CliFirstPositionalArgIndexCore(ref arguments, ref options)
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

func CliFirstPositionalArgIndexCore(args: &CliArgumentTable, optionsWithValues: &CliOptionValueTable): int {
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
            return i
        }

        i = i + 1
    }

    return -1
}

func CliRunFirstOperandIndex(args: string[]): int {
    arguments := new CliArgumentTable { Args: args }
    return CliRunFirstOperandIndexCore(ref arguments)
}

func CliRunFirstOperandIndexCore(args: &CliArgumentTable): int {
    i := 0
    while i < args.Args.Length {
        if args.Args[i] == "--backend" && i + 1 < args.Args.Length {
            i = i + 2
            continue
        }

        return i
    }

    return -1
}

func CliCheckArgumentSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliCheckArgumentSummaryCore(ref arguments, ref results)
}

func CliCheckArgumentSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 7 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = 0
    resultIndices.Indices[4] = 0
    resultIndices.Indices[5] = 0
    resultIndices.Indices[6] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[6] = 1
        }

        kind := CliCheckArgumentSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 3 {
            resultIndices.Indices[3] = 1
        } else if kind == 4 {
            resultIndices.Indices[4] = 1
        } else if kind == 5 {
            resultIndices.Indices[5] = 1
        } else if kind == 6 {
            resultIndices.Indices[6] = 1
        }

        i = i + 1
    }

    i = 0
    while i < args.Args.Length {
        arg := args.Args[i]
        kind := CliCheckArgumentSummaryKind(arg)
        if (kind == 1 || kind == 2) && i + 1 < args.Args.Length {
            i = i + 2
            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            resultIndices.Indices[2] = i
            break
        }

        i = i + 1
    }

    return 0
}

func CliCheckArgumentSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--backend" {
        return 2
    }

    if arg == "--text" {
        return 3
    }

    if arg == "--aot" {
        return 4
    }

    if arg == "--systems-report" {
        return 5
    }

    if arg == "--help" || arg == "-h" {
        return 6
    }

    return 0
}

func CliFixArgumentSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliFixArgumentSummaryCore(ref arguments, ref results)
}

func CliFixArgumentSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 7 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = 0
    resultIndices.Indices[4] = 0
    resultIndices.Indices[5] = 0
    resultIndices.Indices[6] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[6] = 1
        }

        kind := CliFixArgumentSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 3 {
            resultIndices.Indices[3] = 1
        } else if kind == 4 {
            resultIndices.Indices[4] = 1
        } else if kind == 5 {
            resultIndices.Indices[5] = 1
        } else if kind == 6 {
            resultIndices.Indices[6] = 1
        }

        i = i + 1
    }

    i = 0
    while i < args.Args.Length {
        arg := args.Args[i]
        kind := CliFixArgumentSummaryKind(arg)
        if kind == 1 || kind == 2 {
            if i + 1 < args.Args.Length {
                i = i + 2
            } else {
                i = i + 1
            }

            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            resultIndices.Indices[2] = i
            break
        }

        i = i + 1
    }

    return 0
}

func CliFixArgumentSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--file" {
        return 2
    }

    if arg == "--dry-run" {
        return 3
    }

    if arg == "--text" {
        return 4
    }

    if arg == "--include-review-needed" {
        return 5
    }

    if arg == "--help" || arg == "-h" {
        return 6
    }

    return 0
}

func CliAddArgumentSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliAddArgumentSummaryCore(ref arguments, ref results)
}

func CliAddArgumentSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 6 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = 0
    resultIndices.Indices[4] = 0
    resultIndices.Indices[5] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[5] = 1
        }

        kind := CliAddArgumentSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 3 {
            resultIndices.Indices[3] = 1
        } else if kind == 4 {
            resultIndices.Indices[4] = 1
        } else if kind == 5 {
            resultIndices.Indices[5] = 1
        }

        i = i + 1
    }

    i = 0
    while i < args.Args.Length {
        arg := args.Args[i]
        kind := CliAddArgumentSummaryKind(arg)
        if kind == 1 || kind == 2 {
            if i + 1 < args.Args.Length {
                i = i + 2
            } else {
                i = i + 1
            }

            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            resultIndices.Indices[2] = i
            break
        }

        i = i + 1
    }

    return 0
}

func CliAddArgumentSummaryKind(arg: string): int {
    if arg == "--version" {
        return 1
    }

    if arg == "--path" {
        return 2
    }

    if arg == "--framework" {
        return 3
    }

    if arg == "--prerelease" {
        return 4
    }

    if arg == "--help" || arg == "-h" {
        return 5
    }

    return 0
}

func CliRemoveArgumentSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliRemoveArgumentSummaryCore(ref arguments, ref results)
}

func CliRemoveArgumentSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 2 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[1] = 1
        }

        if arg == "--help" || arg == "-h" {
            resultIndices.Indices[1] = 1
        }

        if resultIndices.Indices[0] < 0 {
            if arg.Length == 0 || arg[0] != '-' {
                resultIndices.Indices[0] = i
            }
        }

        i = i + 1
    }

    return 0
}

func CliUpdateArgumentSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliUpdateArgumentSummaryCore(ref arguments, ref results)
}

func CliUpdateArgumentSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 3 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = 0
    resultIndices.Indices[2] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[2] = 1
        }

        if arg == "--dry-run" {
            resultIndices.Indices[1] = 1
        }

        if arg == "--help" || arg == "-h" {
            resultIndices.Indices[2] = 1
        }

        if resultIndices.Indices[0] < 0 {
            if arg.Length == 0 || arg[0] != '-' {
                resultIndices.Indices[0] = i
            }
        }

        i = i + 1
    }

    return 0
}

func CliNewArgumentSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliNewArgumentSummaryCore(ref arguments, ref results)
}

func CliNewArgumentSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 5 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = 0
    resultIndices.Indices[4] = 0

    templateIndex := -1
    typeIndex := -1
    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[4] = 1
        }

        if arg == "--systems" {
            resultIndices.Indices[3] = 1
        }

        if arg == "--help" || arg == "-h" {
            resultIndices.Indices[4] = 1
        }

        if arg == "--template" {
            if templateIndex < 0 && i + 1 < args.Args.Length {
                templateIndex = i + 1
            }
        } else if arg == "--type" {
            if typeIndex < 0 && i + 1 < args.Args.Length {
                typeIndex = i + 1
            }
        }

        i = i + 1
    }

    if templateIndex >= 0 {
        resultIndices.Indices[2] = templateIndex
    } else {
        resultIndices.Indices[2] = typeIndex
    }

    positionalCount := 0
    i = 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if arg == "--template" || arg == "--type" {
            if i + 1 < args.Args.Length {
                i = i + 2
            } else {
                i = i + 1
            }

            continue
        }

        if CliNewArgumentIsValueLessFlag(arg) {
            i = i + 1
            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            if positionalCount == 0 {
                resultIndices.Indices[0] = i
            } else if positionalCount == 1 {
                resultIndices.Indices[1] = i
            }

            positionalCount = positionalCount + 1
        }

        i = i + 1
    }

    return 0
}

func CliNewArgumentIsValueLessFlag(arg: string): bool {
    return arg == "--check"
        || arg == "--verify-no-changes"
        || arg == "--diff"
        || arg == "--stdin"
        || arg == "--verbose"
        || arg == "--systems"
}

func CliTreeOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliTreeOptionSummaryCore(ref arguments, ref results)
}

func CliTreeOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 4 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = 0
    resultIndices.Indices[3] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[3] = 1
        }

        kind := CliTreeOptionSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 3 {
            resultIndices.Indices[2] = 1
        } else if kind == 4 {
            resultIndices.Indices[3] = 1
        }

        i = i + 1
    }

    return 0
}

func CliTreeOptionSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--depth" {
        return 2
    }

    if arg == "--json" {
        return 3
    }

    if arg == "--help" || arg == "-h" {
        return 4
    }

    return 0
}

func CliCleanOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliCleanOptionSummaryCore(ref arguments, ref results)
}

func CliCleanOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 3 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = 0
    resultIndices.Indices[2] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[2] = 1
        }

        if arg == "--project" {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if arg == "--all" {
            resultIndices.Indices[1] = 1
        } else if arg == "--help" || arg == "-h" {
            resultIndices.Indices[2] = 1
        }

        i = i + 1
    }

    return 0
}

func CliPublishOptionsInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliPublishOptionsCore(ref arguments, ref results)
}

func CliPublishOptionsCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 8 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = -1
    resultIndices.Indices[4] = -1
    resultIndices.Indices[5] = 0
    resultIndices.Indices[6] = 0
    resultIndices.Indices[7] = -1

    configurationLongIndex := -1
    configurationShortIndex := -1
    outputLongIndex := -1
    outputShortIndex := -1
    runtimeLongIndex := -1
    runtimeShortIndex := -1

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        kind := CliPublishArgumentKind(arg)
        if kind >= 1 && kind <= 8 {
            if i + 1 >= args.Args.Length {
                resultIndices.Indices[7] = i
                return 1
            }

            value := args.Args[i + 1]
            if value.Length > 0 && value[0] == '-' {
                resultIndices.Indices[7] = i
                return 1
            }

            valueIndex := i + 1
            if kind == 1 {
                if resultIndices.Indices[0] < 0 {
                    resultIndices.Indices[0] = valueIndex
                }
            } else if kind == 2 {
                if resultIndices.Indices[1] < 0 {
                    resultIndices.Indices[1] = valueIndex
                }
            } else if kind == 3 {
                if configurationLongIndex < 0 {
                    configurationLongIndex = valueIndex
                }
            } else if kind == 4 {
                if configurationShortIndex < 0 {
                    configurationShortIndex = valueIndex
                }
            } else if kind == 5 {
                if outputLongIndex < 0 {
                    outputLongIndex = valueIndex
                }
            } else if kind == 6 {
                if outputShortIndex < 0 {
                    outputShortIndex = valueIndex
                }
            } else if kind == 7 {
                if runtimeLongIndex < 0 {
                    runtimeLongIndex = valueIndex
                }
            } else if kind == 8 {
                if runtimeShortIndex < 0 {
                    runtimeShortIndex = valueIndex
                }
            }

            i = i + 2
            continue
        }

        if kind == 9 {
            resultIndices.Indices[5] = 1
            i = i + 1
            continue
        }

        if kind == 10 {
            resultIndices.Indices[6] = 1
            i = i + 1
            continue
        }

        if kind == 11 {
            resultIndices.Indices[7] = i
            return 2
        }

        resultIndices.Indices[7] = i
        if arg.Length > 0 && arg[0] == '-' {
            return 3
        }

        return 4
    }

    if configurationLongIndex >= 0 {
        resultIndices.Indices[2] = configurationLongIndex
    } else {
        resultIndices.Indices[2] = configurationShortIndex
    }

    if outputLongIndex >= 0 {
        resultIndices.Indices[3] = outputLongIndex
    } else {
        resultIndices.Indices[3] = outputShortIndex
    }

    if runtimeLongIndex >= 0 {
        resultIndices.Indices[4] = runtimeLongIndex
    } else {
        resultIndices.Indices[4] = runtimeShortIndex
    }

    return 0
}

func CliPublishArgumentKind(arg: string): int {
    length := arg.Length
    if length == 2 {
        if arg[0] != '-' {
            return 0
        }

        shortName := arg[1]
        if shortName == 'c' {
            return 4
        }

        if shortName == 'o' {
            return 6
        }

        if shortName == 'r' {
            return 8
        }

        return 0
    }

    if length < 5 || arg[0] != '-' || arg[1] != '-' {
        return 0
    }

    first := arg[2]
    if length == 5 {
        if first == 'a' && arg[3] == 'o' && arg[4] == 't' {
            return 10
        }

        return 0
    }

    if length == 8 {
        if first == 'o'
            && arg[3] == 'u'
            && arg[4] == 't'
            && arg[5] == 'p'
            && arg[6] == 'u'
            && arg[7] == 't' {
            return 5
        }

        if first == 't'
            && arg[3] == 'a'
            && arg[4] == 'r'
            && arg[5] == 'g'
            && arg[6] == 'e'
            && arg[7] == 't' {
            return 11
        }

        return 0
    }

    if length == 9 {
        if first == 'p'
            && arg[3] == 'r'
            && arg[4] == 'o'
            && arg[5] == 'j'
            && arg[6] == 'e'
            && arg[7] == 'c'
            && arg[8] == 't' {
            return 1
        }

        if first == 'b'
            && arg[3] == 'a'
            && arg[4] == 'c'
            && arg[5] == 'k'
            && arg[6] == 'e'
            && arg[7] == 'n'
            && arg[8] == 'd' {
            return 2
        }

        if first == 'r'
            && arg[3] == 'u'
            && arg[4] == 'n'
            && arg[5] == 't'
            && arg[6] == 'i'
            && arg[7] == 'm'
            && arg[8] == 'e' {
            return 7
        }

        return 0
    }

    if length == 15 {
        if first == 'c'
            && arg[3] == 'o'
            && arg[4] == 'n'
            && arg[5] == 'f'
            && arg[6] == 'i'
            && arg[7] == 'g'
            && arg[8] == 'u'
            && arg[9] == 'r'
            && arg[10] == 'a'
            && arg[11] == 't'
            && arg[12] == 'i'
            && arg[13] == 'o'
            && arg[14] == 'n' {
            return 3
        }

        return 0
    }

    if length == 16 {
        if first == 's'
            && arg[3] == 'e'
            && arg[4] == 'l'
            && arg[5] == 'f'
            && arg[6] == '-'
            && arg[7] == 'c'
            && arg[8] == 'o'
            && arg[9] == 'n'
            && arg[10] == 't'
            && arg[11] == 'a'
            && arg[12] == 'i'
            && arg[13] == 'n'
            && arg[14] == 'e'
            && arg[15] == 'd' {
            return 9
        }

        return 0
    }

    if length == 17 {
        if first == 't'
            && arg[3] == 'a'
            && arg[4] == 'r'
            && arg[5] == 'g'
            && arg[6] == 'e'
            && arg[7] == 't'
            && arg[8] == '-'
            && arg[9] == 'p'
            && arg[10] == 'l'
            && arg[11] == 'a'
            && arg[12] == 't'
            && arg[13] == 'f'
            && arg[14] == 'o'
            && arg[15] == 'r'
            && arg[16] == 'm' {
            return 11
        }
    }

    return 0
}

func CliPackOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliPackOptionSummaryCore(ref arguments, ref results)
}

func CliPackOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 7 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = -1
    resultIndices.Indices[3] = -1
    resultIndices.Indices[4] = 0
    resultIndices.Indices[5] = 0
    resultIndices.Indices[6] = 0

    outputLongIndex := -1
    outputShortIndex := -1
    configurationLongIndex := -1
    configurationShortIndex := -1

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[6] = 1
        }

        kind := CliPackOptionSummaryKind(arg)
        if kind >= 1 && kind <= 6 {
            if i + 1 < args.Args.Length {
                valueIndex := i + 1
                if kind == 1 {
                    if resultIndices.Indices[0] < 0 {
                        resultIndices.Indices[0] = valueIndex
                    }
                } else if kind == 2 {
                    if outputLongIndex < 0 {
                        outputLongIndex = valueIndex
                    }
                } else if kind == 3 {
                    if outputShortIndex < 0 {
                        outputShortIndex = valueIndex
                    }
                } else if kind == 4 {
                    if resultIndices.Indices[2] < 0 {
                        resultIndices.Indices[2] = valueIndex
                    }
                } else if kind == 5 {
                    if configurationLongIndex < 0 {
                        configurationLongIndex = valueIndex
                    }
                } else if kind == 6 {
                    if configurationShortIndex < 0 {
                        configurationShortIndex = valueIndex
                    }
                }
            }
        } else if kind == 7 {
            resultIndices.Indices[4] = 1
        } else if kind == 8 {
            resultIndices.Indices[5] = 1
        } else if kind == 9 {
            resultIndices.Indices[6] = 1
        }

        i = i + 1
    }

    if outputLongIndex >= 0 {
        resultIndices.Indices[1] = outputLongIndex
    } else {
        resultIndices.Indices[1] = outputShortIndex
    }

    if configurationLongIndex >= 0 {
        resultIndices.Indices[3] = configurationLongIndex
    } else {
        resultIndices.Indices[3] = configurationShortIndex
    }

    return 0
}

func CliPackOptionSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--output" {
        return 2
    }

    if arg == "-o" {
        return 3
    }

    if arg == "--version" {
        return 4
    }

    if arg == "--configuration" {
        return 5
    }

    if arg == "-c" {
        return 6
    }

    if arg == "--include-symbols" {
        return 7
    }

    if arg == "--json" {
        return 8
    }

    if arg == "--help" || arg == "-h" {
        return 9
    }

    return 0
}

func CliLintOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliLintOptionSummaryCore(ref arguments, ref results)
}

func CliLintOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 4 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = 0
    resultIndices.Indices[2] = 0
    resultIndices.Indices[3] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[3] = 1
        }

        kind := CliLintOptionSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            resultIndices.Indices[1] = 1
        } else if kind == 3 {
            resultIndices.Indices[2] = 1
        } else if kind == 4 {
            resultIndices.Indices[3] = 1
        }

        i = i + 1
    }

    return 0
}

func CliLintOptionSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--text" {
        return 2
    }

    if arg == "--json" {
        return 3
    }

    if arg == "--help" || arg == "-h" {
        return 4
    }

    return 0
}

func CliLintFileArgIndicesInto(
    args: string[],
    projectValueIndices: int[],
    resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    projectValues := new CliProjectOptionValueIndexTable { Indices: projectValueIndices }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliLintFileArgIndicesCore(ref arguments, ref projectValues, ref results)
}

func CliLintFileArgIndicesCore(
    args: &CliArgumentTable,
    projectValueIndices: &CliProjectOptionValueIndexTable,
    resultIndices: &CliIndexResultTable): int {
    if projectValueIndices.Indices.Length < args.Args.Length || resultIndices.Indices.Length < args.Args.Length {
        return -1
    }

    projectValueCount := 0
    i := 0
    while i < args.Args.Length - 1 {
        if args.Args[i] == "--project" {
            projectValueIndices.Indices[projectValueCount] = i + 1
            projectValueCount = projectValueCount + 1
            i = i + 2
            continue
        }

        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if arg == "help" {
            i = i + 1
            continue
        }

        if arg.Length > 0 && arg[0] == '-' {
            i = i + 1
            continue
        }

        if CliLintIsProjectOptionValueCore(ref args, ref projectValueIndices, projectValueCount, arg) {
            i = i + 1
            continue
        }

        resultIndices.Indices[resultCount] = i
        resultCount = resultCount + 1
        i = i + 1
    }

    return resultCount
}

func CliLintIsProjectOptionValueCore(
    args: &CliArgumentTable,
    projectValueIndices: &CliProjectOptionValueIndexTable,
    projectValueCount: int,
    value: string): bool {
    i := 0
    while i < projectValueCount {
        valueIndex := projectValueIndices.Indices[i]
        if valueIndex >= 0 && valueIndex < args.Args.Length && args.Args[valueIndex] == value {
            return true
        }

        i = i + 1
    }

    return false
}

func CliTidyOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliTidyOptionSummaryCore(ref arguments, ref results)
}

func CliTidyOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 4 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = 0
    resultIndices.Indices[2] = 0
    resultIndices.Indices[3] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[3] = 1
        }

        kind := CliTidyOptionSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            resultIndices.Indices[1] = 1
        } else if kind == 3 {
            resultIndices.Indices[2] = 1
        } else if kind == 4 {
            resultIndices.Indices[3] = 1
        }

        i = i + 1
    }

    return 0
}

func CliTidyOptionSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--fix" {
        return 2
    }

    if arg == "--json" {
        return 3
    }

    if arg == "--help" || arg == "-h" {
        return 4
    }

    return 0
}

func CliDocOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliDocOptionSummaryCore(ref arguments, ref results)
}

func CliDocOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 5 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = 0
    resultIndices.Indices[3] = 0
    resultIndices.Indices[4] = 0

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[4] = 1
        }

        kind := CliDocOptionSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 3 {
            resultIndices.Indices[2] = 1
        } else if kind == 4 {
            resultIndices.Indices[3] = 1
        } else if kind == 5 {
            resultIndices.Indices[4] = 1
        }

        i = i + 1
    }

    return 0
}

func CliDocOptionSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--output" {
        return 2
    }

    if arg == "--json" {
        return 3
    }

    if arg == "--open" {
        return 4
    }

    if arg == "--help" || arg == "-h" {
        return 5
    }

    return 0
}

func CliTidyDependencyStatusRanksInto(
    packageNames: string[],
    importNamespaces: string[],
    resultStatusRanks: int[]): int {
    packages := new CliPackageNameTable { Names: packageNames }
    imports := new CliImportNamespaceTable { Namespaces: importNamespaces }
    results := new CliStatusRankResultTable { Ranks: resultStatusRanks }
    return CliTidyDependencyStatusRanksCore(ref packages, ref imports, ref results)
}

func CliTidyDependencyStatusRanksCore(
    packageNames: &CliPackageNameTable,
    importNamespaces: &CliImportNamespaceTable,
    resultStatusRanks: &CliStatusRankResultTable): int {
    if resultStatusRanks.Ranks.Length < packageNames.Names.Length {
        return -1
    }

    i := 0
    while i < packageNames.Names.Length {
        resultStatusRanks.Ranks[i] = CliTidyDependencyStatusRankCore(packageNames.Names[i], ref importNamespaces)
        i = i + 1
    }

    return packageNames.Names.Length
}

func CliTidyDependencyStatusRankCore(packageName: string, importNamespaces: &CliImportNamespaceTable): int {
    firstDot := packageName.IndexOf('.')
    if firstDot < 0 {
        return 3
    }

    i := 0
    while i < importNamespaces.Namespaces.Length {
        namespaceName := importNamespaces.Namespaces[i]
        if CliTidyNamespaceMatchesPrefix(namespaceName, packageName, firstDot) {
            return 2
        }

        i = i + 1
    }

    return 1
}

func CliTidyNamespaceMatchesPrefix(namespaceName: string, packageName: string, prefixLength: int): bool {
    if prefixLength <= 0 || namespaceName.Length < prefixLength || packageName.Length < prefixLength {
        return false
    }

    if namespaceName.Length > prefixLength && namespaceName[prefixLength] != '.' {
        return false
    }

    i := 0
    while i < prefixLength {
        if !CliTidyCharsEqualAsciiIgnoreCase(namespaceName[i], packageName[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CliTidyCharsEqualAsciiIgnoreCase(left: char, right: char): bool {
    leftCode := (int)left
    rightCode := (int)right

    if leftCode >= 65 && leftCode <= 90 {
        leftCode = leftCode + 32
    }

    if rightCode >= 65 && rightCode <= 90 {
        rightCode = rightCode + 32
    }

    return leftCode == rightCode
}

func CliTidyRemovalLineKeepFlagsInto(lines: string[], packageNames: string[], resultFlags: int[]): int {
    sourceLines := new CliLineTable { Lines: lines }
    packages := new CliPackageNameTable { Names: packageNames }
    results := new CliFlagResultTable { Flags: resultFlags }
    return CliTidyRemovalLineKeepFlagsCore(ref sourceLines, ref packages, ref results)
}

func CliTidyRemovalLineKeepFlagsCore(
    lines: &CliLineTable,
    packageNames: &CliPackageNameTable,
    resultFlags: &CliFlagResultTable): int {
    if resultFlags.Flags.Length < lines.Lines.Length {
        return -1
    }

    i := 0
    while i < lines.Lines.Length {
        resultFlags.Flags[i] = CliTidyRemovalLineKeepFlagCore(lines.Lines[i], ref packageNames)
        i = i + 1
    }

    return lines.Lines.Length
}

func CliTidyRemovalLineKeepFlagCore(line: string, packageNames: &CliPackageNameTable): int {
    start := 0
    while start < line.Length && CliTidyIsAsciiWhitespace(line[start]) {
        start = start + 1
    }

    if start + 2 > line.Length || line[start] != '-' || line[start + 1] != ' ' {
        return 1
    }

    if CliTidyRemovalLineStartsWithAnyPackageCore(line, start + 2, ref packageNames) {
        return 0
    }

    markerLimit := line.Length - 7
    markerStart := start
    while markerStart <= markerLimit {
        if CliTidyRemovalLineHasNugetMarkerAt(line, markerStart)
            && CliTidyRemovalLineStartsWithAnyPackageCore(line, markerStart + 7, ref packageNames) {
            return 0
        }

        markerStart = markerStart + 1
    }

    return 1
}

func CliTidyIsAsciiWhitespace(value: char): bool {
    code := (int)value
    return code == 32 || (code >= 9 && code <= 13)
}

func CliTidyRemovalLineStartsWithAnyPackageCore(
    line: string,
    packageStart: int,
    packageNames: &CliPackageNameTable): bool {
    i := 0
    while i < packageNames.Names.Length {
        if CliTidyRemovalLineStartsWithPackage(line, packageStart, packageNames.Names[i]) {
            return true
        }

        i = i + 1
    }

    return false
}

func CliTidyRemovalLineStartsWithPackage(line: string, packageStart: int, packageName: string): bool {
    if packageStart + packageName.Length > line.Length {
        return false
    }

    i := 0
    while i < packageName.Length {
        if !CliTidyCharsEqualAsciiIgnoreCase(line[packageStart + i], packageName[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CliTidyRemovalLineHasNugetMarkerAt(line: string, start: int): bool {
    if !CliTidyCharsEqualAsciiIgnoreCase(line[start], 'n')
        || !CliTidyCharsEqualAsciiIgnoreCase(line[start + 1], 'u')
        || !CliTidyCharsEqualAsciiIgnoreCase(line[start + 2], 'g')
        || !CliTidyCharsEqualAsciiIgnoreCase(line[start + 3], 'e')
        || !CliTidyCharsEqualAsciiIgnoreCase(line[start + 4], 't')
        || line[start + 5] != ':'
        || line[start + 6] != ' ' {
        return false
    }

    return true
}

func CliSymbolNameGlobFilterIndicesInto(
    names: string[],
    pattern: string,
    limit: int,
    resultIndices: int[]): int {
    symbolNames := new CliSymbolNameTable { Names: names }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliSymbolNameGlobFilterIndicesCore(ref symbolNames, pattern, limit, ref results)
}

func CliSymbolNameGlobFilterIndicesCore(
    names: &CliSymbolNameTable,
    pattern: string,
    limit: int,
    resultIndices: &CliIndexResultTable): int {
    if limit <= 0 || resultIndices.Indices.Length == 0 {
        return 0
    }

    maxCount := limit
    if maxCount > resultIndices.Indices.Length {
        maxCount = resultIndices.Indices.Length
    }

    matchCount := 0
    i := 0
    while i < names.Names.Length && matchCount < maxCount {
        name := names.Names[i]
        if CliSymbolNameGlobMatchesAsciiIgnoreCase(name, pattern) {
            resultIndices.Indices[matchCount] = i
            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
}

func CliSymbolNameSubstringFilterIndicesInto(
    names: string[],
    pattern: string,
    limit: int,
    resultIndices: int[]): int {
    symbolNames := new CliSymbolNameTable { Names: names }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliSymbolNameSubstringFilterIndicesCore(ref symbolNames, pattern, limit, ref results)
}

func CliSymbolNameSubstringFilterIndicesCore(
    names: &CliSymbolNameTable,
    pattern: string,
    limit: int,
    resultIndices: &CliIndexResultTable): int {
    if limit <= 0 || resultIndices.Indices.Length == 0 {
        return 0
    }

    maxCount := limit
    if maxCount > resultIndices.Indices.Length {
        maxCount = resultIndices.Indices.Length
    }

    matchCount := 0
    i := 0
    while i < names.Names.Length && matchCount < maxCount {
        name := names.Names[i]
        if CliSymbolNameContainsAsciiIgnoreCase(name, pattern) {
            resultIndices.Indices[matchCount] = i
            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
}

func CliSymbolNameContainsAsciiIgnoreCase(text: string, pattern: string): bool {
    return text.IndexOf(pattern, StringComparison.OrdinalIgnoreCase) >= 0
}

func CliSymbolNameGlobMatchesAsciiIgnoreCase(text: string, pattern: string): bool {
    if pattern.Length == 1 && pattern[0] == '*' {
        return true
    }

    if pattern.Length > 1
        && pattern[0] == '*'
        && !CliSymbolNamePatternHasWildcardFrom(pattern, 1) {
        return CliSymbolNameEndsWithAsciiIgnoreCase(text, pattern, 1, pattern.Length - 1)
    }

    if pattern.Length > 1
        && pattern[pattern.Length - 1] == '*'
        && !CliSymbolNamePatternHasWildcardBefore(pattern, pattern.Length - 1) {
        return CliSymbolNameStartsWithAsciiIgnoreCase(text, pattern, 0, pattern.Length - 1)
    }

    textIndex := 0
    patternIndex := 0
    starIndex := -1
    retryTextIndex := 0

    while textIndex < text.Length {
        if patternIndex < pattern.Length {
            patternChar := pattern[patternIndex]
            if patternChar == '*' {
                starIndex = patternIndex
                patternIndex = patternIndex + 1
                retryTextIndex = textIndex
                continue
            }

            if CliSymbolNameCharsEqualAsciiIgnoreCase(text[textIndex], patternChar) {
                textIndex = textIndex + 1
                patternIndex = patternIndex + 1
                continue
            }
        }

        if starIndex >= 0 {
            patternIndex = starIndex + 1
            retryTextIndex = retryTextIndex + 1
            textIndex = retryTextIndex
            continue
        }

        return false
    }

    while patternIndex < pattern.Length && pattern[patternIndex] == '*' {
        patternIndex = patternIndex + 1
    }

    return patternIndex == pattern.Length
}

func CliSymbolNamePatternHasWildcardFrom(pattern: string, start: int): bool {
    i := start
    while i < pattern.Length {
        if pattern[i] == '*' {
            return true
        }

        i = i + 1
    }

    return false
}

func CliSymbolNamePatternHasWildcardBefore(pattern: string, end: int): bool {
    i := 0
    while i < end {
        if pattern[i] == '*' {
            return true
        }

        i = i + 1
    }

    return false
}

func CliSymbolNameStartsWithAsciiIgnoreCase(
    text: string,
    pattern: string,
    patternStart: int,
    patternLength: int): bool {
    if patternLength > text.Length {
        return false
    }

    i := 0
    while i < patternLength {
        if !CliSymbolNameCharsEqualAsciiIgnoreCase(text[i], pattern[patternStart + i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CliSymbolNameEndsWithAsciiIgnoreCase(
    text: string,
    pattern: string,
    patternStart: int,
    patternLength: int): bool {
    if patternLength > text.Length {
        return false
    }

    textStart := text.Length - patternLength
    i := 0
    while i < patternLength {
        if !CliSymbolNameCharsEqualAsciiIgnoreCase(text[textStart + i], pattern[patternStart + i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CliSymbolNameCharsEqualAsciiIgnoreCase(left: char, right: char): bool {
    leftCode := (int)left
    rightCode := (int)right

    if leftCode >= 65 && leftCode <= 90 {
        leftCode = leftCode + 32
    }

    if rightCode >= 65 && rightCode <= 90 {
        rightCode = rightCode + 32
    }

    return leftCode == rightCode
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

func CliExportCSharpFirstOperandIndexInto(
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
    return CliExportCSharpFirstOperandIndexCore(ref arguments, ref kinds, ref links, ref results)
}

func CliExportCSharpFirstOperandIndexCore(
    args: &CliArgumentTable,
    kindIds: &CliBuildArgumentKindTable,
    links: &CliBuildArgumentLinkTable,
    resultIndices: &CliIndexResultTable): int {
    if args.Args.Length == 0 {
        return -1
    }

    firstArg := args.Args[0]
    if firstArg.Length == 0 || firstArg[0] != '-' {
        return 0
    }

    if kindIds.Kinds.Length < args.Args.Length
        || links.NextIndices.Length < args.Args.Length
        || links.PreviousIndices.Length < args.Args.Length
        || links.NextOptionIndices.Length < args.Args.Length
        || (args.Args.Length > 0 && resultIndices.Indices.Length < 1) {
        return -2
    }

    first := -1
    last := -1
    outputHead := -1
    outputTail := -1
    shortOutputHead := -1
    shortOutputTail := -1
    projectHead := -1
    projectTail := -1
    count := 0
    i := 0
    while i < args.Args.Length {
        kind := CliBuildArgumentKind(args.Args[i])
        kindIds.Kinds[i] = kind
        links.NextIndices[i] = -1
        links.PreviousIndices[i] = -1
        links.NextOptionIndices[i] = -1

        if last >= 0 {
            links.NextIndices[last] = i
            links.PreviousIndices[i] = last
        } else {
            first = i
        }

        last = i
        count = count + 1

        if kind == 1 {
            if outputTail >= 0 {
                links.NextOptionIndices[outputTail] = i
            } else {
                outputHead = i
            }

            outputTail = i
        } else if kind == 2 {
            if shortOutputTail >= 0 {
                links.NextOptionIndices[shortOutputTail] = i
            } else {
                shortOutputHead = i
            }

            shortOutputTail = i
        } else if kind == 4 {
            if projectTail >= 0 {
                links.NextOptionIndices[projectTail] = i
            } else {
                projectHead = i
            }

            projectTail = i
        }

        i = i + 1
    }

    resultIndices.Indices[0] = first
    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, outputHead, 1, ref resultIndices, count)
    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, shortOutputHead, 2, ref resultIndices, count)
    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, projectHead, 4, ref resultIndices, count)

    sourceIndex := resultIndices.Indices[0]
    while sourceIndex >= 0 {
        arg := args.Args[sourceIndex]
        if arg.Length == 0 || arg[0] != '-' {
            return sourceIndex
        }

        sourceIndex = links.NextIndices[sourceIndex]
    }

    return -1
}

func CliExportCSharpOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliExportCSharpOptionSummaryCore(ref arguments, ref results)
}

func CliExportCSharpOptionSummaryCore(args: &CliArgumentTable, resultIndices: &CliIndexResultTable): int {
    if resultIndices.Indices.Length < 3 {
        return -1
    }

    resultIndices.Indices[0] = -1
    resultIndices.Indices[1] = -1
    resultIndices.Indices[2] = 0

    shortOutputIndex := -1

    i := 0
    while i < args.Args.Length {
        arg := args.Args[i]
        if i == 0 && arg == "help" {
            resultIndices.Indices[2] = 1
        }

        kind := CliExportCSharpOptionSummaryKind(arg)
        if kind == 1 {
            if resultIndices.Indices[0] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[0] = i + 1
            }
        } else if kind == 2 {
            if resultIndices.Indices[1] < 0 && i + 1 < args.Args.Length {
                resultIndices.Indices[1] = i + 1
            }
        } else if kind == 3 {
            if shortOutputIndex < 0 && i + 1 < args.Args.Length {
                shortOutputIndex = i + 1
            }
        } else if kind == 4 {
            resultIndices.Indices[2] = 1
        }

        i = i + 1
    }

    if resultIndices.Indices[1] < 0 {
        resultIndices.Indices[1] = shortOutputIndex
    }

    return 0
}

func CliExportCSharpOptionSummaryKind(arg: string): int {
    if arg == "--project" {
        return 1
    }

    if arg == "--output" {
        return 2
    }

    if arg == "-o" {
        return 3
    }

    if arg == "--help" || arg == "-h" {
        return 4
    }

    return 0
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

func CliBuildOperandSummaryCore(
    args: &CliArgumentTable,
    kindIds: &CliBuildArgumentKindTable,
    links: &CliBuildArgumentLinkTable,
    resultIndices: &CliIndexResultTable): int {
    if kindIds.Kinds.Length < args.Args.Length
        || links.NextIndices.Length < args.Args.Length
        || links.PreviousIndices.Length < args.Args.Length
        || links.NextOptionIndices.Length < args.Args.Length
        || (args.Args.Length > 0 && resultIndices.Indices.Length < 1) {
        return -1
    }

    first := -1
    last := -1
    count := 0
    outputHead := -1
    outputTail := -1
    shortOutputHead := -1
    shortOutputTail := -1
    backendHead := -1
    backendTail := -1
    projectHead := -1
    projectTail := -1
    i := 0
    while i < args.Args.Length {
        kind := CliBuildArgumentKind(args.Args[i])
        kindIds.Kinds[i] = kind
        links.NextIndices[i] = -1
        links.PreviousIndices[i] = -1
        links.NextOptionIndices[i] = -1

        if kind == 5 {
            kindIds.Kinds[i] = -1
            i = i + 1
            continue
        }

        if last >= 0 {
            links.NextIndices[last] = i
            links.PreviousIndices[i] = last
        } else {
            first = i
        }

        last = i
        count = count + 1

        if kind == 1 {
            if outputTail >= 0 {
                links.NextOptionIndices[outputTail] = i
            } else {
                outputHead = i
            }

            outputTail = i
        } else if kind == 2 {
            if shortOutputTail >= 0 {
                links.NextOptionIndices[shortOutputTail] = i
            } else {
                shortOutputHead = i
            }

            shortOutputTail = i
        } else if kind == 3 {
            if backendTail >= 0 {
                links.NextOptionIndices[backendTail] = i
            } else {
                backendHead = i
            }

            backendTail = i
        } else if kind == 4 {
            if projectTail >= 0 {
                links.NextOptionIndices[projectTail] = i
            } else {
                projectHead = i
            }

            projectTail = i
        }

        i = i + 1
    }

    if resultIndices.Indices.Length > 0 {
        resultIndices.Indices[0] = first
    }

    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, outputHead, 1, ref resultIndices, count)
    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, shortOutputHead, 2, ref resultIndices, count)
    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, backendHead, 3, ref resultIndices, count)
    count = CliBuildRemoveOptionKindPairsCore(ref kindIds, ref links, projectHead, 4, ref resultIndices, count)
    return count
}

func CliFixSafetyFilterIndicesInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    ranks := new CliFixSafetyRankTable { Ranks: safetyRanks }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliFixSafetyFilterIndicesCore(ref ranks, includeReviewNeeded, ref results)
}

func CliFixSafetyFilterIndicesCore(
    safetyRanks: &CliFixSafetyRankTable,
    includeReviewNeeded: int,
    resultIndices: &CliIndexResultTable): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    matchCount := 0
    length := safetyRanks.Ranks.Length
    i := 0

    if resultIndices.Indices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            rank := safetyRanks.Ranks[i]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = i
                matchCount = matchCount + 1
            }

            next := i + 1
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 2
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 3
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 4
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 5
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 6
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 7
            rank = safetyRanks.Ranks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            i = i + 8
        }

        while i < length {
            rank := safetyRanks.Ranks[i]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices.Indices[matchCount] = i
                matchCount = matchCount + 1
            }

            i = i + 1
        }

        return matchCount
    }

    unrolledLimit := length - 4
    while i <= unrolledLimit {
        rank := safetyRanks.Ranks[i]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Indices.Length {
                resultIndices.Indices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        next := i + 1
        rank = safetyRanks.Ranks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Indices.Length {
                resultIndices.Indices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 2
        rank = safetyRanks.Ranks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Indices.Length {
                resultIndices.Indices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 3
        rank = safetyRanks.Ranks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Indices.Length {
                resultIndices.Indices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        i = i + 4
    }

    while i < length {
        rank := safetyRanks.Ranks[i]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Indices.Length {
                resultIndices.Indices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
}

func CliFixSkippedIndicesInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    ranks := new CliFixSafetyRankTable { Ranks: safetyRanks }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliFixSkippedIndicesCore(ref ranks, includeReviewNeeded, ref results)
}

func CliFixSkippedIndicesCore(
    safetyRanks: &CliFixSafetyRankTable,
    includeReviewNeeded: int,
    resultIndices: &CliIndexResultTable): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    skippedCount := 0
    length := safetyRanks.Ranks.Length
    i := 0
    while i < length {
        rank := safetyRanks.Ranks[i]
        if rank == 0 || rank > maxAppliedRank {
            if skippedCount < resultIndices.Indices.Length {
                resultIndices.Indices[skippedCount] = i
            }

            skippedCount = skippedCount + 1
        }

        i = i + 1
    }

    return skippedCount
}

func CliFixAppliedFileGroupsInto(
    fileRanks: int[],
    uniqueFileRankCount: int,
    countsByRank: int[],
    offsetsByRank: int[],
    writeOffsetsByRank: int[],
    resultRanks: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    fileRankTable := new CliFixFileRankTable { Ranks: fileRanks }
    buckets := new CliFixRankBucketTable {
        CountsByRank: countsByRank,
        OffsetsByRank: offsetsByRank,
        WriteOffsetsByRank: writeOffsetsByRank
    }
    results := new CliFixAppliedFileGroupResultTable {
        Ranks: resultRanks,
        Starts: resultStarts,
        Counts: resultCounts,
        Indices: resultIndices
    }
    return CliFixAppliedFileGroupsCore(ref fileRankTable, uniqueFileRankCount, ref buckets, ref results)
}

func CliFixAppliedFileGroupsCore(
    fileRankTable: &CliFixFileRankTable,
    uniqueFileRankCount: int,
    buckets: &CliFixRankBucketTable,
    results: &CliFixAppliedFileGroupResultTable): int {
    if uniqueFileRankCount < 0 {
        return -1
    }

    if fileRankTable.Ranks.Length == 0 {
        return 0
    }

    if uniqueFileRankCount == 0 {
        return -1
    }

    rankCapacity := uniqueFileRankCount + 1
    if buckets.CountsByRank.Length < rankCapacity
        || buckets.OffsetsByRank.Length < rankCapacity
        || buckets.WriteOffsetsByRank.Length < rankCapacity
        || results.Ranks.Length < uniqueFileRankCount
        || results.Starts.Length < uniqueFileRankCount
        || results.Counts.Length < uniqueFileRankCount
        || results.Indices.Length < fileRankTable.Ranks.Length {
        return -1
    }

    rank := 0
    while rank < rankCapacity {
        buckets.CountsByRank[rank] = 0
        buckets.OffsetsByRank[rank] = 0
        buckets.WriteOffsetsByRank[rank] = 0
        rank = rank + 1
    }

    i := 0
    while i < fileRankTable.Ranks.Length {
        fileRank := fileRankTable.Ranks[i]
        if fileRank <= 0 || fileRank > uniqueFileRankCount {
            return -1
        }

        buckets.CountsByRank[fileRank] = buckets.CountsByRank[fileRank] + 1
        i = i + 1
    }

    offset := 0
    rank = 1
    while rank <= uniqueFileRankCount {
        groupIndex := rank - 1
        count := buckets.CountsByRank[rank]
        results.Ranks[groupIndex] = rank
        results.Starts[groupIndex] = offset
        results.Counts[groupIndex] = count
        buckets.OffsetsByRank[rank] = offset
        buckets.WriteOffsetsByRank[rank] = offset
        offset = offset + count
        rank = rank + 1
    }

    if offset > results.Indices.Length {
        return -1
    }

    i = 0
    while i < fileRankTable.Ranks.Length {
        fileRank := fileRankTable.Ranks[i]
        writeIndex := buckets.WriteOffsetsByRank[fileRank]
        if writeIndex < 0 || writeIndex >= results.Indices.Length {
            return -1
        }

        results.Indices[writeIndex] = i
        buckets.WriteOffsetsByRank[fileRank] = writeIndex + 1
        i = i + 1
    }

    return uniqueFileRankCount
}

func CliUnifiedDiffHunkRangesInto(
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
    lines := new CliUnifiedDiffLineTable {
        Kinds: kindIds,
        OldLines: oldLines,
        NewLines: newLines
    }
    results := new CliUnifiedDiffHunkResultTable {
        Starts: resultStarts,
        Lengths: resultLengths,
        OldStarts: resultOldStarts,
        OldCounts: resultOldCounts,
        NewStarts: resultNewStarts,
        NewCounts: resultNewCounts
    }
    return CliUnifiedDiffHunkRangesCore(ref lines, contextLines, ref results)
}

func CliUnifiedDiffHunkRangesCore(
    lines: &CliUnifiedDiffLineTable,
    contextLines: int,
    results: &CliUnifiedDiffHunkResultTable): int {
    lineCount := lines.Kinds.Length
    if contextLines < 0 {
        return -1
    }

    if lines.OldLines.Length < lineCount
        || lines.NewLines.Length < lineCount
        || results.Starts.Length < lineCount
        || results.Lengths.Length < lineCount
        || results.OldStarts.Length < lineCount
        || results.OldCounts.Length < lineCount
        || results.NewStarts.Length < lineCount
        || results.NewCounts.Length < lineCount {
        return -1
    }

    rangeStart := -1
    rangeEnd := -1
    hunkCount := 0
    i := 0
    while i < lineCount {
        if lines.Kinds[i] != 0 {
            nextStart := i - contextLines
            if nextStart < 0 {
                nextStart = 0
            }

            nextEnd := i + contextLines
            if nextEnd >= lineCount {
                nextEnd = lineCount - 1
            }

            if rangeStart < 0 {
                rangeStart = nextStart
                rangeEnd = nextEnd
            } else if nextStart <= rangeEnd + 1 {
                if nextEnd > rangeEnd {
                    rangeEnd = nextEnd
                }
            } else {
                if !CliUnifiedDiffWriteHunkRangeCore(ref lines, rangeStart, rangeEnd, hunkCount, ref results) {
                    return -1
                }

                hunkCount = hunkCount + 1
                rangeStart = nextStart
                rangeEnd = nextEnd
            }
        }

        i = i + 1
    }

    if rangeStart >= 0 {
        if !CliUnifiedDiffWriteHunkRangeCore(ref lines, rangeStart, rangeEnd, hunkCount, ref results) {
            return -1
        }

        hunkCount = hunkCount + 1
    }

    return hunkCount
}

func CliUnifiedDiffWriteHunkRangeCore(
    lines: &CliUnifiedDiffLineTable,
    rangeStart: int,
    rangeEnd: int,
    hunkIndex: int,
    results: &CliUnifiedDiffHunkResultTable): bool {
    if hunkIndex < 0
        || hunkIndex >= results.Starts.Length
        || hunkIndex >= results.Lengths.Length
        || hunkIndex >= results.OldStarts.Length
        || hunkIndex >= results.OldCounts.Length
        || hunkIndex >= results.NewStarts.Length
        || hunkIndex >= results.NewCounts.Length {
        return false
    }

    oldStart := 0
    newStart := 0
    oldCount := 0
    newCount := 0

    i := rangeStart
    while i <= rangeEnd {
        kind := lines.Kinds[i]
        if oldStart == 0 && lines.OldLines[i] > 0 {
            oldStart = lines.OldLines[i]
        }

        if newStart == 0 && lines.NewLines[i] > 0 {
            newStart = lines.NewLines[i]
        }

        if kind != 1 {
            oldCount = oldCount + 1
        }

        if kind != 2 {
            newCount = newCount + 1
        }

        i = i + 1
    }

    if oldStart == 0 {
        oldStart = 1
    }

    if newStart == 0 {
        newStart = 1
    }

    results.Starts[hunkIndex] = rangeStart
    results.Lengths[hunkIndex] = rangeEnd - rangeStart + 1
    results.OldStarts[hunkIndex] = oldStart
    results.OldCounts[hunkIndex] = oldCount
    results.NewStarts[hunkIndex] = newStart
    results.NewCounts[hunkIndex] = newCount
    return true
}

func CliCleanArtifactDirectoryIndicesInto(
    kindRanks: int[],
    nodeModuleFlags: int[],
    pathRanks: int[],
    pathLengths: int[],
    seenPathRanks: int[],
    lengthCounts: int[],
    lengthOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    inputs := new CliCleanArtifactInputTable {
        KindRanks: kindRanks,
        NodeModuleFlags: nodeModuleFlags,
        PathRanks: pathRanks,
        PathLengths: pathLengths
    }
    scratch := new CliCleanArtifactScratchTable {
        SeenPathRanks: seenPathRanks,
        LengthCounts: lengthCounts,
        LengthOffsets: lengthOffsets,
        TempIndices: tempIndices
    }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliCleanArtifactDirectoryIndicesCore(ref inputs, ref scratch, ref results)
}

func CliCleanArtifactDirectoryIndicesCore(
    inputs: &CliCleanArtifactInputTable,
    scratch: &CliCleanArtifactScratchTable,
    results: &CliIndexResultTable): int {
    length := inputs.KindRanks.Length
    if inputs.NodeModuleFlags.Length < length
        || inputs.PathRanks.Length < length
        || inputs.PathLengths.Length < length
        || scratch.TempIndices.Length < length
        || results.Indices.Length < length {
        return -1
    }

    i := 0
    while i < scratch.SeenPathRanks.Length {
        scratch.SeenPathRanks[i] = 0
        i = i + 1
    }

    i = 0
    while i < scratch.LengthCounts.Length {
        scratch.LengthCounts[i] = 0
        scratch.LengthOffsets[i] = 0
        i = i + 1
    }

    selectedCount := 0
    i = 0
    while i < length {
        kindRank := inputs.KindRanks[i]
        if kindRank > 0 && inputs.NodeModuleFlags[i] == 0 {
            pathRank := inputs.PathRanks[i]
            if pathRank <= 0 || pathRank >= scratch.SeenPathRanks.Length {
                return -1
            }

            if scratch.SeenPathRanks[pathRank] == 0 {
                pathLength := inputs.PathLengths[i]
                if pathLength < 0 || pathLength >= scratch.LengthCounts.Length {
                    return -1
                }

                scratch.SeenPathRanks[pathRank] = 1
                scratch.TempIndices[selectedCount] = i
                scratch.LengthCounts[pathLength] = scratch.LengthCounts[pathLength] + 1
                selectedCount = selectedCount + 1
            }
        }

        i = i + 1
    }

    running := 0
    lengthRank := scratch.LengthCounts.Length - 1
    while lengthRank >= 0 {
        count := scratch.LengthCounts[lengthRank]
        scratch.LengthOffsets[lengthRank] = running
        running = running + count
        lengthRank = lengthRank - 1
    }

    i = 0
    while i < selectedCount {
        sourceIndex := scratch.TempIndices[i]
        pathLength := inputs.PathLengths[sourceIndex]
        outputIndex := scratch.LengthOffsets[pathLength]
        results.Indices[outputIndex] = sourceIndex
        scratch.LengthOffsets[pathLength] = outputIndex + 1
        i = i + 1
    }

    return selectedCount
}

func CliUpdateAllNuGetDependencyIndicesInto(
    nugetFlags: int[],
    resultIndices: int[]): int {
    flags := new CliFlagTable { Flags: nugetFlags }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliUpdateAllNuGetDependencyIndicesCore(ref flags, ref results)
}

func CliUpdateAllNuGetDependencyIndicesCore(
    flagTable: &CliFlagTable,
    results: &CliIndexResultTable): int {
    length := flagTable.Flags.Length
    resultCount := 0
    i := 0
    if results.Indices.Length >= length {
        unrolledLimit := length - 16
        while i <= unrolledLimit {
            if flagTable.Flags[i] != 0 {
                results.Indices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 8
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 9
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 10
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 11
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 12
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 13
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 14
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 15
            if flagTable.Flags[next] != 0 {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 16
        }

        while i < length {
            if flagTable.Flags[i] != 0 {
                results.Indices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if flagTable.Flags[i] != 0 {
            if resultCount < results.Indices.Length {
                results.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliUpdateTargetNuGetDependencyIndicesInto(
    nameRanks: int[],
    targetNameRank: int,
    resultIndices: int[]): int {
    ranks := new CliRankTable { Ranks: nameRanks }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliUpdateTargetNuGetDependencyIndicesCore(ref ranks, targetNameRank, ref results)
}

func CliUpdateTargetNuGetDependencyIndicesCore(
    nameRankTable: &CliRankTable,
    targetNameRank: int,
    results: &CliIndexResultTable): int {
    if targetNameRank <= 0 {
        return 0
    }

    length := nameRankTable.Ranks.Length
    resultCount := 0
    i := 0
    if results.Indices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if nameRankTable.Ranks[i] == targetNameRank {
                results.Indices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if nameRankTable.Ranks[next] == targetNameRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 8
        }

        while i < length {
            if nameRankTable.Ranks[i] == targetNameRank {
                results.Indices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if nameRankTable.Ranks[i] == targetNameRank {
            if resultCount < results.Indices.Length {
                results.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliReferenceTypeFilterIndicesInto(
    typeRanks: int[],
    targetTypeRank: int,
    resultIndices: int[]): int {
    ranks := new CliRankTable { Ranks: typeRanks }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliReferenceTypeFilterIndicesCore(ref ranks, targetTypeRank, ref results)
}

func CliReferenceTypeFilterIndicesCore(
    typeRankTable: &CliRankTable,
    targetTypeRank: int,
    results: &CliIndexResultTable): int {
    if targetTypeRank <= 0 {
        return 0
    }

    length := typeRankTable.Ranks.Length
    resultCount := 0
    i := 0
    if results.Indices.Length >= length {
        unrolledLimit := length - 16
        while i <= unrolledLimit {
            if typeRankTable.Ranks[i] == targetTypeRank {
                results.Indices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 8
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 9
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 10
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 11
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 12
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 13
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 14
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 15
            if typeRankTable.Ranks[next] == targetTypeRank {
                results.Indices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 16
        }

        while i < length {
            if typeRankTable.Ranks[i] == targetTypeRank {
                results.Indices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if typeRankTable.Ranks[i] == targetTypeRank {
            if resultCount < results.Indices.Length {
                results.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliReferenceResolutionBestScoreIndex(scores: int[], count: int): int {
    scoreTable := new CliRankTable { Ranks: scores }
    return CliReferenceResolutionBestScoreIndexCore(ref scoreTable, count)
}

func CliReferenceResolutionBestScoreIndexCore(scoresTable: &CliRankTable, count: int): int {
    scores := scoresTable.Ranks
    if count <= 0 {
        return -1
    }

    if count > scores.Length {
        return -2
    }

    bestIndex := -1
    bestScore := -1
    i := 0
    while i < count {
        score := scores[i]
        if score >= 0 && score > bestScore {
            bestScore = score
            bestIndex = i
        }

        i = i + 1
    }

    return bestIndex
}

func CliStableDistinctRankIndicesInto(
    ranks: int[],
    uniqueRankCount: int,
    seenRanks: int[],
    resultIndices: int[]): int {
    rankTable := new CliRankTable { Ranks: ranks }
    seenRankTable := new CliSeenRankTable { Ranks: seenRanks }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliStableDistinctRankIndicesCore(ref rankTable, uniqueRankCount, ref seenRankTable, ref results)
}

func CliStableDistinctRankIndicesCore(
    rankTable: &CliRankTable,
    uniqueRankCount: int,
    seenRankTable: &CliSeenRankTable,
    results: &CliIndexResultTable): int {
    clearCount := uniqueRankCount + 1
    if clearCount > seenRankTable.Ranks.Length {
        clearCount = seenRankTable.Ranks.Length
    }

    i := 0
    while i < clearCount {
        seenRankTable.Ranks[i] = 0
        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < rankTable.Ranks.Length {
        rank := rankTable.Ranks[i]
        if rank > 0 && rank <= uniqueRankCount && rank < seenRankTable.Ranks.Length {
            if seenRankTable.Ranks[rank] == 0 {
                seenRankTable.Ranks[rank] = 1
                if resultCount < results.Indices.Length {
                    results.Indices[resultCount] = i
                }

                resultCount = resultCount + 1
            }
        }

        i = i + 1
    }

    return resultCount
}

func CliTidyDependencyStatusSummaryInto(statusRanks: int[], resultCounts: int[]): int {
    ranks := new CliRankTable { Ranks: statusRanks }
    counts := new CliCountResultTable { Counts: resultCounts }
    return CliTidyDependencyStatusSummaryCore(ref ranks, ref counts)
}

func CliTidyDependencyStatusSummaryCore(
    statusRankTable: &CliRankTable,
    counts: &CliCountResultTable): int {
    if counts.Counts.Length < 2 {
        return -1
    }

    possiblyUnused := 0
    unknown := 0
    i := 0
    length := statusRankTable.Ranks.Length
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        rank := statusRankTable.Ranks[i]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next := i + 1
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 2
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 3
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 4
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 5
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 6
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 7
        rank = statusRankTable.Ranks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        i = i + 8
    }

    while i < length {
        rank := statusRankTable.Ranks[i]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        i = i + 1
    }

    counts.Counts[0] = possiblyUnused
    counts.Counts[1] = unknown
    return length
}

func CliTestOutcomeSummaryInto(outcomeRanks: int[], count: int, resultCounts: int[]): int {
    ranks := new CliRankTable { Ranks: outcomeRanks }
    counts := new CliCountResultTable { Counts: resultCounts }
    return CliTestOutcomeSummaryCore(ref ranks, count, ref counts)
}

func CliTestOptionSummaryInto(args: string[], resultIndices: int[]): int {
    arguments := new CliArgumentTable { Args: args }
    results := new CliIndexResultTable { Indices: resultIndices }
    return CliTestOptionSummaryCore(ref arguments, ref results)
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

func CliTestOutcomeSummaryCore(
    outcomeRankTable: &CliRankTable,
    count: int,
    counts: &CliCountResultTable): int {
    if counts.Counts.Length < 4 {
        return -1
    }

    if count > outcomeRankTable.Ranks.Length {
        count = outcomeRankTable.Ranks.Length
    }

    if count < 0 {
        count = 0
    }

    passed := 0
    failed := 0
    skipped := 0
    nonOk := 0
    i := 0
    unrolledLimit := count - 8
    while i <= unrolledLimit {
        rank := outcomeRankTable.Ranks[i]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next := i + 1
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next = i + 2
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next = i + 3
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next = i + 4
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next = i + 5
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next = i + 6
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        next = i + 7
        rank = outcomeRankTable.Ranks[next]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        i = i + 8
    }

    while i < count {
        rank := outcomeRankTable.Ranks[i]
        if rank == 1 {
            passed = passed + 1
        } else if rank == 2 {
            failed = failed + 1
            nonOk = nonOk + 1
        } else if rank == 3 {
            skipped = skipped + 1
        } else {
            nonOk = nonOk + 1
        }

        i = i + 1
    }

    counts.Counts[0] = passed
    counts.Counts[1] = failed
    counts.Counts[2] = skipped
    counts.Counts[3] = nonOk
    return count
}

func CliShouldFormatDiscoveredPath(relativePath: string): int {
    previousWasTestRoot := false
    segmentStart := 0
    i := 0

    while i <= relativePath.Length {
        atEnd := i == relativePath.Length
        isSeparator := false
        if !atEnd {
            ch := relativePath[i]
            isSeparator = ch == '/' || ch == '\\'
        }

        if atEnd || isSeparator {
            if i > segmentStart {
                if CliFormatPathSegmentIsExcluded(relativePath, segmentStart, i) {
                    return 0
                }

                if previousWasTestRoot && CliFormatPathSegmentEquals(relativePath, segmentStart, i, "fixtures") {
                    return 0
                }

                previousWasTestRoot =
                    CliFormatPathSegmentEquals(relativePath, segmentStart, i, "test")
                    || CliFormatPathSegmentEquals(relativePath, segmentStart, i, "tests")
            }

            segmentStart = i + 1
        }

        i = i + 1
    }

    return 1
}

func CliFormatPathSegmentIsExcluded(text: string, start: int, end: int): bool {
    length := end - start
    if length == 3 {
        return CliFormatPathSegmentEquals(text, start, end, ".hg")
            || CliFormatPathSegmentEquals(text, start, end, "bin")
            || CliFormatPathSegmentEquals(text, start, end, "obj")
    }

    if length == 4 {
        return CliFormatPathSegmentEquals(text, start, end, ".git")
            || CliFormatPathSegmentEquals(text, start, end, ".svn")
            || CliFormatPathSegmentEquals(text, start, end, ".nlc")
    }

    if length == 7 {
        return CliFormatPathSegmentEquals(text, start, end, ".hermes")
    }

    if length == 10 {
        return CliFormatPathSegmentEquals(text, start, end, ".worktrees")
    }

    if length == 12 {
        return CliFormatPathSegmentEquals(text, start, end, "node_modules")
    }

    return false
}

func CliFormatPathSegmentEquals(text: string, start: int, end: int, value: string): bool {
    length := end - start
    if length != value.Length {
        return false
    }

    i := 0
    while i < value.Length {
        if !CliFormatPathCharsEqualAsciiIgnoreCase(text[start + i], value[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func CliFormatPathCharsEqualAsciiIgnoreCase(left: char, right: char): bool {
    leftCode := (int)left
    rightCode := (int)right

    if left >= 'A' && left <= 'Z' {
        leftCode = leftCode + 32
    }

    if right >= 'A' && right <= 'Z' {
        rightCode = rightCode + 32
    }

    return leftCode == rightCode
}

func CliArgumentIsOptionWithValueCore(arg: string, optionsWithValues: &CliOptionValueTable): bool {
    i := 0
    while i < optionsWithValues.Options.Length {
        if arg == optionsWithValues.Options[i] {
            return true
        }

        i = i + 1
    }

    return false
}

func CliBuildRemoveOptionKindPairsCore(
    kindIds: &CliBuildArgumentKindTable,
    links: &CliBuildArgumentLinkTable,
    optionHead: int,
    optionKind: int,
    resultIndices: &CliIndexResultTable,
    count: int): int {
    sourceIndex := optionHead
    while sourceIndex >= 0 {
        nextOptionIndex := links.NextOptionIndices[sourceIndex]
        if kindIds.Kinds[sourceIndex] == optionKind {
            valueIndex := links.NextIndices[sourceIndex]
            if valueIndex >= 0 {
                previousIndex := links.PreviousIndices[sourceIndex]
                afterIndex := links.NextIndices[valueIndex]
                if previousIndex >= 0 {
                    links.NextIndices[previousIndex] = afterIndex
                } else {
                    resultIndices.Indices[0] = afterIndex
                }

                if afterIndex >= 0 {
                    links.PreviousIndices[afterIndex] = previousIndex
                }

                kindIds.Kinds[sourceIndex] = -1
                kindIds.Kinds[valueIndex] = -1
                count = count - 2
            }
        }

        sourceIndex = nextOptionIndex
    }

    return count
}

func CliBuildArgumentKind(arg: string): int {
    length := arg.Length
    if length < 2 || arg[0] != '-' {
        return 0
    }

    if length == 2 {
        if arg[1] == 'o' {
            return 2
        }

        return 0
    }

    if arg[1] != '-' {
        return 0
    }

    if length == 5 {
        if arg[2] == 'a' && arg[3] == 'o' && arg[4] == 't' {
            return 5
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
            return 5
        }

        if marker == 'v'
            && arg[3] == 'e'
            && arg[4] == 'r'
            && arg[5] == 'b'
            && arg[6] == 'o'
            && arg[7] == 's'
            && arg[8] == 'e' {
            return 5
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
        return 5
    }

    return 0
}

func CliArgumentIsValueLessFlag(arg: string): bool {
    if arg == "--check" {
        return true
    }

    if arg == "--verify-no-changes" {
        return true
    }

    if arg == "--diff" {
        return true
    }

    if arg == "--stdin" {
        return true
    }

    if arg == "--verbose" {
        return true
    }

    return false
}

func CliPositionalArgIndicesInto(
    args: string[],
    optionsWithValues: string[],
    resultIndices: int[]): int {
    resultCount := 0
    i := 0
    while i < args.Length {
        arg := args[i]
        if CliArgumentIsOptionWithValue(arg, optionsWithValues) {
            i = i + 2
            continue
        }

        if CliArgumentIsValueLessFlag(arg) {
            i = i + 1
            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliFirstPositionalArgIndex(args: string[], optionsWithValues: string[]): int {
    i := 0
    while i < args.Length {
        arg := args[i]
        if CliArgumentIsOptionWithValue(arg, optionsWithValues) {
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
    i := 0
    while i < args.Length {
        if args[i] == "--backend" && i + 1 < args.Length {
            i = i + 2
            continue
        }

        return i
    }

    return -1
}

func CliWatchForwardedArgIndicesInto(args: string[], resultIndices: int[]): int {
    resultCount := 0
    i := 1

    while i < args.Length {
        arg := args[i]
        if CliWatchArgumentIsOptionWithValue(arg) {
            i = i + 2
            continue
        }

        if arg == "--help" || arg == "-h" {
            i = i + 1
            continue
        }

        if resultCount < resultIndices.Length {
            resultIndices[resultCount] = i
        }

        resultCount = resultCount + 1
        i = i + 1
    }

    return resultCount
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

func CliWatchArgumentIsOptionWithValue(arg: string): bool {
    return arg == "--project" || arg == "--debounce-ms" || arg == "--max-runs"
}

func CliPublishOptionsInto(args: string[], resultIndices: int[]): int {
    if resultIndices.Length < 8 {
        return -1
    }

    resultIndices[0] = -1
    resultIndices[1] = -1
    resultIndices[2] = -1
    resultIndices[3] = -1
    resultIndices[4] = -1
    resultIndices[5] = 0
    resultIndices[6] = 0
    resultIndices[7] = -1

    configurationLongIndex := -1
    configurationShortIndex := -1
    outputLongIndex := -1
    outputShortIndex := -1
    runtimeLongIndex := -1
    runtimeShortIndex := -1

    i := 0
    while i < args.Length {
        arg := args[i]
        kind := CliPublishArgumentKind(arg)
        if kind >= 1 && kind <= 8 {
            if i + 1 >= args.Length {
                resultIndices[7] = i
                return 1
            }

            value := args[i + 1]
            if value.Length > 0 && value[0] == '-' {
                resultIndices[7] = i
                return 1
            }

            valueIndex := i + 1
            if kind == 1 {
                if resultIndices[0] < 0 {
                    resultIndices[0] = valueIndex
                }
            } else if kind == 2 {
                if resultIndices[1] < 0 {
                    resultIndices[1] = valueIndex
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
            resultIndices[5] = 1
            i = i + 1
            continue
        }

        if kind == 10 {
            resultIndices[6] = 1
            i = i + 1
            continue
        }

        if kind == 11 {
            resultIndices[7] = i
            return 2
        }

        resultIndices[7] = i
        if arg.Length > 0 && arg[0] == '-' {
            return 3
        }

        return 4
    }

    if configurationLongIndex >= 0 {
        resultIndices[2] = configurationLongIndex
    } else {
        resultIndices[2] = configurationShortIndex
    }

    if outputLongIndex >= 0 {
        resultIndices[3] = outputLongIndex
    } else {
        resultIndices[3] = outputShortIndex
    }

    if runtimeLongIndex >= 0 {
        resultIndices[4] = runtimeLongIndex
    } else {
        resultIndices[4] = runtimeShortIndex
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

func CliTestOptionSummaryInto(args: string[], resultIndices: int[]): int {
    if resultIndices.Length < 10 {
        return -1
    }

    resultIndices[0] = -1
    resultIndices[1] = -1
    resultIndices[2] = -1
    resultIndices[3] = -1
    resultIndices[4] = 0
    resultIndices[5] = 0
    resultIndices[6] = 0
    resultIndices[7] = 0
    resultIndices[8] = 0
    resultIndices[9] = 0

    i := 0
    while i < args.Length {
        arg := args[i]
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
            resultIndices[9] = 1
        } else if kind == 3 {
            if resultIndices[0] < 0 && i + 1 < args.Length {
                resultIndices[0] = i + 1
            }
        } else if kind == 4 {
            if resultIndices[1] < 0 && i + 1 < args.Length {
                resultIndices[1] = i + 1
            }
        } else if kind == 5 {
            if resultIndices[2] < 0 && i + 1 < args.Length {
                resultIndices[2] = i + 1
            }
        } else if kind == 6 {
            if resultIndices[3] < 0 && i + 1 < args.Length {
                resultIndices[3] = i + 1
            }
        } else if kind == 7 {
            resultIndices[4] = 1
        } else if kind == 8 {
            resultIndices[5] = 1
        } else if kind == 9 {
            resultIndices[6] = 1
        } else if kind == 10 {
            resultIndices[7] = 1
        } else if kind == 11 {
            resultIndices[8] = 1
        }

        i = i + 1
    }

    return 0
}

func CliTestOptionSummaryChecksumInto(args: string[], resultIndices: int[]): int {
    code := CliTestOptionSummaryInto(args, resultIndices)
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

func CliLintFileArgIndicesInto(
    args: string[],
    projectValueIndices: int[],
    resultIndices: int[]): int {
    if projectValueIndices.Length < args.Length || resultIndices.Length < args.Length {
        return -1
    }

    projectValueCount := 0
    i := 0
    while i < args.Length - 1 {
        if args[i] == "--project" {
            projectValueIndices[projectValueCount] = i + 1
            projectValueCount = projectValueCount + 1
            i = i + 2
            continue
        }

        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < args.Length {
        arg := args[i]
        if arg == "help" {
            i = i + 1
            continue
        }

        if arg.Length > 0 && arg[0] == '-' {
            i = i + 1
            continue
        }

        if CliLintIsProjectOptionValue(args, projectValueIndices, projectValueCount, arg) {
            i = i + 1
            continue
        }

        resultIndices[resultCount] = i
        resultCount = resultCount + 1
        i = i + 1
    }

    return resultCount
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

func CliLintIsProjectOptionValue(
    args: string[],
    projectValueIndices: int[],
    projectValueCount: int,
    value: string): bool {
    i := 0
    while i < projectValueCount {
        valueIndex := projectValueIndices[i]
        if valueIndex >= 0 && valueIndex < args.Length && args[valueIndex] == value {
            return true
        }

        i = i + 1
    }

    return false
}

func CliTidyDependencyStatusRanksInto(
    packageNames: string[],
    importNamespaces: string[],
    resultStatusRanks: int[]): int {
    if resultStatusRanks.Length < packageNames.Length {
        return -1
    }

    i := 0
    while i < packageNames.Length {
        resultStatusRanks[i] = CliTidyDependencyStatusRank(packageNames[i], importNamespaces)
        i = i + 1
    }

    return packageNames.Length
}

func CliTidyDependencyStatusRank(packageName: string, importNamespaces: string[]): int {
    firstDot := packageName.IndexOf('.')
    if firstDot < 0 {
        return 3
    }

    i := 0
    while i < importNamespaces.Length {
        namespaceName := importNamespaces[i]
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

func CliTidyRemovalLineKeepFlagsInto(lines: string[], packageNames: string[], resultFlags: int[]): int {
    if resultFlags.Length < lines.Length {
        return -1
    }

    i := 0
    while i < lines.Length {
        resultFlags[i] = CliTidyRemovalLineKeepFlag(lines[i], packageNames)
        i = i + 1
    }

    return lines.Length
}

func CliTidyRemovalLineKeepFlag(line: string, packageNames: string[]): int {
    start := 0
    while start < line.Length && CliTidyIsAsciiWhitespace(line[start]) {
        start = start + 1
    }

    if start + 2 > line.Length || line[start] != '-' || line[start + 1] != ' ' {
        return 1
    }

    if CliTidyRemovalLineStartsWithAnyPackage(line, start + 2, packageNames) {
        return 0
    }

    markerLimit := line.Length - 7
    markerStart := start
    while markerStart <= markerLimit {
        if CliTidyRemovalLineHasNugetMarkerAt(line, markerStart)
            && CliTidyRemovalLineStartsWithAnyPackage(line, markerStart + 7, packageNames) {
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

func CliTidyRemovalLineStartsWithAnyPackage(line: string, packageStart: int, packageNames: string[]): bool {
    i := 0
    while i < packageNames.Length {
        if CliTidyRemovalLineStartsWithPackage(line, packageStart, packageNames[i]) {
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

func CliSymbolNameGlobFilterIndicesInto(
    names: string[],
    pattern: string,
    limit: int,
    resultIndices: int[]): int {
    if limit <= 0 || resultIndices.Length == 0 {
        return 0
    }

    maxCount := limit
    if maxCount > resultIndices.Length {
        maxCount = resultIndices.Length
    }

    matchCount := 0
    i := 0
    while i < names.Length && matchCount < maxCount {
        name := names[i]
        if CliSymbolNameGlobMatchesAsciiIgnoreCase(name, pattern) {
            resultIndices[matchCount] = i
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
    if limit <= 0 || resultIndices.Length == 0 {
        return 0
    }

    maxCount := limit
    if maxCount > resultIndices.Length {
        maxCount = resultIndices.Length
    }

    matchCount := 0
    i := 0
    while i < names.Length && matchCount < maxCount {
        name := names[i]
        if CliSymbolNameContainsAsciiIgnoreCase(name, pattern) {
            resultIndices[matchCount] = i
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

func CliBuildFirstOperandIndexInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    i := 0
    while i < args.Length {
        kind := CliBuildArgumentKind(args[i])
        if kind == 5 {
            i = i + 1
            continue
        }

        if kind == 0 {
            return i
        }

        break
    }

    count := CliBuildOperandSummaryInto(args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices)
    if count <= 0 {
        return -1
    }

    return resultIndices[0]
}

func CliExportCSharpFirstOperandIndexInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    if args.Length == 0 {
        return -1
    }

    firstArg := args[0]
    if firstArg.Length == 0 || firstArg[0] != '-' {
        return 0
    }

    if kindIds.Length < args.Length
        || nextIndices.Length < args.Length
        || previousIndices.Length < args.Length
        || nextOptionIndices.Length < args.Length
        || (args.Length > 0 && resultIndices.Length < 1) {
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
    while i < args.Length {
        kind := CliBuildArgumentKind(args[i])
        kindIds[i] = kind
        nextIndices[i] = -1
        previousIndices[i] = -1
        nextOptionIndices[i] = -1

        if last >= 0 {
            nextIndices[last] = i
            previousIndices[i] = last
        } else {
            first = i
        }

        last = i
        count = count + 1

        if kind == 1 {
            if outputTail >= 0 {
                nextOptionIndices[outputTail] = i
            } else {
                outputHead = i
            }

            outputTail = i
        } else if kind == 2 {
            if shortOutputTail >= 0 {
                nextOptionIndices[shortOutputTail] = i
            } else {
                shortOutputHead = i
            }

            shortOutputTail = i
        } else if kind == 4 {
            if projectTail >= 0 {
                nextOptionIndices[projectTail] = i
            } else {
                projectHead = i
            }

            projectTail = i
        }

        i = i + 1
    }

    resultIndices[0] = first
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, outputHead, 1, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, shortOutputHead, 2, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, projectHead, 4, resultIndices, count)

    sourceIndex := resultIndices[0]
    while sourceIndex >= 0 {
        arg := args[sourceIndex]
        if arg.Length == 0 || arg[0] != '-' {
            return sourceIndex
        }

        sourceIndex = nextIndices[sourceIndex]
    }

    return -1
}

func CliBuildOperandSummaryInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    if kindIds.Length < args.Length
        || nextIndices.Length < args.Length
        || previousIndices.Length < args.Length
        || nextOptionIndices.Length < args.Length
        || (args.Length > 0 && resultIndices.Length < 1) {
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
    while i < args.Length {
        kind := CliBuildArgumentKind(args[i])
        kindIds[i] = kind
        nextIndices[i] = -1
        previousIndices[i] = -1
        nextOptionIndices[i] = -1

        if kind == 5 {
            kindIds[i] = -1
            i = i + 1
            continue
        }

        if last >= 0 {
            nextIndices[last] = i
            previousIndices[i] = last
        } else {
            first = i
        }

        last = i
        count = count + 1

        if kind == 1 {
            if outputTail >= 0 {
                nextOptionIndices[outputTail] = i
            } else {
                outputHead = i
            }

            outputTail = i
        } else if kind == 2 {
            if shortOutputTail >= 0 {
                nextOptionIndices[shortOutputTail] = i
            } else {
                shortOutputHead = i
            }

            shortOutputTail = i
        } else if kind == 3 {
            if backendTail >= 0 {
                nextOptionIndices[backendTail] = i
            } else {
                backendHead = i
            }

            backendTail = i
        } else if kind == 4 {
            if projectTail >= 0 {
                nextOptionIndices[projectTail] = i
            } else {
                projectHead = i
            }

            projectTail = i
        }

        i = i + 1
    }

    if resultIndices.Length > 0 {
        resultIndices[0] = first
    }

    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, outputHead, 1, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, shortOutputHead, 2, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, backendHead, 3, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, projectHead, 4, resultIndices, count)
    return count
}

func CliBuildOperandIndicesInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    count := CliBuildOperandSummaryInto(args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices)
    if count <= 0 {
        return count
    }

    sourceIndex := resultIndices[0]
    resultCount := 0
    while sourceIndex >= 0 {
        resultIndices[resultCount] = sourceIndex
        resultCount = resultCount + 1
        sourceIndex = nextIndices[sourceIndex]
    }

    return resultCount
}

func CliFixSafetyFilterIndicesInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    matchCount := 0
    length := safetyRanks.Length
    i := 0

    if resultIndices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            rank := safetyRanks[i]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = i
                matchCount = matchCount + 1
            }

            next := i + 1
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 2
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 3
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 4
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 5
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 6
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 7
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            i = i + 8
        }

        while i < length {
            rank := safetyRanks[i]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = i
                matchCount = matchCount + 1
            }

            i = i + 1
        }

        return matchCount
    }

    unrolledLimit := length - 4
    while i <= unrolledLimit {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        next := i + 1
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 2
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 3
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        i = i + 4
    }

    while i < length {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
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

func CliFixEditFlattenIndicesInto(
    editCounts: int[],
    resultActionIndices: int[],
    resultEditIndices: int[]): int {
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

func CliFixSkippedIndicesInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    skippedCount := 0
    length := safetyRanks.Length
    i := 0
    while i < length {
        rank := safetyRanks[i]
        if rank == 0 || rank > maxAppliedRank {
            if skippedCount < resultIndices.Length {
                resultIndices[skippedCount] = i
            }

            skippedCount = skippedCount + 1
        }

        i = i + 1
    }

    return skippedCount
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
    if uniqueFileRankCount < 0 {
        return -1
    }

    if fileRanks.Length == 0 {
        return 0
    }

    if uniqueFileRankCount == 0 {
        return -1
    }

    rankCapacity := uniqueFileRankCount + 1
    if countsByRank.Length < rankCapacity
        || offsetsByRank.Length < rankCapacity
        || writeOffsetsByRank.Length < rankCapacity
        || resultRanks.Length < uniqueFileRankCount
        || resultStarts.Length < uniqueFileRankCount
        || resultCounts.Length < uniqueFileRankCount
        || resultIndices.Length < fileRanks.Length {
        return -1
    }

    rank := 0
    while rank < rankCapacity {
        countsByRank[rank] = 0
        offsetsByRank[rank] = 0
        writeOffsetsByRank[rank] = 0
        rank = rank + 1
    }

    i := 0
    while i < fileRanks.Length {
        fileRank := fileRanks[i]
        if fileRank <= 0 || fileRank > uniqueFileRankCount {
            return -1
        }

        countsByRank[fileRank] = countsByRank[fileRank] + 1
        i = i + 1
    }

    offset := 0
    rank = 1
    while rank <= uniqueFileRankCount {
        groupIndex := rank - 1
        count := countsByRank[rank]
        resultRanks[groupIndex] = rank
        resultStarts[groupIndex] = offset
        resultCounts[groupIndex] = count
        offsetsByRank[rank] = offset
        writeOffsetsByRank[rank] = offset
        offset = offset + count
        rank = rank + 1
    }

    if offset > resultIndices.Length {
        return -1
    }

    i = 0
    while i < fileRanks.Length {
        fileRank := fileRanks[i]
        writeIndex := writeOffsetsByRank[fileRank]
        if writeIndex < 0 || writeIndex >= resultIndices.Length {
            return -1
        }

        resultIndices[writeIndex] = i
        writeOffsetsByRank[fileRank] = writeIndex + 1
        i = i + 1
    }

    return uniqueFileRankCount
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
    lineCount := kindIds.Length
    if contextLines < 0 {
        return -1
    }

    if oldLines.Length < lineCount
        || newLines.Length < lineCount
        || resultStarts.Length < lineCount
        || resultLengths.Length < lineCount
        || resultOldStarts.Length < lineCount
        || resultOldCounts.Length < lineCount
        || resultNewStarts.Length < lineCount
        || resultNewCounts.Length < lineCount {
        return -1
    }

    rangeStart := -1
    rangeEnd := -1
    hunkCount := 0
    i := 0
    while i < lineCount {
        if kindIds[i] != 0 {
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
                if !CliUnifiedDiffWriteHunkRange(
                    kindIds,
                    oldLines,
                    newLines,
                    rangeStart,
                    rangeEnd,
                    hunkCount,
                    resultStarts,
                    resultLengths,
                    resultOldStarts,
                    resultOldCounts,
                    resultNewStarts,
                    resultNewCounts) {
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
        if !CliUnifiedDiffWriteHunkRange(
            kindIds,
            oldLines,
            newLines,
            rangeStart,
            rangeEnd,
            hunkCount,
            resultStarts,
            resultLengths,
            resultOldStarts,
            resultOldCounts,
            resultNewStarts,
            resultNewCounts) {
            return -1
        }

        hunkCount = hunkCount + 1
    }

    return hunkCount
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

func CliUnifiedDiffWriteHunkRange(
    kindIds: int[],
    oldLines: int[],
    newLines: int[],
    rangeStart: int,
    rangeEnd: int,
    hunkIndex: int,
    resultStarts: int[],
    resultLengths: int[],
    resultOldStarts: int[],
    resultOldCounts: int[],
    resultNewStarts: int[],
    resultNewCounts: int[]): bool {
    if hunkIndex < 0
        || hunkIndex >= resultStarts.Length
        || hunkIndex >= resultLengths.Length
        || hunkIndex >= resultOldStarts.Length
        || hunkIndex >= resultOldCounts.Length
        || hunkIndex >= resultNewStarts.Length
        || hunkIndex >= resultNewCounts.Length {
        return false
    }

    oldStart := 0
    newStart := 0
    oldCount := 0
    newCount := 0

    i := rangeStart
    while i <= rangeEnd {
        kind := kindIds[i]
        if oldStart == 0 && oldLines[i] > 0 {
            oldStart = oldLines[i]
        }

        if newStart == 0 && newLines[i] > 0 {
            newStart = newLines[i]
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

    resultStarts[hunkIndex] = rangeStart
    resultLengths[hunkIndex] = rangeEnd - rangeStart + 1
    resultOldStarts[hunkIndex] = oldStart
    resultOldCounts[hunkIndex] = oldCount
    resultNewStarts[hunkIndex] = newStart
    resultNewCounts[hunkIndex] = newCount
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
    length := kindRanks.Length
    if nodeModuleFlags.Length < length
        || pathRanks.Length < length
        || pathLengths.Length < length
        || tempIndices.Length < length
        || resultIndices.Length < length {
        return -1
    }

    i := 0
    while i < seenPathRanks.Length {
        seenPathRanks[i] = 0
        i = i + 1
    }

    i = 0
    while i < lengthCounts.Length {
        lengthCounts[i] = 0
        lengthOffsets[i] = 0
        i = i + 1
    }

    selectedCount := 0
    i = 0
    while i < length {
        kindRank := kindRanks[i]
        if kindRank > 0 && nodeModuleFlags[i] == 0 {
            pathRank := pathRanks[i]
            if pathRank <= 0 || pathRank >= seenPathRanks.Length {
                return -1
            }

            if seenPathRanks[pathRank] == 0 {
                pathLength := pathLengths[i]
                if pathLength < 0 || pathLength >= lengthCounts.Length {
                    return -1
                }

                seenPathRanks[pathRank] = 1
                tempIndices[selectedCount] = i
                lengthCounts[pathLength] = lengthCounts[pathLength] + 1
                selectedCount = selectedCount + 1
            }
        }

        i = i + 1
    }

    running := 0
    lengthRank := lengthCounts.Length - 1
    while lengthRank >= 0 {
        count := lengthCounts[lengthRank]
        lengthOffsets[lengthRank] = running
        running = running + count
        lengthRank = lengthRank - 1
    }

    i = 0
    while i < selectedCount {
        sourceIndex := tempIndices[i]
        pathLength := pathLengths[sourceIndex]
        outputIndex := lengthOffsets[pathLength]
        resultIndices[outputIndex] = sourceIndex
        lengthOffsets[pathLength] = outputIndex + 1
        i = i + 1
    }

    return selectedCount
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

func CliUpdateAllNuGetDependencyIndicesInto(
    nugetFlags: int[],
    resultIndices: int[]): int {
    length := nugetFlags.Length
    resultCount := 0
    i := 0
    if resultIndices.Length >= length {
        unrolledLimit := length - 16
        while i <= unrolledLimit {
            if nugetFlags[i] != 0 {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 8
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 9
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 10
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 11
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 12
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 13
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 14
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 15
            if nugetFlags[next] != 0 {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 16
        }

        while i < length {
            if nugetFlags[i] != 0 {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if nugetFlags[i] != 0 {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
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

func CliUpdateTargetNuGetDependencyIndicesInto(
    nameRanks: int[],
    targetNameRank: int,
    resultIndices: int[]): int {
    if targetNameRank <= 0 {
        return 0
    }

    length := nameRanks.Length
    resultCount := 0
    i := 0
    if resultIndices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if nameRanks[i] == targetNameRank {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 8
        }

        while i < length {
            if nameRanks[i] == targetNameRank {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if nameRanks[i] == targetNameRank {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
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

func CliReferenceTypeFilterIndicesInto(
    typeRanks: int[],
    targetTypeRank: int,
    resultIndices: int[]): int {
    if targetTypeRank <= 0 {
        return 0
    }

    length := typeRanks.Length
    resultCount := 0
    i := 0
    if resultIndices.Length >= length {
        unrolledLimit := length - 16
        while i <= unrolledLimit {
            if typeRanks[i] == targetTypeRank {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 8
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 9
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 10
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 11
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 12
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 13
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 14
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 15
            if typeRanks[next] == targetTypeRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 16
        }

        while i < length {
            if typeRanks[i] == targetTypeRank {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if typeRanks[i] == targetTypeRank {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
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

func CliStableDistinctRankIndicesInto(
    ranks: int[],
    uniqueRankCount: int,
    seenRanks: int[],
    resultIndices: int[]): int {
    clearCount := uniqueRankCount + 1
    if clearCount > seenRanks.Length {
        clearCount = seenRanks.Length
    }

    i := 0
    while i < clearCount {
        seenRanks[i] = 0
        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < ranks.Length {
        rank := ranks[i]
        if rank > 0 && rank <= uniqueRankCount && rank < seenRanks.Length {
            if seenRanks[rank] == 0 {
                seenRanks[rank] = 1
                if resultCount < resultIndices.Length {
                    resultIndices[resultCount] = i
                }

                resultCount = resultCount + 1
            }
        }

        i = i + 1
    }

    return resultCount
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

func CliTidyDependencyStatusSummaryInto(statusRanks: int[], resultCounts: int[]): int {
    if resultCounts.Length < 2 {
        return -1
    }

    possiblyUnused := 0
    unknown := 0
    i := 0
    length := statusRanks.Length
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        rank := statusRanks[i]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next := i + 1
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 2
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 3
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 4
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 5
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 6
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        next = i + 7
        rank = statusRanks[next]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        i = i + 8
    }

    while i < length {
        rank := statusRanks[i]
        if rank == 1 {
            possiblyUnused = possiblyUnused + 1
        } else if rank == 3 {
            unknown = unknown + 1
        }

        i = i + 1
    }

    resultCounts[0] = possiblyUnused
    resultCounts[1] = unknown
    return length
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

func CliTestOutcomeSummaryInto(outcomeRanks: int[], count: int, resultCounts: int[]): int {
    if resultCounts.Length < 4 {
        return -1
    }

    if count > outcomeRanks.Length {
        count = outcomeRanks.Length
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
        rank := outcomeRanks[i]
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
        rank = outcomeRanks[next]
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
        rank = outcomeRanks[next]
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
        rank = outcomeRanks[next]
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
        rank = outcomeRanks[next]
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
        rank = outcomeRanks[next]
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
        rank = outcomeRanks[next]
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
        rank = outcomeRanks[next]
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
        rank := outcomeRanks[i]
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

    resultCounts[0] = passed
    resultCounts[1] = failed
    resultCounts[2] = skipped
    resultCounts[3] = nonOk
    return count
}

func CliTestFilterMatchIndicesInto(
    filterParts: string[],
    primaryNames: string[],
    secondaryNames: string[],
    tertiaryNames: string[],
    count: int,
    resultIndices: int[]): int {
    if count < 0
        || count > primaryNames.Length
        || count > secondaryNames.Length
        || count > resultIndices.Length {
        return -1
    }

    if tertiaryNames.Length != 0 && count > tertiaryNames.Length {
        return -1
    }

    matchedCount := 0
    i := 0
    while i < count {
        if CliTestFilterMatchesAnyName(filterParts, primaryNames[i], secondaryNames[i], tertiaryNames, i) {
            resultIndices[matchedCount] = i
            matchedCount = matchedCount + 1
        }

        i = i + 1
    }

    return matchedCount
}

func CliTestFilterMatchesAnyName(
    filterParts: string[],
    primaryName: string,
    secondaryName: string,
    tertiaryNames: string[],
    index: int): bool {
    partIndex := 0
    while partIndex < filterParts.Length {
        part := filterParts[partIndex]
        if part.Length > 0 {
            if CliTestFilterContainsPart(primaryName, part)
                || CliTestFilterContainsPart(secondaryName, part) {
                return true
            }

            if tertiaryNames.Length > index
                && tertiaryNames[index].Length > 0
                && CliTestFilterContainsPart(tertiaryNames[index], part) {
                return true
            }
        }

        partIndex = partIndex + 1
    }

    return false
}

func CliTestFilterContainsPart(text: string, part: string): bool {
    return text.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0
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

func CliFormatDiscoveredPathFlagsInto(relativePaths: string[], resultFlags: int[]): int {
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
    count := CliFormatDiscoveredPathFlagsInto(relativePaths, resultFlags)
    checksum := count
    i := 0

    while i < count {
        checksum = checksum + (i + 1) * 31 + resultFlags[i] * 17 + relativePaths[i].Length * 7
        i = i + 1
    }

    return checksum
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

func CliArgumentIsOptionWithValue(arg: string, optionsWithValues: string[]): bool {
    i := 0
    while i < optionsWithValues.Length {
        if arg == optionsWithValues[i] {
            return true
        }

        i = i + 1
    }

    return false
}

func CliBuildRemoveOptionKindPairs(
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    optionHead: int,
    optionKind: int,
    resultIndices: int[],
    count: int): int {
    sourceIndex := optionHead
    while sourceIndex >= 0 {
        nextOptionIndex := nextOptionIndices[sourceIndex]
        if kindIds[sourceIndex] == optionKind {
            valueIndex := nextIndices[sourceIndex]
            if valueIndex >= 0 {
                previousIndex := previousIndices[sourceIndex]
                afterIndex := nextIndices[valueIndex]
                if previousIndex >= 0 {
                    nextIndices[previousIndex] = afterIndex
                } else {
                    resultIndices[0] = afterIndex
                }

                if afterIndex >= 0 {
                    previousIndices[afterIndex] = previousIndex
                }

                kindIds[sourceIndex] = -1
                kindIds[valueIndex] = -1
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

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

// Source-generator reference resolver kernels.
//
// File-system/package probing remains in C#; this product kernel owns target-framework
// major/minor version parsing used to choose compatible generator assets.

struct SourceGeneratorIntResultTable {
    Values: int[]
}

func SourceGeneratorTargetFrameworkVersionInto(targetFramework: string, result: int[]): int {
    if result.Length < 2 {
        return -1
    }

    result[0] = 0
    result[1] = 0

    start := 0
    while start < targetFramework.Length && !SourceGeneratorTargetFrameworkIsDigit(targetFramework[start]) {
        start = start + 1
    }

    if start >= targetFramework.Length {
        return 0
    }

    end := start
    while end < targetFramework.Length {
        ch := targetFramework[end]
        if !SourceGeneratorTargetFrameworkIsDigit(ch) && ch != '.' {
            break
        }

        end = end + 1
    }

    majorEnd := start
    while majorEnd < end && targetFramework[majorEnd] != '.' {
        majorEnd = majorEnd + 1
    }

    majorTable := new SourceGeneratorIntResultTable { Values: result }
    if !SourceGeneratorTargetFrameworkTryParseIntSegment(targetFramework, start, majorEnd, ref majorTable, 0) {
        result[0] = 0
        result[1] = 0
        return 0
    }

    minorStart := majorEnd
    while minorStart < end && targetFramework[minorStart] == '.' {
        minorStart = minorStart + 1
    }

    if minorStart >= end {
        result[1] = 0
        return 1
    }

    minorEnd := minorStart
    while minorEnd < end && targetFramework[minorEnd] != '.' {
        minorEnd = minorEnd + 1
    }

    minorTable := new SourceGeneratorIntResultTable { Values: result }
    if !SourceGeneratorTargetFrameworkTryParseIntSegment(targetFramework, minorStart, minorEnd, ref minorTable, 1) {
        result[1] = 0
    }

    return 1
}

func SourceGeneratorTargetFrameworkTryParseIntSegment(
    text: string,
    start: int,
    end: int,
    result: &SourceGeneratorIntResultTable,
    resultIndex: int): bool {
    if start >= end {
        return false
    }

    value := 0
    index := start
    while index < end {
        ch := text[index]
        if !SourceGeneratorTargetFrameworkIsDigit(ch) {
            return false
        }

        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 && digit > 7 {
            return false
        }

        value = value * 10 + digit
        index = index + 1
    }

    result.Values[resultIndex] = value
    return true
}

func SourceGeneratorTargetFrameworkIsDigit(ch: char): bool {
    return ch >= '0' && ch <= '9'
}

func SourceGeneratorMinInt(a: int, b: int): int {
    if a < b {
        return a
    }

    return b
}

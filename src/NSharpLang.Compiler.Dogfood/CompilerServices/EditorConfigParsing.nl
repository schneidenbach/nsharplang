// Formatter .editorconfig parsing kernels.
//
// The C# FormatterConfig reader still owns file discovery and line splitting; this product
// kernel owns the integer parse used by formatter numeric options.

struct EditorConfigIntResultTable {
    Values: int[]
}

func EditorConfigTryParseIntInto(value: string, result: int[]): int {
    if result.Length < 1 {
        return -1
    }

    result[0] = 0
    values := new EditorConfigIntResultTable { Values: result }
    if EditorConfigTryParseIntCore(value, 0, value.Length, ref values, 0) {
        return 1
    }

    return 0
}

func EditorConfigTryParseIntCore(
    text: string,
    start: int,
    end: int,
    result: &EditorConfigIntResultTable,
    resultIndex: int): bool {
    while start < end && EditorConfigIsWhiteSpace(text[start]) {
        start = start + 1
    }

    while end > start && EditorConfigIsWhiteSpace(text[end - 1]) {
        end = end - 1
    }

    if start >= end {
        return false
    }

    negative := false
    if text[start] == '+' || text[start] == '-' {
        negative = text[start] == '-'
        start = start + 1
        if start >= end {
            return false
        }
    }

    value := 0
    index := start
    while index < end {
        ch := text[index]
        if ch < '0' || ch > '9' {
            return false
        }

        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 {
            if negative {
                if digit == 8 && index == end - 1 {
                    result.Values[resultIndex] = 0 - 2147483647 - 1
                    return true
                }

                return false
            }

            if digit > 7 {
                return false
            }
        }

        value = value * 10 + digit
        index = index + 1
    }

    if negative {
        result.Values[resultIndex] = 0 - value
    } else {
        result.Values[resultIndex] = value
    }

    return true
}

func EditorConfigIsWhiteSpace(ch: char): bool {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
        return true
    }

    return char.IsWhiteSpace(ch)
}

func EditorConfigMinInt(a: int, b: int): int {
    if a < b {
        return a
    }

    return b
}

import System.Text

struct ColumnarInterpolatedStringPartOutputTable {
    Kinds: int[]
    Texts: string[]
    Formats: string[]
    FormatFlags: int[]
}

func ColumnarInterpolatedStringPartsInto(
    literal: string,
    outKinds: int[],
    outTexts: string[],
    outFormats: string[],
    outFormatFlags: int[]): int {
    outputs := new ColumnarInterpolatedStringPartOutputTable {
        Kinds: outKinds,
        Texts: outTexts,
        Formats: outFormats,
        FormatFlags: outFormatFlags
    }

    return ColumnarInterpolatedStringPartsCore(literal, ref outputs)
}

func ColumnarInterpolatedStringPartsCore(
    literal: string,
    outputs: &ColumnarInterpolatedStringPartOutputTable): int {
    if literal.Length < 3 || literal[0] != '$' || literal[1] != '"' || literal[literal.Length - 1] != '"' {
        return -1
    }

    partCount := 0
    text := new StringBuilder(literal.Length)
    i := 2
    end := literal.Length - 1

    while i < end {
        c := literal[i]
        if c == '\\' && i + 1 < end {
            text.Append(c)
            text.Append(literal[i + 1])
            i = i + 2
            continue
        }

        if c == '{' {
            if i + 1 < end && literal[i + 1] == '{' {
                text.Append('{')
                i = i + 2
                continue
            }

            close := FindColumnarInterpolatedStringClose(literal, i + 1, end)
            if close < 0 || close >= end {
                return -1
            }

            contentStart := i + 1
            contentLength := close - i - 1
            colon := FindColumnarInterpolatedStringColon(literal, contentStart, contentLength)
            exprStart := contentStart
            exprLength := contentLength
            formatStart := 0
            formatLength := 0
            hasFormat := 0

            if colon >= 0 {
                exprLength = colon - contentStart
                formatStart = colon + 1
                formatLength = close - formatStart
                hasFormat = 1
                if formatLength == 0 {
                    return -1
                }

                if ColumnarInterpolatedStringFormatHasBoundaryChars(literal, formatStart, formatLength) {
                    return -1
                }
            }

            if !ColumnarInterpolatedStringIsIdentifierChain(literal, exprStart, exprLength) {
                return -1
            }

            if text.Length > 0 {
                partCount = EmitColumnarInterpolatedStringPart(ref outputs, partCount, 0, text.ToString(), "", 0)
                if partCount < 0 {
                    return -1
                }
                text = new StringBuilder(literal.Length)
            }

            formatText := ""
            if hasFormat != 0 {
                formatText = literal.Substring(formatStart, formatLength)
            }

            partCount = EmitColumnarInterpolatedStringPart(ref outputs, partCount, 1, literal.Substring(exprStart, exprLength), formatText, hasFormat)
            if partCount < 0 {
                return -1
            }

            i = close + 1
            continue
        }

        if c == '}' {
            if i + 1 < end && literal[i + 1] == '}' {
                text.Append('}')
                i = i + 2
                continue
            }

            return -1
        }

        text.Append(c)
        i = i + 1
    }

    if text.Length > 0 {
        partCount = EmitColumnarInterpolatedStringPart(ref outputs, partCount, 0, text.ToString(), "", 0)
        if partCount < 0 {
            return -1
        }
    }

    return partCount
}

func EmitColumnarInterpolatedStringPart(
    outputs: &ColumnarInterpolatedStringPartOutputTable,
    partCount: int,
    kind: int,
    text: string,
    format: string,
    hasFormat: int): int {
    if partCount < 0
        || partCount >= outputs.Kinds.Length
        || partCount >= outputs.Texts.Length
        || partCount >= outputs.Formats.Length
        || partCount >= outputs.FormatFlags.Length {
        return -1
    }

    outputs.Kinds[partCount] = kind
    outputs.Texts[partCount] = text
    outputs.Formats[partCount] = format
    outputs.FormatFlags[partCount] = hasFormat
    return partCount + 1
}

func FindColumnarInterpolatedStringClose(literal: string, start: int, end: int): int {
    i := start
    while i < end {
        if literal[i] == '}' {
            return i
        }

        i = i + 1
    }

    return -1
}

func FindColumnarInterpolatedStringColon(literal: string, start: int, length: int): int {
    i := 0
    while i < length {
        if literal[start + i] == ':' {
            return start + i
        }

        i = i + 1
    }

    return -1
}

func ColumnarInterpolatedStringFormatHasBoundaryChars(literal: string, start: int, length: int): bool {
    i := 0
    while i < length {
        c := literal[start + i]
        if c == '{' || c == '}' || c == '"' || c == '\\' {
            return true
        }

        i = i + 1
    }

    return false
}

func ColumnarInterpolatedStringIsIdentifierChain(literal: string, start: int, length: int): bool {
    if length == 0 {
        return false
    }

    expectIdentifierStart := true
    i := 0
    while i < length {
        ch := literal[start + i]
        if expectIdentifierStart {
            if !ColumnarInterpolatedStringIsIdentifierStart(ch) {
                return false
            }

            expectIdentifierStart = false
        } else if ch == '.' {
            expectIdentifierStart = true
        } else if !ColumnarInterpolatedStringIsIdentifierPart(ch) {
            return false
        }

        i = i + 1
    }

    return !expectIdentifierStart
}

func ColumnarInterpolatedStringIsIdentifierStart(ch: char): bool {
    return ch == '_' || char.IsLetter(ch)
}

func ColumnarInterpolatedStringIsIdentifierPart(ch: char): bool {
    return ch == '_' || char.IsLetterOrDigit(ch)
}

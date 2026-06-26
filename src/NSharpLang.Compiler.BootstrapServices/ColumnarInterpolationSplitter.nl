namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Text

public class ColumnarInterpolationSplitter {
    public class Part {
        public IsHole: bool
        public Text: string
        public Format: string?
    }

    public static func TrySplit(literal: string, parts: List<Part>): bool {
        capacity := literal.Length + 1
        kinds := new int[](capacity)
        texts := new string[](capacity)
        formats := new string[](capacity)
        formatFlags := new int[](capacity)

        count := ColumnarInterpolatedStringParts(literal, kinds, texts, formats, formatFlags)
        if count < 0 {
            return false
        }

        i := 0
        while i < count {
            part := new Part {
                IsHole: kinds[i] == 1,
                Text: texts[i],
                Format: formats[i]
            }

            if formatFlags[i] == 0 {
                part.Format = null
            }

            parts.Add(part)
            i = i + 1
        }

        return true
    }

    static func ColumnarInterpolatedStringParts(
        literal: string,
        outKinds: int[],
        outTexts: string[],
        outFormats: string[],
        outFormatFlags: int[]): int {
        if literal.Length < 3 {
            return -1
        }

        if literal[0] != '$' {
            return -1
        }

        if literal[1] != '"' {
            return -1
        }

        if literal[literal.Length - 1] != '"' {
            return -1
        }

        partCount := 0
        text := new StringBuilder(literal.Length)
        i := 2
        end := literal.Length - 1

        while i < end {
            c := literal[i]
            if c == '\\' {
                if i + 1 < end {
                    text.Append(c)
                    text.Append(literal[i + 1])
                    i = i + 2
                    continue
                }
            }

            if c == '{' {
                if i + 1 < end {
                    if literal[i + 1] == '{' {
                        text.Append('{')
                        i = i + 2
                        continue
                    }
                }

                close := FindColumnarInterpolatedStringClose(literal, i + 1, end)
                if close < 0 {
                    return -1
                }

                if close >= end {
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
                    partCount = EmitColumnarInterpolatedStringPart(outKinds, outTexts, outFormats, outFormatFlags, partCount, 0, text.ToString(), "", 0)
                    if partCount < 0 {
                        return -1
                    }

                    text = new StringBuilder(literal.Length)
                }

                formatText := ""
                if hasFormat != 0 {
                    formatText = literal.Substring(formatStart, formatLength)
                }

                partCount = EmitColumnarInterpolatedStringPart(outKinds, outTexts, outFormats, outFormatFlags, partCount, 1, literal.Substring(exprStart, exprLength), formatText, hasFormat)
                if partCount < 0 {
                    return -1
                }

                i = close + 1
                continue
            }

            if c == '}' {
                if i + 1 < end {
                    if literal[i + 1] == '}' {
                        text.Append('}')
                        i = i + 2
                        continue
                    }
                }

                return -1
            }

            text.Append(c)
            i = i + 1
        }

        if text.Length > 0 {
            partCount = EmitColumnarInterpolatedStringPart(outKinds, outTexts, outFormats, outFormatFlags, partCount, 0, text.ToString(), "", 0)
            if partCount < 0 {
                return -1
            }
        }

        return partCount
    }

    static func EmitColumnarInterpolatedStringPart(
        outKinds: int[],
        outTexts: string[],
        outFormats: string[],
        outFormatFlags: int[],
        partCount: int,
        kind: int,
        text: string,
        format: string,
        hasFormat: int): int {
        if partCount < 0 {
            return -1
        }

        if partCount >= outKinds.Length {
            return -1
        }

        if partCount >= outTexts.Length {
            return -1
        }

        if partCount >= outFormats.Length {
            return -1
        }

        if partCount >= outFormatFlags.Length {
            return -1
        }

        outKinds[partCount] = kind
        outTexts[partCount] = text
        outFormats[partCount] = format
        outFormatFlags[partCount] = hasFormat
        return partCount + 1
    }

    static func FindColumnarInterpolatedStringClose(literal: string, start: int, end: int): int {
        i := start
        while i < end {
            if literal[i] == '}' {
                return i
            }

            i = i + 1
        }

        return -1
    }

    static func FindColumnarInterpolatedStringColon(literal: string, start: int, length: int): int {
        i := 0
        while i < length {
            if literal[start + i] == ':' {
                return start + i
            }

            i = i + 1
        }

        return -1
    }

    static func ColumnarInterpolatedStringFormatHasBoundaryChars(literal: string, start: int, length: int): bool {
        i := 0
        while i < length {
            c := literal[start + i]
            if c == '{' {
                return true
            }

            if c == '}' {
                return true
            }

            if c == '"' {
                return true
            }

            if c == '\\' {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func ColumnarInterpolatedStringIsIdentifierChain(literal: string, start: int, length: int): bool {
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

    static func ColumnarInterpolatedStringIsIdentifierStart(ch: char): bool {
        if ch == '_' {
            return true
        }

        return char.IsLetter(ch)
    }

    static func ColumnarInterpolatedStringIsIdentifierPart(ch: char): bool {
        if ch == '_' {
            return true
        }

        return char.IsLetterOrDigit(ch)
    }
}

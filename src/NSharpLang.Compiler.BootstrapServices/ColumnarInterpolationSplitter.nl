namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Text

public class ColumnarInterpolationPart {
    public IsHole: bool
    public Text: string
    public Format: string?
}

public class ColumnarInterpolationSplitter {
    public static func TrySplit(literal: string, parts: List<ColumnarInterpolationPart>): bool {
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
            part := new ColumnarInterpolationPart {
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

        partCount := 0
        text := new StringBuilder(literal.Length)
        i := 2
        end := literal.Length - 1
        if literal.Length >= 7 &&
            literal[1] == '"' &&
            literal[2] == '"' &&
            literal[3] == '"' &&
            literal[literal.Length - 1] == '"' &&
            literal[literal.Length - 2] == '"' &&
            literal[literal.Length - 3] == '"' {
            i = 4
            end = literal.Length - 3
        } else {
            if literal[1] != '"' {
                return -1
            }

            if literal[literal.Length - 1] != '"' {
                return -1
            }
        }

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

                if !ColumnarInterpolatedStringIsSupportedHoleExpression(literal, exprStart, exprLength) {
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

    static func ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal: string, start: int, length: int): bool {
        if ColumnarInterpolatedStringIsIdentifierChain(literal, start, length) {
            return true
        }

        if ColumnarInterpolatedStringIsRootIndexedIdentifierChain(literal, start, length) {
            return true
        }

        if length > 2 && literal[start + length - 2] == '(' && literal[start + length - 1] == ')' {
            return ColumnarInterpolatedStringIsIdentifierChain(literal, start, length - 2)
        }

        if length > 4 && literal[start + length - 1] == ')' {
            openParen := -1
            i := 0
            while i < length {
                ch := literal[start + i]
                if ch == '(' {
                    if openParen >= 0 {
                        return false
                    }

                    openParen = i
                } else if ch == ',' {
                    return false
                }

                i = i + 1
            }

            if openParen > 0 && openParen < length - 1 {
                argStart := start + openParen + 1
                argLength := length - openParen - 2
                while argLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[argStart]) {
                    argStart = argStart + 1
                    argLength = argLength - 1
                }

                while argLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[argStart + argLength - 1]) {
                    argLength = argLength - 1
                }

                return ColumnarInterpolatedStringIsIdentifierChain(literal, start, openParen)
                    && ColumnarInterpolatedStringIsSupportedCallArgument(literal, argStart, argLength)
            }
        }

        return false
    }

    static func ColumnarInterpolatedStringIsSupportedCallArgument(literal: string, start: int, length: int): bool {
        if length == 0 {
            return false
        }

        parenDepth := 0
        bracketDepth := 0
        i := 0
        while i < length {
            ch := literal[start + i]
            if ch == '{' || ch == '}' || ch == ':' || ch == '"' || ch == '\\' {
                return false
            }

            if ch == ',' && parenDepth == 0 && bracketDepth == 0 {
                return false
            }

            if ch == '(' {
                parenDepth = parenDepth + 1
            } else if ch == ')' {
                parenDepth = parenDepth - 1
                if parenDepth < 0 {
                    return false
                }
            } else if ch == '[' {
                bracketDepth = bracketDepth + 1
            } else if ch == ']' {
                bracketDepth = bracketDepth - 1
                if bracketDepth < 0 {
                    return false
                }
            }

            i = i + 1
        }

        return parenDepth == 0 && bracketDepth == 0
    }

    static func ColumnarInterpolatedStringIsRootIndexedIdentifierChain(literal: string, start: int, length: int): bool {
        if length == 0 {
            return false
        }

        i := 0
        if !ColumnarInterpolatedStringIsIdentifierStart(literal[start]) {
            return false
        }

        i = 1
        while i < length && ColumnarInterpolatedStringIsIdentifierPart(literal[start + i]) {
            i = i + 1
        }

        if i >= length {
            return false
        }

        if literal[start + i] != '[' {
            return false
        }

        i = i + 1
        if i >= length {
            return false
        }

        if ColumnarInterpolatedStringIsAsciiDigit(literal[start + i]) {
            while i < length && ColumnarInterpolatedStringIsAsciiDigit(literal[start + i]) {
                i = i + 1
            }
        } else {
            if !ColumnarInterpolatedStringIsIdentifierStart(literal[start + i]) {
                return false
            }

            i = i + 1
            while i < length && ColumnarInterpolatedStringIsIdentifierPart(literal[start + i]) {
                i = i + 1
            }
        }

        if i >= length {
            return false
        }

        if literal[start + i] != ']' {
            return false
        }

        i = i + 1
        if i == length {
            return true
        }

        while i < length {
            if literal[start + i] != '.' {
                return false
            }

            i = i + 1
            if i >= length {
                return false
            }

            if !ColumnarInterpolatedStringIsIdentifierStart(literal[start + i]) {
                return false
            }

            i = i + 1
            while i < length && ColumnarInterpolatedStringIsIdentifierPart(literal[start + i]) {
                i = i + 1
            }
        }

        return true
    }

    static func ColumnarInterpolatedStringIsSupportedHoleExpression(literal: string, start: int, length: int): bool {
        if ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal, start, length) {
            return true
        }

        if ColumnarInterpolatedStringIsSupportedMultiArgumentCallExpression(literal, start, length) {
            return true
        }

        if ColumnarInterpolatedStringIsSupportedCastHoleExpression(literal, start, length) {
            return true
        }

        if ColumnarInterpolatedStringIsIntegerAdditiveExpression(literal, start, length) {
            return true
        }

        if ColumnarInterpolatedStringIsSupportedParsedHoleExpression(literal, start, length) {
            return true
        }

        equality := ColumnarInterpolatedStringFindEqualityOperator(literal, start, length)
        if equality >= 0 {
            leftStart := start
            leftLength := equality
            rightStart := start + equality + 2
            rightLength := length - equality - 2
            while leftLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[leftStart]) {
                leftStart = leftStart + 1
                leftLength = leftLength - 1
            }

            while leftLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[leftStart + leftLength - 1]) {
                leftLength = leftLength - 1
            }

            while rightLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[rightStart]) {
                rightStart = rightStart + 1
                rightLength = rightLength - 1
            }

            while rightLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[rightStart + rightLength - 1]) {
                rightLength = rightLength - 1
            }

            return ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal, leftStart, leftLength)
                && ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal, rightStart, rightLength)
        }

        coalesce := -1
        i := 0
        while i + 1 < length {
            if literal[start + i] == '?' && literal[start + i + 1] == '?' {
                if coalesce >= 0 {
                    return false
                }

                coalesce = i
                i = i + 2
                continue
            }

            i = i + 1
        }

        if coalesce < 0 {
            return false
        }

        leftStart := start
        leftLength := coalesce
        rightStart := start + coalesce + 2
        rightLength := length - coalesce - 2
        while leftLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[leftStart]) {
            leftStart = leftStart + 1
            leftLength = leftLength - 1
        }

        while leftLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[leftStart + leftLength - 1]) {
            leftLength = leftLength - 1
        }

        while rightLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[rightStart]) {
            rightStart = rightStart + 1
            rightLength = rightLength - 1
        }

        while rightLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[rightStart + rightLength - 1]) {
            rightLength = rightLength - 1
        }

        return ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal, leftStart, leftLength)
            && ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal, rightStart, rightLength)
    }

    // A call hole with TWO OR MORE top-level arguments (`{String.Join(separator, numbers)}`): an
    // identifier-chain callee followed by a balanced argument list whose comma-split segments each
    // pass the shared call-argument scan. This gate only shapes the split; the parsed-expression
    // hole plan's preflight typing decides emission, so an admitted-but-unmodeled call still
    // declines precisely at the hole-resolution site.
    static func ColumnarInterpolatedStringIsSupportedMultiArgumentCallExpression(literal: string, start: int, length: int): bool {
        if length < 6 {
            return false
        }

        if literal[start + length - 1] != ')' {
            return false
        }

        openParen := -1
        i := 0
        while i < length {
            if literal[start + i] == '(' {
                openParen = i
                break
            }

            i = i + 1
        }

        if openParen <= 0 || openParen >= length - 2 {
            return false
        }

        if !ColumnarInterpolatedStringIsIdentifierChain(literal, start, openParen) {
            return false
        }

        argumentCount := 0
        parenDepth := 0
        bracketDepth := 0
        segmentStart := openParen + 1
        j := openParen + 1
        while j < length - 1 {
            ch := literal[start + j]
            if ch == ',' && parenDepth == 0 && bracketDepth == 0 {
                if !ColumnarInterpolatedStringIsSupportedCallArgument(literal, start + segmentStart, j - segmentStart) {
                    return false
                }

                argumentCount = argumentCount + 1
                segmentStart = j + 1
            } else if ch == '(' {
                parenDepth = parenDepth + 1
            } else if ch == ')' {
                parenDepth = parenDepth - 1
                if parenDepth < 0 {
                    return false
                }
            } else if ch == '[' {
                bracketDepth = bracketDepth + 1
            } else if ch == ']' {
                bracketDepth = bracketDepth - 1
                if bracketDepth < 0 {
                    return false
                }
            }

            j = j + 1
        }

        if parenDepth != 0 || bracketDepth != 0 || argumentCount == 0 {
            return false
        }

        return ColumnarInterpolatedStringIsSupportedCallArgument(literal, start + segmentStart, length - 1 - segmentStart)
    }

    static func ColumnarInterpolatedStringIsSupportedParsedHoleExpression(literal: string, start: int, length: int): bool {
        if length == 0 {
            return false
        }

        parenDepth := 0
        bracketDepth := 0
        sawOperator := false
        i := 0
        while i < length {
            ch := literal[start + i]
            if ch == '{' || ch == '}' || ch == ':' || ch == '"' || ch == '\\' {
                return false
            }

            if ch == ',' && parenDepth == 0 && bracketDepth == 0 {
                return false
            }

            if ch == '(' {
                parenDepth = parenDepth + 1
            } else if ch == ')' {
                parenDepth = parenDepth - 1
                if parenDepth < 0 {
                    return false
                }
            } else if ch == '[' {
                bracketDepth = bracketDepth + 1
            } else if ch == ']' {
                bracketDepth = bracketDepth - 1
                if bracketDepth < 0 {
                    return false
                }
            } else if ch == '+' || ch == '-' || ch == '*' || ch == '/' || ch == '%' || ch == '<' || ch == '>' || ch == '&' || ch == '|' {
                sawOperator = true
            }

            i = i + 1
        }

        return sawOperator && parenDepth == 0 && bracketDepth == 0
    }

    static func ColumnarInterpolatedStringIsSupportedCastHoleExpression(literal: string, start: int, length: int): bool {
        if length < 4 {
            return false
        }

        if literal[start] != '(' {
            return false
        }

        close := -1
        i := 1
        while i < length {
            ch := literal[start + i]
            if ch == ')' {
                close = i
                break
            }

            if ch == '(' || ch == ',' || ch == '{' || ch == '}' || ch == ':' {
                return false
            }

            i = i + 1
        }

        if close <= 1 || close >= length - 1 {
            return false
        }

        typeStart := start + 1
        typeLength := close - 1
        while typeLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[typeStart]) {
            typeStart = typeStart + 1
            typeLength = typeLength - 1
        }

        while typeLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[typeStart + typeLength - 1]) {
            typeLength = typeLength - 1
        }

        operandStart := start + close + 1
        operandLength := length - close - 1
        while operandLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[operandStart]) {
            operandStart = operandStart + 1
            operandLength = operandLength - 1
        }

        while operandLength > 0 && ColumnarInterpolatedStringIsTrimSpace(literal[operandStart + operandLength - 1]) {
            operandLength = operandLength - 1
        }

        return ColumnarInterpolatedStringIsIdentifierChain(literal, typeStart, typeLength)
            && ColumnarInterpolatedStringIsSupportedSimpleHoleExpression(literal, operandStart, operandLength)
    }

    static func ColumnarInterpolatedStringFindEqualityOperator(literal: string, start: int, length: int): int {
        found := -1
        i := 0
        while i + 1 < length {
            ch := literal[start + i]
            next := literal[start + i + 1]
            if (ch == '=' && next == '=') || (ch == '!' && next == '=') {
                if found >= 0 {
                    return -1
                }

                found = i
                i = i + 2
                continue
            }

            i = i + 1
        }

        return found
    }

    static func ColumnarInterpolatedStringIsTrimSpace(ch: char): bool {
        if ch == ' ' {
            return true
        }

        return ch == '\t'
    }

    static func ColumnarInterpolatedStringIsIntegerAdditiveExpression(literal: string, start: int, length: int): bool {
        i := 0
        expectNumber := true
        sawNumber := false
        while i < length {
            ch := literal[start + i]
            if ColumnarInterpolatedStringIsTrimSpace(ch) {
                i = i + 1
                continue
            }

            if expectNumber {
                if !ColumnarInterpolatedStringIsAsciiDigit(ch) {
                    return false
                }

                sawNumber = true
                while i < length && ColumnarInterpolatedStringIsAsciiDigit(literal[start + i]) {
                    i = i + 1
                }
                expectNumber = false
            } else {
                if ch != '+' && ch != '-' {
                    return false
                }

                expectNumber = true
                i = i + 1
            }
        }

        return sawNumber && !expectNumber
    }

    static func ColumnarInterpolatedStringIsAsciiDigit(ch: char): bool {
        return ch >= '0' && ch <= '9'
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

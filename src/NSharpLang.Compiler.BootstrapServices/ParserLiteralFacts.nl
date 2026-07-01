namespace NSharpLang.Compiler

public class ParserLiteralFacts {
    public static func IsCompleteStringLiteral(value: string): bool {
        if StartsWithInterpolatedString(value) {
            return HasUnescapedClosingQuote(value, 1)
        }

        if value.Length > 0 && value[0] == '"' {
            return HasUnescapedClosingQuote(value, 0)
        }

        return true
    }

    public static func IsCompleteCharLiteral(value: string): bool {
        if value.Length < 3 || value[0] != '\'' || value[value.Length - 1] != '\'' {
            return false
        }

        bodyLength := value.Length - 2
        if bodyLength == 1 {
            return true
        }

        return bodyLength == 2 && value[1] == '\\'
    }

    public static func FindFormatSpecifierColon(expression: string): int {
        parenDepth := 0
        bracketDepth := 0
        braceDepth := 0
        ternaryDepth := 0
        inString := false

        index := 0
        while index < expression.Length {
            ch := expression[index]

            if inString {
                if ch == '\\' && index + 1 < expression.Length {
                    index = index + 2
                    continue
                }

                if ch == '"' {
                    inString = false
                }

                index = index + 1
                continue
            }

            if ch == '"' {
                inString = true
            } else if ch == '(' {
                parenDepth = parenDepth + 1
            } else if ch == ')' {
                parenDepth = parenDepth - 1
            } else if ch == '[' {
                bracketDepth = bracketDepth + 1
            } else if ch == ']' {
                bracketDepth = bracketDepth - 1
            } else if ch == '{' {
                braceDepth = braceDepth + 1
            } else if ch == '}' {
                braceDepth = braceDepth - 1
            } else if ch == '?' {
                if IsAtFormatDepth(parenDepth, bracketDepth, braceDepth) {
                    next := '\0'
                    if index + 1 < expression.Length {
                        next = expression[index + 1]
                    }

                    if next == '?' {
                        index = index + 1
                    } else if next != '.' && next != '[' {
                        ternaryDepth = ternaryDepth + 1
                    }
                }
            } else if ch == ':' {
                if IsAtFormatDepth(parenDepth, bracketDepth, braceDepth) {
                    if ternaryDepth > 0 {
                        ternaryDepth = ternaryDepth - 1
                    } else {
                        return index
                    }
                }
            }

            index = index + 1
        }

        return -1
    }

    static func StartsWithInterpolatedString(value: string): bool {
        return value.Length >= 2 && value[0] == '$' && value[1] == '"'
    }

    static func HasUnescapedClosingQuote(value: string, openingQuoteIndex: int): bool {
        if value.Length <= openingQuoteIndex + 1 || value[value.Length - 1] != '"' {
            return false
        }

        backslashCount := 0
        index := value.Length - 2
        while index > openingQuoteIndex && value[index] == '\\' {
            backslashCount = backslashCount + 1
            index = index - 1
        }

        return backslashCount % 2 == 0
    }

    static func IsAtFormatDepth(parenDepth: int, bracketDepth: int, braceDepth: int): bool {
        return parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
    }
}

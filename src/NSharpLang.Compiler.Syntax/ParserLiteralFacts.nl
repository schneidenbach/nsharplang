namespace NSharpLang.Compiler

class ParserLiteralFacts {
    static func IsCompleteStringLiteral(value: string): bool {
        if StartsWithInterpolatedString(value) {
            return HasUnescapedClosingQuote(value, 1)
        }

        if value.Length > 0 && value[0] == '"' {
            return HasUnescapedClosingQuote(value, 0)
        }

        return true
    }

    static func IsCompleteCharLiteral(value: string): bool {
        if value.Length < 3 || value[0] != '\'' || value[value.Length - 1] != '\'' {
            return false
        }

        bodyLength := value.Length - 2
        if bodyLength == 1 {
            return true
        }

        return bodyLength == 2 && value[1] == '\\'
    }

    // WHERE AN INTERPOLATION HOLE'S TEXT STOPS BEING STRUCTURE.
    //
    // A hole is an ordinary expression, so the `{`, `}`, `:` and `,` written inside one of its string
    // or character literals are CONTENT: `{name.Replace("}", "")}` and `{c == '}'}` each end at their
    // last brace. This answers, for a quote at `start`, the index just PAST its closing quote, or -1
    // when nothing closes it before `end`. A backslash escape consumes the character after it, so
    // `"\""` and `'\''` are one literal each. Every scanner that decides a hole boundary -- the parser,
    // the emitter's splitter -- skips literals through this one rule, so they cannot disagree on it.
    static func InterpolationHoleQuotedLiteralEnd(text: string, start: int, end: int): int {
        if !OpensInterpolationHoleLiteral(text, start, end) {
            return -1
        }

        quote := text[start]
        index := start + 1
        while index < end {
            ch := text[index]
            if ch == '\\' {
                index = index + 2
                continue
            }

            if ch == quote {
                return index + 1
            }

            index = index + 1
        }

        return -1
    }

    // Whether the character at `index` opens a string or character literal. Every `"` does. An
    // apostrophe does unless it begins a LIFETIME (`'a` in `Ref<'a, T>`): an identifier character
    // after it that is not itself closed by a second apostrophe, a shape no character literal has
    // -- `'a'` closes at once and `'\n'` starts with a backslash.
    static func OpensInterpolationHoleLiteral(text: string, index: int, end: int): bool {
        if index < 0 || index >= end {
            return false
        }

        ch := text[index]
        if ch == '"' {
            return true
        }

        if ch != '\'' {
            return false
        }

        if index + 1 < end && IdentifierText.IsStart(text[index + 1]) {
            return index + 2 < end && text[index + 2] == '\''
        }

        return true
    }

    // The `}` that closes the hole whose content begins at `start`, or -1 when the hole is not closed
    // before `end`. Braces NEST the way C#'s do: an anonymous object, an object initializer or a
    // lambda body inside the hole -- `{new { A: 1 }}`, `{Serialize(new { Ok: true }):X}` -- opens a
    // group the hole cannot end inside, and a brace inside a string or character literal is skipped
    // with the literal. An unterminated literal leaves the hole unclosed.
    static func FindInterpolationHoleClose(text: string, start: int, end: int): int {
        depth := 0
        index := start
        while index < end {
            ch := text[index]
            if OpensInterpolationHoleLiteral(text, index, end) {
                quotedEnd := InterpolationHoleQuotedLiteralEnd(text, index, end)
                if quotedEnd < 0 {
                    return -1
                }

                index = quotedEnd
                continue
            }

            if ch == '{' {
                depth = depth + 1
            } else if ch == '}' {
                if depth == 0 {
                    return index
                }

                depth = depth - 1
            }

            index = index + 1
        }

        return -1
    }

    static func FindFormatSpecifierColon(expression: string): int {
        parenDepth := 0
        bracketDepth := 0
        braceDepth := 0
        ternaryDepth := 0

        index := 0
        while index < expression.Length {
            ch := expression[index]

            // A literal's colon is content: `{c == ':'}` and `{Join(": ", parts)}` have no format.
            if OpensInterpolationHoleLiteral(expression, index, expression.Length) {
                quotedEnd := InterpolationHoleQuotedLiteralEnd(expression, index, expression.Length)
                if quotedEnd < 0 {
                    return -1
                }

                index = quotedEnd
                continue
            }

            if ch == '(' {
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

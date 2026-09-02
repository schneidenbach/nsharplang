namespace NSharpLang.Compiler

import System.Text

class StringLiteralDecoder {

    // `isRawBody` SAYS THE TEXT IS A RAW LITERAL'S BODY, ALREADY WITHOUT ITS DELIMITERS — which is
    // what an AST `StringLiteralExpression.Value` holds and what no source slice ever holds.
    //
    // Every one of this owner's thirteen call sites hands it a SOURCE SLICE (`TryGetNodeText`,
    // `source.Substring(...)`, the emitter's argument texts), delimiters included, so
    // `IsTripleQuoteStringLiteral` succeeds and the raw arm is correct — the emit path was never
    // wrong. The parameter exists for the OTHER input, the one the playground's own copy of this
    // logic was handed, so that the three string forms can be stated as one family here instead of
    // being re-derived per owner. It defaults to false, so all thirteen sites are unchanged.
    static func Decode(tokenText: string, isRawBody: bool = false): string {
        if isRawBody {
            return tokenText
        }

        if IsInterpolatedRawStringLiteral(tokenText) {
            return tokenText.Substring(4, tokenText.Length - 7)
        }

        if IsTripleQuoteStringLiteral(tokenText) {
            return tokenText.Substring(3, tokenText.Length - 6)
        }

        start := 0
        if tokenText.Length > 0 && tokenText[0] == '"' {
            start = 1
        }

        end := tokenText.Length
        if tokenText.Length > start && tokenText[tokenText.Length - 1] == '"' {
            end = tokenText.Length - 1
        }

        return DecodeBody(tokenText.Substring(start, end - start))
    }

    static func DecodeInterpolatedText(literal: string, text: string): string {
        if IsInterpolatedRawStringLiteral(literal) {
            return text
        }

        return DecodeBody(text)
    }

    static func IsInterpolatedRawStringLiteral(tokenText: string): bool {
        if tokenText.Length < 7 {
            return false
        }

        return tokenText[0] == '$' && tokenText[1] == '"' && tokenText[2] == '"' && tokenText[3] == '"' && tokenText[tokenText.Length - 1] == '"' && tokenText[tokenText.Length - 2] == '"' && tokenText[tokenText.Length - 3] == '"'
    }

    static func IsTripleQuoteStringLiteral(tokenText: string): bool {
        if tokenText.Length < 6 {
            return false
        }

        return tokenText[0] == '"' && tokenText[1] == '"' && tokenText[2] == '"' && tokenText[tokenText.Length - 1] == '"' && tokenText[tokenText.Length - 2] == '"' && tokenText[tokenText.Length - 3] == '"'
    }

    static func TryDecodeBody(body: string, out decoded: string): bool {
        decoded = ""
        if body.IndexOf('\\') < 0 {
            decoded = body
            return true
        }

        builder := new StringBuilder(body.Length)
        i := 0
        while i < body.Length {
            ch := body[i]
            if ch != '\\' {
                builder.Append(ch)
                i = i + 1
                continue
            }

            if i + 1 >= body.Length {
                return false
            }

            i = i + 1
            next := body[i]
            if next == '\'' {
                builder.Append('\'')
            } else if next == '"' {
                builder.Append('"')
            } else if next == '\\' {
                builder.Append('\\')
            } else if next == '0' {
                builder.Append('\0')
            } else if next == 'a' {
                builder.Append('\a')
            } else if next == 'b' {
                builder.Append('\b')
            } else if next == 'f' {
                builder.Append('\f')
            } else if next == 'n' {
                builder.Append('\n')
            } else if next == 'r' {
                builder.Append('\r')
            } else if next == 't' {
                builder.Append('\t')
            } else if next == 'v' {
                builder.Append('\v')
            } else {
                return false
            }

            i = i + 1
        }

        decoded = builder.ToString()
        return true
    }

    // No-out scalar seam for columnar expression planners. -1 means the body does not decode to
    // exactly one character; every admitted escape remains owned by TryDecodeBody above.
    static func DecodeCharacterBody(body: string): int {
        decoded := ""
        if !TryDecodeBody(body, out decoded) {
            return -1
        }
        if decoded.Length != 1 {
            return -1
        }
        return (int)decoded[0]
    }

    static func DecodeBody(body: string): string {
        if body.IndexOf('\\') < 0 {
            return body
        }

        result := ""
        i := 0
        while i < body.Length {
            ch := body[i]
            if ch != '\\' || i + 1 >= body.Length {
                result = result + body.Substring(i, 1)
                i = i + 1
                continue
            }

            next := body[i + 1]
            if next == '\'' {
                result = result + '\''
                i = i + 2
                continue
            }

            if next == '"' {
                result = result + '"'
                i = i + 2
                continue
            }

            if next == '\\' {
                result = result + '\\'
                i = i + 2
                continue
            }

            if next == '0' {
                result = result + '\0'
                i = i + 2
                continue
            }

            if next == 'a' {
                result = result + '\a'
                i = i + 2
                continue
            }

            if next == 'b' {
                result = result + '\b'
                i = i + 2
                continue
            }

            if next == 'f' {
                result = result + '\f'
                i = i + 2
                continue
            }

            if next == 'n' {
                result = result + '\n'
                i = i + 2
                continue
            }

            if next == 'r' {
                result = result + '\r'
                i = i + 2
                continue
            }

            if next == 't' {
                result = result + '\t'
                i = i + 2
                continue
            }

            if next == 'v' {
                result = result + '\v'
                i = i + 2
                continue
            }

            result = result + body.Substring(i, 1)
            i = i + 1
        }

        return result
    }
}

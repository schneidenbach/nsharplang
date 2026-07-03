namespace NSharpLang.Compiler

import System.Text

public class StringLiteralDecoder {
    public static func Decode(tokenText: string): string {
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

    public static func DecodeInterpolatedText(literal: string, text: string): string {
        if IsInterpolatedRawStringLiteral(literal) {
            return text
        }

        return DecodeBody(text)
    }

    public static func IsInterpolatedRawStringLiteral(tokenText: string): bool {
        if tokenText.Length < 7 {
            return false
        }

        return tokenText[0] == '$' &&
            tokenText[1] == '"' &&
            tokenText[2] == '"' &&
            tokenText[3] == '"' &&
            tokenText[tokenText.Length - 1] == '"' &&
            tokenText[tokenText.Length - 2] == '"' &&
            tokenText[tokenText.Length - 3] == '"'
    }

    public static func IsTripleQuoteStringLiteral(tokenText: string): bool {
        if tokenText.Length < 6 {
            return false
        }

        return tokenText[0] == '"' &&
            tokenText[1] == '"' &&
            tokenText[2] == '"' &&
            tokenText[tokenText.Length - 1] == '"' &&
            tokenText[tokenText.Length - 2] == '"' &&
            tokenText[tokenText.Length - 3] == '"'
    }

    public static func TryDecodeBody(body: string, out decoded: string): bool {
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

    public static func DecodeBody(body: string): string {
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

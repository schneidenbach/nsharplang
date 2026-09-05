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

    // THE ONE ESCAPE TABLE. Reads the escape whose backslash sits at `backslashIndex` and answers its
    // decoded text plus the index just past it, or `false` when N# admits no such escape. Both entry
    // points below route through this, so the strict and tolerant decoders can no longer disagree about
    // WHICH escapes exist — only about what to do with one that does not.
    static func TryReadEscape(body: string, backslashIndex: int, out text: string, out nextIndex: int): bool {
        text = ""
        nextIndex = backslashIndex
        if backslashIndex + 1 >= body.Length {
            return false
        }

        next := body[backslashIndex + 1]
        nextIndex = backslashIndex + 2

        if next == '\'' {
            text = "'"
            return true
        }
        if next == '"' {
            text = "\""
            return true
        }
        if next == '\\' {
            text = "\\"
            return true
        }
        if next == '0' {
            text = ((char)0).ToString()
            return true
        }
        if next == 'a' {
            text = ((char)7).ToString()
            return true
        }
        if next == 'b' {
            text = ((char)8).ToString()
            return true
        }
        if next == 't' {
            text = ((char)9).ToString()
            return true
        }
        if next == 'n' {
            text = ((char)10).ToString()
            return true
        }
        if next == 'v' {
            text = ((char)11).ToString()
            return true
        }
        if next == 'f' {
            text = ((char)12).ToString()
            return true
        }
        if next == 'r' {
            text = ((char)13).ToString()
            return true
        }
        // `\e` is C# 13's escape escape, and the reason this family was opened: an N# program had no way
        // to spell ESC at all, so the compiler's own colour kernel shipped the literal characters.
        if next == 'e' {
            text = ((char)27).ToString()
            return true
        }

        // `\x` takes ONE to FOUR hex digits, greedily — C#'s rule, and the only variable-length escape.
        if next == 'x' {
            value := 0
            digits := 0
            scan := backslashIndex + 2
            while digits < 4 && scan < body.Length && IsAsciiHexDigit(body[scan]) {
                value = value * 16 + HexDigitValue(body[scan])
                digits = digits + 1
                scan = scan + 1
            }
            if digits == 0 {
                return false
            }
            text = ((char)value).ToString()
            nextIndex = scan
            return true
        }

        // `\u` takes EXACTLY four hex digits and `\U` exactly eight; a short run is not a shorter escape,
        // it is not an escape at all.
        if next == 'u' {
            value := 0
            if !TryReadFixedHex(body, backslashIndex + 2, 4, out value) {
                return false
            }
            text = ((char)value).ToString()
            nextIndex = backslashIndex + 6
            return true
        }

        if next == 'U' {
            value := 0
            if !TryReadFixedHex(body, backslashIndex + 2, 8, out value) {
                return false
            }
            // A scalar VALUE, so the surrogate range is not spellable and anything past the last plane is
            // not a character; everything above the BMP arrives as its surrogate pair.
            if value > 1114111 || (value >= 55296 && value <= 57343) {
                return false
            }
            if value > 65535 {
                shifted := value - 65536
                high := 55296 + (shifted / 1024)
                low := 56320 + (shifted % 1024)
                text = ((char)high).ToString() + ((char)low).ToString()
            } else {
                text = ((char)value).ToString()
            }
            nextIndex = backslashIndex + 10
            return true
        }

        nextIndex = backslashIndex
        return false
    }

    static func TryReadFixedHex(body: string, start: int, length: int, out value: int): bool {
        value = 0
        if start + length > body.Length {
            return false
        }

        index := 0
        while index < length {
            ch := body[start + index]
            if !IsAsciiHexDigit(ch) {
                value = 0
                return false
            }

            value = value * 16 + HexDigitValue(ch)
            index = index + 1
        }

        return true
    }

    // ASCII-only, deliberately: `char.IsDigit` admits every Unicode decimal digit, and a Devanagari five
    // is not a hex digit in any language's escape.
    static func IsAsciiHexDigit(ch: char): bool {
        return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
    }

    static func HexDigitValue(ch: char): int {
        if ch >= '0' && ch <= '9' {
            return (int)ch - 48
        }
        if ch >= 'a' && ch <= 'f' {
            return (int)ch - 87
        }
        return (int)ch - 55
    }

    // The STRICT entry point: every escape in the body must be one the table owns, or the whole body is
    // refused. The columnar char planner needs this — a character literal that does not decode is not a
    // character.
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

            text := ""
            nextIndex := 0
            if !TryReadEscape(body, i, out text, out nextIndex) {
                return false
            }

            builder.Append(text)
            i = nextIndex
        }

        decoded = builder.ToString()
        return true
    }

    // No-out scalar seam for columnar expression planners. -1 means the body does not decode to
    // exactly one character; every admitted escape remains owned by TryReadEscape above.
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

    // The TOLERANT entry point, for the lexer's already-scanned token text. It reads the SAME table, so
    // the two decoders agree on every body the strict one admits; where they still differ is only what
    // happens to an escape the table does not own, and that is now a DIAGNOSTIC rather than a silent
    // pass-through — see the unrecognised-escape check in the analyzer.
    static func DecodeBody(body: string): string {
        if body.IndexOf('\\') < 0 {
            return body
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

            text := ""
            nextIndex := 0
            if TryReadEscape(body, i, out text, out nextIndex) {
                builder.Append(text)
                i = nextIndex
                continue
            }

            builder.Append(ch)
            i = i + 1
        }

        return builder.ToString()
    }
}

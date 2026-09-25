namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler

// ONE CLICKABLE SPAN OF A FILE, in the editor's own 0-based numbering, with the text that was
// found there. A URL never spans a line, so `EndLine` is always `StartLine`; the shape carries
// both because that is what the protocol's range asks for.
//
// `Text` is the matched text EXACTLY as the file spells it. Turning it into the protocol's target
// is the caller's job and deliberately not done here: `System.Uri` is the thing that canonicalises
// a URL, and the columnar backend does not construct one yet.
class EditorDocumentLinkRow {
    startLineValue: int
    startCharacterValue: int
    endLineValue: int
    endCharacterValue: int
    textValue: string

    StartLine: int => startLineValue
    StartCharacter: int => startCharacterValue
    EndLine: int => endLineValue
    EndCharacter: int => endCharacterValue
    Text: string => textValue

    constructor(StartLine: int, StartCharacter: int, EndLine: int, EndCharacter: int, Text: string) {
        startLineValue = StartLine
        startCharacterValue = StartCharacter
        endLineValue = EndLine
        endCharacterValue = EndCharacter
        textValue = Text
    }
}

// WHERE A FILE OFFERS SOMETHING TO CLICK, and in what order.
//
// TWO PLACES ARE SEARCHED AND BOTH ARE SEARCHED WHOLE: the token stream, where a link can sit
// inside a line comment, a block comment or a string literal, and the comment trivia the parser
// kept for the formatter, which a token stream handed to an editor does not always carry. A file
// whose comments appear in both is reported twice, and always tokens first — that is the shipped
// order and a client draws the ranges it is given.
//
// THE SPAN IS MEASURED BY WALKING THE MATCHED TEXT, not by re-scanning the file: a block comment
// begins at one line and column, and every newline inside it up to the match moves the answer down
// a line and back to column zero. This is what lets a URL on the third line of a `/* */` block be
// underlined in the right place.
//
// THE SCAN IS WRITTEN OUT RATHER THAN SPELLED AS A REGULAR EXPRESSION. `https?://[^\s)>"']+` is
// what it means and what the editor used to run, but the columnar backend models neither
// `new Regex(...)` nor the two-argument `Regex.Matches`, so the walk is here in full and the rows
// below pin every edge of it — the optional `s` and the backtrack when it does not pan out, the
// four prose characters that close a link, and the requirement that SOMETHING follow the scheme.
class EditorDocumentLinkFacts {
    static func LinkRows(tokens: List<Token>?, comments: List<CommentTrivia>?): List<EditorDocumentLinkRow> {
        rows := new List<EditorDocumentLinkRow>()

        if tokens != null {
            for token in tokens {
                if token.Type == TokenType.Comment || token.Type == TokenType.MultiLineComment || token.Type == TokenType.StringLiteral {
                    AppendRows(token.Value, token.Line, token.Column, rows)
                }
            }
        }

        if comments != null {
            for comment in comments {
                AppendRows(comment.Text, comment.Line, comment.Column, rows)
            }
        }

        return rows
    }

    // Every link inside one piece of text, placed relative to where that text itself begins. Line
    // and column arrive 1-based, as the lexer and the parser both count, and leave 0-based.
    static func AppendRows(text: string, oneBasedLine: int, oneBasedColumn: int, rows: List<EditorDocumentLinkRow>) {
        line := oneBasedLine - 1
        column := oneBasedColumn - 1
        offset := 0
        while offset < text.Length {
            matchEnd := UrlEndAt(text, offset)
            if matchEnd < 0 {
                if text[offset] == '\n' {
                    line = line + 1
                    column = 0
                } else {
                    column = column + 1
                }

                offset = offset + 1
                continue
            }

            // A match never contains a newline — every whitespace character ends it — so the whole
            // span sits on the line the walk has reached.
            rows.Add(new EditorDocumentLinkRow(line, column, line, column + matchEnd - offset, text.Substring(offset, matchEnd - offset)))
            column = column + matchEnd - offset
            offset = matchEnd
        }
    }

    // WHERE A LINK STARTING AT `start` ENDS, exclusive, or -1 when nothing starts there. The
    // optional `s` is tried first and abandoned if `://` does not follow it, which is what makes
    // `https://` and `http://` both match and `httpss://` match neither.
    static func UrlEndAt(text: string, start: int): int {
        if !StartsWithAt(text, start, "http") {
            return -1
        }

        bodyStart := -1
        if StartsWithAt(text, start + 4, "s://") {
            bodyStart = start + 8
        } else if StartsWithAt(text, start + 4, "://") {
            bodyStart = start + 7
        } else {
            return -1
        }

        bodyEnd := bodyStart
        while bodyEnd < text.Length && !ClosesLink(text[bodyEnd]) {
            bodyEnd = bodyEnd + 1
        }

        // The `+` is not a `*`: a scheme with nothing after it is not a link.
        if bodyEnd == bodyStart {
            return -1
        }

        return bodyEnd
    }

    static func StartsWithAt(text: string, start: int, prefix: string): bool {
        if start < 0 || start + prefix.Length > text.Length {
            return false
        }

        index := 0
        while index < prefix.Length {
            if text[start + index] != prefix[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    // WHAT ENDS A LINK: any whitespace, and the four characters that routinely close one in prose.
    // A trailing full stop is NOT one of them, which is why a sentence-final URL keeps its period.
    static func ClosesLink(character: char): bool {
        return Char.IsWhiteSpace(character) || character == ')' || character == '>' || character == '"' || character == '\''
    }
}

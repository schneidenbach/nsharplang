namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text


// One interpolation hole: its text exactly as written between the braces, and the 1-based line and
// column of the first character after the opening brace.
record InterpolationHoleSpan(Text: string, Line: int, Column: int) {
}

// The scan's position as it walks a literal's raw text. A newline resets the column to 1 because a
// raw literal spans source lines and the positions the scan reports are source positions.
class InterpolationHoleCursor {
    Line: int
    Column: int

    constructor(line: int, column: int) {
        Line = line
        Column = column
    }

    func Advance(character: char) {
        if character == '\n' {
            Line = Line + 1
            Column = 1
        } else {
            Column = Column + 1
        }
    }
}

// WHICH VARIABLES AN INTERPOLATED STRING USES.
//
// NL001 ("declared but never read") and NL012 ("unused parameter") both need this: a name that only
// ever appears inside `$"…{name}…"` IS read, and a linter that could not see into the literal would
// squiggle it. The linter reaches this owner from a `StringLiteralExpression`, whose `Value` is the
// literal's RAW SOURCE TEXT — quotes, dollar and all — not its decoded content, so the scan starts
// by deciding what kind of literal it is looking at.
//
// THIS IS A LEXICAL SCAN, NOT A PARSE, AND THAT IS DELIBERATE. The answer feeds a "was it used"
// question, where a false NEGATIVE is a visible wrong squiggle and a false POSITIVE is silence. So
// the scan is generous: it takes the LEADING identifier of every brace-delimited hole and stops at
// the first separator, which means `{obj.Property}` credits `obj`, `{list[0]}` credits `list`,
// `{a + b}` credits `a` and not `b`, and a format specifier (`{value:F2}`) credits `value`. What it
// never does is credit something that is not an identifier at all: `{1 + 2}` and `{"literal"}`
// credit nothing, because `IdentifierText.IsValid` refuses the segment.
//
// NESTING IS COUNTED RATHER THAN ASSUMED. The hole scan tracks brace DEPTH, so an interpolation
// holding another braced construct — `{new Point { X = 1 }}` — ends at its own matching brace and
// not at the first `}` in the text. A brace inside a NESTED STRING (`{dict["}"]}`) is not counted at
// all, because the scan knows when it is inside one. An UNTERMINATED hole (`$"{name`) yields nothing
// rather than yielding the rest of the literal, which is what keeps a half-typed line in the editor
// from crediting a name the developer has not finished writing.
//
// ── THE SCAN ANSWERS WHERE, AND THE LINTER'S QUESTION IS ONE PROJECTION OF IT ──────────────────
//
// `HoleSpans` is the scanner and `HoleTexts` is a view of it. The linter only ever wanted the hole
// TEXTS, so that is all the file used to produce; the semantic-token layer needs to place a token
// inside a hole and therefore needs the hole's LINE and COLUMN as well. Those are the same holes
// found by the same walk — a text cannot drift from its own position — so there is one scanner here
// rather than a lexical one for the linter and an arithmetic one in the editor.
//
// WHAT THE POSITIONS MEAN. `HoleSpans` is handed the literal token's own 1-based line and column and
// returns, for each hole, the position of the FIRST CHARACTER AFTER THE OPENING BRACE, and the hole's
// text UNTRIMMED. A caller that re-lexes the text gets tokens whose own columns are relative to that
// point. A newline inside a raw literal resets the column to 1, exactly as the source does.
//
// THE ESCAPES ARE PART OF THE SCAN, NOT THE CALLER'S JOB. `{{` and `}}` are literal braces and open
// no hole; in a non-raw literal `\x` consumes both characters, so `$"\\{a}"` still finds `{a}` and
// `$"\{a}"` finds none. In a RAW literal a `{` that is a format specifier's brace, or one whose
// matching `}` is missing or on another line, is literal text — the same rule the raw-string lexer
// applies, and the reason a raw literal may contain braces that mean nothing.
class LinterInterpolationScan {

    // The whole contract. Given a string literal's raw source text, the identifiers its
    // interpolation holes read — in source order, with duplicates preserved, because the caller
    // marks each one used and marking twice is not different from marking once.
    static func UsedIdentifiers(value: string): List<string> {
        result := new List<string>()
        holes := HoleTexts(value)
        index := 0
        while index < holes.Count {
            name := LeadingIdentifier(holes[index])
            if name != null {
                result.Add(name)
            }

            index = index + 1
        }

        return result
    }

    // The trimmed text of every balanced `{…}` hole in an interpolated literal, in source order.
    // A literal that is not interpolated has none — including a plain `"…"`, which may well contain
    // braces that mean nothing.
    static func HoleTexts(value: string): List<string> {
        result := new List<string>()
        spans := HoleSpans(value, 1, 1)
        index := 0
        while index < spans.Count {
            result.Add(spans[index].Text.Trim())
            index = index + 1
        }

        return result
    }

    // Every balanced `{…}` hole in an interpolated literal, in source order, each with the 1-based
    // line and column of its first content character. `literalLine`/`literalColumn` are the
    // position of the literal's own opening `$`.
    //
    // An UNTERMINATED hole contributes nothing: the walk that runs off the end leaves the brace
    // depth above zero, and nothing is recorded for it.
    static func HoleSpans(value: string, literalLine: int, literalColumn: int): List<InterpolationHoleSpan> {
        result := new List<InterpolationHoleSpan>()
        if value == null {
            return result
        }

        if !value.StartsWith("$", StringComparison.Ordinal) {
            return result
        }

        // The raw literal's opening delimiter decides where the content starts. A raw interpolated
        // string opens with `$"""`; a normal one with `$"`. Anything else beginning with `$` is not
        // an interpolated string literal at all.
        isRaw := value.StartsWith("$\"\"\"", StringComparison.Ordinal)
        contentStart := 2
        closing := "\""
        if isRaw {
            contentStart = 4
            closing = "\"\"\""
        } else if !value.StartsWith("$\"", StringComparison.Ordinal) {
            return result
        }

        // An UNTERMINATED literal — the half-typed line in the editor — has no closing delimiter to
        // stop before, so the content runs to the end of the text.
        contentEnd := value.Length - closing.Length
        if contentEnd < contentStart || !value.EndsWith(closing, StringComparison.Ordinal) {
            contentEnd = value.Length
        }

        cursor := new InterpolationHoleCursor(literalLine, literalColumn + contentStart)
        index := contentStart
        while index < contentEnd {
            character := value[index]

            // A non-raw literal's backslash escape consumes both characters, so an escaped brace
            // opens no hole.
            if !isRaw && character == '\\' && index + 1 < contentEnd {
                cursor.Advance(character)
                index = index + 1
                cursor.Advance(value[index])
                index = index + 1
                continue
            }

            // `{{` and `}}` are literal braces.
            if (character == '{' || character == '}') && index + 1 < contentEnd && value[index + 1] == character {
                cursor.Advance(character)
                index = index + 1
                cursor.Advance(value[index])
                index = index + 1
                continue
            }

            if character != '{' {
                cursor.Advance(character)
                index = index + 1
                continue
            }

            // In a raw literal a brace that is not opening an interpolation is ordinary text.
            if isRaw && IsRawLiteralBrace(value, contentStart, contentEnd, index) {
                cursor.Advance(character)
                index = index + 1
                continue
            }

            cursor.Advance(character)
            index = index + 1

            holeLine := cursor.Line
            holeColumn := cursor.Column
            hole := new StringBuilder()
            depth := 1
            inNestedString := false

            while index < contentEnd && depth > 0 {
                character = value[index]

                if inNestedString {
                    hole.Append(character)
                    if character == '\\' && index + 1 < contentEnd {
                        cursor.Advance(character)
                        index = index + 1
                        character = value[index]
                        hole.Append(character)
                    } else if character == '"' {
                        inNestedString = false
                    }
                } else if character == '"' {
                    inNestedString = true
                    hole.Append(character)
                } else if character == '{' {
                    depth = depth + 1
                    hole.Append(character)
                } else if character == '}' {
                    depth = depth - 1
                    if depth == 0 {
                        break
                    }

                    hole.Append(character)
                } else {
                    hole.Append(character)
                }

                cursor.Advance(character)
                index = index + 1
            }

            if depth == 0 {
                result.Add(new InterpolationHoleSpan(hole.ToString(), holeLine, holeColumn))
            }

            if index < contentEnd && value[index] == '}' {
                cursor.Advance(value[index])
                index = index + 1
            }
        }

        return result
    }

    // Whether a `{` inside a RAW interpolated literal is ordinary text rather than the start of an
    // interpolation. Three shapes say it is: a brace directly after a `:` (a format specifier), a
    // brace with no `}` after it at all, and a brace whose `}` is on a later line — a raw literal
    // spans lines, and an interpolation does not.
    static func IsRawLiteralBrace(value: string, contentStart: int, contentEnd: int, braceIndex: int): bool {
        previous := braceIndex - 1
        while previous >= contentStart && char.IsWhiteSpace(value[previous]) {
            previous = previous - 1
        }

        if previous >= contentStart && value[previous] == ':' {
            return true
        }

        close := value.IndexOf('}', braceIndex + 1)
        if close < 0 || close >= contentEnd {
            return true
        }

        inner := value.Substring(braceIndex + 1, close - braceIndex - 1)
        return inner.IndexOf('\r') >= 0 || inner.IndexOf('\n') >= 0
    }

    // The identifier a hole reads, or nothing. The leading run up to the first separator, trimmed;
    // null when that run is empty or is not an identifier.
    static func LeadingIdentifier(holeText: string): string? {
        if holeText == null {
            return null
        }

        cut := FirstSeparatorIndex(holeText)
        leading := holeText.Substring(0, cut).Trim()
        if leading.Length == 0 {
            return null
        }

        if !IdentifierText.IsValid(leading) {
            return null
        }

        return leading
    }

    // Where the leading identifier ends: the lowest index at which any separator occurs, or the
    // whole length when none does. The set is the one the rule has always used — member access,
    // null-conditional, indexing, invocation, every binary operator character, and the two
    // characters that open a format specifier or separate arguments.
    static func FirstSeparatorIndex(holeText: string): int {
        separators := ['.', '?', '[', '(', ' ', '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', ':', ',']
        first := holeText.Length
        position := 0
        while position < separators.Length {
            index := holeText.IndexOf(separators[position])
            if index >= 0 && index < first {
                first = index
            }

            position = position + 1
        }

        return first
    }
}

namespace NSharpLang.Compiler.CodeIntelligence

import System

// ONE SQUIGGLE, in the editor's own 0-based numbering, with an EXCLUSIVE end column.
class EditorDiagnosticSpanRow {
    lineValue: int
    startCharacterValue: int
    endCharacterValue: int

    Line: int => lineValue
    StartCharacter: int => startCharacterValue
    EndCharacter: int => endCharacterValue

    constructor(Line: int, StartCharacter: int, EndCharacter: int) {
        lineValue = Line
        startCharacterValue = StartCharacter
        endCharacterValue = EndCharacter
    }
}

// HOW WIDE A DIAGNOSTIC UNDERLINES, AND WHERE.
//
// The compiler reports a diagnostic at a 1-based line and column with a length; the editor draws
// it at 0-based coordinates with an exclusive end. Five rules turn one into the other, and every
// one of them exists because a real diagnostic broke without it:
//
//   * the line and the column are each one less, because the protocol counts from zero;
//   * the end is the start plus the length, exclusive;
//   * a negative line or column is clamped to zero, because a malformed span must not be rejected
//     by the client — the diagnostic still has something to say;
//   * a length below one becomes one, so every diagnostic underlines at least one column;
//   * and when the offending SOURCE LINE is known, the exclusive end is clamped to that line's
//     length so an over-long span cannot draw past the visible end of the line — but never below
//     start + 1, because a zero-width squiggle is invisible.
//
// THE SPAN IS SINGLE-LINE BY CONTRACT. The compiler resolves a length against the offending
// token's own source line, so start and end always share a line; wrapping to the next one would
// need per-line context this answer does not have.
class EditorDiagnosticSpanFacts {

    // The visible length of the FIRST physical line of a snippet. A snippet stores the offending
    // token's source line; a multi-line one clamps against its first line, which is the line the
    // span starts on.
    static func SnippetLineLength(sourceSnippet: string): int {
        position := 0
        while position < sourceSnippet.Length {
            current := sourceSnippet[position]
            if current == '\n' || current == '\r' {
                return position
            }

            position = position + 1
        }

        return sourceSnippet.Length
    }

    static func Span(oneBasedLine: int, oneBasedColumn: int, length: int, sourceSnippet: string?): EditorDiagnosticSpanRow {
        line := Math.Max(0, oneBasedLine - 1)
        startCharacter := Math.Max(0, oneBasedColumn - 1)
        safeLength := Math.Max(1, length)
        endCharacter := startCharacter + safeLength

        if !string.IsNullOrEmpty(sourceSnippet) {
            lineEnd := SnippetLineLength(sourceSnippet ?? "")
            if endCharacter > lineEnd {
                endCharacter = Math.Max(startCharacter + 1, lineEnd)
            }
        }

        return new EditorDiagnosticSpanRow(line, startCharacter, endCharacter)
    }
}

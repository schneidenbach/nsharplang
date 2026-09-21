namespace NSharpLang.Compiler.CodeIntelligence

// CONTRACTS FOR HOW WIDE A SQUIGGLE IS. These came out of `LspDiagnosticConverter.cs`, where the
// five rules were documented in a remarks block and asserted by nothing.
test "a diagnostic span counts from zero and ends exclusively" {
    span := EditorDiagnosticSpanFacts.Span(4, 7, 3, null)

    assert span.Line == 3
    assert span.StartCharacter == 6
    assert span.EndCharacter == 9
}

test "a diagnostic span underlines at least one column" {
    zeroLength := EditorDiagnosticSpanFacts.Span(1, 1, 0, null)
    assert zeroLength.EndCharacter == zeroLength.StartCharacter + 1

    negativeLength := EditorDiagnosticSpanFacts.Span(1, 1, -5, null)
    assert negativeLength.EndCharacter == negativeLength.StartCharacter + 1
}

test "a diagnostic span clamps a malformed position to the start of the document" {
    span := EditorDiagnosticSpanFacts.Span(0, 0, 4, null)

    assert span.Line == 0
    assert span.StartCharacter == 0
    assert span.EndCharacter == 4
}

test "a diagnostic span stops at the visible end of the line it knows" {
    span := EditorDiagnosticSpanFacts.Span(1, 3, 40, "let value = 1")

    assert span.StartCharacter == 2
    assert span.EndCharacter == 13
}

// NEVER COLLAPSED: a span whose start is already past the end of its own line still underlines one
// column, because a zero-width squiggle is invisible.
test "a diagnostic span past the end of its line keeps one column" {
    span := EditorDiagnosticSpanFacts.Span(1, 30, 4, "short")

    assert span.StartCharacter == 29
    assert span.EndCharacter == 30
}

test "a diagnostic span clamps against the first physical line of a snippet" {
    assert EditorDiagnosticSpanFacts.SnippetLineLength("abc\ndefgh") == 3
    assert EditorDiagnosticSpanFacts.SnippetLineLength("abc\r\ndef") == 3
    assert EditorDiagnosticSpanFacts.SnippetLineLength("abcdef") == 6
    assert EditorDiagnosticSpanFacts.SnippetLineLength("") == 0

    span := EditorDiagnosticSpanFacts.Span(2, 1, 99, "abc\ndefghijkl")
    assert span.EndCharacter == 3
}

// AN EMPTY SNIPPET IS NO SNIPPET: the clamp only applies when the source line is actually known.
test "a diagnostic span is not clamped when no source line is known" {
    assert EditorDiagnosticSpanFacts.Span(1, 1, 50, null).EndCharacter == 50
    assert EditorDiagnosticSpanFacts.Span(1, 1, 50, "").EndCharacter == 50
}

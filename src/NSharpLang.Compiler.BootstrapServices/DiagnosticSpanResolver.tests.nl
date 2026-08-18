namespace NSharpLang.Compiler

import System


// THE CANONICAL CONTRACTS FOR `DiagnosticSpanResolver`, IN N#.
//
// These replace `tests/DiagnosticSpanResolverTests.cs`, the last canonical C# assertion layer over
// `DiagnosticSpanResolver.nl`. The resolver decides what a diagnostic UNDERLINES: given the source
// line and a 1-based column, it answers the column to start at and how many characters to cover.
// Every squiggle in the CLI and in the editor is this answer.
//
// THE FOUR GUARANTEES THE DELETED FILE'S HEADER NAMED, AND THEY ARE STILL THE CONTRACT:
// an underline starts on a VISIBLE character, never starts in the MIDDLE of an identifier, covers
// the WHOLE offending token (the full identifier, the whole quoted string, the entire
// multi-character operator), and never collapses to length 0.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The answers are read through
// `CompilerError.WithSnippet`, which returns a dependency-assembly record.
//
// THE FIRST OF THIS BATCH'S TWO MEASURED WALLS, AND WHY EVERY CALL HERE IS LONG. Omitting a defaulted
// parameter declines at `emit.local.initializer` — on static methods, not only on free funcs — so
// `WithSnippet` is spelled at FULL ARITY (`…, length, null, ErrorSeverity.Error`) where the deleted
// C# used named arguments and defaults. Same call, same nine values.
//
// TWO ENTRY POINTS, DELIBERATELY. The deleted file went through `CompilerError.WithSnippet` for
// everything, which is the shape production uses; that is kept. But `WithSnippet` takes a
// NON-nullable snippet, so the resolver's own `sourceLine == null` arm is unreachable from it — the
// rows that need it call `DiagnosticSpanResolver.Resolve` directly, and say so.
//
// THE THREE THINGS IT IS EASY TO GET WRONG:
//
// (1) AN EXPLICIT LENGTH SHORT-CIRCUITS EVERYTHING. `requestedLength > 0` is answered before the
// line is even looked at — so a caller that knows its span keeps it, and only `0` means "infer".
//
// (2) WHITESPACE SNAPS FORWARD FIRST AND BACKWARD SECOND. A column in indentation moves to the NEXT
// visible token; a column in TRAILING whitespace, with nothing after it, moves BACK — and when it
// lands inside an identifier it walks to that identifier's first character rather than underlining
// its tail.
//
// (3) THE OPERATOR TABLE IS ORDERED, LONGEST FIRST. `??=` is matched before `??`, `...` before
// `..`, `:=` before `:` — an unordered table would underline one character of a three-character
// operator and still pass a "never zero length" test.

func DiagnosticSpanContractColumn(sourceLine: string, oneBasedColumn: int): int {
    snippetError := CompilerError.WithSnippet(ErrorCode.InvalidSyntax, "diagnostic", "test.nl", 1, oneBasedColumn, sourceLine, 0, null, ErrorSeverity.Error)
    return snippetError.Column
}

func DiagnosticSpanContractLength(sourceLine: string, oneBasedColumn: int, requestedLength: int): int {
    snippetError := CompilerError.WithSnippet(ErrorCode.InvalidSyntax, "diagnostic", "test.nl", 1, oneBasedColumn, sourceLine, requestedLength, null, ErrorSeverity.Error)
    return snippetError.Length
}

func DiagnosticSpanContractCovers(sourceLine: string, oneBasedColumn: int, expected: string): bool {
    column := DiagnosticSpanContractColumn(sourceLine, oneBasedColumn)
    length := DiagnosticSpanContractLength(sourceLine, oneBasedColumn, 0)
    if column < 1 || column - 1 + length > sourceLine.Length {
        return false
    }

    return sourceLine.Substring(column - 1, length) == expected
}

// "The span the resolver answered lies inside the line it was measured on" — a column past the end
// of the line is out of range by construction and answers itself, so only an IN-range column is
// held to the bound.
func DiagnosticSpanContractInside(sourceLine: string, oneBasedColumn: int): bool {
    column := DiagnosticSpanContractColumn(sourceLine, oneBasedColumn)
    if column < 1 {
        return false
    }

    if column > sourceLine.Length {
        return true
    }

    return column - 1 + DiagnosticSpanContractLength(sourceLine, oneBasedColumn, 0) <= sourceLine.Length
}

// ---- Identifiers ----------------------------------------------------------------------------

// Successor to Identifier_CoversWholeIdentifier.
test "diagnostic span covers a whole identifier" {
    assert DiagnosticSpanContractColumn("let counter = 0", 5) == 5
    assert DiagnosticSpanContractLength("let counter = 0", 5, 0) == 7

    // NOT IN THE DELETED FILE: the covered TEXT is the identifier, which "column 5, length 7" only
    // implies once the two are read together.
    assert DiagnosticSpanContractCovers("let counter = 0", 5, "counter")
}

// Successor to Identifier_WithDigitsAndUnderscore_CoversWholeIdentifier.
test "diagnostic span covers an identifier with digits and an underscore" {
    assert DiagnosticSpanContractColumn("value_2 := other", 1) == 1
    assert DiagnosticSpanContractLength("value_2 := other", 1, 0) == 7
    assert DiagnosticSpanContractCovers("value_2 := other", 1, "value_2")

    // NOT IN THE DELETED FILE: an underscore-led name and a digit-bearing tail, from the middle of
    // the line, where the scan has to stop on both sides.
    assert DiagnosticSpanContractCovers("x := _leading9", 6, "_leading9")
}

// Successor to Identifier_ColumnInLeadingWhitespace_SnapsToVisibleToken.
test "diagnostic span snaps out of leading whitespace to the visible token" {
    assert DiagnosticSpanContractColumn("    print value", 1) == 5
    assert DiagnosticSpanContractLength("    print value", 1, 0) == 5
    assert DiagnosticSpanContractCovers("    print value", 1, "print")

    // NOT IN THE DELETED FILE: a TAB is whitespace too, and every column inside the indentation
    // snaps to the same token rather than only the first.
    assert DiagnosticSpanContractColumn("\tfoo", 1) == 2
    assert DiagnosticSpanContractLength("\tfoo", 1, 0) == 3
    assert DiagnosticSpanContractColumn("    print value", 3) == 5
    assert DiagnosticSpanContractColumn("    print value", 4) == 5
}

// Successor to Keyword_CoversWholeKeyword.
test "diagnostic span covers a whole keyword" {
    assert DiagnosticSpanContractColumn("return result", 1) == 1
    assert DiagnosticSpanContractLength("return result", 1, 0) == 6
    assert DiagnosticSpanContractCovers("return result", 1, "return")
}

// Successor to MemberAccessChain_CoversEntireChain.
test "diagnostic span covers an entire member access chain" {
    assert DiagnosticSpanContractColumn("foo.bar.baz()", 1) == 1
    assert DiagnosticSpanContractLength("foo.bar.baz()", 1, 0) == 11
    assert DiagnosticSpanContractCovers("foo.bar.baz()", 1, "foo.bar.baz")

    // NOT IN THE DELETED FILE: a dot NOT followed by an identifier character ends the chain, so a
    // trailing dot — the shape an unfinished member access has while it is being typed — is not
    // swallowed.
    assert DiagnosticSpanContractCovers("foo.bar.", 1, "foo.bar")
}

// Successor to NullableType_CoversIdentifierAndQuestionMark.
test "diagnostic span covers a nullable type's question mark" {
    assert DiagnosticSpanContractColumn("name int?", 6) == 6
    assert DiagnosticSpanContractLength("name int?", 6, 0) == 4
    assert DiagnosticSpanContractCovers("name int?", 6, "int?")
}

// Successor to NullForgiving_CoversIdentifierAndBang.
test "diagnostic span covers a null forgiving bang" {
    assert DiagnosticSpanContractColumn("use value!", 5) == 5
    assert DiagnosticSpanContractLength("use value!", 5, 0) == 6
    assert DiagnosticSpanContractCovers("use value!", 5, "value!")
}

// Successor to Identifier_DoesNotSwallowFollowingNullConditionalOperator.
test "diagnostic span does not swallow a following null conditional operator" {
    assert DiagnosticSpanContractColumn("a?.b", 1) == 1
    assert DiagnosticSpanContractLength("a?.b", 1, 0) == 1

    // NOT IN THE DELETED FILE: the rule is "a `?` followed by an OPERATOR character is not mine",
    // so the same `?` IS taken when it ends the line, and `?[` — whose bracket is not an operator
    // character — attaches to the name.
    assert DiagnosticSpanContractLength("a?", 1, 0) == 2
    assert DiagnosticSpanContractLength("a?[b]", 1, 0) == 2
    assert DiagnosticSpanContractLength("a!=b", 1, 0) == 1
}

// ---- Numeric literals -----------------------------------------------------------------------

// Successor to IntegerLiteral_CoversWholeNumber.
test "diagnostic span covers a whole integer literal" {
    assert DiagnosticSpanContractColumn("x := 12345", 6) == 6
    assert DiagnosticSpanContractLength("x := 12345", 6, 0) == 5
    assert DiagnosticSpanContractCovers("x := 12345", 6, "12345")
}

// Successor to FloatLiteral_CoversWholeNumberIncludingDecimalPoint.
test "diagnostic span covers a whole float literal" {
    assert DiagnosticSpanContractColumn("x := 3.14", 6) == 6
    assert DiagnosticSpanContractLength("x := 3.14", 6, 0) == 4
    assert DiagnosticSpanContractCovers("x := 3.14", 6, "3.14")
}

// ---- String literals ------------------------------------------------------------------------

// Successor to StringLiteral_CoversQuotesAndContents.
test "diagnostic span covers a string literal with its quotes" {
    snippet := "msg := \"hello world\""
    quoteColumn := snippet.IndexOf('"') + 1

    assert DiagnosticSpanContractColumn(snippet, quoteColumn) == quoteColumn
    assert DiagnosticSpanContractLength(snippet, quoteColumn, 0) == 13
    assert DiagnosticSpanContractCovers(snippet, quoteColumn, "\"hello world\"")
}

// Successor to StringLiteral_WithEscapedQuote_CoversWholeLiteral.
test "diagnostic span covers a string literal with an escaped quote" {
    snippet := "s := \"a\\\"b\""
    quoteColumn := snippet.IndexOf('"') + 1

    assert DiagnosticSpanContractColumn(snippet, quoteColumn) == quoteColumn
    assert DiagnosticSpanContractLength(snippet, quoteColumn, 0) == 6
    assert DiagnosticSpanContractCovers(snippet, quoteColumn, "\"a\\\"b\"")
}

// Successor to InterpolatedString_CoversDollarSignThroughClosingQuote.
test "diagnostic span covers an interpolated string from its dollar sign" {
    snippet := "msg := $\"hi {name}\""
    dollarColumn := snippet.IndexOf('$') + 1

    assert DiagnosticSpanContractColumn(snippet, dollarColumn) == dollarColumn
    assert DiagnosticSpanContractLength(snippet, dollarColumn, 0) == 12
    assert DiagnosticSpanContractCovers(snippet, dollarColumn, "$\"hi {name}\"")

    // NOT IN THE DELETED FILE: a `$` that does NOT open a string is one character, so the
    // dollar-sign arm cannot run away over the rest of the line.
    assert DiagnosticSpanContractLength("$x", 1, 0) == 1
}

// Successor to CharLiteral_CoversQuotesAndContents.
test "diagnostic span covers a char literal with its quotes" {
    snippet := "c := 'x'"
    quoteColumn := snippet.IndexOf('\'') + 1

    assert DiagnosticSpanContractColumn(snippet, quoteColumn) == quoteColumn
    assert DiagnosticSpanContractLength(snippet, quoteColumn, 0) == 3
    assert DiagnosticSpanContractCovers(snippet, quoteColumn, "'x'")
}

// NOT IN THE DELETED FILE. An UNTERMINATED literal — the shape a half-typed string has, and the one
// that a scan looking for a closing quote could run past the end of the line on. It underlines to
// the end of the line, for both quote characters.
test "diagnostic span covers an unterminated literal to the end of the line" {
    assert DiagnosticSpanContractColumn("s := \"abc", 6) == 6
    assert DiagnosticSpanContractLength("s := \"abc", 6, 0) == 4
    assert DiagnosticSpanContractCovers("s := \"abc", 6, "\"abc")

    assert DiagnosticSpanContractLength("c := 'x", 6, 0) == 2
    assert DiagnosticSpanContractLength("\"", 1, 0) == 1
}

// ---- Operators ------------------------------------------------------------------------------

// Successor to the twenty-one TwoCharOperator_CoversWholeOperator rows, expanded element-wise
// because a `with (…) […]` table does not compile under the pinned toolset.
test "diagnostic span covers every two character operator" {
    operators := ["==", "!=", "<=", ">=", "=>", "::", ":=", "&&", "||", "??", "?.", "?[", "<<", ">>", "++", "--", "+=", "-=", "*=", "/=", ".."]

    assert operators.Length == 21

    index := 0
    while index < operators.Length {
        op := operators[index]
        snippet := "a " + op + " b"
        column := snippet.IndexOf(op, StringComparison.Ordinal) + 1

        assert DiagnosticSpanContractColumn(snippet, column) == column, "two-character operator column"
        assert DiagnosticSpanContractLength(snippet, column, 0) == 2, "two-character operator length"
        assert DiagnosticSpanContractCovers(snippet, column, op), "two-character operator text"

        index = index + 1
    }
}

// Successor to the two ThreeCharOperator_CoversWholeOperator rows.
test "diagnostic span covers every three character operator" {
    operators := ["??=", "..."]

    index := 0
    while index < operators.Length {
        op := operators[index]
        snippet := "a " + op + " b"
        column := snippet.IndexOf(op, StringComparison.Ordinal) + 1

        assert DiagnosticSpanContractColumn(snippet, column) == column, "three-character operator column"
        assert DiagnosticSpanContractLength(snippet, column, 0) == 3, "three-character operator length"
        assert DiagnosticSpanContractCovers(snippet, column, op), "three-character operator text"

        index = index + 1
    }
}

// NOT IN THE DELETED FILE. The table is ORDERED, and the order is what these rows measure: the
// three-character operators must be tried before the two-character prefixes they contain, and the
// two-character ones before their single characters. A table sorted the other way underlines `??`
// inside `??=` and passes every row above.
test "diagnostic span prefers the longest operator at a position" {
    assert DiagnosticSpanContractLength("a ??= b", 3, 0) == 3
    assert DiagnosticSpanContractLength("a ?? b", 3, 0) == 2
    assert DiagnosticSpanContractLength("a ... b", 3, 0) == 3
    assert DiagnosticSpanContractLength("a .. b", 3, 0) == 2
    assert DiagnosticSpanContractLength("a . b", 3, 0) == 1
    assert DiagnosticSpanContractLength("a << b", 3, 0) == 2
    assert DiagnosticSpanContractLength("a < b", 3, 0) == 1
    assert DiagnosticSpanContractLength("a := b", 3, 0) == 2
    assert DiagnosticSpanContractLength("a : b", 3, 0) == 1
}

// Successor to Operator_ColumnInLeadingWhitespace_SnapsToOperator.
test "diagnostic span snaps out of whitespace to an operator" {
    snippet := "x  == y"

    assert DiagnosticSpanContractColumn(snippet, 2) == snippet.IndexOf("==", StringComparison.Ordinal) + 1
    assert DiagnosticSpanContractLength(snippet, 2, 0) == 2
    assert DiagnosticSpanContractCovers(snippet, 2, "==")
}

// Successor to the eighteen SingleCharPunctuation_CoversOneChar rows.
test "diagnostic span covers every single character punctuation mark" {
    marks := ["(", ")", "{", "}", "[", "]", ",", ";", "+", "-", "*", "/", "<", ">", "=", ":", "!", "?"]

    assert marks.Length == 18

    index := 0
    while index < marks.Length {
        mark := marks[index]
        snippet := "a " + mark + " b"
        column := snippet.IndexOf(mark, StringComparison.Ordinal) + 1

        assert DiagnosticSpanContractColumn(snippet, column) == column, "punctuation column"
        assert DiagnosticSpanContractLength(snippet, column, 0) == 1, "punctuation length"
        assert DiagnosticSpanContractCovers(snippet, column, mark), "punctuation text"

        index = index + 1
    }
}

// ---- Boundaries -----------------------------------------------------------------------------

// Successor to ColumnPastEndOfLine_ProducesLengthOne.
test "diagnostic span past the end of the line is one character" {
    assert DiagnosticSpanContractColumn("ab", 10) == 10
    assert DiagnosticSpanContractLength("ab", 10, 0) == 1

    // NOT IN THE DELETED FILE: the column just PAST the last character is out of range too, and a
    // zero or negative column — which a 0-based caller would produce — is refused the same way
    // rather than throwing.
    assert DiagnosticSpanContractLength("ab", 3, 0) == 1
    assert DiagnosticSpanContractLength("ab", 0, 0) == 1
    assert DiagnosticSpanContractLength("ab", -3, 0) == 1
}

// Successor to TokenAtEndOfLine_DoesNotOverrun.
test "diagnostic span does not overrun the end of the line" {
    snippet := "value foo"
    column := snippet.IndexOf("foo", StringComparison.Ordinal) + 1

    assert DiagnosticSpanContractColumn(snippet, column) == column
    assert DiagnosticSpanContractLength(snippet, column, 0) == 3
    assert DiagnosticSpanContractCovers(snippet, column, "foo")
}

// Successor to TrailingWhitespaceColumn_SnapsBackToPrecedingToken.
test "diagnostic span snaps back to the preceding token from trailing whitespace" {
    snippet := "result   "

    assert DiagnosticSpanContractColumn(snippet, 8) == 1
    assert DiagnosticSpanContractLength(snippet, 8, 0) == 6
    assert DiagnosticSpanContractCovers(snippet, 8, "result")

    // NOT IN THE DELETED FILE: the backward snap lands on the identifier's FIRST character from
    // every trailing column, which is the "never start in the middle of an identifier" guarantee;
    // and when the preceding visible character is NOT an identifier character it stays where it is.
    assert DiagnosticSpanContractColumn(snippet, 7) == 1
    assert DiagnosticSpanContractColumn(snippet, 9) == 1
    assert DiagnosticSpanContractColumn("a.b   ", 5) == 3
    assert DiagnosticSpanContractLength("a.b   ", 5, 0) == 1
    assert DiagnosticSpanContractColumn("a;   ", 4) == 2
}

// NOT IN THE DELETED FILE. A line with NOTHING visible on it: the forward snap finds nothing, the
// backward snap finds nothing, and the answer falls back to the requested column at length one.
test "diagnostic span on a blank line keeps the requested column" {
    assert DiagnosticSpanContractColumn("   ", 2) == 2
    assert DiagnosticSpanContractLength("   ", 2, 0) == 1
    assert DiagnosticSpanContractColumn("\t\t", 1) == 1
    assert DiagnosticSpanContractLength("\t\t", 1, 0) == 1
}

// Successor to ExplicitRequestedLength_IsHonored.
test "diagnostic span honours an explicit requested length" {
    assert DiagnosticSpanContractColumn("anything here", 3) == 3
    assert DiagnosticSpanContractLength("anything here", 3, 4) == 4

    // The requested length does not move the COLUMN: both halves of the answer are read off one
    // call, which is how the deleted file asserted it.
    honoured := DiagnosticSpanResolver.Resolve("anything here", 3, 4)
    assert honoured.Column == 3
    assert honoured.Length == 4

    // NOT IN THE DELETED FILE: an explicit length short-circuits BEFORE the line is inspected, so
    // it survives a column that is out of range entirely; and only a POSITIVE length counts —
    // a negative one falls through to inference rather than being honoured or clamped to itself.
    assert DiagnosticSpanContractLength("ab", 40, 7) == 7
    assert DiagnosticSpanContractLength("anything here", 3, 1) == 1
    assert DiagnosticSpanContractLength("let counter = 0", 5, -3) == 7
}

// Successor to EmptySourceLine_ProducesLengthOne.
test "diagnostic span on an empty line is one character" {
    assert DiagnosticSpanContractColumn("", 1) == 1
    assert DiagnosticSpanContractLength("", 1, 0) == 1
}

// NOT IN THE DELETED FILE, AND NOT REACHABLE THROUGH `WithSnippet` AT ALL: its snippet parameter is
// non-nullable, so the resolver's own `sourceLine == null` arm is asked directly. A diagnostic
// raised with no source text still underlines one character at the reported column.
test "diagnostic span with no source line is one character" {
    missing := DiagnosticSpanResolver.Resolve(null, 5, 0)
    assert missing.Column == 5
    assert missing.Length == 1

    // The explicit-length short circuit is answered before the null check, so it survives it.
    requested := DiagnosticSpanResolver.Resolve(null, 5, 3)
    assert requested.Column == 5
    assert requested.Length == 3

    // And the direct entry point agrees with the `WithSnippet` route on an ordinary line.
    direct := DiagnosticSpanResolver.Resolve("value foo", 7, 0)
    assert direct.Column == 7
    assert direct.Length == 3
}

// Successor to Resolve_NeverProducesZeroLength.
test "diagnostic span is never zero length" {
    samples := ["let x = 1", "    spaced", "a == b", "foo.bar.baz", "\"string\"", "$\"interp {x}\"", "obj?.member", "i++", "value!", "int?", ";", ""]

    assert samples.Length == 12

    sampleIndex := 0
    while sampleIndex < samples.Length {
        sample := samples[sampleIndex]
        limit := sample.Length
        if limit < 1 {
            limit = 1
        }

        column := 1
        while column <= limit + 2 {
            assert DiagnosticSpanContractLength(sample, column, 0) >= 1, "length must never be zero"

            // NOT IN THE DELETED FILE: the answered COLUMN is positive too, and the span never
            // runs past the end of the line it was measured on — a length alone cannot say that.
            assert DiagnosticSpanContractColumn(sample, column) >= 1, "column must stay positive"
            assert DiagnosticSpanContractInside(sample, column), "span must stay inside the line"

            column = column + 1
        }

        sampleIndex = sampleIndex + 1
    }
}

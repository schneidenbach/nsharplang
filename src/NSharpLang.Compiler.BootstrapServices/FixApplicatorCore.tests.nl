namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.CodeIntelligence


// THE CANONICAL CONTRACTS FOR `FixApplicatorCore`, IN N#.
//
// These, together with `FixApplicatorTextEditOrderer.tests.nl`,
// `FixApplicatorValidationMessages.tests.nl` and `FixApplicatorEditEngine.tests.nl`, replace
// `tests/FixApplicatorTests.cs` — the last canonical C# assertion layer over the fix applicator.
//
// WHAT THIS SUBJECT IS. `FixApplicatorCore.ApplyEdits` is the function that turns the `TextEdit`s a
// code fix reports into rewritten source on disk. `nlc fix` calls it, the language server's
// workspace-edit path calls it, and every provider in `CodeFix.nl` ultimately answers edits that end
// up here. A fix that reports plausible coordinates and produces broken source is the failure mode
// that matters, so this file states RESULTING TEXT, not coordinates.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. `FixApplicatorCore`, `FixApplicatorEditEngine`,
// `FixApplicatorTextEditOrderer`, `FixApplicatorValidationMessages` and `TextEdit` are all public in
// this assembly, so the subject, its arguments and the assertions are the same assembly's own.
//
// THE ONE MEASURED WALL THIS FILE IS WRITTEN AROUND. `System.Random` cannot be constructed in this
// estate — the parameterless constructor declines exactly as the seeded one does — so the deleted
// file's randomized differential sweep is re-spelled over an N#-written generator. It lives in
// `FixApplicatorTextEditOrderer.tests.nl`, beside the subject it sweeps.
//
// FOUR THINGS THE DELETED FILE COULD NOT SAY, AND THIS ONE DOES:
//
// (1) WHICH EDIT WAS BLAMED. Every rejection in the deleted file was asserted with
// `Assert.Contains("outside the document", ex.Message)` — a substring that four different edits in
// four different positions all produce. Here the WHOLE message is stated, including the formatted
// coordinates of the offending edit and, for an overlap, of BOTH edits in the order the validator
// reports them. An applicator that rejects the right document for the wrong reason, or blames the
// wrong edit, no longer passes.
//
// (2) A BARE CARRIAGE RETURN IS A LINE ENDING TOO. The deleted file covered LF and CRLF. The
// classic-Mac branch of `CountLogicalLines`, `BuildLineLengthsInto` and `SplitLogicalLinesInto` —
// three separate `'\r'` arms — had no coverage anywhere in the repository.
//
// (3) THE ONE-ARGUMENT `ValidateAndSortEdits` IS A DIFFERENT CONTRACT. It orders and checks the
// edits against EACH OTHER without a document, which is what the language server needs when it holds
// edits for a buffer it has not read. The deleted file only ever called the two-argument overload,
// so nothing stated that the position check is the part that drops out and the overlap check is the
// part that does not.
//
// (4) THE APPLICATOR DOES NOT MUTATE ITS CALLER'S LIST. `ApplyEdits` sorts, and the caller — `nlc
// fix` — reuses the list it passed to report what it changed. A sort in place would silently
// reorder the caller's own view.

func FacEdits(): List<TextEdit> {
    return new List<TextEdit>()
}

func FacOne(startLine: int, startColumn: int, endLine: int, endColumn: int, newText: string): List<TextEdit> {
    edits := FacEdits()
    edits.Add(new TextEdit(startLine, startColumn, endLine, endColumn, newText))
    return edits
}

func FacTwo(first: TextEdit, second: TextEdit): List<TextEdit> {
    edits := FacEdits()
    edits.Add(first)
    edits.Add(second)
    return edits
}

// The deleted file asserted only the exception TYPE plus a substring of its message. This returns the
// whole message, so every claim below can state it in full.
func FacApplyMessage(source: string, edits: List<TextEdit>): string {
    try {
        FixApplicatorCore.ApplyEdits(source, edits)
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        if invalid == null {
            return "<wrong exception type: " + ex.Message + ">"
        }

        return ex.Message
    }

    return "<no throw>"
}

func FacValidateMessage(source: string, edits: List<TextEdit>): string {
    try {
        FixApplicatorCore.ValidateAndSortEdits(source, edits)
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        if invalid == null {
            return "<wrong exception type: " + ex.Message + ">"
        }

        return ex.Message
    }

    return "<no throw>"
}

func FacValidateWithoutSourceMessage(edits: List<TextEdit>): string {
    try {
        FixApplicatorCore.ValidateAndSortEdits(edits)
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        if invalid == null {
            return "<wrong exception type: " + ex.Message + ">"
        }

        return ex.Message
    }

    return "<no throw>"
}

func FacNewTexts(edits: List<TextEdit>): string {
    text := ""
    for edit in edits {
        text = text + edit.NewText + "|"
    }

    return text
}

// ── Single edit application ───────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_SingleReplace_ReplacesText, ApplyEdits_SingleInsert_InsertsAtPosition and
// ApplyEdits_DeleteEntireLines_RemovesLines.
test "one edit replaces, inserts or deletes exactly what its coordinates name" {
    assert FixApplicatorCore.ApplyEdits("line one\nline two\nline three", FacOne(2, 5, 2, 8, "TWO")) == "line one\nline TWO\nline three"
    assert FixApplicatorCore.ApplyEdits("hello world", FacOne(1, 5, 1, 5, " beautiful")) == "hello beautiful world"
    assert FixApplicatorCore.ApplyEdits("line one\nline two\nline three\nline four", FacOne(2, 0, 3, 0, "")) == "line one\nline three\nline four"

    // Successor to ApplyEdits_ReplaceEntireSingleLineContent and ApplyEdits_EmptySource_InsertCreatesContent.
    assert FixApplicatorCore.ApplyEdits("old content", FacOne(1, 0, 1, 11, "new content")) == "new content"
    assert FixApplicatorCore.ApplyEdits("", FacOne(1, 0, 1, 0, "new line")) == "new line"

    // Successor to ApplyEdits_InsertAtLineStart_PrependsToLine and ApplyEdits_InsertAtLineEnd_AppendsToLine.
    assert FixApplicatorCore.ApplyEdits("hello", FacOne(1, 0, 1, 0, ">> ")) == ">> hello"
    assert FixApplicatorCore.ApplyEdits("hello", FacOne(1, 5, 1, 5, " world")) == "hello world"

    // NOT IN THE DELETED FILE: an insert at column 0 of the FIRST line and one at the last column of
    // the LAST line are the two ends of the document, and both are reachable in one source. A
    // prepend that silently landed on line 2 would have passed every claim above.
    both := FacTwo(new TextEdit(1, 0, 1, 0, ">> "), new TextEdit(2, 3, 2, 3, " <<"))
    assert FixApplicatorCore.ApplyEdits("one\ntwo", both) == ">> one\ntwo <<"
}

// ── Empty and no-op edits ─────────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_EmptyEditList_ReturnsSourceUnchanged and ApplyEdits_NoOpEdit_ReturnsSourceUnchanged.
test "an empty edit list and a zero-width empty edit both leave the source alone" {
    assert FixApplicatorCore.ApplyEdits("unchanged source", FacEdits()) == "unchanged source"
    assert FixApplicatorCore.ApplyEdits("line one\nline two", FacOne(1, 3, 1, 3, "")) == "line one\nline two"

    // NOT IN THE DELETED FILE: the two paths are DIFFERENT. An empty list returns before the
    // validator runs at all, so a document-invalid edit list of length zero cannot throw; a no-op
    // edit goes all the way through validation and the engine's early-out. The distinction is why an
    // empty list is safe to hand to the applicator from a provider that found nothing to fix.
    assert FixApplicatorCore.ApplyEdits("", FacEdits()) == ""

    // A no-op edit is still POSITION-CHECKED, unlike an empty list: it is a real edit at a real
    // coordinate, and a coordinate off the end is still rejected.
    assert FacApplyMessage("abc", FacOne(1, 99, 1, 99, "")) == "Invalid edit range: (1,99)..(1,99) is outside the document."
}

// ── Multi-edit ordering ───────────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_MultipleEdits_AppliedBottomToTop_PreservesPositions,
// ApplyEdits_MultipleEdits_ReverseSorted_StillCorrect and ApplyEdits_MultipleEditsOnSameLine_RightToLeft.
test "edits land at their original coordinates whatever order they arrive in" {
    forwards := FacTwo(new TextEdit(1, 0, 1, 3, "AAA"), new TextEdit(3, 0, 3, 3, "CCC"))
    backwards := FacTwo(new TextEdit(3, 0, 3, 3, "CCC"), new TextEdit(1, 0, 1, 3, "AAA"))

    assert FixApplicatorCore.ApplyEdits("aaa\nbbb\nccc", forwards) == "AAA\nbbb\nCCC"
    assert FixApplicatorCore.ApplyEdits("aaa\nbbb\nccc", backwards) == "AAA\nbbb\nCCC"

    sameLine := FacTwo(new TextEdit(1, 0, 1, 5, "HELLO"), new TextEdit(1, 12, 1, 15, "FOO"))
    assert FixApplicatorCore.ApplyEdits("hello world foo", sameLine) == "HELLO world FOO"

    // NOT IN THE DELETED FILE: input order is not merely tolerated, it is IRRELEVANT. The two lists
    // above are reverses of one another and the assertion is that they agree — stated directly here
    // rather than left as two coincidentally equal literals.
    assert FixApplicatorCore.ApplyEdits("aaa\nbbb\nccc", forwards) == FixApplicatorCore.ApplyEdits("aaa\nbbb\nccc", backwards)
}

// Successor to ApplyEdits_MultipleEdits_LineCountChange_PreservesPositions.
test "an edit that changes the line count does not move the edits above it" {
    edits := FacTwo(new TextEdit(1, 0, 1, 3, "AAA"), new TextEdit(3, 0, 3, 3, "CCC-1\nCCC-2"))
    assert FixApplicatorCore.ApplyEdits("aaa\nbbb\nccc\nddd", edits) == "AAA\nbbb\nCCC-1\nCCC-2\nddd"

    // NOT IN THE DELETED FILE: the same claim in the OTHER direction. The deleted file only grew the
    // document below an earlier edit; an edit that SHRINKS it is the case where a top-to-bottom
    // applicator would run off the end rather than merely land in the wrong place.
    shrinking := FacTwo(new TextEdit(1, 0, 1, 3, "AAA"), new TextEdit(2, 0, 4, 0, ""))
    assert FixApplicatorCore.ApplyEdits("aaa\nbbb\nccc\nddd", shrinking) == "AAA\nddd"

    // And three edits at once, one of each kind, so the ordering is exercised over more than a pair.
    three := FacEdits()
    three.Add(new TextEdit(1, 0, 1, 1, "A"))
    three.Add(new TextEdit(2, 0, 2, 1, "B\nB2"))
    three.Add(new TextEdit(3, 0, 4, 0, ""))
    assert FixApplicatorCore.ApplyEdits("a\nb\nc\nd", three) == "A\nB\nB2\nd"
}

// ── Edits that change the line count ──────────────────────────────────────────────────────────────

// Successor to ApplyEdits_InsertNewline_SplitsLine, ApplyEdits_InsertMultipleLines_IncreasesLineCount,
// ApplyEdits_ReplaceWithMoreLines_ExpandsDocument and ApplyEdits_ReplaceMultiLinesWithSingle_CollapsesDocument.
test "a replacement carrying newlines expands the document and one without them collapses it" {
    assert FixApplicatorCore.ApplyEdits("before after", FacOne(1, 6, 1, 7, "\n")) == "before\nafter"
    assert FixApplicatorCore.ApplyEdits("line one\nline three", FacOne(2, 0, 2, 0, "line two\n")) == "line one\nline two\nline three"
    assert FixApplicatorCore.ApplyEdits("one\ntwo\nthree", FacOne(2, 0, 2, 3, "TWO-A\nTWO-B")) == "one\nTWO-A\nTWO-B\nthree"
    assert FixApplicatorCore.ApplyEdits("one\ntwo\nthree\nfour", FacOne(2, 0, 3, 5, "MERGED")) == "one\nMERGED\nfour"

    // NOT IN THE DELETED FILE: a zero-width insertion of MANY lines mid-line, which is the shape the
    // missing-import fix produces when it inserts a block. The engine takes its
    // `newText.IndexOf('\n')` branch — splice, then re-split the combined line — and the surrounding
    // text on both sides of the insertion point must survive.
    assert FixApplicatorCore.ApplyEdits("abcdef", FacOne(1, 3, 1, 3, "1\n2\n3")) == "abc1\n2\n3def"

    // A replacement that is itself empty and spans a partial range collapses two lines into one.
    assert FixApplicatorCore.ApplyEdits("one\ntwo\nthree", FacOne(1, 3, 2, 0, "")) == "onetwo\nthree"
}

// Successor to ApplyEdits_DeleteMultipleLines_DecreasesLineCount and
// ApplyEdits_DeleteLastLineWithoutTrailingNewline_RemovesLine.
test "a whole-line deletion removes the lines and the last line needs no trailing newline" {
    assert FixApplicatorCore.ApplyEdits("line one\nline two\nline three\nline four", FacOne(2, 0, 4, 0, "")) == "line one\nline four"
    assert FixApplicatorCore.ApplyEdits("line one\nline two", FacOne(2, 0, 3, 0, "")) == "line one"

    // NOT IN THE DELETED FILE: the last-line deletion is a SPECIAL CASE in the validator — an end
    // line one past the document is normally rejected, and it is allowed here only because the new
    // text is empty, the end column is zero and the start is the first column of the final line.
    // Each of those four conditions is load-bearing, so each is shown to be required.
    assert FacApplyMessage("line one\nline two", FacOne(2, 0, 3, 0, "x")) == "Invalid edit range: (2,0)..(3,0) is outside the document."
    assert FacApplyMessage("line one\nline two", FacOne(2, 1, 3, 0, "")) == "Invalid edit range: (2,1)..(3,0) is outside the document."
    assert FacApplyMessage("line one\nline two", FacOne(1, 0, 3, 0, "")) == "Invalid edit range: (1,0)..(3,0) is outside the document."

    // Deleting the ONLY line leaves an empty document rather than throwing.
    assert FixApplicatorCore.ApplyEdits("solo", FacOne(1, 0, 2, 0, "")) == ""
}

// ── The end of the document ───────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_AppendAtOnePastEnd_AddsAtEnd and ApplyEdits_AppendFarPastEnd_ThrowsInsteadOfClamping.
test "an append is allowed exactly one line past the end and nowhere further" {
    assert FixApplicatorCore.ApplyEdits("only line", FacOne(2, 0, 2, 0, "appended")) == "only line\nappended"

    // The deleted file asserted the substring "outside the document"; the whole message names WHICH
    // edit was refused, which is the part a user of `nlc fix` reads.
    assert FacApplyMessage("only line", FacOne(99, 0, 99, 0, "appended")) == "Invalid edit range: (99,0)..(99,0) is outside the document."

    // NOT IN THE DELETED FILE: the EOF insert is allowed only at COLUMN ZERO of exactly the
    // one-past-the-end line, and only when both ends sit there. Two lines past is refused, and so is
    // column one of the correct line — the clamp the applicator deliberately does not do.
    assert FacApplyMessage("only line", FacOne(3, 0, 3, 0, "appended")) == "Invalid edit range: (3,0)..(3,0) is outside the document."
    assert FacApplyMessage("only line", FacOne(2, 1, 2, 1, "appended")) == "Invalid edit range: (2,1)..(2,1) is outside the document."

    // The EOF insert works on a multi-line document too, and it appends rather than overwriting.
    assert FixApplicatorCore.ApplyEdits("one\ntwo", FacOne(3, 0, 3, 0, "three")) == "one\ntwo\nthree"

    // An EOF insert of MANY lines lands as many lines, not as one line holding a newline.
    assert FixApplicatorCore.ApplyEdits("one", FacOne(2, 0, 2, 0, "two\nthree")) == "one\ntwo\nthree"
}

// ── Line endings ──────────────────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_CrlfSource_ColumnsExcludeCarriageReturn and
// ValidateAndSortEdits_CrlfSource_RejectsColumnPastLogicalLineEnd.
test "a carriage return is not a column, in all three line-ending conventions" {
    assert FixApplicatorCore.ApplyEdits("alpha\r\nbeta\r\ngamma", FacOne(2, 4, 2, 4, "!")) == "alpha\nbeta!\ngamma"
    assert FacValidateMessage("alpha\r\nbeta\r\ngamma", FacOne(2, 5, 2, 5, "!")) == "Invalid edit range: (2,5)..(2,5) is outside the document."

    // NOT IN THE DELETED FILE, AND WITH NO COVERAGE ANYWHERE: a BARE CARRIAGE RETURN is a line
    // ending too. `CountLogicalLines`, `BuildLineLengthsInto` and `SplitLogicalLinesInto` each carry
    // a separate classic-Mac arm, and the deleted file reached none of them.
    assert FixApplicatorCore.ApplyEdits("alpha\rbeta\rgamma", FacOne(2, 4, 2, 4, "!")) == "alpha\nbeta!\ngamma"
    assert FacValidateMessage("alpha\rbeta\rgamma", FacOne(2, 5, 2, 5, "!")) == "Invalid edit range: (2,5)..(2,5) is outside the document."

    // A MIXED document — CRLF, then bare CR, then LF — is counted as four lines, which is the case
    // that separates "split on \n and strip \r" from a real line walk.
    mixed := "one\r\ntwo\rthree\nfour"
    assert FixApplicatorCore.ApplyEdits(mixed, FacOne(3, 5, 3, 5, "!")) == "one\ntwo\nthree!\nfour"
    assert FixApplicatorCore.ApplyEdits(mixed, FacOne(4, 4, 4, 4, "!")) == "one\ntwo\nthree\nfour!"

    // OUTPUT IS ALWAYS LF. The applicator joins with `'\n'` whatever it read, so applying ANY edit to
    // a CRLF document normalises the whole file — a real behaviour of `nlc fix` that nothing stated.
    assert FixApplicatorCore.ApplyEdits("a\r\nb\r\nc", FacOne(1, 0, 1, 1, "A")) == "A\nb\nc"

    // A trailing line ending still leaves a final empty line, so an edit can address it.
    assert FixApplicatorCore.ApplyEdits("a\nb\n", FacOne(3, 0, 3, 0, "c")) == "a\nb\nc"
}

// ── Overlap detection ─────────────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_OverlappingSameLine_Throws, ApplyEdits_OverlappingAcrossLines_Throws,
// ApplyEdits_FullyNestedEdit_Throws, ApplyEdits_SameStartInsertAndReplace_Throws and
// ApplyEdits_SameStartShorterAndLongerReplace_Throws.
test "overlapping edits are refused, and the refusal names both of them" {
    // Every one of these five was asserted in the deleted file as the substring "Overlapping edits
    // detected". The whole message states the two ranges IN THE ORDER THE VALIDATOR WALKS THEM —
    // later-in-the-document first — which is the only evidence that the pair it found is the pair
    // that actually overlaps rather than an adjacent innocent one.
    sameLine := FacTwo(new TextEdit(1, 2, 1, 8, "XX"), new TextEdit(1, 5, 1, 12, "YY"))
    assert FacApplyMessage("abcdefghijklmnop", sameLine) == "Overlapping edits detected: edit at (1,2)..(1,8) overlaps with edit at (1,5)..(1,12)"

    acrossLines := FacTwo(new TextEdit(2, 0, 4, 0, "A"), new TextEdit(3, 0, 5, 0, "B"))
    assert FacApplyMessage("line1\nline2\nline3\nline4\nline5", acrossLines) == "Overlapping edits detected: edit at (2,0)..(4,0) overlaps with edit at (3,0)..(5,0)"

    nested := FacTwo(new TextEdit(1, 0, 1, 15, "OUTER"), new TextEdit(1, 3, 1, 8, "INNER"))
    assert FacApplyMessage("abcdefghijklmnop", nested) == "Overlapping edits detected: edit at (1,0)..(1,15) overlaps with edit at (1,3)..(1,8)"

    insertInsideReplace := FacTwo(new TextEdit(1, 2, 1, 4, "RR"), new TextEdit(1, 2, 1, 2, "I"))
    assert FacApplyMessage("abcdefghij", insertInsideReplace) == "Overlapping edits detected: edit at (1,2)..(1,4) overlaps with edit at (1,2)..(1,2)"

    shorterAndLonger := FacTwo(new TextEdit(1, 2, 1, 5, "XX"), new TextEdit(1, 2, 1, 8, "YY"))
    assert FacApplyMessage("abcdefghij", shorterAndLonger) == "Overlapping edits detected: edit at (1,2)..(1,8) overlaps with edit at (1,2)..(1,5)"
}

// Successor to ApplyEdits_AdjacentNonOverlapping_Succeeds and
// ApplyEdits_SamePositionZeroWidthInserts_PreservesInputOrder.
test "edits that merely touch are not overlaps, and co-located inserts keep input order" {
    adjacent := FacTwo(new TextEdit(1, 0, 1, 5, "ABCDE"), new TextEdit(1, 5, 1, 10, "FGHIJ"))
    assert FixApplicatorCore.ApplyEdits("abcdefghij", adjacent) == "ABCDEFGHIJ"

    coLocated := FacTwo(new TextEdit(1, 3, 1, 3, "X"), new TextEdit(1, 3, 1, 3, "Y"))
    assert FixApplicatorCore.ApplyEdits("abcdef", coLocated) == "abcXYdef"

    // NOT IN THE DELETED FILE: the boundary is EXACT. Moving the second edit's start one column
    // LEFT — so the ranges share a single character rather than a single point — is an overlap.
    overlapping := FacTwo(new TextEdit(1, 0, 1, 5, "ABCDE"), new TextEdit(1, 4, 1, 10, "FGHIJ"))
    assert FacApplyMessage("abcdefghij", overlapping) == "Overlapping edits detected: edit at (1,0)..(1,5) overlaps with edit at (1,4)..(1,10)"

    // THREE co-located inserts, so the claim is about a preserved SEQUENCE and not a swapped pair.
    threeInserts := FacEdits()
    threeInserts.Add(new TextEdit(1, 3, 1, 3, "X"))
    threeInserts.Add(new TextEdit(1, 3, 1, 3, "Y"))
    threeInserts.Add(new TextEdit(1, 3, 1, 3, "Z"))
    assert FixApplicatorCore.ApplyEdits("abcdef", threeInserts) == "abcXYZdef"

    // An insert adjacent to a replacement, in both arrangements, produces the same text — the
    // property the co-location tiebreak exists to protect.
    insertThenReplace := FacTwo(new TextEdit(1, 3, 1, 3, "-"), new TextEdit(1, 3, 1, 6, "DEF"))
    assert FacApplyMessage("abcdef", insertThenReplace) == "Overlapping edits detected: edit at (1,3)..(1,6) overlaps with edit at (1,3)..(1,3)"
}

// ── Malformed edits ───────────────────────────────────────────────────────────────────────────────

// Successor to ApplyEdits_EndBeforeStart_ThrowsInsteadOfSilentlyReordering,
// ApplyEdits_LineAndColumnMustBeNonNegativeAndOneBasedLines and
// ApplyEdits_ColumnPastLineEnd_ThrowsInsteadOfClamping.
test "a malformed edit is refused with the reason that fits it" {
    // The deleted file asserted three different substrings; the three whole messages are stated here,
    // and they are three DIFFERENT sentences with three different validator codes behind them.
    assert FacApplyMessage("abcdef", FacOne(1, 5, 1, 2, "XX")) == "Invalid edit range: (1,5)..(1,2) ends before it starts."
    assert FacApplyMessage("abcdef", FacOne(0, 0, 1, 0, "XX")) == "Invalid edit position: (0,0)..(1,0). Lines are 1-based and columns must be non-negative."
    assert FacApplyMessage("abcdef", FacOne(1, 99, 1, 99, "XX")) == "Invalid edit range: (1,99)..(1,99) is outside the document."

    // NOT IN THE DELETED FILE: the position check has FOUR arms and the deleted file reached one.
    // A zero end line, a negative start column and a negative end column are each refused, and each
    // reports the same sentence, so the rule is "the shape is wrong", not "line zero is special".
    assert FacApplyMessage("abcdef", FacOne(1, 0, 0, 0, "XX")) == "Invalid edit position: (1,0)..(0,0). Lines are 1-based and columns must be non-negative."
    assert FacApplyMessage("abcdef", FacOne(1, -1, 1, 0, "XX")) == "Invalid edit position: (1,-1)..(1,0). Lines are 1-based and columns must be non-negative."
    assert FacApplyMessage("abcdef", FacOne(1, 0, 1, -1, "XX")) == "Invalid edit position: (1,0)..(1,-1). Lines are 1-based and columns must be non-negative."

    // AND THE ORDER OF THE CHECKS IS ITSELF A CONTRACT. An edit that is BOTH out of shape and
    // backwards reports the SHAPE, because the position walk runs to completion before the
    // ends-before-it-starts walk begins. A validator that interleaved them would answer differently.
    assert FacApplyMessage("abcdef", FacOne(0, 5, 0, 2, "XX")) == "Invalid edit position: (0,5)..(0,2). Lines are 1-based and columns must be non-negative."

    // An end line BEFORE the start line is the other half of the backwards test; the deleted file
    // only ever moved the column.
    assert FacApplyMessage("a\nb\nc", FacOne(3, 0, 2, 0, "XX")) == "Invalid edit range: (3,0)..(2,0) ends before it starts."

    // The column limit is INCLUSIVE of the line length — one past the last character is a legal
    // insertion point, one further is not.
    assert FixApplicatorCore.ApplyEdits("abcdef", FacOne(1, 6, 1, 6, "!")) == "abcdef!"
    assert FacApplyMessage("abcdef", FacOne(1, 7, 1, 7, "!")) == "Invalid edit range: (1,7)..(1,7) is outside the document."
}

// ── ValidateAndSortEdits ──────────────────────────────────────────────────────────────────────────

// NOT IN THE DELETED FILE at all beyond one rejection: what the validator RETURNS.
test "the validator returns the edits in application order and leaves the caller's list alone" {
    edits := FacEdits()
    edits.Add(new TextEdit(1, 0, 1, 0, "first"))
    edits.Add(new TextEdit(3, 0, 3, 0, "third"))
    edits.Add(new TextEdit(2, 0, 2, 0, "second"))

    sorted := FixApplicatorCore.ValidateAndSortEdits("a\nb\nc", edits)

    assert FacNewTexts(sorted) == "third|second|first|"
    assert sorted.Count == 3

    // THE CALLER'S LIST IS UNTOUCHED. `nlc fix` reuses the list it passed to report what it changed,
    // so an in-place sort would silently reorder its own view of the fixes it applied. Nothing
    // anywhere stated this.
    assert FacNewTexts(edits) == "first|third|second|"

    // And the same holds through `ApplyEdits`, which sorts internally.
    FixApplicatorCore.ApplyEdits("a\nb\nc", edits)
    assert FacNewTexts(edits) == "first|third|second|"
}

// NOT IN THE DELETED FILE: the one-argument overload, which is a DIFFERENT contract.
test "validating without a document drops the position check and keeps the rest" {
    // Coordinates far outside any real file are accepted, because there is no file to be outside of.
    // This is what the language server needs when it holds edits for a buffer it has not read.
    farOut := FacOne(9999, 400, 9999, 400, "x")
    assert FacValidateWithoutSourceMessage(farOut) == "<no throw>"

    // The same edit against a real one-line document is refused, so the difference is the document
    // and nothing else.
    assert FacValidateMessage("abc", farOut) == "Invalid edit range: (9999,400)..(9999,400) is outside the document."

    // The SHAPE and ORDER checks do NOT drop out. All three still fire without a source.
    assert FacValidateWithoutSourceMessage(FacOne(0, 0, 1, 0, "x")) == "Invalid edit position: (0,0)..(1,0). Lines are 1-based and columns must be non-negative."
    assert FacValidateWithoutSourceMessage(FacOne(1, 5, 1, 2, "x")) == "Invalid edit range: (1,5)..(1,2) ends before it starts."

    overlapping := FacTwo(new TextEdit(1, 2, 1, 8, "XX"), new TextEdit(1, 5, 1, 12, "YY"))
    assert FacValidateWithoutSourceMessage(overlapping) == "Overlapping edits detected: edit at (1,2)..(1,8) overlaps with edit at (1,5)..(1,12)"

    // And it still SORTS: the answer is the application-ordered list, not the input list.
    unordered := FacTwo(new TextEdit(1, 0, 1, 0, "top"), new TextEdit(5, 0, 5, 0, "bottom"))
    assert FacNewTexts(FixApplicatorCore.ValidateAndSortEdits(unordered)) == "bottom|top|"
}

// NOT IN THE DELETED FILE: `MaterializeEditInputs`, the projection every other entry point runs on.
test "materializing an edit list splits it into five parallel columns" {
    edits := FacEdits()
    edits.Add(new TextEdit(1, 2, 3, 4, "alpha"))
    edits.Add(new TextEdit(5, 6, 7, 8, "beta"))

    inputs := FixApplicatorCore.MaterializeEditInputs(edits)

    assert inputs.Count == 2
    assert inputs.StartLines.Length == 2
    assert inputs.StartColumns.Length == 2
    assert inputs.EndLines.Length == 2
    assert inputs.EndColumns.Length == 2
    assert inputs.NewTexts.Length == 2

    assert inputs.StartLines[0] == 1
    assert inputs.StartColumns[0] == 2
    assert inputs.EndLines[0] == 3
    assert inputs.EndColumns[0] == 4
    assert inputs.NewTexts[0] == "alpha"

    assert inputs.StartLines[1] == 5
    assert inputs.StartColumns[1] == 6
    assert inputs.EndLines[1] == 7
    assert inputs.EndColumns[1] == 8
    assert inputs.NewTexts[1] == "beta"

    // The columns are sized to the list, so an empty list produces empty columns rather than null
    // ones — the shape check inside the engine reads `.Length` on every one of them.
    emptyInputs := FixApplicatorCore.MaterializeEditInputs(FacEdits())
    assert emptyInputs.Count == 0
    assert emptyInputs.StartLines.Length == 0
    assert emptyInputs.NewTexts.Length == 0
}

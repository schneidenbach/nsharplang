namespace NSharpLang.Compiler

import NSharpLang.Compiler.CodeIntelligence


// THE CANONICAL CONTRACTS FOR `FixApplicatorEditEngine`, IN N#.
//
// Part of the replacement for `tests/FixApplicatorTests.cs`. This is the kernel underneath
// `FixApplicatorCore`: it answers integer CODES rather than throwing, and it is the only place the
// line walk actually lives.
//
// THE DELETED FILE NEVER SAW A CODE. Every one of its thirty-five cases went through
// `FixApplicatorCore`, which converts the engine's code into an `InvalidOperationException` and
// throws it away as a message. That route cannot distinguish "the engine rejected this" from "the
// engine crashed and something else caught it", and it cannot reach the engine's two SHAPE
// rejections at all, because `FixApplicatorCore` builds well-shaped tables by construction.
//
// FOUR THINGS STATED HERE THAT NOTHING STATED ANYWHERE:
//
// (1) THE RETURN CODES, AS NUMBERS. 0 accept, 1 bad position, 2 backwards range, 3 overlap,
// 4 outside the document, -1 malformed call. These are the values `FixApplicatorValidationMessages`
// switches on, and the two files agree only if both are pinned.
//
// (2) THE ERROR SLOTS. The engine reports WHICH edit it rejected by writing indices into a
// two-element `int[]`, and for an overlap it writes BOTH — slot 0 the low edit, slot 1 the high one.
// A message can name the right pair only if the engine found the right pair.
//
// (3) THE LINE WALK, DIRECTLY. `CountLogicalLines` and `BuildLineLengthsInto` each carry three
// separate line-ending arms — CRLF, bare CR, LF — and the bare-CR arm had no coverage anywhere in
// the repository. They are asked here about the endings themselves rather than through an edit that
// happens to depend on them.
//
// (4) THE MALFORMED-CALL GUARD. An output buffer with no room, and a count larger than the columns
// that carry it, are both refused with -1 rather than read out of bounds. `FixApplicatorCore` cannot
// produce either, which is precisely why the guard needs its own statement.

func FeeInts(a: int, b: int): int[] {
    values := new int[](2)
    values[0] = a
    values[1] = b
    return values
}

func FeeOne(value: int): int[] {
    values := new int[](1)
    values[0] = value
    return values
}

func FeeTexts(a: string, b: string): string[] {
    values := new string[](2)
    values[0] = a
    values[1] = b
    return values
}

func FeeText(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

// One edit, validated against a document.
func FeeValidateOne(source: string, hasSource: int, startLine: int, startColumn: int, endLine: int, endColumn: int, newText: string, errorInfo: int[]): int {
    return FixApplicatorEditEngine.ValidateOrderedTextEdits(source, hasSource, FeeOne(startLine), FeeOne(startColumn), FeeOne(endLine), FeeOne(endColumn), FeeText(newText), 1, errorInfo)
}

// ── The return codes ──────────────────────────────────────────────────────────────────────────────

test "the validator answers zero for an edit it accepts" {
    errorInfo := FeeInts(7, 7)
    assert FeeValidateOne("abcdef", 1, 1, 0, 1, 6, "X", errorInfo) == 0

    // ON ACCEPTANCE THE SLOTS ARE STILL RESET. The engine clears both to -1 before it walks, so a
    // caller that read them after a zero would see the sentinel rather than whatever was there
    // before — which is what makes `ValidationIndex`'s negative arm the reachable one it is.
    assert errorInfo[0] == -1
    assert errorInfo[1] == -1

    // Zero edits is an acceptance, not a special case.
    empty := FeeInts(7, 7)
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("abcdef", 1, FeeOne(0), FeeOne(0), FeeOne(0), FeeOne(0), FeeText(""), 0, empty) == 0
}

test "the validator answers one for a coordinate that is not a coordinate" {
    // Line zero — lines are one-based.
    startLineZero := FeeInts(7, 7)
    assert FeeValidateOne("abcdef", 1, 0, 0, 1, 0, "X", startLineZero) == 1
    assert startLineZero[0] == 0
    assert startLineZero[1] == -1

    // End line zero, negative start column, negative end column — the other three arms of the same
    // check, each of which the deleted file's single case could not separate.
    assert FeeValidateOne("abcdef", 1, 1, 0, 0, 0, "X", FeeInts(7, 7)) == 1
    assert FeeValidateOne("abcdef", 1, 1, -1, 1, 0, "X", FeeInts(7, 7)) == 1
    assert FeeValidateOne("abcdef", 1, 1, 0, 1, -1, "X", FeeInts(7, 7)) == 1

    // The shape check runs WITHOUT a document too — it is about the numbers, not about the file.
    assert FeeValidateOne("", 0, 0, 0, 1, 0, "X", FeeInts(7, 7)) == 1
}

test "the validator answers two for a range that runs backwards" {
    columnBackwards := FeeInts(7, 7)
    assert FeeValidateOne("abcdef", 1, 1, 5, 1, 2, "X", columnBackwards) == 2
    assert columnBackwards[0] == 0
    assert columnBackwards[1] == -1

    // A backwards LINE is the other arm, and it is checked even when the columns would be fine.
    assert FeeValidateOne("a\nb\nc", 1, 3, 0, 2, 9, "X", FeeInts(7, 7)) == 2

    // An empty range is NOT backwards — start equal to end is the insertion point every zero-width
    // edit uses.
    assert FeeValidateOne("abcdef", 1, 1, 3, 1, 3, "X", FeeInts(7, 7)) == 0
}

test "the validator answers three for an overlap and names both edits" {
    // The edits arrive ALREADY ORDERED, which is the engine's contract with the orderer: index 0 is
    // later in the document than index 1. Slot 0 is the LOW edit and slot 1 the HIGH one.
    errorInfo := FeeInts(7, 7)
    code := FixApplicatorEditEngine.ValidateOrderedTextEdits("abcdefghijklmnop", 1, FeeInts(1, 1), FeeInts(5, 2), FeeInts(1, 1), FeeInts(12, 8), FeeTexts("YY", "XX"), 2, errorInfo)

    assert code == 3
    assert errorInfo[0] == 1
    assert errorInfo[1] == 0

    // ADJACENCY IS NOT OVERLAP, and the boundary is exact: the high edit's START may equal the low
    // edit's END, but not fall before it.
    adjacent := FeeInts(7, 7)
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("abcdefghij", 1, FeeInts(1, 1), FeeInts(5, 0), FeeInts(1, 1), FeeInts(10, 5), FeeTexts("FGHIJ", "ABCDE"), 2, adjacent) == 0

    oneCloser := FeeInts(7, 7)
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("abcdefghij", 1, FeeInts(1, 1), FeeInts(4, 0), FeeInts(1, 1), FeeInts(10, 5), FeeTexts("FGHIJ", "ABCDE"), 2, oneCloser) == 3

    // ACROSS LINES the same rule holds on the LINE key alone.
    acrossLines := FeeInts(7, 7)
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("a\nb\nc\nd\ne", 1, FeeInts(3, 2), FeeInts(0, 0), FeeInts(5, 4), FeeInts(0, 0), FeeTexts("B", "A"), 2, acrossLines) == 3
    assert acrossLines[0] == 1
    assert acrossLines[1] == 0

    // The overlap check runs WITHOUT a document — it is the part of validation that does not need one.
    noSource := FeeInts(7, 7)
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("", 0, FeeInts(1, 1), FeeInts(5, 2), FeeInts(1, 1), FeeInts(12, 8), FeeTexts("YY", "XX"), 2, noSource) == 3
}

test "the validator answers four for a coordinate outside the document, and only with one" {
    // A column past the end of a real line.
    pastColumn := FeeInts(7, 7)
    assert FeeValidateOne("abcdef", 1, 1, 7, 1, 7, "X", pastColumn) == 4
    assert pastColumn[0] == 0

    // A line past the end of the document.
    pastLine := FeeInts(7, 7)
    assert FeeValidateOne("abcdef", 1, 3, 0, 3, 0, "X", pastLine) == 4

    // THE SAME EDITS ARE ACCEPTED WITHOUT A DOCUMENT. This is the whole difference the `hasSource`
    // flag makes, and the deleted file never called the engine with it clear.
    assert FeeValidateOne("abcdef", 0, 1, 7, 1, 7, "X", FeeInts(7, 7)) == 0
    assert FeeValidateOne("abcdef", 0, 3, 0, 3, 0, "X", FeeInts(7, 7)) == 0
    assert FeeValidateOne("", 0, 9999, 400, 9999, 400, "X", FeeInts(7, 7)) == 0

    // THE TWO EXEMPTIONS. An EOF insert at column zero of the one-past-the-end line is accepted, and
    // so is a whole-line deletion of the final line — but only when its new text is EMPTY.
    assert FeeValidateOne("abcdef", 1, 2, 0, 2, 0, "appended", FeeInts(7, 7)) == 0
    assert FeeValidateOne("abcdef", 1, 1, 0, 2, 0, "", FeeInts(7, 7)) == 0
    assert FeeValidateOne("abcdef", 1, 1, 0, 2, 0, "x", FeeInts(7, 7)) == 4

    // The column limit is INCLUSIVE of the line length: one past the last character is an insertion
    // point, one further is not.
    assert FeeValidateOne("abcdef", 1, 1, 6, 1, 6, "X", FeeInts(7, 7)) == 0
}

// ── The malformed-call guard ──────────────────────────────────────────────────────────────────────

test "a malformed call is refused rather than read out of bounds" {
    // A count larger than the columns that carry it. `FixApplicatorCore` cannot produce this — it
    // sizes every column to the list — so this guard has no end-to-end route at all.
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("abc", 1, FeeOne(1), FeeOne(0), FeeOne(1), FeeOne(0), FeeText("X"), 2, FeeInts(7, 7)) == -1

    // A negative count.
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("abc", 1, FeeOne(1), FeeOne(0), FeeOne(1), FeeOne(0), FeeText("X"), -1, FeeInts(7, 7)) == -1

    // An error array too small to carry both slots.
    assert FixApplicatorEditEngine.ValidateOrderedTextEdits("abc", 1, FeeOne(1), FeeOne(0), FeeOne(1), FeeOne(0), FeeText("X"), 1, FeeOne(0)) == -1

    // And on the APPLY side: an output buffer with no room at all.
    assert FixApplicatorEditEngine.ApplyOrderedTextEdits("abc", FeeOne(1), FeeOne(0), FeeOne(1), FeeOne(0), FeeText("X"), 1, new string[](0)) == -1
    assert FixApplicatorEditEngine.ApplyOrderedTextEdits("abc", FeeOne(1), FeeOne(0), FeeOne(1), FeeOne(0), FeeText("X"), 2, new string[](1)) == -1
}

// ── Applying, at the kernel level ─────────────────────────────────────────────────────────────────

test "the apply kernel writes its answer into the caller's buffer and reports zero" {
    output := new string[](1)
    output[0] = "<untouched>"

    code := FixApplicatorEditEngine.ApplyOrderedTextEdits("line one\nline two\nline three", FeeOne(2), FeeOne(5), FeeOne(2), FeeOne(8), FeeText("TWO"), 1, output)

    assert code == 0
    assert output[0] == "line one\nline TWO\nline three"

    // A buffer LARGER than one is fine; only slot zero is written.
    roomy := new string[](3)
    roomy[1] = "<kept>"
    assert FixApplicatorEditEngine.ApplyOrderedTextEdits("abc", FeeOne(1), FeeOne(0), FeeOne(1), FeeOne(0), FeeText(">"), 1, roomy) == 0
    assert roomy[0] == ">abc"
    assert roomy[1] == "<kept>"

    // THE APPLY KERNEL DOES NOT VALIDATE. Handed an edit the validator would reject with code 4, it
    // applies what it can and still reports success — which is exactly why `FixApplicatorCore`
    // validates FIRST and why a caller that skipped that step would silently corrupt a file.
    unvalidated := new string[](1)
    assert FixApplicatorEditEngine.ApplyOrderedTextEdits("abc", FeeOne(9), FeeOne(0), FeeOne(9), FeeOne(0), FeeText("far"), 1, unvalidated) == 0
    assert unvalidated[0] == "abc\nfar"
}

// ── The line walk ─────────────────────────────────────────────────────────────────────────────────

test "the line count knows all three line endings" {
    // The empty document is ONE line, not zero — every column check downstream depends on it.
    assert FixApplicatorEditEngine.CountLogicalLines("") == 1
    assert FixApplicatorEditEngine.CountLogicalLines("abc") == 1

    assert FixApplicatorEditEngine.CountLogicalLines("a\nb") == 2
    assert FixApplicatorEditEngine.CountLogicalLines("a\r\nb") == 2

    // THE BARE CARRIAGE RETURN, WITH NO COVERAGE ANYWHERE BEFORE THIS LINE.
    assert FixApplicatorEditEngine.CountLogicalLines("a\rb") == 2

    // A CRLF IS ONE ENDING, NOT TWO. This is the arm that separates a real walk from a naive count
    // of `'\n'` plus a count of `'\r'`.
    assert FixApplicatorEditEngine.CountLogicalLines("a\r\nb\r\nc") == 3
    assert FixApplicatorEditEngine.CountLogicalLines("a\n\rb") == 3

    // A trailing ending leaves a final empty line.
    assert FixApplicatorEditEngine.CountLogicalLines("a\n") == 2
    assert FixApplicatorEditEngine.CountLogicalLines("a\r\n") == 2
    assert FixApplicatorEditEngine.CountLogicalLines("a\r") == 2
    assert FixApplicatorEditEngine.CountLogicalLines("\n") == 2

    // A MIXED document counts each ending once, whatever order they arrive in.
    assert FixApplicatorEditEngine.CountLogicalLines("one\r\ntwo\rthree\nfour") == 4
}

test "the line lengths exclude the terminator, whichever terminator it is" {
    lengths := new int[](4)
    written := FixApplicatorEditEngine.BuildLineLengthsInto("one\r\ntwo\rthree\nfour", lengths)

    assert written == 4
    assert lengths[0] == 3
    assert lengths[1] == 3
    assert lengths[2] == 5
    assert lengths[3] == 4

    // The empty document has one line of length zero.
    single := new int[](1)
    assert FixApplicatorEditEngine.BuildLineLengthsInto("", single) == 1
    assert single[0] == 0

    // A trailing ending produces a final line of length zero — the line an EOF-adjacent edit
    // addresses.
    trailing := new int[](2)
    assert FixApplicatorEditEngine.BuildLineLengthsInto("abc\n", trailing) == 2
    assert trailing[0] == 3
    assert trailing[1] == 0

    // Consecutive endings produce empty lines between them rather than being coalesced.
    blanks := new int[](3)
    assert FixApplicatorEditEngine.BuildLineLengthsInto("a\n\nb", blanks) == 3
    assert blanks[0] == 1
    assert blanks[1] == 0
    assert blanks[2] == 1
}

test "a position is in the document when its line exists and its column reaches no further than the end" {
    lengths := new int[](2)
    lengths[0] = 6
    lengths[1] = 0

    // Column zero through the line length inclusive — the last of these is the insertion point past
    // the final character.
    assert FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 1, 0)
    assert FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 1, 6)
    assert !FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 1, 7)

    // An empty final line accepts column zero only.
    assert FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 2, 0)
    assert !FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 2, 1)

    // Lines are one-based and bounded above by the count the caller supplies, not by the array.
    assert !FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 0, 0)
    assert !FixApplicatorEditEngine.PositionIsInDocument(lengths, 2, 3, 0)
    assert !FixApplicatorEditEngine.PositionIsInDocument(lengths, 1, 2, 0)
}

test "the engine's integer minimum picks the smaller and ties on equality" {
    assert FixApplicatorEditEngine.MinInt(3, 9) == 3
    assert FixApplicatorEditEngine.MinInt(9, 3) == 3
    assert FixApplicatorEditEngine.MinInt(4, 4) == 4
    assert FixApplicatorEditEngine.MinInt(-2, 1) == -2
    assert FixApplicatorEditEngine.MinInt(0, -5) == -5
}

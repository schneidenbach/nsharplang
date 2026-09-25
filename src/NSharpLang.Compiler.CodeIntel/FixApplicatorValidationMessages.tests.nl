namespace NSharpLang.Compiler

import NSharpLang.Compiler.CodeIntelligence


// THE CANONICAL CONTRACTS FOR `FixApplicatorValidationMessages`, IN N#.
//
// Part of the replacement for `tests/FixApplicatorTests.cs`. This is the renderer that turns the edit
// engine's integer rejection code into the sentence a developer reads when `nlc fix` refuses to
// rewrite their file.
//
// NOTHING ANYWHERE STATED THIS SUBJECT DIRECTLY. The deleted file only ever saw these messages
// through `FixApplicatorCore.ApplyEdits`, and only ever asserted a SUBSTRING of one
// (`Assert.Contains("outside the document", ex.Message)`). That reaches four of the five arms
// incidentally and can distinguish none of them from a message that named the wrong edit.
//
// THREE THINGS THAT WERE UNREACHABLE THROUGH THE DELETED FILE'S ROUTE AND ARE STATED HERE:
//
// (1) THE FALLBACK ARM. An unrecognised code answers "N# fix applicator kernel rejected the edit
// validation." `FixApplicatorCore` never calls the renderer with code 0, so no end-to-end test could
// reach this line — and it is the line that runs if a future engine adds a rejection code and
// forgets to add its sentence.
//
// (2) `ValidationIndex` IS A CLAMP, NOT A LOOKUP. The engine writes -1 into both error slots before
// it walks, so a renderer that trusted the slot would format edit -1 and crash. Every clamping arm —
// a negative index, an index past the end, an empty edit table, a slot outside the array — is stated
// here, and none of them is reachable from a well-formed engine run.
//
// (3) THE OVERLAP MESSAGE READS TWO SLOTS, IN A FIXED ORDER. Slot 0 is the LOW edit and slot 1 is
// the HIGH one, and the sentence puts slot 0 first. Swapping them produces a sentence that is still
// grammatical, still contains "Overlapping edits detected", and blames the pair backwards.
func FvmLines(): int[] {
    lines := new int[](3)
    lines[0] = 1
    lines[1] = 20
    lines[2] = 300
    return lines
}

func FvmColumns(): int[] {
    columns := new int[](3)
    columns[0] = 2
    columns[1] = 30
    columns[2] = 400
    return columns
}

func FvmEndLines(): int[] {
    lines := new int[](3)
    lines[0] = 3
    lines[1] = 40
    lines[2] = 500
    return lines
}

func FvmEndColumns(): int[] {
    columns := new int[](3)
    columns[0] = 4
    columns[1] = 50
    columns[2] = 600
    return columns
}

func FvmErrorInfo(first: int, second: int): int[] {
    errorInfo := new int[](2)
    errorInfo[0] = first
    errorInfo[1] = second
    return errorInfo
}

func FvmMessage(code: int, errorInfo: int[]): string {
    return FixApplicatorValidationMessages.BuildValidationMessage(code, errorInfo, FvmLines(), FvmColumns(), FvmEndLines(), FvmEndColumns(), 3)
}

// ── The five arms ─────────────────────────────────────────────────────────────────────────────────

test "each rejection code renders its own sentence" {
    // Code 1 — a coordinate that is not a coordinate at all.
    assert FvmMessage(1, FvmErrorInfo(0, -1)) == "Invalid edit position: (1,2)..(3,4). Lines are 1-based and columns must be non-negative."

    // Code 2 — a range that runs backwards.
    assert FvmMessage(2, FvmErrorInfo(1, -1)) == "Invalid edit range: (20,30)..(40,50) ends before it starts."

    // Code 3 — two edits that fight over the same text. Slot 0 is named FIRST.
    assert FvmMessage(3, FvmErrorInfo(0, 2)) == "Overlapping edits detected: edit at (1,2)..(3,4) overlaps with edit at (300,400)..(500,600)"

    // The two slots are NOT interchangeable: swapping them swaps the sentence.
    assert FvmMessage(3, FvmErrorInfo(2, 0)) == "Overlapping edits detected: edit at (300,400)..(500,600) overlaps with edit at (1,2)..(3,4)"

    // Code 4 — a coordinate outside the document it was measured against.
    assert FvmMessage(4, FvmErrorInfo(2, -1)) == "Invalid edit range: (300,400)..(500,600) is outside the document."

    // AND THE FALLBACK, WHICH `FixApplicatorCore` CAN NEVER REACH. Code 0 means "no error", so a
    // renderer asked for its sentence has been called by mistake; every other unrecognised code is a
    // rejection the engine grew and the renderer has not learned yet. Both answer the same
    // deliberately generic sentence rather than an empty string or a crash.
    assert FvmMessage(0, FvmErrorInfo(0, -1)) == "N# fix applicator kernel rejected the edit validation."
    assert FvmMessage(5, FvmErrorInfo(0, -1)) == "N# fix applicator kernel rejected the edit validation."
    assert FvmMessage(-1, FvmErrorInfo(0, -1)) == "N# fix applicator kernel rejected the edit validation."
    assert FvmMessage(99, FvmErrorInfo(0, -1)) == "N# fix applicator kernel rejected the edit validation."
}

// ── The clamp ─────────────────────────────────────────────────────────────────────────────────────

test "an out-of-range error slot is clamped rather than trusted" {
    // THE ENGINE'S OWN INITIAL STATE. `ValidateOrderedTextEditsCore` writes -1 into both slots before
    // it starts walking, so a renderer that indexed the arrays directly would read index -1 the
    // moment a code arrived without an index. It clamps to the FIRST edit instead.
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(-1, -1), 0, 3) == 0
    assert FvmMessage(1, FvmErrorInfo(-1, -1)) == "Invalid edit position: (1,2)..(3,4). Lines are 1-based and columns must be non-negative."

    // An index PAST the end clamps to the LAST edit, not to the first and not past the array.
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(3, -1), 0, 3) == 2
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(9999, -1), 0, 3) == 2
    assert FvmMessage(4, FvmErrorInfo(9999, -1)) == "Invalid edit range: (300,400)..(500,600) is outside the document."

    // An EMPTY edit table has no last edit to clamp to, so the answer is 0 — the only value that
    // cannot index past a zero-length array once the caller checks its own count.
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(5, -1), 0, 0) == 0
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(5, -1), 0, -1) == 0

    // A SLOT outside the error array is clamped too, which is what keeps the two-slot overlap
    // sentence safe against a one-slot array.
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(2, 1), 2, 3) == 0
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(2, 1), -1, 3) == 0

    // An in-range index is passed through untouched — the clamp is not a rewrite.
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(0, 1), 0, 3) == 0
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(1, 2), 0, 3) == 1
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(2, 0), 0, 3) == 2
    assert FixApplicatorValidationMessages.ValidationIndex(FvmErrorInfo(2, 1), 1, 3) == 1
}

// ── The coordinate format ─────────────────────────────────────────────────────────────────────────

test "an edit range renders as two parenthesised pairs joined by two dots" {
    assert FixApplicatorValidationMessages.FormatEditRange(FvmLines(), FvmColumns(), FvmEndLines(), FvmEndColumns(), 0) == "(1,2)..(3,4)"
    assert FixApplicatorValidationMessages.FormatEditRange(FvmLines(), FvmColumns(), FvmEndLines(), FvmEndColumns(), 1) == "(20,30)..(40,50)"
    assert FixApplicatorValidationMessages.FormatEditRange(FvmLines(), FvmColumns(), FvmEndLines(), FvmEndColumns(), 2) == "(300,400)..(500,600)"

    // The four columns are read in the order line, column, line, column — a transposition would
    // produce a well-formed string that pointed at a different place in the file.
    zeros := new int[](1)
    ones := new int[](1)
    twos := new int[](1)
    threes := new int[](1)
    zeros[0] = 0
    ones[0] = 1
    twos[0] = 2
    threes[0] = 3
    assert FixApplicatorValidationMessages.FormatEditRange(zeros, ones, twos, threes, 0) == "(0,1)..(2,3)"

    // Negative coordinates render as they are, because the position-rejection sentence exists to
    // SHOW the developer the number the tool was handed.
    negatives := new int[](1)
    negatives[0] = -7
    assert FixApplicatorValidationMessages.FormatEditRange(negatives, negatives, negatives, negatives, 0) == "(-7,-7)..(-7,-7)"
}

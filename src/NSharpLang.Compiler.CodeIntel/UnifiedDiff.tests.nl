namespace NSharpLang.Cli

import System

// THE UNIFIED DIFF `nlc fix --diff` AND `nlc format --diff` PRINT.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliParityAuditTests.cs`:
// `UnifiedDiff_Create_EmitsStableMultiHunkDiff` (60 declaration lines, ONE `Assert.` row). That row
// was a whole-string equality against a twelve-line before/after pair with `contextLines: 1`, and
// it is reproduced here EXACTLY — same input, same expected text, same trailing newline.
//
// WHAT THE DELETED ROW COULD NOT SAY, AND THESE BLOCKS DO. A single whole-string comparison is
// true or false and never names WHICH rule produced the string. It cannot distinguish a diff whose
// hunk-header arithmetic is wrong from one whose CONTEXT WINDOW is wrong, because both change the
// same string. The mechanism is stated a piece at a time below: the two-line file header, the
// `@@ -old,count +new,count @@` arithmetic, the three line prefixes, the merge rule that joins two
// edits whose context windows touch, and the identical-input short circuit — which the deleted body
// never exercised at all, and which is the only path that returns the empty string.

// ── the deleted row, reproduced whole ─────────────────────────────────────────
func TwelveLineBefore(): string {
    return "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve"
}

func TwelveLineAfter(): string {
    return "one\ntwo\nTHREE\nfour\nfive\nsix\nseven\neight\nnine-a\nnine\nten\ntwelve"
}

test "the multi-hunk diff of the twelve-line pair is byte-stable at one context line" {
    diff := UnifiedDiff.Create(TwelveLineBefore(), TwelveLineAfter(), "a/Program.nl", "b/Program.nl", 1)

    assert diff == "--- a/Program.nl\n+++ b/Program.nl\n@@ -2,3 +2,3 @@\n two\n-three\n+THREE\n four\n@@ -8,5 +8,5 @@\n eight\n+nine-a\n nine\n ten\n-eleven\n twelve\n"
}

// ── the file header ───────────────────────────────────────────────────────────

test "the two header lines carry the labels verbatim and in before/after order" {
    assert UnifiedDiff.BeforeHeaderText("a/Program.nl") == "--- a/Program.nl"
    assert UnifiedDiff.AfterHeaderText("b/Program.nl") == "+++ b/Program.nl"

    // and the whole print opens with exactly those two lines, in that order
    diff := UnifiedDiff.Create("x", "y", "OLD", "NEW", 0)
    assert diff.StartsWith("--- OLD\n+++ NEW\n")
}

test "a label is never inspected, so an empty label still produces a well-formed header" {
    assert UnifiedDiff.BeforeHeaderText("") == "--- "
    assert UnifiedDiff.AfterHeaderText("") == "+++ "
}

// ── the hunk header arithmetic ────────────────────────────────────────────────

test "the hunk header states the OLD range then the NEW range, each as start,count" {
    assert UnifiedDiff.HunkHeaderText(2, 3, 2, 3) == "@@ -2,3 +2,3 @@"
    assert UnifiedDiff.HunkHeaderText(8, 5, 8, 5) == "@@ -8,5 +8,5 @@"

    // THE TWO SIDES ARE INDEPENDENT, which the deleted body's symmetric example hid: both of its
    // hunks happened to have equal old and new counts, so a transposed pair would have passed.
    assert UnifiedDiff.HunkHeaderText(4, 1, 9, 7) == "@@ -4,1 +9,7 @@"
}

test "an inserted line makes the new count exceed the old count in the same hunk" {
    // one context line either side of a pure insertion: 2 context + 0 removed on the old side,
    // 2 context + 1 added on the new side
    diff := UnifiedDiff.Create("a\nb\nc", "a\nb\nINSERT\nc", "x", "y", 1)

    assert diff.Contains("@@ -2,2 +2,3 @@")
    assert diff.Contains("+INSERT")
}

test "a deleted line makes the old count exceed the new count in the same hunk" {
    diff := UnifiedDiff.Create("a\nb\nGONE\nc", "a\nb\nc", "x", "y", 1)

    assert diff.Contains("@@ -2,3 +2,2 @@")
    assert diff.Contains("-GONE")
}

// ── the three line prefixes ───────────────────────────────────────────────────

test "context is a space, an addition is +, a removal is -, and nothing else is a prefix" {
    assert UnifiedDiff.LinePrefixText(0) == " "
    assert UnifiedDiff.LinePrefixText(1) == "+"
    assert UnifiedDiff.LinePrefixText(2) == "-"

    // the kind space is exactly those three; anything outside it falls to the context prefix
    assert UnifiedDiff.LinePrefixText(3) == " "
}

test "a replaced line appears TWICE, once removed and once added, and the removal comes first" {
    diff := UnifiedDiff.Create("a\nOLD\nc", "a\nNEW\nc", "x", "y", 1)

    removedIndex := diff.IndexOf("-OLD", 0, StringComparison.Ordinal)
    addedIndex := diff.IndexOf("+NEW", 0, StringComparison.Ordinal)

    assert removedIndex >= 0
    assert addedIndex >= 0
    assert removedIndex < addedIndex
}

// ── the context window and the hunk merge rule ────────────────────────────────

test "two edits far apart become TWO hunks and two edits close together become ONE" {
    // THE MERGE RULE, STATED. Two edits share a hunk when the second edit's context window starts
    // no later than one line past the end of the first — which is why the deleted body's twelve
    // line pair, whose edits sit at lines 3 and 9, produced exactly two hunks at one context line.
    apart := UnifiedDiff.Create(
        "a\nb\nc\nd\ne\nf\ng\nh",
        "A\nb\nc\nd\ne\nf\ng\nH",
        "x",
        "y",
        1
    )
    assert CountOccurrences(apart, "@@ ") == 2

    together := UnifiedDiff.Create("a\nb\nc\nd", "A\nb\nC\nd", "x", "y", 1)
    assert CountOccurrences(together, "@@ ") == 1
}

test "a wider context window merges hunks the narrow window kept apart" {
    before := "a\nb\nc\nd\ne\nf\ng\nh"
    after := "A\nb\nc\nd\ne\nf\ng\nH"

    assert CountOccurrences(UnifiedDiff.Create(before, after, "x", "y", 1), "@@ ") == 2
    assert CountOccurrences(UnifiedDiff.Create(before, after, "x", "y", 3), "@@ ") == 1
}

test "a zero context window prints the changed lines and no surrounding text at all" {
    diff := UnifiedDiff.Create("a\nb\nc", "a\nB\nc", "x", "y", 0)

    assert diff == "--- x\n+++ y\n@@ -2,1 +2,1 @@\n-b\n+B\n"
}

// ── the two edges the deleted body never reached ──────────────────────────────

test "identical input short-circuits to the EMPTY string, with no header at all" {
    // THE ONLY PATH THAT RETURNS "". `nlc fix --diff` prints nothing for an unchanged file, and
    // this is the rule that makes it so. The deleted body never passed equal inputs.
    assert UnifiedDiff.Create("same\ntext", "same\ntext", "a", "b", 1) == ""
    assert UnifiedDiff.Create("", "", "a", "b", 3) == ""
}

test "a negative context count is rejected rather than clamped" {
    // and it is rejected AFTER the identical-input check, so equal inputs win even with a bad count
    assert UnifiedDiff.Create("same", "same", "a", "b", -1) == ""

    threw := false
    try {
        UnifiedDiff.Create("a", "b", "x", "y", -1)
    } catch {
        threw = true
    }
    assert threw
}

test "CRLF and CR line endings are normalized before the comparison, so they are not differences" {
    // A FILE THAT DIFFERS ONLY IN LINE ENDINGS STILL DIFFERS, because the short circuit compares
    // the RAW text — but the diff it then produces sees the same lines on both sides.
    diff := UnifiedDiff.Create("a\r\nb", "a\nb", "x", "y", 1)

    assert diff.Contains("@@ ") == false
    assert diff == "--- x\n+++ y\n"
}

func CountOccurrences(text: string, marker: string): int {
    count := 0
    start := 0
    while start < text.Length {
        index := text.IndexOf(marker, start, StringComparison.Ordinal)
        if index < 0 {
            break
        }

        count = count + 1
        start = index + marker.Length
    }

    return count
}

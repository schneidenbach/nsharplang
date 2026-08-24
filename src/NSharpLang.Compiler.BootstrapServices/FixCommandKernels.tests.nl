namespace NSharpLang.Cli.Commands

import System.Collections.Generic
import NSharpLang.Compiler

// THE `nlc fix` SAFETY FILTER, SKIP SELECTOR, FILE GROUPING AND MESSAGE KERNELS.
//
// These replace FOUR `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `FixCommandKernels_ShapesMessages`, `..._FiltersFixesBySafety`, `..._SelectsSkippedFixEntries`
// and `..._GroupsAppliedFixEntriesByFile`.
//
// ONE OF THE FOUR IS SPLIT, AND THE SPLIT IS FORCED. `..._ShapesMessages` ended by driving
// `FixCommand.Execute` through a console capture. `Console.SetOut` declines on this emit path at
// `emit.call.static-member-unmodeled`, so those rows are in `tests/native/cli-command-contracts`.
//
// THE THREE COLLECTION BODIES COMPUTED THEIR EXPECTATIONS WITH LINQ OVER THE SAME INPUT — a
// `Where` clause restating the kernel's own predicate, and a `GroupBy` restating its grouping —
// so each asserted only that two implementations of one rule agree. The answers are written out
// literally below, which is what makes them pins.

func SafeFix(title: string, safety: FixSafety): CodeAction {
    return new CodeAction(title, "NL000", new List<TextEdit>(), safety)
}

// `file` is reserved in the parameter-name position, so the path parameter is spelled `filePath`.
func Entry(filePath: string, code: string, title: string, safety: string): FixEntry {
    return new FixEntry(filePath, code, title, new List<TextEdit>(), safety)
}

// ── the safety filter ─────────────────────────────────────────────────────────

test "by default only Safe fixes are applied" {
    fixes := [
        SafeFix("safe import", FixSafety.Safe),
        SafeFix("review unused variable", FixSafety.ReviewNeeded),
        SafeFix("suggest rewrite", FixSafety.SuggestionOnly),
        SafeFix("safe empty catch", FixSafety.Safe),
        SafeFix("review null access", FixSafety.ReviewNeeded)
    ]

    applied := FixCommandKernels.FilterBySafety(fixes, false)

    assert applied.Count == 2
    assert applied[0].Title == "safe import"
    assert applied[1].Title == "safe empty catch"
    // Reading `.Safety` back off the ANSWER is what proves the filter hands back the original
    // objects rather than reconstructing them, and it is the property the deleted `Where`
    // predicate named.
    assert applied[0].Safety == FixSafety.Safe
    assert applied[1].Safety == FixSafety.Safe
}

test "--include-review-needed adds the ReviewNeeded fixes but never the SuggestionOnly ones" {
    fixes := [
        SafeFix("safe import", FixSafety.Safe),
        SafeFix("review unused variable", FixSafety.ReviewNeeded),
        SafeFix("suggest rewrite", FixSafety.SuggestionOnly),
        SafeFix("safe empty catch", FixSafety.Safe),
        SafeFix("review null access", FixSafety.ReviewNeeded)
    ]

    applied := FixCommandKernels.FilterBySafety(fixes, true)

    // Source order is preserved, and `suggest rewrite` is STILL excluded — there is no flag that
    // applies a suggestion-only fix.
    assert applied.Count == 4
    assert applied[0].Title == "safe import"
    assert applied[1].Title == "review unused variable"
    assert applied[2].Title == "safe empty catch"
    assert applied[3].Title == "review null access"
    assert applied[0].Safety == FixSafety.Safe
    assert applied[1].Safety == FixSafety.ReviewNeeded
    assert applied[3].Safety == FixSafety.ReviewNeeded
}

// ── the skipped selector ──────────────────────────────────────────────────────

test "everything not applied is reported as skipped, including an unrecognised safety" {
    entries := [
        Entry("Program.nl", "NL000", "safe import", "safe"),
        Entry("Program.nl", "NL000", "review unused variable", "reviewNeeded"),
        Entry("Program.nl", "NL000", "suggest rewrite", "suggestionOnly"),
        Entry("Program.nl", "NL000", "unknown safety", "unknown"),
        Entry("Program.nl", "NL000", "safe empty catch", "safe"),
        Entry("Program.nl", "NL000", "review null access", "reviewNeeded")
    ]

    skipped := FixCommandKernels.SelectSkippedEntries(entries, false)

    // An UNRECOGNISED safety string is skipped rather than silently applied — the safe default.
    assert skipped.Count == 4
    assert skipped[0].Title == "review unused variable"
    assert skipped[1].Title == "suggest rewrite"
    assert skipped[2].Title == "unknown safety"
    assert skipped[3].Title == "review null access"
    // `FixEntry` carries its safety as a STRING, and none of the four survivors is `"safe"` —
    // the property the deleted `Where(entry => entry.Safety is not "safe")` named.
    assert skipped[0].Safety == "reviewNeeded"
    assert skipped[1].Safety == "suggestionOnly"
    assert skipped[2].Safety == "unknown"
    assert skipped[3].Safety == "reviewNeeded"
}

test "with --include-review-needed only the suggestion-only and unknown entries stay skipped" {
    entries := [
        Entry("Program.nl", "NL000", "safe import", "safe"),
        Entry("Program.nl", "NL000", "review unused variable", "reviewNeeded"),
        Entry("Program.nl", "NL000", "suggest rewrite", "suggestionOnly"),
        Entry("Program.nl", "NL000", "unknown safety", "unknown"),
        Entry("Program.nl", "NL000", "safe empty catch", "safe"),
        Entry("Program.nl", "NL000", "review null access", "reviewNeeded")
    ]

    skipped := FixCommandKernels.SelectSkippedEntries(entries, true)

    assert skipped.Count == 2
    assert skipped[0].Title == "suggest rewrite"
    assert skipped[1].Title == "unknown safety"
    assert skipped[0].Safety == "suggestionOnly"
    assert skipped[1].Safety == "unknown"
}

// ── the applied-entry grouping ────────────────────────────────────────────────

test "applied entries group by file in FIRST-APPEARANCE order, keeping each file's entry order" {
    entries := [
        Entry("src/B.nl", "NL001", "first b", "safe"),
        Entry("src/A.nl", "NL002", "first a", "safe"),
        Entry("src/B.nl", "NL003", "second b", "safe"),
        Entry("src/C.nl", "NL004", "first c", "safe"),
        Entry("src/A.nl", "NL005", "second a", "safe")
    ]

    grouping := FixCommandKernels.GroupAppliedEntriesByFile(entries)

    // Three groups, in the order the files were first seen — B, A, C — NOT sorted.
    assert grouping.GroupCount == 3
    assert grouping.Files[0] == "src/B.nl"
    assert grouping.Files[1] == "src/A.nl"
    assert grouping.Files[2] == "src/C.nl"

    assert grouping.Counts[0] == 2
    assert grouping.Counts[1] == 2
    assert grouping.Counts[2] == 1

    // The starts partition the index array end to end, with no gap and no overlap.
    assert grouping.Starts[0] == 0
    assert grouping.Starts[1] == 2
    assert grouping.Starts[2] == 4
    assert grouping.Indices.Length == 5

    // Group B holds the two B entries in their original relative order.
    assert entries[grouping.Indices[0]].DiagnosticCode == "NL001"
    assert entries[grouping.Indices[1]].DiagnosticCode == "NL003"
    // Group A likewise.
    assert entries[grouping.Indices[2]].DiagnosticCode == "NL002"
    assert entries[grouping.Indices[3]].DiagnosticCode == "NL005"
    // Group C is the single late arrival.
    assert entries[grouping.Indices[4]].DiagnosticCode == "NL004"

    // EVERY member of a group actually carries that group's file. Without this the label and its
    // members are two independent lists, and a kernel that grouped correctly but wrote the wrong
    // label into `Files` would still pass every row above. The deleted body expressed this by
    // grouping on `entry.File` in its own LINQ; here it is read back off the answer.
    assert entries[grouping.Indices[0]].File == grouping.Files[0]
    assert entries[grouping.Indices[1]].File == grouping.Files[0]
    assert entries[grouping.Indices[2]].File == grouping.Files[1]
    assert entries[grouping.Indices[3]].File == grouping.Files[1]
    assert entries[grouping.Indices[4]].File == grouping.Files[2]
}

test "an empty applied list groups into nothing rather than one empty group" {
    grouping := FixCommandKernels.GroupAppliedEntriesByFile(new List<FixEntry>())

    assert grouping.GroupCount == 0
    assert grouping.Indices.Length == 0
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the fix help text names the command, its usage and the review flag" {
    helpText := FixCommandKernels.GetHelpText()

    assert helpText.Contains("N# Auto-Fix")
    assert helpText.Contains("Usage: nlc fix [options] [project-dir]")
    assert helpText.Contains("--include-review-needed")
}

test "the fix command's failure sentences are exactly these" {
    assert FixCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-fix-project") == "Directory not found: /tmp/missing-fix-project"
    assert FixCommandKernels.GetFileNotFoundMessage("Missing.nl") == "File not found: Missing.nl"
    assert FixCommandKernels.GetNoFilesFoundMessage() == "No .nl files found."
    assert FixCommandKernels.GetFailedMessage("disk full") == "Fix failed: disk full"
    assert FixCommandKernels.GetNothingToFixMessage() == "Nothing to fix."
}

test "the applied header reads WOULD FIX on a dry run and FIXED otherwise, and counts both nouns" {
    assert FixCommandKernels.GetAppliedHeader(1, 1, true) == "Would fix 1 issue in 1 file:"
    assert FixCommandKernels.GetAppliedHeader(2, 3, false) == "Fixed 2 issues in 3 files:"
    assert FixCommandKernels.GetAppliedFileHeader("src/Program.nl") == "  src/Program.nl:"
    assert FixCommandKernels.GetEntryLine("NL001", "Remove unused variable") == "    [NL001] Remove unused variable"
}

test "the skipped header pluralises, and each safety has its own reason sentence" {
    assert FixCommandKernels.GetSkippedHeader(1) == "Skipped 1 fix:"
    assert FixCommandKernels.GetSkippedHeader(2) == "Skipped 2 fixes:"
    assert FixCommandKernels.GetSkippedReason("suggestionOnly") == "suggestion only — manual review required"
    assert FixCommandKernels.GetSkippedReason("reviewNeeded") == "requires --include-review-needed flag"
    assert FixCommandKernels.GetSkippedLine("NL010", "Remove unused import", "requires --include-review-needed flag") == "  [NL010] Remove unused import (requires --include-review-needed flag)"
}

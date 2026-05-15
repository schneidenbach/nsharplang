using System;
using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

public class FixApplicatorTests
{
    // ── Single Edit Application ─────────────────────────────────────────

    [Fact]
    public void ApplyEdits_SingleReplace_ReplacesText()
    {
        var source = "line one\nline two\nline three";
        var edits = new List<TextEdit>
        {
            new(2, 5, 2, 8, "TWO")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("line one\nline TWO\nline three", result);
    }

    [Fact]
    public void ApplyEdits_SingleInsert_InsertsAtPosition()
    {
        var source = "hello world";
        var edits = new List<TextEdit>
        {
            new(1, 5, 1, 5, " beautiful")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("hello beautiful world", result);
    }

    [Fact]
    public void ApplyEdits_DeleteEntireLines_RemovesLines()
    {
        var source = "line one\nline two\nline three\nline four";
        // Delete line 2 (startCol=0, endCol=0, endLine > startLine)
        var edits = new List<TextEdit>
        {
            new(2, 0, 3, 0, "")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("line one\nline three\nline four", result);
    }

    // ── Empty / No-Op Edit Handling ─────────────────────────────────────

    [Fact]
    public void ApplyEdits_EmptyEditList_ReturnsSourceUnchanged()
    {
        var source = "unchanged source";
        var edits = new List<TextEdit>();

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal(source, result);
    }

    [Fact]
    public void ApplyEdits_NoOpEdit_ReturnsSourceUnchanged()
    {
        var source = "line one\nline two";
        // A no-op edit: same start/end, empty new text
        var edits = new List<TextEdit>
        {
            new(1, 3, 1, 3, "")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal(source, result);
    }

    // ── Multi-Edit Ordering (Bottom-to-Top) ─────────────────────────────

    [Fact]
    public void ApplyEdits_MultipleEdits_AppliedBottomToTop_PreservesPositions()
    {
        var source = "aaa\nbbb\nccc";
        // Two replacements: one on line 1, one on line 3
        // Both should apply correctly regardless of order in the list
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 3, "AAA"),
            new(3, 0, 3, 3, "CCC")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("AAA\nbbb\nCCC", result);
    }

    [Fact]
    public void ApplyEdits_MultipleEdits_ReverseSorted_StillCorrect()
    {
        var source = "aaa\nbbb\nccc";
        // Supply edits in top-to-bottom order; they should still be applied correctly
        var edits = new List<TextEdit>
        {
            new(3, 0, 3, 3, "CCC"),
            new(1, 0, 1, 3, "AAA")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("AAA\nbbb\nCCC", result);
    }

    [Fact]
    public void ApplyEdits_MultipleEdits_LineCountChange_PreservesPositions()
    {
        var source = "aaa\nbbb\nccc\nddd";
        // First edit (line 3): replace "ccc" with two lines — shifts line count
        // Second edit (line 1): replace "aaa" with "AAA"
        // If applied top-to-bottom, the line-3 edit would shift and corrupt the result
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 3, "AAA"),
            new(3, 0, 3, 3, "CCC-1\nCCC-2")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("AAA\nbbb\nCCC-1\nCCC-2\nddd", result);
    }

    [Fact]
    public void ApplyEdits_MultipleEditsOnSameLine_RightToLeft()
    {
        var source = "hello world foo";
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 5, "HELLO"),
            new(1, 12, 1, 15, "FOO")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("HELLO world FOO", result);
    }

    // ── Edits That Change Line Count ────────────────────────────────────

    [Fact]
    public void ApplyEdits_InsertNewline_SplitsLine()
    {
        var source = "before after";
        var edits = new List<TextEdit>
        {
            new(1, 6, 1, 7, "\n")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("before\nafter", result);
    }

    [Fact]
    public void ApplyEdits_InsertMultipleLines_IncreasesLineCount()
    {
        var source = "line one\nline three";
        // Insert at beginning of line 2
        var edits = new List<TextEdit>
        {
            new(2, 0, 2, 0, "line two\n")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("line one\nline two\nline three", result);
    }

    [Fact]
    public void ApplyEdits_DeleteMultipleLines_DecreasesLineCount()
    {
        var source = "line one\nline two\nline three\nline four";
        // Delete lines 2 and 3
        var edits = new List<TextEdit>
        {
            new(2, 0, 4, 0, "")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("line one\nline four", result);
    }

    [Fact]
    public void ApplyEdits_DeleteLastLineWithoutTrailingNewline_RemovesLine()
    {
        var source = "line one\nline two";
        var edits = new List<TextEdit>
        {
            new(2, 0, 3, 0, "")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("line one", result);
    }

    [Fact]
    public void ApplyEdits_ReplaceWithMoreLines_ExpandsDocument()
    {
        var source = "one\ntwo\nthree";
        // Replace "two" with two lines
        var edits = new List<TextEdit>
        {
            new(2, 0, 2, 3, "TWO-A\nTWO-B")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("one\nTWO-A\nTWO-B\nthree", result);
    }

    [Fact]
    public void ApplyEdits_ReplaceMultiLinesWithSingle_CollapsesDocument()
    {
        var source = "one\ntwo\nthree\nfour";
        // Replace lines 2-3 with a single line
        var edits = new List<TextEdit>
        {
            new(2, 0, 3, 5, "MERGED")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("one\nMERGED\nfour", result);
    }

    // ── Edge Cases ──────────────────────────────────────────────────────

    [Fact]
    public void ApplyEdits_AppendAtOnePastEnd_AddsAtEnd()
    {
        var source = "only line";
        // EOF insertion is allowed at one line past the document, column 0.
        var edits = new List<TextEdit>
        {
            new(2, 0, 2, 0, "appended")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("only line\nappended", result);
    }

    [Fact]
    public void ApplyEdits_AppendFarPastEnd_ThrowsInsteadOfClamping()
    {
        var source = "only line";
        var edits = new List<TextEdit>
        {
            new(99, 0, 99, 0, "appended")
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("outside the document", ex.Message);
    }

    [Fact]
    public void ApplyEdits_InsertAtLineStart_PrependsToLine()
    {
        var source = "hello";
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 0, ">> ")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal(">> hello", result);
    }

    [Fact]
    public void ApplyEdits_InsertAtLineEnd_AppendsToLine()
    {
        var source = "hello";
        var edits = new List<TextEdit>
        {
            new(1, 5, 1, 5, " world")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("hello world", result);
    }

    [Fact]
    public void ApplyEdits_CrlfSource_ColumnsExcludeCarriageReturn()
    {
        var source = "alpha\r\nbeta\r\ngamma";
        var edits = new List<TextEdit>
        {
            new(2, 4, 2, 4, "!")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("alpha\nbeta!\ngamma", result);
    }

    [Fact]
    public void ValidateAndSortEdits_CrlfSource_RejectsColumnPastLogicalLineEnd()
    {
        var source = "alpha\r\nbeta\r\ngamma";
        var edits = new List<TextEdit>
        {
            new(2, 5, 2, 5, "!")
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ValidateAndSortEdits(source, edits));
        Assert.Contains("outside the document", ex.Message);
    }

    [Fact]
    public void SourceTextLines_SplitLogicalLines_StripsCrLfAndStandaloneCrSeparators()
    {
        Assert.Equal(new[] { "one", "two", "three" },
            SourceTextLines.SplitLogicalLines("one\r\ntwo\rthree"));
    }

    [Fact]
    public void ApplyEdits_ReplaceEntireSingleLineContent()
    {
        var source = "old content";
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 11, "new content")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("new content", result);
    }

    [Fact]
    public void ApplyEdits_EmptySource_InsertCreatesContent()
    {
        var source = "";
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 0, "new line")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("new line", result);
    }

    // ── Overlapping Edit Detection ──────────────────────────────────────

    [Fact]
    public void ApplyEdits_OverlappingSameLine_Throws()
    {
        var source = "abcdefghijklmnop";
        var edits = new List<TextEdit>
        {
            new(1, 2, 1, 8, "XX"),   // replace cols 2-8
            new(1, 5, 1, 12, "YY")   // replace cols 5-12 (overlaps)
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Overlapping edits detected", ex.Message);
    }

    [Fact]
    public void ApplyEdits_OverlappingAcrossLines_Throws()
    {
        var source = "line1\nline2\nline3\nline4\nline5";
        var edits = new List<TextEdit>
        {
            new(2, 0, 4, 0, "A"),  // spans lines 2-4
            new(3, 0, 5, 0, "B")   // spans lines 3-5 (overlaps)
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Overlapping edits detected", ex.Message);
    }

    [Fact]
    public void ApplyEdits_AdjacentNonOverlapping_Succeeds()
    {
        var source = "abcdefghij";
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 5, "ABCDE"),  // cols 0-5
            new(1, 5, 1, 10, "FGHIJ")  // cols 5-10 (adjacent, not overlapping)
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("ABCDEFGHIJ", result);
    }

    [Fact]
    public void ApplyEdits_FullyNestedEdit_Throws()
    {
        var source = "abcdefghijklmnop";
        var edits = new List<TextEdit>
        {
            new(1, 0, 1, 15, "OUTER"),  // entire line
            new(1, 3, 1, 8, "INNER")    // nested inside
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Overlapping edits detected", ex.Message);
    }

    [Fact]
    public void ApplyEdits_SameStartInsertAndReplace_Throws()
    {
        var source = "abcdefghij";
        var edits = new List<TextEdit>
        {
            new(1, 2, 1, 4, "RR"),  // replace cols 2-4
            new(1, 2, 1, 2, "I")    // insert at col 2 (same start)
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Overlapping edits detected", ex.Message);
    }

    [Fact]
    public void ApplyEdits_SameStartShorterAndLongerReplace_Throws()
    {
        var source = "abcdefghij";
        var edits = new List<TextEdit>
        {
            new(1, 2, 1, 5, "XX"),  // replace cols 2-5
            new(1, 2, 1, 8, "YY")  // replace cols 2-8 (same start, wider)
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Overlapping edits detected", ex.Message);
    }

    [Fact]
    public void ApplyEdits_SamePositionZeroWidthInserts_PreservesInputOrder()
    {
        var source = "abcdef";
        var edits = new List<TextEdit>
        {
            new(1, 3, 1, 3, "X"),  // insert at col 3
            new(1, 3, 1, 3, "Y")   // insert at col 3 (same position, both zero-width)
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("abcXYdef", result);
    }

    [Fact]
    public void ApplyEdits_EndBeforeStart_ThrowsInsteadOfSilentlyReordering()
    {
        var source = "abcdef";
        var edits = new List<TextEdit>
        {
            new(1, 5, 1, 2, "XX")
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Invalid edit range", ex.Message);
    }

    [Fact]
    public void ApplyEdits_LineAndColumnMustBeNonNegativeAndOneBasedLines()
    {
        var source = "abcdef";
        var edits = new List<TextEdit>
        {
            new(0, 0, 1, 0, "XX")
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("Invalid edit position", ex.Message);
    }

    [Fact]
    public void ApplyEdits_ColumnPastLineEnd_ThrowsInsteadOfClamping()
    {
        var source = "abcdef";
        var edits = new List<TextEdit>
        {
            new(1, 99, 1, 99, "XX")
        };

        var ex = Assert.Throws<InvalidOperationException>(
            () => FixApplicator.ApplyEdits(source, edits));
        Assert.Contains("outside the document", ex.Message);
    }
}

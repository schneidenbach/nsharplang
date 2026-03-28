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
    public void ApplyEdits_AppendPastEnd_AddsAtEnd()
    {
        var source = "only line";
        // Edit starts beyond the last line
        var edits = new List<TextEdit>
        {
            new(99, 0, 99, 0, "appended")
        };

        var result = FixApplicator.ApplyEdits(source, edits);

        Assert.Equal("only line\nappended", result);
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
}

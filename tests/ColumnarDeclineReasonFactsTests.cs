using NSharpLang.Compiler;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarDeclineReasonFactsTests
{
    [Theory]
    [InlineData(0, 0, 0)]
    [InlineData(4, 0, 4)]
    [InlineData(5, -1, -1)]
    [InlineData(6, -1, -1)]
    [InlineData(7, 1, 0)]
    [InlineData(9, 1, 2)]
    [InlineData(10, -1, -1)]
    [InlineData(11, -1, -1)]
    [InlineData(12, 2, 0)]
    public void MergedOffsetMapping_AccountsForSeparators(int offset, int expectedFileIndex, int expectedLocalOffset)
    {
        var fileLengths = new[] { 5, 3, 4 };

        Assert.Equal(expectedFileIndex, ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, offset));
        Assert.Equal(expectedLocalOffset, ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, offset));
    }

    [Fact]
    public void MergedOffsetMapping_SingleFileUsesIdentityOffsets()
    {
        var fileLengths = new[] { 5 };

        Assert.Equal(0, ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 3));
        Assert.Equal(3, ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 3));
        Assert.Equal(-1, ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 5));
        Assert.Equal(-1, ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, -1));
    }

    [Theory]
    [InlineData("one\ntwo\nthree", 0, 1, 1)]
    [InlineData("one\ntwo\nthree", 4, 2, 1)]
    [InlineData("one\ntwo\nthree", 6, 2, 3)]
    [InlineData("one\r\ntwo\r\nthree", 5, 2, 1)]
    [InlineData("one\r\ntwo\r\nthree", 8, 2, 4)]
    [InlineData("one\r\ntwo\r\nthree", 10, 3, 1)]
    public void LineAndColumnFromOffset_HandleLfAndCrLf(string source, int offset, int expectedLine, int expectedColumn)
    {
        Assert.Equal(expectedLine, ColumnarDeclineReasonFacts.LineFromOffset(source, offset));
        Assert.Equal(expectedColumn, ColumnarDeclineReasonFacts.ColumnFromOffset(source, offset));
    }

    [Fact]
    public void FormatDetail_IncludesSiteMessageMemberAndLocation()
    {
        var reason = new ColumnarDeclineReason(
            "emit.statement.unhandled-kind",
            "unsupported statement (node kind 29)",
            42,
            6,
            "Main");

        var detail = ColumnarDeclineReasonFacts.FormatDetail(reason, "Program.nl", 15, 5);

        Assert.Equal(
            "Declined at emit.statement.unhandled-kind: unsupported statement (node kind 29) in 'Main' (Program.nl:15:5).",
            detail);
    }

    [Fact]
    public void FormatTraceLine_IsSingleLineMachineReadableText()
    {
        var reason = new ColumnarDeclineReason(
            "emit.call.instance-member-unmodeled",
            "string.CompareTo with 1 argument is not modeled",
            91,
            19,
            "Main");

        Assert.Equal(
            "decline site=emit.call.instance-member-unmodeled message=\"string.CompareTo with 1 argument is not modeled\" span=91:19 member=\"Main\" location=Program.nl:15:5",
            ColumnarDeclineReasonFacts.FormatTraceLine(reason, "Program.nl", 15, 5));
    }

    [Fact]
    public void EmissionDiagnosticFactories_PreserveFirstSentenceAndAttachLocation()
    {
        var error = ColumnarEmissionDiagnostics.RequiredEmissionError(
            "Hello",
            "Declined at emit.expression.unhandled-kind: unsupported expression.",
            "Program.nl",
            3,
            9,
            4);

        Assert.StartsWith(
            "Columnar emission is required for 'Hello', but the columnar backend declined.",
            error.Message);
        Assert.EndsWith(" Declined at emit.expression.unhandled-kind: unsupported expression.", error.Message);
        Assert.Equal("Program.nl", error.FileName);
        Assert.Equal(3, error.Line);
        Assert.Equal(9, error.Column);
        Assert.Equal(4, error.Length);
    }
}

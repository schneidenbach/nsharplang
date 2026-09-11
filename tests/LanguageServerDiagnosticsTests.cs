using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Xunit;

namespace NSharpLang.Tests;

public class LanguageServerDiagnosticsTests
{
    [Fact]
    public void LspLinterDiagnostic_UsesExactLinterSpan()
    {
        var diagnostic = new Diagnostic(
            "NL012",
            "Parameter 'unusedName' in 'greet' is never read — is it needed?",
            new Location(1, 12, "Program.nl"),
            DiagnosticSeverity.Info,
            "Prefix with '_' if this is intentional",
            "unusedName".Length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(11, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(21, (int)lspDiagnostic.Range.End.Character);
    }

    // ---------------------------------------------------------------------------------------------
    // Converter conversion-invariant coverage (Unit 12).
    //
    // These tests exercise LspDiagnosticConverter directly with hand-constructed CompilerError /
    // Diagnostic values so the 1-based -> 0-based, end-exclusive, length>=1 and clamp invariants are
    // asserted independently of any analyzer raise-site span (which other units own).
    // ---------------------------------------------------------------------------------------------

    [Theory]
    // Column 1, length 1: minimal span at the very start of a line.
    [InlineData(1, 1, 1, 0, 0, 1)]
    // Mid-line span of several columns.
    [InlineData(5, 10, 4, 4, 9, 13)]
    // Length defaults below 1 are forced to a single column.
    [InlineData(3, 3, 0, 2, 2, 3)]
    [InlineData(3, 3, -7, 2, 2, 3)]
    // Negative/zero line and column are clamped to 0 without throwing.
    [InlineData(0, 0, 1, 0, 0, 1)]
    [InlineData(-4, -9, 1, 0, 0, 1)]
    // Large length with no source snippet is left intact (end-exclusive).
    [InlineData(2, 1, 250, 1, 0, 250)]
    public void Converter_CompilerError_AppliesConversionInvariants(
        int line,
        int column,
        int length,
        int expectedLine0,
        int expectedStartCharacter,
        int expectedEndCharacter)
    {
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line, column, ErrorSeverity.Error)
        {
            Length = length
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(expectedStartCharacter, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(expectedEndCharacter, (int)lspDiagnostic.Range.End.Character);
        Assert.True(lspDiagnostic.Range.End.Character > lspDiagnostic.Range.Start.Character,
            "End character must stay strictly greater than start (span underlines at least one column).");
    }

    [Fact]
    public void Converter_CompilerError_SpanAtEndOfLine_StaysExclusiveWithinLine()
    {
        // "abc" is 3 chars; a length-1 span on the final char ('c') ends exactly at the line length.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 1, column: 3, ErrorSeverity.Error)
        {
            Length = 1,
            SourceSnippet = "abc"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(3, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Converter_CompilerError_OverlongSpan_IsClampedToVisibleLineLength()
    {
        // A defective length that would otherwise overflow past the end of the visible line must be
        // clamped to the line length so the squiggle does not bleed into virtual whitespace.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 2, column: 5, ErrorSeverity.Error)
        {
            Length = 100,
            SourceSnippet = "    nums := [1, 2"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        // "    nums := [1, 2" is 17 characters; the end is clamped to that visible length.
        Assert.Equal("    nums := [1, 2".Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Converter_CompilerError_OverlongSpan_NeverCollapsesBelowOneColumn()
    {
        // Even when the start sits at (or past) the visible end of the line, the clamp must keep the
        // range non-empty: end stays strictly greater than start.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 1, column: 6, ErrorSeverity.Error)
        {
            Length = 50,
            SourceSnippet = "abcd"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(5, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(6, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Converter_CompilerError_MultiLineSnippet_ClampsAgainstFirstLineOnly()
    {
        // SourceSnippet may carry more than the starting line; the span is single-line by contract so
        // the clamp considers only the first physical line and never wraps end onto a later line.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 1, column: 1, ErrorSeverity.Error)
        {
            Length = 100,
            SourceSnippet = "abc\ndefghijklmnop"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal("abc".Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Theory]
    [InlineData(1, 1, 1, 0, 0, 1)]
    [InlineData(7, 12, 10, 6, 11, 21)]
    [InlineData(3, 3, 0, 2, 2, 3)]
    [InlineData(0, 0, -3, 0, 0, 1)]
    public void Converter_LinterDiagnostic_AppliesConversionInvariants(
        int line,
        int column,
        int length,
        int expectedLine0,
        int expectedStartCharacter,
        int expectedEndCharacter)
    {
        var diagnostic = new Diagnostic(
            "NL012",
            "synthetic",
            new Location(line, column, "Program.nl"),
            DiagnosticSeverity.Info,
            Suggestion: null,
            Length: length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(expectedStartCharacter, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(expectedEndCharacter, (int)lspDiagnostic.Range.End.Character);
        Assert.True(lspDiagnostic.Range.End.Character > lspDiagnostic.Range.Start.Character);
    }

    [Theory]
    [InlineData(DiagnosticSeverity.Error, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error)]
    [InlineData(DiagnosticSeverity.Warning, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning)]
    [InlineData(DiagnosticSeverity.Info, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Information)]
    public void Converter_LinterDiagnostic_MapsSeverity(
        DiagnosticSeverity compilerSeverity,
        OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity expected)
    {
        var diagnostic = new Diagnostic(
            "NL001",
            "synthetic",
            new Location(1, 1, "Program.nl"),
            compilerSeverity,
            Length: 1);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(expected, lspDiagnostic.Severity);
    }

    [Theory]
    [InlineData(ErrorSeverity.Error, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error)]
    [InlineData(ErrorSeverity.Warning, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning)]
    public void Converter_CompilerError_MapsSeverity(
        ErrorSeverity compilerSeverity,
        OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity expected)
    {
        var error = new CompilerError(ErrorCode.TypeMismatch, "synthetic", line: 1, column: 1, compilerSeverity);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(expected, lspDiagnostic.Severity);
    }

    /// <summary>
    /// Coverage sweep: every compiler ErrorCode (NL1xx-NL9xx) and every linter rule (NL0xx) must
    /// produce a deterministic LSP Range obeying the conversion invariants. This guards against a new
    /// diagnostic code being added without the converter being exercised for it.
    /// </summary>
    [Fact]
    public void Converter_EveryDiagnosticCode_ProducesValidLspRange()
    {
        const int line = 4;
        const int column = 7;
        const int length = 5;

        foreach (ErrorCode code in System.Enum.GetValues<ErrorCode>())
        {
            var severity = code is ErrorCode.VisibilityConventionWarning
                or ErrorCode.ReferenceLoadFailure
                ? ErrorSeverity.Warning
                : ErrorSeverity.Error;

            var error = new CompilerError(code, $"synthetic {code}", line, column, severity)
            {
                Length = length
            };

            var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

            Assert.Equal($"NL{(int)code:D3}", lspDiagnostic.Code!.Value.String);
            Assert.Equal("N#", lspDiagnostic.Source);
            Assert.Equal(line - 1, (int)lspDiagnostic.Range.Start.Line);
            Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
            Assert.Equal(column - 1 + length, (int)lspDiagnostic.Range.End.Character);
        }

        foreach (var descriptor in DiagnosticCatalog.LinterDescriptors)
        {
            var diagnostic = new Diagnostic(
                descriptor.Code,
                $"synthetic {descriptor.Code}",
                new Location(line, column, "Program.nl"),
                descriptor.DefaultSeverity,
                Length: length);

            var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

            Assert.Equal(descriptor.Code, lspDiagnostic.Code!.Value.String);
            Assert.Equal("N#", lspDiagnostic.Source);
            Assert.Equal(line - 1, (int)lspDiagnostic.Range.Start.Line);
            Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
            Assert.Equal(column - 1 + length, (int)lspDiagnostic.Range.End.Character);
        }
    }

}

using System;
using NSharpLang.Compiler;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;
using LspDiagnosticSeverity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using CompilerDiagnostic = NSharpLang.Compiler.Diagnostic;
using CompilerDiagnosticSeverity = NSharpLang.Compiler.DiagnosticSeverity;

namespace NSharpLang.LanguageServer.Services;

internal static class LspDiagnosticConverter
{
    public static LspDiagnostic FromCompilerError(CompilerError error)
    {
        var range = BuildRange(error.Line, error.Column, error.Length, error.SourceSnippet);

        return new LspDiagnostic
        {
            Range = range,
            Severity = error.Severity == ErrorSeverity.Warning
                ? LspDiagnosticSeverity.Warning
                : LspDiagnosticSeverity.Error,
            Code = error.DiagnosticId,
            Source = "N#",
            Message = error.FormatForTooling(includeCode: true, includeLocation: false)
        };
    }

    public static LspDiagnostic FromLinterDiagnostic(CompilerDiagnostic diagnostic)
    {
        var range = BuildRange(diagnostic.Location.Line, diagnostic.Location.Column, diagnostic.Length, sourceSnippet: null);

        return new LspDiagnostic
        {
            Range = range,
            Severity = diagnostic.Severity switch
            {
                CompilerDiagnosticSeverity.Error => LspDiagnosticSeverity.Error,
                CompilerDiagnosticSeverity.Warning => LspDiagnosticSeverity.Warning,
                CompilerDiagnosticSeverity.Info => LspDiagnosticSeverity.Information,
                _ => LspDiagnosticSeverity.Warning
            },
            Code = diagnostic.Code,
            Source = "N#",
            Message = diagnostic.Message
        };
    }

    /// <summary>
    /// Converts a 1-based, single-line compiler/linter span into an LSP <see cref="LspRange"/>.
    /// </summary>
    /// <remarks>
    /// Conversion invariants:
    /// <list type="bullet">
    /// <item>LSP positions are 0-based, so the 1-based line and column are each decremented by one.</item>
    /// <item>The end position is exclusive: <c>endCharacter = startCharacter + length</c>.</item>
    /// <item>Negative inputs are clamped to 0 (defensive against malformed spans).</item>
    /// <item>Length is forced to at least 1 so every diagnostic underlines at least one column.</item>
    /// <item>The span is single-line by contract: the compiler resolves <c>Length</c> against the
    /// offending token's source line (see <c>DiagnosticSpanResolver</c>), so start and end always share
    /// the same line. We therefore never wrap to <c>endLine = startLine + 1</c>; doing so would require
    /// per-line length context the converter does not own.</item>
    /// <item>When the originating source line is available (<paramref name="sourceSnippet"/>), the
    /// exclusive end character is clamped to the line length so a malformed over-long span cannot push
    /// the squiggle past the visible end of the line.</item>
    /// </list>
    /// </remarks>
    private static LspRange BuildRange(int oneBasedLine, int oneBasedColumn, int length, string? sourceSnippet)
    {
        var line = Math.Max(0, oneBasedLine - 1);
        var startCharacter = Math.Max(0, oneBasedColumn - 1);
        var safeLength = Math.Max(1, length);
        var endCharacter = startCharacter + safeLength;

        // Clamp the exclusive end to the visible line length when we know it, but never collapse
        // the range below a single column (end must stay strictly greater than start).
        if (!string.IsNullOrEmpty(sourceSnippet))
        {
            var lineEnd = LineLength(sourceSnippet);
            if (endCharacter > lineEnd)
            {
                endCharacter = Math.Max(startCharacter + 1, lineEnd);
            }
        }

        return new LspRange(line, startCharacter, line, endCharacter);
    }

    /// <summary>
    /// Length of the first physical line of <paramref name="sourceSnippet"/>, excluding any trailing
    /// newline. The snippet stores the offending token's source line; multi-line snippets only clamp
    /// against their first line, which is the line the span starts on.
    /// </summary>
    private static int LineLength(string sourceSnippet)
    {
        var newlineIndex = sourceSnippet.IndexOfAny(new[] { '\n', '\r' });
        return newlineIndex >= 0 ? newlineIndex : sourceSnippet.Length;
    }
}

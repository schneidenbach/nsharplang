using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;
using LspDiagnosticSeverity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using CompilerDiagnostic = NSharpLang.Compiler.Diagnostic;
using CompilerDiagnosticSeverity = NSharpLang.Compiler.DiagnosticSeverity;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// The compiler's diagnostics as the wire carries them.
///
/// HOW WIDE A SQUIGGLE IS AND WHERE IT STARTS is N#-owned by <c>EditorDiagnosticSpanFacts</c> —
/// the 0-based conversion, the exclusive end, the two clamps that keep a malformed span legal and
/// the clamp against the offending source line. What is left here is the protocol: OmniSharp's
/// Diagnostic, its Range and the wire numbers of its severities.
/// </summary>
internal static class LspDiagnosticConverter
{
    public static LspDiagnostic FromCompilerError(CompilerError error)
    {
        var range = ToRange(EditorDiagnosticSpanFacts.Span(error.Line, error.Column, error.Length, error.SourceSnippet));

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
        var range = ToRange(EditorDiagnosticSpanFacts.Span(diagnostic.Location.Line, diagnostic.Location.Column, diagnostic.Length, null));

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

    private static LspRange ToRange(EditorDiagnosticSpanRow span)
        => new LspRange(span.Line, span.StartCharacter, span.Line, span.EndCharacter);
}

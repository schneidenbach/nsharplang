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
        var line = Math.Max(0, error.Line - 1);
        var column = Math.Max(0, error.Column - 1);
        var length = Math.Max(1, error.Length);

        return new LspDiagnostic
        {
            Range = new LspRange(line, column, line, column + length),
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
        var line = Math.Max(0, diagnostic.Location.Line - 1);
        var column = Math.Max(0, diagnostic.Location.Column - 1);
        var length = Math.Max(1, diagnostic.Length);

        return new LspDiagnostic
        {
            Range = new LspRange(line, column, line, column + length),
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
}

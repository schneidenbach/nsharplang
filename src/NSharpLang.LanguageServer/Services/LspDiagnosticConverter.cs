using System;
using NSharpLang.Compiler;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;
using LspDiagnosticSeverity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

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
}

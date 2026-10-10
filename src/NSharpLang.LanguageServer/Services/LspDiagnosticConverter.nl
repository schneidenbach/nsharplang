namespace NSharpLang.LanguageServer.Services

import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// The compiler's diagnostics as the wire carries them.
//
// HOW WIDE A SQUIGGLE IS AND WHERE IT STARTS is N#-owned by `EditorDiagnosticSpanFacts` — the
// 0-based conversion, the exclusive end, the two clamps that keep a malformed span legal and the
// clamp against the offending source line. What is left here is the protocol: OmniSharp's
// Diagnostic, its Range and the wire numbers of its severities.
//
// Every OmniSharp name is written in full. Both `Diagnostic` and `DiagnosticSeverity` are declared
// on BOTH sides of this file — the compiler's and the protocol's — and N# has no import alias, so
// the qualified spelling is what keeps the two vocabularies apart.
class LspDiagnosticConverter {
    static func FromCompilerError(error: CompilerError): OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic {
        range := toRange(EditorDiagnosticSpanFacts.Span(error.Line, error.Column, error.Length, error.SourceSnippet))

        severity := OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error
        if error.Severity == ErrorSeverity.Warning {
            severity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning
        }

        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic {
            Range: range,
            Severity: severity,
            Code: new OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticCode(error.DiagnosticId),
            Source: "N#",
            Message: error.FormatForTooling(true, false)
        }
    }

    static func FromLinterDiagnostic(diagnostic: Diagnostic): OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic {
        location := diagnostic.Location
        range := toRange(EditorDiagnosticSpanFacts.Span(location.Line, location.Column, diagnostic.Length, null))

        severity := OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning
        if diagnostic.Severity == DiagnosticSeverity.Error {
            severity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error
        } else if diagnostic.Severity == DiagnosticSeverity.Warning {
            severity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning
        } else if diagnostic.Severity == DiagnosticSeverity.Info {
            severity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Information
        }

        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic {
            Range: range,
            Severity: severity,
            Code: new OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticCode(diagnostic.Code),
            Source: "N#",
            Message: diagnostic.Message
        }
    }

    static func toRange(span: EditorDiagnosticSpanRow): OmniSharp.Extensions.LanguageServer.Protocol.Models.Range => new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(span.Line, span.StartCharacter, span.Line, span.EndCharacter)
}

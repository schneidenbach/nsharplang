namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler

// WHICH DIAGNOSTIC A CODE ACTION IS FOR.
//
// A client asks for code actions at a range and hands back the diagnostics IT is showing there.
// Those are wire shapes — a code, a range and a message — and the fix service needs the compiler's
// own diagnostic. Finding it again is this answer: the editor's two lists are searched for one
// that agrees about the code AND the exact position.
//
// THE LINTER'S LIST IS SEARCHED FIRST and wins, because a linter diagnostic IS a `Diagnostic`
// already and carries the suggestion its rule wrote. A compiler error has to be rebuilt into one,
// and rebuilding drops everything a fix does not read: the explanation, the related information
// and the docs link stay behind, and the SUGGESTION FALLS BACK to the contextual hint when the
// error has no suggestion of its own.
//
// THE POSITION MUST MATCH EXACTLY. A diagnostic one column away is a different diagnostic, and
// offering its fix would edit the wrong span.
class EditorCodeActionFacts {
    static func MatchLinterDiagnostic(diagnostics: List<Diagnostic>?, code: string, oneBasedLine: int, oneBasedColumn: int): Diagnostic? {
        if diagnostics == null {
            return null
        }

        for diagnostic in diagnostics {
            if diagnostic.Code == code && diagnostic.Location.Line == oneBasedLine && diagnostic.Location.Column == oneBasedColumn {
                return diagnostic
            }
        }

        return null
    }

    static func MatchCompilerError(errors: List<CompilerError>?, code: string, oneBasedLine: int, oneBasedColumn: int): CompilerError? {
        if errors == null {
            return null
        }

        for error in errors {
            if error.DiagnosticId == code && error.Line == oneBasedLine && error.Column == oneBasedColumn {
                return error
            }
        }

        return null
    }

    // A COMPILER ERROR AS A DIAGNOSTIC A FIX CAN READ. Severity collapses to the two a fix
    // distinguishes, and the length never falls below one so a fix always has a span to replace.
    static func AsDiagnostic(error: CompilerError): Diagnostic {
        severity := DiagnosticSeverity.Warning
        if error.Severity == ErrorSeverity.Error {
            severity = DiagnosticSeverity.Error
        }

        suggestion := error.Suggestion
        if suggestion == null {
            suggestion = error.ContextualHint
        }

        location := new Location(error.Line, error.Column, error.FileName)
        return new Diagnostic(error.DiagnosticId, error.Message, location, severity, suggestion, Math.Max(error.Length, 1))
    }

    // The whole search, in the order the editor asks it.
    static func DiagnosticAt(linterDiagnostics: List<Diagnostic>?, compilerErrors: List<CompilerError>?, code: string?, oneBasedLine: int, oneBasedColumn: int): Diagnostic? {
        if code == null {
            return null
        }

        linterDiagnostic := MatchLinterDiagnostic(linterDiagnostics, code, oneBasedLine, oneBasedColumn)
        if linterDiagnostic != null {
            return linterDiagnostic
        }

        compilerError := MatchCompilerError(compilerErrors, code, oneBasedLine, oneBasedColumn)
        if compilerError == null {
            return null
        }

        return AsDiagnostic(compilerError)
    }
}

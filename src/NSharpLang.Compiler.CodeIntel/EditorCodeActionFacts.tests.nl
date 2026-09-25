namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler

// CONTRACTS FOR FINDING THE DIAGNOSTIC A FIX IS FOR. These came out of `CodeActionHandler.cs`,
// where the search and the rebuild were private and reachable only through an OmniSharp request.
func EcaLinter(code: string, message: string, line: int, column: int): Diagnostic {
    return new Diagnostic(code, message, new Location(line, column, "Program.nl"), DiagnosticSeverity.Warning, "drop it", 4)
}

func EcaLinterList(diagnostics: Diagnostic[]): List<Diagnostic> {
    list := new List<Diagnostic>()
    for diagnostic in diagnostics {
        list.Add(diagnostic)
    }

    return list
}

func EcaErrorList(errors: CompilerError[]): List<CompilerError> {
    list := new List<CompilerError>()
    for error in errors {
        list.Add(error)
    }

    return list
}

test "a code action finds the linter diagnostic at exactly that position" {
    wanted := EcaLinter("NL901", "unused import", 3, 1)
    diagnostics := EcaLinterList([EcaLinter("NL901", "unused import", 2, 1), wanted, EcaLinter("NL902", "unused local", 3, 1)])

    found := EditorCodeActionFacts.MatchLinterDiagnostic(diagnostics, "NL901", 3, 1)
    if found == null {
        throw new System.InvalidOperationException("expected the linter diagnostic at 3:1")
    }

    assert System.Object.ReferenceEquals(found, wanted)
    assert EditorCodeActionFacts.MatchLinterDiagnostic(diagnostics, "NL901", 3, 2) == null
    assert EditorCodeActionFacts.MatchLinterDiagnostic(null, "NL901", 3, 1) == null
}

test "a code action rebuilds a compiler error into a diagnostic a fix can read" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "bad token", 7, 9, ErrorSeverity.Error)
    error.FileName = "Program.nl"
    error.Length = 5
    error.ContextualHint = "did you mean ==?"

    rebuilt := EditorCodeActionFacts.AsDiagnostic(error)
    assert rebuilt.Code == error.DiagnosticId
    assert rebuilt.Message == "bad token"
    assert rebuilt.Location.Line == 7
    assert rebuilt.Location.Column == 9
    assert rebuilt.Location.FilePath == "Program.nl"
    assert rebuilt.Severity == DiagnosticSeverity.Error
    assert rebuilt.Length == 5
    assert rebuilt.Suggestion == "did you mean ==?"
}

// THE SUGGESTION FALLS BACK TO THE CONTEXTUAL HINT and a warning stays a warning.
test "a rebuilt diagnostic prefers the error's own suggestion" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "bad token", 1, 1, ErrorSeverity.Warning)
    error.Suggestion = "remove it"
    error.ContextualHint = "ignored"

    rebuilt := EditorCodeActionFacts.AsDiagnostic(error)
    assert rebuilt.Suggestion == "remove it"
    assert rebuilt.Severity == DiagnosticSeverity.Warning
}

// A LENGTH OF ZERO IS A SPAN A FIX CANNOT REPLACE, so it becomes one.
test "a rebuilt diagnostic always has a span" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "bad token", 1, 1, ErrorSeverity.Error)
    error.Length = 0

    rebuilt := EditorCodeActionFacts.AsDiagnostic(error)
    assert rebuilt.Length == 1
}

test "a code action searches the linter's list before the compiler's" {
    linterDiagnostic := EcaLinter("NL901", "from the linter", 3, 1)
    error := new CompilerError(ErrorCode.InvalidSyntax, "from the compiler", 3, 1, ErrorSeverity.Error)
    error.DiagnosticIdOverride = "NL901"

    found := EditorCodeActionFacts.DiagnosticAt(EcaLinterList([linterDiagnostic]), EcaErrorList([error]), "NL901", 3, 1)
    if found == null {
        throw new System.InvalidOperationException("expected a diagnostic at 3:1")
    }

    assert found.Message == "from the linter"
}

test "a code action falls through to the compiler's list and then to nothing" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "from the compiler", 3, 1, ErrorSeverity.Error)
    error.DiagnosticIdOverride = "NL901"

    found := EditorCodeActionFacts.DiagnosticAt(null, EcaErrorList([error]), "NL901", 3, 1)
    if found == null {
        throw new System.InvalidOperationException("expected the rebuilt compiler diagnostic")
    }

    assert found.Message == "from the compiler"
    assert EditorCodeActionFacts.DiagnosticAt(null, EcaErrorList([error]), "NL901", 4, 1) == null
    assert EditorCodeActionFacts.DiagnosticAt(null, EcaErrorList([error]), null, 3, 1) == null
    assert EditorCodeActionFacts.DiagnosticAt(null, null, "NL901", 3, 1) == null
}

namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE DIAGNOSTICS (task 019 slice 15).
//
// The whole family was six C# members behind one snapshot-bound entry, so every one of the answers
// below previously needed a project on disk to ask. Asked directly, the family states EIGHT things
// that were prose, accident, or unreachable:
//   (a) COMPILER ERRORS COME FIRST AND LINT SECOND, and nothing re-sorts the list afterwards.
//   (b) THE `--file` FILTER IS APPLIED TWICE WITH DIFFERENT OPERANDS: a compiler error is matched on
//       the error's OWN file string, and a lint row on the source file's FULL path.
//   (c) A COMPILER ERROR WITH NO FILE IS REPORTED AGAINST THE LITERAL `"unknown"` — and a `--file`
//       filter therefore hides it.
//   (d) THE PROJECT-ERROR ARM KEEPS `DocsUrl` NULL when the error carries none. Only the lint arm
//       always has one, and only `nlc check`'s own entry falls back to the catalog. Three arms,
//       three answers.
//   (e) A LINT DIAGNOSTIC'S LENGTH IS WIDENED TO 1 and its explanation/hint/type pair are ALWAYS
//       null — a lint row is structurally poorer than a compiler row and that is the contract.
//   (f) THE TWO SEVERITY MAPS ARE NOT THE SAME MAP: a compiler error has two levels, a lint
//       diagnostic three, and only the lint one can say `info`.
//   (g) SHADOWING SUPPRESSION IS BUILT FROM EVERY COMPILER ERROR, NOT THE FILTERED ONES, so a
//       `--file` query still suppresses using the whole project's shadowing errors.
//   (h) A BLANK-BUT-PRESENT SNIPPET IS REPLACED and a line of 0 is not: the fallback needs both a
//       blank snippet and a positive line.
// Every error built here carries a NON-BLANK snippet on purpose. The snippet fallback reads the
// file from DISK when the project's text cache does not hold it, so an error over a path that does
// not exist would throw — which is the inherited behaviour, and the reason the fallback is asked
// only in the one test that supplies a cached text.
func CidError(code: ErrorCode, message: string, fileName: string?, line: int, severity: ErrorSeverity): CompilerError {
    return new CompilerError(code, message, line, 7, severity) {
        FileName: fileName,
        Length: 4,
        SourceSnippet: "snip"
    }
}

func CidErrors(errors: CompilerError[]): List<CompilerError> {
    values := new List<CompilerError>()
    index := 0
    while index < errors.Length {
        values.Add(errors[index])
        index = index + 1
    }
    return values
}

func CidNoFiles(): List<string> {
    return new List<string>()
}

func CidNoUnits(): Dictionary<string, CompilationUnit> {
    return new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
}

func CidNoTexts(): Dictionary<string, string> {
    return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
}

func CidCodes(results: List<DiagnosticResult>): string {
    text := ""
    index := 0
    while index < results.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + results[index].Code + ":" + results[index].Severity
        index = index + 1
    }
    return text
}

test "compiler errors are reported in their own order, with severity mapped to two levels" {
    errors := CidErrors([
        CidError(ErrorCode.InvalidSyntax, "first", "/p/a.nl", 3, ErrorSeverity.Error),
        CidError(ErrorCode.InvalidSyntax, "second", "/p/b.nl", 4, ErrorSeverity.Warning)
    ])

    results := CodeIntelligenceDiagnostics.Build("/p", errors, CidNoFiles(), CidNoUnits(), CidNoTexts(), null)

    assert results.Count == 2
    assert CidCodes(results) == "NL103:error,NL103:warning"
    assert results[0].Message == "first"
    assert results[0].File == "a.nl"
    assert results[0].Line == 3
    assert results[0].Column == 7
    assert results[0].Length == 4
    assert results[1].File == "b.nl"
}

test "a compiler error with no file is reported against the literal unknown, and a filter hides it" {
    errors := CidErrors([CidError(ErrorCode.InvalidSyntax, "nowhere", null, 1, ErrorSeverity.Error)])

    unfiltered := CodeIntelligenceDiagnostics.Build("/p", errors, CidNoFiles(), CidNoUnits(), CidNoTexts(), null)
    assert unfiltered.Count == 1
    // The literal `"unknown"` is then RELATIVISED like any other path, so the reported file is a
    // computed route from the project root to `<cwd>/unknown` — never the bare word.
    assert unfiltered[0].File != "unknown"
    assert unfiltered[0].File.EndsWith("unknown", StringComparison.Ordinal)

    filtered := CodeIntelligenceDiagnostics.Build("/p", errors, CidNoFiles(), CidNoUnits(), CidNoTexts(), "a.nl")
    assert filtered.Count == 0
}

test "the project-error arm keeps a null DocsUrl and carries the error's own rich fields" {
    plain := new CompilerError(ErrorCode.InvalidSyntax, "plain", 2, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "snip"
    }
    rich := new CompilerError(ErrorCode.InvalidSyntax, "rich", 2, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        HumanExplanation: "why",
        ContextualHint: "hint",
        ExpectedType: "int",
        ActualType: "string",
        DocsUrl: "https://example.test/x",
        SourceSnippet: "let x = 1"
    }

    results := CodeIntelligenceDiagnostics.Build("/p", CidErrors([plain, rich]), CidNoFiles(), CidNoUnits(), CidNoTexts(), null)

    assert results[0].DocsUrl == null
    assert results[0].Explanation == null
    assert results[0].Hint == null
    assert results[1].DocsUrl == "https://example.test/x"
    assert results[1].Explanation == "why"
    assert results[1].Hint == "hint"
    assert results[1].ExpectedType == "int"
    assert results[1].ActualType == "string"
    assert results[1].SourceSnippet == "let x = 1"
}

test "the snippet fallback needs BOTH a blank snippet and a positive line" {
    texts := CidNoTexts()
    texts[System.IO.Path.GetFullPath("/p/a.nl")] = "alpha\nbeta\ngamma\n"

    blankAtLineTwo := new CompilerError(ErrorCode.InvalidSyntax, "m", 2, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "   "
    }
    blankAtLineZero := new CompilerError(ErrorCode.InvalidSyntax, "m", 0, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "   "
    }

    results := CodeIntelligenceDiagnostics.Build("/p", CidErrors([blankAtLineTwo, blankAtLineZero]), CidNoFiles(), CidNoUnits(), texts, null)

    assert results[0].SourceSnippet == "beta"
    assert results[1].SourceSnippet == "   "
}

test "the suggestion falls back to the joined suggestion LIST only when the single one is absent" {
    // Three DISTINCT lines: the family deduplicates on code, file and position, so three errors at
    // one position would collapse into one row before any of them could be compared.
    withSingle := new CompilerError(ErrorCode.InvalidSyntax, "m", 1, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "snip",
        Suggestion: "do this"
    }
    listOnly := new CompilerError(ErrorCode.InvalidSyntax, "m", 2, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "snip",
        Suggestions: CodeIntelligenceDiagnosticsSuggestions()
    }
    neither := new CompilerError(ErrorCode.InvalidSyntax, "m", 3, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "snip"
    }

    results := CodeIntelligenceDiagnostics.Build("/p", CidErrors([withSingle, listOnly, neither]), CidNoFiles(), CidNoUnits(), CidNoTexts(), null)

    assert results[0].Suggestion == "do this"
    assert results[1].Suggestion != null
    assert results[2].Suggestion == null
}

test "the shadowing file list is built from EVERY error and echoes the project-relative path" {
    errors := CidErrors([
        CidError(ErrorCode.ShadowedDeclaration, "shadow", "/p/a.nl", 1, ErrorSeverity.Error),
        CidError(ErrorCode.InvalidSyntax, "other", "/p/b.nl", 1, ErrorSeverity.Error),
        CidError(ErrorCode.ShadowedDeclaration, "blank file", "   ", 1, ErrorSeverity.Error),
        CidError(ErrorCode.ShadowedDeclaration, "no file", null, 1, ErrorSeverity.Error)
    ])

    files := CodeIntelligenceDiagnostics.CompilerShadowingErrorFiles(errors, "/p")

    assert files.Count == 1
    assert files[0] == "a.nl"
}

test "a lint diagnostic is structurally poorer than a compiler one, and its length is widened to 1" {
    diagnostic := new Diagnostic("NL020", "unused", new Location(9, 4, "/p/a.nl"), DiagnosticSeverity.Info, "drop it", 0)

    result := CodeIntelligenceDiagnostics.FromLintDiagnostic(diagnostic, "/p", "/p/a.nl", "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\n")

    assert result.Code == "NL020"
    assert result.Severity == "info"
    assert result.File == "a.nl"
    assert result.Line == 9
    assert result.Column == 4
    assert result.Length == 1
    assert result.SourceSnippet == "nine"
    assert result.Suggestion == "drop it"
    assert result.Explanation == null
    assert result.Hint == null
    assert result.ExpectedType == null
    assert result.ActualType == null
    assert result.DocsUrl != null
}

test "the two severity maps do not agree — only the lint map can say info" {
    assert CodeIntelligenceDiagnostics.SeverityText(ErrorSeverity.Error) == "error"
    assert CodeIntelligenceDiagnostics.SeverityText(ErrorSeverity.Warning) == "warning"
    assert CodeIntelligenceDiagnostics.LintSeverityText(DiagnosticSeverity.Error) == "error"
    assert CodeIntelligenceDiagnostics.LintSeverityText(DiagnosticSeverity.Warning) == "warning"
    assert CodeIntelligenceDiagnostics.LintSeverityText(DiagnosticSeverity.Info) == "info"
}

test "the source-text door prefers the cached FULL-PATH text and answers null for a null path" {
    texts := CidNoTexts()
    texts[System.IO.Path.GetFullPath("/p/a.nl")] = "cached"

    assert CodeIntelligenceSourceDoor.SourceText(texts, "/p/a.nl") == "cached"
    assert CodeIntelligenceSourceDoor.SourceText(texts, null) == null
}

test "nlc check's own entry differs from the project arm in exactly two places" {
    texts := CidNoTexts()
    texts["/p/a.nl"] = "alpha\nbeta\ngamma\n"

    blank := new CompilerError(ErrorCode.InvalidSyntax, "m", 2, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "   "
    }

    // (1) THE LOOKUP KEY IS THE ERROR'S RAW FILE STRING, not the full path the project arm uses —
    // which is why this entry finds a text keyed by the raw string and the project arm would not.
    found := CodeIntelligenceDiagnostics.FromCompilerError(blank, "/p", texts)
    assert found.SourceSnippet == "beta"

    // (2) THE DOCS URL FALLS BACK TO THE CATALOG. The project arm leaves it null. Asked with a
    // NON-blank snippet, because the project arm's full-path door would otherwise read from disk and
    // throw — which is itself the first difference, stated from the other side.
    filled := new CompilerError(ErrorCode.InvalidSyntax, "m", 2, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "snip"
    }
    assert found.DocsUrl != null
    assert CodeIntelligenceDiagnostics.FromProjectError(filled, "/p", "/p/a.nl", CidNoTexts()).DocsUrl == null
    assert CodeIntelligenceDiagnostics.FromCompilerError(filled, "/p", CidNoTexts()).DocsUrl != null

    // A NULL DICTIONARY IS NOT AN EMPTY ONE. Null skips the lookup entirely and leaves the blank
    // snippet UNTOUCHED; an empty dictionary runs the lookup and blanks it to null. This distinction
    // was unreachable while the parameter could not cross the boundary at all.
    assert CodeIntelligenceDiagnostics.FromCompilerError(blank, "/p", null).SourceSnippet == "   "
    assert CodeIntelligenceDiagnostics.FromCompilerError(blank, "/p", CidNoTexts()).SourceSnippet == null

    // A carried DocsUrl still wins over the catalog fallback.
    carried := new CompilerError(ErrorCode.InvalidSyntax, "m", 1, 1, ErrorSeverity.Error) {
        FileName: "/p/a.nl",
        SourceSnippet: "snip",
        DocsUrl: "https://example.test/own"
    }
    assert CodeIntelligenceDiagnostics.FromCompilerError(carried, "/p", null).DocsUrl == "https://example.test/own"
}

func CodeIntelligenceDiagnosticsSuggestions(): List<string> {
    values := new List<string>()
    values.Add("try one")
    values.Add("try two")
    return values
}

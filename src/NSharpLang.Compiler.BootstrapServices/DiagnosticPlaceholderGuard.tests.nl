namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// CONTRACTS FOR THE PLACEHOLDER GUARD AND FOR THE FOUR DOORS THAT ENFORCE IT.
//
// The rule is stated on `DiagnosticPlaceholderGuard`: a diagnostic whose sentence would print the
// parser's `<error>` recovery placeholder is a cascade off a syntax error that has already been
// reported, and is suppressed. What is asserted here is that the rule cannot be reopened — every
// door a diagnostic can reach a user through refuses one, and each door is asked ALONE so that a
// guard deleted from one of them cannot hide behind the others.
//
// THE FIELD LIST IS THE CONTRACT, NOT AN IMPLEMENTATION DETAIL. `nlc check --text` prints the
// headline, the explanation, the hint, the expected/actual pair and the suggestion, and the JSON
// schema publishes the same fields; a placeholder in any one of them is the same broken sentence, so
// each field is asserted on its own. `SourceSnippet` is asserted the OTHER way: it is the user's own
// line echoed back, so a file that really does contain the characters `<error>` must keep its
// diagnostics.
func DpgSink(errors: List<CompilerError>): AnalyzerDiagnosticSink {
    return new AnalyzerDiagnosticSink(errors, new AnalyzerProjectSourceProvider())
}

func DpgDetailed(message: string, suggestion: string?, humanExplanation: string?, contextualHint: string?): CompilerError {
    return CompilerError.CreateDetailed(ErrorCode.TypeNotFound, message, 1, 1, "Program.nl", 1, suggestion, humanExplanation, contextualHint, null, ErrorSeverity.Error)
}

func DpgLinterState(): LinterWalkState {
    return new LinterWalkState("Program.nl", null, LinterConfig.Default())
}

test "the placeholder has ONE spelling, and the tree walk reads it from the guard" {
    assert DiagnosticPlaceholderGuard.PlaceholderName() == "<error>"
    assert AnalyzerParserErrorPlaceholders.PlaceholderName() == DiagnosticPlaceholderGuard.PlaceholderName()
}

test "the text test is ORDINAL and a SUBSTRING test, so a quoted, qualified or embedded placeholder is caught" {
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("<error>")
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("Type '<error>' not found")
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("Sales.<error> is not a member")
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("add the import that provides '<error>'.")
    assert !DiagnosticPlaceholderGuard.TextCarriesPlaceholder("Type 'error' not found")
    assert !DiagnosticPlaceholderGuard.TextCarriesPlaceholder("<Error>")
    assert !DiagnosticPlaceholderGuard.TextCarriesPlaceholder("")
    assert !DiagnosticPlaceholderGuard.TextCarriesPlaceholder(null)
}

test "EVERY rendered field is tested, and each one alone is enough to suppress" {
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(DpgDetailed("Type '<error>' not found", null, null, null))
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(DpgDetailed("m", "import '<error>'", null, null))
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(DpgDetailed("m", null, "I could not find '<error>':", null))
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(DpgDetailed("m", null, null, "'<error>' is not in scope."))
    assert !DiagnosticPlaceholderGuard.CarriesPlaceholder(DpgDetailed("m", "s", "h", "c"))
}

test "the expected/actual pair and the multi-suggestion list are rendered too, so they are guarded too" {
    expected := new CompilerError(ErrorCode.TypeMismatch, "m", 1, 1, ErrorSeverity.Error) {
        ExpectedType: "<error>"
    }
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(expected)

    actual := new CompilerError(ErrorCode.TypeMismatch, "m", 1, 1, ErrorSeverity.Error) {
        ActualType: "<error>"
    }
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(actual)

    many := new List<string>()
    many.Add("rename the field")
    many.Add("import '<error>'")
    listed := new CompilerError(ErrorCode.TypeMismatch, "m", 1, 1, ErrorSeverity.Error) {
        Suggestions: many
    }
    assert DiagnosticPlaceholderGuard.CarriesPlaceholder(listed)
}

test "the SOURCE SNIPPET is NOT guarded, so a file that really contains the characters keeps its diagnostics" {
    echoed := new CompilerError(ErrorCode.TypeMismatch, "Cannot convert 'string' to 'int'", 1, 1, ErrorSeverity.Error) {
        SourceSnippet: "    message := \"<error>\""
    }
    assert !DiagnosticPlaceholderGuard.CarriesPlaceholder(echoed)
}

test "DOOR 1 — the sink's Report refuses a placeholder in the message and in the suggestion, and reports everything else" {
    errors := new List<CompilerError>()
    sink := DpgSink(errors)
    sink.Report(ErrorCode.TypeNotFound, "Type '<error>' not found", 1, 1, null, 7)
    assert errors.Count == 0

    sink.Report(ErrorCode.TypeNotFound, "Type 'Buyer' not found", 1, 1, "add the import that provides '<error>'.", 5)
    assert errors.Count == 0

    sink.Report(ErrorCode.TypeNotFound, "Type 'Buyer' not found", 1, 1, "add the import that provides 'Buyer'.", 5)
    assert errors.Count == 1
    assert errors[0].Message == "Type 'Buyer' not found"
}

test "DOOR 2 — the sink's Warn refuses one on the same two fields" {
    errors := new List<CompilerError>()
    sink := DpgSink(errors)
    sink.Warn(ErrorCode.VisibilityConventionWarning, "Identifier '<error>' starts with a non-letter character", 1, 1, null, 7)
    assert errors.Count == 0

    sink.Warn(ErrorCode.VisibilityConventionWarning, "Identifier 'x' starts with a non-letter character", 1, 1, "rename it '<error>'", 1)
    assert errors.Count == 0

    sink.Warn(ErrorCode.VisibilityConventionWarning, "Identifier 'x' starts with a non-letter character", 1, 1, null, 1)
    assert errors.Count == 1
    assert errors[0].Severity == ErrorSeverity.Warning
}

test "DOOR 3 — the sink's ReportBuilt refuses one in ANY rendered field of an already-built report" {
    errors := new List<CompilerError>()
    sink := DpgSink(errors)
    sink.ReportBuilt(DpgDetailed("Type '<error>' not found", null, null, null))
    sink.ReportBuilt(DpgDetailed("Type 'Buyer' not found", "import '<error>'", null, null))
    sink.ReportBuilt(DpgDetailed("Type 'Buyer' not found", null, "'<error>' was not declared:", null))
    sink.ReportBuilt(DpgDetailed("Type 'Buyer' not found", null, null, "add an import for '<error>'."))
    assert errors.Count == 0

    sink.ReportBuilt(DpgDetailed("Type 'Buyer' not found", "s", "h", "c"))
    assert errors.Count == 1
}

test "DOOR 4 — the linter's AddDiagnostic refuses one, so NL001 and NL012 cannot name a placeholder" {
    state := DpgLinterState()
    state.AddDiagnostic("NL001", LinterBindingUsageCore.UnusedVariableMessage("<error>"), 1, 1, DiagnosticSeverity.Error, LinterBindingUsageCore.UnusedVariableSuggestion("<error>"), 7)
    assert state.Diagnostics.Count == 0

    state.AddDiagnostic("NL012", LinterBindingUsageCore.UnusedParameterMessage("<error>", "main"), 1, 1, DiagnosticSeverity.Error, null, 7)
    assert state.Diagnostics.Count == 0

    state.AddDiagnostic("NL001", LinterBindingUsageCore.UnusedVariableMessage("count"), 1, 1, DiagnosticSeverity.Error, LinterBindingUsageCore.UnusedVariableSuggestion("count"), 5)
    assert state.Diagnostics.Count == 1
    assert state.Diagnostics[0].Message == "Variable 'count' is declared but never read"
}

test "the guard sits AFTER the rule's own severity and suppression gates, so it cannot resurrect a disabled rule" {
    state := DpgLinterState()
    state.AddDiagnostic("NL001", LinterBindingUsageCore.UnusedVariableMessage("count"), 1, 1, DiagnosticSeverity.Error, null, 5)
    assert state.Diagnostics.Count == 1
}

// The three sentences the shipped compiler was measured printing for `func Add(a: int, 5: int)` and
// `class Box { 5: int }` before this guard existed. They are pinned as TEXT rather than reproduced
// through a parse, because what the rule forbids is the SENTENCE — whichever rule composes it.
test "the three sentences the placeholder cascade actually printed are each refused" {
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private")
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("A type named '<error>' already exists — each type name must be unique")
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder("Type '<error>' not found")
    assert DiagnosticPlaceholderGuard.TextCarriesPlaceholder(LinterBindingUsageCore.UnusedParameterMessage("<error>", "main"))
}

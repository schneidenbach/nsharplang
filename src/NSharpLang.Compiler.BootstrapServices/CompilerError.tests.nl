namespace NSharpLang.Compiler

import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `CompilerError`, IN N#.
//
// These replace the `CompilerError` half of `tests/ErrorReportingTests.cs`, one of the two canonical
// C# assertion layers this slice deletes. `CompilerError` is the record every diagnostic in the
// product becomes before a human or an agent reads it: the CLI prints `Format`, MSBuild prints
// `FormatForMsBuild`, and `nlc query` prints `FormatForTooling`. Three renderers, one record.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. `CompilerError`, `ErrorCode`, `ErrorSeverity`
// and `DiagnosticSpanResolver` are all public in this assembly, so the subject, its arguments and
// the assertions are the same assembly's own — which is exactly why this cluster priced cheapest in
// the slice-12 triage.
//
// THE MEASURED WALL THIS FILE IS WRITTEN AROUND. Omitting a defaulted parameter declines at
// `emit.local.initializer`, so every factory is spelled at FULL ARITY (`…, length, null,
// ErrorSeverity.Error`) where the deleted C# used named arguments and defaults. Same call, same
// values.
//
// WHY THE EXACT-TEXT CLAIMS GO THROUGH `CompilerErrorText`. Both rust-style and tooling renderers
// build with `StringBuilder.AppendLine`, which appends `Environment.NewLine`. Normalising CRLF to LF
// is what lets a whole rendering be stated as ONE value instead of as a handful of `Contains`
// samples — and stating the whole rendering is what pins the GUTTER WIDTH and the MARKER INDENT,
// neither of which any `Contains` claim can see.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE RENDERER IS CHOSEN BY `HumanExplanation` ALONE. A non-null explanation switches the whole
// output from rust-style to Elm-style; nothing else — not the code, not the severity, not the
// snippet — participates in that choice.
//
// (2) A `Suggestions` LIST SUPPRESSES THE `Suggestion` HELP LINE. Both `FormatForTooling` and
// `FormatForMsBuild` render "did you mean" INSTEAD of "help:", never both.
//
// (3) THE RENDERER NEVER CONSULTS `ErrorSuggestions`. An error with no `Suggestion` renders no help
// line at all, even when the code has a default suggestion in that table.
//
// (4) THE MARKER INDENT DIFFERS BETWEEN THE TWO RENDERERS. Rust-style indents by `Column - 1`;
// Elm-style indents by `Column - 1 + 6`, to clear its `{Line}|     ` gutter.

// Renderings are built with `AppendLine`, so they carry `Environment.NewLine`. Normalise to LF.
func CompilerErrorText(value: string): string {
    return value.Replace("\r\n", "\n")
}

func CompilerErrorSeverityHeading(code: ErrorCode, severity: ErrorSeverity): string {
    return CompilerError.Create(code, "message", 1, 1, severity).GetElmSeverityText()
}

// ---- The rust-style renderer -----------------------------------------------------------------

// Successor to ErrorCode_Format_IncludesCode.
test "the rust-style format states the code, the severity and the message" {
    error := CompilerError.Create(ErrorCode.TypeMismatch, "Cannot assign 'string' to 'int'", 10, 5, ErrorSeverity.Error)
    formatted := error.Format(false)

    assert formatted.Contains("NL202")
    assert formatted.Contains("error")
    assert formatted.Contains("Cannot assign 'string' to 'int'")

    // NOT IN THE DELETED FILE: the WHOLE rendering. Three `Contains` samples cannot see that the
    // code and the severity share one line, that the location is the only other line, or that
    // nothing else is emitted for a snippet-free error.
    assert CompilerErrorText(formatted) == "error NL202: Cannot assign 'string' to 'int'\n  --> line 10, column 5\n"
}

// Successor to ErrorCode_Format_IncludesLocation.
test "the rust-style format states a file-less location as a line and a column" {
    error := CompilerError.Create(ErrorCode.UndefinedVariable, "Variable 'x' not found", 15, 10, ErrorSeverity.Error)
    formatted := error.Format(false)

    assert formatted.Contains("line 15")
    assert formatted.Contains("column 10")

    assert CompilerErrorText(formatted) == "error NL301: Variable 'x' not found\n  --> line 15, column 10\n"

    // NOT IN THE DELETED FILE: with a file name the SAME error renders the compact `file:line:col`
    // form instead, which is the form editors and CI log scrapers parse.
    located := CompilerError.Create(ErrorCode.UndefinedVariable, "Variable 'x' not found", 15, 10, ErrorSeverity.Error)
    located.FileName = "test.nl"
    assert CompilerErrorText(located.Format(false)) == "error NL301: Variable 'x' not found\n  --> test.nl:15:10\n"
}

// Successor to DiagnosticId_UsesNlPrefix.
test "the diagnostic id is NL plus the numeric error code" {
    error := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 1, 1, ErrorSeverity.Error)

    assert error.DiagnosticId == "NL202"

    // NOT IN THE DELETED FILE: one sample cannot show that the id is derived from the ENUM VALUE
    // rather than from a table, so every band of the code space is crossed once.
    assert CompilerError.Create(ErrorCode.UnexpectedToken, "m", 1, 1, ErrorSeverity.Error).DiagnosticId == "NL101"
    assert CompilerError.Create(ErrorCode.NonExhaustiveMatch, "m", 1, 1, ErrorSeverity.Error).DiagnosticId == "NL501"
    assert CompilerError.Create(ErrorCode.CircularImport, "m", 1, 1, ErrorSeverity.Error).DiagnosticId == "NL703"
    assert CompilerError.Create(ErrorCode.UnusedVariable, "m", 1, 1, ErrorSeverity.Warning).DiagnosticId == "NL901"
    assert CompilerError.Create(ErrorCode.AotExpressionTree, "m", 1, 1, ErrorSeverity.Error).DiagnosticId == "NL963"

    // AND THE OVERRIDE, WHICH NOTHING ANYWHERE STATED. A non-null `DiagnosticIdOverride` replaces
    // the derived id everywhere the id is read, including inside the rendered header.
    overridden := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 1, 1, ErrorSeverity.Error)
    overridden.DiagnosticIdOverride = "NLX01"
    assert overridden.DiagnosticId == "NLX01"
    assert overridden.Format(false).Contains("error NLX01: Type mismatch")
    assert overridden.FormatForTooling(true, false).Contains("NLX01: Type mismatch")
}

// Successor to ErrorCode_Format_IncludesSuggestion.
test "the rust-style format renders a suggestion as its own help line" {
    error := CompilerError.Create(ErrorCode.NonExhaustiveMatch, "Match is not exhaustive", 20, 5, ErrorSeverity.Error)
    error.Suggestion = "Add wildcard pattern '_'"
    formatted := error.Format(false)

    assert formatted.Contains("help:")
    assert formatted.Contains("Add wildcard pattern '_'")

    // NOT IN THE DELETED FILE: the help line is preceded by a bare gutter line, which is what
    // separates it from the location when there is no snippet between them.
    assert CompilerErrorText(formatted) == "error NL501: Match is not exhaustive\n  --> line 20, column 5\n   |\nhelp: Add wildcard pattern '_'\n"
}

// Successor to CompilerError_WithSuggestion_OverridesDefault.
test "an explicit suggestion is the only help text a rendered error can carry" {
    error := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    error.Suggestion = "Custom suggestion"
    formatted := error.Format(false)

    assert formatted.Contains("Custom suggestion")
    assert !formatted.Contains("Ensure types are compatible")

    // NOT IN THE DELETED FILE, AND IT IS THE POINT OF THAT SECOND ASSERTION. The absent text is the
    // `ErrorSuggestions` default FOR THE SAME CODE — so the claim is not "some other string is
    // missing", it is "the renderer never consults that table". An error with no suggestion at all
    // renders NO help line, which is the only way to see the difference.
    assert (ErrorSuggestions.GetSuggestion(ErrorCode.TypeMismatch, null, null) ?? "") == "Ensure types are compatible or add explicit cast"
    bare := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    assert !bare.Format(false).Contains("help:")
}

// Successor to ErrorCode_Format_IncludesSourceSnippet.
test "the rust-style format renders the snippet, the gutter and the caret marker" {
    error := CompilerError.WithSnippet(ErrorCode.TypeMismatch, "Type mismatch", "test.nl", 10, 5, "    return \"string\"", 6, "Change return type to string", ErrorSeverity.Error)
    formatted := error.Format(false)

    assert formatted.Contains("test.nl:10:5")
    assert formatted.Contains("return \"string\"")
    assert formatted.Contains("^^^")
    assert formatted.Contains("Change return type to string")

    // NOT IN THE DELETED FILE: `Contains("^^^")` passes for ANY marker of three carets or more, at
    // ANY indentation. The whole rendering pins the marker's LENGTH (6, the requested length) and
    // its COLUMN, and pins the line-number gutter to `PadLeft(3)` — a three-digit line would push
    // the snippet across, and nothing stated that either.
    assert CompilerErrorText(formatted) == "error NL202: Type mismatch\n  --> test.nl:10:5\n   |\n 10 |     return \"string\"\n   |     ^^^^^^\n   |\nhelp: Change return type to string\n"
}

// Successor to WithSnippet_DefaultSpan_UsesNearestVisibleToken.
test "with snippet infers the span from the nearest visible token" {
    error := CompilerError.WithSnippet(ErrorCode.InvalidSyntax, "Expected expression", "test.nl", 3, 1, "    print value", 0, null, ErrorSeverity.Error)

    assert error.Column == 5
    assert error.Length == 5

    // NOT IN THE DELETED FILE: a NON-ZERO requested length short-circuits the resolver entirely, so
    // a caller that already knows its span keeps BOTH the column it asked for and the length. Only
    // zero means "infer", and the deleted file only ever passed zero here.
    kept := CompilerError.WithSnippet(ErrorCode.InvalidSyntax, "Expected expression", "test.nl", 3, 1, "    print value", 9, null, ErrorSeverity.Error)
    assert kept.Column == 1
    assert kept.Length == 9
}

// Successor to Warning_Format_ShowsWarning.
test "a warning renders as a warning" {
    warning := CompilerError.Create(ErrorCode.UnusedVariable, "Variable 'x' is unused", 5, 10, ErrorSeverity.Warning)
    formatted := warning.Format(false)

    assert formatted.Contains("warning")
    assert formatted.Contains("NL901")

    assert CompilerErrorText(formatted) == "warning NL901: Variable 'x' is unused\n  --> line 5, column 10\n"

    // NOT IN THE DELETED FILE: severity moves ONLY the leading word. The same code at error severity
    // renders an otherwise identical line, so nothing else in the header is severity-dependent.
    assert CompilerErrorText(CompilerError.Create(ErrorCode.UnusedVariable, "Variable 'x' is unused", 5, 10, ErrorSeverity.Error).Format(false)) == "error NL901: Variable 'x' is unused\n  --> line 5, column 10\n"
}

// Successor to RustStyle_StillWorksWithoutElmContext.
test "an error with no human explanation stays in the rust-style renderer" {
    error := CompilerError.Create(ErrorCode.TypeMismatch, "Cannot assign 'string' to 'int'", 10, 5, ErrorSeverity.Error)
    error.SourceSnippet = "x: int = \"hello\""
    error.Length = 7
    formatted := error.Format(false)

    assert formatted.Contains("error NL202")
    assert formatted.Contains("Cannot assign 'string' to 'int'")
    assert !formatted.Contains("TYPE MISMATCH")

    assert CompilerErrorText(formatted) == "error NL202: Cannot assign 'string' to 'int'\n  --> line 10, column 5\n   |\n 10 | x: int = \"hello\"\n   |     ^^^^^^^\n"

    // NOT IN THE DELETED FILE, AND IT IS THE WHOLE RULE THE TEST'S NAME CLAIMS. The discriminator is
    // `HumanExplanation` ALONE — not the code, not the snippet, not the actual/expected pair. Adding
    // only that one field to the SAME error flips the entire rendering.
    elmBound := CompilerError.Create(ErrorCode.TypeMismatch, "Cannot assign 'string' to 'int'", 10, 5, ErrorSeverity.Error)
    elmBound.SourceSnippet = "x: int = \"hello\""
    elmBound.Length = 7
    elmBound.HumanExplanation = "I am having trouble with this code:"
    assert elmBound.Format(false).Contains("-- TYPE MISMATCH")
    assert !elmBound.Format(false).Contains("error NL202:")
}

// ---- The tooling renderer --------------------------------------------------------------------

// Successor to FormatForTooling_PreservesRichContextWithoutLocation.
test "format for tooling preserves the rich context and omits the location" {
    error := ErrorMessageBuilder.TypeMismatch("test.nl", 10, 5, "x: int = \"hello\"", 7, "string", "int", "Type mismatch")
    formatted := error.FormatForTooling(true, false)

    assert formatted.Contains("NL202: Type mismatch")
    assert formatted.Contains("I am having trouble")
    assert formatted.Contains("x: int = \"hello\"")
    assert formatted.Contains("^^^^^^^")
    assert formatted.Contains("actual: string")
    assert formatted.Contains("expected: int")
    assert !formatted.Contains("at test.nl:10:5")

    // NOT IN THE DELETED FILE: the WHOLE payload an agent reads. Seven `Contains` samples cannot see
    // the ORDER of the blocks, the blank line between each pair, the marker's indent, or that the
    // trailing newline is trimmed — and this is the exact text `nlc query` hands an LLM.
    assert CompilerErrorText(formatted) == "NL202: Type mismatch\n\nI am having trouble with this code on line 10:\n\nx: int = \"hello\"\n    ^^^^^^^\n\nactual: string\nexpected: int\n\nStrings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result).\n\ndocs: https://docs.n-sharp.dev/errors/NL202"
}

// NOT IN THE DELETED FILE AT ALL: the two arms the deleted file never asked for.
test "format for tooling renders the location when it is asked for" {
    located := ErrorMessageBuilder.TypeMismatch("test.nl", 10, 5, "x: int = \"hello\"", 7, "string", "int", "Type mismatch")
    assert located.FormatForTooling(true, true).Contains("at test.nl:10:5")

    // Without a file name the SAME switch renders the prose form instead.
    fileless := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    assert CompilerErrorText(fileless.FormatForTooling(true, true)) == "NL202: Type mismatch\nat line 10, column 5"

    // And `includeCode: false` drops the id, leaving the message as the first line.
    assert CompilerErrorText(fileless.FormatForTooling(false, false)) == "Type mismatch"
    assert CompilerErrorText(fileless.FormatForTooling(false, true)) == "Type mismatch\nat line 10, column 5"
}

// Successor to FormatForMsBuild_CollapsesRichContextOntoOneLine.
test "format for msbuild collapses the rich context onto one line" {
    error := ErrorMessageBuilder.TypeMismatch("test.nl", 10, 5, "x: int = \"hello\"", 7, "string", "int", "Type mismatch")
    formatted := error.FormatForMsBuild()

    assert formatted.Contains("Type mismatch")
    assert formatted.Contains("actual: string")
    assert formatted.Contains("expected: int")
    assert formatted.Contains("I am having trouble")
    assert !formatted.Contains("\n")

    // NOT IN THE DELETED FILE: "no newline" is satisfied by simply DROPPING the multi-line hint.
    // The whole value proves the hint SURVIVES, with its interior newline folded to a single space,
    // and pins the ` | ` separator MSBuild's log parser splits on.
    assert formatted == "Type mismatch | I am having trouble with this code on line 10: | actual: string | expected: int | Strings and integers are different types. To convert a string to an int, you can use int.Parse(yourString) or int.TryParse(yourString, out result). | docs: https://docs.n-sharp.dev/errors/NL202"

    // AND THE SNIPPET IS DELIBERATELY ABSENT: MSBuild renders its own caret line, so a second one
    // would double it.
    assert !formatted.Contains("^")
    assert !formatted.Contains("x: int = ")
}

// NOT IN THE DELETED FILE AT ALL, AND NOT PINNED ANYWHERE UNTIL 021/8: MSBuild's span.
//
// `FormatForMsBuild` renders the TEXT of a diagnostic; the SPAN was computed separately, inside
// `src/NSharpLang.Build.Tasks/EmitIlAssembly.cs`, as `error.Column + Math.Max(0, error.Length - 1)`
// at two call sites, and nothing asserted it. It decides how wide the squiggle is in the IDE error
// list and what `(line,col-col)` reads in build output.
test "the msbuild end column is inclusive, so a one-character diagnostic reports its own column" {
    single := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    assert single.Length == 1
    assert single.MsBuildEndColumn == 5
    assert single.MsBuildEndColumn == single.Column

    // an N-character span ends N-1 past its start — an EXCLUSIVE end would over-report by one
    span := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    span.Length = 7
    assert span.MsBuildEndColumn == 11

    // and it never runs BACKWARDS past the column, whatever a zero or negative length claims
    zero := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    zero.Length = 0
    assert zero.MsBuildEndColumn == 5
    negative := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 10, 5, ErrorSeverity.Error)
    negative.Length = -3
    assert negative.MsBuildEndColumn == 5
}

// NOT IN THE DELETED FILE AT ALL: the suppression rule that governs BOTH rich renderers.
test "a suggestions list suppresses the help line in both rich renderers" {
    names := new List<string>()
    names.Add("alpha")
    names.Add("beta")

    error := CompilerError.Create(ErrorCode.UndefinedVariable, "Variable 'alfa' not found", 3, 1, ErrorSeverity.Error)
    error.Suggestion = "help me"
    error.Suggestions = names

    tooling := CompilerErrorText(error.FormatForTooling(true, false))
    assert tooling == "NL301: Variable 'alfa' not found\n\ndid you mean:\n- alpha\n- beta"
    assert !tooling.Contains("help: ")

    msbuild := error.FormatForMsBuild()
    assert msbuild == "Variable 'alfa' not found | did you mean: alpha, beta"
    assert !msbuild.Contains("help: ")

    // An EMPTY list does not suppress it — the flag is set by rendering, not by presence.
    emptyList := CompilerError.Create(ErrorCode.UndefinedVariable, "Variable 'alfa' not found", 3, 1, ErrorSeverity.Error)
    emptyList.Suggestion = "help me"
    emptyList.Suggestions = new List<string>()
    assert CompilerErrorText(emptyList.FormatForTooling(true, false)) == "NL301: Variable 'alfa' not found\n\nhelp: help me"
    assert emptyList.FormatForMsBuild() == "Variable 'alfa' not found | help: help me"
}

// ---- The Elm severity table and the inline-text folder ----------------------------------------

// NOT IN THE DELETED FILE AT ALL: the deleted file reached four of these seven headings, and only
// ever indirectly, through a rendered string. All seven are stated here directly, together, so a
// code moved between bands cannot silently change the heading a user sees.
test "the elm severity table names all seven headings" {
    assert CompilerErrorSeverityHeading(ErrorCode.UnusedVariable, ErrorSeverity.Warning) == "WARNING"
    assert CompilerErrorSeverityHeading(ErrorCode.TypeMismatch, ErrorSeverity.Error) == "TYPE MISMATCH"
    assert CompilerErrorSeverityHeading(ErrorCode.TypeNotFound, ErrorSeverity.Error) == "TYPE MISMATCH"
    assert CompilerErrorSeverityHeading(ErrorCode.UndefinedVariable, ErrorSeverity.Error) == "NAMING ERROR"
    assert CompilerErrorSeverityHeading(ErrorCode.UndefinedType, ErrorSeverity.Error) == "NAMING ERROR"
    assert CompilerErrorSeverityHeading(ErrorCode.UndefinedMember, ErrorSeverity.Error) == "NAMING ERROR"
    assert CompilerErrorSeverityHeading(ErrorCode.NonExhaustiveMatch, ErrorSeverity.Error) == "INCOMPLETE PATTERN MATCH"
    assert CompilerErrorSeverityHeading(ErrorCode.WrongArgumentCount, ErrorSeverity.Error) == "FUNCTION CALL ERROR"
    assert CompilerErrorSeverityHeading(ErrorCode.NoMatchingOverload, ErrorSeverity.Error) == "FUNCTION CALL ERROR"
    assert CompilerErrorSeverityHeading(ErrorCode.UndefinedFunction, ErrorSeverity.Error) == "FUNCTION CALL ERROR"
    assert CompilerErrorSeverityHeading(ErrorCode.CircularImport, ErrorSeverity.Error) == "CIRCULAR IMPORT"
    assert CompilerErrorSeverityHeading(ErrorCode.InvalidSyntax, ErrorSeverity.Error) == "ERROR"

    // WARNING WINS OVER EVERY CODE. The severity test runs FIRST, so a warning-severity type
    // mismatch is headed WARNING, not TYPE MISMATCH — the one ordering fact in the table.
    assert CompilerErrorSeverityHeading(ErrorCode.TypeMismatch, ErrorSeverity.Warning) == "WARNING"
    assert CompilerErrorSeverityHeading(ErrorCode.CircularImport, ErrorSeverity.Warning) == "WARNING"
}

// NOT IN THE DELETED FILE AT ALL: the folder the MsBuild renderer depends on, stated directly.
test "normalize inline text folds every newline into a single space" {
    assert CompilerError.NormalizeInlineText("first\nsecond") == "first second"
    assert CompilerError.NormalizeInlineText("first\r\nsecond") == "first second"
    assert CompilerError.NormalizeInlineText("first\n\n\nsecond") == "first second"

    // A newline followed by INDENTATION folds to the indentation, not to a doubled space: the space
    // is only inserted before a NON-whitespace character.
    assert CompilerError.NormalizeInlineText("first\n    second") == "first    second"

    // Leading and trailing whitespace is trimmed, and a leading newline inserts nothing because the
    // builder is still empty.
    assert CompilerError.NormalizeInlineText("\nfirst") == "first"
    assert CompilerError.NormalizeInlineText("  first  ") == "first"
    assert CompilerError.NormalizeInlineText("") == ""
    assert CompilerError.NormalizeInlineText("\n") == ""
}

// NOT IN THE DELETED FILE AT ALL: the predicate that decides whether a block is rendered at all.
test "has text treats a whitespace-only value as absent" {
    assert CompilerError.HasText("x")
    assert !CompilerError.HasText("")
    assert !CompilerError.HasText("   ")
    assert !CompilerError.HasText("\n")
    assert !CompilerError.HasText(null)
}

// ---- The detailed factories --------------------------------------------------------------------

// NOT IN THE DELETED FILE AT ALL: `CreateDetailed` and `WithSnippetDetailed` had no coverage
// anywhere, and both are how the analyser builds an Elm-style diagnostic.
test "create detailed carries every optional field and floors the length at one" {
    error := CompilerError.CreateDetailed(ErrorCode.TypeMismatch, "Type mismatch", 4, 2, "test.nl", 3, "help text", "human text", "hint text", "https://example.test/docs", ErrorSeverity.Error)

    assert error.FileName == "test.nl"
    assert error.Length == 3
    assert error.Suggestion == "help text"
    assert error.HumanExplanation == "human text"
    assert error.ContextualHint == "hint text"
    assert error.DocsUrl == "https://example.test/docs"
    assert error.Severity == ErrorSeverity.Error

    // A zero or negative length is floored to one, so a marker is never empty.
    zeroLength := CompilerError.CreateDetailed(ErrorCode.TypeMismatch, "m", 4, 2, "test.nl", 0, null, null, null, null, ErrorSeverity.Error)
    assert zeroLength.Length == 1
    negativeLength := CompilerError.CreateDetailed(ErrorCode.TypeMismatch, "m", 4, 2, "test.nl", -7, null, null, null, null, ErrorSeverity.Error)
    assert negativeLength.Length == 1

    // A human explanation is enough to select the Elm renderer, exactly as it is on the record.
    assert error.Format(false).Contains("-- TYPE MISMATCH")
}

// NOT IN THE DELETED FILE AT ALL.
test "with snippet detailed threads the elm fields through the span resolver" {
    error := CompilerError.WithSnippetDetailed(ErrorCode.TypeMismatch, "Type mismatch", "test.nl", 4, 1, "    let x = 1", 0, "help text", ErrorSeverity.Error, "human text", "hint text", "https://example.test/docs")

    // The span is resolved exactly as `WithSnippet` resolves it — column 1 is indentation, so it
    // snaps forward to `let` and takes that token's length.
    assert error.Column == 5
    assert error.Length == 3
    assert error.SourceSnippet == "    let x = 1"
    assert error.HumanExplanation == "human text"
    assert error.ContextualHint == "hint text"
    assert error.DocsUrl == "https://example.test/docs"
    assert error.Suggestion == "help text"
}

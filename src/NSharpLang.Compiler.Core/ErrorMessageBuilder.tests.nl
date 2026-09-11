namespace NSharpLang.Compiler

import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `ErrorMessageBuilder`, IN N#.
//
// These replace the Elm-style half of `tests/ErrorReportingTests.cs`. `ErrorMessageBuilder` is the
// one place a bare `(code, message, line, column)` becomes an Elm-style diagnostic: it chooses the
// human explanation, the contextual hint, the "did you mean" list and the docs URL. Everything a
// user reads when N# says something helpful is assembled here.
//
// WHAT THE DELETED FILE COULD NOT SEE. It reached SIX of the twenty builders, each through a single
// rendered string, and asserted `Contains` on fragments of them. Three whole mechanisms were
// therefore invisible: the DOCS-URL TABLE (it stated one of eighteen distinct URLs), the
// SIMILAR-NAMES SWITCH (four builders answer a DIFFERENT contextual hint depending on whether the
// caller found near-misses, and it saw one arm of two of them), and the LIST RENDERERS
// (`IndentedLines`, `JoinBackticked`, `BulletLines`) that shape every enumeration in every hint.
//
// THE THREE THINGS IT IS EASY TO GET WRONG:
//
// (1) AN EMPTY SIMILAR-NAMES LIST BECOMES NULL, NOT AN EMPTY LIST. `OptionalNames` is what stops the
// renderer printing an empty "Did you mean one of these?" block — a builder that passed the list
// straight through would render the heading with nothing under it.
//
// (2) THE ELM MARKER INDENT IS `Column - 1 + 6`, NOT `Column - 1`. The Elm renderer prefixes each
// snippet with a `{Line}|     ` gutter, and the marker has to clear it. The rust-style renderer,
// which the same record can also be printed through, uses the un-shifted indent.
//
// (3) `UndefinedFunction` IS NOT `UndefinedVariable`. Both say "I cannot find"; only one of them
// says "function". The deleted file's own test name recorded that this had regressed once.
func ErrorBuilderText(value: string): string {
    return value.Replace("\r\n", "\n")
}

func ErrorBuilderDocsUrl(error: CompilerError): string {
    return error.DocsUrl ?? "<null>"
}

func ErrorBuilderNames(first: string, second: string): List<string> {
    values := new List<string>()
    values.Add(first)
    values.Add(second)
    return values
}

// ---- The migrated Elm-style renderings ---------------------------------------------------------

// Successor to ElmStyle_TypeMismatch_ShowsHumanExplanation and ElmStyle_ErrorsIncludeDocsUrl.
test "an elm-style type mismatch explains both types and links the docs" {
    error := ErrorMessageBuilder.TypeMismatch("test.nl", 10, 5, "x: int = \"hello\"", 7, "string", "int", "Type mismatch")
    formatted := error.Format(false)

    assert formatted.Contains("TYPE MISMATCH")
    assert formatted.Contains("I am having trouble")
    assert formatted.Contains("This expression has type:")
    assert formatted.Contains("string")
    assert formatted.Contains("But you said it should be:")
    assert formatted.Contains("int")
    assert formatted.Contains("int.Parse")
    assert formatted.Contains("https://schneidenbach.github.io/nsharplang/docs/errors/NL202")

    // NOT IN THE DELETED FILE: the header rule and the gutter. The heading is padded to a fixed
    // fifty-dash rule with the FILE NAME on the right, and the snippet carries a `{Line}|     `
    // gutter that the caret marker has to clear by exactly six columns.
    lines := ErrorBuilderText(formatted)
    assert lines.Contains("-- TYPE MISMATCH --------------------------------------------------  test.nl\n")
    assert lines.Contains("\n10|     x: int = \"hello\"\n          ^^^^^^^\n")

    // AND THE FILE NAME IS SUBSTITUTED WHEN THERE IS NONE, so the rule never renders ragged.
    fileless := CompilerError.Create(ErrorCode.TypeMismatch, "Type mismatch", 1, 1, ErrorSeverity.Error)
    fileless.HumanExplanation = "explanation"
    assert ErrorBuilderText(fileless.Format(false)).Contains("-- TYPE MISMATCH --------------------------------------------------  code\n")
}

// Successor to ElmStyle_UndefinedVariable_SuggestsSimilarNames.
test "an elm-style undefined variable lists the names it nearly matched" {
    similarNames := new List<string>()
    similarNames.Add("person")
    similarNames.Add("personName")
    error := ErrorMessageBuilder.UndefinedVariable("test.nl", 15, 10, "print(persn.Name)", 5, "persn", similarNames)
    formatted := error.Format(false)

    assert formatted.Contains("NAMING ERROR")
    assert formatted.Contains("I cannot find")
    assert formatted.Contains("persn")
    assert formatted.Contains("Did you mean one of these?")
    assert formatted.Contains("person")
    assert formatted.Contains("personName")

    // NOT IN THE DELETED FILE: the candidates are rendered one per line at a four-space indent, in
    // the order the caller ranked them — the ranking `SmartSuggester` produced would be worthless if
    // this block reordered it.
    assert ErrorBuilderText(formatted).Contains("\nDid you mean one of these?\n\n    person\n    personName\n")

    // AND WITHOUT NEAR-MISSES THE BLOCK IS ABSENT ENTIRELY, not present and empty. This is the arm
    // the deleted file never asked for, and it is the one `OptionalNames` exists to produce.
    lonely := ErrorMessageBuilder.UndefinedVariable("test.nl", 15, 10, "print(persn.Name)", 5, "persn", new List<string>())
    assert !lonely.Format(false).Contains("Did you mean one of these?")
    assert lonely.Format(false).Contains("Make sure you've declared this variable before using it.")
    assert error.Format(false).Contains("Variables need to be declared before they can be used.")
}

// Successor to ElmStyle_UndefinedFunction_ReportsFunctionNotVariable.
test "an elm-style undefined function says function, not variable" {
    error := ErrorMessageBuilder.UndefinedFunction("test.nl", 6, 10, "    i := Hi()", 2, "Hi", new List<string>())
    formatted := error.Format(false)
    tooling := error.FormatForTooling(true, false)

    assert error.Code == ErrorCode.UndefinedFunction
    assert formatted.Contains("FUNCTION CALL ERROR")
    assert formatted.Contains("function named `Hi`")
    assert error.Message == "Function 'Hi' not found"
    assert tooling.Contains("NL412: Function 'Hi' not found")
    assert !tooling.Contains("Variable 'Hi' not found")

    // NOT IN THE DELETED FILE: the no-near-miss hint tells the caller how to DEFINE the function,
    // and the with-near-miss hint tells them about scope and imports instead.
    assert formatted.Contains("Define `func Hi(...)` before calling it")
    named := ErrorMessageBuilder.UndefinedFunction("test.nl", 6, 10, "    i := Hi()", 2, "Hi", ErrorBuilderNames("Hi2", "High"))
    assert named.Format(false).Contains("Function calls need a function, method, or callable value with this name in scope.")
    assert named.Format(false).Contains("Did you mean one of these?")
}

// Successor to ElmStyle_NonExhaustiveMatch_ListsMissingCases.
test "an elm-style non-exhaustive match lists the cases it is missing" {
    missingCases := new List<string>()
    missingCases.Add("Pending")
    missingCases.Add("Cancelled")
    error := ErrorMessageBuilder.NonExhaustiveMatch("test.nl", 20, 12, "match result {", 5, missingCases)
    formatted := error.Format(false)

    assert formatted.Contains("INCOMPLETE PATTERN MATCH")
    assert formatted.Contains("does not cover all possibilities")
    assert formatted.Contains("Pending")
    assert formatted.Contains("Cancelled")
    assert formatted.Contains("must be exhaustive")
    assert formatted.Contains("wildcard '_'")
    assert formatted.Contains("prevent runtime errors")

    // NOT IN THE DELETED FILE: the missing cases are ALSO carried as machine-readable related info,
    // which is the form the language server and `nlc query` consume — a renderer-only claim cannot
    // see it, and nothing else in the repository stated it.
    assert error.RelatedInfo != null
    relatedInfo := error.RelatedInfo ?? new Dictionary<string, string>()
    assert relatedInfo["missingCases"] == "Pending, Cancelled"

    // AND THE HINT'S CASE BLOCK IS FOUR-SPACE INDENTED, ONE PER LINE — the shape a user is meant to
    // paste back into their `match`.
    assert ErrorBuilderText(formatted).Contains("You need to handle these cases:\n\n    Pending\n    Cancelled\n\n")
}

// Successor to ReturnValueRequiresReturnType_FormatForTooling_ExplainsImplicitVoid.
test "returning a value from an unannotated function explains the implicit void" {
    error := ErrorMessageBuilder.ReturnValueRequiresReturnType("test.nl", 3, 5, "    return 42", 6, "Hi", "int")
    formatted := error.FormatForTooling(true, false)

    assert formatted.Contains("NL202: Function 'Hi' returns int but has no return type")
    assert formatted.Contains("Function `Hi` has no return type annotation")
    assert formatted.Contains("expected: void")
    assert formatted.Contains("Add `: int`")
    assert !formatted.Contains("These types are not compatible")

    // NOT IN THE DELETED FILE: the WHOLE payload, which pins the block order, the caret indent and
    // the fact that the suggestion survives as its own `help:` line beneath the hint.
    assert ErrorBuilderText(formatted) == "NL202: Function 'Hi' returns int but has no return type\n\nFunction `Hi` has no return type annotation, so N# treats it as `void`:\n\n    return 42\n    ^^^^^^\n\nactual: int\nexpected: void\n\nThis code gives back a value of type `int` from a function that currently returns nothing.\nAdd `: int` after the parameter list if `Hi` should return this value, or remove the value if the function should stay void.\n\nhelp: Add `: int` to `Hi` or remove the returned value\n\ndocs: https://schneidenbach.github.io/nsharplang/docs/errors/NL202"

    // AND THE UNKNOWN-TYPE ARM, which the deleted file could not reach: when the analyser could not
    // name the returned type, the builder stops proposing a concrete annotation.
    unknown := ErrorMessageBuilder.ReturnValueRequiresReturnType("test.nl", 3, 5, "    return null", 6, "Hi", "null")
    assert unknown.FormatForTooling(true, false).Contains("Add an explicit return type after the parameter list if `Hi` should return a value")
    assert !unknown.FormatForTooling(true, false).Contains("Add `: null`")
    assert ErrorMessageBuilder.ReturnValueRequiresReturnType("test.nl", 3, 5, "    return x", 6, "Hi", "unknown").FormatForTooling(true, false).Contains("Add an explicit return type to `Hi` or remove the returned value")
}

// ---- The docs-url table --------------------------------------------------------------------------

// NOT IN THE DELETED FILE AT ALL: eighteen builders, eighteen documentation anchors. The deleted
// file stated ONE of them, so a builder pointed at the wrong error page would have passed.
test "every builder links the documentation page for the code it raises" {
    empty := new List<string>()

    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.UnexpectedToken("f.nl", 1, 1, "x", 1, "}", null)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL101"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.TypeMismatch("f.nl", 1, 1, "x", 1, "string", "int", "Type mismatch")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL202"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.ReturnValueInVoidFunction("f.nl", 1, 1, "x", 1, "Hi", "int")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL202"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.ReturnTypeMismatch("f.nl", 1, 1, "x", 1, "Hi", "string", "int")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL202"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.WrongArgumentType("f.nl", 1, 1, "x", 1, "Hi", 1, "p", "string", "int")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL202"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.UndefinedVariable("f.nl", 1, 1, "x", 1, "v", empty)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL301"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.UndefinedMember("f.nl", 1, 1, "x", 1, "m", "T", empty)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL303"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.MissingReturn("f.nl", 1, 1, "x", 1, "int")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL305"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.DuplicateDeclaration("f.nl", 1, 1, "x", 1, "n", "function")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL306"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.InvalidExpressionStatement("f.nl", 1, 1, "x", 1, "a.B")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL313"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.InvalidForIteratorExpression("f.nl", 1, 1, "x", 1, "a.B")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL313"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.ControlTransferOutOfFinally("f.nl", 1, 1, "x", 1, "return")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL319"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.LockRequiresReferenceType("f.nl", 1, 1, "x", 1, "int", false)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL320"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.MemberWriteThroughValueCopy("f.nl", 1, 1, "x", 1, "X", "P", "a call result")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL322"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.WrongArgumentCount("f.nl", 1, 1, "x", 1, "Hi", 2, 1)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL401"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.NoMatchingOverload("f.nl", 1, 1, "x", 1, "Hi", 1, empty, empty)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL402"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.MethodGroupUsedAsValue("f.nl", 1, 1, "x", 1, "Hi")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL411"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.UndefinedFunction("f.nl", 1, 1, "x", 1, "Hi", empty)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL412"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.NonExhaustiveMatch("f.nl", 1, 1, "x", 1, empty)) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL501"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.ImportNotFound("f.nl", 1, 1, "x", 1, "a/b.nl")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL701"
    assert ErrorBuilderDocsUrl(ErrorMessageBuilder.CircularImport("f.nl", 1, 1, "x", 1, "a/b.nl")) == "https://schneidenbach.github.io/nsharplang/docs/errors/NL703"
}

// ---- The NL202 headline belongs to the CALLER -----------------------------------------------------

// THE FOUR-ARGUMENT `Analyze` DEFECT, PINNED AT ITS OWNER. `ErrorMessageBuilder.TypeMismatch` used to
// write its own headline, and the only headline it could write was the bare words `Type mismatch` —
// the two disagreeing NAMES are not among its arguments. Every analyzer site that reaches it already
// knows the sentence, and said it on the route with no source text. So the route production actually
// calls — `Analyze(unit, path, root, source)`, the only one `nlc check`, `nlc build` and the language
// server use — was the one with LESS to say. The builder now takes the sentence and adds to it.
test "the type-mismatch builder reports the caller's sentence, not a headline of its own" {
    described := ErrorMessageBuilder.TypeMismatch("test.nl", 10, 5, "total: int = \"hi\"", 4, "string", "int", "Variable 'total' is typed as 'int', but the value is 'string'")

    assert described.Message == "Variable 'total' is typed as 'int', but the value is 'string'"
    assert described.Code == ErrorCode.TypeMismatch

    // AND EVERYTHING THE RICH SHAPE ADDS IS STILL ADDED. The sentence is not paid for with the
    // snippet, the caret width, the two type names, the hint or the docs link.
    assert described.FileName == "test.nl"
    assert described.SourceSnippet == "total: int = \"hi\""
    assert described.Length == 4
    assert described.ActualType == "string"
    assert described.ExpectedType == "int"
    assert described.HumanExplanation == "I am having trouble with this code on line 10:"
    assert described.ContextualHint != null
    assert described.DocsUrl == "https://schneidenbach.github.io/nsharplang/docs/errors/NL202"

    // The renderers put the caller's sentence where the bare words used to go.
    assert described.FormatForTooling(true, false).Contains("NL202: Variable 'total' is typed as 'int', but the value is 'string'")
    assert described.FormatForMsBuild().Contains("Variable 'total' is typed as 'int', but the value is 'string'")
}

// ---- The pieces every hint is assembled from -----------------------------------------------------

// NOT IN THE DELETED FILE AT ALL: the count-sensitive wording that appears in BOTH the message and
// the hint of an argument-count error.
test "the argument count message agrees with itself in singular and plural" {
    assert ErrorMessageBuilder.Pluralize(1, "argument", "arguments") == "argument"
    assert ErrorMessageBuilder.Pluralize(0, "argument", "arguments") == "arguments"
    assert ErrorMessageBuilder.Pluralize(2, "argument", "arguments") == "arguments"
    assert ErrorMessageBuilder.Pluralize(-1, "argument", "arguments") == "arguments"

    single := ErrorMessageBuilder.WrongArgumentCount("f.nl", 1, 1, "Hi(1, 2)", 8, "Hi", 1, 2)
    assert single.Message == "Function 'Hi' expects 1 argument but got 2"
    assert (single.ContextualHint ?? "").Contains("expects 1 argument, but you are")
    assert (single.ContextualHint ?? "").Contains("You may have passed too many arguments.")

    plural := ErrorMessageBuilder.WrongArgumentCount("f.nl", 1, 1, "Hi(1)", 5, "Hi", 2, 1)
    assert plural.Message == "Function 'Hi' expects 2 arguments but got 1"
    assert (plural.ContextualHint ?? "").Contains("You may have forgotten to pass some arguments.")
}

// NOT IN THE DELETED FILE AT ALL: the three list renderers, stated directly. Every enumeration in
// every hint is one of these three, and they differ only in their bullet.
test "the three list renderers indent, backtick and bullet" {
    values := new List<string>()
    values.Add("alpha")
    values.Add("beta")

    assert ErrorMessageBuilder.IndentedLines(values) == "    alpha\n    beta"
    assert ErrorMessageBuilder.JoinBackticked(values) == "`alpha`, `beta`"
    assert ErrorMessageBuilder.BulletLines(values) == "  - alpha\n  - beta"

    single := new List<string>()
    single.Add("only")
    assert ErrorMessageBuilder.IndentedLines(single) == "    only"
    assert ErrorMessageBuilder.JoinBackticked(single) == "`only`"
    assert ErrorMessageBuilder.BulletLines(single) == "  - only"

    empty := new List<string>()
    assert ErrorMessageBuilder.IndentedLines(empty) == ""
    assert ErrorMessageBuilder.JoinBackticked(empty) == ""
    assert ErrorMessageBuilder.BulletLines(empty) == ""
    assert !ErrorMessageBuilder.HasItems(empty)
    assert ErrorMessageBuilder.HasItems(single)
    assert ErrorMessageBuilder.OptionalNames(empty) == null
    assert ErrorMessageBuilder.OptionalNames(single) != null
}

// NOT IN THE DELETED FILE AT ALL: the overload reporter's two arms, which are what an agent reads
// when a call does not bind.
test "the overload reporter names the arguments it saw and the overloads it knows" {
    empty := new List<string>()
    bare := ErrorMessageBuilder.NoMatchingOverload("f.nl", 1, 1, "Hi()", 4, "Hi", 0, empty, empty)
    assert bare.Message == "No overload of 'Hi' accepts 0 arguments with these types"
    assert (bare.ContextualHint ?? "").Contains("This call passes 0 arguments: no arguments.")
    assert (bare.ContextualHint ?? "").Contains("No callable overloads were found.")

    argumentTypes := new List<string>()
    argumentTypes.Add("int")
    candidates := new List<string>()
    candidates.Add("Hi(a: string)")
    candidates.Add("Hi(a: int, b: int)")
    described := ErrorMessageBuilder.NoMatchingOverload("f.nl", 1, 1, "Hi(1)", 5, "Hi", 1, argumentTypes, candidates)
    assert described.Message == "No overload of 'Hi' accepts 1 argument with these types"
    assert (described.ContextualHint ?? "").Contains("This call passes 1 argument: `int`.")
    assert (described.ContextualHint ?? "").Contains("Available overloads:\n  - Hi(a: string)\n  - Hi(a: int, b: int)")
}

// NOT IN THE DELETED FILE AT ALL: the argument-type sentence, whose two arms differ only in whether
// the parameter could be named.
test "the wrong-argument-type sentence names the parameter when it can" {
    assert ErrorMessageBuilder.WrongArgumentTypeMessage("Argument 1", "Hi", "a `string`", "value", "int") == "Argument 1 to 'Hi' is a `string`, but parameter 'value' expects 'int'"
    assert ErrorMessageBuilder.WrongArgumentTypeMessage("Argument 1", "Hi", "a `string`", null, "int") == "Argument 1 to 'Hi' is a `string`, but this parameter expects 'int'"
}

// NOT IN THE DELETED FILE AT ALL: the three builders whose text changes on a boolean or a keyword,
// each of which is a place a copy-and-paste would silently produce the wrong advice.
test "the switched builders answer differently on each arm" {
    // `return` leaves the FUNCTION; `break` and `continue` leave a LOOP.
    returnTransfer := ErrorMessageBuilder.ControlTransferOutOfFinally("f.nl", 1, 1, "return", 6, "return")
    breakTransfer := ErrorMessageBuilder.ControlTransferOutOfFinally("f.nl", 1, 1, "break", 5, "break")
    assert (returnTransfer.ContextualHint ?? "").Contains("would exit the `finally` early to reach the function")
    assert (breakTransfer.ContextualHint ?? "").Contains("would exit the `finally` early to reach a loop outside the `finally`")

    // A concrete value type is told to lock on an object; a TYPE PARAMETER is told to constrain it.
    concreteLock := ErrorMessageBuilder.LockRequiresReferenceType("f.nl", 1, 1, "lock x", 6, "int", false)
    genericLock := ErrorMessageBuilder.LockRequiresReferenceType("f.nl", 1, 1, "lock x", 6, "T", true)
    assert (concreteLock.Suggestion ?? "") == "Lock on a dedicated `object` field instead: `sync: object = new object()`"
    assert (genericLock.Suggestion ?? "").Contains("Constrain `T` to a reference type (`where T: class`)")

    // An expected token turns "unexpected" into "expected X but found Y".
    assert ErrorMessageBuilder.UnexpectedToken("f.nl", 1, 1, "}", 1, "}", null).Message == "Unexpected token: }"
    assert ErrorMessageBuilder.UnexpectedToken("f.nl", 1, 1, "}", 1, "}", "';'").Message == "Expected ';' but found }"
}

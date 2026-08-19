namespace NSharpLang.Compiler


// THE CANONICAL CONTRACTS FOR `ErrorSuggestions`, IN N#.
//
// These replace the `ErrorSuggestions` half of `tests/ErrorReportingTests.cs`. `GetSuggestion` is the
// one table that turns an `ErrorCode` into the "help:" line a user reads when the diagnostic itself
// carries no suggestion of its own, and `LevenshteinDistance` is the edit-distance kernel every
// "did you mean" answer in the product is ranked by — including `SmartSuggester`'s, which calls it
// directly.
//
// THE DELETED FILE SAMPLED THREE OF THE TABLE'S TWENTY-SIX ANSWERING CODES AND NEVER ASKED WHAT AN
// UNMAPPED CODE ANSWERS. The whole table is crossed here, in one place, so a code moved between
// bands or a message reworded cannot drift without a named failure.
//
// THE THREE THINGS IT IS EASY TO GET WRONG:
//
// (1) FOUR CODES ANSWER ONLY WHEN THEY ARE GIVEN CONTEXT. `UndefinedVariable`, `UndefinedFunction`
// and `DuckInterfaceMismatch` answer NULL without it, and `ShadowedDeclaration` answers a DIFFERENT
// sentence. A caller that forgets to pass context silently loses the help line.
//
// (2) THE TABLE IS A FALL-THROUGH CHAIN, NOT A SWITCH. `UndefinedVariable` with no context does not
// return — it falls past every remaining arm to the final `null`. That is why "answers null" has to
// be stated, not assumed.
//
// (3) `LevenshteinDistance` IS CASE-SENSITIVE. `SmartSuggester` lowercases both sides BEFORE calling
// it; `IsPossibleTypo` and `FindSimilarType` do the same. The kernel itself never does.

func ErrorSuggestionText(code: ErrorCode): string {
    return ErrorSuggestions.GetSuggestion(code, null, null) ?? "<null>"
}

func ErrorSuggestionTextWithContext(code: ErrorCode, context: string): string {
    return ErrorSuggestions.GetSuggestion(code, context, null) ?? "<null>"
}

func ErrorSuggestionTextWithInfo(code: ErrorCode, additionalInfo: string): string {
    return ErrorSuggestions.GetSuggestion(code, null, additionalInfo) ?? "<null>"
}

// ---- The migrated samples ---------------------------------------------------------------------

// Successor to ErrorSuggestions_TypeNotFound_ReturnsHelpfulMessage.
test "a type that was not found suggests checking the definition and the import" {
    suggestion := ErrorSuggestions.GetSuggestion(ErrorCode.TypeNotFound, null, null)

    assert suggestion != null
    assert (suggestion ?? "").Contains("type is defined")

    // NOT IN THE DELETED FILE: the whole sentence, so a reworded answer names itself.
    assert (suggestion ?? "") == "Check that the type is defined and imported correctly"
}

// Successor to ErrorSuggestions_MissingReturn_ReturnsHelpfulMessage.
test "a missing return suggests a return statement or a void return type" {
    suggestion := ErrorSuggestions.GetSuggestion(ErrorCode.MissingReturn, null, null)

    assert suggestion != null
    assert (suggestion ?? "").Contains("return statement")

    assert (suggestion ?? "") == "Add a return statement or change return type to void"
}

// Successor to ErrorSuggestions_NonExhaustiveMatch_WithAdditionalInfo.
test "a non-exhaustive match names the missing cases it was given" {
    suggestion := ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, "Success, Failure")

    assert suggestion != null
    assert (suggestion ?? "").Contains("Success, Failure")

    assert (suggestion ?? "") == "Add missing cases: Success, Failure, or use wildcard '_' to match all remaining"

    // NOT IN THE DELETED FILE: WITHOUT the additional info the same code answers a different, generic
    // sentence — so the info is not decoration, it selects the arm.
    assert ErrorSuggestionText(ErrorCode.NonExhaustiveMatch) == "Ensure all cases are covered or add wildcard pattern '_'"
}

// ---- The whole table, crossed once -------------------------------------------------------------

// NOT IN THE DELETED FILE AT ALL: every context-free arm of the table, stated together.
test "the context-free suggestion table answers every code it names" {
    assert ErrorSuggestionText(ErrorCode.TypeNotFound) == "Check that the type is defined and imported correctly"
    assert ErrorSuggestionText(ErrorCode.MissingReturn) == "Add a return statement or change return type to void"
    assert ErrorSuggestionText(ErrorCode.DefiniteAssignmentError) == "Initialize property in constructor or provide default value"
    assert ErrorSuggestionText(ErrorCode.ShadowedDeclaration) == "Rename this declaration, or remove it and reuse the variable from the enclosing scope"
    assert ErrorSuggestionText(ErrorCode.UnverifiedErrorResult) == "Check the paired error first, or return/throw from the error branch before using the result"
    assert ErrorSuggestionText(ErrorCode.DiscardedMustUseResult) == "Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`"
    assert ErrorSuggestionText(ErrorCode.TypeMismatch) == "Ensure types are compatible or add explicit cast"
    assert ErrorSuggestionText(ErrorCode.CannotInferType) == "Add explicit type annotation: 'let x: Type = ...'"
    assert ErrorSuggestionText(ErrorCode.NonExhaustiveMatch) == "Ensure all cases are covered or add wildcard pattern '_'"
    assert ErrorSuggestionText(ErrorCode.GuardNotBoolean) == "Guard expression must be boolean type"
    assert ErrorSuggestionText(ErrorCode.WrongArgumentCount) == "Check the function signature for required parameters"
    assert ErrorSuggestionText(ErrorCode.MethodGroupUsedAsValue) == "Call the method with parentheses, or pass it to a parameter with a delegate type"
    assert ErrorSuggestionText(ErrorCode.FeatureNotImplemented) == "This language feature is parsed for forward compatibility, but it is not available in production builds yet"
    assert ErrorSuggestionText(ErrorCode.ReadonlyAssignment) == "Readonly fields can only be assigned in constructor"
    assert ErrorSuggestionText(ErrorCode.VisibilityConventionWarning) == "Use PascalCase for public members or camelCase for private members"
    assert ErrorSuggestionText(ErrorCode.ImportCollision) == "Use 'import ... as Alias' to resolve naming conflicts"
    assert ErrorSuggestionText(ErrorCode.CircularImport) == "Reorganize imports to avoid cycles. Move shared types to a separate file that both files can import"
    assert ErrorSuggestionText(ErrorCode.InvalidOperatorOverload) == "Operators must be public static and have correct parameter types"
    assert ErrorSuggestionText(ErrorCode.ComparisonOperatorPair) == "Define both operators in the pair (== with !=, < with >, <= with >=)"
    assert ErrorSuggestionText(ErrorCode.UnreachableStatement) == "Remove unreachable code or restructure control flow"
    assert ErrorSuggestionText(ErrorCode.InvalidExpressionStatement) == "Use the value by assigning it, printing it, passing it to a call, or remove the expression"
}

// NOT IN THE DELETED FILE AT ALL: the four codes whose answer DEPENDS on what they are given, and
// the fall-through that leaves three of them null when they are given nothing.
test "four codes answer only when they are given context or additional info" {
    assert ErrorSuggestionText(ErrorCode.UndefinedVariable) == "<null>"
    assert ErrorSuggestionTextWithContext(ErrorCode.UndefinedVariable, "counter") == "Variable 'counter' is not defined in current scope"

    assert ErrorSuggestionText(ErrorCode.UndefinedFunction) == "<null>"
    assert ErrorSuggestionTextWithContext(ErrorCode.UndefinedFunction, "Hi") == "Function 'Hi' is not defined in current scope"

    assert ErrorSuggestionText(ErrorCode.DuckInterfaceMismatch) == "<null>"
    assert ErrorSuggestionTextWithInfo(ErrorCode.DuckInterfaceMismatch, "Draw()") == "Implement missing method: Draw()"

    // `ShadowedDeclaration` answers in BOTH cases, but with different sentences — the only code in
    // the table that does.
    assert ErrorSuggestionTextWithContext(ErrorCode.ShadowedDeclaration, "count") == "Rename this declaration (the outer 'count' is still in scope), or remove it and reuse the existing 'count'"
}

// NOT IN THE DELETED FILE AT ALL: the codes the table does NOT name answer null, which is what lets
// a caller fall back to its own text instead of printing a wrong hint.
test "an unmapped code has no suggestion at all" {
    assert ErrorSuggestionText(ErrorCode.UnexpectedToken) == "<null>"
    assert ErrorSuggestionText(ErrorCode.InvalidSyntax) == "<null>"
    assert ErrorSuggestionText(ErrorCode.UnusedVariable) == "<null>"
    assert ErrorSuggestionText(ErrorCode.PossibleNullAccess) == "<null>"
    assert ErrorSuggestionText(ErrorCode.NoMatchingOverload) == "<null>"
    assert ErrorSuggestionText(ErrorCode.AotExpressionTree) == "<null>"
    assert ErrorSuggestionTextWithContext(ErrorCode.UnexpectedToken, "anything") == "<null>"
}

// ---- The typo arm of TypeNotFound ---------------------------------------------------------------

// NOT IN THE DELETED FILE AT ALL: the deleted file only ever called `TypeNotFound` WITHOUT context,
// so the whole typo path — `IsPossibleTypo`, `FindSimilarType` and the ten-name table behind them —
// had no coverage anywhere.
test "a type name close to a built-in is answered as a typo" {
    assert ErrorSuggestionTextWithContext(ErrorCode.TypeNotFound, "strin") == "Did you mean 'string'?"
    assert ErrorSuggestionTextWithContext(ErrorCode.TypeNotFound, "Strng") == "Did you mean 'string'?"
    assert ErrorSuggestionTextWithContext(ErrorCode.TypeNotFound, "inr") == "Did you mean 'int'?"

    // A name far from every built-in falls back to the generic sentence rather than guessing.
    assert ErrorSuggestionTextWithContext(ErrorCode.TypeNotFound, "HttpClientFactory") == "Check that the type is defined and imported correctly"
}

// NOT IN THE DELETED FILE AT ALL.
test "the typo probe is case-insensitive and bounded at distance two" {
    assert ErrorSuggestions.IsPossibleTypo("strin")
    assert ErrorSuggestions.IsPossibleTypo("STRING")
    assert ErrorSuggestions.IsPossibleTypo("st")
    assert !ErrorSuggestions.IsPossibleTypo("HttpClientFactory")
    assert !ErrorSuggestions.IsPossibleTypo("")

    assert ErrorSuggestions.FindSimilarType("strin") == "string"
    assert ErrorSuggestions.FindSimilarType("STRNG") == "string"
    assert ErrorSuggestions.FindSimilarType("dubble") == "double"
    assert ErrorSuggestions.FindSimilarType("Guyd") == "Guid"

    // `FindSimilarType` ALWAYS answers — it has no threshold of its own, which is why only
    // `IsPossibleTypo` may gate the suggestion.
    assert ErrorSuggestions.FindSimilarType("HttpClientFactory") != ""
}

// NOT IN THE DELETED FILE AT ALL: the ten-name table both helpers scan, pinned in order.
test "the common type table is the ten names the typo probe scans" {
    common := ErrorSuggestions.CommonTypes()

    assert common.Length == 10
    assert common[0] == "string"
    assert common[1] == "int"
    assert common[2] == "bool"
    assert common[3] == "double"
    assert common[4] == "float"
    assert common[5] == "long"
    assert common[6] == "decimal"
    assert common[7] == "object"
    assert common[8] == "DateTime"
    assert common[9] == "Guid"
}

// ---- The edit-distance kernel --------------------------------------------------------------------

// Successor to LevenshteinDistance_CalculatesCorrectly.
test "the levenshtein kernel measures insertions, substitutions and case" {
    assert ErrorSuggestions.LevenshteinDistance("test", "test") == 0
    assert ErrorSuggestions.LevenshteinDistance("test", "tests") == 1
    assert ErrorSuggestions.LevenshteinDistance("test", "Test") == 1
    assert ErrorSuggestions.LevenshteinDistance("kitten", "sitting") == 3

    // NOT IN THE DELETED FILE: the two EMPTY arms, which short-circuit before the matrix is even
    // allocated, and are the arms a length-driven off-by-one would land in.
    assert ErrorSuggestions.LevenshteinDistance("", "") == 0
    assert ErrorSuggestions.LevenshteinDistance("", "abc") == 3
    assert ErrorSuggestions.LevenshteinDistance("abc", "") == 3

    // NOT IN THE DELETED FILE: the kernel is SYMMETRIC. Four samples in one direction cannot see a
    // deletion/insertion cost that is not paired, which is the classic transposed-index defect.
    assert ErrorSuggestions.LevenshteinDistance("tests", "test") == 1
    assert ErrorSuggestions.LevenshteinDistance("sitting", "kitten") == 3
    assert ErrorSuggestions.LevenshteinDistance("abc", "xyz") == 3
    assert ErrorSuggestions.LevenshteinDistance("flaw", "lawn") == 2
    assert ErrorSuggestions.LevenshteinDistance("lawn", "flaw") == 2
}

// NOT IN THE DELETED FILE AT ALL.
test "the integer minimum the kernel folds with picks the smaller side" {
    assert ErrorSuggestions.MinInt(2, 5) == 2
    assert ErrorSuggestions.MinInt(5, 2) == 2
    assert ErrorSuggestions.MinInt(4, 4) == 4
    assert ErrorSuggestions.MinInt(-3, 1) == -3
}

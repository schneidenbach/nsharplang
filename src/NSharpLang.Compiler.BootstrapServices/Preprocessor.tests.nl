namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `Preprocessor`, IN N#.
//
// These replace `tests/PreprocessorTests.cs`, the last canonical C# assertion layer over
// `Preprocessor.nl`. The preprocessor is the conditional-compilation pass: it runs BEFORE the
// parser sees anything, over the lexer's token stream (`Process`) or over the raw text
// (`ProcessSource`), and decides which `#if`/`#elif`/`#else` branch survives.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every input is a dependency-assembly
// `List<Token>` produced by `Lexer`, every answer is read off `Token`/`CompilerError`, and the
// defined-symbol argument is a `HashSet<string>` WIDENED to an `IReadOnlySet<string>` parameter —
// all constructed, none primitive.
//
// THE FIRST OF THIS BATCH'S TWO MEASURED WALLS. Omitting a defaulted parameter declines at
// `emit.local.initializer` on static methods, not only on free funcs, so every call here is spelled
// at FULL ARITY. It does not bite this file (its calls have no defaults) but it is why the sibling
// `DiagnosticSpanResolver` and `DotnetRunner` contracts spell `WithSnippet` and `Run` out in full.
// The second wall — a `TimeSpan` may be constructed and passed but not interrogated — is recorded
// where it bites, in `DotnetRunner.tests.nl`.
//
// WHY THE SYMBOL SET IS BUILT BY HAND. The deleted file wrote `new HashSet<string>(defines,
// StringComparer.Ordinal)`. `HashSet<string>`'s default comparer IS ordinal, so
// `PreprocessorContractSymbols` builds the identical set one `Add` at a time and the comparison
// semantics are unchanged — a symbol matches only when it matches exactly, which is the point of
// the case-sensitivity contract below.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE DIRECTIVES MUST NOT SURVIVE. `#if`/`#elif`/`#else`/`#endif` are RESOLVED, so no
// `PreprocessorDirective` token reaches the parser. Every OTHER directive — `#region`, `#endregion`
// and anything unrecognised — is PASSED THROUGH when the branch is live and DROPPED when it is not.
//
// (2) A BRANCH IS TAKEN AT MOST ONCE. `BranchTaken` is sticky: the first `#elif` whose condition
// holds wins, every later `#elif` is dead even if its condition also holds, and `#else` is live
// only when nothing before it was taken.
//
// (3) A NESTED CONDITIONAL UNDER A DEAD BRANCH IS DEAD, AND STILL WELL-FORMED. `ParentActive`
// carries that: the inner `#if` is pushed and popped normally — so no "unterminated" error is
// raised — but nothing inside it can be emitted, whatever its condition says.
//
// (4) EVERY MALFORMED DIRECTIVE IS ONE `InvalidPreprocessorDirective` AND THE BRANCH IS EXCLUDED.
// A condition that does not parse is `false`, not `true`, so a broken `#if` never leaks its body.

func PreprocessorContractSymbols(defines: string[]): HashSet<string> {
    symbolSet := new HashSet<string>()
    index := 0
    while index < defines.Length {
        symbolSet.Add(defines[index])
        index = index + 1
    }

    return symbolSet
}

func PreprocessorContractTokens(source: string, defines: string[], errorList: List<CompilerError>): List<Token> {
    lexer := new Lexer(source, "test.nl")
    tokenList := lexer.Tokenize()
    return Preprocessor.Process(tokenList, PreprocessorContractSymbols(defines), "test.nl", errorList)
}

func PreprocessorContractHas(tokens: List<Token>, name: string): bool {
    for candidate in tokens {
        if candidate.Type == TokenType.Identifier && candidate.Value == name {
            return true
        }
    }

    return false
}

func PreprocessorContractDirectiveCount(tokens: List<Token>): int {
    total := 0
    for candidate in tokens {
        if candidate.Type == TokenType.PreprocessorDirective {
            total = total + 1
        }
    }

    return total
}

func PreprocessorContractDirectiveTexts(tokens: List<Token>): string {
    texts := ""
    for candidate in tokens {
        if candidate.Type == TokenType.PreprocessorDirective {
            texts = texts + candidate.Value + "|"
        }
    }

    return texts
}

// The verdict is THREE-WAY, deliberately. Every row of the deleted `[Theory]` asserted TWO things —
// that the condition raised no diagnostic AND whether the body survived — so a two-valued answer
// would have silently dropped the first half on the rows that answer "excluded". `"error"` is the
// third value, and it is what separates a condition that is FALSE from one that is BROKEN.
func PreprocessorContractConditionVerdict(condition: string, defines: string[]): string {
    errorList := new List<CompilerError>()
    source := "#if " + condition + "\nlet x = body\n#endif"
    tokens := PreprocessorContractTokens(source, defines, errorList)

    if errorList.Count != 0 {
        return "error"
    }

    if PreprocessorContractHas(tokens, "body") {
        return "included"
    }

    return "excluded"
}

func PreprocessorContractConditionErrors(condition: string, defines: string[]): List<CompilerError> {
    errorList := new List<CompilerError>()
    source := "#if " + condition + "\nlet x = body\n#endif"
    PreprocessorContractTokens(source, defines, errorList)
    return errorList
}

func PreprocessorContractCountChar(text: string, needle: char): int {
    total := 0
    index := 0
    while index < text.Length {
        if text[index] == needle {
            total = total + 1
        }

        index = index + 1
    }

    return total
}

func PreprocessorContractTwoBranch(): string {
    return "#if FEATURE_X\nlet value = featureOnValue\n#else\nlet value = featureOffValue\n#endif"
}

// ---- Branch selection -----------------------------------------------------------------------

// Successor to IfBranch_Included_WhenSymbolDefined.
test "preprocessor takes the if branch when the symbol is defined" {
    errorList := new List<CompilerError>()
    tokens := PreprocessorContractTokens(PreprocessorContractTwoBranch(), ["FEATURE_X"], errorList)

    assert errorList.Count == 0
    assert PreprocessorContractHas(tokens, "featureOnValue")
    assert !PreprocessorContractHas(tokens, "featureOffValue")
}

// Successor to ElseBranch_Included_WhenSymbolUndefined.
test "preprocessor takes the else branch when the symbol is undefined" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    tokens := PreprocessorContractTokens(PreprocessorContractTwoBranch(), empty, errorList)

    assert errorList.Count == 0
    assert !PreprocessorContractHas(tokens, "featureOnValue")
    assert PreprocessorContractHas(tokens, "featureOffValue")
}

// Successor to DebugSymbol_IsCaseSensitive.
test "preprocessor matches defined symbols case sensitively" {
    source := "#if DEBUG\nlet x = debugBody\n#endif"
    errorList := new List<CompilerError>()
    empty: string[] = []

    assert PreprocessorContractHas(PreprocessorContractTokens(source, ["DEBUG"], errorList), "debugBody")
    assert !PreprocessorContractHas(PreprocessorContractTokens(source, ["debug"], errorList), "debugBody")
    assert !PreprocessorContractHas(PreprocessorContractTokens(source, empty, errorList), "debugBody")

    // NOT IN THE DELETED FILE: the case-sensitive miss is a MISS, not a malformed condition.
    assert errorList.Count == 0
}

// Successor to Elif_SelectsFirstMatchingBranch_AndIsMutuallyExclusive.
test "preprocessor elif selects the first matching branch" {
    errorList := new List<CompilerError>()
    source := "#if A\nlet v = branchA\n#elif B\nlet v = branchB\n#elif C\nlet v = branchC\n#else\nlet v = branchElse\n#endif"
    tokens := PreprocessorContractTokens(source, ["B", "C"], errorList)

    assert errorList.Count == 0
    assert !PreprocessorContractHas(tokens, "branchA")
    assert PreprocessorContractHas(tokens, "branchB")
    assert !PreprocessorContractHas(tokens, "branchC")
    assert !PreprocessorContractHas(tokens, "branchElse")
}

// Successor to Else_IsTaken_WhenNoBranchMatches.
test "preprocessor takes else when no branch matches" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "#if A\nlet v = branchA\n#elif B\nlet v = branchB\n#else\nlet v = branchElse\n#endif"
    tokens := PreprocessorContractTokens(source, empty, errorList)

    assert !PreprocessorContractHas(tokens, "branchA")
    assert !PreprocessorContractHas(tokens, "branchB")
    assert PreprocessorContractHas(tokens, "branchElse")
}

// NOT IN THE DELETED FILE. `BranchTaken` is STICKY, which the deleted file could only see through
// `#elif`. The first arm winning must also kill a LATER `#elif` whose condition holds AND the
// `#else`, and an `#if` that is taken must leave every later arm dead in the same run.
test "preprocessor keeps a taken branch exclusive against every later arm" {
    errorList := new List<CompilerError>()
    source := "#if A\nlet v = branchA\n#elif A\nlet v = branchAgain\n#elif B\nlet v = branchB\n#else\nlet v = branchElse\n#endif"
    tokens := PreprocessorContractTokens(source, ["A", "B"], errorList)

    assert errorList.Count == 0
    assert PreprocessorContractHas(tokens, "branchA")
    assert !PreprocessorContractHas(tokens, "branchAgain")
    assert !PreprocessorContractHas(tokens, "branchB")
    assert !PreprocessorContractHas(tokens, "branchElse")
}

// NOT IN THE DELETED FILE. An `#elif` chain in which NOTHING matches and there is no `#else` emits
// nothing at all and is still well-formed — the shape that would pass if `#elif` defaulted to live.
test "preprocessor emits nothing when an elif chain matches nothing" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "#if A\nlet v = branchA\n#elif B\nlet v = branchB\n#elif C\nlet v = branchC\n#endif"
    tokens := PreprocessorContractTokens(source, empty, errorList)

    assert errorList.Count == 0
    assert !PreprocessorContractHas(tokens, "branchA")
    assert !PreprocessorContractHas(tokens, "branchB")
    assert !PreprocessorContractHas(tokens, "branchC")
    assert PreprocessorContractDirectiveCount(tokens) == 0
}

// ---- Directive survival ---------------------------------------------------------------------

// Successor to ConditionalDirectiveTokens_AreRemoved.
test "preprocessor resolves conditional directive tokens away" {
    errorList := new List<CompilerError>()
    tokens := PreprocessorContractTokens(PreprocessorContractTwoBranch(), ["FEATURE_X"], errorList)

    assert PreprocessorContractDirectiveCount(tokens) == 0
}

// Successor to RegionDirectives_ArePassedThrough.
test "preprocessor passes region directives through" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    tokens := PreprocessorContractTokens("#region Helpers\nlet x = inRegion\n#endregion", empty, errorList)

    assert errorList.Count == 0
    assert PreprocessorContractHas(tokens, "inRegion")

    texts := PreprocessorContractDirectiveTexts(tokens)
    assert texts.Contains("#region Helpers")
    assert texts.Contains("#endregion")

    // NOT IN THE DELETED FILE: exactly two survive, in source order, and nothing else does.
    assert texts == "#region Helpers|#endregion|"
}

// Successor to RegionInsideExcludedBranch_IsDropped.
test "preprocessor drops a region inside an excluded branch" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "#if FEATURE_X\n#region OnlyWhenOn\nlet x = inRegion\n#endregion\n#endif"
    tokens := PreprocessorContractTokens(source, empty, errorList)

    assert PreprocessorContractDirectiveCount(tokens) == 0
    assert !PreprocessorContractHas(tokens, "inRegion")
}

// NOT IN THE DELETED FILE. An UNRECOGNISED directive takes the same route as `#region`: kept when
// the branch is live, dropped when it is dead. That arm is the one the deleted file's `#region`
// pair could not distinguish from a `#region`-specific rule.
test "preprocessor treats an unrecognised directive like a region" {
    liveErrors := new List<CompilerError>()
    live := PreprocessorContractTokens("#if A\n#pragma keep\nlet x = body\n#endif", ["A"], liveErrors)

    assert liveErrors.Count == 0
    assert PreprocessorContractHas(live, "body")
    assert PreprocessorContractDirectiveTexts(live) == "#pragma keep|"

    deadErrors := new List<CompilerError>()
    empty: string[] = []
    dead := PreprocessorContractTokens("#if A\n#pragma keep\nlet x = body\n#endif", empty, deadErrors)

    assert deadErrors.Count == 0
    assert !PreprocessorContractHas(dead, "body")
    assert PreprocessorContractDirectiveCount(dead) == 0
}

// NOT IN THE DELETED FILE. The end-of-file token ALWAYS survives, in every branch state — the
// parser cannot terminate without it, and a preprocessor that filtered it under a dead branch
// would pass every assertion above.
test "preprocessor always keeps the end of file token" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    tokens := PreprocessorContractTokens("#if A\nlet x = body\n#endif", empty, errorList)

    eofCount := 0
    for candidate in tokens {
        if candidate.Type == TokenType.Eof {
            eofCount = eofCount + 1
        }
    }

    assert eofCount == 1
    assert !PreprocessorContractHas(tokens, "body")
}

// ---- Nesting --------------------------------------------------------------------------------

// Successor to NestedConditional_UnderExcludedOuterBranch_IsExcluded.
test "preprocessor excludes a nested conditional under an excluded outer branch" {
    errorList := new List<CompilerError>()
    source := "#if OUTER\nlet a = outerBody\n#if INNER\nlet b = innerBody\n#endif\n#endif"
    tokens := PreprocessorContractTokens(source, ["INNER"], errorList)

    assert errorList.Count == 0
    assert !PreprocessorContractHas(tokens, "outerBody")
    assert !PreprocessorContractHas(tokens, "innerBody")
}

// NOT IN THE DELETED FILE. The other three quadrants of the same nesting: an ACTIVE outer branch
// admits the inner branch on its own condition, and a nested `#else` under a dead outer branch
// stays dead — which `ParentActive` is the only thing preventing.
test "preprocessor evaluates a nested conditional under a live outer branch" {
    bothErrors := new List<CompilerError>()
    source := "#if OUTER\nlet a = outerBody\n#if INNER\nlet b = innerBody\n#else\nlet c = innerElse\n#endif\n#endif"

    both := PreprocessorContractTokens(source, ["OUTER", "INNER"], bothErrors)
    assert bothErrors.Count == 0
    assert PreprocessorContractHas(both, "outerBody")
    assert PreprocessorContractHas(both, "innerBody")
    assert !PreprocessorContractHas(both, "innerElse")

    outerErrors := new List<CompilerError>()
    outerOnly := PreprocessorContractTokens(source, ["OUTER"], outerErrors)
    assert outerErrors.Count == 0
    assert PreprocessorContractHas(outerOnly, "outerBody")
    assert !PreprocessorContractHas(outerOnly, "innerBody")
    assert PreprocessorContractHas(outerOnly, "innerElse")

    innerErrors := new List<CompilerError>()
    innerOnly := PreprocessorContractTokens(source, ["INNER"], innerErrors)
    assert innerErrors.Count == 0
    assert !PreprocessorContractHas(innerOnly, "outerBody")
    assert !PreprocessorContractHas(innerOnly, "innerBody")
    assert !PreprocessorContractHas(innerOnly, "innerElse")
}

// ---- Condition evaluation -------------------------------------------------------------------

// Successor to the ten BooleanExpressions_EvaluateCorrectly rows, expanded one row per assertion
// because a `with (…) […]` table does not compile under the pinned toolset.
test "preprocessor evaluates boolean conditions" {
    empty: string[] = []

    assert PreprocessorContractConditionVerdict("!A", empty) == "included"
    assert PreprocessorContractConditionVerdict("!A", ["A"]) == "excluded"
    assert PreprocessorContractConditionVerdict("A && B", ["A", "B"]) == "included"
    assert PreprocessorContractConditionVerdict("A && B", ["A"]) == "excluded"
    assert PreprocessorContractConditionVerdict("A || B", ["B"]) == "included"
    assert PreprocessorContractConditionVerdict("A || B", empty) == "excluded"
    assert PreprocessorContractConditionVerdict("(A || B) && !C", ["A"]) == "included"
    assert PreprocessorContractConditionVerdict("(A || B) && !C", ["A", "C"]) == "excluded"
    assert PreprocessorContractConditionVerdict("true", empty) == "included"
    assert PreprocessorContractConditionVerdict("false", empty) == "excluded"
}

// NOT IN THE DELETED FILE. The rows it did not write: a bare symbol either way, `&&` binding
// TIGHTER than `||` (the row `A || B && C` with only `A` defined proves the grammar, not just the
// operators), double negation, nested parentheses, an underscore-led symbol name, and a symbol
// whose name merely STARTS with a defined one.
test "preprocessor evaluates the conditions the deleted rows never combined" {
    empty: string[] = []

    assert PreprocessorContractConditionVerdict("A", ["A"]) == "included"
    assert PreprocessorContractConditionVerdict("A", empty) == "excluded"
    assert PreprocessorContractConditionVerdict("A || B && C", ["A"]) == "included"
    assert PreprocessorContractConditionVerdict("(A || B) && C", ["A"]) == "excluded"
    assert PreprocessorContractConditionVerdict("!!A", ["A"]) == "included"
    assert PreprocessorContractConditionVerdict("!!A", empty) == "excluded"
    assert PreprocessorContractConditionVerdict("((A))", ["A"]) == "included"
    assert PreprocessorContractConditionVerdict("_LEADING", ["_LEADING"]) == "included"
    assert PreprocessorContractConditionVerdict("A1", ["A1"]) == "included"
    assert PreprocessorContractConditionVerdict("AB", ["A"]) == "excluded"
    assert PreprocessorContractConditionVerdict("A", ["AB"]) == "excluded"
}

// NOT IN THE DELETED FILE. `true` and `false` are LITERALS, not symbols — and the reverse: their
// capitalised spellings are ordinary symbol names, undefined unless defined.
test "preprocessor reads true and false as literals and not as symbols" {
    empty: string[] = []

    assert PreprocessorContractConditionVerdict("true", empty) == "included"
    assert PreprocessorContractConditionVerdict("false", empty) == "excluded"
    assert PreprocessorContractConditionVerdict("false", ["false"]) == "excluded"
    assert PreprocessorContractConditionVerdict("True", empty) == "excluded"
    assert PreprocessorContractConditionVerdict("True", ["True"]) == "included"
    assert PreprocessorContractConditionVerdict("!false", empty) == "included"
    assert PreprocessorContractConditionVerdict("true || A", empty) == "included"
    assert PreprocessorContractConditionVerdict("false && A", ["A"]) == "excluded"
}

// Successor to TrailingLineComment_OnCondition_IsIgnored.
test "preprocessor ignores a trailing line comment on a condition" {
    errorList := new List<CompilerError>()
    source := "#if FEATURE_X // turn the feature on\nlet x = body\n#endif"
    tokens := PreprocessorContractTokens(source, ["FEATURE_X"], errorList)

    assert errorList.Count == 0
    assert PreprocessorContractHas(tokens, "body")

    // NOT IN THE DELETED FILE: the same trimming applies to `#elif`, which shares `SplitDirective`.
    elifErrors := new List<CompilerError>()
    elifSource := "#if A\nlet v = branchA\n#elif B // and this one\nlet v = branchB\n#endif"
    elifTokens := PreprocessorContractTokens(elifSource, ["B"], elifErrors)

    assert elifErrors.Count == 0
    assert PreprocessorContractHas(elifTokens, "branchB")
}

// ---- Malformed input ------------------------------------------------------------------------

// Successor to MalformedCondition_ReportsError_AndExcludesBranch.
test "preprocessor reports a malformed condition and excludes the branch" {
    errorList := new List<CompilerError>()
    tokens := PreprocessorContractTokens("#if A &&\nlet x = body\n#endif", ["A"], errorList)

    assert !PreprocessorContractHas(tokens, "body")
    assert errorList.Count == 1
    assert errorList[0].Code == ErrorCode.InvalidPreprocessorDirective

    // NOT IN THE DELETED FILE: the diagnostic is an ERROR at the directive's own position, and it
    // underlines the whole directive rather than collapsing to a point.
    assert errorList[0].Severity == ErrorSeverity.Error
    assert errorList[0].Line == 1
    assert errorList[0].Column == 1
    assert errorList[0].FileName == "test.nl"
    assert errorList[0].Length == 8
}

// Successor to EndifWithoutIf_ReportsError.
test "preprocessor reports an endif without an if" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    PreprocessorContractTokens("#endif", empty, errorList)

    assert errorList.Count == 1
    assert errorList[0].Code == ErrorCode.InvalidPreprocessorDirective
    assert errorList[0].Message.Contains("'#endif' directive without a matching '#if'")
}

// Successor to UnterminatedIf_ReportsError.
test "preprocessor reports an unterminated if" {
    errorList := new List<CompilerError>()
    tokens := PreprocessorContractTokens("#if A\nlet x = body", ["A"], errorList)

    assert errorList.Count == 1
    assert errorList[0].Code == ErrorCode.InvalidPreprocessorDirective

    // NOT IN THE DELETED FILE: the body of an unterminated but TAKEN `#if` still emits, and the
    // error is raised once — the stack is cleared rather than reported per open frame.
    assert errorList[0].Message.Contains("Unterminated '#if' directive")
    assert PreprocessorContractHas(tokens, "body")
}

// Successor to ElifAfterElse_ReportsError.
test "preprocessor reports an elif after an else" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "#if A\nlet x = a\n#else\nlet x = b\n#elif C\nlet x = c\n#endif"
    PreprocessorContractTokens(source, empty, errorList)

    hasCode := false
    for reported in errorList {
        if reported.Code == ErrorCode.InvalidPreprocessorDirective {
            hasCode = true
        }
    }

    assert hasCode

    // NOT IN THE DELETED FILE: the message names the offence, and the frame SURVIVES the error —
    // the `#endif` that follows still pairs, so exactly one diagnostic is reported.
    assert errorList.Count == 1
    assert errorList[0].Message.Contains("'#elif' directive cannot appear after '#else'")
}

// NOT IN THE DELETED FILE. The three unpaired-directive arms it never reached: `#elif` and `#else`
// with no open `#if` at all, and a second `#else` for one `#if`.
test "preprocessor reports unpaired elif and else directives" {
    empty: string[] = []

    elifErrors := new List<CompilerError>()
    PreprocessorContractTokens("#elif A\nlet x = body\n", empty, elifErrors)
    assert elifErrors.Count == 1
    assert elifErrors[0].Code == ErrorCode.InvalidPreprocessorDirective
    assert elifErrors[0].Message.Contains("'#elif' directive without a matching '#if'")

    elseErrors := new List<CompilerError>()
    PreprocessorContractTokens("#else\nlet x = body\n", empty, elseErrors)
    assert elseErrors.Count == 1
    assert elseErrors[0].Message.Contains("'#else' directive without a matching '#if'")

    doubleElseErrors := new List<CompilerError>()
    doubleElse := "#if A\nlet x = a\n#else\nlet x = b\n#else\nlet x = c\n#endif"
    PreprocessorContractTokens(doubleElse, empty, doubleElseErrors)
    assert doubleElseErrors.Count == 1
    assert doubleElseErrors[0].Message.Contains("Multiple '#else' directives for a single '#if'")
}

// NOT IN THE DELETED FILE. The condition evaluator's own refusals, each of which the deleted file
// covered with ONE `A &&`: an empty condition, an unclosed parenthesis, an unexpected character in
// the middle, and trailing junk after a complete condition. Every one of them EXCLUDES the branch.
test "preprocessor reports each malformed condition shape" {
    empty: string[] = []

    missing := PreprocessorContractConditionErrors("", empty)
    assert missing.Count == 1
    assert missing[0].Message.Contains("Missing condition after '#if'/'#elif'")

    unclosed := PreprocessorContractConditionErrors("(A || B", ["A"])
    assert unclosed.Count == 1
    assert unclosed[0].Message.Contains("Missing ')' in preprocessor condition")
    assert PreprocessorContractConditionVerdict("(A || B", ["A"]) == "error"

    unexpected := PreprocessorContractConditionErrors("@A", empty)
    assert unexpected.Count == 1
    assert unexpected[0].Message.Contains("Unexpected character")

    trailing := PreprocessorContractConditionErrors("A )", ["A"])
    assert trailing.Count == 1
    assert trailing[0].Message.Contains("Unexpected character ')'")
    assert PreprocessorContractConditionVerdict("A )", ["A"]) == "error"
}

// ---- ProcessSource --------------------------------------------------------------------------

// Successor to ProcessSource_PreservesLength_AndRemovesInactiveBranches.
test "preprocessor process source preserves length and removes inactive branches" {
    errorList := new List<CompilerError>()
    source := "#region Header\n#if FEATURE_X\nlet value = onValue\n#else\nlet value = offValue\n#endif\n#endregion"
    processed := Preprocessor.ProcessSource(source, PreprocessorContractSymbols(["FEATURE_X"]), "test.nl", errorList)

    assert errorList.Count == 0
    assert processed.Length == source.Length
    assert processed.Contains("#region Header")
    assert processed.Contains("onValue")
    assert !processed.Contains("offValue")
    assert !processed.Contains("#if FEATURE_X")
    assert !processed.Contains("#else")
    assert !processed.Contains("#endif")
}

// NOT IN THE DELETED FILE. Length preservation is the WEAK half of the contract; the strong half is
// that every LINE keeps its own length and its own line break, so a diagnostic computed on the
// processed text lands on the same line and column as one computed on the original. The blanked
// lines are spaces — not deleted, not collapsed.
test "preprocessor process source blanks lines in place" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "#if A\nlet value = offValue\n#endif\nlet kept = keptValue\n"
    processed := Preprocessor.ProcessSource(source, PreprocessorContractSymbols(empty), "test.nl", errorList)

    assert errorList.Count == 0
    assert processed.Length == source.Length
    assert PreprocessorContractCountChar(processed, '\n') == PreprocessorContractCountChar(source, '\n')
    assert processed == "     \n                    \n      \nlet kept = keptValue\n"
}

// NOT IN THE DELETED FILE. A `\r\n` source keeps BOTH characters of every line break — the arm that
// steps over the pair — so a Windows checkout is not silently reflowed.
test "preprocessor process source preserves carriage returns" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "#if A\r\nlet value = offValue\r\n#endif\r\n"
    processed := Preprocessor.ProcessSource(source, PreprocessorContractSymbols(empty), "test.nl", errorList)

    assert errorList.Count == 0
    assert processed.Length == source.Length
    assert PreprocessorContractCountChar(processed, '\r') == 3
    assert PreprocessorContractCountChar(processed, '\n') == 3
    assert processed == "     \r\n                    \r\n      \r\n"
}

// NOT IN THE DELETED FILE. `ProcessSource` finds a directive after LEADING WHITESPACE — it has its
// own scan for that, independent of the lexer — and blanks the indentation with it.
test "preprocessor process source finds an indented directive" {
    errorList := new List<CompilerError>()
    empty: string[] = []
    source := "    #if A\n    let value = offValue\n    #endif\n"
    processed := Preprocessor.ProcessSource(source, PreprocessorContractSymbols(empty), "test.nl", errorList)

    assert errorList.Count == 0
    assert processed.Length == source.Length
    assert !processed.Contains("#if")
    assert !processed.Contains("offValue")
}

// NOT IN THE DELETED FILE. `ProcessSource` reports the SAME unterminated-`#if` diagnostic the token
// path does, at the line after the last one — the two entry points share `AddError`, and the
// deleted file only ever proved it on the token path.
test "preprocessor process source reports an unterminated if" {
    errorList := new List<CompilerError>()
    processed := Preprocessor.ProcessSource("#if A\nlet x = body\n", PreprocessorContractSymbols(["A"]), "test.nl", errorList)

    assert errorList.Count == 1
    assert errorList[0].Code == ErrorCode.InvalidPreprocessorDirective
    assert errorList[0].Message.Contains("Unterminated '#if' directive")
    assert processed.Contains("body")
}

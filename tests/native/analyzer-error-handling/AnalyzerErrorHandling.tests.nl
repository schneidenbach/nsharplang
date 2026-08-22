namespace NSharpLang.AnalyzerErrorHandling.Tests

import System
import System.Collections


// THE ANALYZER'S (AND THE LINTER'S) ERROR-HANDLING DIAGNOSTICS, IN N#.
//
// These replace the ANALYSIS HALF of `tests/ErrorHandlingTests.cs`, which task 020 slice 25 deletes.
// That file's 39 `[Fact]`s split by SUBJECT into 24 that reach only
// `ColumnarParserRecovery.ParseFileAst` — restated in the estate as
// `ColumnarParserErrorHandling.tests.nl` — and the 15 recorded here, which construct an `Analyzer`,
// call `LoadSystemAssemblies()` and the SINGLE-ARGUMENT `Analyze(unit)`, and read
// `AnalysisResult.Errors`. Three of the 15 also construct a `Linter`. The split does not follow the
// method NAMES: `Parser_HandlesDuplicateFunctionDeclarations`,
// `Parser_HandlesInvalidBreakStatement` and `Parser_HandlesInvalidContinueStatement` are named for
// the parser and assert only over `AnalysisResult`, so they are here.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT, MEASURED RATHER THAN ASSUMED. `Analyzer`
// is the C# class in `Compiler.dll`, and `Compiler.dll` depends on
// `NSharpLang.Compiler.BootstrapServices` rather than the other way round, so a `.tests.nl` inside
// the estate cannot reach it in any spelling. The route is REFLECTION through `object`, which slice
// 23 measured to be a constraint of the emitter's type resolution rather than a style choice.
//
// `Linter` IS an estate type and the estate CAN spell it — `Linter.tests.nl` does. Its rows are here
// anyway, and deliberately: the one deleted method that drove both owners asserted them over ONE
// fixture, and it is the PAIRING that carries the content. Splitting it would have lost the fact this
// file exists to state — that on one of the four unreachable-code fixtures the two owners DISAGREE.
//
// FOUR THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//   (a) THE ROWS NOBODY ASKED ABOUT. `Assert.Contains(result.Errors, e => (int)e.Code >= 200 &&
//       (int)e.Code < 300)` is a claim about a NUMERIC RANGE and is silent about every other row.
//       Two fixtures report more rows than the deleted assertion named — one reports two, one
//       reports three — and in both the extra rows are `NL301:UndefinedVariable` on the word `var`,
//       because `var x = …` is C# and the N# parser reads `var` as an ordinary identifier. The
//       censuses below state the WHOLE list, in recording order.
//   (b) THE SPANS. Not one deleted assertion stated a line, a column or a length. Every census here
//       carries all three, which is what makes `NL301` a one-column underline and `NL412` a
//       thirteen-column one — a difference nothing had compared.
//   (c) THE NULL SUGGESTIONS. Four of the nine distinct diagnostics in this cluster carry NO
//       suggestion at all. That is pinned as `<null>` rather than left unstated, so filling the gap
//       is a visible change.
//   (d) THE LINTER'S SILENCE. The analyzer reports `NL312` for unreachable code after a `return`,
//       after two `return`s, after a `throw` AND after an if/else whose branches both return. The
//       linter reports `NL006` for the first three and NOTHING for the fourth. One deleted method
//       read one linter message once; the divergence is stated below.
//
// EVERY PARSE CENSUS BELOW IS PINNED EMPTY, AND ALL FIFTEEN ARE. The deleted helper discarded
// `.Errors` outright, so nothing separated an analyzer diagnostic from a recovery artefact carried in
// from the parse. Pinning the parse silence is what makes every row in every analysis census provably
// the ANALYZER's own.
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself: each deleted
// method's fixture-construction prefix was pasted unmodified into a generated console program that
// printed the resulting string's sha256, its length and its N# spelling.

func SetEhObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// The estate models both fields and property accessors, and `FileParseAst.CompilationUnit` is a
// FIELD while `AnalysisResult.Errors` is a property, so every read tries both.
func EhMember(owner: object, memberName: string): object? {
    property := owner.GetType().GetProperty(memberName)
    if property != null {
        return property.GetValue(owner)
    }

    field := owner.GetType().GetField(memberName)
    if field != null {
        return field.GetValue(owner)
    }

    throw new InvalidOperationException("The production type exposed no '" + memberName + "' member.")
}

func EhRequiredMember(owner: object, memberName: string): object {
    value := EhMember(owner, memberName)
    if value == null {
        throw new InvalidOperationException("The production '" + memberName + "' member was null.")
    }

    return value
}

func EhText(owner: object, memberName: string): string {
    value := EhMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

// The production recovery parser, asked with the file name `test.nl` — exactly as the deleted
// `Parse` helper asked it.
func EhParse(source: string): object {
    parserType := Type.GetType("NSharpLang.Compiler.Columnar.ColumnarParserRecovery, NSharpLang.Compiler.BootstrapServices")
    if parserType == null {
        throw new InvalidOperationException("The production recovery parser was not loadable.")
    }

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(string)
    parseParameterTypes[1] = typeof(string)
    parseMethod := parserType.GetMethod("ParseFileAst", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production ParseFileAst entry point was not found.")
    }

    parseArguments := new object?[](2)
    SetEhObject(parseArguments, 0, source)
    SetEhObject(parseArguments, 1, "test.nl")
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

func EhParseUnit(source: string): object {
    return EhRequiredMember(EhParse(source), "CompilationUnit")
}

// Every PARSE diagnostic of a fixture, in recording order. Pinned EMPTY for all fifteen.
func EhParseCensus(source: string): string {
    errors := EhRequiredMember(EhParse(source), "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + EhText(entry, "DiagnosticId") + "@" + EhText(entry, "Line") + ":" + EhText(entry, "Column") + "+" + EhText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

// The production analysis — `new Analyzer()`, `LoadSystemAssemblies()` and the SINGLE-ARGUMENT
// `Analyze(unit)`, which is the overload the deleted helper called, with the analyzer disposed
// afterwards.
func EhAnalyze(source: string): object {
    unit := EhParseUnit(source)

    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, Compiler")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if analyzerType == null || unitType == null {
        throw new InvalidOperationException("The production analyzer types were not loadable.")
    }

    analyzerConstructor := analyzerType.GetConstructor(new Type[](0))
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production analyzer was not constructible.")
    }
    analyzer := analyzerConstructor.Invoke(new object?[](0))

    loadParameterTypes := new Type[](0)
    loadMethod := analyzerType.GetMethod("LoadSystemAssemblies", loadParameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("The production LoadSystemAssemblies entry point was not found.")
    }
    loadArguments := new object?[](0)
    loadMethod.Invoke(analyzer, loadArguments)

    analyzeParameterTypes := new Type[](1)
    analyzeParameterTypes[0] = unitType
    analyzeMethod := analyzerType.GetMethod("Analyze", analyzeParameterTypes)
    if analyzeMethod == null {
        throw new InvalidOperationException("The production single-argument Analyze entry point was not found.")
    }

    analyzeArguments := new object?[](1)
    SetEhObject(analyzeArguments, 0, unit)
    analysis := analyzeMethod.Invoke(analyzer, analyzeArguments)

    disposeParameterTypes := new Type[](0)
    disposeMethod := analyzerType.GetMethod("Dispose", disposeParameterTypes)
    if disposeMethod != null {
        disposeArguments := new object?[](0)
        disposeMethod.Invoke(analyzer, disposeArguments)
    }

    if analysis == null {
        throw new InvalidOperationException("The production analyzer returned no result.")
    }

    return analysis
}

// EVERY diagnostic's id, code name and span, in recording order. Empty when analysis is silent, and
// non-empty in a way that no `Assert.Contains` over a numeric range could be.
func EhCensus(analysis: object): string {
    errors := EhRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + EhText(entry, "DiagnosticId") + ":" + EhText(entry, "Code") + "@" + EhText(entry, "Line") + ":" + EhText(entry, "Column") + "+" + EhText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func EhHasErrors(analysis: object): string {
    return EhText(analysis, "HasErrors")
}

// One diagnostic, whole, BY POSITION rather than by code. Positional is not a style choice: one
// fixture in this cluster reports the SAME code twice with two different messages, so a code-keyed
// lookup would silently answer the first row twice and the second row would never be stated.
func EhRow(analysis: object, index: int): string {
    errors := EhRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    if index >= errors.Count {
        return "<no-such-error>"
    }

    entry := errors[index]
    if entry == null {
        return "<null-error>"
    }

    return EhText(entry, "Code") + "|" + EhText(entry, "Message") + "|" + EhText(entry, "Suggestion") + "|" + EhText(entry, "Severity")
}

// The production linter — `new Linter()` and `Lint(unit, "test.nl", null)`, the three-argument form
// the estate's own contracts call. `Diagnostic` carries its position in a `Location` node rather
// than in Line/Column fields, which is why this census reads one level deeper than the analyzer's.
func EhLint(source: string): IList {
    unit := EhParseUnit(source)

    linterType := Type.GetType("NSharpLang.Compiler.Linter, NSharpLang.Compiler.BootstrapServices")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if linterType == null || unitType == null {
        throw new InvalidOperationException("The production linter types were not loadable.")
    }

    configType := Type.GetType("NSharpLang.Compiler.LinterConfig, NSharpLang.Compiler.BootstrapServices")
    if configType == null {
        throw new InvalidOperationException("The production linter configuration type was not loadable.")
    }

    linterParameterTypes := new Type[](1)
    linterParameterTypes[0] = configType
    linterConstructor := linterType.GetConstructor(linterParameterTypes)
    if linterConstructor == null {
        throw new InvalidOperationException("The production linter was not constructible.")
    }
    linterArguments := new object?[](1)
    SetEhObject(linterArguments, 0, null)
    linter := linterConstructor.Invoke(linterArguments)

    lintParameterTypes := new Type[](3)
    lintParameterTypes[0] = unitType
    lintParameterTypes[1] = typeof(string)
    lintParameterTypes[2] = typeof(string)
    lintMethod := linterType.GetMethod("Lint", lintParameterTypes)
    if lintMethod == null {
        throw new InvalidOperationException("The production Lint entry point was not found.")
    }

    lintArguments := new object?[](3)
    SetEhObject(lintArguments, 0, unit)
    SetEhObject(lintArguments, 1, "test.nl")
    SetEhObject(lintArguments, 2, null)
    diagnostics := lintMethod.Invoke(linter, lintArguments) as IList
    if diagnostics == null {
        throw new InvalidOperationException("The production linter returned no diagnostic list.")
    }

    return diagnostics
}

func EhLintPosition(entry: object): string {
    location := EhMember(entry, "Location")
    if location == null {
        return "<null>"
    }

    return EhText(location, "Line") + ":" + EhText(location, "Column")
}

func EhLintCensus(source: string): string {
    diagnostics := EhLint(source)
    census := ""
    index := 0
    while index < diagnostics.Count {
        entry := diagnostics[index]
        if entry != null {
            census = census + EhText(entry, "Code") + "@" + EhLintPosition(entry) + "+" + EhText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func EhLintRow(source: string, codeName: string): string {
    diagnostics := EhLint(source)
    index := 0
    while index < diagnostics.Count {
        entry := diagnostics[index]
        if entry != null && EhText(entry, "Code") == codeName {
            return EhText(entry, "Message") + "|" + EhText(entry, "Severity") + "|" + EhText(entry, "Suggestion")
        }

        index = index + 1
    }

    return "<no-such-code>"
}

// ---- contracts ----

// WHAT THIS ADDS: The deleted assertion was `Assert.Contains(result.Errors, e => (int)e.Code >= 200 && (int)e.Code
// < 300)`, a claim about a NUMERIC RANGE that is satisfied by any one row and silent about every
// other. This fixture reports TWO rows, and the first is `NL301:UndefinedVariable` on `var` at 2:5 —
// because `var x: int = ...` is C# and the N# parser reads `var` as an ordinary identifier. The census
// states the whole list in recording order, so the range claim can no longer pass on a tree that also
// reports something unexpected.
test "020 s25 analyzer error handling: a C#-shaped typed declaration reports TWO errors and the FIRST is not a type error at all — NL301 on the word `var` — with NL202 naming both the declared and the actual type (was ErrorHandlingTests.Analyzer_DetectsTypeMismatch)" {
    source := "func main() {\n    var x: int = \"string\"  // Type mismatch\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL301:UndefinedVariable@2:5+1;NL202:TypeMismatch@2:9+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UndefinedVariable|I can't find 'var' — it hasn't been declared in this scope|<null>|Error"
    assert EhRow(analysis, 1) == "TypeMismatch|Variable 'x' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert EhRow(analysis, 2) == "<no-such-error>"
    assert EhLintCensus(source) == "NL001@2:9+1;"
    assert EhLintRow(source, "NL001") == "Variable 'x' is declared but never read|Error|If this is intentional, prefix it with '_' to indicate it's unused: '_x'"
}

// WHAT THIS ADDS: The deleted assertion read the code and a message substring. This adds the id, the exact
// span (2:11, one column, the `undefinedVar` read inside `print(...)`), the whole message, and the fact
// that this diagnostic carries a NULL Suggestion — a gap in the guidance that nothing recorded.
test "020 s25 analyzer error handling: an undefined variable is NL301 at the READ position with the name in the message and NO suggestion (was ErrorHandlingTests.Analyzer_DetectsUndefinedVariable)" {
    source := "func main() {\n    print(undefinedVar)\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL301:UndefinedVariable@2:11+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UndefinedVariable|I can't find 'undefinedVar' — it hasn't been declared in this scope|<null>|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion read the code and a message substring. The span is the find: NL412
// underlines from column 5 for 13 columns, covering `undefinedFunc()` including its parentheses, while
// the sibling NL301 above underlines a single column. Nothing compared them.
test "020 s25 analyzer error handling: an undefined function is NL412 whose span is THIRTEEN columns — the whole call, not the name — and it too carries no suggestion (was ErrorHandlingTests.Analyzer_DetectsUndefinedFunction)" {
    source := "func main() {\n    undefinedFunc()\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL412:UndefinedFunction@2:5+13;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UndefinedFunction|Function 'undefinedFunc' not found|<null>|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was `Assert.Contains(result.Errors, e => e.Message.Contains("argument"))`
// — the weakest claim in the file, satisfiable by any message with that substring anywhere. The census
// names all three rows: NL301 on `var` at 6:5, NL301 on `result` at 6:9 (the assignment target is never
// declared, because `var result = ...` is not a declaration in N#), and only then the real
// NL401:WrongArgumentCount at 6:18 over the callee, whose message states both counts.
test "020 s25 analyzer error handling: a wrong argument count reports THREE errors, and the two the deleted assertion did not ask about are NL301s on `var` and on the declared name (was ErrorHandlingTests.Analyzer_DetectsWrongArgumentCount)" {
    source := "func add(a: int, b: int) -> int {\n    return a + b\n}\n\nfunc main() {\n    var result = add(1)  // Wrong number of arguments\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL301:UndefinedVariable@6:5+1;NL301:UndefinedVariable@6:9+1;NL401:WrongArgumentCount@6:18+3;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UndefinedVariable|I can't find 'var' — it hasn't been declared in this scope|<null>|Error"
    assert EhRow(analysis, 1) == "UndefinedVariable|I can't find 'result' — it hasn't been declared in this scope|<null>|Error"
    assert EhRow(analysis, 2) == "WrongArgumentCount|'add' takes 2 argument(s), but you passed 1|Check the argument count against the function signature.|Error"
    assert EhRow(analysis, 3) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was again the 200-299 numeric range. This pins that the row is
// singular, that it anchors at 2:5 on the `return` and not on the value at 2:12, and the whole message
// and suggestion.
test "020 s25 analyzer error handling: a return-type mismatch is ONE NL202 anchored on the `return` KEYWORD, and its message names the function, the declared type and the actual type (was ErrorHandlingTests.Analyzer_DetectsReturnTypeMismatch)" {
    source := "func getNumber() -> int {\n    return \"not a number\"\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL202:TypeMismatch@2:5+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "TypeMismatch|Function 'getNumber' should return 'int', but this return statement gives back 'string'|Ensure types are compatible or add explicit cast|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was a three-way message substring OR — `duplicate` or `already
// defined` or `already declared` — which none of the three would have matched had the wording changed
// to any of the others. The real message says `is already declared in this scope`, and it is pinned
// whole, with the code, the id and the span at 5:1 over the four columns of `func`.
test "020 s25 analyzer error handling: a duplicated function declaration is ONE NL306 anchored on the SECOND declaration's `func` keyword, spanning four columns (was ErrorHandlingTests.Parser_HandlesDuplicateFunctionDeclarations)" {
    source := "func test() {\n    print(\"first\")\n}\n\nfunc test() {\n    print(\"second\")\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL306:DuplicateDeclaration@5:1+4;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "DuplicateDeclaration|'test' is already declared in this scope — each name must be unique within the same scope|<null>|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: This is the only deleted method that drove both owners, and it read one message substring
// from each. Both censuses are pinned here: the analyzer's `NL312:UnreachableStatement@3:5+1` and the
// linter's `NL006@3:5+1`. They agree on the sentence and differ in the suggestion — the analyzer says
// restructure control flow, the linter says move it before the return — which no substring could
// compare.
test "020 s25 analyzer error handling: unreachable code after a bare `return` is reported TWICE by two different owners — NL312 by the ANALYZER and NL006 by the LINTER — at the SAME position, with the same sentence and DIFFERENT guidance (was ErrorHandlingTests.Analyzer_DetectsUnreachableCode)" {
    source := "func main() {\n    return\n    print(\"unreachable\")\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL312:UnreachableStatement@3:5+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UnreachableStatement|This code will never run — there's a 'return' or 'throw' above it|Remove unreachable code or restructure control flow|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == "NL006@3:5+1;"
    assert EhLintRow(source, "NL006") == "This code will never run — there's a 'return' or 'throw' above it|Error|Remove the unreachable code, or move it before the return/throw if it should execute"
}

// WHAT THIS ADDS: The deleted assertion read only the analyzer's code. Both censuses are pinned, so this
// fixture and the bare-return one above are now provably the same diagnostic at the same span rather
// than merely both containing an unreachable error.
test "020 s25 analyzer error handling: a second `return` after the first is the same NL312 at 3:5, and the linter agrees at the same position (was ErrorHandlingTests.Analyzer_DetectsUnreachableCodeAfterTwoReturns)" {
    source := "func getValue() -> int {\n    return 1\n    return 2\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL312:UnreachableStatement@3:5+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UnreachableStatement|This code will never run — there's a 'return' or 'throw' above it|Remove unreachable code or restructure control flow|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == "NL006@3:5+1;"
    assert EhLintRow(source, "NL006") == "This code will never run — there's a 'return' or 'throw' above it|Error|Remove the unreachable code, or move it before the return/throw if it should execute"
}

// WHAT THIS ADDS: The deleted assertion read only the analyzer's code. Pinning both censuses is what makes
// the throw/return equivalence a stated fact rather than a coincidence of two passing tests.
test "020 s25 analyzer error handling: unreachable code after a `throw` is the same NL312 at 3:5 as after a `return`, and the linter agrees — the two terminators are interchangeable to both owners (was ErrorHandlingTests.Analyzer_DetectsUnreachableCodeAfterThrow)" {
    source := "func main() {\n    throw Exception(\"fail\")\n    print(\"unreachable\")\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL312:UnreachableStatement@3:5+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UnreachableStatement|This code will never run — there's a 'return' or 'throw' above it|Remove unreachable code or restructure control flow|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == "NL006@3:5+1;"
    assert EhLintRow(source, "NL006") == "This code will never run — there's a 'return' or 'throw' above it|Error|Remove the unreachable code, or move it before the return/throw if it should execute"
}

// WHAT THIS ADDS: THE FIND OF THIS FILE. The deleted assertion read only the analyzer's code, so nobody had
// asked the linter. The linter reports NL006 for a bare `return`, for a double `return` and for a
// `throw` — and reports NOTHING for an if/else whose branches both return, while the analyzer reports
// NL312 at 7:5. The empty linter census is pinned deliberately: this contract states the divergence,
// so closing it is a decision someone has to make rather than an accident.
test "020 s25 analyzer error handling: unreachable code after an if/else where BOTH branches return is NL312 at 7:5 — and THE LINTER IS SILENT HERE, which is a real disagreement between the two owners (was ErrorHandlingTests.Analyzer_DetectsUnreachableCodeAfterIfElseBothReturn)" {
    source := "func getValue(x: int) -> int {\n    if x > 0 {\n        return 1\n    } else {\n        return 2\n    }\n    print(\"unreachable\")\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL312:UnreachableStatement@7:5+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UnreachableStatement|This code will never run — there's a 'return' or 'throw' above it|Remove unreachable code or restructure control flow|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was `Assert.DoesNotContain(…, e.Code == UnreachableStatement)`, which
// is satisfied by a result carrying any number of OTHER errors. The census is empty, which is strictly
// stronger, and the linter census is empty too.
test "020 s25 analyzer error handling: code where only one branch returns is analysed with an EMPTY diagnostic list and an empty linter list — the unreachable rule is not a ban on statements after an `if` (was ErrorHandlingTests.Analyzer_NoUnreachableErrorForValidCode)" {
    source := "func getValue(x: int) -> int {\n    if x > 0 {\n        return 1\n    }\n    return 2\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == ""
    assert EhHasErrors(analysis) == "False"
    assert EhRow(analysis, 0) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was `Assert.Single(result.Errors, e => e.Code == UnreachableStatement)`,
// a claim about the rows carrying ONE code. The census states the whole list, so it also states that
// the other two unreachable statements produce nothing at all and that no other diagnostic joins
// them.
test "020 s25 analyzer error handling: three statements after a `return` produce exactly ONE NL312, on the first of them — and the linter also reports exactly one (was ErrorHandlingTests.Analyzer_ReportsOnlyFirstUnreachableStatement)" {
    source := "func main() {\n    return\n    print(\"first\")\n    print(\"second\")\n    print(\"third\")\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL312:UnreachableStatement@3:5+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "UnreachableStatement|This code will never run — there's a 'return' or 'throw' above it|Remove unreachable code or restructure control flow|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == "NL006@3:5+1;"
    assert EhLintRow(source, "NL006") == "This code will never run — there's a 'return' or 'throw' above it|Error|Remove the unreachable code, or move it before the return/throw if it should execute"
}

// WHAT THIS ADDS: The deleted assertion was `e.Message.Contains("return") || e.Message.Contains("path")`, an
// OR over two substrings that the real message satisfies twice over. The anchor is the find: NL305
// underlines a single column at 1:1, the start of the whole function, so an editor squiggle for this
// diagnostic lands on `func` and not on the branch that fails to return.
test "020 s25 analyzer error handling: a function whose only `return` is inside an `if` reports NL305 anchored at 1:1 — the FUNCTION, not the missing branch — with a one-column span (was ErrorHandlingTests.Analyzer_DetectsMissingReturn)" {
    source := "func getValue() -> int {\n    if true {\n        return 42\n    }\n    // Missing return in else branch\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL305:MissingReturn@1:1+1;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "MissingReturn|This function should return 'int', but not all code paths return a value — make sure every branch ends with a 'return'|Add a return statement or change return type to void|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was a case-insensitive substring search for `break`, which the word
// appears in three times. The whole row is pinned: the code is `InvalidSyntax` and not a dedicated one,
// the span is exactly the keyword's five columns at 2:5, and the suggestion names the two ways out.
test "020 s25 analyzer error handling: `break` outside a loop is NL103:InvalidSyntax spanning the five columns of the keyword, with guidance in backticks (was ErrorHandlingTests.Parser_HandlesInvalidBreakStatement)" {
    source := "func main() {\n    break  // Break outside loop\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL103:InvalidSyntax@2:5+5;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "InvalidSyntax|'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here|Move this `break` inside a loop, or remove it if there is no loop to exit.|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

// WHAT THIS ADDS: The deleted assertion was a case-insensitive substring search for `continue`. Pinning both
// rows is what makes the `break`/`continue` pairing visible: same code, same anchor column, spans of 5
// and 8, and two messages that differ only in the keyword and the verb.
test "020 s25 analyzer error handling: `continue` outside a loop is the SAME NL103:InvalidSyntax code as `break`, distinguished only by its eight-column span and its wording (was ErrorHandlingTests.Parser_HandlesInvalidContinueStatement)" {
    source := "func main() {\n    continue  // Continue outside loop\n}"
    assert EhParseCensus(source) == ""
    analysis := EhAnalyze(source)
    assert EhCensus(analysis) == "NL103:InvalidSyntax@2:5+8;"
    assert EhHasErrors(analysis) == "True"
    assert EhRow(analysis, 0) == "InvalidSyntax|'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here|Move this `continue` inside a loop, or remove it if there is no loop to continue.|Error"
    assert EhRow(analysis, 1) == "<no-such-error>"
    assert EhLintCensus(source) == ""
}

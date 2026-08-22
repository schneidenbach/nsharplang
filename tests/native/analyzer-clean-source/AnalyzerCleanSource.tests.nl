namespace NSharpLang.AnalyzerCleanSource.Tests

import System
import System.Collections


// THE ANALYZER'S ASSIGNABILITY AND FLOW-NARROWING RULES, READ FROM SOURCE TEXT, IN N#.
//
// THIS FILE HOLDS TWO TRANCHES. Slice 28's is below, under `// ---- contracts ----`; slice 29's —
// tranche 1b, the seven remaining `#region`s — is behind its own banner further down, and its header
// carries the findings that only the SECOND tranche's instruments could reach.
//
// These replace TRANCHE 1a of `tests/AnalyzerTests.cs` — the file's FIRST TWELVE `#region`s, taken
// whole: `Nominal Subtyping`, `Numeric Widening`, `Nullable Assignability`, `Flow-Sensitive Null
// Narrowing`, `Enum Exhaustiveness`, `Unknown Type Kinds`, the five `Flow Narrowing:` regions and
// `Lambda-Delegate Structural Validation`. 109 `[Fact]`s, 1,584 C# lines, 37 `Assert.` occurrences,
// 154 decoded claim rows. Task 020 slice 28 deletes them.
//
// WHY THE TWELVE, AND WHY NOT THIRTEEN. The whole 19-region tranche the campaign sketch priced is
// 190 methods over 2,241 declaration lines, which does not fit one slice. Region 12 closes at 1,295
// declaration lines; region 13 (`Generic Constraint Validation`) would carry it to 1,567. Twelve is
// the largest whole-region prefix under the budget, and it is contiguous in the source file.
//
// AND THE CONTIGUOUS SPAN IS NOT THE TRANCHE. Three un-regioned `ReflectionGenericReceiver_*`
// methods sit between region 2 and region 3, and all three read `result.SemanticModel
// .LookupIdentifier` — a semantic-model surface this project has no kernel for. They stay in
// `AnalyzerTests.cs`, so the deletion is TWO spans rather than one. The rule that decided it is the
// campaign's own: classify by what the body NAMES, never by where it sits or what it is called.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT. Every one of the 109 deleted bodies
// reaches the analyzer through one private helper — `ColumnarParserRecovery.ParseFileAst(source,
// null)`, `new Analyzer()`, `LoadSystemAssemblies()`, `Analyze(unit)` — and `Analyzer` is the C#
// class in `Compiler.dll`, which depends on `NSharpLang.Compiler.BootstrapServices` rather than the
// other way round. A `.tests.nl` inside the estate cannot reach it in any spelling. The route is
// REFLECTION through `object`, exactly as slices 25-27 established.
//
// THE INSTRUMENT IS COPIED, NOT SHARED. `AcParse` / `AcParseCensus` / `AcAnalyze` / `AcCensus` /
// `AcHasErrors` / `AcRow` are `tests/native/analyzer-error-handling`'s `Eh*` kernels renamed, and
// `AcErrorCount` / `AcCodeCount` are `tests/native/analyzer-semantic-model`'s `Sm*` pair renamed.
// Each native project carries its own reflection plumbing by design; there is no shared prelude to
// import. TWO kernels are new here: `AcHint`, which reads the `ContextualHint` field no contract in
// this arc had read, and the NULL file name in `AcParse` — the deleted helper passed `null` where
// slice 25's passed `"test.nl"`, and the census is pinned against the parse the deleted code
// actually performed.
//
// SEVEN THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//
//   (a) EVERY ONE OF THE 109 PARSE CENSUSES IS EMPTY, AND ALL 109 ARE PINNED. The deleted helper
//       discarded `.Errors` from the parse outright, so nothing separated an analyzer diagnostic
//       from a recovery artefact carried in from the parse. Pinning the parse silence is what makes
//       every row in every analysis census provably the ANALYZER's own.
//
//   (b) THE CLEAN CLAIM WAS ONE BOOLEAN AND IT IS NOW THE WHOLE LIST. `AssertNoErrors` asserted
//       `result.HasErrors == false` and nothing else — a claim that says nothing about warnings,
//       nothing about how many rows there are, and nothing about what they say. All 86 silent
//       fixtures here pin an EMPTY census, an error COUNT of zero, and `<no-such-error>` at index 0.
//       Measured: all 75 `AssertNoErrors` claims hold, so this tranche has no false-clean fixture —
//       unlike the parser campaign's, whose sources were C#-shaped.
//
//   (c) THE `NL202` MESSAGE ON A REJECTED LAMBDA SAYS A VALUE IS NOT ASSIGNABLE TO ITS OWN TYPE.
//       `Lambda_Delegate_WrongParamCount_Error` reports TWO rows, and the second reads `Variable 'f'
//       is typed as 'NSharpLang.Compiler.FunctionTypeInfo', but the value is
//       'NSharpLang.Compiler.FunctionTypeInfo'` — a user-facing sentence that leaks a
//       COMPILER-INTERNAL CLR type name on BOTH sides. The deleted method matched the eleven
//       characters `is typed as` and asked about one row; nothing could see either fact.
//
//   (d) A CODE NAMED `NullabilityWarning` IS REPORTED AT `Error` SEVERITY, TWICE. `NL907` fires for
//       a redundant `must` and for an unguarded `.Value`, and both rows are `Error`. The name is the
//       only thing that says warning.
//
//   (e) THE SPANS, WHICH NOT ONE OF THE 109 METHODS STATED. Two `Assert.Equal(…​.Length)` calls read
//       a length and NO method read a line or a column. All 24 diagnostic rows here carry all three,
//       and the audit of what sits at each is in the ledger: `NL202` anchors on the DECLARED NAME
//       (one column, fourteen times), `NL905` on the RECEIVER (`x`, `b`, and five columns of
//       `items`), `NL907` on the `must` KEYWORD and on the member name `Value` with the dot OUTSIDE
//       the underline, `NL501` on the `match` KEYWORD in both the enum and the nullable case,
//       `NL203` on the offending lambda PARAMETER, and `NL412` on the callee NAME with the
//       parentheses EXCLUDED.
//
//   (f) THE SUGGESTIONS, WHICH NO DELETED ASSERTION READ AT ALL. Fourteen of the 24 rows share one
//       sentence (`Ensure types are compatible or add explicit cast`); the `NL905` suggestions are
//       TEMPLATED WITH THE USER'S OWN VARIABLE NAME (`guard with 'if items == null { return }'`) and
//       the index form suggests `?[` where the dereference form suggests `?.`; and `NL412` carries
//       NO suggestion at all.
//
//   (g) THE `ContextualHint` OF ALL 24 ROWS IS NULL. `AnalyzerTests.cs` has an `AssertHasHint`
//       helper that reads exactly that field, used by a later tranche. In this tranche it is null
//       everywhere, pinned as `<null>` rather than left unstated.
//
// TWO MEASURED FACTS ABOUT THE NULLABLE MATRIX WORTH READING TOGETHER. `x: string = null` and
// `f: Foo = null` are both accepted in SILENCE — the deleted comments call that intended, because
// N# embraces .NET's null — while `x: int = null` is rejected. So the non-nullable annotation on a
// REFERENCE type is not enforced at the assignment; it is enforced at the DEREFERENCE, where
// `NL905` fires. Both halves are pinned here, on adjacent fixtures, for the first time.
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself: every method's
// `@"…"` literal was copied unmodified into a generated console program that printed its sha256 and
// its length, and the decoder that produced the strings below reproduces all 109 shas and lengths
// with zero mismatches. All 109 are distinct.


func SetAcObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func AcMember(owner: object, memberName: string): object? {
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

func AcRequiredMember(owner: object, memberName: string): object {
    value := AcMember(owner, memberName)
    if value == null {
        throw new InvalidOperationException("The production '" + memberName + "' member was null.")
    }

    return value
}

func AcText(owner: object, memberName: string): string {
    value := AcMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func AcParse(source: string): object {
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
    SetAcObject(parseArguments, 0, source)
    SetAcObject(parseArguments, 1, null)
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

func AcParseUnit(source: string): object {
    return AcRequiredMember(AcParse(source), "CompilationUnit")
}

func AcParseNamed(source: string): object {
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
    SetAcObject(parseArguments, 0, source)
    SetAcObject(parseArguments, 1, "test.nl")
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

func AcCensusOfParse(parsed: object): string {
    errors := AcRequiredMember(parsed, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + AcText(entry, "DiagnosticId") + "@" + AcText(entry, "Line") + ":" + AcText(entry, "Column") + "+" + AcText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func AcRowOfParse(parsed: object, index: int): string {
    errors := AcRequiredMember(parsed, "Errors") as IList
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

    return AcText(entry, "Code") + "|" + AcText(entry, "Message") + "|" + AcText(entry, "Suggestion") + "|" + AcText(entry, "Severity")
}

func AcParseCensus(source: string): string {
    return AcCensusOfParse(AcParse(source))
}

func AcParseNamedCensus(source: string): string {
    return AcCensusOfParse(AcParseNamed(source))
}

func AcParseSuccess(source: string): string {
    return AcText(AcParse(source), "Success")
}

func AcParseNamedSuccess(source: string): string {
    return AcText(AcParseNamed(source), "Success")
}

func AcParseNamedRow(source: string, index: int): string {
    return AcRowOfParse(AcParseNamed(source), index)
}

func AcAnalyze(source: string): object {
    unit := AcParseUnit(source)

    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, Compiler")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if analyzerType == null || unitType == null {
        throw new InvalidOperationException("The production analyzer types were not loadable.")
    }

    constructorParameterTypes := new Type[](0)
    analyzerConstructor := analyzerType.GetConstructor(constructorParameterTypes)
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production analyzer was not constructible.")
    }
    constructorArguments := new object?[](0)
    analyzer := analyzerConstructor.Invoke(constructorArguments)

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
    SetAcObject(analyzeArguments, 0, unit)
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

func AcCensus(analysis: object): string {
    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + AcText(entry, "DiagnosticId") + ":" + AcText(entry, "Code") + "@" + AcText(entry, "Line") + ":" + AcText(entry, "Column") + "+" + AcText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func AcHasErrors(analysis: object): string {
    return AcText(analysis, "HasErrors")
}

func AcErrorCount(analysis: object): int {
    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return -1
    }

    return errors.Count
}

func AcCodeCount(analysis: object, codeName: string): int {
    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return -1
    }

    matches := 0
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null && AcText(entry, "Code") == codeName {
            matches = matches + 1
        }

        index = index + 1
    }

    return matches
}

func AcRow(analysis: object, index: int): string {
    errors := AcRequiredMember(analysis, "Errors") as IList
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

    return AcText(entry, "Code") + "|" + AcText(entry, "Message") + "|" + AcText(entry, "Suggestion") + "|" + AcText(entry, "Severity")
}

func AcHint(analysis: object, index: int): string {
    errors := AcRequiredMember(analysis, "Errors") as IList
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

    return AcText(entry, "ContextualHint")
}

func AcSnippet(analysis: object, index: int): string {
    errors := AcRequiredMember(analysis, "Errors") as IList
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

    return AcText(entry, "SourceSnippet")
}

func AcAnalyzeWithSource(source: string): object {
    unit := AcParseUnit(source)

    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, Compiler")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if analyzerType == null || unitType == null {
        throw new InvalidOperationException("The production analyzer types were not loadable.")
    }

    constructorParameterTypes := new Type[](0)
    analyzerConstructor := analyzerType.GetConstructor(constructorParameterTypes)
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production analyzer was not constructible.")
    }
    constructorArguments := new object?[](0)
    analyzer := analyzerConstructor.Invoke(constructorArguments)

    loadParameterTypes := new Type[](0)
    loadMethod := analyzerType.GetMethod("LoadSystemAssemblies", loadParameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("The production LoadSystemAssemblies entry point was not found.")
    }
    loadArguments := new object?[](0)
    loadMethod.Invoke(analyzer, loadArguments)

    analyzeParameterTypes := new Type[](4)
    analyzeParameterTypes[0] = unitType
    analyzeParameterTypes[1] = typeof(string)
    analyzeParameterTypes[2] = typeof(string)
    analyzeParameterTypes[3] = typeof(string)
    analyzeMethod := analyzerType.GetMethod("Analyze", analyzeParameterTypes)
    if analyzeMethod == null {
        throw new InvalidOperationException("The production four-argument Analyze entry point was not found.")
    }

    analyzeArguments := new object?[](4)
    SetAcObject(analyzeArguments, 0, unit)
    SetAcObject(analyzeArguments, 1, "test.nl")
    SetAcObject(analyzeArguments, 2, null)
    SetAcObject(analyzeArguments, 3, source)
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


// ---- slice 30's kernels: the ERROR-CODE census read ----
//
// `AnalyzerTests.cs`'s `AssertHasErrorCode(source, code)` and `AssertNoErrorCode(source, code)` are
// the one shape the campaign had no kernel for: both select by `e.Code == code && e.Severity ==
// ErrorSeverity.Error` rather than by a message substring, and the presence half RETURNS the
// matching row so the caller can read its fields. `AcCodeMatchIndex` is that selection, and the
// four functions over it are what the deleted helpers could answer plus what they could not:
// `AcCodeErrorCount` is the absence half exactly, `AcCodeCount` (built in slice 28) is its
// severity-BLIND sibling and is pinned beside it on every fixture so the two are measured against
// each other, and `AcCodeRow` / `AcCodeAnchor` state what the returned row actually says and where
// it points. `AcSuggestions` reads the PLURAL `Suggestions` list — a member no contract in this arc
// had read, and the one the deleted `error.Suggestion ?? string.Join(", ", error.Suggestions ?? …)`
// fallback exists for.

func AcCodeMatchIndex(analysis: object, codeName: string): int {
    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return -1
    }

    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null && AcText(entry, "Code") == codeName && AcText(entry, "Severity") == "Error" {
            return index
        }

        index = index + 1
    }

    return -1
}

func AcCodeErrorCount(analysis: object, codeName: string): int {
    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return -1
    }

    matches := 0
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null && AcText(entry, "Code") == codeName && AcText(entry, "Severity") == "Error" {
            matches = matches + 1
        }

        index = index + 1
    }

    return matches
}

func AcCodeRow(analysis: object, codeName: string): string {
    index := AcCodeMatchIndex(analysis, codeName)
    if index < 0 {
        return "<no-such-code>"
    }

    return AcRow(analysis, index)
}

func AcCodeAnchor(analysis: object, codeName: string): string {
    index := AcCodeMatchIndex(analysis, codeName)
    if index < 0 {
        return "<no-such-code>"
    }

    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    entry := errors[index]
    if entry == null {
        return "<null-error>"
    }

    return AcText(entry, "DiagnosticId") + "@" + AcText(entry, "Line") + ":" + AcText(entry, "Column") + "+" + AcText(entry, "Length")
}

func AcItemText(values: IList, index: int): string {
    item := values[index]
    if item == null {
        return "<null>"
    }

    return item.ToString() ?? "<null>"
}

func AcSuggestions(analysis: object, index: int): string {
    errors := AcRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    if index < 0 || index >= errors.Count {
        return "<no-such-error>"
    }

    entry := errors[index]
    if entry == null {
        return "<null-error>"
    }

    values := AcMember(entry, "Suggestions") as IList
    if values == null {
        return "<null>"
    }

    joined := ""
    position := 0
    while position < values.Count {
        if position > 0 {
            joined = joined + ", "
        }

        joined = joined + AcItemText(values, position)
        position = position + 1
    }

    return joined
}

// ---- contracts ----

// ======== Nominal Subtyping — 3 contracts ========

test "020 s28 analyzer clean source: a `Dog` that derives from `Animal` assigns to an `Animal`-typed local and the analysis is SILENT — both censuses EMPTY, which is strictly stronger than the deleted `HasErrors == false` (was AnalyzerTests.NominalSubtyping_ClassInheritance_Assignable)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func Main() {\n                dog := new Dog()\n                animal: Animal = dog\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a class that implements `IGreetable` assigns to an `IGreetable`-typed local and the analysis is SILENT (was AnalyzerTests.NominalSubtyping_InterfaceImplementation_Assignable)" {
    source := "\n            interface IGreetable {\n                func Greet(): string\n            }\n            class Person : IGreetable {\n                func Greet(): string {\n                    return \"Hello\"\n                }\n            }\n            func Main() {\n                p := new Person()\n                g: IGreetable = p\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int`, a `string` and a `bool` all assign to `object`-typed locals in one function and the analysis is SILENT (was AnalyzerTests.NominalSubtyping_EverythingAssignableToObject)" {
    source := "\n            func Main() {\n                x: object = 42\n                y: object = \"hello\"\n                z: object = true\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Numeric Widening — Comprehensive Assignability Matrix — 53 contracts ========

test "020 s28 analyzer clean source: a `byte` widens to a `short` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ByteToShort)" {
    source := "\n            func GetByte(): byte { return 0 as byte }\n            func Main() {\n                x: byte = GetByte()\n                y: short = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `byte` widens to an `int` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ByteToInt)" {
    source := "\n            func GetByte(): byte { return 0 as byte }\n            func Main() {\n                x: byte = GetByte()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `byte` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ByteToLong)" {
    source := "\n            func GetByte(): byte { return 0 as byte }\n            func Main() {\n                x: byte = GetByte()\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `byte` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ByteToFloat)" {
    source := "\n            func GetByte(): byte { return 0 as byte }\n            func Main() {\n                x: byte = GetByte()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `byte` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ByteToDouble)" {
    source := "\n            func GetByte(): byte { return 0 as byte }\n            func Main() {\n                x: byte = GetByte()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `byte` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ByteToDecimal)" {
    source := "\n            func GetByte(): byte { return 0 as byte }\n            func Main() {\n                x: byte = GetByte()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `sbyte` widens to a `short` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_SByteToShort)" {
    source := "\n            func GetSByte(): sbyte { return 0 as sbyte }\n            func Main() {\n                x: sbyte = GetSByte()\n                y: short = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `sbyte` widens to an `int` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_SByteToInt)" {
    source := "\n            func GetSByte(): sbyte { return 0 as sbyte }\n            func Main() {\n                x: sbyte = GetSByte()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `sbyte` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_SByteToLong)" {
    source := "\n            func GetSByte(): sbyte { return 0 as sbyte }\n            func Main() {\n                x: sbyte = GetSByte()\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `sbyte` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_SByteToFloat)" {
    source := "\n            func GetSByte(): sbyte { return 0 as sbyte }\n            func Main() {\n                x: sbyte = GetSByte()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `sbyte` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_SByteToDouble)" {
    source := "\n            func GetSByte(): sbyte { return 0 as sbyte }\n            func Main() {\n                x: sbyte = GetSByte()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `sbyte` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_SByteToDecimal)" {
    source := "\n            func GetSByte(): sbyte { return 0 as sbyte }\n            func Main() {\n                x: sbyte = GetSByte()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `short` widens to an `int` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ShortToInt)" {
    source := "\n            func GetShort(): short { return 0 as short }\n            func Main() {\n                x: short = GetShort()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `short` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ShortToLong)" {
    source := "\n            func GetShort(): short { return 0 as short }\n            func Main() {\n                x: short = GetShort()\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `short` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ShortToFloat)" {
    source := "\n            func GetShort(): short { return 0 as short }\n            func Main() {\n                x: short = GetShort()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `short` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ShortToDouble)" {
    source := "\n            func GetShort(): short { return 0 as short }\n            func Main() {\n                x: short = GetShort()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `short` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ShortToDecimal)" {
    source := "\n            func GetShort(): short { return 0 as short }\n            func Main() {\n                x: short = GetShort()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ushort` widens to an `int` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UShortToInt)" {
    source := "\n            func GetUShort(): ushort { return 0 as ushort }\n            func Main() {\n                x: ushort = GetUShort()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ushort` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UShortToLong)" {
    source := "\n            func GetUShort(): ushort { return 0 as ushort }\n            func Main() {\n                x: ushort = GetUShort()\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ushort` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UShortToFloat)" {
    source := "\n            func GetUShort(): ushort { return 0 as ushort }\n            func Main() {\n                x: ushort = GetUShort()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ushort` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UShortToDouble)" {
    source := "\n            func GetUShort(): ushort { return 0 as ushort }\n            func Main() {\n                x: ushort = GetUShort()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ushort` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UShortToDecimal)" {
    source := "\n            func GetUShort(): ushort { return 0 as ushort }\n            func Main() {\n                x: ushort = GetUShort()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_IntToLong)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_IntToFloat)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_IntToDouble)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_IntToDecimal)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `uint` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UIntToLong)" {
    source := "\n            func GetUInt(): uint { return 0 as uint }\n            func Main() {\n                x: uint = GetUInt()\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `uint` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UIntToFloat)" {
    source := "\n            func GetUInt(): uint { return 0 as uint }\n            func Main() {\n                x: uint = GetUInt()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `uint` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UIntToDouble)" {
    source := "\n            func GetUInt(): uint { return 0 as uint }\n            func Main() {\n                x: uint = GetUInt()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `uint` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_UIntToDecimal)" {
    source := "\n            func GetUInt(): uint { return 0 as uint }\n            func Main() {\n                x: uint = GetUInt()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `long` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_LongToFloat)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `long` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_LongToDouble)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `long` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_LongToDecimal)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ulong` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ULongToFloat)" {
    source := "\n            func GetULong(): ulong { return 0 as ulong }\n            func Main() {\n                x: ulong = GetULong()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ulong` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ULongToDouble)" {
    source := "\n            func GetULong(): ulong { return 0 as ulong }\n            func Main() {\n                x: ulong = GetULong()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `ulong` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_ULongToDecimal)" {
    source := "\n            func GetULong(): ulong { return 0 as ulong }\n            func Main() {\n                x: ulong = GetULong()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: the unsigned literal suffixes `u`, `U`, `ul` and `UL` together with `uint` / `ulong` / `long` targets analyse SILENT in one function (was AnalyzerTests.IntegerLiteralTypes_UnsignedSuffixesAndTargetTypes_NoError)" {
    source := "\n            import System.Numerics\n\n            func ReturnUlongMax(): ulong {\n                return 0xFFFFFFFFFFFFFFFFUL\n            }\n\n            func ReturnUintHighBit(): uint {\n                return 0x80000000\n            }\n\n            func CountMasked(value: ulong): int {\n                return BitOperations.PopCount(value & 0xF0F0F0F0F0F0F0F0UL)\n            }\n\n            func CountLiteral(): int {\n                return BitOperations.PopCount(0xF0F0F0F0F0F0F0F0UL)\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `char` widens to an `int` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_CharToInt)" {
    source := "\n            func GetChar(): char { return 65 as char }\n            func Main() {\n                x: char = GetChar()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `char` widens to a `long` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_CharToLong)" {
    source := "\n            func GetChar(): char { return 65 as char }\n            func Main() {\n                x: char = GetChar()\n                y: long = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `char` widens to a `float` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_CharToFloat)" {
    source := "\n            func GetChar(): char { return 65 as char }\n            func Main() {\n                x: char = GetChar()\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `char` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_CharToDouble)" {
    source := "\n            func GetChar(): char { return 65 as char }\n            func Main() {\n                x: char = GetChar()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `char` widens to a `decimal` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_CharToDecimal)" {
    source := "\n            func GetChar(): char { return 65 as char }\n            func Main() {\n                x: char = GetChar()\n                y: decimal = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `float` widens to a `double` and the analysis is SILENT — both censuses EMPTY (was AnalyzerTests.NumericWidening_FloatToDouble)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: float = x\n                z: double = y\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing an `int` to a `byte` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_IntToByte_Rejected)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: byte = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'byte', but the value is 'int'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `short` to a `byte` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_ShortToByte_Rejected)" {
    source := "\n            func GetShort(): short { return 0 as short }\n            func Main() {\n                x: short = GetShort()\n                y: byte = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'byte', but the value is 'short'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `long` to an `int` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_LongToInt_Rejected)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int', but the value is 'long'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `double` to a `float` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_DoubleToFloat_Rejected)" {
    source := "\n            func Main() {\n                x: double = 3.14\n                y: float = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'float', but the value is 'double'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `decimal` to a `double` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_DecimalToDouble_Rejected)" {
    source := "\n            func GetDecimal(): decimal { return 0 as decimal }\n            func Main() {\n                x: decimal = GetDecimal()\n                y: double = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'double', but the value is 'decimal'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing an `int` to a `short` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_IntToShort_Rejected)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: short = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'short', but the value is 'int'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `double` to an `int` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_DoubleToInt_Rejected)" {
    source := "\n            func Main() {\n                x: double = 3.14\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int', but the value is 'double'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `float` to an `int` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_FloatToInt_Rejected)" {
    source := "\n            func GetFloat(): float { return 0 as float }\n            func Main() {\n                x: float = GetFloat()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int', but the value is 'float'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `decimal` to an `int` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_DecimalToInt_Rejected)" {
    source := "\n            func GetDecimal(): decimal { return 0 as decimal }\n            func Main() {\n                x: decimal = GetDecimal()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int', but the value is 'decimal'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: narrowing a `long` to a `short` is ONE `NL202:TypeMismatch` on the DECLARED NAME `y`, ONE column wide, and the message names both the declared and the actual type (was AnalyzerTests.NumericNarrowing_LongToShort_Rejected)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: short = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'short', but the value is 'long'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

// ======== Nullable Assignability — Comprehensive Matrix — 9 contracts ========

test "020 s28 analyzer clean source: an `int` widens to an `int?` and the analysis is SILENT (was AnalyzerTests.NullableWidening_IntToNullableInt)" {
    source := "\n            func Main() {\n                x: int = 42\n                y: int? = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `string` widens to a `string?` and the analysis is SILENT (was AnalyzerTests.NullableWidening_StringToNullableString)" {
    source := "\n            func Main() {\n                x: string = \"hello\"\n                y: string? = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: `null` assigns to an `int?` and the analysis is SILENT (was AnalyzerTests.NullableAssignment_NullToNullableInt)" {
    source := "\n            func Main() {\n                x: int? = null\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: `null` assigns to a `string?` and the analysis is SILENT (was AnalyzerTests.NullableAssignment_NullToNullableString)" {
    source := "\n            func Main() {\n                x: string? = null\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: `null` assigns to a NON-nullable `string` with no diagnostic at all — the reference-type hole, pinned as an EMPTY census rather than left implied (was AnalyzerTests.NullAssignment_NullToString)" {
    source := "\n            func Main() {\n                x: string = null\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: `null` assigned to a non-nullable `int` is ONE `NL202:TypeMismatch` on the DECLARED NAME `x` at 3:17, one column, and the message spells the value `null` (was AnalyzerTests.NullAssignment_NullToInt_Rejected)" {
    source := "\n            func Main() {\n                x: int = null\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'x' is typed as 'int', but the value is 'null'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int?` widens to a `long?` and the analysis is SILENT (was AnalyzerTests.NullableWidening_NullableIntToNullableLong)" {
    source := "\n            func GetNullableInt(): int? { return null }\n            func Main() {\n                x: int? = GetNullableInt()\n                y: long? = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `int?` widens to `object` and the analysis is SILENT (was AnalyzerTests.NullableWidening_NullableIntToObject)" {
    source := "\n            func GetNullableInt(): int? { return null }\n            func Main() {\n                x: int? = GetNullableInt()\n                y: object = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: `null` assigns to a NON-nullable user class type with no diagnostic at all, the same hole as the `string` case (was AnalyzerTests.NullAssignment_NullToClassType)" {
    source := "\n            class Foo {\n                x: int = 0\n            }\n            func Main() {\n                f: Foo = null\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Flow-Sensitive Null Narrowing — 22 contracts ========

test "020 s28 analyzer clean source: an `if x != null` guard narrows a `string?` to `string` inside the then-branch and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_NullCheckNarrowsToNonNullable)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                if x != null {\n                    y: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `if x == null` guard narrows in the ELSE branch and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_EqualNullNarrowsInElse)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                if x == null {\n                    // x is still string? here\n                } else {\n                    y: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: reading `.Length` off an unguarded `string?` is ONE `NL905:PossibleNullAccess` at 4:24 spanning ONE column — the RECEIVER `x`, not the member — with a four-option suggestion the deleted substring match never read (was AnalyzerTests.Nullability_PossibleDereferenceReportsStableError)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                len := x.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL905:PossibleNullAccess@4:24+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "PossibleNullAccess|Possible null dereference: `x` is maybe-null|Use '?.', add a '??' fallback, guard with 'if x == null { return }', or explicitly assert after proving 'x' is not null.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 1
}

test "020 s28 analyzer clean source: an early-return guard narrows a `string?` parameter for the rest of the function and the analysis is SILENT (was AnalyzerTests.Nullability_GuardClauseNarrowsAfterEarlyReturn)" {
    source := "\n            func LengthOrZero(x: string?): int {\n                if x == null {\n                    return 0\n                }\n\n                return x.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: calling a method on a nullable receiver is ONE `NL905` whose span is the RECEIVER `b` — one column at 7:24 — and whose suggestion names the guard in the user's own variable (was AnalyzerTests.Nullability_StrictFlow_MethodCallOnNullableReceiverErrors)" {
    source := "\n            class Box {\n                func Open(): int { return 1 }\n            }\n\n            func Use(b: Box?): int {\n                return b.Open()\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL905:PossibleNullAccess@7:24+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "PossibleNullAccess|Possible null dereference: `b` is maybe-null|Use '?.', add a '??' fallback, guard with 'if b == null { return }', or explicitly assert after proving 'b' is not null.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 1
}

test "020 s28 analyzer clean source: indexing a nullable array is `Possible null INDEX`, not `dereference`, spanning FIVE columns at 3:24 and suggesting `?[` rather than `?.` (was AnalyzerTests.Nullability_StrictFlow_IndexAccessOnNullableReceiverErrors)" {
    source := "\n            func First(items: int[]?): int {\n                return items[0]\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL905:PossibleNullAccess@3:24+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "PossibleNullAccess|Possible null index: `items` is maybe-null|Use '?[', add a '??' fallback, guard with 'if items == null { return }', or explicitly assert after proving 'items' is not null.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 1
}

test "020 s28 analyzer clean source: a `??` fallback narrows the result to non-null and the analysis is SILENT (was AnalyzerTests.Nullability_StrictFlow_CoalesceFallbackNarrowsToNonNull)" {
    source := "\n            func Length(s: string?): int {\n                t := s ?? \"fallback\"\n                return t.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: a `throw` guard narrows after the early exit and the analysis is SILENT (was AnalyzerTests.Nullability_StrictFlow_ThrowGuardNarrowsAfterEarlyExit)" {
    source := "\n            import System\n\n            func Length(s: string?): int {\n                if s == null {\n                    throw new Exception(\"value was null\")\n                }\n\n                return s.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: an `is string str` pattern binds a non-null `str` and the analysis is SILENT (was AnalyzerTests.Nullability_StrictFlow_IsPatternNarrowsBoundVariable)" {
    source := "\n            func Length(s: string?): int {\n                if s is string str {\n                    return str.Length\n                }\n                return 0\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: a `match` with a `null` arm narrows the other arm and the analysis is SILENT (was AnalyzerTests.Nullability_StrictFlow_MatchNullArmNarrowsOtherArm)" {
    source := "\n            func Length(s: string?): int {\n                return match s {\n                    null => 0,\n                    other => other.Length\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: a NON-nullable receiver never reports `NL905`, and the whole analysis is SILENT — which the deleted `DoesNotContain` could not distinguish from a file full of other errors (was AnalyzerTests.Nullability_StrictFlow_NonNullableTypeNeverErrors)" {
    source := "\n            class Box {\n                func Open(): int { return 1 }\n            }\n\n            func Use(b: Box): int {\n                return b.Open()\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: assigning a non-null value clears the null state of a `string?` local and the analysis is SILENT (was AnalyzerTests.Nullability_StrictFlow_ReassignmentToNonNullClearsNullState)" {
    source := "\n            func Length(): int {\n                x: string? = null\n                x = \"now not null\"\n                return x.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: `s?.Length` never reports `NL905`, and the whole analysis is SILENT (was AnalyzerTests.Nullability_StrictFlow_NullConditionalAccessNeverErrors)" {
    source := "\n            func Length(s: string?): int? {\n                return s?.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: writing `null` after a guard invalidates the guard, and the message flips from `is maybe-null` to `is null` — the same code, the same span shape, a DIFFERENT sentence (was AnalyzerTests.Nullability_AssignmentInvalidatesPriorGuardFact)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                if x == null {\n                    return\n                }\n\n                x = null\n                len := x.Length\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL905:PossibleNullAccess@9:24+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "PossibleNullAccess|Possible null dereference: `x` is null|Use '?.', add a '??' fallback, guard with 'if x == null { return }', or explicitly assert after proving 'x' is not null.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 1
}

test "020 s28 analyzer clean source: a guard on the member path `p.Name` narrows the later read of the same path and the analysis is SILENT (was AnalyzerTests.Nullability_StableMemberPathGuardNarrowsValueUse)" {
    source := "\n            record Person {\n                Name: string?\n            }\n\n            func Read(p: Person): string {\n                if p.Name == null {\n                    return \"\"\n                }\n\n                name: string = p.Name\n                return name\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: a `while x != null` condition narrows the loop BODY even though the body writes `null` back, and the analysis is SILENT (was AnalyzerTests.Nullability_LoopConditionNarrowsBody)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                while x != null {\n                    len := x.Length\n                    x = null\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "PossibleNullAccess") == 0
}

test "020 s28 analyzer clean source: `must` unwraps an `int?` to `int` and the analysis is SILENT (was AnalyzerTests.MustExpression_UnwrapsNullableToInnerType)" {
    source := "\n            func Take(value: int): int { return value }\n            func Main(input: int?): int {\n                return Take(must input)\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `must` after a `HasValue` guard is `NL907` at 4:28 spanning the FOUR columns of the `must` KEYWORD, and its message names the already-known type (was AnalyzerTests.MustExpression_RedundantAfterHasValueGuard_Errors)" {
    source := "\n            func Main(input: int?): int {\n                if input.HasValue {\n                    return must input\n                }\n                return 0\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL907:NullabilityWarning@4:28+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "NullabilityWarning|This 'must' unwrap is redundant — the expression is already known to be 'int'|Remove the 'must' keyword, or keep the original nullable value until the point where you need to unwrap it.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "NullabilityWarning") == 1
}

test "020 s28 analyzer clean source: a `HasValue` guard makes `.Value` safe and the analysis is SILENT (was AnalyzerTests.NullableHasValueGuard_AllowsValueAccessWithoutUnsafeWarning)" {
    source := "\n            func Main(input: int?): int {\n                if input.HasValue {\n                    return input.Value\n                }\n                return 0\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "NullabilityWarning") == 0
}

test "020 s28 analyzer clean source: an unguarded `.Value` is `NL907` at 3:30 spanning the FIVE columns of the member name `Value`, the dot OUTSIDE the underline, and it is reported at `Error` severity even though the code is NAMED `NullabilityWarning` (was AnalyzerTests.NullableValueAccess_UnguardedIsAnError)" {
    source := "\n            func Main(input: int?): int {\n                return input.Value\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL907:NullabilityWarning@3:30+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "NullabilityWarning|This '.Value' access can throw when the nullable value is absent|Prefer 'must value' for an explicit unwrap, or use 'match value { null => ..., inner => ... }' to handle both cases.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "NullabilityWarning") == 1
}

test "020 s28 analyzer clean source: a `match` over an `int?` binds the present arm as `int` and the analysis is SILENT (was AnalyzerTests.NullableMatch_BindsPresentArmAsInnerType)" {
    source := "\n            func Main(input: int?): int {\n                return match input {\n                    null => 0,\n                    value => value + 1\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a nullable `match` with no `null` arm is `NL501:NonExhaustiveMatch` anchored on the `match` KEYWORD at 3:24 — the SAME code an enum gap reports — with a nullable-specific sentence and suggestion (was AnalyzerTests.NullableMatch_MissingNullCoverageErrors)" {
    source := "\n            func Main(input: int?): int {\n                return match input {\n                    value => value + 1\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL501:NonExhaustiveMatch@3:24+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "NonExhaustiveMatch|This nullable match doesn't cover null — handle both 'null' and a non-null value arm|Use `null => ...` for the absent case and `value => ...` to bind the non-null value.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "NonExhaustiveMatch") == 1
}

// ======== Enum Exhaustiveness — 4 contracts ========

test "020 s28 analyzer clean source: a `match` covering all three enum members analyses SILENT (was AnalyzerTests.EnumExhaustiveness_AllCasesCovered_NoError)" {
    source := "\n            enum Status {\n                Active = 0,\n                Inactive = 1\n            }\n            func Main() {\n                s: Status = Status.Active\n                result := match s {\n                    Status.Active => \"on\",\n                    Status.Inactive => \"off\"\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `_` wildcard arm covers the remaining enum members and the analysis is SILENT (was AnalyzerTests.EnumExhaustiveness_WildcardCovers_NoError)" {
    source := "\n            enum Status {\n                Active = 0,\n                Inactive = 1,\n                Pending = 2\n            }\n            func Main() {\n                s: Status = Status.Active\n                result := match s {\n                    Status.Active => \"on\",\n                    _ => \"other\"\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a `match` missing one enum member is ONE `NL501` anchored on the `match` KEYWORD at 9:27, whose message and suggestion both NAME the missing member (was AnalyzerTests.EnumExhaustiveness_MissingCase_Error)" {
    source := "\n            enum Status {\n                Active = 0,\n                Inactive = 1,\n                Pending = 2\n            }\n            func Main() {\n                s: Status = Status.Active\n                result := match s {\n                    Status.Active => \"on\",\n                    Status.Inactive => \"off\"\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL501:NonExhaustiveMatch@9:27+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "NonExhaustiveMatch|This match doesn't cover all enum members — missing: Pending|Add missing cases: Pending, or use wildcard '_' to match all remaining|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an enum member assigns to an `int` local implicitly and the analysis is SILENT (was AnalyzerTests.EnumToInt_ImplicitlyAssignable)" {
    source := "\n            enum Priority {\n                Low = 0,\n                High = 1\n            }\n            func Main() {\n                p := Priority.Low\n                n: int = p\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Unknown Type Kinds — 1 contracts ========

test "020 s28 analyzer clean source: an undefined call reports ONE `NL412` at 3:22 spanning SEVENTEEN columns — the callee NAME exactly, parentheses EXCLUDED — and NO cascading `NL202` on the local that takes its value (was AnalyzerTests.UnknownKind_ErrorRecovery_SuppressesCascading)" {
    source := "\n            func Main() {\n                x := undefinedFunction()\n                y: int = x\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL412:UndefinedFunction@3:22+17;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedFunction|Function 'undefinedFunction' not found|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
}

// ======== Flow Narrowing: && Chaining — 3 contracts ========

test "020 s28 analyzer clean source: an `&&` chain of two null checks narrows BOTH variables in the then-branch and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_AndChain_BothNullChecks)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                y: int? = 42\n                if x != null && y != null {\n                    a: string = x\n                    b: int = y\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `&&` chain mixing a null check with an ordinary condition narrows and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_AndChain_NullCheckWithCondition)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                if x != null && true {\n                    a: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: the ELSE branch of an `&&` chain narrows NOTHING, and the resulting `NL202` on the declared name `b` at 8:21 is the only diagnostic — its message spelling the source type `string?` with the question mark (was AnalyzerTests.FlowNarrowing_AndChain_NoElseNarrowing)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                y: int? = 42\n                if x != null && y != null {\n                    a: string = x\n                } else {\n                    b: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@8:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'b' is typed as 'string', but the value is 'string?'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

// ======== Flow Narrowing: Is-Type Patterns — 3 contracts ========

test "020 s28 analyzer clean source: an `is` pattern that BINDS a variable narrows it and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_IsPattern_BindsVariable)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func TakeAnimal(a: Animal) {\n                if a is Dog d {\n                    name: string = d.Name\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `is` pattern with NO binding still narrows the tested variable and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_IsPattern_NarrowsWithoutBinding)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func TakeAnimal(a: Animal) {\n                if a is Dog {\n                    dog: Dog = a\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: an `is` pattern inside an `&&` chain narrows and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_IsPattern_WithAndChain)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func TakeAnimal(a: Animal, x: string?) {\n                if a is Dog && x != null {\n                    dog: Dog = a\n                    s: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Flow Narrowing: Or-Chain — 4 contracts ========

test "020 s28 analyzer clean source: the ELSE branch of an `||` chain narrows both variables and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_OrChain_NarrowsInElseBranch)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                y: int? = 42\n                if x == null || y == null {\n                    // can't narrow here — one or the other failed\n                } else {\n                    a: string = x\n                    b: int = y\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: the THEN branch of an `||` chain narrows NOTHING, and the resulting `NL202` on the declared name `a` at 6:21 is the only diagnostic (was AnalyzerTests.FlowNarrowing_OrChain_NoThenNarrowing)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                y: int? = 42\n                if x == null || y == null {\n                    a: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@6:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'a' is typed as 'string', but the value is 'string?'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a THREE-term `||` chain narrows all three variables in the else-branch and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_OrChain_TripleNullCheck)" {
    source := "\n            func Main() {\n                x: string? = \"a\"\n                y: string? = \"b\"\n                z: string? = \"c\"\n                if x == null || y == null || z == null {\n                    // can't narrow\n                } else {\n                    a: string = x\n                    b: string = y\n                    c: string = z\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: the right operand of an `||` sees the left operand's else-narrowing and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_OrChain_RhsSeesLeftElseNarrowing)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                if x == null || x.Length > 0 {\n                    // can narrow x in then body only if both sides hold,\n                    // but the important thing is no error on x.Length\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Flow Narrowing: And-Chain RHS Narrowing — 2 contracts ========

test "020 s28 analyzer clean source: the right operand of an `&&` sees the left operand's narrowing and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_AndChain_RhsSeesLeftNarrowing)" {
    source := "\n            func Main() {\n                x: string? = \"hello\"\n                if x != null && x.Length > 0 {\n                    s: string = x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: the right operand of an `&&` sees the left operand's `is`-pattern narrowing and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_AndChain_RhsSeesIsPatternNarrowing)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func TakeAnimal(a: Animal) {\n                if a is Dog && a.Breed == \"poodle\" {\n                    breed: string = a.Breed\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Flow Narrowing: Same-Symbol Intersection — 2 contracts ========

test "020 s28 analyzer clean source: two narrowings of the SAME symbol keep the most specific type and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_SameSymbol_KeepsMostSpecific)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func TakeAnimal(a: Animal) {\n                if a is Dog && a is Animal {\n                    d: Dog = a\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: the same two narrowings in REVERSED order keep the same most-specific type and the analysis is SILENT (was AnalyzerTests.FlowNarrowing_SameSymbol_ReversedOrder_KeepsMostSpecific)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func TakeAnimal(a: Animal) {\n                if a is Animal && a is Dog {\n                    d: Dog = a\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

// ======== Lambda-Delegate Structural Validation — 3 contracts ========

test "020 s28 analyzer clean source: a one-parameter lambda assigned to `Func<int, string>` analyses SILENT (was AnalyzerTests.Lambda_Delegate_CorrectParamCount_NoError)" {
    source := "\n            func Apply(f: Func<int, string>, x: int): string {\n                return f(x)\n            }\n            func Main() {\n                result := Apply((x) => \"hello\", 42)\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a TWO-parameter lambda in a one-parameter delegate home reports TWO diagnostics — `NL203` on the surplus parameter `y` at 3:48, then an `NL202` on `f` that says the value is not assignable to ITSELF, both sides spelled `NSharpLang.Compiler.FunctionTypeInfo` (was AnalyzerTests.Lambda_Delegate_WrongParamCount_Error)" {
    source := "\n            func Main() {\n                let f: Func<int, string> = (x, y) => \"hello\"\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL203:CannotInferType@3:48+1;NL202:TypeMismatch@3:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 2
    assert AcRow(analysis, 0) == "CannotInferType|I can't figure out the type of lambda parameter 'y' — nothing here names the lambda's delegate type|Give the lambda a typed home (e.g., 'let f: Func<int, int> = y => ...') or pass it directly where a delegate type is expected.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "TypeMismatch|Variable 'f' is typed as 'NSharpLang.Compiler.FunctionTypeInfo', but the value is 'NSharpLang.Compiler.FunctionTypeInfo'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 1) == "<null>"
    assert AcRow(analysis, 2) == "<no-such-error>"
}

test "020 s28 analyzer clean source: a zero-parameter lambda matches `Func<int>` and the analysis is SILENT (was AnalyzerTests.Lambda_Delegate_ZeroParams_MatchesFunc)" {
    source := "\n            func RunIt(f: Func<int>): int {\n                return f()\n            }\n            func Main() {\n                result := RunIt(() => 42)\n            }\n        "
    assert AcParseCensus(source) == ""
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
}


// ================================================================================================
// TRANCHE 1b — THE SEVEN REMAINING `#region`s OF `tests/AnalyzerTests.cs`. 82 `[Fact]`s, 1,193 C#
// lines, 22 `Assert.` occurrences, 134 decoded claim rows. Task 020 slice 29 deletes them, and after
// it the file has no `#region` left.
//
// THE HEADLINE: `Analyze(unit)` AND `Analyze(unit, path, root, source)` ARE DIFFERENT ANSWERS, AND
// PRODUCTION CALLS THE ONE 73 OF THE 82 DELETED ASSERTIONS NEVER DROVE. There are exactly TWO
// production call sites — `MultiFileCompiler.cs:282` and the language server's
// `DocumentManager.cs:277` — and BOTH pass all four arguments; the one-argument overload has ZERO
// production callers. The deleted helpers `AssertNoErrors`, `AssertHasError`, `AssertHasStrictError`
// and `AssertNoWarning` all pass ONE. Measured over these 82 fixtures, the two entry points return
// the same codes every time and disagree otherwise:
//
//   * 22 of the 33 reporting fixtures get a DIFFERENT COLUMN or LENGTH. The plain route anchors an
//     `NL202` on the DECLARED NAME one column wide; the production route anchors it on the VALUE and
//     underlines the whole thing (`null`, `"red"`, `42`). `NL506` is `is` two columns plain and
//     `is string` nine columns rich. `NL208` on a circular constraint is the `f` of `func` plain and
//     `func` rich.
//   * 15 of them get a DIFFERENT MESSAGE, and the rich one is SHORTER. `Variable 'c' is typed as
//     'Color', but the value is 'string'` becomes the bare `Type mismatch`, and its suggestion
//     (`Ensure types are compatible or add explicit cast`) is DROPPED to null.
//   * `ContextualHint` is non-null on 15 fixtures through the production route and on ZERO through
//     the plain one. That is why slice 28 pinned `AcHint` as `<null>` twenty-four times: the field is
//     a property of the ENTRY POINT, not of the fixture.
//   * `SourceSnippet` is non-null on all 33 reporting fixtures rich and on ZERO plain.
//
// Every contract below states BOTH routes, so the deleted claim and the shipped behaviour are pinned
// side by side.
//
// THREE FIXTURES DO NOT PARSE, AND TWO OF THEM MADE A VACUOUS CLAIM. A bodiless positional record —
// `record Person(Name: string, Age: int)` — is a PARSE ERROR in N#: the parser reports `NL102
// Expected '{'` and `NL106 Missing closing '}'` and swallows the rest of the file. Two of the three
// fixtures that spell one are `AssertNoErrors` methods, so their `HasErrors == false` held only
// because the analyzer never saw the declaration they were written to test. The deleted helper threw
// `ParseResult.Errors` away; the census pins it, 82 times.
//
// THE FILE NAME IS INERT. `ParseFileAst(source, null)` and `ParseFileAst(source, "test.nl")` return
// the same census and the same `Success` on all 82 fixtures — pinned in both spellings on every one,
// which is what makes the two `AssertHasParseError` methods' `"test.nl"` route provably equivalent to
// the `null` route the other 80 used.
//
// `AssertHasStrictError` IS NOT STRICT MODE. Its body is the same no-config `Analyze(source)` every
// other helper calls; the name describes a severity-filtered CLAIM. Zero of the 82 bodies names a
// `ProjectConfig`.
// ================================================================================================

// ======== Generic Constraint Validation — 21 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.GenericConstraint_Satisfied_NoError)" {
    source := "\n            interface IComparable {\n                func CompareTo(other: object): int\n            }\n            class MyInt : IComparable {\n                func CompareTo(other: object): int {\n                    return 0\n                }\n            }\n            func Max<T>(a: T, b: T): T where T : IComparable {\n                return a\n            }\n            func Main() {\n                result := Max(new MyInt(), new MyInt())\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` at `11:27+3`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.GenericConstraint_Violated_Error)" {
    source := "\n            interface IComparable {\n                func CompareTo(other: object): int\n            }\n            class Plain {\n            }\n            func Max<T>(a: T, b: T): T where T : IComparable {\n                return a\n            }\n            func Main() {\n                result := Max(new Plain(), new Plain())\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@11:27+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|`Plain` does not implement `IComparable`, which type parameter `T` of `Max` requires|Implement `IComparable` on `Plain`, or relax the constraint on `Max`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@11:27+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|`Plain` does not implement `IComparable`, which type parameter `T` of `Max` requires|Implement `IComparable` on `Plain`, or relax the constraint on `Max`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := Max(new Plain(), new Plain())"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` that MOVES between the entry points — `2:13+1` plain, `2:13+4` through the four-argument route production actually calls; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.GenericConstraint_CircularSelf_Errors)" {
    source := "\n            func Identity<T>(value: T): T where T : T {\n                return value\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@2:13+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|Type parameter `T` of `Identity` has a circular constraint dependency|Remove the cycle in the `where` clauses of `Identity` — a type parameter cannot be constrained to itself, directly or through other type parameters.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@2:13+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|Type parameter `T` of `Identity` has a circular constraint dependency|Remove the cycle in the `where` clauses of `Identity` — a type parameter cannot be constrained to itself, directly or through other type parameters.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "            func Identity<T>(value: T): T where T : T {"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` that MOVES between the entry points — `2:13+1` plain, `2:13+4` through the four-argument route production actually calls; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.GenericConstraint_CircularMutual_Errors)" {
    source := "\n            func Pick<T, U>(a: T, b: U): T where T : U where U : T {\n                return a\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@2:13+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|Type parameter `T` of `Pick` has a circular constraint dependency|Remove the cycle in the `where` clauses of `Pick` — a type parameter cannot be constrained to itself, directly or through other type parameters.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@2:13+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|Type parameter `T` of `Pick` has a circular constraint dependency|Remove the cycle in the `where` clauses of `Pick` — a type parameter cannot be constrained to itself, directly or through other type parameters.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "            func Pick<T, U>(a: T, b: U): T where T : U where U : T {"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.GenericConstraint_FBounded_NoError)" {
    source := "\n            interface IComparable<T> {\n                func CompareTo(other: T): int\n            }\n            func Max<T>(a: T, b: T): T where T : IComparable<T> {\n                return a\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.GenericConstraint_TypeParamChain_NoError)" {
    source := "\n            func Pick<T, U>(a: T, b: U): T where T : U where U : class {\n                return a\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_Class_WithStringArg_NoError)" {
    source := "\n            func Identity<T>(value: T): T where T : class {\n                return value\n            }\n            func Main() {\n                result := Identity(\"hello\")\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` at `6:36+2`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.SpecialConstraint_Class_WithIntArg_Error)" {
    source := "\n            func Identity<T>(value: T): T where T : class {\n                return value\n            }\n            func Main() {\n                result := Identity(42)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@6:36+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|`int` is a value type, but type parameter `T` of `Identity` requires a reference type (the `class` constraint)|Pass a class instance for `T`, or relax the `class` constraint on `Identity`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@6:36+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|`int` is a value type, but type parameter `T` of `Identity` requires a reference type (the `class` constraint)|Pass a class instance for `T`, or relax the `class` constraint on `Identity`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := Identity(42)"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_Struct_WithIntArg_NoError)" {
    source := "\n            func Box<T>(value: T): T where T : struct {\n                return value\n            }\n            func Main() {\n                result := Box(42)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` that MOVES between the entry points — `6:31+1` plain, `6:31+7` through the four-argument route production actually calls; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.SpecialConstraint_Struct_WithStringArg_Error)" {
    source := "\n            func Box<T>(value: T): T where T : struct {\n                return value\n            }\n            func Main() {\n                result := Box(\"hello\")\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@6:31+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|`string` is not a non-nullable value type, but type parameter `T` of `Box` requires one (the `struct` constraint)|Pass a non-nullable value type for `T`, or relax the `struct` constraint on `Box`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@6:31+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|`string` is not a non-nullable value type, but type parameter `T` of `Box` requires one (the `struct` constraint)|Pass a non-nullable value type for `T`, or relax the `struct` constraint on `Box`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := Box(\"hello\")"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_New_WithDefaultCtorClass_NoError)" {
    source := "\n            class Widget {\n            }\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                w := new Widget()\n                result := Create(w)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_New_WithExplicitParameterlessCtorClass_NoError)" {
    source := "\n            class Widget {\n                constructor() {\n                }\n            }\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                w := new Widget()\n                result := Create<Widget>(w)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` at `11:42+1`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.SpecialConstraint_New_WithParameterizedCtorOnlyClass_Error)" {
    source := "\n            class Widget {\n                constructor(size: int) {\n                }\n            }\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                w := new Widget(1)\n                result := Create<Widget>(w)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@11:42+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|`Widget` has no parameterless constructor, but type parameter `T` of `Create` requires one (the `new()` constraint)|Give `Widget` a parameterless constructor, or relax the `new()` constraint on `Create`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@11:42+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|`Widget` has no parameterless constructor, but type parameter `T` of `Create` requires one (the `new()` constraint)|Give `Widget` a parameterless constructor, or relax the `new()` constraint on `Create`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := Create<Widget>(w)"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: THE PARSE IS NOT SILENT — 2 diagnostics (NL102 NL106), pinned whole in BOTH file-name spellings; and ONE `NL208:GenericConstraintViolation` at `8:41+1`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.SpecialConstraint_New_WithParameterizedCtorOnly_Error)" {
    source := "\n            record Point(X: int, Y: int)\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                p := new Point(1, 2)\n                result := Create<Point>(p)\n            }\n        "
    assert AcParseSuccess(source) == "False"
    assert AcParseCensus(source) == "NL102@3:13+4;NL106@2:20+5;"
    assert AcParseNamedSuccess(source) == "False"
    assert AcParseNamedCensus(source) == "NL102@3:13+4;NL106@2:20+5;"
    assert AcParseNamedRow(source, 0) == "ExpectedToken|Expected '{'. Expected '{', got 'func'|<null>|Error"
    assert AcParseNamedRow(source, 1) == "MissingClosingBrace|Missing closing '}'|<null>|Error"
    assert AcParseNamedRow(source, 2) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@8:41+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|`Point` has no parameterless constructor, but type parameter `T` of `Create` requires one (the `new()` constraint)|Give `Point` a parameterless constructor, or relax the `new()` constraint on `Create`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@8:41+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|`Point` has no parameterless constructor, but type parameter `T` of `Create` requires one (the `new()` constraint)|Give `Point` a parameterless constructor, or relax the `new()` constraint on `Create`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := Create<Point>(p)"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: THE PARSE IS NOT SILENT — 1 diagnostic (NL103), pinned whole in BOTH file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `ParseResult.Success == false` plus one parse message substring (was AnalyzerTests.SpecialConstraint_ClassAndStruct_MutuallyExclusive_ParseError)" {
    source := "\n            func Bad<T>(value: T): T where T : class, struct {\n                return value\n            }\n        "
    assert AcParseSuccess(source) == "False"
    assert AcParseCensus(source) == "NL103@2:55+6;"
    assert AcParseNamedSuccess(source) == "False"
    assert AcParseNamedCensus(source) == "NL103@2:55+6;"
    assert AcParseNamedRow(source, 0) == "InvalidSyntax|Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive|<null>|Error"
    assert AcParseNamedRow(source, 1) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_Class_WithInterface_WithStringArg_NoError)" {
    source := "\n            interface IComparable {\n                func CompareTo(other: object): int\n            }\n            class MyString : IComparable {\n                func CompareTo(other: object): int { return 0 }\n            }\n            func Process<T>(value: T): T where T : class, IComparable {\n                return value\n            }\n            func Main() {\n                ms := new MyString()\n                result := Process(ms)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_New_WithStructArg_NoError)" {
    source := "\n            struct Point {\n                X: int\n                Y: int\n            }\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                p := new Point()\n                result := Create(p)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: THE PARSE IS NOT SILENT — 2 diagnostics (NL102 NL106), pinned whole in BOTH file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; so the deleted `AssertNoErrors` was VACUOUS: it never saw the parse complain; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_Class_WithRecordArg_NoError)" {
    source := "\n            record Person(Name: string, Age: int)\n            func Process<T>(value: T): T where T : class {\n                return value\n            }\n            func Main() {\n                p := new Person(\"Alice\", 30)\n                result := Process(p)\n            }\n        "
    assert AcParseSuccess(source) == "False"
    assert AcParseCensus(source) == "NL102@3:13+4;NL106@2:20+6;"
    assert AcParseNamedSuccess(source) == "False"
    assert AcParseNamedCensus(source) == "NL102@3:13+4;NL106@2:20+6;"
    assert AcParseNamedRow(source, 0) == "ExpectedToken|Expected '{'. Expected '{', got 'func'|<null>|Error"
    assert AcParseNamedRow(source, 1) == "MissingClosingBrace|Missing closing '}'|<null>|Error"
    assert AcParseNamedRow(source, 2) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: THE PARSE IS NOT SILENT — 1 diagnostic (NL103), pinned whole in BOTH file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `ParseResult.Success == false` plus one parse message substring (was AnalyzerTests.SpecialConstraint_StructAndNew_MutuallyExclusive_ParseError)" {
    source := "\n            func Bad<T>(value: T): T where T : struct, new() {\n                return value\n            }\n        "
    assert AcParseSuccess(source) == "False"
    assert AcParseCensus(source) == "NL103@2:56+5;"
    assert AcParseNamedSuccess(source) == "False"
    assert AcParseNamedCensus(source) == "NL103@2:56+5;"
    assert AcParseNamedRow(source, 0) == "InvalidSyntax|Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor|<null>|Error"
    assert AcParseNamedRow(source, 1) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL208:GenericConstraintViolation` at `8:51+1`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.SpecialConstraint_New_WithPrimaryCtorClass_Error)" {
    source := "\n            class RequiresPrimary(X: int) { }\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                r := new RequiresPrimary(1)\n                result := Create<RequiresPrimary>(r)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL208:GenericConstraintViolation@8:51+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "GenericConstraintViolation|`RequiresPrimary` has no parameterless constructor, but type parameter `T` of `Create` requires one (the `new()` constraint)|Give `RequiresPrimary` a parameterless constructor, or relax the `new()` constraint on `Create`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL208:GenericConstraintViolation@8:51+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "GenericConstraintViolation|`RequiresPrimary` has no parameterless constructor, but type parameter `T` of `Create` requires one (the `new()` constraint)|Give `RequiresPrimary` a parameterless constructor, or relax the `new()` constraint on `Create`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := Create<RequiresPrimary>(r)"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: THE PARSE IS NOT SILENT — 2 diagnostics (NL102 NL106), pinned whole in BOTH file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; so the deleted `AssertNoErrors` was VACUOUS: it never saw the parse complain; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SpecialConstraint_New_WithRecordStructArg_NoError)" {
    source := "\n            record struct Size(Width: int, Height: int)\n            func Create<T>(dummy: T): T where T : new() {\n                return dummy\n            }\n            func Main() {\n                s := new Size(10, 20)\n                result := Create<Size>(s)\n            }\n        "
    assert AcParseSuccess(source) == "False"
    assert AcParseCensus(source) == "NL102@3:13+4;NL106@2:27+4;"
    assert AcParseNamedSuccess(source) == "False"
    assert AcParseNamedCensus(source) == "NL102@3:13+4;NL106@2:27+4;"
    assert AcParseNamedRow(source, 0) == "ExpectedToken|Expected '{'. Expected '{', got 'func'|<null>|Error"
    assert AcParseNamedRow(source, 1) == "MissingClosingBrace|Missing closing '}'|<null>|Error"
    assert AcParseNamedRow(source, 2) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

// ======== String-to-Enum Rejection — 8 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `7:17+1` plain, `7:28+5` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.StringToEnum_Rejected)" {
    source := "\n            enum Color {\n                Red = 0,\n                Blue = 1\n            }\n            func Main() {\n                c: Color = \"red\"\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'c' is typed as 'Color', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:28+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                c: Color = \"red\""
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `7:17+1` plain, `7:28+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.IntToEnum_Rejected)" {
    source := "\n            enum Color {\n                Red = 0,\n                Blue = 1\n            }\n            func Main() {\n                c: Color = 0\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'c' is typed as 'Color', but the value is 'int'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:28+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                c: Color = 0"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.EnumToString_Allowed)" {
    source := "\n            enum Color {\n                Red = 0,\n                Blue = 1\n            }\n            func Main() {\n                c := Color.Red\n                n: int = c\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.StringEnumToString_Allowed)" {
    source := "\n            enum Color {\n                Red = \"red\",\n                Blue = \"blue\"\n            }\n            func Main() {\n                c := Color.Red\n                s: string = c\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `7:17+1` plain, `7:28+5` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.StringToStringEnum_Rejected)" {
    source := "\n            enum Color {\n                Red = \"red\",\n                Blue = \"blue\"\n            }\n            func Main() {\n                c: Color = \"red\"\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'c' is typed as 'Color', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:28+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                c: Color = \"red\""
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.StringEnumAsParameterType_Allowed)" {
    source := "\n            enum Status: string {\n                Active = \"active\",\n                Inactive = \"inactive\"\n            }\n            func Process(s: Status): string {\n                return s\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.StringEnumAsReturnType_Allowed)" {
    source := "\n            enum Status: string {\n                Active = \"active\",\n                Inactive = \"inactive\"\n            }\n            func GetDefault(): Status {\n                return Status.Active\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.StringEnumAsRecordProperty_Allowed)" {
    source := "\n            enum Status: string {\n                Active = \"active\",\n                Inactive = \"inactive\"\n            }\n            record Item {\n                CurrentStatus: Status\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

// ======== UN-REGIONED — one method, taken by what its body NAMES — 1 contract ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.SetupSymbols_VisibleInTestBodies)" {
    source := "\n            setup {\n                count := 42\n            }\n\n            test \"should see setup variable\" {\n                assert count == 42\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

// ======== Overload Resolution — Betterness Rules — 6 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.OverloadResolution_IntBeatsLong_WithIntArg)" {
    source := "\n            func Foo(x: int): int { return x }\n            func Foo(x: long): long { return x }\n            func Main() {\n                r := Foo(42)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.OverloadResolution_IntBeatsObject_WithIntArg)" {
    source := "\n            func Foo(x: int): int { return x }\n            func Foo(x: object) { }\n            func Main() {\n                Foo(42)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.OverloadResolution_TwoParams_FirstExactWins)" {
    source := "\n            func Foo(x: int, y: int): int { return x }\n            func Foo(x: int, y: long): long { return x as long }\n            func Main() {\n                r := Foo(1, 2)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.OverloadResolution_NonParamsBeatsParams)" {
    source := "\n            func Foo(x: int): int { return x }\n            func Foo(params x: int[]): int { return 0 }\n            func Main() {\n                r := Foo(1)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.OverloadResolution_ImplicitNumeric_IntToLong_Works)" {
    source := "\n            func Process(x: long): long { return x }\n            func Main() {\n                r := Process(42)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.OverloadResolution_ImplicitNumeric_IntToDouble_Works)" {
    source := "\n            func Process(x: double): double { return x }\n            func Main() {\n                r := Process(42)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

// ======== Missing Diagnostics — Type System Edge Cases — 14 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` at `4:22+7`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.VoidUsedAsValue_Rejected)" {
    source := "\n            func DoStuff() { }\n            func Main() {\n                x := DoStuff()\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:22+7;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|This expression doesn't return a value (it's void) — you can't assign it to a variable|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:22+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|This expression doesn't return a value (it's void) — you can't assign it to a variable|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                x := DoStuff()"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL306:DuplicateDeclaration` at `2:30+1`, IDENTICAL on both analyzer entry points; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.DuplicateParameterNames_Rejected)" {
    source := "\n            func Dup(x: int, x: string): int {\n                return 0\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL306:DuplicateDeclaration@2:30+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DuplicateDeclaration|'x' is already declared in this scope — each name must be unique within the same scope|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL306:DuplicateDeclaration@2:30+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "DuplicateDeclaration|'x' is already declared in this scope — each name must be unique within the same scope|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "            func Dup(x: int, x: string): int {"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullAssignment_NullToInterfaceType)" {
    source := "\n            interface IFoo {\n                func Bar(): int\n            }\n            func Main() {\n                x: IFoo = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullAssignment_NullToArrayType)" {
    source := "\n            func Main() {\n                x: int[] = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `3:17+1` plain, `3:27+4` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.NullAssignment_NullToBool_Rejected)" {
    source := "\n            func Main() {\n                x: bool = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'x' is typed as 'bool', but the value is 'null'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:27+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                x: bool = null"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `3:17+1` plain, `3:29+4` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.NullAssignment_NullToDouble_Rejected)" {
    source := "\n            func Main() {\n                x: double = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'x' is typed as 'double', but the value is 'null'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:29+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                x: double = null"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullableWidening_IntNullableToLongNullable)" {
    source := "\n            func GetNullableInt(): int? { return null }\n            func Main() {\n                x: int? = GetNullableInt()\n                y: long? = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullableWidening_ByteNullableToIntNullable)" {
    source := "\n            func GetNullableByte(): byte? { return null }\n            func Main() {\n                x: byte? = GetNullableByte()\n                y: int? = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullableWidening_FloatNullableToDoubleNullable)" {
    source := "\n            func GetNullableFloat(): float? { return null }\n            func Main() {\n                x: float? = GetNullableFloat()\n                y: double? = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `5:17+1` plain, `5:27+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.NullableNarrowing_LongNullableToIntNullable_Rejected)" {
    source := "\n            func GetNullableLong(): long? { return null }\n            func Main() {\n                x: long? = GetNullableLong()\n                y: int? = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int?', but the value is 'long?'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@5:27+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                y: int? = x"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `7:17+1` plain, `7:28+4` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.NullAssignment_NullToRecordStruct_Rejected)" {
    source := "\n            record struct Point {\n                x: int = 0\n                y: int = 0\n            }\n            func Main() {\n                p: Point = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'p' is typed as 'Point', but the value is 'null'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:28+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                p: Point = null"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullAssignment_NullToRecord_Allowed)" {
    source := "\n            record Person {\n                name: string = \"unknown\"\n            }\n            func Main() {\n                p: Person = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `7:17+1` plain, `7:28+4` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one message substring (was AnalyzerTests.NullAssignment_NullToStruct_Rejected)" {
    source := "\n            struct Point {\n                x: int = 0\n                y: int = 0\n            }\n            func Main() {\n                p: Point = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'p' is typed as 'Point', but the value is 'null'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:28+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
    assert AcSnippet(rich, 0) == "                p: Point = null"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NullAssignment_NullToUnionType)" {
    source := "\n            union Shape {\n                Circle { radius: double }\n                Rectangle { width: double, height: double }\n            }\n            func Main() {\n                s: Shape = null\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

// ======== Impossible Pattern Errors — 11 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL506:ImpossiblePattern` that MOVES between the entry points — `4:29+2` plain, `4:29+9` through the four-argument route production actually calls; the deleted claim was one severity-filtered message substring (was AnalyzerTests.ImpossiblePattern_IntIsString_ProducesError)" {
    source := "\n            func Main() {\n                x: int = 42\n                result := x is string\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL506:ImpossiblePattern@4:29+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ImpossiblePattern|This 'is string' check is always false — a 'int' is never a 'string'|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL506:ImpossiblePattern@4:29+9;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ImpossiblePattern|This 'is string' check is always false — a 'int' is never a 'string'|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := x is string"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL506:ImpossiblePattern` that MOVES between the entry points — `4:32+2` plain, `4:32+6` through the four-argument route production actually calls; the deleted claim was one severity-filtered message substring (was AnalyzerTests.ImpossiblePattern_BoolIsInt_ProducesError)" {
    source := "\n            func Main() {\n                flag: bool = true\n                result := flag is int\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL506:ImpossiblePattern@4:32+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ImpossiblePattern|This 'is int' check is always false — a 'bool' is never a 'int'|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL506:ImpossiblePattern@4:32+6;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ImpossiblePattern|This 'is int' check is always false — a 'bool' is never a 'int'|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := flag is int"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was that no message carries one substring (was AnalyzerTests.ImpossiblePattern_IntIsInt_NoWarning)" {
    source := "\n            func Main() {\n                x: int = 42\n                result := x is int\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was that no message carries one substring (was AnalyzerTests.ImpossiblePattern_ClassIsInterface_NoWarning)" {
    source := "\n            interface IShape {\n                func Area(): double\n            }\n            class Circle {\n                Radius: double\n                func Area(): double { return 3.14 * Radius * Radius }\n            }\n            func Main() {\n                c: Circle = new Circle { Radius: 1.0 }\n                result := c is IShape\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was that no message carries one substring (was AnalyzerTests.ImpossiblePattern_BaseClassIsDerived_NoWarning)" {
    source := "\n            class Animal {\n                Name: string\n            }\n            class Dog : Animal {\n                Breed: string\n            }\n            func Main() {\n                a: Animal = new Dog { Name: \"Rex\", Breed: \"Lab\" }\n                result := a is Dog\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL506:ImpossiblePattern` that MOVES between the entry points — `10:29+2` plain, `10:29+6` through the four-argument route production actually calls; the deleted claim was one severity-filtered message substring (was AnalyzerTests.ImpossiblePattern_SealedClassUnrelated_ProducesError)" {
    source := "\n            sealed class Cat {\n                Name: string\n            }\n            class Dog {\n                Name: string\n            }\n            func Main() {\n                c: Cat = new Cat { Name: \"Whiskers\" }\n                result := c is Dog\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL506:ImpossiblePattern@10:29+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ImpossiblePattern|This 'is Dog' check is always false — a 'Cat' is never a 'Dog'|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL506:ImpossiblePattern@10:29+6;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ImpossiblePattern|This 'is Dog' check is always false — a 'Cat' is never a 'Dog'|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := c is Dog"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was that no message carries one substring (was AnalyzerTests.ImpossiblePattern_ObjectIsString_NoWarning)" {
    source := "\n            func Main() {\n                obj: object = \"hello\"\n                result := obj is string\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was that no message carries one substring (was AnalyzerTests.ImpossiblePattern_UnionTypeIsCase_NoWarning)" {
    source := "\n            union Shape {\n                Circle { radius: double }\n                Rectangle { width: double, height: double }\n            }\n            func Main() {\n                s: Shape = new Shape.Circle { radius: 1.0 }\n                x := match s {\n                    Shape.Circle { radius } => radius,\n                    _ => 0.0\n                }\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL506:ImpossiblePattern` that MOVES between the entry points — `4:22+2` plain, `4:22+9` through the four-argument route production actually calls; the deleted claim was one severity-filtered message substring (was AnalyzerTests.ImpossiblePattern_IsExpression_IntIsString_ProducesError)" {
    source := "\n            func Main() {\n                n: int = 42\n                if n is string s {\n                    len: int = s.Length\n                }\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL506:ImpossiblePattern@4:22+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ImpossiblePattern|This 'is string' check is always false — a 'int' is never a 'string'|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL506:ImpossiblePattern@4:22+9;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ImpossiblePattern|This 'is string' check is always false — a 'int' is never a 'string'|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                if n is string s {"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was that no message carries one substring (was AnalyzerTests.ImpossiblePattern_IsExpression_ObjectIsString_NoWarning)" {
    source := "\n            func Main() {\n                obj: object = \"hello\"\n                if obj is string s {\n                    len: int = s.Length\n                }\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL506:ImpossiblePattern` that MOVES between the entry points — `4:29+2` plain, `4:29+9` through the four-argument route production actually calls; the deleted claim was one severity-filtered message substring (was AnalyzerTests.ImpossiblePattern_IsExpression_IntIsDouble_Error)" {
    source := "\n            func Main() {\n                x: int = 5\n                result := x is double\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL506:ImpossiblePattern@4:29+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ImpossiblePattern|This 'is double' check is always false — a 'int' is never a 'double'|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL506:ImpossiblePattern@4:29+9;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ImpossiblePattern|This 'is double' check is always false — a 'int' is never a 'double'|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "                result := x is double"
    assert AcRow(rich, 1) == "<no-such-error>"
}

// ======== Numeric Narrowing Cast Suggestions — 8 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `5:17+1` plain, `5:26+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one non-null `ContextualHint` substring (was AnalyzerTests.NarrowingSuggestion_LongToInt_SuggestsCast)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: int = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int', but the value is 'long'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@5:26+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "Cannot implicitly convert 'long' to 'int'. Use an explicit cast: (int)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
    assert AcSnippet(rich, 0) == "                y: int = x"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `4:17+1` plain, `4:28+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one non-null `ContextualHint` substring (was AnalyzerTests.NarrowingSuggestion_DoubleToFloat_SuggestsCast)" {
    source := "\n            func Main() {\n                x: double = 3.14\n                y: float = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'float', but the value is 'double'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:28+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "Cannot implicitly convert 'double' to 'float'. Use an explicit cast: (float)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
    assert AcSnippet(rich, 0) == "                y: float = x"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` at `6:21+1` on both entry points, but the four-argument route rewrites the MESSAGE; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one non-null `ContextualHint` substring (was AnalyzerTests.NarrowingSuggestion_FunctionArgument_LongToInt_SuggestsCast)" {
    source := "\n            func Foo(x: int) {}\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                v: long = GetLong()\n                Foo(v)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@6:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Argument 1 to 'Foo' is 'long', but parameter 'x' expects 'int'|Pass a value with the expected type, or update the function signature.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@6:21+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Cannot pass `long` as argument for parameter `x` of type `int`|<null>|Error"
    assert AcHint(rich, 0) == "Cannot implicitly convert 'long' to 'int'. Use an explicit cast: (int)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
    assert AcSnippet(rich, 0) == "                Foo(v)"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `5:17+1` plain, `5:24+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one non-null `ContextualHint` substring (was AnalyzerTests.NarrowingSuggestion_ReturnDoubleFromIntFunc_SuggestsCast)" {
    source := "\n            func GetDouble(): double { return 0.0 }\n            func Compute(): int {\n                d: double = GetDouble()\n                return d\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Function 'Compute' should return 'int', but this return statement gives back 'double'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@5:24+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Function 'Compute' should return int but returns double|<null>|Error"
    assert AcHint(rich, 0) == "Cannot implicitly convert 'double' to 'int'. Use an explicit cast: (int)value\nWarning: This truncates decimals (e.g. 3.7 becomes 3) and may lose data if the value exceeds the target type's range."
    assert AcSnippet(rich, 0) == "                return d"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `4:17+1` plain, `4:27+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one non-null `ContextualHint` substring (was AnalyzerTests.NarrowingSuggestion_IntToByte_LiteralTooLarge_SuggestsCast)" {
    source := "\n            func Main() {\n                x: int = 300\n                y: byte = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'byte', but the value is 'int'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:27+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "Cannot implicitly convert 'int' to 'byte'. Use an explicit cast: (byte)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
    assert AcSnippet(rich, 0) == "                y: byte = x"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.NarrowingSuggestion_IntToInt_NoError)" {
    source := "\n            func Main() {\n                x: int = 42\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `4:17+1` plain, `4:26+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted body drove `Analyze(unit, path, root, source)` directly (was AnalyzerTests.NarrowingSuggestion_StringToInt_NotNumericNarrowing)" {
    source := "\n            func Main() {\n                x: string = \"hello\"\n                y: int = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:26+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert AcSnippet(rich, 0) == "                y: int = x"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL202:TypeMismatch` that MOVES between the entry points — `5:17+1` plain, `5:28+1` through the four-argument route production actually calls; the `ContextualHint` is `<null>` plain and NON-NULL rich; the deleted claim was `HasErrors == true` plus one non-null `ContextualHint` substring (was AnalyzerTests.NarrowingSuggestion_LongToShort_SuggestsCast)" {
    source := "\n            func GetLong(): long { return 0 as long }\n            func Main() {\n                x: long = GetLong()\n                y: short = x\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Variable 'y' is typed as 'short', but the value is 'long'|Ensure types are compatible or add explicit cast|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@5:28+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcHint(rich, 0) == "Cannot implicitly convert 'long' to 'short'. Use an explicit cast: (short)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
    assert AcSnippet(rich, 0) == "                y: short = x"
    assert AcRow(rich, 1) == "<no-such-error>"
}

// ======== Default Expression — 13 contracts ========

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_IntVariable_NoErrors)" {
    source := "\n            func Main() {\n                x: int = default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_StringVariable_NoErrors)" {
    source := "\n            func Main() {\n                s: string = default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_ReturnFromIntFunction_NoErrors)" {
    source := "\n            func Foo(): int {\n                return default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL203:CannotInferType` at `2:10+7`, IDENTICAL on both analyzer entry points; the deleted body drove `Analyze(unit)` directly (was AnalyzerTests.DefaultExpression_NoTypeContext_ReportsError)" {
    source := "func Main() {\n    x := default\n}"
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL203:CannotInferType@2:10+7;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "CannotInferType|I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')|Add explicit type annotation: 'let x: Type = ...'|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL203:CannotInferType@2:10+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "CannotInferType|I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')|Add explicit type annotation: 'let x: Type = ...'|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "    x := default"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL203:CannotInferType` at `2:10+3`, IDENTICAL on both analyzer entry points; the deleted body drove `Analyze(unit)` directly (was AnalyzerTests.TargetTypedNew_NoTypeContext_ReportsError)" {
    source := "func Main() {\n    x := new()\n}"
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL203:CannotInferType@2:10+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "CannotInferType|I can't figure out what type 'new()' should create here — add a type annotation or write the type after 'new'|For example, use `value: Person = new()` when the target type is clear, or `new Person()` when it is not.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL203:CannotInferType@2:10+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "CannotInferType|I can't figure out what type 'new()' should create here — add a type annotation or write the type after 'new'|For example, use `value: Person = new()` when the target type is clear, or `new Person()` when it is not.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "    x := new()"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and ONE `NL203:CannotInferType` at `2:5+3`, IDENTICAL on both analyzer entry points; the deleted body drove `Analyze(unit)` directly (was AnalyzerTests.TargetTypedNew_ExpressionStatementNoTypeContext_ReportsError)" {
    source := "func Main() {\n    new()\n}"
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL203:CannotInferType@2:5+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "CannotInferType|I can't figure out what type 'new()' should create here — add a type annotation or write the type after 'new'|For example, use `value: Person = new()` when the target type is clear, or `new Person()` when it is not.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSnippet(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL203:CannotInferType@2:5+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "CannotInferType|I can't figure out what type 'new()' should create here — add a type annotation or write the type after 'new'|For example, use `value: Person = new()` when the target type is clear, or `new Person()` when it is not.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSnippet(rich, 0) == "    new()"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.AnonymousObjectCreation_NoTypeContext_IsAllowed)" {
    source := "func Main() {\n    value := new { Name: \"Ada\", Count: 1 }\n}"
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_FunctionArgument_NoErrors)" {
    source := "\n            func Bar(x: int) {}\n            func Main() {\n                Bar(default)\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_NullableIntVariable_NoErrors)" {
    source := "\n            func Main() {\n                x: int? = default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_BoolVariable_NoErrors)" {
    source := "\n            func Main() {\n                x: bool = default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_DoubleVariable_NoErrors)" {
    source := "\n            func Main() {\n                x: double = default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_ReturnFromBoolFunction_NoErrors)" {
    source := "\n            func IsReady(): bool {\n                return default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}

test "020 s29 analyzer clean source: the parse is SILENT in both file-name spellings; and BOTH analyzer entry points are SILENT — empty censuses, zero errors, `<no-such-error>` at index 0; the deleted claim was `HasErrors == false` and nothing else (was AnalyzerTests.DefaultExpression_FieldInitializer_NoErrors)" {
    source := "\n            class Counter {\n                count: int = default\n            }\n        "
    assert AcParseSuccess(source) == "True"
    assert AcParseCensus(source) == ""
    assert AcParseNamedSuccess(source) == "True"
    assert AcParseNamedCensus(source) == ""
    assert AcParseNamedRow(source, 0) == "<no-such-error>"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
}


// ======================================================================================
// TRANCHE 2 — THE ERROR-CODE ASSERTION FAMILY (task 020 slice 30)
// ======================================================================================
//
// These 106 declarations replace 106 methods and 1,743 lines of `tests/AnalyzerTests.cs`: every
// method that named `AssertHasErrorCode` or `AssertNoErrorCode` (88 — 53 / 33 / 2 that name both),
// plus the 18 direct-`Analyze` shape neighbours interleaved among their deletion runs from line
// 9460 to the end of the file. **BOTH HELPERS DIE WITH THIS TRANCHE**: measured file-wide,
// `AssertHasErrorCode` occurred 57 times (56 calls + its declaration) and `AssertNoErrorCode` 36
// (35 + its declaration), and every call site was inside it.
//
// WHY THE BOUNDARY IS THIS AND NOT THE WHOLE `Analyze`+`ErrorCode` SHAPE. That shape is 42 methods
// over 569 declaration lines and would carry the tranche to 1,868 — over budget. Line 9460 is the
// first at which the two shapes SHARE a deletion run; taking the neighbours from there collapses
// ten runs into eight and migrates the unresolved-type / generic-arity subject and the WHOLE NL319
// subject rather than splitting them.
//
// THE ONE MISSING KERNEL. `AssertHasErrorCode` selects `e.Code == code && e.Severity ==
// ErrorSeverity.Error`, asserts the match is non-null and RETURNS it; `AssertNoErrorCode` asserts
// the same predicate matches nothing. `AcCodeMatchIndex` and the four functions over it are that
// shape, and they are pinned on every fixture beside slice 28's severity-blind `AcCodeCount`.
//
// SEVEN THINGS THE 199 DELETED CLAIMS COULD NOT SEE, EVERY ONE MEASURED:
//
//   (a) THE SEVERITY HALF OF BOTH HELPERS IS DEAD OVER THIS CORPUS. All 82 diagnostics the 111
//       fixtures produce are `Error`; `AcCodeCount` and `AcCodeErrorCount` agree on every fixture
//       and every code, 0 disagreements. The predicate that reads `&& e.Severity ==
//       ErrorSeverity.Error` never once discriminated anything. Both are pinned, so the day one of
//       these codes starts arriving as a Warning, the pair separates.
//
//   (b) `AssertNoErrorCode` WAS ALMOST ALWAYS A VACUOUS "NOTHING AT ALL". 34 of its 35 fixtures
//       analyse COMPLETELY SILENT: the assertion said "this one code is absent" where the truth was
//       "every code is absent". Each of the 34 now pins an EMPTY census, an error COUNT of zero and
//       `<no-such-error>` at index 0.
//
//   (c) AND THE ONE THAT IS NOT SILENT IS A FALSE CLEAN. `EnumValueObjectMemberAccess_Resolves` —
//       the name says it resolves — reports `NL202:TypeMismatch@10:17+1`. The deleted assertion
//       asked only about `UndefinedMember`, so it passed. Pinned here as the diagnostic it is.
//
//   (d) TWO FIXTURES DO NOT PARSE, AND ONE OF THEM PROVED NOTHING AT ALL.
//       `BreakInsideSwitchInsideFinally_NoDiagnostic` spells a C# `switch`/`case` statement; the
//       parse reports `NL102` at 11:23 with `Success == False` and the ANALYSIS REPORTS NOTHING, so
//       the deleted `AssertNoErrorCode(ControlTransferOutOfFinally)` was satisfied by a file that
//       never reached the walk. `Lock_OnEnumValue_ReportsNL320` spells an enum whose members are
//       newline-separated rather than comma-separated; that reports `NL101` twice, and its NL320
//       claim SURVIVES — but the analysis reports FOUR rows, two of them `NL903` complaining about
//       an identifier literally named `<error>`, a recovery artefact leaking a synthetic name into
//       a user-facing sentence. Both parse censuses are pinned WHOLE.
//
//   (e) A CODE NAMED `VisibilityConventionWarning` IS REPORTED AT `Error` SEVERITY, TWICE — the
//       same shape slice 28 found in `NullabilityWarning`, in a second code.
//
//   (f) THE TWO ENTRY POINTS DISAGREE ON 28 OF THE PINNED ROWS, AND THE PRODUCTION ONE IS WORSE.
//       Slice 29 measured this over its own corpus; this tranche measures it over a disjoint one
//       and the direction is the same. The census differs on 16 fixtures, the code row on 28 and
//       the code anchor on 13; the error COUNT never differs. On the 28, production DROPS the
//       suggestion 15 times and GAINS one ZERO times. **THREE DELETED ASSERTIONS ARE TRUE ONLY OF
//       THE ENTRY POINT NOTHING SHIPS**: the `'Items' is typed as 'List<Pt>', but the value is
//       'List<Rs>'` sentence and its two siblings become the bare `Type mismatch` on the route
//       `nlc check`, `nlc build` and the IDE take. Both routes are pinned on every fixture.
//
//   (g) THE PLURAL `Suggestions` LIST IS A PRODUCTION-ONLY FIELD. It is null on all 82 plain rows
//       and non-null on 5 rich ones, so the `?? string.Join(", ", error.Suggestions ?? …)` fallback
//       the deleted code carried is unreachable on the route the deleted code used. 37 of the 82
//       rich rows also carry a `ContextualHint` that the plain route leaves null.
//
// THE ANCHOR AUDIT — ALL 82 POSITIONS READ BACK OUT OF THE FIXTURE TEXT. `NL319` underlines the
// whole KEYWORD (`return`×6, `break`, `continue`); `NL201` the whole type name
// (`MissingExternalType`×5); `NL303` the whole misspelled member, including the dotted
// `Result.Sucess`; `NL316` the declared name; `NL207` the generic HEAD (`Box`×3, `List`, `Task`,
// `Action`) except where the head is built-in or a type parameter, where it moves to the ARGUMENT;
// `NL322` the indexer `[`. **`NL202` TRUNCATES on the plain route** — a bare `"` where the value is
// a string literal, four times, and single letters elsewhere — which is exactly what the production
// route repairs.
//
// THE TABLE. `GenericTypes_StaticMembers_ReportBeforeEmission` is the FIRST of `AnalyzerTests.cs`'s
// 35 `[Theory]`s to leave the file, and it is a table here rather than three declarations because
// BOTH its fixture and its message claim are interpolated per row. Every one of its four C#
// parameters is load-bearing in the N# body. **AND THE PER-ROW PIN IMMEDIATELY FOUND A DEFECT THE
// C# COULD NOT**: the three rows do not anchor alike. `field count` underlines `count` and
// `property value` underlines `value`, but `method mk` underlines **`fu`** — column 12, length 2:
// the column of the `func` keyword with the LENGTH of the member name. A single collapsed
// assertion could not have said so; three separate `codeAnchor` values do.
//
// The fixtures are the deleted ones byte-for-byte: every literal was copied unmodified into a
// generated console program that printed its sha256 and length, and the decoder that produced the
// strings below reproduces all 111 shas and all 111 lengths with zero mismatches. All 111 are
// distinct.

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the whole census is pinned (1 row); the deleted claim was that `ShadowedDeclaration` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ScopeNesting_NestedRedeclarationShadowsOuter_IsError)" {
    source := "\n            func Main() {\n                x := 1\n                {\n                    x := 2\n                    print x\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL316:ShadowedDeclaration@5:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ShadowedDeclaration|'x' shadows an existing 'x' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'x' is still in scope), or remove it and reuse the existing 'x'|Error"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "ShadowedDeclaration|'x' shadows an existing 'x' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'x' is still in scope), or remove it and reuse the existing 'x'|Error"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "NL316@5:21+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL316:ShadowedDeclaration@5:21+1;"
    assert AcCodeRow(rich, "ShadowedDeclaration") == "ShadowedDeclaration|'x' shadows an existing 'x' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'x' is still in scope), or remove it and reuse the existing 'x'|Error"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "NL316@5:21+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `UndefinedMember`: the whole census is pinned (1 row); the deleted claim was that `UndefinedMember` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.EnumMemberAccess_UnknownStaticMember_ReportsUndefinedMember)" {
    source := "\n            enum Status {\n                Pending,\n                Active,\n                Done\n            }\n\n            func Main(): Status {\n                return Status.Activ\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL303:UndefinedMember@9:31+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedMember|Member 'Activ' not found on type 'Status'|Did you mean 'Active'?|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 1
    assert AcCodeCount(analysis, "UndefinedMember") == 1
    assert AcCodeRow(analysis, "UndefinedMember") == "UndefinedMember|Member 'Activ' not found on type 'Status'|Did you mean 'Active'?|Error"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "NL303@9:31+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL303:UndefinedMember@9:31+5;"
    assert AcCodeRow(rich, "UndefinedMember") == "UndefinedMember|Member 'Activ' not found on type 'Status'|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedMember") == "NL303@9:31+5"
    assert AcSuggestions(rich, 0) == "Active"
    assert AcHint(rich, 0) == "The type `Status` does not have a member named `Activ`.\nCheck for typos, or make sure you're accessing the right type."
}

test "020 s30 analyzer error codes: THE TRANCHE'S ONE FALSE CLEAN — the method name says it RESOLVES and the deleted `AssertNoErrorCode(UndefinedMember)` passed, but the analysis reports `NL202:TypeMismatch@10:17+1`; it is the only one of the 35 absence claims whose fixture is not completely silent (was AnalyzerTests.EnumValueObjectMemberAccess_Resolves)" {
    source := "\n            enum Status {\n                Pending,\n                Active,\n                Done\n            }\n\n            func Main(): string {\n                status := Status.Active\n                return status.ToString()\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@10:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Function 'Main' should return 'string', but this return statement gives back 'string?'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 0
    assert AcCodeCount(analysis, "UndefinedMember") == 0
    assert AcCodeRow(analysis, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@10:31+8;"
    assert AcCodeRow(rich, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(rich, "UndefinedMember") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `UndefinedMember`: the whole census is pinned (1 row); the deleted claim was that `UndefinedMember` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.EnumValueMemberAccess_EnumMemberName_ReportsUndefinedMember)" {
    source := "\n            enum Status {\n                Pending,\n                Active,\n                Done\n            }\n\n            func Main(): Status {\n                status := Status.Active\n                return status.Done\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL303:UndefinedMember@10:31+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedMember|Member 'Done' not found on type 'Status'|Did you mean 'Done'?|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 1
    assert AcCodeCount(analysis, "UndefinedMember") == 1
    assert AcCodeRow(analysis, "UndefinedMember") == "UndefinedMember|Member 'Done' not found on type 'Status'|Did you mean 'Done'?|Error"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "NL303@10:31+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL303:UndefinedMember@10:31+4;"
    assert AcCodeRow(rich, "UndefinedMember") == "UndefinedMember|Member 'Done' not found on type 'Status'|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedMember") == "NL303@10:31+4"
    assert AcSuggestions(rich, 0) == "Done"
    assert AcHint(rich, 0) == "The type `Status` does not have a member named `Done`.\nCheck for typos, or make sure you're accessing the right type."
}

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the whole census is pinned (1 row); the deleted claim was that `ShadowedDeclaration` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Shadowing_InnerBlockLocalShadowingOuterLocal_IsError)" {
    source := "\nfunc Main() {\n    count := 1\n    if count > 0 {\n        count := 2\n        print count\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL316:ShadowedDeclaration@5:9+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ShadowedDeclaration|'count' shadows an existing 'count' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'count' is still in scope), or remove it and reuse the existing 'count'|Error"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "ShadowedDeclaration|'count' shadows an existing 'count' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'count' is still in scope), or remove it and reuse the existing 'count'|Error"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "NL316@5:9+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL316:ShadowedDeclaration@5:9+5;"
    assert AcCodeRow(rich, "ShadowedDeclaration") == "ShadowedDeclaration|'count' shadows an existing 'count' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'count' is still in scope), or remove it and reuse the existing 'count'|Error"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "NL316@5:9+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the whole census is pinned (1 row); the deleted claim was that `ShadowedDeclaration` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Shadowing_LocalShadowingParameter_IsError)" {
    source := "\nfunc Greet(name: string) {\n    name := \"override\"\n    print name\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL316:ShadowedDeclaration@3:5+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ShadowedDeclaration|'name' shadows an existing 'name' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'name' is still in scope), or remove it and reuse the existing 'name'|Error"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "ShadowedDeclaration|'name' shadows an existing 'name' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'name' is still in scope), or remove it and reuse the existing 'name'|Error"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "NL316@3:5+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL316:ShadowedDeclaration@3:5+4;"
    assert AcCodeRow(rich, "ShadowedDeclaration") == "ShadowedDeclaration|'name' shadows an existing 'name' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'name' is still in scope), or remove it and reuse the existing 'name'|Error"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "NL316@3:5+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the whole census is pinned (1 row); the deleted claim was that `ShadowedDeclaration` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Shadowing_NestedFunctionBlockShadowingOuter_IsError)" {
    source := "\nfunc Outer() {\n    sum := 1\n    for i := 0; i < 3; i = i + 1 {\n        sum := i\n        print sum\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL316:ShadowedDeclaration@5:9+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ShadowedDeclaration|'sum' shadows an existing 'sum' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'sum' is still in scope), or remove it and reuse the existing 'sum'|Error"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 1
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "ShadowedDeclaration|'sum' shadows an existing 'sum' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'sum' is still in scope), or remove it and reuse the existing 'sum'|Error"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "NL316@5:9+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL316:ShadowedDeclaration@5:9+3;"
    assert AcCodeRow(rich, "ShadowedDeclaration") == "ShadowedDeclaration|'sum' shadows an existing 'sum' from an enclosing scope — N# forbids shadowing because it hides the outer binding and invites confusing bugs|Rename this declaration (the outer 'sum' is still in scope), or remove it and reuse the existing 'sum'|Error"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "NL316@5:9+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ShadowedDeclaration` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Shadowing_SiblingBlocksReusingName_IsAllowed)" {
    source := "\nfunc Main() {\n    if true {\n        temp := 1\n        print temp\n    }\n    if false {\n        temp := 2\n        print temp\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 0
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 0
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ShadowedDeclaration") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ShadowedDeclaration` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Shadowing_LocalShadowingClassField_IsAllowed)" {
    source := "\nclass Counter {\n    count: int = 0\n\n    func Increment() {\n        count := 1\n        print count\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 0
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 0
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ShadowedDeclaration") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ShadowedDeclaration`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ShadowedDeclaration` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Shadowing_DiscardAndUnderscoreNames_AreAllowed)" {
    source := "\nfunc Main() {\n    _temp := 1\n    if true {\n        _temp := 2\n        print _temp\n    }\n    print _temp\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ShadowedDeclaration") == 0
    assert AcCodeCount(analysis, "ShadowedDeclaration") == 0
    assert AcCodeRow(analysis, "ShadowedDeclaration") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ShadowedDeclaration") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ShadowedDeclaration") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ShadowedDeclaration") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the whole census is pinned (1 row); the deleted claim was that `DefiniteAssignmentError` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.DefiniteAssignment_ReadAfterConditionalAssignment_IsError)" {
    source := "\nfunc Cond(): bool {\n    return true\n}\n\nfunc Main() {\n    let total: int\n    if Cond() {\n        total = 5\n    }\n    print total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL304:DefiniteAssignmentError@11:11+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DefiniteAssignmentError|'total' is used here before it has been assigned a value on every path that reaches this point|Give 'total' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "DefiniteAssignmentError|'total' is used here before it has been assigned a value on every path that reaches this point|Give 'total' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "NL304@11:11+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL304:DefiniteAssignmentError@11:11+5;"
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "DefiniteAssignmentError|'total' is used here before it has been assigned a value on every path that reaches this point|Give 'total' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "NL304@11:11+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the whole census is pinned (1 row); the deleted claim was that `DefiniteAssignmentError` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.DefiniteAssignment_ReadBeforeAnyAssignment_IsError)" {
    source := "\nfunc Main() {\n    let value: int\n    print value\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL304:DefiniteAssignmentError@4:11+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DefiniteAssignmentError|'value' is used here before it has been assigned a value on every path that reaches this point|Give 'value' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "DefiniteAssignmentError|'value' is used here before it has been assigned a value on every path that reaches this point|Give 'value' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "NL304@4:11+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL304:DefiniteAssignmentError@4:11+5;"
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "DefiniteAssignmentError|'value' is used here before it has been assigned a value on every path that reaches this point|Give 'value' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "NL304@4:11+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `DefiniteAssignmentError` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.DefiniteAssignment_AssignedOnAllBranches_IsAllowed)" {
    source := "\nfunc Cond(): bool {\n    return true\n}\n\nfunc Main() {\n    let total: int\n    if Cond() {\n        total = 5\n    } else {\n        total = 0\n    }\n    print total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `DefiniteAssignmentError` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.DefiniteAssignment_AssignedBeforeUse_IsAllowed)" {
    source := "\nfunc Main() {\n    let total: int\n    total = 42\n    print total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `DefiniteAssignmentError` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.DefiniteAssignment_InitializedAtDeclaration_IsAllowed)" {
    source := "\nfunc Main() {\n    total := 0\n    print total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `DefiniteAssignmentError` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.DefiniteAssignment_EarlyReturnGuardsUnassignedPath_IsAllowed)" {
    source := "\nfunc Cond(): bool {\n    return true\n}\n\nfunc Main() {\n    let total: int\n    if Cond() {\n        total = 5\n    } else {\n        return\n    }\n    print total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the whole census is pinned (1 row); the deleted claim was that `DefiniteAssignmentError` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.DefiniteAssignment_ArrayLengthUse_ReadBeforeAnyAssignment_IsError)" {
    source := "\nfunc Main() {\n    let n: int\n    let arr = new int[n]\n    print arr.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL304:DefiniteAssignmentError@4:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DefiniteAssignmentError|'n' is used here before it has been assigned a value on every path that reaches this point|Give 'n' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "DefiniteAssignmentError|'n' is used here before it has been assigned a value on every path that reaches this point|Give 'n' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "NL304@4:23+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL304:DefiniteAssignmentError@4:23+1;"
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "DefiniteAssignmentError|'n' is used here before it has been assigned a value on every path that reaches this point|Give 'n' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "NL304@4:23+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the whole census is pinned (1 row); the deleted claim was that `DefiniteAssignmentError` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.DefiniteAssignment_ArrayLengthUse_ConditionallyAssigned_IsError)" {
    source := "\nfunc Cond(): bool {\n    return true\n}\n\nfunc Main() {\n    let n: int\n    if Cond() {\n        n = 5\n    }\n    let arr = new int[n]\n    print arr.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL304:DefiniteAssignmentError@11:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DefiniteAssignmentError|'n' is used here before it has been assigned a value on every path that reaches this point|Give 'n' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 1
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "DefiniteAssignmentError|'n' is used here before it has been assigned a value on every path that reaches this point|Give 'n' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "NL304@11:23+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL304:DefiniteAssignmentError@11:23+1;"
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "DefiniteAssignmentError|'n' is used here before it has been assigned a value on every path that reaches this point|Give 'n' an initial value where you declare it, or assign it on every branch before this use.|Error"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "NL304@11:23+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `DefiniteAssignmentError`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `DefiniteAssignmentError` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.DefiniteAssignment_ArrayLengthUse_AssignedOnAllBranches_IsAllowed)" {
    source := "\nfunc Cond(): bool {\n    return true\n}\n\nfunc Main() {\n    let n: int\n    if Cond() {\n        n = 5\n    } else {\n        n = 6\n    }\n    let arr = new int[n]\n    print arr.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeCount(analysis, "DefiniteAssignmentError") == 0
    assert AcCodeRow(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "DefiniteAssignmentError") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "DefiniteAssignmentError") == "<no-such-code>"
    assert AcCodeAnchor(rich, "DefiniteAssignmentError") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `UndefinedVariable`: the whole census is pinned (1 row); the deleted claim was that `UndefinedVariable` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_UndefinedLengthName_ReportsUndefinedVariable)" {
    source := "\nfunc Scratch(): int {\n    scratch := stackalloc byte[undefinedName]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL301:UndefinedVariable@3:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedVariable|I can't find 'undefinedName' — it hasn't been declared in this scope|<null>|Error"
    assert AcCodeErrorCount(analysis, "UndefinedVariable") == 1
    assert AcCodeCount(analysis, "UndefinedVariable") == 1
    assert AcCodeRow(analysis, "UndefinedVariable") == "UndefinedVariable|I can't find 'undefinedName' — it hasn't been declared in this scope|<null>|Error"
    assert AcCodeAnchor(analysis, "UndefinedVariable") == "NL301@3:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL301:UndefinedVariable@3:32+13;"
    assert AcCodeRow(rich, "UndefinedVariable") == "UndefinedVariable|Variable 'undefinedName' not found|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedVariable") == "NL301@3:32+13"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Make sure you've declared this variable before using it."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_StringLength_ReportsTypeMismatch)" {
    source := "\nfunc Scratch(name: string): int {\n    scratch := stackalloc byte[name]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|stackalloc length must be an int, but this is a 'string'|Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|stackalloc length must be an int, but this is a 'string'|Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:32+4;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|stackalloc length must be an int, but this is a 'string'|Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:32+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_LongLength_ReportsTypeMismatch)" {
    source := "\nfunc Scratch(count: long): int {\n    scratch := stackalloc byte[count]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|stackalloc length must be an int, but this is a 'long'|Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|stackalloc length must be an int, but this is a 'long'|Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:32+5;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|stackalloc length must be an int, but this is a 'long'|Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:32+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_NegativeConstantLength_Rejected)" {
    source := "\nfunc Scratch(): int {\n    scratch := stackalloc byte[-1]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:32+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:32+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_CastedNegativeConstantLength_Rejected)" {
    source := "\nfunc Scratch(): int {\n    scratch := stackalloc byte[checked((int)-1)]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:32+7;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:32+7"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_ParenthesizedNegativeConstantOperand_Rejected)" {
    source := "\nfunc Scratch(): int {\n    scratch := stackalloc byte[unchecked(-(1))]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:32+9;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:32+9"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.StackAlloc_AliasedSignedCastNegativeConstantLength_Rejected)" {
    source := "\ntype Count = short\n\nfunc Scratch(): int {\n    scratch := stackalloc byte[(Count)-1]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@5:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@5:32+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|stackalloc length must not be negative|Use a length of zero or more.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@5:32+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ArithmeticOp_OnRuntimeVectorType_ResolvesOperatorOverload_NoTypeMismatch)" {
    source := "\nimport System.Numerics\n\nfunc vadd(a: Vector<int>, b: Vector<int>): Vector<int> {\n    return a + b\n}\n\nfunc vop(a: Vector<int>, b: Vector<int>, c: Vector<int>): Vector<int> {\n    return a * b - c\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ArithmeticOp_OnFixedSizeVectorType_ResolvesOperatorOverload_NoTypeMismatch)" {
    source := "\nimport System.Numerics\n\nfunc vadd(a: Vector3, b: Vector3): Vector3 {\n    return a + b\n}\n\nfunc vmul(a: Vector4, b: Vector4): Vector4 {\n    return a * b\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ArithmeticOp_OnUserDeclaredStructOperator_NoTypeMismatch)" {
    source := "\nstruct Vec2 {\n    X: double\n    Y: double\n\n    static func operator +(a: Vec2, b: Vec2): Vec2 {\n        return new Vec2 { X: a.X + b.X, Y: a.Y + b.Y }\n    }\n}\n\nfunc add(a: Vec2, b: Vec2): Vec2 {\n    return a + b\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.BitwiseShiftAndUnaryOps_OnUserDeclaredStructOperators_NoTypeMismatch)" {
    source := "\nstruct Flags {\n    Value: int\n\n    static func operator &(a: Flags, b: Flags): Flags {\n        return new Flags { Value: a.Value & b.Value }\n    }\n\n    static func operator <<(a: Flags, amount: int): Flags {\n        return new Flags { Value: a.Value << amount }\n    }\n\n    static func operator ~(value: Flags): Flags {\n        return new Flags { Value: ~value.Value }\n    }\n}\n\nfunc combine(a: Flags, b: Flags): Flags {\n    masked := a & b\n    shifted := masked << 2\n    return ~shifted\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.LogicalNot_OnUserDeclaredStructOperator_NoTypeMismatch)" {
    source := "\nstruct Flag {\n    Value: int\n\n    static func operator !(value: Flag): bool {\n        return value.Value == 0\n    }\n}\n\nfunc check(value: Flag): bool {\n    return !value\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ArithmeticOp_OnTypeWithoutOperator_StillReportsTypeMismatch)" {
    source := "\nclass Box {\n    Value: int\n}\n\nfunc bad(a: Box, b: Box): Box {\n    return a + b\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:14+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '+' operator doesn't work with 'Box' and 'Box' — both sides need numeric values, but I found 'Box' and 'Box'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'Box' and 'Box' — both sides need numeric values, but I found 'Box' and 'Box'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@7:14+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:14+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'Box' and 'Box' — both sides need numeric values, but I found 'Box' and 'Box'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@7:14+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ArithmeticOp_VectorPlusUnrelatedType_StillReportsTypeMismatch)" {
    source := "\nimport System.Numerics\n\nclass Box {\n    Value: int\n}\n\nfunc bad(a: Vector<int>, b: Box): Vector<int> {\n    return a + b\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@9:14+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '+' operator doesn't work with 'Vector<int>' and 'Box' — both sides need numeric values, but I found 'Vector<int>' and 'Box'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'Vector<int>' and 'Box' — both sides need numeric values, but I found 'Vector<int>' and 'Box'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@9:14+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@9:14+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'Vector<int>' and 'Box' — both sides need numeric values, but I found 'Vector<int>' and 'Box'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@9:14+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ArithmeticOp_DeclaredOperatorWithWrongParameterTypes_StillReportsTypeMismatch)" {
    source := "\nstruct Vec2 {\n    X: double\n    Y: double\n\n    static func operator +(a: int, b: int): Vec2 {\n        return new Vec2 { X: 0.0, Y: 0.0 }\n    }\n}\n\nfunc bad(a: Vec2, b: Vec2): Vec2 {\n    return a + b\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@12:14+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '+' operator doesn't work with 'Vec2' and 'Vec2' — both sides need numeric values, but I found 'Vec2' and 'Vec2'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'Vec2' and 'Vec2' — both sides need numeric values, but I found 'Vec2' and 'Vec2'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@12:14+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@12:14+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'Vec2' and 'Vec2' — both sides need numeric values, but I found 'Vec2' and 'Vec2'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@12:14+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (1 row); the deleted claim was that `TypeNotFound` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.UnresolvedType_InParameterAnnotation_ReportsTypeNotFound)" {
    source := "func Handle(input: MissingExternalType) {\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@1:20+19;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@1:20+19"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@1:20+19;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@1:20+19"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (2 rows); the deleted claim was that `TypeNotFound` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.UnresolvedType_InReturnType_ReportsTypeNotFound)" {
    source := "func Make(): MissingExternalType {\n    return null\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@1:14+19;NL202:TypeMismatch@2:5+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 2
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@1:14+19"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@1:14+19;NL202:TypeMismatch@2:12+4;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@1:14+19"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (1 row); the deleted claim was that `TypeNotFound` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.UnresolvedType_InNewExpression_ReportsTypeNotFound)" {
    source := "func Main() {\n    x := new MissingExternalType()\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@2:14+19;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@2:14+19"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@2:14+19;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@2:14+19"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (1 row); the deleted claim was that `TypeNotFound` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.UnresolvedType_InFieldType_ReportsTypeNotFound)" {
    source := "class Box {\n    Value: MissingExternalType\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@2:12+19;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@2:12+19"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@2:12+19;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@2:12+19"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.UnresolvedType_InGenericTypeArgument_ReportsArgNotTheKnownGeneric)" {
    source := "import System.Collections.Generic\nfunc Handle(items: List<MissingExternalType>) {\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@2:25+19;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@2:25+19"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@2:25+19;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingExternalType' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingExternalType'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@2:25+19"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.UnresolvedType_SuggestsNearestInScopeType)" {
    source := "class Person {\n    Name: string\n}\nfunc Greet(p: Persn) {\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@4:15+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'Persn' not found|Did you mean 'Person'? Otherwise add the 'import' or package reference that provides 'Persn'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'Persn' not found|Did you mean 'Person'? Otherwise add the 'import' or package reference that provides 'Persn'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@4:15+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@4:15+5;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'Persn' not found|Did you mean 'Person'? Otherwise add the 'import' or package reference that provides 'Persn'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@4:15+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericNew_MissingTypeArguments_ReportsInvalidTypeArgument)" {
    source := "class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box(5)\n    return 0\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@10:14+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'Box' requires 1 type argument(s)|Specify them explicitly: 'new Box<...>(...)'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Box' requires 1 type argument(s)|Specify them explicitly: 'new Box<...>(...)'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@10:14+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@10:14+3;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Box' requires 1 type argument(s)|Specify them explicitly: 'new Box<...>(...)'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@10:14+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericNew_WrongArity_ReportsInvalidTypeArgument)" {
    source := "class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box<int, string>(5)\n    return 0\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@10:14+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'Box' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Box'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Box' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Box'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@10:14+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@10:14+3;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Box' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Box'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@10:14+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_WrongArity_ReportsInvalidTypeArgument)" {
    source := "class Box<T> {\n    item: T\n}\n\nfunc Handle(input: Box<int, bool>) {\n    _ = input\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@5:20+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'Box' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Box'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Box' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Box'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@5:20+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@5:20+3;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Box' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Box'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@5:20+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_BuiltInHeadWithTypeArguments_ReportsInvalidTypeArgument)" {
    source := "record Holder {\n    Items: int<int>\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@2:12+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|'int' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'int'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|'int' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'int'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@2:12+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@2:12+3;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|'int' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'int'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@2:12+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_TypeParameterHeadWithTypeArguments_ReportsInvalidTypeArgument)" {
    source := "func Handle<T>(input: T<int>) {\n    _ = input\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@1:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|'T' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'T'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|'T' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'T'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@1:23+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@1:23+1;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|'T' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'T'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@1:23+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_ExternalNonGenericHeadWithTypeArguments_ReportsInvalidTypeArgument)" {
    source := "import System.Text\nfunc Handle(input: StringBuilder<int>) {\n    _ = input\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@2:20+13;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|'StringBuilder' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'StringBuilder'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|'StringBuilder' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'StringBuilder'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@2:20+13"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@2:20+13;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|'StringBuilder' is not generic, but 1 type argument(s) were provided|Remove the type arguments: 'StringBuilder'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@2:20+13"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `InvalidTypeArgument` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.GenericAnnotation_ExternalGenericHeadWithTypeArguments_HasNoArityDiagnostics)" {
    source := "import System.Collections.Generic\nfunc Handle(items: List<int>) {\n    _ = items\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 0
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 0
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `InvalidTypeArgument` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.GenericAnnotation_ExternalGenericHeadWithNonGenericSibling_HasNoArityDiagnostics)" {
    source := "import System.Threading.Tasks\nfunc Handle(task: Task<int>) {\n    _ = task\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 0
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 0
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_ExternalGenericWrongArity_ReportsInvalidTypeArgument)" {
    source := "import System.Collections.Generic\nfunc Handle(items: List<int, string>) {\n    _ = items\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@2:20+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'List' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'List'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'List' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'List'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@2:20+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@2:20+4;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'List' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'List'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@2:20+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_ExternalGenericWithNonGenericSiblingWrongArity_ReportsInvalidTypeArgument)" {
    source := "import System.Threading.Tasks\nfunc Handle(task: Task<int, string>) {\n    _ = task\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@2:19+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'Task' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Task'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Task' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Task'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@2:19+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@2:19+4;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Task' takes 1 type argument(s), but 2 were provided|Match the declaration's type parameter count for 'Task'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@2:19+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_CompilerKnownGenericWrongArity_ReportsInvalidTypeArgument)" {
    source := "func Handle(value: Result<int>) {\n    _ = value\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@1:20+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'Result' takes 2 type argument(s), but 1 were provided|Match the declaration's type parameter count for 'Result'|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Result' takes 2 type argument(s), but 1 were provided|Match the declaration's type parameter count for 'Result'|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@1:20+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@1:20+6;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Result' takes 2 type argument(s), but 1 were provided|Match the declaration's type parameter count for 'Result'|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@1:20+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument` / `TypeNotFound`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericAnnotation_ExternalGenericMultipleAritiesWrongArity_ReportsInvalidTypeArgument)" {
    source := "import System\nfunc Handle(action: Action<int, int, int, int, int, int, int, int, int, int, int, int, int, int, int, int, int>) {\n    _ = action\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL207:InvalidTypeArgument@2:21+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidTypeArgument|Generic type 'Action' does not take 17 type argument(s); available arities are 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16|Use one of the supported type-argument counts for 'Action'.|Error"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 1
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Action' does not take 17 type argument(s); available arities are 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16|Use one of the supported type-argument counts for 'Action'.|Error"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "NL207@2:21+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 0
    assert AcCodeCount(analysis, "TypeNotFound") == 0
    assert AcCodeRow(analysis, "TypeNotFound") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL207:InvalidTypeArgument@2:21+6;"
    assert AcCodeRow(rich, "InvalidTypeArgument") == "InvalidTypeArgument|Generic type 'Action' does not take 17 type argument(s); available arities are 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16|Use one of the supported type-argument counts for 'Action'.|Error"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "NL207@2:21+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
    assert AcCodeRow(rich, "TypeNotFound") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeNotFound") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeNotFound`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.GenericNew_UnknownTypeArgument_ReportsTypeNotFound)" {
    source := "class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box<Nope>(5)\n    return 0\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@10:18+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'Nope' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'Nope'.|Error"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'Nope' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'Nope'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@10:18+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@10:18+4;"
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'Nope' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'Nope'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@10:18+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `InvalidTypeArgument` / `TypeNotFound`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted body read the error list directly (was AnalyzerTests.GenericNew_CorrectArity_HasNoArityDiagnostics)" {
    source := "class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box<int>(5)\n    return b.item\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "InvalidTypeArgument") == 0
    assert AcCodeCount(analysis, "InvalidTypeArgument") == 0
    assert AcCodeRow(analysis, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 0
    assert AcCodeCount(analysis, "TypeNotFound") == 0
    assert AcCodeRow(analysis, "TypeNotFound") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeAnchor(rich, "InvalidTypeArgument") == "<no-such-code>"
    assert AcCodeRow(rich, "TypeNotFound") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeNotFound") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ReturnInsideFinally_Void_ReportsNL319)" {
    source := "\nfunc F(n: int) {\n    try {\n        n = n + 1\n    } finally {\n        return\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@6:9+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@6:9+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@6:9+6;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@6:9+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `return`\nwould exit the `finally` early to reach the function, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ReturnInsideFinally_Value_WithReturningCatch_ReportsNL319)" {
    source := "\nfunc F(n: int): int {\n    try {\n        return 100 / n\n    } catch {\n        return 0 - 1\n    } finally {\n        return 7\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@8:9+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@8:9+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@8:9+6;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@8:9+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `return`\nwould exit the `finally` early to reach the function, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally` / `MissingReturn`: the whole census is pinned (2 rows); the deleted body read the error list directly (was AnalyzerTests.ReturnInsideFinally_Value_NoCatch_ReportsNL319)" {
    source := "\nfunc F(n: int): int {\n    try {\n        return 100 / n\n    } finally {\n        return 2\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@6:9+6;NL305:MissingReturn@2:1+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 2
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@6:9+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcCodeErrorCount(analysis, "MissingReturn") == 1
    assert AcCodeCount(analysis, "MissingReturn") == 1
    assert AcCodeRow(analysis, "MissingReturn") == "MissingReturn|This function should return 'int', but not all code paths return a value — make sure every branch ends with a 'return'|Add a return statement or change return type to void|Error"
    assert AcCodeAnchor(analysis, "MissingReturn") == "NL305@2:1+1"
    assert AcSuggestions(analysis, 1) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@6:9+6;NL305:MissingReturn@2:1+6;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@6:9+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `return`\nwould exit the `finally` early to reach the function, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
    assert AcCodeRow(rich, "MissingReturn") == "MissingReturn|Not all code paths return a value of type 'int'|Add a `return` statement, or change the return type to `void`|Error"
    assert AcCodeAnchor(rich, "MissingReturn") == "NL305@2:1+6"
    assert AcSuggestions(rich, 1) == "<null>"
    assert AcHint(rich, 1) == "Every code path through this function must end with a `return` statement that\nprovides a `int` value. If you don't need to return anything, change the\nreturn type to `void`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.BreakInsideFinally_LoopOutside_ReportsNL319)" {
    source := "\nfunc F(n: int): int {\n    total := 0\n    i := 0\n    while i < n {\n        i = i + 1\n        try {\n            total = total + 1\n        } finally {\n            if i == 2 {\n                break\n            }\n        }\n    }\n    return total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@11:17+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'break'|Move the `break` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'break'|Move the `break` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@11:17+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@11:17+5;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'break'|Move the `break` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@11:17+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `break`\nwould exit the `finally` early to reach a loop outside the `finally`, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ContinueInsideFinally_LoopOutside_ReportsNL319)" {
    source := "\nfunc F(n: int): int {\n    total := 0\n    i := 0\n    while i < n {\n        i = i + 1\n        try {\n            total = total + 1\n        } finally {\n            if i == 2 {\n                continue\n            }\n        }\n    }\n    return total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@11:17+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'continue'|Move the `continue` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'continue'|Move the `continue` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@11:17+8"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@11:17+8;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'continue'|Move the `continue` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@11:17+8"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `continue`\nwould exit the `finally` early to reach a loop outside the `finally`, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ControlTransferOutOfFinally` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.BreakAndContinueInsideLoopOpenedInsideFinally_NoDiagnostic)" {
    source := "\nfunc F(n: int): int {\n    total := 0\n    try {\n        total = total + 1\n    } finally {\n        i := 0\n        while i < n {\n            if i == 3 {\n                break\n            }\n            if i == 1 {\n                i = i + 2\n                continue\n            }\n            total = total + 1\n            i = i + 1\n        }\n    }\n    return total\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ControlTransferOutOfFinally` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ReturnInsideLambdaInsideFinally_NoDiagnostic)" {
    source := "\nfunc F(): int {\n    r := 0\n    try {\n        r = 1\n    } finally {\n        let f: Func<int, int> = x => {\n            return x + 1\n        }\n        r = f(r)\n    }\n    return r\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ControlTransferOutOfFinally` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ReturnInsideLocalFunctionInsideFinally_NoDiagnostic)" {
    source := "\nfunc F(): int {\n    r := 0\n    try {\n        r = 1\n    } finally {\n        func bump(x: int): int {\n            return x + 1\n        }\n        r = bump(r)\n    }\n    return r\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally` / `InvalidSyntax`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.BreakInsideLambdaInsideFinally_ReportsInvalidSyntaxNotNL319)" {
    source := "\nfunc F(): int {\n    i := 0\n    while i < 1 {\n        try {\n            i = i + 1\n        } finally {\n            let f: Func<int> = () => {\n                break\n                return 1\n            }\n            i = f()\n        }\n    }\n    return i\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@9:17+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here|Move this `break` inside a loop, or remove it if there is no loop to exit.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here|Move this `break` inside a loop, or remove it if there is no loop to exit.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@9:17+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@9:17+5;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here|Move this `break` inside a loop, or remove it if there is no loop to exit.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@9:17+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally` / `InvalidSyntax`: the whole census is pinned (1 row); the deleted body read the error list directly (was AnalyzerTests.ContinueInsideLocalFunctionInsideFinally_ReportsInvalidSyntaxNotNL319)" {
    source := "\nfunc F(): int {\n    i := 0\n    while i < 1 {\n        try {\n            i = i + 1\n        } finally {\n            func bump(): int {\n                continue\n                return 1\n            }\n            i = bump()\n        }\n    }\n    return i\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@9:17+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here|Move this `continue` inside a loop, or remove it if there is no loop to continue.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here|Move this `continue` inside a loop, or remove it if there is no loop to continue.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@9:17+8"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@9:17+8;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here|Move this `continue` inside a loop, or remove it if there is no loop to continue.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@9:17+8"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ReturnInsideTryNestedInsideFinally_ReportsNL319)" {
    source := "\nfunc F(n: int) {\n    try {\n        n = n + 1\n    } finally {\n        try {\n            return\n        } catch {\n            n = 0\n        }\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@7:13+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@7:13+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@7:13+6;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@7:13+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `return`\nwould exit the `finally` early to reach the function, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ReturnInsideLockNestedInsideFinally_ReportsNL319)" {
    source := "\nfunc F(s: string) {\n    try {\n        print(s)\n    } finally {\n        lock s {\n            return\n        }\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@7:13+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@7:13+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@7:13+6;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@7:13+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `return`\nwould exit the `finally` early to reach the function, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ControlTransferOutOfFinally` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ThrowInsideFinally_NoDiagnostic)" {
    source := "\nfunc F(n: int): int {\n    r := 0\n    try {\n        r = 1\n    } finally {\n        if n == 0 {\n            throw new InvalidOperationException(\"fin\")\n        }\n    }\n    return r\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the whole census is pinned (1 row); the deleted claim was that `ControlTransferOutOfFinally` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.NestedFinallys_InnerReturnRejected)" {
    source := "\nfunc F(n: int) {\n    try {\n        n = n + 1\n    } finally {\n        try {\n            n = n + 2\n        } finally {\n            return\n        }\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL319:ControlTransferOutOfFinally@9:13+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 1
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block.|Error"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "NL319@9:13+6"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL319:ControlTransferOutOfFinally@9:13+6;"
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "ControlTransferOutOfFinally|Control cannot leave a 'finally' block with 'return'|Move the `return` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)|Error"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "NL319@9:13+6"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Control cannot leave a `finally` block — the runtime must always finish running it,\nwhether the `try` completed normally or an exception is in flight. This `return`\nwould exit the `finally` early to reach the function, which the CLR forbids.\n`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."
}

test "020 s30 analyzer error codes: `ControlTransferOutOfFinally`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `ControlTransferOutOfFinally` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ReturnAfterFinally_NoDiagnostic)" {
    source := "\nfunc F(n: int): int {\n    try {\n        n = n + 1\n    } finally {\n        n = n + 2\n    }\n    return n\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
}

test "020 s30 analyzer error codes: THE VACUOUS CLAIM — this fixture spells a C# `switch`/`case` statement, which is NOT N# syntax: the parse reports `NL102` at 11:23 with `Success == False` and the analysis then reports NOTHING AT ALL, so the deleted `AssertNoErrorCode(ControlTransferOutOfFinally)` was satisfied by a file that never reached the analyzer walk (was AnalyzerTests.BreakInsideSwitchInsideFinally_NoDiagnostic)" {
    source := "\nfunc F(n: int): int {\n    total := 0\n    i := 0\n    while i < n {\n        i = i + 1\n        try {\n            total = total + 1\n        } finally {\n            switch i {\n                case 2:\n                    break\n                default:\n                    total = total + 1\n            }\n        }\n    }\n    return total\n}"
    assert AcParseCensus(source) == "NL102@11:23+1;"
    assert AcParseSuccess(source) == "False"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeCount(analysis, "ControlTransferOutOfFinally") == 0
    assert AcCodeRow(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "ControlTransferOutOfFinally") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
    assert AcCodeAnchor(rich, "ControlTransferOutOfFinally") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the whole census is pinned (1 row); the deleted claim was that `LockRequiresReferenceType` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Lock_OnIntLocal_ReportsNL320)" {
    source := "\nfunc F() {\n    n := 5\n    lock n {\n        print(n)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL320:LockRequiresReferenceType@4:10+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "LockRequiresReferenceType|'int' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "LockRequiresReferenceType|'int' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "NL320@4:10+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL320:LockRequiresReferenceType@4:10+1;"
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "LockRequiresReferenceType|'int' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "NL320@4:10+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "`Monitor` locks on object IDENTITY. A value type has no stable identity: it would be\nboxed into a fresh object on every `lock`, so no two threads would ever contend on\nthe same lock — the lock would guard nothing."
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the whole census is pinned (1 row); the deleted claim was that `LockRequiresReferenceType` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Lock_OnRecordStructInstance_ReportsNL320)" {
    source := "\nrecord struct Point {\n    X: int\n    Y: int\n}\n\nfunc F() {\n    p := new Point { X: 1, Y: 2 }\n    lock p {\n        print(p.X)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL320:LockRequiresReferenceType@9:10+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "LockRequiresReferenceType|'Point' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "LockRequiresReferenceType|'Point' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "NL320@9:10+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL320:LockRequiresReferenceType@9:10+1;"
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "LockRequiresReferenceType|'Point' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "NL320@9:10+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "`Monitor` locks on object IDENTITY. A value type has no stable identity: it would be\nboxed into a fresh object on every `lock`, so no two threads would ever contend on\nthe same lock — the lock would guard nothing."
}

test "020 s30 analyzer error codes: THIS FIXTURE DOES NOT PARSE — an enum whose members are newline-separated rather than comma-separated reports `NL101` TWICE and `Success == False`, and the analysis then reports FOUR rows, two of them `NL903` complaining about an identifier literally named `<error>`; the NL320 claim survives all of it, but the deleted assertion saw only that one code was present (was AnalyzerTests.Lock_OnEnumValue_ReportsNL320)" {
    source := "\nenum Color {\n    Red\n    Green\n}\n\nfunc F() {\n    c := Color.Red\n    lock c {\n        print(1)\n    }\n}"
    assert AcParseCensus(source) == "NL101@4:5+5;NL101@5:1+1;"
    assert AcParseSuccess(source) == "False"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL306:DuplicateDeclaration@7:1+7;NL903:VisibilityConventionWarning@5:1+7;NL903:VisibilityConventionWarning@7:1+7;NL320:LockRequiresReferenceType@9:10+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 4
    assert AcRow(analysis, 0) == "DuplicateDeclaration|A type named '<error>' already exists — each type name must be unique|<null>|Error"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "LockRequiresReferenceType|'Color' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "NL320@9:10+1"
    assert AcSuggestions(analysis, 3) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL306:DuplicateDeclaration@7:1+7;NL903:VisibilityConventionWarning@5:1+7;NL903:VisibilityConventionWarning@7:1+7;NL320:LockRequiresReferenceType@9:10+1;"
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "LockRequiresReferenceType|'Color' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "NL320@9:10+1"
    assert AcSuggestions(rich, 3) == "<null>"
    assert AcHint(rich, 3) == "`Monitor` locks on object IDENTITY. A value type has no stable identity: it would be\nboxed into a fresh object on every `lock`, so no two threads would ever contend on\nthe same lock — the lock would guard nothing."
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the whole census is pinned (1 row); the deleted claim was that `LockRequiresReferenceType` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Lock_OnNullableInt_ReportsNL320)" {
    source := "\nfunc F() {\n    let n: int? = 5\n    lock n {\n        print(1)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL320:LockRequiresReferenceType@4:10+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "LockRequiresReferenceType|'int?' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "LockRequiresReferenceType|'int?' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "NL320@4:10+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL320:LockRequiresReferenceType@4:10+1;"
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "LockRequiresReferenceType|'int?' is not a reference type as required by the lock statement|Lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "NL320@4:10+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "`Monitor` locks on object IDENTITY. A value type has no stable identity: it would be\nboxed into a fresh object on every `lock`, so no two threads would ever contend on\nthe same lock — the lock would guard nothing."
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the whole census is pinned (1 row); the deleted claim was that `LockRequiresReferenceType` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Lock_OnUnconstrainedTypeParameter_ReportsNL320)" {
    source := "\nfunc LockIt<T>(x: T) {\n    lock x {\n        print(1)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL320:LockRequiresReferenceType@3:10+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "LockRequiresReferenceType|'T' is not a reference type as required by the lock statement|Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "LockRequiresReferenceType|'T' is not a reference type as required by the lock statement|Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "NL320@3:10+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL320:LockRequiresReferenceType@3:10+1;"
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "LockRequiresReferenceType|'T' is not a reference type as required by the lock statement|Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "NL320@3:10+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "`Monitor` locks on object IDENTITY. If `T` is instantiated with a value type, the\nvalue would be boxed into a fresh object on every `lock`, so no two threads would ever\ncontend on the same lock — the lock would guard nothing."
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the whole census is pinned (1 row); the deleted claim was that `LockRequiresReferenceType` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Lock_OnStructConstrainedTypeParameter_ReportsNL320)" {
    source := "\nfunc LockIt<T>(x: T) where T: struct {\n    lock x {\n        print(1)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL320:LockRequiresReferenceType@3:10+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "LockRequiresReferenceType|'T' is not a reference type as required by the lock statement|Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 1
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "LockRequiresReferenceType|'T' is not a reference type as required by the lock statement|Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "NL320@3:10+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL320:LockRequiresReferenceType@3:10+1;"
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "LockRequiresReferenceType|'T' is not a reference type as required by the lock statement|Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`|Error"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "NL320@3:10+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "`Monitor` locks on object IDENTITY. If `T` is instantiated with a value type, the\nvalue would be boxed into a fresh object on every `lock`, so no two threads would ever\ncontend on the same lock — the lock would guard nothing."
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnClassConstrainedTypeParameter_NoDiagnostic)" {
    source := "\nfunc LockIt<T>(x: T) where T: class {\n    lock x {\n        print(1)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnString_NoDiagnostic)" {
    source := "\nfunc F(s: string) {\n    lock s {\n        print(s.Length)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnClassInstance_NoDiagnostic)" {
    source := "\nclass Box {\n    v: int\n}\n\nfunc F() {\n    b := new Box { v: 5 }\n    lock b {\n        print(b.v)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnObjectField_NoDiagnostic)" {
    source := "\nclass Counter {\n    count: int = 0\n    syncLock: object = new object()\n\n    func Increment() {\n        lock syncLock {\n            count++\n        }\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnArray_NoDiagnostic)" {
    source := "\nfunc F(items: int[]) {\n    lock items {\n        print(items.Length)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnInterfaceTypedValue_NoDiagnostic)" {
    source := "\ninterface Greeter {\n    func Greet(): string\n}\n\nclass Hello {\n    func Greet(): string {\n        return \"hi\"\n    }\n}\n\nfunc F(g: Greeter) {\n    lock g {\n        print(g.Greet())\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `LockRequiresReferenceType`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `LockRequiresReferenceType` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.Lock_OnExternalReflectionReferenceType_NoFalsePositive)" {
    source := "\nimport System.Text\n\nfunc F() {\n    sb := new StringBuilder()\n    lock sb {\n        print(1)\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeCount(analysis, "LockRequiresReferenceType") == 0
    assert AcCodeRow(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "LockRequiresReferenceType") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "LockRequiresReferenceType") == "<no-such-code>"
    assert AcCodeAnchor(rich, "LockRequiresReferenceType") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `MemberWriteThroughValueCopy`: the whole census is pinned (1 row); the deleted claim was that `MemberWriteThroughValueCopy` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.MemberWrite_ThroughListIndexerOfStruct_ReportsNL322)" {
    source := "\nstruct S {\n    X: int\n}\n\nfunc F(): int {\n    lst := new List<S>()\n    lst.Add(new S { X: 1 })\n    lst[0].X = 5\n    return lst[0].X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL322:MemberWriteThroughValueCopy@9:8+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back|Error"
    assert AcCodeErrorCount(analysis, "MemberWriteThroughValueCopy") == 1
    assert AcCodeCount(analysis, "MemberWriteThroughValueCopy") == 1
    assert AcCodeRow(analysis, "MemberWriteThroughValueCopy") == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back|Error"
    assert AcCodeAnchor(analysis, "MemberWriteThroughValueCopy") == "NL322@9:8+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL322:MemberWriteThroughValueCopy@9:8+2;"
    assert AcCodeRow(rich, "MemberWriteThroughValueCopy") == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back (e.g. `tmp := …` / `tmp.X = …` / store `tmp`)|Error"
    assert AcCodeAnchor(rich, "MemberWriteThroughValueCopy") == "NL322@9:8+2"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "A value type is copied every time it is returned from a call, an indexer, or a\nproperty. This write would land in that temporary copy and be thrown away with it —\nthe original value would never change."
}

test "020 s30 analyzer error codes: `MemberWriteThroughValueCopy`: the whole census is pinned (1 row); the deleted claim was that `MemberWriteThroughValueCopy` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.MemberWrite_ThroughStructCallResult_ReportsNL322)" {
    source := "\nstruct S {\n    X: int\n}\n\nfunc Make(): S {\n    return new S { X: 1 }\n}\n\nfunc F() {\n    Make().X = 5\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL322:MemberWriteThroughValueCopy@11:5+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back|Error"
    assert AcCodeErrorCount(analysis, "MemberWriteThroughValueCopy") == 1
    assert AcCodeCount(analysis, "MemberWriteThroughValueCopy") == 1
    assert AcCodeRow(analysis, "MemberWriteThroughValueCopy") == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back|Error"
    assert AcCodeAnchor(analysis, "MemberWriteThroughValueCopy") == "NL322@11:5+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL322:MemberWriteThroughValueCopy@11:5+4;"
    assert AcCodeRow(rich, "MemberWriteThroughValueCopy") == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back (e.g. `tmp := …` / `tmp.X = …` / store `tmp`)|Error"
    assert AcCodeAnchor(rich, "MemberWriteThroughValueCopy") == "NL322@11:5+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "A value type is copied every time it is returned from a call, an indexer, or a\nproperty. This write would land in that temporary copy and be thrown away with it —\nthe original value would never change."
}

test "020 s30 analyzer error codes: `MemberWriteThroughValueCopy`: the whole census is pinned (1 row); the deleted claim was that `MemberWriteThroughValueCopy` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.CompoundMemberWrite_ThroughListIndexerOfStruct_ReportsNL322)" {
    source := "\nstruct S {\n    X: int\n}\n\nfunc F() {\n    lst := new List<S>()\n    lst.Add(new S { X: 1 })\n    lst[0].X += 3\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL322:MemberWriteThroughValueCopy@9:8+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back|Error"
    assert AcCodeErrorCount(analysis, "MemberWriteThroughValueCopy") == 1
    assert AcCodeCount(analysis, "MemberWriteThroughValueCopy") == 1
    assert AcCodeRow(analysis, "MemberWriteThroughValueCopy") == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back|Error"
    assert AcCodeAnchor(analysis, "MemberWriteThroughValueCopy") == "NL322@9:8+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL322:MemberWriteThroughValueCopy@9:8+2;"
    assert AcCodeRow(rich, "MemberWriteThroughValueCopy") == "MemberWriteThroughValueCopy|Cannot assign to 'X' because its receiver is a temporary copy of 'S', not a variable|Copy the value into a local first, modify the local, then store the whole value back (e.g. `tmp := …` / `tmp.X = …` / store `tmp`)|Error"
    assert AcCodeAnchor(rich, "MemberWriteThroughValueCopy") == "NL322@9:8+2"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "A value type is copied every time it is returned from a call, an indexer, or a\nproperty. This write would land in that temporary copy and be thrown away with it —\nthe original value would never change."
}

test "020 s30 analyzer error codes: `MemberWriteThroughValueCopy`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `MemberWriteThroughValueCopy` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.MemberWrite_ThroughReferenceReceivers_NoFalsePositive)" {
    source := "\nclass C {\n    X: int\n    constructor(v: int) {\n        X = v\n    }\n}\n\nfunc Pick(items: List<C>): C {\n    return items[0]\n}\n\nfunc F(): int {\n    lst := new List<C>()\n    lst.Add(new C(1))\n    lst[0].X = 5\n    Pick(lst).X = 6\n    return lst[0].X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "MemberWriteThroughValueCopy") == 0
    assert AcCodeCount(analysis, "MemberWriteThroughValueCopy") == 0
    assert AcCodeRow(analysis, "MemberWriteThroughValueCopy") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "MemberWriteThroughValueCopy") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "MemberWriteThroughValueCopy") == "<no-such-code>"
    assert AcCodeAnchor(rich, "MemberWriteThroughValueCopy") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `MemberWriteThroughValueCopy`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `MemberWriteThroughValueCopy` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.MemberWrite_ThroughAddressableValueChains_NoFalsePositive)" {
    source := "\nstruct Inner {\n    X: int\n}\n\nstruct Outer {\n    i: Inner\n}\n\nfunc G(p: Outer): int {\n    p.i.X = 7\n    return p.i.X\n}\n\nfunc F(): int {\n    o := new Outer { i: new Inner { X: 1 } }\n    o.i.X = 5\n    arr := new int[3]\n    arr[0] = 1\n    return o.i.X + G(o)\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "MemberWriteThroughValueCopy") == 0
    assert AcCodeCount(analysis, "MemberWriteThroughValueCopy") == 0
    assert AcCodeRow(analysis, "MemberWriteThroughValueCopy") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "MemberWriteThroughValueCopy") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "MemberWriteThroughValueCopy") == "<no-such-code>"
    assert AcCodeAnchor(rich, "MemberWriteThroughValueCopy") == "<no-such-code>"
}

test "020 s30 analyzer error codes: ONE OF THE THREE DELETED CLAIMS THAT ARE TRUE ONLY OF THE ENTRY POINT NOTHING SHIPS — the deleted body matched `'Items' is typed as 'List<Pt>', but the value is 'List<Rs>'`, which the plain route says and the four-argument route production actually calls collapses to the bare `Type mismatch`; both routes are pinned here (was AnalyzerTests.ObjectInitializer_GenericCollectionElementMismatch_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Rs {\n    S: string\n}\n\nrecord H {\n    Items: List<Pt>\n}\n\nfunc f(): int {\n    l := new List<Rs>()\n    l.Add(new Rs { S: \"abc\" })\n    h := new H { Items: l }\n    return h.Items[0].X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@17:25+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'Items' is typed as 'List<Pt>', but the value is 'List<Rs>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'Items' is typed as 'List<Pt>', but the value is 'List<Rs>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@17:25+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@17:25+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@17:25+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_SameShapedElementTypeMismatch_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Qt {\n    X: int\n}\n\nrecord H {\n    Items: List<Pt>\n}\n\nfunc f(): int {\n    l := new List<Qt>()\n    h := new H { Items: l }\n    return h.Items[0].X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@16:25+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'Items' is typed as 'List<Pt>', but the value is 'List<Qt>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'Items' is typed as 'List<Pt>', but the value is 'List<Qt>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@16:25+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@16:25+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@16:25+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_DictionaryValueTypeMismatch_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Rs {\n    S: string\n}\n\nrecord H {\n    Map: Dictionary<string, Pt>\n}\n\nfunc f(): int {\n    d := new Dictionary<string, Rs>()\n    h := new H { Map: d }\n    return h.Map[\"k\"].X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@16:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'Map' is typed as 'Dictionary<string, Pt>', but the value is 'Dictionary<string, Rs>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'Map' is typed as 'Dictionary<string, Pt>', but the value is 'Dictionary<string, Rs>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@16:23+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@16:23+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@16:23+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_SimpleFieldTypeMismatch_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nfunc f(): int {\n    p := new Pt { X: \"abc\" }\n    return p.X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:22+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'X' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'X' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@7:22+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:22+5;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@7:22+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_GenericUserTypeArgumentMismatch_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Rs {\n    S: string\n}\n\nrecord Box<T> {\n    Item: T\n}\n\nrecord H {\n    B: Box<Pt>\n}\n\nfunc f(h: H, b: Box<Rs>): H {\n    return new H { B: b }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@19:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'B' is typed as 'Box<Pt>', but the value is 'Box<Rs>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'B' is typed as 'Box<Pt>', but the value is 'Box<Rs>'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@19:23+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@19:23+1;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@19:23+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_ClosedGenericMemberSubstitution_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Rs {\n    S: string\n}\n\nrecord Box<T> {\n    Item: T\n}\n\nfunc f(): Box<Pt> {\n    return new Box<Pt> { Item: new Rs { S: \"abc\" } }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@15:32+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'Item' is typed as 'Pt', but the value is 'Rs'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'Item' is typed as 'Pt', but the value is 'Rs'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@15:32+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@15:32+3;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@15:32+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_ArrayElementTypeMismatch_Error)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Rs {\n    S: string\n}\n\nrecord H {\n    Items: Pt[]\n}\n\nfunc f(arr: Rs[]): H {\n    return new H { Items: arr }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@15:27+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'Items' is typed as 'Pt[]', but the value is 'Rs[]'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'Items' is typed as 'Pt[]', but the value is 'Rs[]'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@15:27+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@15:27+3;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@15:27+3"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "These types are not compatible. Check if you need to convert or cast."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the whole census is pinned (1 row); the deleted claim was that `TypeMismatch` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_UnionCasePropertyMismatch_Error)" {
    source := "\nunion Result<T> {\n    Success { value: T }\n    Failure { error: string }\n}\n\nfunc f(): Result<int> {\n    return new Result.Success<int> { value: \"abc\" }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@8:45+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|'value' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|'value' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@8:45+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@8:45+5;"
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@8:45+5"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ObjectInitializer_MatchingGenericTypes_NoError)" {
    source := "\nrecord Pt {\n    X: int\n}\n\nrecord Box<T> {\n    Item: T\n}\n\nrecord H {\n    Items: List<Pt>\n    Map: Dictionary<string, Pt>\n    B: Box<int>\n}\n\nfunc f(): int {\n    l := new List<Pt>()\n    l.Add(new Pt { X: 7 })\n    d := new Dictionary<string, Pt>()\n    h := new H { Items: l, Map: d, B: new Box<int> { Item: 5 } }\n    return h.Items[0].X\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch`: the analysis is COMPLETELY SILENT — census EMPTY, count 0; the deleted claim was that `TypeMismatch` is ABSENT at `Error` severity, which says nothing about any OTHER code (was AnalyzerTests.ObjectInitializer_WideningAndNullAndSubtype_NoError)" {
    source := "\nclass Animal {\n}\n\nclass Dog : Animal {\n}\n\nrecord Pt {\n    X: int\n}\n\nrecord H {\n    V: double\n    Items: List<Pt>?\n    Pet: Animal\n    Tags: List<string>\n}\n\nfunc f(): H {\n    return new H { V: 3, Items: null, Pet: new Dog(), Tags: new() }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `UndefinedMember`: the whole census is pinned (1 row); the deleted claim was that `UndefinedMember` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_UnknownMemberName_Error)" {
    source := "\nrecord H {\n    Items: List<int>\n}\n\nfunc f(): H {\n    return new H { Itmes: new List<int>() }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL303:UndefinedMember@7:20+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedMember|Member 'Itmes' not found on type 'H'|Did you mean 'Items'?|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 1
    assert AcCodeCount(analysis, "UndefinedMember") == 1
    assert AcCodeRow(analysis, "UndefinedMember") == "UndefinedMember|Member 'Itmes' not found on type 'H'|Did you mean 'Items'?|Error"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "NL303@7:20+5"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL303:UndefinedMember@7:20+5;"
    assert AcCodeRow(rich, "UndefinedMember") == "UndefinedMember|Member 'Itmes' not found on type 'H'|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedMember") == "NL303@7:20+5"
    assert AcSuggestions(rich, 0) == "Items"
    assert AcHint(rich, 0) == "The type `H` does not have a member named `Itmes`.\nCheck for typos, or make sure you're accessing the right type."
}

test "020 s30 analyzer error codes: `UndefinedMember`: the whole census is pinned (1 row); the deleted claim was that `UndefinedMember` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_UnknownMemberOnClosedGeneric_Error)" {
    source := "\nrecord Box<T> {\n    Item: T\n}\n\nfunc f(): Box<int> {\n    return new Box<int> { Itm: 5 }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL303:UndefinedMember@7:27+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedMember|Member 'Itm' not found on type 'Box<int>'|Did you mean 'Item'?|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 1
    assert AcCodeCount(analysis, "UndefinedMember") == 1
    assert AcCodeRow(analysis, "UndefinedMember") == "UndefinedMember|Member 'Itm' not found on type 'Box<int>'|Did you mean 'Item'?|Error"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "NL303@7:27+3"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL303:UndefinedMember@7:27+3;"
    assert AcCodeRow(rich, "UndefinedMember") == "UndefinedMember|Member 'Itm' not found on type 'Box<int>'|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedMember") == "NL303@7:27+3"
    assert AcSuggestions(rich, 0) == "Item"
    assert AcHint(rich, 0) == "The type `Box<int>` does not have a member named `Itm`.\nCheck for typos, or make sure you're accessing the right type."
}

test "020 s30 analyzer error codes: `UndefinedMember`: the whole census is pinned (1 row); the deleted claim was that `UndefinedMember` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.ObjectInitializer_UnionCasePropertyTypo_Error)" {
    source := "\nunion Result<T> {\n    Success { value: T }\n    Failure { error: string }\n}\n\nfunc f(): Result<int> {\n    return new Result.Success<int> { valu: 42 }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL303:UndefinedMember@8:38+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedMember|Union case 'Success' doesn't have a property named 'valu' — check the case definition for available properties|Did you mean 'value'?|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 1
    assert AcCodeCount(analysis, "UndefinedMember") == 1
    assert AcCodeRow(analysis, "UndefinedMember") == "UndefinedMember|Union case 'Success' doesn't have a property named 'valu' — check the case definition for available properties|Did you mean 'value'?|Error"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "NL303@8:38+4"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL303:UndefinedMember@8:38+4;"
    assert AcCodeRow(rich, "UndefinedMember") == "UndefinedMember|Union case 'Success' doesn't have a property named 'valu' — check the case definition for available properties|Did you mean 'value'?|Error"
    assert AcCodeAnchor(rich, "UndefinedMember") == "NL303@8:38+4"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `UndefinedMember`: the whole census is pinned (2 rows); the deleted claim was that `UndefinedMember` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.UnionCaseConstruction_UnknownCase_Error)" {
    source := "\nunion Result<T> {\n    Success { value: T }\n    Failure { error: string }\n}\n\nfunc f(): Result<int> {\n    return new Result.Sucess<int> { value: 42 }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL303:UndefinedMember@8:16+13;NL202:TypeMismatch@8:5+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 2
    assert AcRow(analysis, 0) == "UndefinedMember|'Sucess' is not a case of union 'Result' — check the union definition for available cases|Did you mean 'Result.Success'?|Error"
    assert AcCodeErrorCount(analysis, "UndefinedMember") == 1
    assert AcCodeCount(analysis, "UndefinedMember") == 1
    assert AcCodeRow(analysis, "UndefinedMember") == "UndefinedMember|'Sucess' is not a case of union 'Result' — check the union definition for available cases|Did you mean 'Result.Success'?|Error"
    assert AcCodeAnchor(analysis, "UndefinedMember") == "NL303@8:16+13"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL303:UndefinedMember@8:16+13;NL202:TypeMismatch@8:12+3;"
    assert AcCodeRow(rich, "UndefinedMember") == "UndefinedMember|'Sucess' is not a case of union 'Result' — check the union definition for available cases|Did you mean 'Result.Success'?|Error"
    assert AcCodeAnchor(rich, "UndefinedMember") == "NL303@8:16+13"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

test "020 s30 analyzer error codes: `TypeMismatch` / `UndefinedMember`: the whole census is pinned (1 row); the deleted body claimed one code present and one absent, and nothing else (was AnalyzerTests.ObjectInitializer_InheritedMember_ResolvesAndTypeChecks)" {
    source0 := "\nclass Base {\n    X: int\n}\n\nclass Derived : Base {\n}\n\nfunc f(): Derived {\n    return new Derived { X: 5 }\n}"
    assert AcParseCensus(source0) == ""
    assert AcParseSuccess(source0) == "True"
    analysis0 := AcAnalyze(source0)
    assert AcCensus(analysis0) == ""
    assert AcHasErrors(analysis0) == "False"
    assert AcErrorCount(analysis0) == 0
    assert AcRow(analysis0, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis0, "TypeMismatch") == 0
    assert AcCodeCount(analysis0, "TypeMismatch") == 0
    assert AcCodeRow(analysis0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeErrorCount(analysis0, "UndefinedMember") == 0
    assert AcCodeCount(analysis0, "UndefinedMember") == 0
    assert AcCodeRow(analysis0, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(analysis0, "UndefinedMember") == "<no-such-code>"
    rich0 := AcAnalyzeWithSource(source0)
    assert AcCensus(rich0) == ""
    assert AcCodeRow(rich0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeRow(rich0, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(rich0, "UndefinedMember") == "<no-such-code>"
    source1 := "\nclass Base {\n    X: int\n}\n\nclass Derived : Base {\n}\n\nfunc f(): Derived {\n    return new Derived { X: \"abc\" }\n}"
    assert AcParseCensus(source1) == ""
    assert AcParseSuccess(source1) == "True"
    analysis1 := AcAnalyze(source1)
    assert AcCensus(analysis1) == "NL202:TypeMismatch@10:29+1;"
    assert AcHasErrors(analysis1) == "True"
    assert AcErrorCount(analysis1) == 1
    assert AcRow(analysis1, 0) == "TypeMismatch|'X' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis1, "TypeMismatch") == 1
    assert AcCodeCount(analysis1, "TypeMismatch") == 1
    assert AcCodeRow(analysis1, "TypeMismatch") == "TypeMismatch|'X' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis1, "TypeMismatch") == "NL202@10:29+1"
    assert AcSuggestions(analysis1, 0) == "<null>"
    assert AcCodeErrorCount(analysis1, "UndefinedMember") == 0
    assert AcCodeCount(analysis1, "UndefinedMember") == 0
    assert AcCodeRow(analysis1, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(analysis1, "UndefinedMember") == "<no-such-code>"
    rich1 := AcAnalyzeWithSource(source1)
    assert AcCensus(rich1) == "NL202:TypeMismatch@10:29+5;"
    assert AcCodeRow(rich1, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich1, "TypeMismatch") == "NL202@10:29+5"
    assert AcSuggestions(rich1, 0) == "<null>"
    assert AcHint(rich1, 0) == "Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert AcCodeRow(rich1, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(rich1, "UndefinedMember") == "<no-such-code>"
}

test "020 s30 analyzer error codes: `TypeMismatch` / `UndefinedMember`: the whole census is pinned (2 rows); the deleted body claimed one code present and one absent, and nothing else (was AnalyzerTests.ObjectInitializer_ReflectionMembers_TypeCheckAndNameCheck)" {
    source0 := "\nimport System.Text\n\nfunc f(): StringBuilder {\n    return new StringBuilder { Capacity: 10 }\n}"
    assert AcParseCensus(source0) == ""
    assert AcParseSuccess(source0) == "True"
    analysis0 := AcAnalyze(source0)
    assert AcCensus(analysis0) == ""
    assert AcHasErrors(analysis0) == "False"
    assert AcErrorCount(analysis0) == 0
    assert AcRow(analysis0, 0) == "<no-such-error>"
    assert AcCodeErrorCount(analysis0, "TypeMismatch") == 0
    assert AcCodeCount(analysis0, "TypeMismatch") == 0
    assert AcCodeRow(analysis0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeErrorCount(analysis0, "UndefinedMember") == 0
    assert AcCodeCount(analysis0, "UndefinedMember") == 0
    assert AcCodeRow(analysis0, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(analysis0, "UndefinedMember") == "<no-such-code>"
    rich0 := AcAnalyzeWithSource(source0)
    assert AcCensus(rich0) == ""
    assert AcCodeRow(rich0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich0, "TypeMismatch") == "<no-such-code>"
    assert AcCodeRow(rich0, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(rich0, "UndefinedMember") == "<no-such-code>"
    source1 := "\nimport System.Text\n\nfunc f(): StringBuilder {\n    return new StringBuilder { Capacity: \"abc\" }\n}"
    assert AcParseCensus(source1) == ""
    assert AcParseSuccess(source1) == "True"
    analysis1 := AcAnalyze(source1)
    assert AcCensus(analysis1) == "NL202:TypeMismatch@5:42+1;"
    assert AcHasErrors(analysis1) == "True"
    assert AcErrorCount(analysis1) == 1
    assert AcRow(analysis1, 0) == "TypeMismatch|'Capacity' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeErrorCount(analysis1, "TypeMismatch") == 1
    assert AcCodeCount(analysis1, "TypeMismatch") == 1
    assert AcCodeRow(analysis1, "TypeMismatch") == "TypeMismatch|'Capacity' is typed as 'int', but the value is 'string'|Ensure types are compatible or add explicit cast|Error"
    assert AcCodeAnchor(analysis1, "TypeMismatch") == "NL202@5:42+1"
    assert AcSuggestions(analysis1, 0) == "<null>"
    assert AcCodeErrorCount(analysis1, "UndefinedMember") == 0
    assert AcCodeCount(analysis1, "UndefinedMember") == 0
    assert AcCodeRow(analysis1, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(analysis1, "UndefinedMember") == "<no-such-code>"
    rich1 := AcAnalyzeWithSource(source1)
    assert AcCensus(rich1) == "NL202:TypeMismatch@5:42+5;"
    assert AcCodeRow(rich1, "TypeMismatch") == "TypeMismatch|Type mismatch|<null>|Error"
    assert AcCodeAnchor(rich1, "TypeMismatch") == "NL202@5:42+5"
    assert AcSuggestions(rich1, 0) == "<null>"
    assert AcHint(rich1, 0) == "Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert AcCodeRow(rich1, "UndefinedMember") == "<no-such-code>"
    assert AcCodeAnchor(rich1, "UndefinedMember") == "<no-such-code>"
    source2 := "\nimport System.Text\n\nfunc f(): StringBuilder {\n    return new StringBuilder { Capcity: 10 }\n}"
    assert AcParseCensus(source2) == ""
    assert AcParseSuccess(source2) == "True"
    analysis2 := AcAnalyze(source2)
    assert AcCensus(analysis2) == "NL303:UndefinedMember@5:32+7;"
    assert AcHasErrors(analysis2) == "True"
    assert AcErrorCount(analysis2) == 1
    assert AcRow(analysis2, 0) == "UndefinedMember|Member 'Capcity' not found on type 'StringBuilder'|Did you mean 'Capacity'?|Error"
    assert AcCodeErrorCount(analysis2, "TypeMismatch") == 0
    assert AcCodeCount(analysis2, "TypeMismatch") == 0
    assert AcCodeRow(analysis2, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(analysis2, "TypeMismatch") == "<no-such-code>"
    assert AcCodeErrorCount(analysis2, "UndefinedMember") == 1
    assert AcCodeCount(analysis2, "UndefinedMember") == 1
    assert AcCodeRow(analysis2, "UndefinedMember") == "UndefinedMember|Member 'Capcity' not found on type 'StringBuilder'|Did you mean 'Capacity'?|Error"
    assert AcCodeAnchor(analysis2, "UndefinedMember") == "NL303@5:32+7"
    assert AcSuggestions(analysis2, 0) == "<null>"
    rich2 := AcAnalyzeWithSource(source2)
    assert AcCensus(rich2) == "NL303:UndefinedMember@5:32+7;"
    assert AcCodeRow(rich2, "TypeMismatch") == "<no-such-code>"
    assert AcCodeAnchor(rich2, "TypeMismatch") == "<no-such-code>"
    assert AcCodeRow(rich2, "UndefinedMember") == "UndefinedMember|Member 'Capcity' not found on type 'StringBuilder'|<null>|Error"
    assert AcCodeAnchor(rich2, "UndefinedMember") == "NL303@5:32+7"
    assert AcSuggestions(rich2, 0) == "Capacity"
    assert AcHint(rich2, 0) == "The type `StringBuilder` does not have a member named `Capcity`.\nCheck for typos, or make sure you're accessing the right type."
}

test "020 s30 analyzer error codes: `InvalidSyntax`: the whole census is pinned (1 row); the deleted claim was that `InvalidSyntax` is present at `Error` severity, and NOTHING about where or what it says (was AnalyzerTests.Nameof_UnsupportedTarget_ReportsAnalyzerDiagnostic)" {
    source := "func f(): string {\n    return nameof(1 + 2)\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@2:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|nameof can only name an identifier or member access|Use nameof(value) or nameof(value.Member).|Error"
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|nameof can only name an identifier or member access|Use nameof(value) or nameof(value.Member).|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@2:21+1"
    assert AcSuggestions(analysis, 0) == "<null>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@2:21+1;"
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|nameof can only name an identifier or member access|Use nameof(value) or nameof(value.Member).|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@2:21+1"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcHint(rich, 0) == "<null>"
}

// THE FIRST `[Theory]` TO LEAVE `AnalyzerTests.cs`. It is a table rather than three declarations
// because BOTH sides of the C# were interpolated per row — the fixture was `$@"{typeKind} Box<T>
// {{…{memberSource}…}}"` and the claim was `$"Static {memberKind} '{memberName}'"` — so all four
// parameters stay load-bearing here: the body rebuilds the source from two of them and the expected
// sentence from the other two. **AND THE PER-ROW `codeAnchor` IMMEDIATELY FOUND A DEFECT THE C#
// COULD NOT**: `field count` underlines `count` and `property value` underlines `value`, but
// `method mk` underlines `fu` — column 12, length 2, the column of the `func` keyword carrying the
// LENGTH of the member name. One collapsed assertion could not have said so; three separate values
// do.
test "020 s30 analyzer error codes: a static member on a GENERIC type is refused before emission, one row per member kind — the fixture and the message are BOTH interpolated per row, which is why this is a table and not three contracts, and the three rows do NOT anchor alike: `count` and `value` are underlined whole while `mk` underlines `fu`, the `func` keyword's column with the member name's length (was AnalyzerTests.GenericTypes_StaticMembers_ReportBeforeEmission, all three [InlineData] rows)" with (typeKind: string, memberSource: string, memberKind: string, memberName: string, census: string, codeRow: string, codeAnchor: string) [
    ("class", "static count: int", "field", "count", "NL323:FeatureNotImplemented@3:12+5;", "FeatureNotImplemented|Static field 'count' is not supported on generic type 'Box<T>' yet|Move the static member to a non-generic helper type, or make it an instance member.|Error", "NL323@3:12+5"),
    ("record", "static func mk(): int {\n        return 1\n    }", "method", "mk", "NL323:FeatureNotImplemented@3:12+2;", "FeatureNotImplemented|Static method 'mk' is not supported on generic type 'Box<T>' yet|Move the static member to a non-generic helper type, or make it an instance member.|Error", "NL323@3:12+2"),
    ("struct", "static value: int {\n        get {\n            return 1\n        }\n    }", "property", "value", "NL323:FeatureNotImplemented@3:12+5;", "FeatureNotImplemented|Static property 'value' is not supported on generic type 'Box<T>' yet|Move the static member to a non-generic helper type, or make it an instance member.|Error", "NL323@3:12+5")
] {
    source := typeKind + " Box<T> {\n    item: T\n    " + memberSource + "\n}\n\nfunc Use(): int {\n    return 0\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcCodeErrorCount(analysis, "FeatureNotImplemented") == 1
    assert AcCodeCount(analysis, "FeatureNotImplemented") == 1
    assert AcCodeRow(analysis, "FeatureNotImplemented") == codeRow
    assert AcCodeAnchor(analysis, "FeatureNotImplemented") == codeAnchor
    assert codeRow.Contains("Static " + memberKind + " '" + memberName + "'")
    assert codeRow.Contains("generic type 'Box<T>'")
    rich := AcAnalyzeWithSource(source)
    assert AcCodeRow(rich, "FeatureNotImplemented") == codeRow
}


// ══════════════════════════════════════════════════════════════════════════════════════════════
// TRANCHE 3 — THE WHOLE REMAINING DIRECT-`Analyze` + `ErrorCode` SHAPE, AND THE FIRST 56 OF THE
// `AnalyzeWithSource` + `ErrorCode` SHAPE. 80 methods / 1,349 declaration lines / 242 in-body
// `Assert.` / 139 fixtures / 570 decoded claim rows. Task 020 slice 31 deletes them.
//
// TWO SHAPES, AND ONE OF THEM GOES TO ZERO. The 24 methods that reach the analyzer through the
// ONE-argument `Analyze(unit)` helper AND read an `ErrorCode` are taken WHOLE, so after this slice
// `AnalyzerTests.cs` has no direct-`Analyze` + `ErrorCode` method left. The other 56 are the
// `AnalyzeWithSource` shape's prefix, cut at line 3353 where the readonly-field subject ends.
//
// NEITHER HELPER DIES, AND THAT WAS CHECKED RATHER THAN ASSUMED. `Analyze` keeps 15 consumers that
// read no `ErrorCode` plus `AssertNoErrors`/`AssertHasError`; `AnalyzeWithSource` keeps 26 plus the
// 33 `AnalyzeWithSource` + `ErrorCode` methods beyond the cut.
//
// THE TABLE CAPABILITY IS NOW ROUTINE. Slice 30 migrated the campaign's FIRST `[Theory]`; this
// tranche migrates THIRTY-ONE of them — 90 `InlineData` rows, 31 of `AnalyzerTests.cs`'s remaining
// 34 theories and 90 of its 97 rows — and every one is a table with PER-ROW identity rather than a
// collapsed assertion. Three tables carry a column the C# never had: the plain-route anchor and the
// production-route anchor as SEPARATE per-row values, because they disagree.
//
// SIX THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//
//   (a) THE TWO ENTRY POINTS DISAGREE ABOUT SPAN WIDTH, TWENTY-THREE TIMES, AND ALWAYS THE SAME
//       WAY. Every one of the 139 fixtures is analysed through BOTH `Analyze(unit)` and the
//       four-argument production route, and 23 of the 148 resulting row pairs differ in LENGTH —
//       `plain` reports **1** in every single one of the 23, while production reports the real
//       token width (2, 3, 5, 6, 7 …). The one-argument overload is handed no source text, so it
//       cannot measure a token; it emits a one-column underline and the caller cannot tell. Not one
//       of the 242 deleted `Assert.` calls read a length, a line or a column, so nothing in
//       `AnalyzerTests.cs` could see it. Both widths are pinned here, side by side, per fixture.
//
//   (b) THE TWO ENTRY POINTS ALSO DISAGREE ABOUT WORDS. Seven suggestions and three messages differ
//       between the routes for the same source. `MethodGroupToClrDelegate_RejectsNumericParameter-
//       Conversion` is the sharpest: the plain route says `Argument 1 to 'Use' is method group
//       'AcceptLong', but parameter 'action' expects 'Action<int>'` AND offers a fix, while the
//       production route says `Cannot pass ...` and offers NO suggestion at all. The deleted method
//       asserted a substring that survives both, so it could not have failed either way.
//
//   (c) `ContextualHint` IS A PRODUCTION-ROUTE-ONLY FIELD, ELEVEN TIMES. Eleven fixtures carry a
//       hint on the four-argument route and NONE on the one-argument route. Exactly two deleted
//       assertions ever read the field; the other nine hints were invisible. All are pinned.
//
//   (d) FIVE OF THE THIRTEEN ABSENCE CLAIMS WERE VACUOUS. Three fixtures —
//       `GenericListOfNSharpType_CountProperty_IsNotMethodGroup`, `StackAlloc_SmallIntLengths_-
//       Accepted` and `StackAlloc_AliasedSmallIntLength_Accepted` — report NOTHING AT ALL, so a
//       claim that some code is absent from their diagnostics holds for every code that exists.
//       They are pinned here as an EMPTY census, an error COUNT of zero and `<no-such-error>` at
//       index 0. The other eight absence claims are discriminating: their fixtures do report a row,
//       and the census names which.
//
//   (e) THE SPANS, WHICH NOT ONE OF THE 80 METHODS STATED. 296 anchor positions were read back out
//       of the fixture text with ZERO out of range. `NL309` anchors on the FIELD NAME (`value` 18
//       times, `Value` 11); `NL411` on the whole dotted path (`greeting.CompareTo`, eighteen
//       columns) or the bare member; `NL315` on the callee name with the receiver and dot OUTSIDE
//       it; `NL202` on the operator itself for the relational and equality families, and on the
//       spelled return type for the generator family, where the length tracks the annotation
//       character for character.
//
//   (f) THE FULL SENTENCES, INCLUDING THE ONES THAT DIFFER BY ONE WORD. `is readonly` against `is
//       static readonly`, `assigned with '='` against `changed with '++'`, `'+'` against `'+='` —
//       the readonly-field and compound-assignment families each choose between two spellings, and
//       a `Contains` on the shared prefix could not tell them apart. Every row is pinned whole:
//       code, message, suggestion and severity.
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself: every
// method's literal — 35 `@"…"` verbatim, 27 interpolated raw `$$"""…"""`, 14 plain raw `"""…"""`
// and 4 concatenation expressions over ordinary literals — was copied unmodified into a generated
// console program that printed its sha256 and length, expanded per `[InlineData]` row, and the
// decoder that produced the strings below reproduces all 139 shas and all 139 lengths with ZERO
// mismatches. All 139 are distinct. Every one of the 139 PARSES CLEANLY: all 139 parse censuses are
// empty and all 139 report success, so every row in every analysis census is provably the
// ANALYZER's own.
// ══════════════════════════════════════════════════════════════════════════════════════════════

test "020 s31 analyzer error codes: throwing a non-exception operand is `NL202` naming the operand type, one row per operand kind — and the per-row anchor immediately separates the routes: `throw 1` and the `object` local agree, but the string-literal row underlines ONE column on the plain route and all FIVE of the string literal on the production route (was AnalyzerTests.ThrowStatement_NonExceptionOperand_ReportsTypeMismatch, all 3 [InlineData] rows)" with (statement: string, operandType: string, census: string, row0: string, codeAnchorTypeMismatch: string, richCensus: string, richCodeAnchorTypeMismatch: string) [
    ("throw 1", "int", "NL202:TypeMismatch@2:11+1;", "TypeMismatch|Throw expressions must be assignable to System.Exception, but this expression is 'int'|Throw an Exception-derived value, or wrap this value in an exception type.|Error", "NL202@2:11+1", "NL202:TypeMismatch@2:11+1;", "NL202@2:11+1"),
    ("throw \"bad\"", "string", "NL202:TypeMismatch@2:11+1;", "TypeMismatch|Throw expressions must be assignable to System.Exception, but this expression is 'string'|Throw an Exception-derived value, or wrap this value in an exception type.|Error", "NL202@2:11+1", "NL202:TypeMismatch@2:11+5;", "NL202@2:11+5"),
    ("value: object = \"bad\"\n                throw value", "object", "NL202:TypeMismatch@3:23+5;", "TypeMismatch|Throw expressions must be assignable to System.Exception, but this expression is 'object'|Throw an Exception-derived value, or wrap this value in an exception type.|Error", "NL202@3:23+5", "NL202:TypeMismatch@3:23+5;", "NL202@3:23+5")
] {
    source := "func Main() {\n    " + statement + "\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == richCodeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains("'" + operandType + "'")
}

test "020 s31 analyzer error codes: reading an error-tuple result after an error branch that does NOT return is ONE `NL314:UnverifiedErrorResult` on the RESULT NAME `i` inside the interpolation at 14:38, one column wide, and the suggestion spells both the guard and the early-return escape (was AnalyzerTests.ErrorTupleResultUseAfterNonReturningErrorBranch_IsRejected)" {
    source := "\n            import System\n\n            func Hi(): int {\n                throw new Exception(\"boom\")\n            }\n\n            func Main() {\n                i, err := Hi()\n                if err != null {\n                    print err\n                }\n\n                print $\"hi returned {i}\"\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL314:UnverifiedErrorResult@14:38+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "UnverifiedErrorResult") == 1
    assert AcCodeErrorCount(analysis, "UnverifiedErrorResult") == 1
    assert AcCodeRow(analysis, "UnverifiedErrorResult") == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcCodeAnchor(analysis, "UnverifiedErrorResult") == "NL314@14:38+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL314:UnverifiedErrorResult@14:38+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "UnverifiedErrorResult") == 1
    assert AcCodeErrorCount(rich, "UnverifiedErrorResult") == 1
    assert AcCodeRow(rich, "UnverifiedErrorResult") == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcCodeAnchor(rich, "UnverifiedErrorResult") == "NL314@14:38+1"
}

test "020 s31 analyzer error codes: reading an error-tuple result INSIDE the error branch is the same `NL314` sentence at a different anchor — 11:27, the `i` in the print — which is what separates this fixture from its sibling and what the deleted substring pair could not tell apart (was AnalyzerTests.ErrorTupleResultUseInsideErrorBranch_IsRejected)" {
    source := "\n            import System\n\n            func Hi(): int {\n                throw new Exception(\"boom\")\n            }\n\n            func Main() {\n                i, err := Hi()\n                if err != null {\n                    print i\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL314:UnverifiedErrorResult@11:27+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "UnverifiedErrorResult") == 1
    assert AcCodeErrorCount(analysis, "UnverifiedErrorResult") == 1
    assert AcCodeRow(analysis, "UnverifiedErrorResult") == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcCodeAnchor(analysis, "UnverifiedErrorResult") == "NL314@11:27+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL314:UnverifiedErrorResult@11:27+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "UnverifiedErrorResult") == 1
    assert AcCodeErrorCount(rich, "UnverifiedErrorResult") == 1
    assert AcCodeRow(rich, "UnverifiedErrorResult") == "UnverifiedErrorResult|Result 'i' may be unavailable because 'err' can be non-null|Use 'i' only after `if err == null`, or return/throw from an `if err != null` error branch before the result is used.|Error"
    assert AcCodeAnchor(rich, "UnverifiedErrorResult") == "NL314@11:27+1"
}

test "020 s31 analyzer error codes: discarding a `[MustUse]` FUNCTION result is ONE `NL315:DiscardedMustUseResult` underlining the whole callee name `Compute` at 8:17, seven columns, with a suggestion that names `_ = ...` as the explicit discard (was AnalyzerTests.DiscardedMustUseFunctionResult_IsRejected)" {
    source := "\n            [MustUse]\n            func Compute(): int {\n                return 42\n            }\n\n            func Main() {\n                Compute()\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL315:DiscardedMustUseResult@8:17+7;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeRow(analysis, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(analysis, "DiscardedMustUseResult") == "NL315@8:17+7"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL315:DiscardedMustUseResult@8:17+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeRow(rich, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(rich, "DiscardedMustUseResult") == "NL315@8:17+7"
}

test "020 s31 analyzer error codes: discarding a `[MustUse]` METHOD result anchors on the member name `Add` at 11:19 — three columns, the receiver and the dot OUTSIDE the underline (was AnalyzerTests.DiscardedMustUseMethodResult_IsRejected)" {
    source := "\n            class Calc {\n                [MustUse]\n                func Add(a: int, b: int): int {\n                    return a + b\n                }\n            }\n\n            func Main() {\n                let c := new Calc()\n                c.Add(1, 2)\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL315:DiscardedMustUseResult@11:19+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DiscardedMustUseResult|You're discarding the result of 'Add', but 'Add' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeRow(analysis, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Add', but 'Add' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(analysis, "DiscardedMustUseResult") == "NL315@11:19+3"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL315:DiscardedMustUseResult@11:19+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "DiscardedMustUseResult|You're discarding the result of 'Add', but 'Add' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeRow(rich, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Add', but 'Add' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(rich, "DiscardedMustUseResult") == "NL315@11:19+3"
}

test "020 s31 analyzer error codes: discarding the result of a `[MustUse]` OVERLOAD reports once, not once per candidate, and anchors on `Compute` at 12:17 (was AnalyzerTests.DiscardedMustUseSelectedOverload_IsRejected)" {
    source := "\n            [MustUse]\n            func Compute(): int {\n                return 42\n            }\n\n            func Compute(value: int): int {\n                return value\n            }\n\n            func Main() {\n                Compute()\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL315:DiscardedMustUseResult@12:17+7;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeRow(analysis, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(analysis, "DiscardedMustUseResult") == "NL315@12:17+7"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL315:DiscardedMustUseResult@12:17+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeRow(rich, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(rich, "DiscardedMustUseResult") == "NL315@12:17+7"
}

test "020 s31 analyzer error codes: a bare call to an undeclared function is `NL412:UndefinedFunction` and NOT `NL301:UndefinedVariable` — the deleted method could only say the message lacked a word; here the code itself is pinned, the row carries NO suggestion at all, and the RICH route adds a `ContextualHint` the plain route leaves null (was AnalyzerTests.UndefinedBareCall_ReportsFunctionError)" {
    source := "\n            func Main() {\n                i := Hi()\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL412:UndefinedFunction@3:22+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedFunction|Function 'Hi' not found|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "UndefinedFunction") == 1
    assert AcCodeErrorCount(analysis, "UndefinedFunction") == 1
    assert AcCodeRow(analysis, "UndefinedFunction") == "UndefinedFunction|Function 'Hi' not found|<null>|Error"
    assert AcCodeAnchor(analysis, "UndefinedFunction") == "NL412@3:22+2"
    assert AcCodeCount(analysis, "UndefinedVariable") == 0
    assert AcCodeErrorCount(analysis, "UndefinedVariable") == 0
    assert AcCodeRow(analysis, "UndefinedVariable") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL412:UndefinedFunction@3:22+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "UndefinedFunction|Function 'Hi' not found|<null>|Error"
    assert AcHint(rich, 0) == "Define `func Hi(...)` before calling it, or import the function if it lives elsewhere."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "UndefinedFunction") == 1
    assert AcCodeErrorCount(rich, "UndefinedFunction") == 1
    assert AcCodeRow(rich, "UndefinedFunction") == "UndefinedFunction|Function 'Hi' not found|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedFunction") == "NL412@3:22+2"
    assert AcCodeCount(rich, "UndefinedVariable") == 0
    assert AcCodeErrorCount(rich, "UndefinedVariable") == 0
    assert AcCodeRow(rich, "UndefinedVariable") == "<no-such-code>"
}

test "020 s31 analyzer error codes: a generator that returns a value is `NL103`, once for `func*` and once for `async func*`, and the two rows anchor at different columns because the declarations are different lengths (was AnalyzerTests.GeneratorReturnValue_ReportsInvalidSyntax, all 2 [InlineData] rows)" with (declaration: string, census: string, codeAnchorInvalidSyntax: string) [
    ("func* Numbers(): IEnumerable<int> { return 1 }", "NL103:InvalidSyntax@3:44+1;", "NL103@3:44+1"),
    ("async func* Numbers(): IAsyncEnumerable<int> { return 1 }", "NL103:InvalidSyntax@3:55+1;", "NL103@3:55+1")
] {
    source := "import System.Collections.Generic\n\n" + declaration
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|Generator functions cannot return a value|Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|Generator functions cannot return a value|Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|Generator functions cannot return a value|Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|Generator functions cannot return a value|Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == codeAnchorInvalidSyntax
}

test "020 s31 analyzer error codes: `yield` and `yield break` outside a generator both report `NL103` anchored on the `yield` KEYWORD at 2:5 — five columns for both rows, so `break` is outside the underline (was AnalyzerTests.YieldOutsideGenerator_ReportsInvalidSyntax, all 2 [InlineData] rows)" with (statement: string) [
    ("yield 1"),
    ("yield break")
] {
    source := "func Main() {\n    " + statement + "\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@2:5+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|'yield' can only be used inside a generator function|Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|'yield' can only be used inside a generator function|Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@2:5+5"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@2:5+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|'yield' can only be used inside a generator function|Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|'yield' can only be used inside a generator function|Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@2:5+5"
}

test "020 s31 analyzer error codes: a generator whose return type is not a sequence is `NL202`, six rows over both `func*` and `async func*`, and the anchor LENGTH tracks the spelled return type — 3 for `int`, 5 for `int[]`, 16 for `IEnumerator<int>`, 21 for `IAsyncEnumerable<int>` — while the suggestion switches between `IEnumerable<T>` and `IAsyncEnumerable<T>` with the generator kind (was AnalyzerTests.GeneratorNonSequenceReturnType_ReportsTypeMismatch, all 6 [InlineData] rows)" with (declaration: string, returnType: string, expectedSequenceKind: string, expectedSuggestion: string, census: string, row0: string, codeAnchorTypeMismatch: string) [
    ("func* Numbers(): int { yield 1 }", "int", "synchronous enumerable", "IEnumerable<T>", "NL202:TypeMismatch@3:18+3;", "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'int'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error", "NL202@3:18+3"),
    ("func* Numbers(): int[] { yield 1 }", "int[]", "synchronous enumerable", "IEnumerable<T>", "NL202:TypeMismatch@3:18+5;", "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'int[]'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error", "NL202@3:18+5"),
    ("func* Numbers(): IEnumerator<int> { yield 1 }", "IEnumerator", "synchronous enumerable", "IEnumerable<T>", "NL202:TypeMismatch@3:18+16;", "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'IEnumerator<int>'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error", "NL202@3:18+16"),
    ("func* Numbers(): IAsyncEnumerable<int> { yield 1 }", "IAsyncEnumerable", "synchronous enumerable", "IEnumerable<T>", "NL202:TypeMismatch@3:18+21;", "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'IAsyncEnumerable<int>'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error", "NL202@3:18+21"),
    ("async func* Numbers(): int { yield 1 }", "int", "async enumerable", "IAsyncEnumerable<T>", "NL202:TypeMismatch@3:24+3;", "TypeMismatch|Generator function 'Numbers' must return an async enumerable sequence type, but it returns 'int'|Use `IAsyncEnumerable<T>` for `async func*`.|Error", "NL202@3:24+3"),
    ("async func* Numbers(): IEnumerable<int> { yield 1 }", "IEnumerable", "async enumerable", "IAsyncEnumerable<T>", "NL202:TypeMismatch@3:24+16;", "TypeMismatch|Generator function 'Numbers' must return an async enumerable sequence type, but it returns 'IEnumerable<int>'|Use `IAsyncEnumerable<T>` for `async func*`.|Error", "NL202@3:24+16")
] {
    source := "import System.Collections.Generic\n\n" + declaration
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == codeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains(expectedSequenceKind)
    assert AcRow(rich, 0).Contains(returnType)
    assert AcRow(rich, 0).Contains(expectedSuggestion)
}

test "020 s31 analyzer error codes: a yielded value that does not match the sequence element type is `NL202` naming both types, and the two rows split on the routes: the `int` yield agrees, the string-literal yield is one column plain and five rich (was AnalyzerTests.GeneratorYieldValueTypeMismatch_ReportsTypeMismatch, all 2 [InlineData] rows)" with (declaration: string, yieldedType: string, elementType: string, census: string, row0: string, codeAnchorTypeMismatch: string, richCensus: string, richCodeAnchorTypeMismatch: string) [
    ("func* Numbers(): IEnumerable<string> { yield 1 }", "int", "string", "NL202:TypeMismatch@3:46+1;", "TypeMismatch|Generator yield value is 'int', but the sequence element type is 'string'|Yield a value assignable to 'string', or change the generator return type.|Error", "NL202@3:46+1", "NL202:TypeMismatch@3:46+1;", "NL202@3:46+1"),
    ("async func* Numbers(): IAsyncEnumerable<int> { yield \"bad\" }", "string", "int", "NL202:TypeMismatch@3:54+1;", "TypeMismatch|Generator yield value is 'string', but the sequence element type is 'int'|Yield a value assignable to 'int', or change the generator return type.|Error", "NL202@3:54+1", "NL202:TypeMismatch@3:54+5;", "NL202@3:54+5")
] {
    source := "import System.Collections.Generic\n\n" + declaration
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == richCodeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains("yield value is '" + yieldedType + "'")
    assert AcRow(rich, 0).Contains("sequence element type is '" + elementType + "'")
    assert AcRow(rich, 0).Contains("assignable to '" + elementType + "'")
}

test "020 s31 analyzer error codes: a LOCAL generator with a non-sequence return type reports the same `NL202` sentence as a top-level one, at 2:22 (was AnalyzerTests.LocalGeneratorNonSequenceReturnType_ReportsTypeMismatch)" {
    source := "func Main() {\n    func* Numbers(): int {\n        yield 1\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@2:22+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'int'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'int'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@2:22+3"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@2:22+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'int'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Generator function 'Numbers' must return a synchronous enumerable sequence type, but it returns 'int'|Use `IEnumerable<T>`, `IReadOnlyList<T>`, or `List<T>` for `func*`.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@2:22+3"
}

test "020 s31 analyzer error codes: a generator with an expression body is `NL103` and NOT `NL202` — the absence is discriminating here, because the fixture does report a code, and the census names it (was AnalyzerTests.GeneratorExpressionBody_ReportsInvalidSyntax, all 2 [InlineData] rows)" with (declaration: string, census: string, codeAnchorInvalidSyntax: string) [
    ("func* Numbers(): IEnumerable<int> => []", "NL103:InvalidSyntax@3:38+1;", "NL103@3:38+1"),
    ("async func* Numbers(): IAsyncEnumerable<int> => []", "NL103:InvalidSyntax@3:49+1;", "NL103@3:49+1")
] {
    source := "import System.Collections.Generic\n\n" + declaration
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == codeAnchorInvalidSyntax
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s31 analyzer error codes: a LOCAL generator with an expression body reports the same `NL103` at 4:42, with `NL202` absent from a NON-empty census (was AnalyzerTests.LocalGeneratorExpressionBody_ReportsInvalidSyntax)" {
    source := "import System.Collections.Generic\n\nfunc Main() {\n    func* Numbers(): IEnumerable<int> => []\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@4:42+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@4:42+1"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@4:42+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|Generator functions must use a block body|Use `{ yield value }` to produce sequence values from a generator.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@4:42+1"
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s31 analyzer error codes: a for-loop iterator with no effect is `NL313` — and this fixture is where all three of the routes' divergences appear at once: the anchor is one column plain and five rich, the SUGGESTION is rewritten (`Use an assignment, call, increment ...` against `Use an assignment such as `i = i + 1` ...`), and the `ContextualHint` exists only on the production route (was AnalyzerTests.ForIteratorMustHaveStatementEffect)" {
    source := "func Main() {\n    for i := 0; i < 3; i + 1 {\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL313:InvalidExpressionStatement@2:26+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidExpressionStatement|This for-loop iterator has no effect|Use an assignment, call, increment, decrement, await expression, or object construction in the iterator clause, or remove the iterator.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidExpressionStatement") == 1
    assert AcCodeErrorCount(analysis, "InvalidExpressionStatement") == 1
    assert AcCodeRow(analysis, "InvalidExpressionStatement") == "InvalidExpressionStatement|This for-loop iterator has no effect|Use an assignment, call, increment, decrement, await expression, or object construction in the iterator clause, or remove the iterator.|Error"
    assert AcCodeAnchor(analysis, "InvalidExpressionStatement") == "NL313@2:26+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL313:InvalidExpressionStatement@2:26+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidExpressionStatement|This for-loop iterator has no effect|Use an assignment such as `i = i + 1`, an increment/decrement such as `i++`, a side-effecting call, or remove the iterator.|Error"
    assert AcHint(rich, 0) == "The expression `binary expression` produces a value or names a member, but the value is ignored.\nOnly assignments, calls, increments, decrements, await expressions, and object construction can be used as for-loop iterators."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidExpressionStatement") == 1
    assert AcCodeErrorCount(rich, "InvalidExpressionStatement") == 1
    assert AcCodeRow(rich, "InvalidExpressionStatement") == "InvalidExpressionStatement|This for-loop iterator has no effect|Use an assignment such as `i = i + 1`, an increment/decrement such as `i++`, a side-effecting call, or remove the iterator.|Error"
    assert AcCodeAnchor(rich, "InvalidExpressionStatement") == "NL313@2:26+5"
}

test "020 s31 analyzer error codes: a `[MustUse]` call in a for-loop ITERATOR clause is still `NL315`, anchored on `Next` at 7:24 (was AnalyzerTests.ForIteratorDiscardedMustUseCall_IsRejected)" {
    source := "[MustUse]\nfunc Next(): int {\n    return 1\n}\n\nfunc Main() {\n    for i := 0; i < 3; Next() {\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL315:DiscardedMustUseResult@7:24+4;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "DiscardedMustUseResult|You're discarding the result of 'Next', but 'Next' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(analysis, "DiscardedMustUseResult") == 1
    assert AcCodeRow(analysis, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Next', but 'Next' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(analysis, "DiscardedMustUseResult") == "NL315@7:24+4"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL315:DiscardedMustUseResult@7:24+4;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "DiscardedMustUseResult|You're discarding the result of 'Next', but 'Next' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeErrorCount(rich, "DiscardedMustUseResult") == 1
    assert AcCodeRow(rich, "DiscardedMustUseResult") == "DiscardedMustUseResult|You're discarding the result of 'Next', but 'Next' is marked [MustUse] — its result must be used|Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.|Error"
    assert AcCodeAnchor(rich, "DiscardedMustUseResult") == "NL315@7:24+4"
}

test "020 s31 analyzer error codes: a bare member access used as a statement is `NL411:MethodGroupUsedAsValue` underlining the WHOLE dotted path `greeting.CompareTo`, eighteen columns at 4:17, and the production route rewrites the suggestion into two sentences the plain route states as one (was AnalyzerTests.ExpressionStatement_BareMemberAccess_MethodGroupUsedAsValue)" {
    source := "\n            func Main() {\n                greeting := \"hello\"\n                greeting.CompareTo\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL411:MethodGroupUsedAsValue@4:17+18;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MethodGroupUsedAsValue|Method 'CompareTo' must be called or passed to a delegate|Call `CompareTo(...)`, or pass `CompareTo` to a parameter with a delegate type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(analysis, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'CompareTo' must be called or passed to a delegate|Call `CompareTo(...)`, or pass `CompareTo` to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(analysis, "MethodGroupUsedAsValue") == "NL411@4:17+18"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL411:MethodGroupUsedAsValue@4:17+18;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "MethodGroupUsedAsValue|Method 'CompareTo' must be called or passed to a delegate|If you meant to use the result, call `CompareTo(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcHint(rich, 0) == "Methods need a call site like `name()` before they produce a value.\nA bare method name is only valid when the surrounding API expects a delegate."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(rich, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'CompareTo' must be called or passed to a delegate|If you meant to use the result, call `CompareTo(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(rich, "MethodGroupUsedAsValue") == "NL411@4:17+18"
}

test "020 s31 analyzer error codes: a non-side-effecting expression statement is `NL313`, one column plain against three rich, and the production route adds a hint naming the expression KIND (was AnalyzerTests.ExpressionStatement_NonSideEffectingValue_Error)" {
    source := "\n            func Main() {\n                value := 41\n                value + 1\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL313:InvalidExpressionStatement@4:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidExpressionStatement|This expression statement has no effect|Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidExpressionStatement") == 1
    assert AcCodeErrorCount(analysis, "InvalidExpressionStatement") == 1
    assert AcCodeRow(analysis, "InvalidExpressionStatement") == "InvalidExpressionStatement|This expression statement has no effect|Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.|Error"
    assert AcCodeAnchor(analysis, "InvalidExpressionStatement") == "NL313@4:23+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL313:InvalidExpressionStatement@4:23+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidExpressionStatement|This expression statement has no effect|Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.|Error"
    assert AcHint(rich, 0) == "The expression `binary expression` produces a value or names a member, but the value is ignored.\nOnly assignments, calls, increments, decrements, await expressions, and object construction can be used as statements."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidExpressionStatement") == 1
    assert AcCodeErrorCount(rich, "InvalidExpressionStatement") == 1
    assert AcCodeRow(rich, "InvalidExpressionStatement") == "InvalidExpressionStatement|This expression statement has no effect|Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.|Error"
    assert AcCodeAnchor(rich, "InvalidExpressionStatement") == "NL313@4:23+3"
}

test "020 s31 analyzer error codes: printing a method group is `NL411` anchored on `ToString` at 3:31 — and the deleted method is the tranche's ONLY reader of `ContextualHint` through a predicate, a field that is null on the plain route and a full sentence on the production one (was AnalyzerTests.MethodGroupUsedAsPrintValue_Error)" {
    source := "\n            func Main() {\n                print \"hello\".ToString\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL411:MethodGroupUsedAsValue@3:31+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(analysis, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(analysis, "MethodGroupUsedAsValue") == "NL411@3:31+8"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL411:MethodGroupUsedAsValue@3:31+8;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcHint(rich, 0) == "Methods need a call site like `name()` before they produce a value.\nA bare method name is only valid when the surrounding API expects a delegate."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(rich, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(rich, "MethodGroupUsedAsValue") == "NL411@3:31+8"
}

test "020 s31 analyzer error codes: binding a method group to an inferred local is `NL411` at 3:34 (was AnalyzerTests.MethodGroupUsedAsInferredVariableValue_Error)" {
    source := "\n            func Main() {\n                value := \"hello\".ToString\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL411:MethodGroupUsedAsValue@3:34+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(analysis, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(analysis, "MethodGroupUsedAsValue") == "NL411@3:34+8"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL411:MethodGroupUsedAsValue@3:34+8;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcHint(rich, 0) == "Methods need a call site like `name()` before they produce a value.\nA bare method name is only valid when the surrounding API expects a delegate."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(rich, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(rich, "MethodGroupUsedAsValue") == "NL411@3:34+8"
}

test "020 s31 analyzer error codes: a method group as a bare expression statement is `NL411` at 3:25 (was AnalyzerTests.MethodGroupUsedAsExpressionStatement_Error)" {
    source := "\n            func Main() {\n                \"hello\".ToString\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL411:MethodGroupUsedAsValue@3:25+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(analysis, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(analysis, "MethodGroupUsedAsValue") == "NL411@3:25+8"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL411:MethodGroupUsedAsValue@3:25+8;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcHint(rich, 0) == "Methods need a call site like `name()` before they produce a value.\nA bare method name is only valid when the surrounding API expects a delegate."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(rich, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(rich, "MethodGroupUsedAsValue") == "NL411@3:25+8"
}

test "020 s31 analyzer error codes: a method group passed where an `object` is expected is `NL411` at 7:29 — the method group loses to the parameter type rather than being boxed (was AnalyzerTests.MethodGroupUsedAsObjectArgument_Error)" {
    source := "\n            func Use(value: object) {\n                print value\n            }\n\n            func Main() {\n                Use(\"hello\".ToString)\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL411:MethodGroupUsedAsValue@7:29+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(analysis, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(analysis, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|Call `ToString(...)`, or pass `ToString` to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(analysis, "MethodGroupUsedAsValue") == "NL411@7:29+8"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL411:MethodGroupUsedAsValue@7:29+8;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcHint(rich, 0) == "Methods need a call site like `name()` before they produce a value.\nA bare method name is only valid when the surrounding API expects a delegate."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeErrorCount(rich, "MethodGroupUsedAsValue") == 1
    assert AcCodeRow(rich, "MethodGroupUsedAsValue") == "MethodGroupUsedAsValue|Method 'ToString' must be called or passed to a delegate|If you meant to use the result, call `ToString(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.|Error"
    assert AcCodeAnchor(rich, "MethodGroupUsedAsValue") == "NL411@7:29+8"
}

test "020 s31 analyzer error codes: reading `.Count` off a `List<T>` of an N# type is NOT a method group, and the whole analysis is SILENT — the deleted `DoesNotContain` asserted one code was absent from a list that is EMPTY, so it was VACUOUS; the empty census, the zero error count and `<no-such-error>` at index 0 are not (was AnalyzerTests.GenericListOfNSharpType_CountProperty_IsNotMethodGroup)" {
    source := "\n            import System.Collections.Generic\n\n            class TaskItem {\n                Name: string\n            }\n\n            func Main() {\n                tasks := new List<TaskItem>()\n                total := tasks.Count\n                print total\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "MethodGroupUsedAsValue") == 0
    assert AcCodeErrorCount(analysis, "MethodGroupUsedAsValue") == 0
    assert AcCodeRow(analysis, "MethodGroupUsedAsValue") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
    assert AcCodeCount(rich, "MethodGroupUsedAsValue") == 0
    assert AcCodeErrorCount(rich, "MethodGroupUsedAsValue") == 0
    assert AcCodeRow(rich, "MethodGroupUsedAsValue") == "<no-such-code>"
}

test "020 s31 analyzer error codes: `++` on a string is `NL202` naming the operator and the operand type, anchored on the two `++` columns at 4:22 (was AnalyzerTests.Increment_NonIntegralOperand_Error)" {
    source := "\n            func Main() {\n                value := \"hello\"\n                value++\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:22+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '++' operator doesn't work with 'string' — the operand needs an integral numeric value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '++' operator doesn't work with 'string' — the operand needs an integral numeric value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@4:22+2"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:22+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|The '++' operator doesn't work with 'string' — the operand needs an integral numeric value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '++' operator doesn't work with 'string' — the operand needs an integral numeric value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@4:22+2"
}

test "020 s31 analyzer error codes: `++` on a non-assignable target is `NL103`, not `NL202` — a different code for a different defect in the same operator (was AnalyzerTests.Increment_NonAssignableTarget_Error)" {
    source := "\n            func Main() {\n                1++\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@3:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|The '++' operator needs an assignable target|Use a variable, field, property, or indexed element as the operand.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|The '++' operator needs an assignable target|Use a variable, field, property, or indexed element as the operand.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@3:17+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@3:17+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|The '++' operator needs an assignable target|Use a variable, field, property, or indexed element as the operand.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|The '++' operator needs an assignable target|Use a variable, field, property, or indexed element as the operand.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@3:17+1"
}

test "020 s31 analyzer error codes: writing a read-only RUNTIME property is `NL103` naming the property and the operator, three rows for `=`, `+=` and `++`, all anchored on the property NAME at 3:14 — and the sentence's verb changes with the operator, `assigned with` for the first two and `changed with` for `++` (was AnalyzerTests.Write_ReadOnlyRuntimePropertyTarget_Error, all 3 [InlineData] rows)" with (statement: string, propertyName: string, op: string, row0: string) [
    ("text.Length = 2", "Length", "=", "InvalidSyntax|Property 'Length' is read-only — it can't be assigned with '='|Use a variable, field, settable property, or indexed element as the target.|Error"),
    ("text.Length += 1", "Length", "+=", "InvalidSyntax|Property 'Length' is read-only — it can't be assigned with '+='|Use a variable, field, settable property, or indexed element as the target.|Error"),
    ("text.Length++", "Length", "++", "InvalidSyntax|Property 'Length' is read-only — it can't be changed with '++'|Use a variable, field, settable property, or indexed element as the target.|Error")
] {
    source := "    func Main() {\n        text := \"abc\"\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@3:14+6;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@3:14+6"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@3:14+6;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@3:14+6"
    assert AcRow(rich, 0).Contains("Property '" + propertyName + "' is read-only")
    assert AcRow(rich, 0).Contains("'" + op + "'")
}

test "020 s31 analyzer error codes: the same rule on a SOURCE-declared property anchors on `Value` at 15:19 and carries the same verb split across its three rows (was AnalyzerTests.Write_ReadOnlySourcePropertyTarget_Error, all 3 [InlineData] rows)" with (statement: string, propertyName: string, op: string, census: string, row0: string, codeAnchorInvalidSyntax: string) [
    ("other.Value = 2", "Value", "=", "NL103:InvalidSyntax@15:19+5;", "InvalidSyntax|Property 'Value' is read-only — it can't be assigned with '='|Use a variable, field, settable property, or indexed element as the target.|Error", "NL103@15:19+5"),
    ("other.Value++", "Value", "++", "NL103:InvalidSyntax@15:19+5;", "InvalidSyntax|Property 'Value' is read-only — it can't be changed with '++'|Use a variable, field, settable property, or indexed element as the target.|Error", "NL103@15:19+5"),
    ("Value = 2", "Value", "=", "NL103:InvalidSyntax@15:13+5;", "InvalidSyntax|Property 'Value' is read-only — it can't be assigned with '='|Use a variable, field, settable property, or indexed element as the target.|Error", "NL103@15:13+5")
] {
    source := "    class Box {\n        backing: int\n\n        Value: int {\n            get {\n                return backing\n            }\n        }\n\n        constructor() {\n            backing = 0\n        }\n\n        func Mutate(other: Box) {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == codeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains("Property '" + propertyName + "' is read-only")
    assert AcRow(rich, 0).Contains("'" + op + "'")
}

test "020 s31 analyzer error codes: assigning to a non-assignable target is `NL103` naming `'='`, three rows over a literal, a call result and a parenthesized value (was AnalyzerTests.Assignment_NonAssignableTarget_Error, all 3 [InlineData] rows)" with (statement: string, op: string, census: string, row0: string, codeAnchorInvalidSyntax: string) [
    ("(1 + 2) = 3", "=", "NL103:InvalidSyntax@3:12+1;", "InvalidSyntax|The '=' assignment needs an assignable target|Use a variable, field, property, indexed element, or `_` discard as the left side.|Error", "NL103@3:12+1"),
    ("checked(value) = 2", "=", "NL103:InvalidSyntax@3:17+5;", "InvalidSyntax|The '=' assignment needs an assignable target|Use a variable, field, property, indexed element, or `_` discard as the left side.|Error", "NL103@3:17+5"),
    ("unchecked(value) += 2", "+=", "NL103:InvalidSyntax@3:19+5;", "InvalidSyntax|The '+=' assignment needs an assignable target|Use a variable, field, property, indexed element, or `_` discard as the left side.|Error", "NL103@3:19+5")
] {
    source := "    func Main() {\n        value := 1\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == codeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains("'" + op + "' assignment needs an assignable target")
}

test "020 s31 analyzer error codes: a null-conditional WRITE target is `NL103`, and this is the tranche's widest table — twelve rows spanning member access and index access across `=`, `+=`, `++`, `ref` and `out`, with the message built from a target KIND and an ACTION that both stay load-bearing per row, and four of the twelve rows anchor one column on the plain route against three on the production route (was AnalyzerTests.Write_NullConditionalTarget_Error, all 12 [InlineData] rows)" with (statement: string, targetKind: string, action: string, census: string, row0: string, codeAnchorInvalidSyntax: string, richCensus: string, richCodeAnchorInvalidSyntax: string) [
    ("box?.Value = 1", "member access", "assigned with '='", "NL103:InvalidSyntax@27:14+5;", "InvalidSyntax|Null-conditional member access can't be assigned with '='|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+5", "NL103:InvalidSyntax@27:14+5;", "NL103@27:14+5"),
    ("box?.Next.Value = 1", "member access", "assigned with '='", "NL103:InvalidSyntax@27:14+4;", "InvalidSyntax|Null-conditional member access can't be assigned with '='|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+4", "NL103:InvalidSyntax@27:14+4;", "NL103@27:14+4"),
    ("box?.Value += 1", "member access", "assigned with '+='", "NL103:InvalidSyntax@27:14+5;", "InvalidSyntax|Null-conditional member access can't be assigned with '+='|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+5", "NL103:InvalidSyntax@27:14+5;", "NL103@27:14+5"),
    ("box?.Value++", "member access", "changed with '++'", "NL103:InvalidSyntax@27:14+5;", "InvalidSyntax|Null-conditional member access can't be changed with '++'|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+5", "NL103:InvalidSyntax@27:14+5;", "NL103@27:14+5"),
    ("box?.Next.Value++", "member access", "changed with '++'", "NL103:InvalidSyntax@27:14+4;", "InvalidSyntax|Null-conditional member access can't be changed with '++'|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+4", "NL103:InvalidSyntax@27:14+4;", "NL103@27:14+4"),
    ("items?[0] = 1", "index access", "assigned with '='", "NL103:InvalidSyntax@27:14+1;", "InvalidSyntax|Null-conditional index access can't be assigned with '='|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+1", "NL103:InvalidSyntax@27:14+3;", "NL103@27:14+3"),
    ("matrix?[0][1] = 1", "index access", "assigned with '='", "NL103:InvalidSyntax@27:15+1;", "InvalidSyntax|Null-conditional index access can't be assigned with '='|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:15+1", "NL103:InvalidSyntax@27:15+3;", "NL103@27:15+3"),
    ("items?[0]++", "index access", "changed with '++'", "NL103:InvalidSyntax@27:14+1;", "InvalidSyntax|Null-conditional index access can't be changed with '++'|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:14+1", "NL103:InvalidSyntax@27:14+3;", "NL103@27:14+3"),
    ("bump(ref box?.Value)", "member access", "used as the ref argument", "NL103:InvalidSyntax@27:23+5;", "InvalidSyntax|Null-conditional member access can't be used as the ref argument|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:23+5", "NL103:InvalidSyntax@27:23+5;", "NL103@27:23+5"),
    ("bump(ref box?.Next.Value)", "member access", "used as the ref argument", "NL103:InvalidSyntax@27:23+4;", "InvalidSyntax|Null-conditional member access can't be used as the ref argument|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:23+4", "NL103:InvalidSyntax@27:23+4;", "NL103@27:23+4"),
    ("bump(ref items?[0])", "index access", "used as the ref argument", "NL103:InvalidSyntax@27:23+1;", "InvalidSyntax|Null-conditional index access can't be used as the ref argument|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:23+1", "NL103:InvalidSyntax@27:23+3;", "NL103@27:23+3"),
    ("reset(out box?.Value)", "member access", "used as the out argument", "NL103:InvalidSyntax@27:24+5;", "InvalidSyntax|Null-conditional member access can't be used as the out argument|Store the receiver in a local, guard it for null, then write through a normal member or index target.|Error", "NL103@27:24+5", "NL103:InvalidSyntax@27:24+5;", "NL103@27:24+5")
] {
    source := "    class Box {\n        backing: int\n\n        Value: int {\n            get {\n                return backing\n            }\n            set {\n                backing = value\n            }\n        }\n\n        constructor() {\n            backing = 0\n        }\n    }\n\n    func bump(ref value: int) {\n        value += 1\n    }\n\n    func reset(out value: int) {\n        value = 0\n    }\n\n    func Main(box: Box?, items: int[]?, matrix: int[][]?) {\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == richCodeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains("Null-conditional " + targetKind + " can't be " + action)
}

test "020 s31 analyzer error codes: a `checked`/`unchecked` operand as a `ref` or `out` argument is `NL103` naming the modifier in BOTH the message and the suggestion (was AnalyzerTests.RefOutArgument_NonAssignableTarget_Error, all 2 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorInvalidSyntax: string) [
    ("update(ref checked(value), out copy)", "ref", "NL103:InvalidSyntax@9:28+5;", "InvalidSyntax|The 'ref' argument needs an assignable target|Use a variable, field, or indexed array/SoA column element as the ref argument.|Error", "NL103@9:28+5"),
    ("update(ref value, out unchecked(copy))", "out", "NL103:InvalidSyntax@9:41+4;", "InvalidSyntax|The 'out' argument needs an assignable target|Use a variable, field, or indexed array/SoA column element as the out argument.|Error", "NL103@9:41+4")
] {
    source := "    func update(ref value: int, out copy: int) {\n        copy = value\n        value += 1\n    }\n\n    func Main() {\n        value := 1\n        copy := 0\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == codeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains("'" + modifier + "' argument needs an assignable target")
    assert AcRow(rich, 0).Contains("as the " + modifier + " argument")
}

test "020 s31 analyzer error codes: non-addressable CLR targets as `ref`/`out` arguments are `NL103`, three rows, and one of them splits the routes one column against two (was AnalyzerTests.RefOutArgument_NonAddressableClrTargets_Error, all 3 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorInvalidSyntax: string, richCensus: string, richCodeAnchorInvalidSyntax: string) [
    ("if Int32.TryParse(\"42\", out checked(result)) { }", "out", "NL103:InvalidSyntax@12:45+6;", "InvalidSyntax|The 'out' argument needs an assignable target|Use a variable, field, or indexed array/SoA column element as the out argument.|Error", "NL103@12:45+6", "NL103:InvalidSyntax@12:45+6;", "NL103@12:45+6"),
    ("Int32.TryParse(\"42\", out text.Length)", "out", "NL103:InvalidSyntax@12:34+11;", "InvalidSyntax|The 'out' argument needs an assignable target|Use a variable, field, or indexed array/SoA column element as the out argument.|Error", "NL103@12:34+11", "NL103:InvalidSyntax@12:34+11;", "NL103@12:34+11"),
    ("update(ref items[0])", "ref", "NL103:InvalidSyntax@12:25+1;", "InvalidSyntax|The 'ref' argument needs an assignable target|Use a variable, field, or indexed array/SoA column element as the ref argument.|Error", "NL103@12:25+1", "NL103:InvalidSyntax@12:25+2;", "NL103@12:25+2")
] {
    source := "    import System\n    import System.Collections.Generic\n\n    func update(ref value: int) {\n        value += 1\n    }\n\n    func Main() {\n        result := 0\n        text := \"abc\"\n        items := new List<int>()\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == richCodeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains("'" + modifier + "' argument needs an assignable target")
    assert AcRow(rich, 0).Contains("as the " + modifier + " argument")
}

test "020 s31 analyzer error codes: an array RANGE SLICE as a `ref` argument is its own `NL103` sentence, one column plain against five rich (was AnalyzerTests.RefOutArgument_ArrayRangeSlice_Error)" {
    source := "    func update(ref values: int[]) {\n    }\n\n    func Main() {\n        values := [1, 2, 3]\n        update(ref values[0..1])\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@6:26+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|Array slices cannot be used as the ref argument|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|Array slices cannot be used as the ref argument|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@6:26+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@6:26+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|Array slices cannot be used as the ref argument|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|Array slices cannot be used as the ref argument|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@6:26+5"
}

test "020 s31 analyzer error codes: `!` on an int is `NL202` naming the operator and demanding a boolean (was AnalyzerTests.LogicalNot_NonBoolOperand_Error)" {
    source := "\nfunc bad(value: int): bool {\n    return !value\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:12+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '!' operator doesn't work with 'int' — the operand needs a boolean value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '!' operator doesn't work with 'int' — the operand needs a boolean value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:12+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:12+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|The '!' operator doesn't work with 'int' — the operand needs a boolean value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '!' operator doesn't work with 'int' — the operand needs a boolean value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:12+1"
}

test "020 s31 analyzer error codes: five relational comparisons over incompatible operand pairs report FIVE separate `NL202` rows in ONE fixture, and the census pins all five with their anchors in order — the deleted method filtered the list and asserted a count and two substrings, and could not say which row was which (was AnalyzerTests.RelationalOperator_InvalidOperands_ReportTypeMismatch)" {
    source := "\nfunc BadString(): bool {\n    return \"a\" < \"b\"\n}\n\nfunc BadObject(value: object): bool {\n    return value > 0\n}\n\nfunc BadBool(left: bool, right: bool): bool {\n    return left <= right\n}\n\nfunc BadNullable(value: int?): bool {\n    return value >= 0\n}\n\nfunc BadMixed(left: ulong, right: long): bool {\n    return left < right\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:16+1;NL202:TypeMismatch@7:12+5;NL202:TypeMismatch@11:17+2;NL202:TypeMismatch@15:12+5;NL202:TypeMismatch@19:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 5
    assert AcRow(analysis, 0) == "TypeMismatch|The '<' operator doesn't work with 'string' and 'string' — both sides need primitive numeric values or a comparison operator overload, but I found 'string' and 'string'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "TypeMismatch|The '>' operator doesn't work with 'object' and 'int' — both sides need primitive numeric values or a comparison operator overload, but the left side is 'object'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 1) == "<null>"
    assert AcSuggestions(analysis, 1) == "<null>"
    assert AcRow(analysis, 2) == "TypeMismatch|The '<=' operator doesn't work with 'bool' and 'bool' — both sides need primitive numeric values or a comparison operator overload, but I found 'bool' and 'bool'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 2) == "<null>"
    assert AcSuggestions(analysis, 2) == "<null>"
    assert AcRow(analysis, 3) == "TypeMismatch|The '>=' operator doesn't work with 'int?' and 'int' — both sides need primitive numeric values or a comparison operator overload, but the left side is 'int?'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 3) == "<null>"
    assert AcSuggestions(analysis, 3) == "<null>"
    assert AcRow(analysis, 4) == "TypeMismatch|The '<' operator doesn't work with 'ulong' and 'long'|Use numeric operands with a compatible common type, or add an explicit conversion.|Error"
    assert AcHint(analysis, 4) == "<null>"
    assert AcSuggestions(analysis, 4) == "<null>"
    assert AcRow(analysis, 5) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 5
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 5
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '<' operator doesn't work with 'string' and 'string' — both sides need primitive numeric values or a comparison operator overload, but I found 'string' and 'string'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:16+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:16+1;NL202:TypeMismatch@7:12+5;NL202:TypeMismatch@11:17+2;NL202:TypeMismatch@15:12+5;NL202:TypeMismatch@19:17+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 5
    assert AcRow(rich, 0) == "TypeMismatch|The '<' operator doesn't work with 'string' and 'string' — both sides need primitive numeric values or a comparison operator overload, but I found 'string' and 'string'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "TypeMismatch|The '>' operator doesn't work with 'object' and 'int' — both sides need primitive numeric values or a comparison operator overload, but the left side is 'object'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 1) == "<null>"
    assert AcSuggestions(rich, 1) == "<null>"
    assert AcRow(rich, 2) == "TypeMismatch|The '<=' operator doesn't work with 'bool' and 'bool' — both sides need primitive numeric values or a comparison operator overload, but I found 'bool' and 'bool'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 2) == "<null>"
    assert AcSuggestions(rich, 2) == "<null>"
    assert AcRow(rich, 3) == "TypeMismatch|The '>=' operator doesn't work with 'int?' and 'int' — both sides need primitive numeric values or a comparison operator overload, but the left side is 'int?'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 3) == "<null>"
    assert AcSuggestions(rich, 3) == "<null>"
    assert AcRow(rich, 4) == "TypeMismatch|The '<' operator doesn't work with 'ulong' and 'long'|Use numeric operands with a compatible common type, or add an explicit conversion.|Error"
    assert AcHint(rich, 4) == "<null>"
    assert AcSuggestions(rich, 4) == "<null>"
    assert AcRow(rich, 5) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 5
    assert AcCodeErrorCount(rich, "TypeMismatch") == 5
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '<' operator doesn't work with 'string' and 'string' — both sides need primitive numeric values or a comparison operator overload, but I found 'string' and 'string'|Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:16+1"
}

test "020 s31 analyzer error codes: four equality comparisons report FOUR `NL202` rows in one fixture, each naming both sides, all anchored on the `==` operator itself (was AnalyzerTests.EqualityOperator_InvalidOperands_ReportTypeMismatch)" {
    source := "\nstruct Plain {\n    Value: int\n}\n\nfunc BadObjectInt(value: object): bool {\n    return value == 1\n}\n\nfunc BadPlain(left: Plain, right: Plain): bool {\n    return left == right\n}\n\nfunc BadNullable(left: int?, right: int?): bool {\n    return left != right\n}\n\nfunc BadMixedDecimal(left: decimal, right: int): bool {\n    return left == right\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@7:18+2;NL202:TypeMismatch@11:17+2;NL202:TypeMismatch@15:17+2;NL202:TypeMismatch@19:17+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 4
    assert AcRow(analysis, 0) == "TypeMismatch|The '==' operator doesn't work with 'object' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "TypeMismatch|The '==' operator doesn't work with 'Plain' and 'Plain' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(analysis, 1) == "<null>"
    assert AcSuggestions(analysis, 1) == "<null>"
    assert AcRow(analysis, 2) == "TypeMismatch|The '!=' operator doesn't work with 'int?' and 'int?' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(analysis, 2) == "<null>"
    assert AcSuggestions(analysis, 2) == "<null>"
    assert AcRow(analysis, 3) == "TypeMismatch|The '==' operator doesn't work with 'decimal' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(analysis, 3) == "<null>"
    assert AcSuggestions(analysis, 3) == "<null>"
    assert AcRow(analysis, 4) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 4
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 4
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '==' operator doesn't work with 'object' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@7:18+2"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@7:18+2;NL202:TypeMismatch@11:17+2;NL202:TypeMismatch@15:17+2;NL202:TypeMismatch@19:17+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 4
    assert AcRow(rich, 0) == "TypeMismatch|The '==' operator doesn't work with 'object' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "TypeMismatch|The '==' operator doesn't work with 'Plain' and 'Plain' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(rich, 1) == "<null>"
    assert AcSuggestions(rich, 1) == "<null>"
    assert AcRow(rich, 2) == "TypeMismatch|The '!=' operator doesn't work with 'int?' and 'int?' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(rich, 2) == "<null>"
    assert AcSuggestions(rich, 2) == "<null>"
    assert AcRow(rich, 3) == "TypeMismatch|The '==' operator doesn't work with 'decimal' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcHint(rich, 3) == "<null>"
    assert AcSuggestions(rich, 3) == "<null>"
    assert AcRow(rich, 4) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 4
    assert AcCodeErrorCount(rich, "TypeMismatch") == 4
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '==' operator doesn't work with 'object' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload|Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@7:18+2"
}

test "020 s31 analyzer error codes: an unknown operand under `&&`/`||` reports `NL301` ONCE and does not cascade into a type mismatch — and the two routes give two different SENTENCES for it, `I can't find 'missing' — it hasn't been declared in this scope` on the plain route against `Variable 'missing' not found` on the production one, plus one column against seven (was AnalyzerTests.LogicalOperators_UnknownOperand_DoesNotCascade)" {
    source := "\nfunc Main(flag: bool) {\n    if flag || missing {\n    }\n}\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL301:UndefinedVariable@3:16+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "UndefinedVariable|I can't find 'missing' — it hasn't been declared in this scope|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "UndefinedVariable") == 1
    assert AcCodeErrorCount(analysis, "UndefinedVariable") == 1
    assert AcCodeRow(analysis, "UndefinedVariable") == "UndefinedVariable|I can't find 'missing' — it hasn't been declared in this scope|<null>|Error"
    assert AcCodeAnchor(analysis, "UndefinedVariable") == "NL301@3:16+1"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL301:UndefinedVariable@3:16+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "UndefinedVariable|Variable 'missing' not found|<null>|Error"
    assert AcHint(rich, 0) == "Make sure you've declared this variable before using it."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "UndefinedVariable") == 1
    assert AcCodeErrorCount(rich, "UndefinedVariable") == 1
    assert AcCodeRow(rich, "UndefinedVariable") == "UndefinedVariable|Variable 'missing' not found|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedVariable") == "NL301@3:16+7"
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s31 analyzer error codes: a sized array allocation that also passes constructor arguments is ONE `NL321` anchored on the `new` KEYWORD at 7:27, three columns (was AnalyzerTests.SizedArrayAllocation_WithConstructorArguments_ReportsSemanticDiagnostic)" {
    source := "\n            func sideEffect(): int {\n                return 1\n            }\n\n            func Main() {\n                values := new int[4](sideEffect())\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL321:InvalidSizedArrayConstructorArguments@7:27+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeErrorCount(analysis, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeRow(analysis, "InvalidSizedArrayConstructorArguments") == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcCodeAnchor(analysis, "InvalidSizedArrayConstructorArguments") == "NL321@7:27+3"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL321:InvalidSizedArrayConstructorArguments@7:27+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeErrorCount(rich, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeRow(rich, "InvalidSizedArrayConstructorArguments") == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcCodeAnchor(rich, "InvalidSizedArrayConstructorArguments") == "NL321@7:27+3"
}

test "020 s31 analyzer error codes: the sized-array rejection does not stop argument analysis: TWO rows in one fixture, `NL301` for the undefined `missing` and `NL321` for the allocation, and the census pins them IN ORDER — and the two routes disagree about the width of the `NL301`, one column plain against the whole seven-character name rich (was AnalyzerTests.SizedArrayAllocation_WithConstructorArguments_StillAnalyzesArgumentExpressions)" {
    source := "\n            func Main() {\n                values := new int[4](missing)\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL301:UndefinedVariable@3:38+1;NL321:InvalidSizedArrayConstructorArguments@3:27+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 2
    assert AcRow(analysis, 0) == "UndefinedVariable|I can't find 'missing' — it hasn't been declared in this scope|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcHint(analysis, 1) == "<null>"
    assert AcSuggestions(analysis, 1) == "<null>"
    assert AcRow(analysis, 2) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeErrorCount(analysis, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeRow(analysis, "InvalidSizedArrayConstructorArguments") == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcCodeAnchor(analysis, "InvalidSizedArrayConstructorArguments") == "NL321@3:27+3"
    assert AcCodeCount(analysis, "UndefinedVariable") == 1
    assert AcCodeErrorCount(analysis, "UndefinedVariable") == 1
    assert AcCodeRow(analysis, "UndefinedVariable") == "UndefinedVariable|I can't find 'missing' — it hasn't been declared in this scope|<null>|Error"
    assert AcCodeAnchor(analysis, "UndefinedVariable") == "NL301@3:38+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL301:UndefinedVariable@3:38+7;NL321:InvalidSizedArrayConstructorArguments@3:27+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 2
    assert AcRow(rich, 0) == "UndefinedVariable|Variable 'missing' not found|<null>|Error"
    assert AcHint(rich, 0) == "Make sure you've declared this variable before using it."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcHint(rich, 1) == "<null>"
    assert AcSuggestions(rich, 1) == "<null>"
    assert AcRow(rich, 2) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeErrorCount(rich, "InvalidSizedArrayConstructorArguments") == 1
    assert AcCodeRow(rich, "InvalidSizedArrayConstructorArguments") == "InvalidSizedArrayConstructorArguments|Sized array allocation cannot also pass constructor arguments|Use 'new T[n]' for a zero-initialized array, or use 'new T[] { ... }' to provide element values.|Error"
    assert AcCodeAnchor(rich, "InvalidSizedArrayConstructorArguments") == "NL321@3:27+3"
    assert AcCodeCount(rich, "UndefinedVariable") == 1
    assert AcCodeErrorCount(rich, "UndefinedVariable") == 1
    assert AcCodeRow(rich, "UndefinedVariable") == "UndefinedVariable|Variable 'missing' not found|<null>|Error"
    assert AcCodeAnchor(rich, "UndefinedVariable") == "NL301@3:38+7"
}

test "020 s31 analyzer error codes: four bad range endpoints report FOUR `NL202` rows naming `int or System.Index`, and two of the four anchors widen from one column to three between the routes (was AnalyzerTests.RangeExpression_InvalidEndpointTypes_ReportTypeMismatch)" {
    source := "\nfunc BadStart(values: int[]) {\n    _ = values[\"0\"..2]\n}\n\nfunc BadEnd(values: int[]) {\n    _ = values[0..\"2\"]\n}\n\nfunc BadFromEnd(values: int[]) {\n    _ = values[0..^\"2\"]\n}\n\nfunc BadLong(values: int[], count: long) {\n    _ = values[0..count]\n}\n"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:16+1;NL202:TypeMismatch@7:19+1;NL202:TypeMismatch@11:19+1;NL202:TypeMismatch@15:19+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 4
    assert AcRow(analysis, 0) == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'string'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'string'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcHint(analysis, 1) == "<null>"
    assert AcSuggestions(analysis, 1) == "<null>"
    assert AcRow(analysis, 2) == "TypeMismatch|The '^' operator doesn't work with 'string' — the from-end index count must be an int-compatible value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcHint(analysis, 2) == "<null>"
    assert AcSuggestions(analysis, 2) == "<null>"
    assert AcRow(analysis, 3) == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'long'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcHint(analysis, 3) == "<null>"
    assert AcSuggestions(analysis, 3) == "<null>"
    assert AcRow(analysis, 4) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 4
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 4
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'string'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:16+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:16+3;NL202:TypeMismatch@7:19+3;NL202:TypeMismatch@11:19+1;NL202:TypeMismatch@15:19+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 4
    assert AcRow(rich, 0) == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'string'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'string'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcHint(rich, 1) == "<null>"
    assert AcSuggestions(rich, 1) == "<null>"
    assert AcRow(rich, 2) == "TypeMismatch|The '^' operator doesn't work with 'string' — the from-end index count must be an int-compatible value|Use a compatible operand, convert the value, or define an operator overload for this type.|Error"
    assert AcHint(rich, 2) == "<null>"
    assert AcSuggestions(rich, 2) == "<null>"
    assert AcRow(rich, 3) == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'long'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcHint(rich, 3) == "<null>"
    assert AcSuggestions(rich, 3) == "<null>"
    assert AcRow(rich, 4) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 4
    assert AcCodeErrorCount(rich, "TypeMismatch") == 4
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Range bounds must be int or System.Index, but this bound has type 'string'|Use an int bound, '^n' with an int count, or convert the value before building the range.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:16+3"
}

test "020 s31 analyzer error codes: indexing an array with a string is `NL202` at 3:19, and the plain route underlines ONE column where the rich route underlines the whole three-character literal (was AnalyzerTests.ArrayIndexAccess_WithStringIndex_ReportsTypeMismatch)" {
    source := "func Main(): int {\n    values := [1, 2, 3]\n    return values[\"0\"]\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@3:19+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Array indexes must be int, System.Index, or System.Range, but this index has type 'string'|Use an int element index, '^n' for from-end access, or a '..' range for slicing.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|Array indexes must be int, System.Index, or System.Range, but this index has type 'string'|Use an int element index, '^n' for from-end access, or a '..' range for slicing.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@3:19+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@3:19+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Array indexes must be int, System.Index, or System.Range, but this index has type 'string'|Use an int element index, '^n' for from-end access, or a '..' range for slicing.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Array indexes must be int, System.Index, or System.Range, but this index has type 'string'|Use an int element index, '^n' for from-end access, or a '..' range for slicing.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@3:19+3"
}

test "020 s31 analyzer error codes: assigning through an array RANGE index is refused before emission with `NL103` at 3:11 — one column on the plain route, five on the rich (was AnalyzerTests.ArrayRangeIndexedAssignment_ReportsBeforeEmission)" {
    source := "func Main() {\n    values := [1, 2, 3]\n    values[0..1] = [4]\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@3:11+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|Array slices cannot be assigned|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|Array slices cannot be assigned|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@3:11+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@3:11+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|Array slices cannot be assigned|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|Array slices cannot be assigned|Assign individual elements, or construct a replacement array value explicitly.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@3:11+5"
}

test "020 s31 analyzer error codes: assigning through a string index is `NL103` naming immutability, at 3:9, one column plain against two rich (was AnalyzerTests.StringIndexedAssignment_ReportsImmutableString)" {
    source := "func Main() {\n    text := \"hello\"\n    text[0] = 'H'\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@3:9+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|String characters and slices cannot be assigned|Create a new string value instead; strings are immutable.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|String characters and slices cannot be assigned|Create a new string value instead; strings are immutable.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@3:9+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@3:9+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|String characters and slices cannot be assigned|Create a new string value instead; strings are immutable.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|String characters and slices cannot be assigned|Create a new string value instead; strings are immutable.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@3:9+2"
}

test "020 s31 analyzer error codes: a catch clause over a non-exception type is `NL202` naming the type, three rows (was AnalyzerTests.CatchClause_NonExceptionType_ReportsTypeMismatch, all 3 [InlineData] rows)" with (catchClause: string, catchType: string, census: string, row0: string, codeAnchorTypeMismatch: string) [
    ("catch ex: int { }", "int", "NL202:TypeMismatch@3:17+3;", "TypeMismatch|Catch type must be assignable to System.Exception, but this type is 'int'|Catch Exception or an Exception-derived type, or use a bare catch for all exceptions.|Error", "NL202@3:17+3"),
    ("catch ex: string { }", "string", "NL202:TypeMismatch@3:17+6;", "TypeMismatch|Catch type must be assignable to System.Exception, but this type is 'string'|Catch Exception or an Exception-derived type, or use a bare catch for all exceptions.|Error", "NL202@3:17+6"),
    ("catch ex: object { }", "object", "NL202:TypeMismatch@3:17+6;", "TypeMismatch|Catch type must be assignable to System.Exception, but this type is 'object'|Catch Exception or an Exception-derived type, or use a bare catch for all exceptions.|Error", "NL202@3:17+6")
] {
    source := "func Main() {\n    try {\n    } " + catchClause + "\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == codeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains("'" + catchType + "'")
}

test "020 s31 analyzer error codes: an unknown catch type is `NL201` ONLY — no `NL202` follows it, and the absence is discriminating because the census is non-empty and names exactly one row (was AnalyzerTests.CatchClause_UnknownType_ReportsTypeNotFoundOnly)" {
    source := "func Main() {\n    try {\n    } catch ex: MissingException {\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@3:17+16;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@3:17+16"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@3:17+16;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeNotFound") == 1
    assert AcCodeErrorCount(rich, "TypeNotFound") == 1
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@3:17+16"
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s31 analyzer error codes: `assert throws` over a non-exception type is the catch clause's rule again, with its own sentence, three rows (was AnalyzerTests.AssertThrows_NonExceptionType_ReportsTypeMismatch, all 3 [InlineData] rows)" with (assertType: string, expectedType: string, census: string, row0: string, codeAnchorTypeMismatch: string) [
    ("int", "int", "NL202:TypeMismatch@2:19+3;", "TypeMismatch|Assert throws type must be assignable to System.Exception, but this type is 'int'|Assert an Exception-derived type, or use a broader exception type such as Exception.|Error", "NL202@2:19+3"),
    ("string", "string", "NL202:TypeMismatch@2:19+6;", "TypeMismatch|Assert throws type must be assignable to System.Exception, but this type is 'string'|Assert an Exception-derived type, or use a broader exception type such as Exception.|Error", "NL202@2:19+6"),
    ("object", "object", "NL202:TypeMismatch@2:19+6;", "TypeMismatch|Assert throws type must be assignable to System.Exception, but this type is 'object'|Assert an Exception-derived type, or use a broader exception type such as Exception.|Error", "NL202@2:19+6")
] {
    source := "func Main() {\n    assert throws " + assertType + " {\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == codeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains("'" + expectedType + "'")
}

test "020 s31 analyzer error codes: an unknown `assert throws` type is `NL201` only, the sibling of the catch-clause case (was AnalyzerTests.AssertThrows_UnknownType_ReportsTypeNotFoundOnly)" {
    source := "func Main() {\n    assert throws MissingException {\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL201:TypeNotFound@2:19+16;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeNotFound") == 1
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 1
    assert AcCodeRow(analysis, "TypeNotFound") == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcCodeAnchor(analysis, "TypeNotFound") == "NL201@2:19+16"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL201:TypeNotFound@2:19+16;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeNotFound") == 1
    assert AcCodeErrorCount(rich, "TypeNotFound") == 1
    assert AcCodeRow(rich, "TypeNotFound") == "TypeNotFound|Type 'MissingException' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'MissingException'.|Error"
    assert AcCodeAnchor(rich, "TypeNotFound") == "NL201@2:19+16"
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
}

test "020 s31 analyzer error codes: a non-disposable `using` resource is `NL103` naming the type and both halves of the requirement, three rows, one of which widens from one column to six between the routes (was AnalyzerTests.UsingStatement_NonDisposableResource_Error, all 3 [InlineData] rows)" with (statement: string, typeName: string, census: string, row0: string, codeAnchorInvalidSyntax: string, richCensus: string, richCodeAnchorInvalidSyntax: string) [
    ("using value := 1 { }", "int", "NL103:InvalidSyntax@2:9+5;", "InvalidSyntax|Using resource of type 'int' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error", "NL103@2:9+5", "NL103:InvalidSyntax@2:9+5;", "NL103@2:9+5"),
    ("using let text: string = \"test\" { }", "string", "NL103:InvalidSyntax@2:19+4;", "InvalidSyntax|Using resource of type 'string' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error", "NL103@2:19+4", "NL103:InvalidSyntax@2:19+4;", "NL103@2:19+4"),
    ("using \"test\" { }", "string", "NL103:InvalidSyntax@2:15+1;", "InvalidSyntax|Using resource of type 'string' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error", "NL103@2:15+1", "NL103:InvalidSyntax@2:15+6;", "NL103@2:15+6")
] {
    source := "    func Main() {\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == richCodeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains("Using resource of type '" + typeName + "' must implement IDisposable")
}

test "020 s31 analyzer error codes: a resource whose `Dispose` has the wrong shape fails the same rule as one with no `Dispose` at all — three rows, all `NL103` (was AnalyzerTests.UsingStatement_InvalidDisposePattern_Error, all 3 [InlineData] rows)" with (disposeMember: string) [
    ("func Dispose(value: int): void { }"),
    ("func Dispose(): int { return 0 }"),
    ("static func Dispose(): void { }")
] {
    source := "    class Resource {\n        " + disposeMember + "\n    }\n\n    func Main() {\n        using resource := new Resource() {\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL103:InvalidSyntax@6:9+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidSyntax|Using resource of type 'Resource' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == "InvalidSyntax|Using resource of type 'Resource' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error"
    assert AcCodeAnchor(analysis, "InvalidSyntax") == "NL103@6:9+8"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL103:InvalidSyntax@6:9+8;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidSyntax|Using resource of type 'Resource' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == "InvalidSyntax|Using resource of type 'Resource' must implement IDisposable or provide Dispose(): void|Use a resource type with a parameterless void Dispose method, or remove the using statement.|Error"
    assert AcCodeAnchor(rich, "InvalidSyntax") == "NL103@6:9+8"
}

test "020 s31 analyzer error codes: deconstructing a non-tuple initializer is `NL103` naming the initializer type, three rows, two of which split one column against two between the routes (was AnalyzerTests.TupleDeconstruction_InvalidInitializer_Error, all 3 [InlineData] rows)" with (statement: string, message: string, census: string, row0: string, codeAnchorInvalidSyntax: string, richCensus: string, richCodeAnchorInvalidSyntax: string) [
    ("x, y := 1", "needs a tuple value", "NL103:InvalidSyntax@2:17+1;", "InvalidSyntax|Tuple deconstruction needs a tuple value, but this initializer is 'int'|Return or construct a tuple with the same number of elements as the deconstruction targets.|Error", "NL103@2:17+1", "NL103:InvalidSyntax@2:17+1;", "NL103@2:17+1"),
    ("x, y, z := (1, 2)", "has 3 target(s), but the initializer has 2 element(s)", "NL103:InvalidSyntax@2:20+1;", "InvalidSyntax|Tuple deconstruction has 3 target(s), but the initializer has 2 element(s)|Match the number of target names to the tuple element count.|Error", "NL103@2:20+1", "NL103:InvalidSyntax@2:20+2;", "NL103@2:20+2"),
    ("x, y := (1, 2, 3)", "has 2 target(s), but the initializer has 3 element(s)", "NL103:InvalidSyntax@2:17+1;", "InvalidSyntax|Tuple deconstruction has 2 target(s), but the initializer has 3 element(s)|Match the number of target names to the tuple element count.|Error", "NL103@2:17+1", "NL103:InvalidSyntax@2:17+2;", "NL103@2:17+2")
] {
    source := "    func Main() {\n        " + statement + "\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidSyntax") == 1
    assert AcCodeErrorCount(analysis, "InvalidSyntax") == 1
    assert AcCodeRow(analysis, "InvalidSyntax") == row0
    assert AcCodeAnchor(analysis, "InvalidSyntax") == codeAnchorInvalidSyntax
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidSyntax") == 1
    assert AcCodeErrorCount(rich, "InvalidSyntax") == 1
    assert AcCodeRow(rich, "InvalidSyntax") == row0
    assert AcCodeAnchor(rich, "InvalidSyntax") == richCodeAnchorInvalidSyntax
    assert AcRow(rich, 0).Contains(message)
}

test "020 s31 analyzer error codes: a non-enumerable `foreach` collection is `NL202`, two rows, one of them route-split (was AnalyzerTests.ForeachLoop_NonEnumerableCollection_Error, all 2 [InlineData] rows)" with (statement: string, message: string, census: string, row0: string, codeAnchorTypeMismatch: string, richCensus: string, richCodeAnchorTypeMismatch: string) [
    ("foreach value in 1 { }", "foreach collection must be enumerable", "NL202:TypeMismatch@4:22+1;", "TypeMismatch|foreach collection must be enumerable, but this collection is 'int'|Use an array, Span<T>, or IEnumerable<T> value as the foreach collection.|Error", "NL202@4:22+1", "NL202:TypeMismatch@4:22+1;", "NL202@4:22+1"),
    ("await foreach value in [1, 2, 3] { }", "await foreach collection must be async enumerable", "NL202:TypeMismatch@4:28+1;", "TypeMismatch|await foreach collection must be async enumerable, but this collection is 'int[]'|Use an IAsyncEnumerable<T> value as the await foreach collection.|Error", "NL202@4:28+1", "NL202:TypeMismatch@4:28+2;", "NL202@4:28+2")
] {
    source := "import System.Threading.Tasks\n\nasync func Main(): Task<int> {\n    " + statement + "\n    return 0\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == richCensus
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == richCodeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains(message)
}

test "020 s31 analyzer error codes: `+=` on two bools is `NL202` naming the underlying `'+'` operator rather than the compound one (was AnalyzerTests.CompoundAssignment_BoolOperand_Error)" {
    source := "\n            func Main() {\n                value := true\n                value += true\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:23+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '+' operator doesn't work with 'bool' and 'bool' — both sides need numeric values, but I found 'bool' and 'bool'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'bool' and 'bool' — both sides need numeric values, but I found 'bool' and 'bool'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@4:23+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:23+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|The '+' operator doesn't work with 'bool' and 'bool' — both sides need numeric values, but I found 'bool' and 'bool'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '+' operator doesn't work with 'bool' and 'bool' — both sides need numeric values, but I found 'bool' and 'bool'|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@4:23+1"
}

test "020 s31 analyzer error codes: `+=` whose promoted result is an `int` cannot be stored back into a `byte`, and THIS sentence names the compound operator `'+='` — the pair of fixtures is what shows the analyzer chooses between two spellings (was AnalyzerTests.CompoundAssignment_PromotedSmallIntegerResult_Error)" {
    source := "\n            func Main() {\n                left: byte = 1 as byte\n                right: byte = 2 as byte\n                left += right\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@5:22+2;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The '+=' assignment produces 'int', which can't be stored in 'byte'|Use an explicit assignment with a conversion, or choose operands whose operator result is assignable to the target.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The '+=' assignment produces 'int', which can't be stored in 'byte'|Use an explicit assignment with a conversion, or choose operands whose operator result is assignable to the target.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@5:22+2"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@5:22+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|The '+=' assignment produces 'int', which can't be stored in 'byte'|Use an explicit assignment with a conversion, or choose operands whose operator result is assignable to the target.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The '+=' assignment produces 'int', which can't be stored in 'byte'|Use an explicit assignment with a conversion, or choose operands whose operator result is assignable to the target.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@5:22+2"
}

test "020 s31 analyzer error codes: `??=` onto a non-nullable `int` is ONE `NL202` whose sentence names the OPERATOR and the type, anchored at 4:17 (was AnalyzerTests.NullCoalesceAssignment_NonNullableValueTarget_Invalid)" {
    source := "\n            func Main() {\n                x := 10\n                x ??= 5\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The left side of '??=' has type 'int', which can't be null|Use '=' for values that are always present, or make the target nullable before using '??='.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The left side of '??=' has type 'int', which can't be null|Use '=' for values that are always present, or make the target nullable before using '??='.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@4:17+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:17+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|The left side of '??=' has type 'int', which can't be null|Use '=' for values that are always present, or make the target nullable before using '??='.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The left side of '??=' has type 'int', which can't be null|Use '=' for values that are always present, or make the target nullable before using '??='.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@4:17+1"
}

test "020 s31 analyzer error codes: `??` with a non-nullable `int` left side is the sibling `NL202` at 4:24 — same shape, different operator, and both sentences are pinned whole rather than by the eleven characters the deleted code matched (was AnalyzerTests.NullCoalesce_NonNullableValueLeft_Invalid)" {
    source := "\n            func Main(): int {\n                x := 10\n                return x ?? 5\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@4:24+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|The left side of '??' has type 'int', which can't be null|Use the value directly, or make the left side nullable before using '??'.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|The left side of '??' has type 'int', which can't be null|Use the value directly, or make the left side nullable before using '??'.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@4:24+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@4:24+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|The left side of '??' has type 'int', which can't be null|Use the value directly, or make the left side nullable before using '??'.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|The left side of '??' has type 'int', which can't be null|Use the value directly, or make the left side nullable before using '??'.|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@4:24+1"
}

test "020 s31 analyzer error codes: an `soa record` parses and is then feature-gated with `NL323`, anchored on the `soa` keyword at 2:13, and the fixture reports NO `NL201` — an absence the C# claimed and the census here proves DISCRIMINATING rather than vacuous, because the fixture does report something else (was AnalyzerTests.SoaRecordDeclaration_IsFeatureGated)" {
    source := "\n            soa record NodeTable {\n                kind: int\n                valueStart: int\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL323:FeatureNotImplemented@2:13+3;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "FeatureNotImplemented|soa record 'NodeTable' is parsed but not available in production builds yet|Set NSHARP_EXPERIMENTAL_SOA=1 only for the compiler table migration gate; otherwise keep using regular records|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "FeatureNotImplemented") == 1
    assert AcCodeErrorCount(analysis, "FeatureNotImplemented") == 1
    assert AcCodeRow(analysis, "FeatureNotImplemented") == "FeatureNotImplemented|soa record 'NodeTable' is parsed but not available in production builds yet|Set NSHARP_EXPERIMENTAL_SOA=1 only for the compiler table migration gate; otherwise keep using regular records|Error"
    assert AcCodeAnchor(analysis, "FeatureNotImplemented") == "NL323@2:13+3"
    assert AcCodeCount(analysis, "TypeNotFound") == 0
    assert AcCodeErrorCount(analysis, "TypeNotFound") == 0
    assert AcCodeRow(analysis, "TypeNotFound") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL323:FeatureNotImplemented@2:13+3;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "FeatureNotImplemented|soa record 'NodeTable' is parsed but not available in production builds yet|Set NSHARP_EXPERIMENTAL_SOA=1 only for the compiler table migration gate; otherwise keep using regular records|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "FeatureNotImplemented") == 1
    assert AcCodeErrorCount(rich, "FeatureNotImplemented") == 1
    assert AcCodeRow(rich, "FeatureNotImplemented") == "FeatureNotImplemented|soa record 'NodeTable' is parsed but not available in production builds yet|Set NSHARP_EXPERIMENTAL_SOA=1 only for the compiler table migration gate; otherwise keep using regular records|Error"
    assert AcCodeAnchor(rich, "FeatureNotImplemented") == "NL323@2:13+3"
    assert AcCodeCount(rich, "TypeNotFound") == 0
    assert AcCodeErrorCount(rich, "TypeNotFound") == 0
    assert AcCodeRow(rich, "TypeNotFound") == "<no-such-code>"
}

test "020 s31 analyzer error codes: a readonly field as a `ref`/`out` argument outside the constructor is `NL309:ReadonlyAssignment` anchored on the FIELD NAME `value`, five columns, two rows (was AnalyzerTests.ReadonlyField_RefOutArgumentOutsideConstructor_Error, all 2 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("bump(ref value)", "ref", "NL309:ReadonlyAssignment@17:22+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be used as a ref argument|Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.|Error", "NL309@17:22+5"),
    ("reset(out this.value)", "out", "NL309:ReadonlyAssignment@17:28+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be used as a out argument|Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.|Error", "NL309@17:28+5")
] {
    source := "    func bump(ref value: int) {\n        value += 1\n    }\n\n    func reset(out value: int) {\n        value = 0\n    }\n\n    class Counter {\n        readonly value: int\n\n        constructor() {\n            value = 1\n        }\n\n        func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("can't be used as a " + modifier + " argument")
}

test "020 s31 analyzer error codes: a `this.`-qualified readonly write outside the constructor is `NL309` — the qualification does not change the rule, and the anchor is still the field name (was AnalyzerTests.ReadonlyField_QualifiedInstanceAssignmentOutsideConstructor_Error)" {
    source := "    class Counter {\n        readonly value: int\n\n        constructor() {\n            value = 1\n        }\n\n        func Mutate(other: Counter) {\n            other.value = 2\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL309:ReadonlyAssignment@9:19+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == "NL309@9:19+5"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL309:ReadonlyAssignment@9:19+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == "NL309@9:19+5"
}

test "020 s31 analyzer error codes: a constructor may assign its OWN readonly fields but not another instance's, and the sentence says so explicitly (was AnalyzerTests.ReadonlyField_QualifiedInstanceAssignmentInConstructor_Error)" {
    source := "    class Counter {\n        readonly value: int\n\n        constructor(other: Counter) {\n            value = 1\n            other.value = 2\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL309:ReadonlyAssignment@6:19+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == "NL309@6:19+5"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL309:ReadonlyAssignment@6:19+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == "NL309@6:19+5"
}

test "020 s31 analyzer error codes: a qualified readonly field as a `ref`/`out` argument is `NL309`, two rows (was AnalyzerTests.ReadonlyField_QualifiedInstanceRefOutArgument_Error, all 2 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("bump(ref other.value)", "ref", "NL309:ReadonlyAssignment@17:28+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be used as a ref argument|Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.|Error", "NL309@17:28+5"),
    ("reset(out other.value)", "out", "NL309:ReadonlyAssignment@17:29+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be used as a out argument|Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.|Error", "NL309@17:29+5")
] {
    source := "    func bump(ref value: int) {\n        value += 1\n    }\n\n    func reset(out value: int) {\n        value = 0\n    }\n\n    class Counter {\n        readonly value: int\n\n        constructor() {\n            value = 1\n        }\n\n        func Mutate(other: Counter) {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("can't be used as a " + modifier + " argument")
}

test "020 s31 analyzer error codes: an INHERITED readonly field assigned outside the constructor is `NL309`, two rows (was AnalyzerTests.ReadonlyField_InheritedAssignmentOutsideConstructor_Error, all 2 [InlineData] rows)" with (statement: string, census: string, codeAnchorReadonlyAssignment: string) [
    ("value = 2", "NL309:ReadonlyAssignment@7:13+5;", "NL309@7:13+5"),
    ("this.value = 2", "NL309:ReadonlyAssignment@7:18+5;", "NL309@7:18+5")
] {
    source := "    class Base {\n        readonly value: int = 1\n    }\n\n    class Derived : Base {\n        func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — it can only be assigned in a constructor|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
}

test "020 s31 analyzer error codes: a DERIVED constructor may not assign the base's readonly field, and the message names the constructor rule rather than the general one (was AnalyzerTests.ReadonlyField_InheritedAssignmentInDerivedConstructor_Error, all 2 [InlineData] rows)" with (statement: string, census: string, codeAnchorReadonlyAssignment: string) [
    ("value = 2", "NL309:ReadonlyAssignment@7:13+5;", "NL309@7:13+5"),
    ("this.value = 2", "NL309:ReadonlyAssignment@7:18+5;", "NL309@7:18+5")
] {
    source := "    class Base {\n        readonly value: int = 1\n    }\n\n    class Derived : Base {\n        constructor() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'value' is readonly — constructors can only assign readonly fields on the current instance|Assign the current instance field directly, or remove `readonly` if other instances must be mutated.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
}

test "020 s31 analyzer error codes: an inherited readonly field as a `ref`/`out` argument is `NL309`, two rows (was AnalyzerTests.ReadonlyField_InheritedRefOutArgument_Error, all 2 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("bump(ref value)", "ref", "NL309:ReadonlyAssignment@15:22+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be used as a ref argument|Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.|Error", "NL309@15:22+5"),
    ("reset(out this.value)", "out", "NL309:ReadonlyAssignment@15:28+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be used as a out argument|Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference.|Error", "NL309@15:28+5")
] {
    source := "    func bump(ref value: int) {\n        value += 1\n    }\n\n    func reset(out value: int) {\n        value = 0\n    }\n\n    class Base {\n        readonly value: int = 1\n    }\n\n    class Derived : Base {\n        func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("can't be used as a " + modifier + " argument")
}

test "020 s31 analyzer error codes: incrementing an inherited readonly field is `NL309` with the `changed with '++'` verb (was AnalyzerTests.ReadonlyField_InheritedIncrement_Error, all 2 [InlineData] rows)" with (statement: string, op: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("value++", "++", "NL309:ReadonlyAssignment@7:13+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be changed with '++'|Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.|Error", "NL309@7:13+5"),
    ("this.value--", "--", "NL309:ReadonlyAssignment@7:18+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be changed with '--'|Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.|Error", "NL309@7:18+5")
] {
    source := "    class Base {\n        readonly value: int = 1\n    }\n\n    class Derived : Base {\n        func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("'" + op + "'")
}

test "020 s31 analyzer error codes: incrementing a readonly field outside the constructor is `NL309`, two rows over `++` and `--` (was AnalyzerTests.ReadonlyField_IncrementOutsideConstructor_Error, all 2 [InlineData] rows)" with (statement: string, op: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("value++", "++", "NL309:ReadonlyAssignment@9:13+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be changed with '++'|Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.|Error", "NL309@9:13+5"),
    ("this.value--", "--", "NL309:ReadonlyAssignment@9:18+5;", "ReadonlyAssignment|Field 'value' is readonly — it can't be changed with '--'|Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.|Error", "NL309@9:18+5")
] {
    source := "    class Counter {\n        readonly value: int\n\n        constructor() {\n            value = 1\n        }\n\n        func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("'" + op + "'")
}

test "020 s31 analyzer error codes: incrementing a qualified readonly field is `NL309`, two rows (was AnalyzerTests.ReadonlyField_QualifiedInstanceIncrement_Error, all 2 [InlineData] rows)" with (statement: string, op: string, row0: string) [
    ("other.value++", "++", "ReadonlyAssignment|Field 'value' is readonly — it can't be changed with '++'|Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.|Error"),
    ("other.value--", "--", "ReadonlyAssignment|Field 'value' is readonly — it can't be changed with '--'|Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later.|Error")
] {
    source := "    class Counter {\n        readonly value: int\n\n        constructor() {\n            value = 1\n        }\n\n        func Mutate(other: Counter) {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL309:ReadonlyAssignment@9:19+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == "NL309@9:19+5"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL309:ReadonlyAssignment@9:19+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == "NL309@9:19+5"
    assert AcRow(rich, 0).Contains("'" + op + "'")
}

test "020 s31 analyzer error codes: incrementing a STATIC readonly field is `NL309` whose sentence says `is static readonly` rather than `is readonly` — a different string for a different rule, which the deleted substring match could not distinguish (was AnalyzerTests.StaticReadonlyField_Increment_Error, all 2 [InlineData] rows)" with (statement: string, op: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("State.Value++", "++", "NL309:ReadonlyAssignment@5:19+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be changed with '++'|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@5:19+5"),
    ("Value--", "--", "NL309:ReadonlyAssignment@5:13+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be changed with '--'|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@5:13+5")
] {
    source := "    class State {\n        static readonly Value: int = 1\n\n        static func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("'" + op + "'")
}

test "020 s31 analyzer error codes: assigning an inherited static readonly field is `NL309` naming initialization AT ITS DECLARATION as the only legal place (was AnalyzerTests.StaticReadonlyField_InheritedAssignment_Error)" {
    source := "    class Base {\n        static readonly Value: int = 1\n    }\n\n    class Derived : Base {\n        static func Mutate() {\n            Derived.Value = 2\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL309:ReadonlyAssignment@7:21+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == "NL309@7:21+5"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL309:ReadonlyAssignment@7:21+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == "NL309@7:21+5"
}

test "020 s31 analyzer error codes: an inherited static readonly field as a `ref`/`out` argument is `NL309`, two rows (was AnalyzerTests.StaticReadonlyField_InheritedRefOutArgument_Error, all 2 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("bump(ref Derived.Value)", "ref", "NL309:ReadonlyAssignment@15:30+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be used as a ref argument|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@15:30+5"),
    ("reset(out Derived.Value)", "out", "NL309:ReadonlyAssignment@15:31+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be used as a out argument|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@15:31+5")
] {
    source := "    func bump(ref value: int) {\n        value += 1\n    }\n\n    func reset(out value: int) {\n        value = 0\n    }\n\n    class Base {\n        static readonly Value: int = 1\n    }\n\n    class Derived : Base {\n        static func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("can't be used as a " + modifier + " argument")
}

test "020 s31 analyzer error codes: incrementing an inherited static readonly field is `NL309` (was AnalyzerTests.StaticReadonlyField_InheritedIncrement_Error)" {
    source := "    class Base {\n        static readonly Value: int = 1\n    }\n\n    class Derived : Base {\n        static func Mutate() {\n            Derived.Value++\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL309:ReadonlyAssignment@7:21+5;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'Value' is static readonly — it can't be changed with '++'|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'Value' is static readonly — it can't be changed with '++'|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == "NL309@7:21+5"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL309:ReadonlyAssignment@7:21+5;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'Value' is static readonly — it can't be changed with '++'|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'Value' is static readonly — it can't be changed with '++'|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == "NL309@7:21+5"
}

test "020 s31 analyzer error codes: setting a static readonly field outside its declaration is `NL309`, two rows (was AnalyzerTests.StaticReadonlyField_SetOutsideDeclaration_Error, all 2 [InlineData] rows)" with (statement: string, fieldName: string, census: string, codeAnchorReadonlyAssignment: string) [
    ("State.Value = 2", "Value", "NL309:ReadonlyAssignment@5:19+5;", "NL309@5:19+5"),
    ("Value = 2", "Value", "NL309:ReadonlyAssignment@5:13+5;", "NL309@5:13+5")
] {
    source := "    class State {\n        static readonly Value: int = 1\n\n        static func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == "ReadonlyAssignment|Field 'Value' is static readonly — it can only be initialized at its declaration|Move this value into the field initializer, or remove `readonly` if the static field needs to change later.|Error"
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("Field '" + fieldName + "' is static readonly")
}

test "020 s31 analyzer error codes: a static readonly field as a `ref`/`out` argument is `NL309`, three rows, and it closes the readonly-field subject (was AnalyzerTests.StaticReadonlyField_RefOutArgument_Error, all 3 [InlineData] rows)" with (statement: string, modifier: string, census: string, row0: string, codeAnchorReadonlyAssignment: string) [
    ("bump(ref State.Value)", "ref", "NL309:ReadonlyAssignment@13:28+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be used as a ref argument|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@13:28+5"),
    ("reset(out State.Value)", "out", "NL309:ReadonlyAssignment@13:29+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be used as a out argument|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@13:29+5"),
    ("bump(ref Value)", "ref", "NL309:ReadonlyAssignment@13:22+5;", "ReadonlyAssignment|Field 'Value' is static readonly — it can't be used as a ref argument|Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`.|Error", "NL309@13:22+5")
] {
    source := "    func bump(ref value: int) {\n        value += 1\n    }\n\n    func reset(out value: int) {\n        value = 0\n    }\n\n    class State {\n        static readonly Value: int = 1\n\n        static func Mutate() {\n            " + statement + "\n        }\n    }"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(analysis, "ReadonlyAssignment") == 1
    assert AcCodeRow(analysis, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(analysis, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeErrorCount(rich, "ReadonlyAssignment") == 1
    assert AcCodeRow(rich, "ReadonlyAssignment") == row0
    assert AcCodeAnchor(rich, "ReadonlyAssignment") == codeAnchorReadonlyAssignment
    assert AcRow(rich, 0).Contains("can't be used as a " + modifier + " argument")
}

test "020 s31 analyzer error codes: a list pattern against an `IEnumerable` is `NL504:PatternTypeMismatch`, a code no other contract in this project pins, at 6:21 (was AnalyzerTests.ListPattern_IEnumerablePattern_ReportsPatternTypeMismatch)" {
    source := "\n            import System.Collections.Generic\n\n            func Main(values: IEnumerable<int>): int {\n                return match values {\n                    [first] => first,\n                    _ => 0\n                }\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL504:PatternTypeMismatch@6:21+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "PatternTypeMismatch|A list pattern can only match arrays or indexable collections, but this value is 'IEnumerable<int>'|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "PatternTypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "PatternTypeMismatch") == 1
    assert AcCodeRow(analysis, "PatternTypeMismatch") == "PatternTypeMismatch|A list pattern can only match arrays or indexable collections, but this value is 'IEnumerable<int>'|<null>|Error"
    assert AcCodeAnchor(analysis, "PatternTypeMismatch") == "NL504@6:21+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL504:PatternTypeMismatch@6:21+7;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "PatternTypeMismatch|A list pattern can only match arrays or indexable collections, but this value is 'IEnumerable<int>'|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "PatternTypeMismatch") == 1
    assert AcCodeErrorCount(rich, "PatternTypeMismatch") == 1
    assert AcCodeRow(rich, "PatternTypeMismatch") == "PatternTypeMismatch|A list pattern can only match arrays or indexable collections, but this value is 'IEnumerable<int>'|<null>|Error"
    assert AcCodeAnchor(rich, "PatternTypeMismatch") == "NL504@6:21+7"
}

test "020 s31 analyzer error codes: an unsupported relational pattern comparison is `NL202` naming the OPERATOR and both compared types, five rows over `<` and `==` across string, object, `int?` and decimal — the second of the file's 35 theories to leave, and the per-row anchor separates the operators by WIDTH: `<` underlines one column at 3:9 and `==` underlines two, so the length is the operator's own (was AnalyzerTests.RelationalPattern_UnsupportedComparison_ReportsTypeMismatch, all 5 [InlineData] rows)" with (declaration: string, pattern: string, valueType: string, patternType: string, census: string, row0: string, codeAnchorTypeMismatch: string) [
    ("value: string", "< \"m\"", "string", "string", "NL202:TypeMismatch@3:9+1;", "TypeMismatch|Relational pattern '<' can't compare 'string' with 'string' before IL emission|Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.|Error", "NL202@3:9+1"),
    ("value: string", "== \"m\"", "string", "string", "NL202:TypeMismatch@3:9+2;", "TypeMismatch|Relational pattern '==' can't compare 'string' with 'string' before IL emission|Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.|Error", "NL202@3:9+2"),
    ("value: object", "== 1", "object", "int", "NL202:TypeMismatch@3:9+2;", "TypeMismatch|Relational pattern '==' can't compare 'object' with 'int' before IL emission|Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.|Error", "NL202@3:9+2"),
    ("value: int?", "< 1", "int?", "int", "NL202:TypeMismatch@3:9+1;", "TypeMismatch|Relational pattern '<' can't compare 'int?' with 'int' before IL emission|Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.|Error", "NL202@3:9+1"),
    ("value: decimal", "< 1m", "decimal", "decimal", "NL202:TypeMismatch@3:9+1;", "TypeMismatch|Relational pattern '<' can't compare 'decimal' with 'decimal' before IL emission|Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.|Error", "NL202@3:9+1")
] {
    source := "func Main(" + declaration + "): int {\n    return match value {\n        " + pattern + " => 1,\n        _ => 0\n    }\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == census
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == row0
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == row0
    assert AcCodeAnchor(analysis, "TypeMismatch") == codeAnchorTypeMismatch
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == census
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == row0
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == row0
    assert AcCodeAnchor(rich, "TypeMismatch") == codeAnchorTypeMismatch
    assert AcRow(rich, 0).Contains("Relational pattern")
    assert AcRow(rich, 0).Contains("'" + valueType + "'")
    assert AcRow(rich, 0).Contains("'" + patternType + "'")
}

test "020 s31 analyzer error codes: a collection expression assigned to `IQueryable<int>` is `NL323` naming the exact constructed type, at 5:46 (was AnalyzerTests.CollectionExpression_IQueryableAssignment_ReportsFeatureNotImplemented)" {
    source := "\n            import System.Linq\n\n            func Main() {\n                let items: IQueryable<int> = [1, 2, 3]\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL323:FeatureNotImplemented@5:46+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "FeatureNotImplemented|Collection expressions for 'IQueryable<int>' are not implemented yet|Use an array, List<T>, HashSet<T>, Queue<T>, or construct the queryable value explicitly.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "FeatureNotImplemented") == 1
    assert AcCodeErrorCount(analysis, "FeatureNotImplemented") == 1
    assert AcCodeRow(analysis, "FeatureNotImplemented") == "FeatureNotImplemented|Collection expressions for 'IQueryable<int>' are not implemented yet|Use an array, List<T>, HashSet<T>, Queue<T>, or construct the queryable value explicitly.|Error"
    assert AcCodeAnchor(analysis, "FeatureNotImplemented") == "NL323@5:46+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL323:FeatureNotImplemented@5:46+2;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "FeatureNotImplemented|Collection expressions for 'IQueryable<int>' are not implemented yet|Use an array, List<T>, HashSet<T>, Queue<T>, or construct the queryable value explicitly.|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "FeatureNotImplemented") == 1
    assert AcCodeErrorCount(rich, "FeatureNotImplemented") == 1
    assert AcCodeRow(rich, "FeatureNotImplemented") == "FeatureNotImplemented|Collection expressions for 'IQueryable<int>' are not implemented yet|Use an array, List<T>, HashSet<T>, Queue<T>, or construct the queryable value explicitly.|Error"
    assert AcCodeAnchor(rich, "FeatureNotImplemented") == "NL323@5:46+2"
}

test "020 s31 analyzer error codes: a required parameter after an optional one is ONE `NL409` anchored on the offending parameter NAME `b` at 2:38, one column (was AnalyzerTests.TestDefaultParametersRequiredAfterOptional)" {
    source := "\n            func Invalid(a: int = 1, b: int) {\n                print a\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL409:RequiredParameterAfterOptional@2:38+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "RequiredParameterAfterOptional|Required parameter 'b' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL409:RequiredParameterAfterOptional@2:38+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "RequiredParameterAfterOptional|Required parameter 'b' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
}

test "020 s31 analyzer error codes: TWO required parameters after an optional one report TWICE, once each — `c` at 2:46 and `d` at 2:54 — which the deleted `FirstOrDefault` plus `NotNull` pair could not say, since it read only the first row and never counted (was AnalyzerTests.TestDefaultParametersMultipleRequiredAfterOptional)" {
    source := "\n            func Invalid(a: int, b: int = 1, c: int, d: string) {\n                print a\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL409:RequiredParameterAfterOptional@2:46+1;NL409:RequiredParameterAfterOptional@2:54+1;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 2
    assert AcRow(analysis, 0) == "RequiredParameterAfterOptional|Required parameter 'c' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "RequiredParameterAfterOptional|Required parameter 'd' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcHint(analysis, 1) == "<null>"
    assert AcSuggestions(analysis, 1) == "<null>"
    assert AcRow(analysis, 2) == "<no-such-error>"
    assert AcCodeCount(analysis, "RequiredParameterAfterOptional") == 2
    assert AcCodeErrorCount(analysis, "RequiredParameterAfterOptional") == 2
    assert AcCodeRow(analysis, "RequiredParameterAfterOptional") == "RequiredParameterAfterOptional|Required parameter 'c' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcCodeAnchor(analysis, "RequiredParameterAfterOptional") == "NL409@2:46+1"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL409:RequiredParameterAfterOptional@2:46+1;NL409:RequiredParameterAfterOptional@2:54+1;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 2
    assert AcRow(rich, 0) == "RequiredParameterAfterOptional|Required parameter 'c' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "RequiredParameterAfterOptional|Required parameter 'd' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcHint(rich, 1) == "<null>"
    assert AcSuggestions(rich, 1) == "<null>"
    assert AcRow(rich, 2) == "<no-such-error>"
    assert AcCodeCount(rich, "RequiredParameterAfterOptional") == 2
    assert AcCodeErrorCount(rich, "RequiredParameterAfterOptional") == 2
    assert AcCodeRow(rich, "RequiredParameterAfterOptional") == "RequiredParameterAfterOptional|Required parameter 'c' can't come after optional parameters — move it before the optional ones, or give it a default value too|<null>|Error"
    assert AcCodeAnchor(rich, "RequiredParameterAfterOptional") == "NL409@2:46+1"
}

test "020 s31 analyzer error codes: a non-constant default value is `NL410`, anchored on the whole call `GetValue` at 6:35 (was AnalyzerTests.TestDefaultParametersInvalidNonConstant)" {
    source := "\n            func GetValue(): int {\n                return 42\n            }\n\n            func Invalid(x: int = GetValue()) {\n                print x\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL410:InvalidDefaultParameterValue@6:35+8;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "InvalidDefaultParameterValue|The default value for 'x' must be something the compiler can evaluate — use a literal, null, or a simple constant|<null>|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "InvalidDefaultParameterValue") == 1
    assert AcCodeErrorCount(analysis, "InvalidDefaultParameterValue") == 1
    assert AcCodeRow(analysis, "InvalidDefaultParameterValue") == "InvalidDefaultParameterValue|The default value for 'x' must be something the compiler can evaluate — use a literal, null, or a simple constant|<null>|Error"
    assert AcCodeAnchor(analysis, "InvalidDefaultParameterValue") == "NL410@6:35+8"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL410:InvalidDefaultParameterValue@6:35+8;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "InvalidDefaultParameterValue|The default value for 'x' must be something the compiler can evaluate — use a literal, null, or a simple constant|<null>|Error"
    assert AcHint(rich, 0) == "<null>"
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "InvalidDefaultParameterValue") == 1
    assert AcCodeErrorCount(rich, "InvalidDefaultParameterValue") == 1
    assert AcCodeRow(rich, "InvalidDefaultParameterValue") == "InvalidDefaultParameterValue|The default value for 'x' must be something the compiler can evaluate — use a literal, null, or a simple constant|<null>|Error"
    assert AcCodeAnchor(rich, "InvalidDefaultParameterValue") == "NL410@6:35+8"
}

test "020 s31 analyzer error codes: a method group whose parameter would need a numeric conversion is refused for a CLR delegate — and **the two entry points give two different sentences and two different suggestions for it**: the plain route says `Argument 1 to 'Use' is method group ...` and offers a fix, the production route says `Cannot pass ... as argument for parameter ...` and offers NOTHING (was AnalyzerTests.MethodGroupToClrDelegate_RejectsNumericParameterConversion)" {
    source := "\n            import System\n\n            func Use(action: Action<int>) {\n            }\n\n            func AcceptLong(value: long) {\n            }\n\n            func Main() {\n                Use(AcceptLong)\n            }\n        "
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == "NL202:TypeMismatch@11:21+10;"
    assert AcHasErrors(analysis) == "True"
    assert AcErrorCount(analysis) == 1
    assert AcRow(analysis, 0) == "TypeMismatch|Argument 1 to 'Use' is method group 'AcceptLong', but parameter 'action' expects 'Action<int>'|Pass a value with the expected type, or update the function signature.|Error"
    assert AcHint(analysis, 0) == "<null>"
    assert AcSuggestions(analysis, 0) == "<null>"
    assert AcRow(analysis, 1) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 1
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 1
    assert AcCodeRow(analysis, "TypeMismatch") == "TypeMismatch|Argument 1 to 'Use' is method group 'AcceptLong', but parameter 'action' expects 'Action<int>'|Pass a value with the expected type, or update the function signature.|Error"
    assert AcCodeAnchor(analysis, "TypeMismatch") == "NL202@11:21+10"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == "NL202:TypeMismatch@11:21+10;"
    assert AcHasErrors(rich) == "True"
    assert AcErrorCount(rich) == 1
    assert AcRow(rich, 0) == "TypeMismatch|Cannot pass `method group 'AcceptLong'` as argument for parameter `action` of type `Action<int>`|<null>|Error"
    assert AcHint(rich, 0) == "The parameter `action` expects a `Action<int>` value, but you passed a\n`method group 'AcceptLong'`. These types are not compatible."
    assert AcSuggestions(rich, 0) == "<null>"
    assert AcRow(rich, 1) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 1
    assert AcCodeErrorCount(rich, "TypeMismatch") == 1
    assert AcCodeRow(rich, "TypeMismatch") == "TypeMismatch|Cannot pass `method group 'AcceptLong'` as argument for parameter `action` of type `Action<int>`|<null>|Error"
    assert AcCodeAnchor(rich, "TypeMismatch") == "NL202@11:21+10"
}

test "020 s31 analyzer error codes: byte, sbyte, short, ushort and char stackalloc lengths are all ACCEPTED, and the census is EMPTY — the deleted method asserted only that two particular codes were absent from a list that turns out to be empty, so both of its claims were VACUOUS; the empty census and the zero count are not (was AnalyzerTests.StackAlloc_SmallIntLengths_Accepted)" {
    source := "\nfunc Scratch(b: byte, s: short, c: char): int {\n    s1 := stackalloc byte[b]\n    s2 := stackalloc byte[s]\n    s3 := stackalloc byte[c]\n    return s1.Length + s2.Length + s3.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeCount(analysis, "UndefinedVariable") == 0
    assert AcCodeErrorCount(analysis, "UndefinedVariable") == 0
    assert AcCodeRow(analysis, "UndefinedVariable") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeCount(rich, "UndefinedVariable") == 0
    assert AcCodeErrorCount(rich, "UndefinedVariable") == 0
    assert AcCodeRow(rich, "UndefinedVariable") == "<no-such-code>"
}

test "020 s31 analyzer error codes: an aliased small-int stackalloc length is accepted with an EMPTY census — the second of the tranche's two vacuous-absence fixtures, pinned as silence rather than as two absent codes (was AnalyzerTests.StackAlloc_AliasedSmallIntLength_Accepted)" {
    source := "\ntype Count = short\n\nfunc Scratch(count: Count): int {\n    scratch := stackalloc byte[count]\n    return scratch.Length\n}"
    assert AcParseCensus(source) == ""
    assert AcParseSuccess(source) == "True"
    analysis := AcAnalyze(source)
    assert AcCensus(analysis) == ""
    assert AcHasErrors(analysis) == "False"
    assert AcErrorCount(analysis) == 0
    assert AcRow(analysis, 0) == "<no-such-error>"
    assert AcCodeCount(analysis, "TypeMismatch") == 0
    assert AcCodeErrorCount(analysis, "TypeMismatch") == 0
    assert AcCodeRow(analysis, "TypeMismatch") == "<no-such-code>"
    assert AcCodeCount(analysis, "UndefinedVariable") == 0
    assert AcCodeErrorCount(analysis, "UndefinedVariable") == 0
    assert AcCodeRow(analysis, "UndefinedVariable") == "<no-such-code>"
    rich := AcAnalyzeWithSource(source)
    assert AcCensus(rich) == ""
    assert AcHasErrors(rich) == "False"
    assert AcErrorCount(rich) == 0
    assert AcRow(rich, 0) == "<no-such-error>"
    assert AcCodeCount(rich, "TypeMismatch") == 0
    assert AcCodeErrorCount(rich, "TypeMismatch") == 0
    assert AcCodeRow(rich, "TypeMismatch") == "<no-such-code>"
    assert AcCodeCount(rich, "UndefinedVariable") == 0
    assert AcCodeErrorCount(rich, "UndefinedVariable") == 0
    assert AcCodeRow(rich, "UndefinedVariable") == "<no-such-code>"
}

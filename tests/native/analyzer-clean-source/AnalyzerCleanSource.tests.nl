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

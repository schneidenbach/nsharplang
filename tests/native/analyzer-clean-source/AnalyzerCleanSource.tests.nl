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

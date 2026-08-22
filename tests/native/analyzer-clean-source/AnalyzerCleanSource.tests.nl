namespace NSharpLang.AnalyzerCleanSource.Tests

import System
import System.Collections


// THE ANALYZER'S ASSIGNABILITY AND FLOW-NARROWING RULES, READ FROM SOURCE TEXT, IN N#.
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

func AcParseCensus(source: string): string {
    errors := AcRequiredMember(AcParse(source), "Errors") as IList
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

namespace NSharpLang.AnalyzerBindingMap.Tests

import System
import System.Collections


// THE ANALYZER'S BINDING MAP — GO-TO-DEFINITION AND FIND-ALL-REFERENCES — IN N#.
//
// These replace `tests/AnalyzerBindingMapTests.cs` WHOLE, which task 020 slice 24 deletes. All
// twelve of its `[Fact]`s ran the same three steps: parse with `ParseFileAst(source, "test.nl")`,
// analyse with the FOUR-argument `Analyze(unit, "test.nl", null, source)`, then ask
// `AnalysisResult.Bindings` — a `BindingMap` — either `GetBindingAt(file, line, column)` or
// `FindAllReferences(file, line, column)`.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT. `BindingMap`, `SymbolDeclaration` and
// `BindingReferenceResult` are ALL already N# in `NSharpLang.Compiler.BootstrapServices`. The one
// type that is not is `Analyzer`, the C# class in `Compiler.dll` that POPULATES the map while it
// walks, and `Compiler.dll` depends on the estate rather than the other way round — so the estate
// cannot reach it in any spelling. The route is reflection through `object`, the same one slice 23
// measured and `tests/native/analyzer-event-subscription` uses next door.
//
// THE CURSOR COLUMNS ARE THE DELETED ONES, COMPUTED BY THE DELETED HELPER ITSELF. Every position
// below was a runtime `FindColumn(source, line, needle, occurrence)` call — `line.IndexOf(needle)`
// plus one — and all eighteen were decoded by pasting the twelve verbatim fixtures AND that helper,
// unmodified, into a generated C# program and printing what it computed. Nothing is counted by hand.
//
// FIVE THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//   (a) THE WHOLE USAGE LIST. `Assert.True(usages.Count >= 2)` is the weakest claim in the deleted
//       file, and it was hiding something: the `Config` reference set is FIVE entries, and THREE of
//       them are the same position — `6:14`, the return type, is recorded three times. A `>=` could
//       not see it and a `Contains` could not either.
//   (b) THE DECLARATION KIND ON THE REFERENCE PATHS. `FindAllReferences` was asked for a name and a
//       position, never a kind; a function parameter's declaration reports Kind `variable`, not
//       `parameter`.
//   (c) THE ANALYSIS DIAGNOSTIC CENSUS. Eleven of the twelve fixtures analyse cleanly and the
//       shadowing one does NOT: it reports `NL203` on the lambda parameter. The deleted file read
//       `result.Bindings` and never looked at `result.Errors`.
//   (d) THE PARSE CENSUS. All twelve parse with an empty diagnostic list, so every binding below is
//       over a complete tree rather than a recovered one.
//   (e) A REFUSAL. Nothing in the deleted file asked what a position that binds NOTHING answers.

func SetBindingObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func BindingMember(owner: object, memberName: string): object? {
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

func BindingRequiredMember(owner: object, memberName: string): object {
    value := BindingMember(owner, memberName)
    if value == null {
        throw new InvalidOperationException("The production '" + memberName + "' member was null.")
    }

    return value
}

func BindingText(owner: object, memberName: string): string {
    value := BindingMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

// The production recovery parser, asked with the file name the deleted helper passed — which is the
// same name every lookup below passes, and the reason the lookups find anything at all.
func BindingParse(source: string): object {
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
    SetBindingObject(parseArguments, 0, source)
    SetBindingObject(parseArguments, 1, "test.nl")
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

// Every PARSE diagnostic, in recording order. The deleted helper asserted only that the unit was
// non-null and discarded this list.
func BindingParseCensus(source: string): string {
    errors := BindingRequiredMember(BindingParse(source), "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + BindingText(entry, "DiagnosticId") + "@" + BindingText(entry, "Line") + ":" + BindingText(entry, "Column") + "+" + BindingText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

// The production analysis — the FOUR-argument overload the deleted helper called, with the source
// text handed in, and the analyzer disposed afterwards.
func BindingAnalyze(source: string): object {
    unit := BindingRequiredMember(BindingParse(source), "CompilationUnit")

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
    SetBindingObject(analyzeArguments, 0, unit)
    SetBindingObject(analyzeArguments, 1, "test.nl")
    SetBindingObject(analyzeArguments, 2, null)
    SetBindingObject(analyzeArguments, 3, source)
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

func BindingAnalysisCensus(analysis: object): string {
    errors := BindingRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + BindingText(entry, "DiagnosticId") + ":" + BindingText(entry, "Code") + "@" + BindingText(entry, "Line") + ":" + BindingText(entry, "Column") + "+" + BindingText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

// The runtime type of `AnalysisResult.Bindings` — the reflection spelling of
// `Assert.IsType<BindingMap>(result.Bindings)`, which every one of the twelve deleted methods made.
func BindingMapKind(analysis: object): string {
    bindings := BindingMember(analysis, "Bindings")
    if bindings == null {
        return "<null>"
    }

    return bindings.GetType().Name
}

// `BindingMap.GetBindingAt(file, line, column)` rendered as name, kind and declaration anchor.
func BindingAt(analysis: object, line: int, column: int): string {
    bindings := BindingRequiredMember(analysis, "Bindings")
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(int)
    parameterTypes[2] = typeof(int)
    method := bindings.GetType().GetMethod("GetBindingAt", parameterTypes)
    if method == null {
        throw new InvalidOperationException("The production GetBindingAt entry point was not found.")
    }

    arguments := new object?[](3)
    SetBindingObject(arguments, 0, "test.nl")
    SetBindingObject(arguments, 1, line)
    SetBindingObject(arguments, 2, column)
    answer := method.Invoke(bindings, arguments)
    if answer == null {
        return "<unbound>"
    }

    return BindingText(answer, "Name") + ":" + BindingText(answer, "Kind") + "@" + BindingText(answer, "Line") + ":" + BindingText(answer, "Column")
}

// `BindingMap.FindAllReferences(file, line, column)` rendered as the declaration AND the WHOLE usage
// list in recording order, duplicates included.
func BindingReferences(analysis: object, line: int, column: int): string {
    bindings := BindingRequiredMember(analysis, "Bindings")
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(int)
    parameterTypes[2] = typeof(int)
    method := bindings.GetType().GetMethod("FindAllReferences", parameterTypes)
    if method == null {
        throw new InvalidOperationException("The production FindAllReferences entry point was not found.")
    }

    arguments := new object?[](3)
    SetBindingObject(arguments, 0, "test.nl")
    SetBindingObject(arguments, 1, line)
    SetBindingObject(arguments, 2, column)
    result := method.Invoke(bindings, arguments)
    if result == null {
        return "<no-result>"
    }

    declaration := BindingMember(result, "Declaration")
    text := "decl="
    if declaration == null {
        text = text + "<null>"
    } else {
        text = text + BindingText(declaration, "Name") + ":" + BindingText(declaration, "Kind") + "@" + BindingText(declaration, "Line") + ":" + BindingText(declaration, "Column")
    }

    usages := BindingMember(result, "Usages") as IList
    if usages == null {
        return text + " usages=<not-a-list>"
    }

    text = text + " usages=" + usages.Count.ToString() + "["
    index := 0
    while index < usages.Count {
        entry := usages[index]
        if entry != null {
            text = text + BindingText(entry, "Line") + ":" + BindingText(entry, "Column") + ";"
        }

        index = index + 1
    }

    return text + "]"
}


// ---- contracts ----

test "020 s24 binding map: an identifier inside an INTERPOLATION HOLE binds to its local declaration, and the reference walk answers the hole as that local's only usage (was AnalyzerBindingMapTests.AnalyzerBindingMap_InterpolatedIdentifier_ResolvesToDeclaration)" {
    source := "\nfunc test() {\n    name := \"Spencer\"\n    print $\"Hello, {name}!\"\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 4, 21) == "name:local@3:5"
    assert BindingReferences(analysis, 4, 21) == "decl=name:local@3:5 usages=1[4:21;]"
}

test "020 s24 binding map: a MEMBER ACCESS inside an interpolation hole binds to the record's field declaration (was AnalyzerBindingMapTests.AnalyzerBindingMap_InterpolatedMemberAccess_ResolvesToFieldDeclaration)" {
    source := "\nrecord Person {\n    Name: string\n}\n\nfunc test() {\n    person := new Person { Name: \"Spencer\" }\n    print $\"Hello, {person.Name}!\"\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 8, 28) == "Name:field@3:5"
}

test "020 s24 binding map: an identifier inside a RAW-STRING interpolation hole binds exactly as it does inside an ordinary one, three lines below its declaration (was AnalyzerBindingMapTests.AnalyzerBindingMap_InterpolatedRawStringIdentifier_ResolvesToDeclaration)" {
    source := "\nfunc test() {\n    name := \"Spencer\"\n    print $\"\"\"\nHello, {name}!\n\"\"\"\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 5, 9) == "name:local@3:5"
}

test "020 s24 binding map: a member access OUTSIDE any interpolation binds to the same field declaration as the interpolated one, so the hole is not a special case (was AnalyzerBindingMapTests.AnalyzerBindingMap_MemberAccess_ResolvesToPropertyDeclaration)" {
    source := "\nrecord Person {\n    Name: string\n}\n\nfunc test() {\n    person := new Person { Name: \"Spencer\" }\n    print person.Name\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 8, 18) == "Name:field@3:5"
}

test "020 s24 binding map: a local's TYPE ANNOTATION binds to the class declaration, whose Kind is `class` and whose anchor is the NAME rather than the keyword (was AnalyzerBindingMapTests.AnalyzerBindingMap_TypeAnnotation_RecordsBindingToTypeDeclaration)" {
    source := "\nclass Greeter {\n    Name: string\n}\n\nfunc test() {\n    g: Greeter = new Greeter()\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 7, 8) == "Greeter:class@2:7"
}

test "020 s24 binding map: a PARAMETER's type annotation binds to the record declaration, and the Kind is the declaration's own — `record`, not `class` (was AnalyzerBindingMapTests.AnalyzerBindingMap_TypeAnnotationInParameter_RecordsBinding)" {
    source := "\nrecord Point {\n    X: int\n    Y: int\n}\n\nfunc draw(p: Point) {\n    print p.X\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 7, 14) == "Point:record@2:8"
}

test "020 s24 binding map: a RETURN TYPE binds to the struct declaration, at the same column a parameter type binds from — the two annotation positions are not distinguished (was AnalyzerBindingMapTests.AnalyzerBindingMap_ReturnType_RecordsBinding)" {
    source := "\nstruct Vector {\n    X: float\n    Y: float\n}\n\nfunc make(): Vector {\n    return new Vector()\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 7, 14) == "Vector:struct@2:8"
}

test "020 s24 binding map: a FIELD's type annotation inside a class body binds to the record declaration above it (was AnalyzerBindingMapTests.AnalyzerBindingMap_FieldTypeAnnotation_RecordsBinding)" {
    source := "\nrecord Address {\n    City: string\n}\n\nclass Person {\n    Home: Address\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 7, 11) == "Address:record@2:8"
}

test "020 s24 binding map: find-all-references from a class NAME answers FIVE usages, and THREE of them are the same position — the return type at 6:14 is recorded three times, which the deleted `usages.Count >= 2` could not see (was AnalyzerBindingMapTests.AnalyzerBindingMap_FindAllReferences_IncludesTypeAnnotations)" {
    source := "\nclass Config {\n    Value: string\n}\n\nfunc make(): Config {\n    c: Config = new Config()\n    return c\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingReferences(analysis, 2, 7) == "decl=Config:class@2:7 usages=5[6:14;6:14;6:14;7:8;7:21;]"
}

test "020 s24 binding map: every COMPOSITE type position binds to the same declaration the bare name does — nullable, array, generic argument and delegate argument — and the generic's own name binds to its own record (was AnalyzerBindingMapTests.AnalyzerBindingMap_CompositeTypeUses_RecordSemanticBindings)" {
    source := "\nrecord Person {\n    Name: string\n}\n\nrecord Box<T> {\n    Value: T\n}\n\nfunc use(\n    maybe: Person?,\n    many: Person[],\n    box: Box<Person>,\n    mapper: Func<Person, string>\n) {\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingAt(analysis, 11, 12) == "Person:record@2:8"
    assert BindingAt(analysis, 12, 11) == "Person:record@2:8"
    assert BindingAt(analysis, 13, 10) == "Box:record@6:8"
    assert BindingAt(analysis, 13, 14) == "Person:record@2:8"
    assert BindingAt(analysis, 14, 18) == "Person:record@2:8"
}

test "020 s24 binding map: a function PARAMETER declares at its NAME span and its body use is its only reference — and the declaration's Kind is `variable`, not `parameter`, which nothing asserted (was AnalyzerBindingMapTests.AnalyzerBindingMap_FunctionParameter_DeclarationUsesParameterNameSpan)" {
    source := "\nfunc echo(value: int): int {\n    return value\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == ""
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingReferences(analysis, 2, 11) == "decl=value:variable@2:11 usages=1[3:12;]"
    assert BindingAt(analysis, 3, 12) == "value:variable@2:11"
}

test "020 s24 binding map: a LAMBDA PARAMETER shadowing an outer local keeps the two apart — the lambda body binds to the parameter and the line below binds to the outer local — and the fixture is NOT diagnostic-free: it reports NL203 on the parameter (was AnalyzerBindingMapTests.AnalyzerBindingMap_LambdaParameter_ShadowedNameDoesNotConflateOuterLocal)" {
    source := "\nfunc test(): void {\n    let value := 1\n    let apply := (value) => value + 1\n    print(value)\n}"
    assert BindingParseCensus(source) == ""
    analysis := BindingAnalyze(source)

    assert BindingAnalysisCensus(analysis) == "NL203:CannotInferType@4:19+5;"
    assert BindingMapKind(analysis) == "BindingMap"
    assert BindingReferences(analysis, 4, 19) == "decl=value:variable@4:19 usages=1[4:29;]"
    assert BindingAt(analysis, 4, 29) == "value:variable@4:19"
    assert BindingAt(analysis, 5, 11) == "value:local@3:9"
}

test "020 s24 binding map: THE REFUSAL — a position that binds nothing answers nothing, on the keyword before a bound identifier and on a line the fixture does not have; nothing in the deleted file asked, so every claim above was consistent with a map that answered the same declaration everywhere" {
    source := "\nfunc test() {\n    name := \"Spencer\"\n    print $\"Hello, {name}!\"\n}"
    analysis := BindingAnalyze(source)

    assert BindingAt(analysis, 4, 5) == "<unbound>"
    assert BindingAt(analysis, 99, 1) == "<unbound>"
    assert BindingReferences(analysis, 99, 1) == "decl=<null> usages=0[]"
}

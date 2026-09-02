namespace NSharpLang.AnalyzerIdentifierBinding.Tests

import System
import System.Collections


// THE ANALYZER'S IDENTIFIER BINDING AT AN INCOMPLETE MEMBER ACCESS, IN N#.
//
// These replace the ANALYZER HALF of `tests/AstNodeFinderTests.cs`, which task 020 slice 23 deletes.
// That file's five `[Fact]`s made 30 decoded claims between them; 21 were about
// `AstNodeFinder.FindExpressionAtPosition` and moved into the estate as
// `AstNodeFinderCore.tests.nl`, and the 9 recorded here are the ones its second and third methods
// made about the ANALYZER after the finder had answered: that the identifier the cursor sits behind
// binds to the declared class type, that the bound handle names the class, and that the class's
// declared members are the ones the source declares.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT, MEASURED RATHER THAN ASSUMED. Every
// other type in these contracts lives in `NSharpLang.Compiler.BootstrapServices` —
// `ColumnarParserRecovery`, `CompilationUnit`, `AnalysisResult`, `SemanticModel`, `ClassTypeInfo`
// and `DeclaredMemberInfo` are all N# classes in the estate. The ONE type that is not is
// `Analyzer`, the C# class in `Compiler.dll` that PRODUCES the `SemanticModel`, and `Compiler.dll`
// depends on the estate rather than the other way round. A `.tests.nl` inside BootstrapServices
// cannot reach it in any spelling, so the analyzer half of the deleted file has to leave the estate
// while the finder half stays in it.
//
// THE ROUTE IS REFLECTION, AND THAT IS A MEASURED CONSTRAINT RATHER THAN A STYLE CHOICE. A native
// project reaches a `dll:` dependency's types only through `object`: naming one of them in a local,
// an argument or a `new` declines columnar emission. The decline was measured three ways before
// this file was written — `new Analyzer()` (a C# type in `Compiler.dll`),
// `ColumnarParserRecovery.ParseFileAst(...)` bound to a local of its own `FileParseAst` return type
// (an N# type in the estate's own assembly), and `new SerializerBuilder()` (a `nuget:` type) all
// report `emit.local.initializer` / `emit.local.unsupported-type`. Static entry points whose values
// are all primitives DO bind directly, which is why `tests/native/parser-literal-facts` next door
// calls its owner by name. Nothing about a PROJECT reference would change this: the decline is in
// the emitter's type resolution, not in how the assembly arrives.
//
// FIVE THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//   (a) THE ANALYZER'S OWN DIAGNOSTIC CENSUS. The C# read `analysis.SemanticModel` and discarded
//       `analysis.Errors` entirely. Both fixtures end in a bare `p.`, and the measured answer is
//       that the analyzer reports NOTHING on either — the incomplete member access is the recovery
//       parser's diagnostic, and analysis adds none of its own.
//   (b) THE WHOLE DECLARED-MEMBER LIST, IN ORDER, WITH KIND AND ANCHOR. `Assert.Contains(members,
//       m => m.Name == "Name")` says a member with that name exists somewhere; the census below
//       says which members exist, in which order, of which kind and at which position.
//   (c) THE CLASS'S OWN ANCHOR. Neither method stated where `ClassTypeInfo` sits.
//   (d) THE BOUND CLASS NAME ON BOTH FIXTURES. The C# stated `Name == "Person"` on the second
//       fixture only.
//   (e) A REFUSAL. Nothing in the deleted file asked what an UNDECLARED identifier binds to.
func SetBindingObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// The estate models both fields and property accessors, and `FileParseAst.CompilationUnit` is a
// FIELD while `AnalysisResult.SemanticModel` is a property, so every read tries both.
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

// The production recovery parser — the same entry point the estate's finder contracts drive, asked
// here through reflection because this project reaches the estate as a compiled assembly.
func ParseUnit(source: string, fileName: string): object {
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
    SetBindingObject(parseArguments, 1, fileName)
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return BindingRequiredMember(parsed, "CompilationUnit")
}

// The production analysis — `new Analyzer()`, `LoadSystemAssemblies()` and the four-argument
// `Analyze(unit, currentFilePath, projectRoot, sourceCode)`, exactly the sequence the deleted C#
// ran, with the analyzer disposed afterwards as its `using` did.
func AnalyzeSource(source: string, filePath: string, projectRoot: string?): object {
    unit := ParseUnit(source, filePath)

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
        throw new InvalidOperationException("The production Analyze entry point was not found.")
    }

    analyzeArguments := new object?[](4)
    SetBindingObject(analyzeArguments, 0, unit)
    SetBindingObject(analyzeArguments, 1, filePath)
    SetBindingObject(analyzeArguments, 2, projectRoot)
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

// Every analysis diagnostic's id and position, in recording order. Empty when analysis is silent.
func AnalyzerCensus(analysis: object): string {
    errors := BindingRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + BindingText(entry, "DiagnosticId") + "@" + BindingText(entry, "Line") + ":" + BindingText(entry, "Column") + ";"
        }

        index = index + 1
    }

    return census
}

func LookupBound(analysis: object, identifier: string): object? {
    model := BindingRequiredMember(analysis, "SemanticModel")

    lookupParameterTypes := new Type[](1)
    lookupParameterTypes[0] = typeof(string)
    lookupMethod := model.GetType().GetMethod("LookupIdentifier", lookupParameterTypes)
    if lookupMethod == null {
        throw new InvalidOperationException("The production LookupIdentifier entry point was not found.")
    }

    lookupArguments := new object?[](1)
    SetBindingObject(lookupArguments, 0, identifier)
    return lookupMethod.Invoke(model, lookupArguments)
}

// The runtime type of the bound handle — the reflection spelling of `Assert.IsType<ClassTypeInfo>`.
func BoundKind(analysis: object, identifier: string): string {
    bound := LookupBound(analysis, identifier)
    if bound == null {
        return "<unbound>"
    }

    return bound.GetType().Name
}

func BoundName(analysis: object, identifier: string): string {
    bound := LookupBound(analysis, identifier)
    if bound == null {
        return "<unbound>"
    }

    return BindingText(bound, "Name")
}

func BoundAnchor(analysis: object, identifier: string): string {
    bound := LookupBound(analysis, identifier)
    if bound == null {
        return "<unbound>"
    }

    return BindingText(bound, "Line") + ":" + BindingText(bound, "Column")
}

// Every declared member, in declaration order, with its kind name and its anchor.
func BoundMemberCensus(analysis: object, identifier: string): string {
    bound := LookupBound(analysis, identifier)
    if bound == null {
        return "<unbound>"
    }

    members := BindingRequiredMember(bound, "DeclaredMembers") as IList
    if members == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < members.Count {
        entry := members[index]
        if entry != null {
            census = census + BindingText(entry, "Name") + ":" + BindingText(entry, "KindName") + "@" + BindingText(entry, "Line") + ":" + BindingText(entry, "Column") + ";"
        }

        index = index + 1
    }

    return census
}

// ---- contracts ----

test "020 s23 analyzer binding: the identifier behind a bare dot binds to the DECLARED class type, whose name, anchor and one-field member list are all stated, and analysis itself reports nothing (was AstNodeFinderTests.ReturnsIncompleteMemberAccessAtDotCursor, analyzer half)" {
    source := "\nclass Person {\n    Name: string\n}\n\nfunc main(): void\n    let p = new Person()\n    p."
    analysis := AnalyzeSource(source, "test.nl", null)

    assert AnalyzerCensus(analysis) == ""
    assert BoundKind(analysis, "p") == "ClassTypeInfo"
    assert BoundName(analysis, "p") == "Person"
    assert BoundAnchor(analysis, "p") == "2:1"
    assert BoundMemberCensus(analysis, "p") == "Name:field@3:5;"
}

test "020 s23 analyzer binding: the three-member class binds the same way and its member census pins ORDER, KIND and ANCHOR where the deleted assertions asked only whether a name was present (was AstNodeFinderTests.ReturnsIncompleteMemberAccessForCompletionSource, analyzer half)" {
    source := "\nclass Person {\n    Name: string\n    Age: int\n\n    func Greet(): string {\n        return \"Hello\"\n    }\n}\n\nfunc main(): void\n    let p = new Person()\n    p."
    analysis := AnalyzeSource(source, "/test/nsharp-class.nl", "/test")

    assert AnalyzerCensus(analysis) == ""
    assert BoundKind(analysis, "p") == "ClassTypeInfo"
    assert BoundName(analysis, "p") == "Person"
    assert BoundAnchor(analysis, "p") == "2:1"
    assert BoundMemberCensus(analysis, "p") == "Name:field@3:5;Age:field@4:5;Greet:function@6:5;"
}

test "020 s23 analyzer binding: the file path and project root the deleted methods varied between them do not move the binding — the three-member fixture analysed as an anonymous test file with NO project root answers byte-identically" {
    source := "\nclass Person {\n    Name: string\n    Age: int\n\n    func Greet(): string {\n        return \"Hello\"\n    }\n}\n\nfunc main(): void\n    let p = new Person()\n    p."
    rooted := AnalyzeSource(source, "/test/nsharp-class.nl", "/test")
    anonymous := AnalyzeSource(source, "test.nl", null)

    assert BoundKind(anonymous, "p") == BoundKind(rooted, "p")
    assert BoundName(anonymous, "p") == BoundName(rooted, "p")
    assert BoundAnchor(anonymous, "p") == BoundAnchor(rooted, "p")
    assert BoundMemberCensus(anonymous, "p") == BoundMemberCensus(rooted, "p")
    assert AnalyzerCensus(anonymous) == AnalyzerCensus(rooted)
}

test "020 s23 analyzer binding: an identifier the fixture never declares binds to NOTHING — a refusal the deleted file never asked for, and the guard that keeps the three claims above from passing on a permissive lookup" {
    source := "\nclass Person {\n    Name: string\n}\n\nfunc main(): void\n    let p = new Person()\n    p."
    analysis := AnalyzeSource(source, "test.nl", null)

    assert BoundKind(analysis, "q") == "<unbound>"
    assert BoundName(analysis, "q") == "<unbound>"
    assert BoundAnchor(analysis, "q") == "<unbound>"
    assert BoundMemberCensus(analysis, "q") == "<unbound>"
}

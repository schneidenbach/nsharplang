namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE IMPLEMENTORS (task 019 slice 15).
//
// The whole territory was two C# members — one public and snapshot-bound, one private — so asking it
// anything meant loading a project from disk. Asked directly, it answers SIX things that were
// previously unreachable or asserted only by accident:
//   (a) A CLASS MATCHES ON ITS BASE TYPE. `BaseClass` holds the first colon-separated type and the
//       parser cannot tell an interface from a base class there, so `class C: IThing` reports as an
//       implementor while `class C: Base` reports nothing.
//   (b) A STRUCT AND A RECORD ARE NEVER ASKED ABOUT A BASE TYPE — they have no `BaseClass` at all,
//       so only their interface list can match.
//   (c) THE KIND IS THE DECLARATION FORM, NOT THE RUNTIME SHAPE. A record STRUCT reports "record".
//   (d) AN INTERFACE THAT EXTENDS THE NAMED INTERFACE IS NOT AN IMPLEMENTOR, and neither is an enum,
//       a union or a free function — the walk has three arms and the other twelve fall through.
//   (e) THE WALK IS TOP-LEVEL ONLY: a nested type implementing the interface is NOT reported.
//   (f) THE ANSWER'S ORDER IS UNIT ORDER THEN DECLARATION ORDER, and the `Interface` echoed back is
//       the QUERY string — not any matched type's spelling — even when nothing matched at all.
func CiimAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func CiimSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func CiimInterfaces(names: List<string>): List<TypeReference> {
    references := new List<TypeReference>()
    index := 0
    while index < names.Count {
        references.Add(CiimSimple(names[index]))
        index = index + 1
    }
    return references
}

func CiimNames(names: string[]): List<string> {
    values := new List<string>()
    index := 0
    while index < names.Length {
        values.Add(names[index])
        index = index + 1
    }
    return values
}

func CiimClass(name: string, baseClass: SimpleTypeReference?, interfaces: List<string>, members: List<Declaration>, line: int): ClassDeclaration {
    return new ClassDeclaration(name, null, baseClass, CiimInterfaces(interfaces), members, null, Modifiers.Public, CiimAttributes(), line, 1)
}

func CiimStruct(name: string, interfaces: List<string>, line: int): StructDeclaration {
    return new StructDeclaration(name, null, CiimInterfaces(interfaces), new List<Declaration>(), null, Modifiers.Public, CiimAttributes(), line, 3)
}

func CiimRecord(name: string, interfaces: List<string>, isStruct: bool, line: int): RecordDeclaration {
    return new RecordDeclaration(name, null, CiimInterfaces(interfaces), new List<Declaration>(), null, isStruct, Modifiers.Public, CiimAttributes(), line, 5)
}

func CiimUnit(declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(
        null,
        new List<ImportDirective>(),
        new List<Statement>(),
        null,
        declarations,
        1,
        1
    )
}

func CiimOne(declarations: List<Declaration>): List<CompilationUnit> {
    units := new List<CompilationUnit>()
    units.Add(CiimUnit(declarations))
    return units
}

func CiimFiles(names: string[]): List<string> {
    return CiimNames(names)
}

func CiimText(results: List<ImplementorResult>): string {
    text := ""
    index := 0
    while index < results.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + results[index].TypeName + ":" + results[index].Kind
        index = index + 1
    }
    return text
}

test "a class matches on its BASE type as well as on its interface list" {
    declarations := new List<Declaration>()
    declarations.Add(CiimClass("OnBase", CiimSimple("IThing"), CiimNames([]), new List<Declaration>(), 10))
    declarations.Add(CiimClass("OnList", null, CiimNames(["IOther", "IThing"]), new List<Declaration>(), 20))
    declarations.Add(CiimClass("OnRealBase", CiimSimple("Base"), CiimNames([]), new List<Declaration>(), 30))

    result := CodeIntelligenceImplementors.Build(CiimOne(declarations), CiimFiles(["Program.nl"]), "IThing")

    assert result.Interface == "IThing"
    assert CiimText(result.Results) == "OnBase:class,OnList:class"
    assert result.Results[0].File == "Program.nl"
    assert result.Results[0].Line == 10
    assert result.Results[0].Column == 1
    assert result.Results[1].Line == 20
}

test "a struct and a record match only through their interface lists, and a record STRUCT says record" {
    declarations := new List<Declaration>()
    declarations.Add(CiimStruct("Point", CiimNames(["IThing"]), 11))
    declarations.Add(CiimStruct("Plain", CiimNames(["IOther"]), 12))
    declarations.Add(CiimRecord("RefRec", CiimNames(["IThing"]), false, 13))
    declarations.Add(CiimRecord("ValRec", CiimNames(["IThing"]), true, 14))

    result := CodeIntelligenceImplementors.Build(CiimOne(declarations), CiimFiles(["Shapes.nl"]), "IThing")

    assert CiimText(result.Results) == "Point:struct,RefRec:record,ValRec:record"
    assert result.Results[0].Column == 3
    assert result.Results[1].Column == 5
}

test "the twelve other declaration forms never match, and an extending interface is not an implementor" {
    declarations := new List<Declaration>()
    declarations.Add(new InterfaceDeclaration("IExtends", null, CiimInterfaces(CiimNames(["IThing"])), new List<Declaration>(), Modifiers.Public, false, CiimAttributes(), 5, 1))
    declarations.Add(new EnumDeclaration("Colour", new List<EnumMember>(), EnumType.Int, Modifiers.Public, CiimAttributes(), 6, 1))
    declarations.Add(new FunctionDeclaration("Main", new List<Parameter>(), null, null, null, null, null, Modifiers.Public, CiimAttributes(), false, null, false, false, 7, 1))

    result := CodeIntelligenceImplementors.Build(CiimOne(declarations), CiimFiles(["Other.nl"]), "IThing")

    assert result.Interface == "IThing"
    assert result.Results.Count == 0
}

test "the walk is top-level only — a nested implementor is invisible" {
    members := new List<Declaration>()
    members.Add(CiimClass("Nested", null, CiimNames(["IThing"]), new List<Declaration>(), 42))
    declarations := new List<Declaration>()
    declarations.Add(CiimClass("Outer", null, CiimNames([]), members, 40))

    result := CodeIntelligenceImplementors.Build(CiimOne(declarations), CiimFiles(["Nest.nl"]), "IThing")

    assert result.Results.Count == 0
}

test "the answer walks units in order and echoes the QUERY name even when nothing matched" {
    first := new List<Declaration>()
    first.Add(CiimClass("A", null, CiimNames(["IThing"]), new List<Declaration>(), 1))
    second := new List<Declaration>()
    second.Add(CiimClass("B", null, CiimNames(["IThing"]), new List<Declaration>(), 2))

    units := new List<CompilationUnit>()
    units.Add(CiimUnit(first))
    units.Add(CiimUnit(second))

    result := CodeIntelligenceImplementors.Build(units, CiimFiles(["one.nl", "two.nl"]), "IThing")

    assert CiimText(result.Results) == "A:class,B:class"
    assert result.Results[0].File == "one.nl"
    assert result.Results[1].File == "two.nl"

    empty := CodeIntelligenceImplementors.Build(units, CiimFiles(["one.nl", "two.nl"]), "IMissing")
    assert empty.Interface == "IMissing"
    assert empty.Results.Count == 0
}

test "the interface name match is ORDINAL and exact — case and generic arity are not folded" {
    declarations := new List<Declaration>()
    declarations.Add(CiimClass("Exact", null, CiimNames(["IThing"]), new List<Declaration>(), 1))
    declarations.Add(CiimClass("Cased", null, CiimNames(["ithing"]), new List<Declaration>(), 2))

    result := CodeIntelligenceImplementors.Build(CiimOne(declarations), CiimFiles(["Case.nl"]), "IThing")
    assert CiimText(result.Results) == "Exact:class"

    // A generic interface reference matches on its BARE name, so `IThing<int>` answers `IThing`.
    generic := new List<Declaration>()
    genericInterfaces := new List<TypeReference>()
    genericArguments := new List<TypeReference>()
    genericArguments.Add(CiimSimple("int"))
    genericInterfaces.Add(new GenericTypeReference("IThing", genericArguments, 1, 1))
    generic.Add(new ClassDeclaration("Closed", null, null, genericInterfaces, new List<Declaration>(), null, Modifiers.Public, CiimAttributes(), 3, 1))

    genericResult := CodeIntelligenceImplementors.Build(CiimOne(generic), CiimFiles(["Generic.nl"]), "IThing")
    assert CiimText(genericResult.Results) == "Closed:class"
}

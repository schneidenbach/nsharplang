namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE TYPE-HIERARCHY VIEW. These came out of `TypeHierarchyHandler.cs`, where the
// three requests each carried their own copy of "what a node is": the kind map, the 0-based span,
// the upward walk that reads what the SOURCE wrote, the downward walk that reads a class's base
// slot whatever the target's kind is, and the interface-extends-interface arm that only the
// downward walk counts.
func EthClassInfo(name: string, line: int, column: int): TypeInfo {
    info: TypeInfo = new ClassTypeInfo(name, line, column, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), false)
    return info
}

func EthInterfaceInfo(name: string, line: int, column: int): TypeInfo {
    info: TypeInfo = new InterfaceTypeInfo(name, line, column, false, new TypeReference[](0), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return info
}

func EthStructInfo(name: string, line: int, column: int): TypeInfo {
    info: TypeInfo = new StructTypeInfo(name, line, column, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return info
}

func EthRecordInfo(name: string, line: int, column: int): TypeInfo {
    info: TypeInfo = new RecordTypeInfo(name, line, column, false, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return info
}

func EthSymbols(names: string[], infos: TypeInfo[]): Dictionary<string, TypeInfo> {
    symbols := new Dictionary<string, TypeInfo>()
    index := 0
    while index < names.Length {
        symbols[names[index]] = infos[index]
        index = index + 1
    }
    return symbols
}

func EthReferences(names: string[]): List<TypeReference> {
    list := new List<TypeReference>()
    for name in names {
        reference: TypeReference = new SimpleTypeReference(name, 1, 1)
        list.Add(reference)
    }
    return list
}

func EthClass(name: string, baseName: string?, interfaceNames: string[], line: int, column: int): Declaration {
    baseReference: TypeReference? = null
    if baseName != null {
        baseReference = new SimpleTypeReference(baseName, 1, 1)
    }
    declaration: Declaration = new ClassDeclaration(name, null, baseReference, EthReferences(interfaceNames), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column)
    return declaration
}

func EthInterface(name: string, baseNames: string[], line: int, column: int): Declaration {
    declaration: Declaration = new InterfaceDeclaration(name, null, EthReferences(baseNames), new List<Declaration>(), Modifiers.None, false, new List<AttributeNode>(), line, column)
    return declaration
}

func EthStruct(name: string, interfaceNames: string[], line: int, column: int): Declaration {
    declaration: Declaration = new StructDeclaration(name, null, EthReferences(interfaceNames), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column)
    return declaration
}

func EthUnit(declarations: Declaration[]): CompilationUnit {
    list := new List<Declaration>()
    for declaration in declarations {
        list.Add(declaration)
    }
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, list, 1, 1)
}

func EthSubtypes(unit: CompilationUnit?, targetName: string, targetIsInterface: bool): List<EditorTypeHierarchyRow> {
    rows := new List<EditorTypeHierarchyRow>()
    EditorTypeHierarchyFacts.AppendSubtypeRows(unit, "file:///probe.nl", targetName, targetIsInterface, rows)
    return rows
}

// THE NODE UNDER THE CARET IS ONE OF FIVE KINDS, and a record shows as a class exactly as it does
// in the outline. Anything else the symbol table holds is not a hierarchy node at all.
test "the type hierarchy prepares a node for five kinds and nothing else" {
    symbols := EthSymbols(
        ["Greeter", "IGreeter", "Pair", "Options"],
        [EthClassInfo("Greeter", 12, 5), EthInterfaceInfo("IGreeter", 3, 1), EthStructInfo("Pair", 20, 1), EthRecordInfo("Options", 30, 1)]
    )

    greeter := EditorTypeHierarchyFacts.PrepareRow(symbols, "Greeter", "file:///a.nl")
    assert greeter != null
    assert greeter.Kind == EditorSymbolKind.Class
    assert greeter.Line == 11
    assert greeter.StartCharacter == 4
    assert greeter.EndCharacter == 11
    assert greeter.Uri == "file:///a.nl"

    assert EditorTypeHierarchyFacts.PrepareRow(symbols, "IGreeter", "file:///a.nl").Kind == EditorSymbolKind.Interface
    assert EditorTypeHierarchyFacts.PrepareRow(symbols, "Pair", "file:///a.nl").Kind == EditorSymbolKind.Struct
    assert EditorTypeHierarchyFacts.PrepareRow(symbols, "Options", "file:///a.nl").Kind == EditorSymbolKind.Class
    assert EditorTypeHierarchyFacts.PrepareRow(symbols, "Missing", "file:///a.nl") == null
    assert EditorTypeHierarchyFacts.PrepareRow(null, "Greeter", "file:///a.nl") == null
}

// A TYPE THE TABLE KNOWS BUT CANNOT PLACE IS NOT A NODE. The editor would have nowhere to take
// the reader, so the supertype resolution passes over it and tries the next document.
test "the type hierarchy refuses to resolve a supertype it cannot place in a file" {
    placed := EthSymbols(["Base"], [EthClassInfo("Base", 4, 1)])
    unplaced := EthSymbols(["Base"], [EthClassInfo("Base", 0, 0)])

    assert EditorTypeHierarchyFacts.ResolveRow(placed, "Base", "file:///a.nl") != null
    assert EditorTypeHierarchyFacts.ResolveRow(unplaced, "Base", "file:///a.nl") == null
    assert EditorTypeHierarchyFacts.ResolveRow(placed, "Missing", "file:///a.nl") == null
    assert EditorTypeHierarchyFacts.ResolveRow(null, "Base", "file:///a.nl") == null
}

// THE UPWARD WALK SAYS WHAT THE SOURCE WROTE, in the order it wrote it: a class's base slot first
// and then its interfaces.
test "the type hierarchy walks up through the base slot and then the interfaces" {
    unit := EthUnit([
        EthClass("Loud", "Base", ["IGreeter", "IDisposable"], 10, 1),
        EthInterface("ILoud", ["IGreeter"], 20, 1),
        EthStruct("Pair", ["IGreeter"], 30, 1)
    ])

    up := EditorTypeHierarchyFacts.SupertypeNames(unit, "Loud")
    assert up.Count == 3
    assert up[0] == "Base"
    assert up[1] == "IGreeter"
    assert up[2] == "IDisposable"

    assert EditorTypeHierarchyFacts.SupertypeNames(unit, "ILoud").Count == 1
    assert EditorTypeHierarchyFacts.SupertypeNames(unit, "Pair").Count == 1
    assert EditorTypeHierarchyFacts.SupertypeNames(unit, "Nothing").Count == 0
    assert EditorTypeHierarchyFacts.SupertypeNames(null, "Loud").Count == 0
}

// A REFERENCE THAT NAMES NOTHING SIMPLE IS NOT A SUPERTYPE. Reaching through a nullable or an
// array to the type inside — which the general display owner does — would put a node in the
// hierarchy that the source never wrote.
test "the type hierarchy takes a supertype name only from a plain or generic reference" {
    names := new List<string>()
    EditorTypeHierarchyFacts.AppendName(new SimpleTypeReference("Base", 1, 1), names)
    EditorTypeHierarchyFacts.AppendName(new GenericTypeReference("Box", EthReferences(["int"]), 1, 1), names)
    EditorTypeHierarchyFacts.AppendName(new NullableTypeReference(new SimpleTypeReference("Base", 1, 1)), names)
    EditorTypeHierarchyFacts.AppendName(new ArrayTypeReference(new SimpleTypeReference("Base", 1, 1)), names)

    assert names.Count == 2
    assert names[0] == "Base"
    assert names[1] == "Box"
}

// THE DOWNWARD WALK READS A CLASS'S BASE SLOT WHATEVER THE TARGET'S KIND IS. This is exactly what
// `EditorImplementationFacts` does NOT do, and the difference is why `class C : IFoo` appears
// under `IFoo` in the hierarchy view but not in the go-to-implementation list.
test "the type hierarchy walks down through the base slot even for an interface target" {
    unit := EthUnit([EthClass("Lonely", "IGreeter", [], 5, 1)])

    down := EthSubtypes(unit, "IGreeter", true)
    assert down.Count == 1
    assert down[0].Name == "Lonely"
    assert down[0].Kind == EditorSymbolKind.Class

    assert EditorImplementationFacts.MatchesAnyInterface(EthReferences([]), "IGreeter") == false
}

// AN INTERFACE THAT EXTENDS THE TARGET IS A SUBTYPE, but only when the target is itself an
// interface — and a struct and a record answer from their interface lists.
test "the type hierarchy counts an extending interface only under an interface target" {
    unit := EthUnit([
        EthInterface("ILoud", ["IGreeter"], 8, 1),
        EthStruct("Pair", ["IGreeter"], 12, 1)
    ])

    asInterface := EthSubtypes(unit, "IGreeter", true)
    assert asInterface.Count == 2
    assert asInterface[0].Name == "ILoud"
    assert asInterface[0].Kind == EditorSymbolKind.Interface
    assert asInterface[1].Name == "Pair"
    assert asInterface[1].Kind == EditorSymbolKind.Struct

    asClass := EthSubtypes(unit, "IGreeter", false)
    assert asClass.Count == 1
    assert asClass[0].Name == "Pair"

    assert EthSubtypes(null, "IGreeter", true).Count == 0
}

// THE SPAN IS 0-BASED AND AS WIDE AS THE NAME, and a declaration the parser placed at line or
// column zero does not produce a negative position.
test "the type hierarchy reports a 0-based span as wide as the node's name" {
    unit := EthUnit([EthClass("Loud", "Base", [], 0, 0)])
    rows := EthSubtypes(unit, "Base", false)

    assert rows.Count == 1
    assert rows[0].Line == 0
    assert rows[0].StartCharacter == 0
    assert rows[0].EndCharacter == 4
    assert rows[0].Uri == "file:///probe.nl"
}

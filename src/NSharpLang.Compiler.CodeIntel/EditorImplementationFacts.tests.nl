namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR GO-TO-IMPLEMENTATION. These came out of `GoToImplementationHandler.cs`, where they
// could only be reached through an OmniSharp request over a live document manager: the kind gate
// on what the caret is on, the asymmetry between asking about a class and asking about an
// interface, the per-file semantic verification, and the 0-based span the editor highlights.
func EifTypeReferences(names: string[]): List<TypeReference> {
    list := new List<TypeReference>()
    for name in names {
        reference: TypeReference = new SimpleTypeReference(name, 1, 1)
        list.Add(reference)
    }
    return list
}

func EifClass(name: string, baseName: string?, interfaceNames: string[], line: int, column: int): Declaration {
    baseReference: TypeReference? = null
    if baseName != null {
        baseReference = new SimpleTypeReference(baseName, 1, 1)
    }

    declaration: Declaration = new ClassDeclaration(name, null, baseReference, EifTypeReferences(interfaceNames), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column)
    return declaration
}

func EifStruct(name: string, interfaceNames: string[], line: int, column: int): Declaration {
    declaration: Declaration = new StructDeclaration(name, null, EifTypeReferences(interfaceNames), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column)
    return declaration
}

func EifRecord(name: string, interfaceNames: string[], line: int, column: int): Declaration {
    declaration: Declaration = new RecordDeclaration(name, null, EifTypeReferences(interfaceNames), new List<Declaration>(), null, false, Modifiers.None, new List<AttributeNode>(), line, column)
    return declaration
}

func EifUnit(declarations: Declaration[]): CompilationUnit {
    list := new List<Declaration>()
    for declaration in declarations {
        list.Add(declaration)
    }
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, list, 1, 1)
}

func EifClassInfo(name: string): TypeInfo {
    info: TypeInfo = new ClassTypeInfo(name, 0, 0, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), false)
    return info
}

func EifStructInfo(name: string): TypeInfo {
    info: TypeInfo = new StructTypeInfo(name, 0, 0, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return info
}

func EifRecordInfo(name: string): TypeInfo {
    info: TypeInfo = new RecordTypeInfo(name, 0, 0, false, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return info
}

func EifInterfaceInfo(name: string): TypeInfo {
    info: TypeInfo = new InterfaceTypeInfo(name, 0, 0, false, new TypeReference[](0), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return info
}

func EifSymbols(names: string[], infos: TypeInfo[]): Dictionary<string, TypeInfo> {
    symbols := new Dictionary<string, TypeInfo>()
    index := 0
    while index < names.Length {
        symbols[names[index]] = infos[index]
        index = index + 1
    }
    return symbols
}

func EifRows(unit: CompilationUnit?, symbols: Dictionary<string, TypeInfo>?, targetName: string, kind: EditorImplementationTarget): List<EditorImplementorRow> {
    rows := new List<EditorImplementorRow>()
    EditorImplementationFacts.AppendImplementorRows(unit, symbols, "file:///probe.nl", targetName, kind, rows)
    return rows
}

// ONLY AN INTERFACE OR A CLASS HAS IMPLEMENTATIONS. Everything else the caret can sit on — a
// struct, a record, a name the file never declared, a file with no symbol table yet — is `None`,
// and `None` is how the handler declines without inventing a failure.
test "go to implementation recognises only an interface or a class as a target" {
    symbols := EifSymbols(
        ["IGreeter", "Greeter", "Pair", "Options"],
        [EifInterfaceInfo("IGreeter"), EifClassInfo("Greeter"), EifStructInfo("Pair"), EifRecordInfo("Options")]
    )

    assert EditorImplementationFacts.TargetKind(symbols, "IGreeter") == EditorImplementationTarget.Interface
    assert EditorImplementationFacts.TargetKind(symbols, "Greeter") == EditorImplementationTarget.Class
    assert EditorImplementationFacts.TargetKind(symbols, "Pair") == EditorImplementationTarget.None
    assert EditorImplementationFacts.TargetKind(symbols, "Options") == EditorImplementationTarget.None
    assert EditorImplementationFacts.TargetKind(symbols, "Missing") == EditorImplementationTarget.None
    assert EditorImplementationFacts.TargetKind(null, "IGreeter") == EditorImplementationTarget.None
}

// THE BASE-CLASS ARM IS READ ONLY WHEN THE TARGET IS A CLASS, and this is the asymmetry that
// decides what `class C : IFoo` answers. The parser records the FIRST colon-separated type as the
// base class whatever it really is, so asking about the interface does NOT find that class — only
// a class that lists the interface after a base does.
test "go to implementation reads the base class only when the target is a class" {
    unit := EifUnit([
        EifClass("Loud", "Base", [], 10, 1),
        EifClass("Quiet", "Base", ["IGreeter"], 20, 1),
        EifClass("Lonely", "IGreeter", [], 30, 1)
    ])
    symbols := EifSymbols(
        ["Base", "IGreeter", "Loud", "Quiet", "Lonely"],
        [EifClassInfo("Base"), EifInterfaceInfo("IGreeter"), EifClassInfo("Loud"), EifClassInfo("Quiet"), EifClassInfo("Lonely")]
    )

    asClass := EifRows(unit, symbols, "Base", EditorImplementationTarget.Class)
    assert asClass.Count == 2
    assert asClass[0].Name == "Loud"
    assert asClass[1].Name == "Quiet"

    asInterface := EifRows(unit, symbols, "IGreeter", EditorImplementationTarget.Interface)
    assert asInterface.Count == 1
    assert asInterface[0].Name == "Quiet"
}

// A STRUCT AND A RECORD ANSWER FROM THEIR INTERFACE LIST ALONE — neither has a base type that
// could be confused with one.
test "go to implementation finds a struct and a record through their interface list" {
    unit := EifUnit([
        EifStruct("Pair", ["IGreeter"], 5, 1),
        EifRecord("Options", ["IGreeter"], 9, 1)
    ])
    symbols := EifSymbols(
        ["IGreeter", "Pair", "Options"],
        [EifInterfaceInfo("IGreeter"), EifStructInfo("Pair"), EifRecordInfo("Options")]
    )

    rows := EifRows(unit, symbols, "IGreeter", EditorImplementationTarget.Interface)
    assert rows.Count == 2
    assert rows[0].Name == "Pair"
    assert rows[1].Name == "Options"
}

// AN INTERFACE THAT EXTENDS ANOTHER IS NOT AN IMPLEMENTATION OF IT. The semantic check refuses
// any implementor the finding file knows as an interface, which is the rule that keeps an
// interface hierarchy out of the implementation list.
test "go to implementation refuses an implementor the file knows as an interface" {
    unit := EifUnit([EifClass("ILoud", null, ["IGreeter"], 4, 1)])
    symbols := EifSymbols(["IGreeter", "ILoud"], [EifInterfaceInfo("IGreeter"), EifInterfaceInfo("ILoud")])

    assert EifRows(unit, symbols, "IGreeter", EditorImplementationTarget.Interface).Count == 0
}

// THE FINDING FILE MUST KNOW BOTH NAMES. A file whose text says it implements the target but whose
// own symbol table has never heard of the implementor, or of the target, is a coincidence of
// spelling and is not offered.
test "go to implementation verifies both names against the finding file's own symbols" {
    unit := EifUnit([EifClass("Greeter", null, ["IGreeter"], 6, 1)])

    unknownImplementor := EifSymbols(["IGreeter"], [EifInterfaceInfo("IGreeter")])
    assert EifRows(unit, unknownImplementor, "IGreeter", EditorImplementationTarget.Interface).Count == 0

    unknownTarget := EifSymbols(["Greeter"], [EifClassInfo("Greeter")])
    assert EifRows(unit, unknownTarget, "IGreeter", EditorImplementationTarget.Interface).Count == 0

    targetIsNotAType := EifSymbols(["IGreeter", "Greeter"], [EifStructInfo("IGreeter"), EifClassInfo("Greeter")])
    assert EifRows(unit, targetIsNotAType, "IGreeter", EditorImplementationTarget.Interface).Count == 0

    assert EifRows(unit, null, "IGreeter", EditorImplementationTarget.Interface).Count == 0
    assert EifRows(null, unknownImplementor, "IGreeter", EditorImplementationTarget.Interface).Count == 0
}

// THE SPAN IS 0-BASED AND AS WIDE AS THE NAME, measured from where the DECLARATION begins. A
// declaration the parser placed at line or column zero does not produce a negative position.
test "go to implementation reports a 0-based span as wide as the implementor's name" {
    unit := EifUnit([EifClass("Greeter", null, ["IGreeter"], 12, 5), EifClass("X", null, ["IGreeter"], 0, 0)])
    symbols := EifSymbols(
        ["IGreeter", "Greeter", "X"],
        [EifInterfaceInfo("IGreeter"), EifClassInfo("Greeter"), EifClassInfo("X")]
    )

    rows := EifRows(unit, symbols, "IGreeter", EditorImplementationTarget.Interface)
    assert rows.Count == 2
    assert rows[0].Uri == "file:///probe.nl"
    assert rows[0].Line == 11
    assert rows[0].StartCharacter == 4
    assert rows[0].EndCharacter == 11

    assert rows[1].Line == 0
    assert rows[1].StartCharacter == 0
    assert rows[1].EndCharacter == 1
}

// THE WALK IS TOP-LEVEL ONLY. A nested type that implements the target is not offered, because
// the walk never descends into a declaration's members.
test "go to implementation does not descend into nested declarations" {
    nested := EifClass("Inner", null, ["IGreeter"], 8, 5)
    members := new List<Declaration>()
    members.Add(nested)
    outer: Declaration = new ClassDeclaration("Outer", null, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), 6, 1)

    symbols := EifSymbols(
        ["IGreeter", "Outer", "Inner"],
        [EifInterfaceInfo("IGreeter"), EifClassInfo("Outer"), EifClassInfo("Inner")]
    )

    assert EifRows(EifUnit([outer]), symbols, "IGreeter", EditorImplementationTarget.Interface).Count == 0
}

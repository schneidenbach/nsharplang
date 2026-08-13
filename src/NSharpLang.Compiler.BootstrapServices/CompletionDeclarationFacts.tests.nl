namespace NSharpLang.Compiler.CodeIntelligence

import System
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR WHAT A COMPLETION ITEM SAYS ABOUT A DECLARED MEMBER (task 019 slice 1). The
// assertions came out of `CompletionEngine.cs` with the rules, and they pin the three things the
// deleted C# decided: the WORD a member is offered under, which kinds have no completion shape at
// all, and how a parameter list reads.

func CdfNoTypeParameters(): TypeParameter[] {
    return new TypeParameter[](0)
}

func CdfNoConstraints(): GenericConstraint[] {
    return new GenericConstraint[](0)
}

func CdfNoNames(): string[] {
    return new string[](0)
}

func CdfNoTypes(): TypeReference[] {
    return new TypeReference[](0)
}

func CdfNoModifiers(): ParameterModifier[] {
    return new ParameterModifier[](0)
}

func CdfMember(name: string, kind: DeclaredMemberKind, memberType: TypeReference?, isStatic: bool): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name, "Owner", kind, "member", memberType, isStatic, false, false, true,
        0, CdfNoNames(), CdfNoTypes(), CdfNoModifiers(), 0, false, false,
        memberType, 0, CdfNoTypeParameters(), CdfNoConstraints(),
        0, false, false, false, false, "", false, false, 1, 1)
}

func CdfFunction(name: string, returnType: TypeReference?, isStatic: bool, parameterNames: string[], parameterTypes: TypeReference[], parameterModifiers: ParameterModifier[], requiredCount: int): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name, "Owner", DeclaredMemberKind.Function, "function", null, isStatic, false, false, true,
        parameterNames.Length, parameterNames, parameterTypes, parameterModifiers, requiredCount, false, false,
        returnType, 0, CdfNoTypeParameters(), CdfNoConstraints(),
        0, false, false, false, false, "", false, false, 1, 1)
}

func CdfSimple(name: string): TypeReference {
    reference: TypeReference = new SimpleTypeReference(name)
    return reference
}

test "a function is offered as a function at file scope and as a method after a dot" {
    member := CdfFunction("Combine", CdfSimple("bool"), false, CdfNoNames(), CdfNoTypes(), CdfNoModifiers(), 0)

    fileScope := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(member, false)
    assert fileScope != null
    assert fileScope.Name == "Combine"
    assert fileScope.Kind == "function"
    assert fileScope.Type == "bool"
    assert fileScope.Parameters == "()"
    assert !fileScope.IsStatic

    // The SAME member after a dot is a "method". One member, two words, decided by context alone.
    memberScope := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(member, true)
    assert memberScope != null
    assert memberScope.Kind == "method"
    assert memberScope.Name == "Combine"

    // A function with no declared return type reads "void", not an empty string.
    voidMember := CdfFunction("Run", null, true, CdfNoNames(), CdfNoTypes(), CdfNoModifiers(), 0)
    voidItem := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(voidMember, true)
    assert voidItem != null
    assert voidItem.Type == "void"
    assert voidItem.IsStatic
}

test "a nested type is offered with no type text and is never static" {
    kinds := new DeclaredMemberKind[](6)
    kinds[0] = DeclaredMemberKind.Class
    kinds[1] = DeclaredMemberKind.Struct
    kinds[2] = DeclaredMemberKind.Record
    kinds[3] = DeclaredMemberKind.Interface
    kinds[4] = DeclaredMemberKind.Enum
    kinds[5] = DeclaredMemberKind.Union

    expected := new string[](6)
    expected[0] = "class"
    expected[1] = "struct"
    expected[2] = "record"
    expected[3] = "interface"
    expected[4] = "enum"
    expected[5] = "union"

    index := 0
    while index < kinds.Length {
        // Declared STATIC on purpose: a nested type is a name to reach through, so the completion
        // reports `IsStatic = false` regardless of what the member says.
        member := CdfMember("Inner", kinds[index], CdfSimple("int"), true)
        item := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(member, true)
        if item == null {
            throw new InvalidOperationException("A declared type kind produced no completion item.")
        }

        if item.Kind != expected[index] {
            throw new InvalidOperationException(
                "A declared type kind was offered as " + item.Kind + " instead of " + expected[index] + ".")
        }

        assert item.Name == "Inner"
        assert item.Type == null
        assert item.Parameters == null
        assert item.Documentation == null
        assert !item.IsStatic

        index = index + 1
    }
}

test "a field and a property are the same offer and the shapeless kinds are no offer at all" {
    field := CdfMember("Count", DeclaredMemberKind.Field, CdfSimple("int"), false)
    fieldItem := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(field, true)
    assert fieldItem != null
    assert fieldItem.Kind == "property"
    assert fieldItem.Type == "int"
    assert fieldItem.Parameters == null

    property := CdfMember("Total", DeclaredMemberKind.Property, CdfSimple("long"), true)
    propertyItem := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(property, true)
    assert propertyItem != null
    assert propertyItem.Kind == "property"
    assert propertyItem.Type == "long"
    assert propertyItem.IsStatic

    // A value with no declared type still reads "void" — the display rule is total.
    untyped := CdfMember("Loose", DeclaredMemberKind.Field, null, false)
    untypedItem := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(untyped, true)
    assert untypedItem != null
    assert untypedItem.Type == "void"

    // THE KINDS WITH NO COMPLETION SHAPE. Each is `null` and the caller drops it.
    shapeless := new DeclaredMemberKind[](5)
    shapeless[0] = DeclaredMemberKind.Unknown
    shapeless[1] = DeclaredMemberKind.SoaRecord
    shapeless[2] = DeclaredMemberKind.TypeAlias
    shapeless[3] = DeclaredMemberKind.Newtype
    shapeless[4] = DeclaredMemberKind.Constructor

    index := 0
    while index < shapeless.Length {
        member := CdfMember("Hidden", shapeless[index], CdfSimple("int"), false)
        if CompletionDeclarationFacts.DeclaredMemberToCompletionItem(member, true) != null {
            throw new InvalidOperationException("A shapeless member kind produced a completion item.")
        }

        index = index + 1
    }
}

test "a declared member's parameter list defaults past the required count but never defaults params" {
    names := new string[](3)
    names[0] = "count"
    names[1] = "label"
    names[2] = "extras"

    types := new TypeReference[](3)
    types[0] = CdfSimple("int")
    types[1] = CdfSimple("string")
    types[2] = CdfSimple("string")

    modifiers := new ParameterModifier[](3)
    modifiers[0] = ParameterModifier.None
    modifiers[1] = ParameterModifier.None
    modifiers[2] = ParameterModifier.Params

    member := CdfFunction("Write", CdfSimple("void"), false, names, types, modifiers, 1)
    assert CompletionDeclarationFacts.FormatDeclaredMemberParameters(member) ==
        "(count int, label string = ..., extras string)"

    // Required equal to the count defaults nothing.
    allRequired := CdfFunction("Write", CdfSimple("void"), false, names, types, modifiers, 3)
    assert CompletionDeclarationFacts.FormatDeclaredMemberParameters(allRequired) ==
        "(count int, label string, extras string)"

    // A SHORT type list still names every parameter — the missing ones read "unknown".
    shortTypes := new TypeReference[](1)
    shortTypes[0] = CdfSimple("int")
    shortTyped := CdfFunction("Write", CdfSimple("void"), false, names, shortTypes, modifiers, 3)
    assert CompletionDeclarationFacts.FormatDeclaredMemberParameters(shortTyped) ==
        "(count int, label unknown, extras unknown)"

    // A short MODIFIER list reads `None` past its end, so those parameters do default.
    shortModifiers := new ParameterModifier[](1)
    shortModifiers[0] = ParameterModifier.None
    shortMods := CdfFunction("Write", CdfSimple("void"), false, names, types, shortModifiers, 0)
    assert CompletionDeclarationFacts.FormatDeclaredMemberParameters(shortMods) ==
        "(count int = ..., label string = ..., extras string = ...)"

    // No parameters at all is "()", and it reaches the completion item unchanged.
    empty := CdfFunction("Now", CdfSimple("int"), false, CdfNoNames(), CdfNoTypes(), CdfNoModifiers(), 0)
    assert CompletionDeclarationFacts.FormatDeclaredMemberParameters(empty) == "()"
    emptyItem := CompletionDeclarationFacts.DeclaredMemberToCompletionItem(empty, false)
    assert emptyItem != null
    assert emptyItem.Parameters == "()"
}

test "the declared member modifier read is total in both directions" {
    values := new ParameterModifier[](4)
    values[0] = ParameterModifier.None
    values[1] = ParameterModifier.Ref
    values[2] = ParameterModifier.Out
    values[3] = ParameterModifier.Params
    member := CdfFunction("Take", null, false, CdfNoNames(), CdfNoTypes(), values, 0)

    index := 0
    while index < values.Length {
        actual := CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(member, index)
        if actual != values[index] {
            throw new InvalidOperationException(
                "Declared member modifier read disagreed at index " + index.ToString() + ".")
        }

        index = index + 1
    }

    // Past the end and before the start are both `None`, not faults — the same totality its twin
    // `AnalyzerCallableReferenceFacts.GetFunctionParameterModifier` holds.
    assert CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(member, 4) == ParameterModifier.None
    assert CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(member, 99) == ParameterModifier.None
    assert CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(member, -1) == ParameterModifier.None
    assert CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(member, -99) == ParameterModifier.None

    emptyMember := CdfFunction("None", null, false, CdfNoNames(), CdfNoTypes(), CdfNoModifiers(), 0)
    assert CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(emptyMember, 0) == ParameterModifier.None
    assert CompletionDeclarationFacts.GetDeclaredMemberParameterModifier(emptyMember, -1) == ParameterModifier.None
}

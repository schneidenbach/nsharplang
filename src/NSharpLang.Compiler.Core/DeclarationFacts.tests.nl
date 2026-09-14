namespace NSharpLang.Compiler

// ── THE MEMBER VOCABULARY ─────────────────────────────────────────────────────
//
// AN INTERFACE HAS NO INSTANCE FIELDS. A value member written `Area: double` inside an `interface`
// parses to a `FieldDeclaration`, but the CLR has no such thing to emit and every other reader of
// the project already reported it as a property — `nlc query outline`, `nlc query symbols` and the
// completion list all did. Only the analyzer's member lookup still said "field", which is why
// `nlc query inspect` printed BOTH words for ONE member in ONE document (`symbol.kind: "field"`
// beside `completions.properties[0].kind: "property"`) and `nlc query def` printed the losing half
// on its own.
func VocabularyInterface(name: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(name, 1, 1, false, new TypeReference[](0), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

func VocabularyClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
}

func VocabularyStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(name, 1, 1, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
}

test "an interface's instance value member is reported as a property, not a field" {
    assert DeclarationFacts.MemberKindName(VocabularyInterface("Shape"), "field", false) == "property"
}

test "a STATIC value member of an interface is a real field and keeps the word" {
    // C# 11 and the CLR both allow one, so the rule is narrowed to the instance case rather than
    // applied to the word "interface".
    assert DeclarationFacts.MemberKindName(VocabularyInterface("Shape"), "field", true) == "field"
}

test "every other owner and every other kind word is answered unchanged" {
    assert DeclarationFacts.MemberKindName(VocabularyClass("Widget"), "field", false) == "field"
    assert DeclarationFacts.MemberKindName(VocabularyStruct("Point"), "field", false) == "field"
    assert DeclarationFacts.MemberKindName(null, "field", false) == "field"
    assert DeclarationFacts.MemberKindName(VocabularyInterface("Shape"), "function", false) == "function"
    assert DeclarationFacts.MemberKindName(VocabularyInterface("Shape"), "property", false) == "property"
    assert DeclarationFacts.MemberKindName(VocabularyInterface("Shape"), "event", false) == "event"
}

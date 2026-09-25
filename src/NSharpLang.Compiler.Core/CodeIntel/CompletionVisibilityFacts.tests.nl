namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE ONE QUESTION A MEMBER LIST HAD NEVER ASKED: is the caret allowed to see this?
//
// The observed defect: `service.` in `Program.nl` offered `summaries`, the camelCase field of a
// class in `WeatherDemo.Services`, and `nlc check` answered NL308 on the very line the editor had
// just written. The rule these blocks pin is the analyzer's own — package-scoped, not file-scoped —
// so the SAME field stays offered to a file that shares its namespace.
func CvfNoTypeParameters(): TypeParameter[] {
    return new TypeParameter[](0)
}

func CvfNoConstraints(): GenericConstraint[] {
    return new GenericConstraint[](0)
}

func CvfMember(name: string, isExported: bool): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        "Owner",
        DeclaredMemberKind.Property,
        "member",
        null,
        false,
        false,
        false,
        isExported,
        0,
        new string[](0),
        new TypeReference[](0),
        new ParameterModifier[](0),
        0,
        false,
        false,
        null,
        0,
        CvfNoTypeParameters(),
        CvfNoConstraints(),
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1,
        0
    )
}

func CvfClassType(name: string, line: int, column: int, members: DeclaredMemberInfo[]): TypeInfo {
    classType: TypeInfo = new ClassTypeInfo(name, line, column, false, null, new TypeReference[](0), CvfNoTypeParameters(), new ParameterDeclarationInfo[](0), members, new NestedTypeInfo[](0), true)
    return classType
}

func CvfUnit(namespaceName: string?, declarationName: string, line: int, column: int): CompilationUnit {
    declarations := new List<Declaration>()
    declarations.Add(new ClassDeclaration(declarationName, null, null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column, null))

    namespaceDeclaration: NamespaceDeclaration? = null
    if namespaceName != null {
        namespaceDeclaration = new NamespaceDeclaration(namespaceName ?? "", 1, 1)
    }

    return new CompilationUnit(namespaceDeclaration, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

func CvfUnits(units: CompilationUnit[]): List<CompilationUnit> {
    result := new List<CompilationUnit>()
    index := 0
    while index < units.Length {
        result.Add(units[index])
        index = index + 1
    }

    return result
}

func CvfNoUnits(): List<CompilationUnit> {
    return new List<CompilationUnit>()
}

func CvfNoModels(): List<SemanticModel> {
    return new List<SemanticModel>()
}

test "the global namespace answers the empty string, never null" {
    assert CompletionVisibilityFacts.UnitNamespaceName(null) == ""
    assert CompletionVisibilityFacts.UnitNamespaceName(CvfUnit(null, "Widget", 3, 1)) == ""
    assert CompletionVisibilityFacts.UnitNamespaceName(CvfUnit("A.B", "Widget", 3, 1)) == "A.B"
}

test "a receiver type text reads back as its last segment" {
    assert CompletionVisibilityFacts.SimpleTypeName("Widget") == "Widget"
    assert CompletionVisibilityFacts.SimpleTypeName("A.B.Widget") == "Widget"
    assert CompletionVisibilityFacts.SimpleTypeName("") == ""
}

test "only the four member-owning declaration families name a type" {
    unit := CvfUnit("A", "Widget", 3, 1)
    assert CompletionVisibilityFacts.TypeDeclarationName(unit.Declarations[0]) == "Widget"
    assert CompletionVisibilityFacts.TypeDeclarationName(null) == null
}

test "the declaring namespace is found by name, and by POSITION when two files spell the same name" {
    units := new CompilationUnit[](2)
    units[0] = CvfUnit("A.Foo", "Widget", 3, 1)
    units[1] = CvfUnit("A.Bar", "Widget", 9, 1)

    // The unique name case: one match, one answer.
    single := new CompilationUnit[](1)
    single[0] = units[0]
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Widget", 0, 0, CvfUnits(single)) == "A.Foo"

    // TWO FILES, ONE SIMPLE NAME: the POSITION decides, and it decides each way.
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Widget", 3, 1, CvfUnits(units)) == "A.Foo"
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Widget", 9, 1, CvfUnits(units)) == "A.Bar"

    // No position to break the tie, and the two disagree: the walk says it does not know.
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Widget", 0, 0, CvfUnits(units)) == null

    // A qualified receiver text still finds the declaration, which is written unqualified.
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("A.Foo.Widget", 3, 1, CvfUnits(units)) == "A.Foo"

    // Nothing declares it, and no units were handed over: both answer null, both fail open.
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Nobody", 0, 0, CvfUnits(units)) == null
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Widget", 3, 1, CvfNoUnits()) == null
}

test "two files that AGREE on the namespace are not an ambiguity" {
    units := new CompilationUnit[](2)
    units[0] = CvfUnit("A.Foo", "Widget", 3, 1)
    units[1] = CvfUnit("A.Foo", "Widget", 9, 1)
    assert CompletionVisibilityFacts.DeclaringNamespaceOfType("Widget", 0, 0, CvfUnits(units)) == "A.Foo"
}

test "the predicate is two words wide: exported, or same package" {
    // Exported wins whatever the packages are.
    assert CompletionVisibilityFacts.IsOfferableAcrossPackages(true, "A.Foo", "A.Bar")

    // Unexported and the same package: offered, because the analyzer accepts it.
    assert CompletionVisibilityFacts.IsOfferableAcrossPackages(false, "A.Foo", "A.Foo")

    // Unexported and a DIFFERENT package: dropped, because the analyzer answers NL308.
    assert !CompletionVisibilityFacts.IsOfferableAcrossPackages(false, "A.Foo", "A.Bar")

    // The global namespace is a package like any other, and it is not the same one as `A.Foo`.
    assert CompletionVisibilityFacts.IsOfferableAcrossPackages(false, "", "")
    assert !CompletionVisibilityFacts.IsOfferableAcrossPackages(false, "A.Foo", "")

    // FAIL OPEN: an unknown declaring namespace offers everything rather than hiding a legal member.
    assert CompletionVisibilityFacts.IsOfferableAcrossPackages(false, null, "A.Bar")
}

test "the receiver-type half reads the position off the four TypeInfo shapes it can" {
    units := new CompilationUnit[](2)
    units[0] = CvfUnit("A.Foo", "Widget", 3, 1)
    units[1] = CvfUnit("A.Bar", "Widget", 9, 1)

    fooWidget := CvfClassType("Widget", 3, 1, new DeclaredMemberInfo[](0))
    barWidget := CvfClassType("Widget", 9, 1, new DeclaredMemberInfo[](0))
    assert CompletionVisibilityFacts.DeclaringNamespaceOfReceiverType(fooWidget, "Widget", CvfUnits(units)) == "A.Foo"
    assert CompletionVisibilityFacts.DeclaringNamespaceOfReceiverType(barWidget, "Widget", CvfUnits(units)) == "A.Bar"

    // A shape that carries no declaration position cannot break the tie, so it fails open.
    assert CompletionVisibilityFacts.DeclaringNamespaceOfReceiverType(new SimpleTypeInfo("Widget"), "Widget", CvfUnits(units)) == null
}

test "the offered member list drops what the analyzer would refuse, and only that" {
    members := new DeclaredMemberInfo[](2)
    members[0] = CvfMember("Reading", true)
    members[1] = CvfMember("summaries", false)
    owner := CvfClassType("Sensor", 3, 1, members)

    // THE DEFECT: no packages known, so the old two-argument answer offers both.
    both := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels())
    assert both.Count == 2

    // ACROSS packages the camelCase member goes and the exported one stays.
    across := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels(), "A.Foo", "A.Bar")
    assert across.Count == 1
    assert across[0].Name == "Reading"

    // WITHIN the package both stay: this is the control that a casing-only filter would have broken.
    within := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels(), "A.Foo", "A.Foo")
    assert within.Count == 2
    assert within[0].Name == "Reading"
    assert within[1].Name == "summaries"

    // An unknown declaring package offers both, the fail-open rule seen from the caller's side.
    unknown := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels(), null, "A.Bar")
    assert unknown.Count == 2
}

// THE DECLARED RULE, IN THE EDITOR. The package rule above is about a NAME; these blocks are about a
// written `private`/`protected`, which the analyzer began enforcing on 2026-09-13. Offering one is
// the same defect as offering a camelCase member across packages: the editor writes it, and the very
// next diagnostic pass answers NL308.
func CvfModifiedMember(name: string, declaredModifiers: int): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        "Owner",
        DeclaredMemberKind.Property,
        "member",
        null,
        false,
        false,
        false,
        true,
        0,
        new string[](0),
        new TypeReference[](0),
        new ParameterModifier[](0),
        0,
        false,
        false,
        null,
        0,
        CvfNoTypeParameters(),
        CvfNoConstraints(),
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1,
        declaredModifiers
    )
}

func CvfDerivedUnit(namespaceName: string?, derivedName: string, baseName: string, line: int): CompilationUnit {
    declarations := new List<Declaration>()
    baseReference: TypeReference = new SimpleTypeReference(baseName, line, 1)
    declarations.Add(new ClassDeclaration(derivedName, null, baseReference, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, 1, null))

    namespaceDeclaration: NamespaceDeclaration? = null
    if namespaceName != null {
        namespaceDeclaration = new NamespaceDeclaration(namespaceName ?? "", 1, 1)
    }

    return new CompilationUnit(namespaceDeclaration, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

test "a written private or protected member is offered only where the analyzer would admit it" {
    // Outside every type: neither is offerable.
    assert !CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(2, false, false)
    assert !CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(8, false, false)

    // Inside the declaring type: both are.
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(2, true, true)
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(8, true, true)

    // Inside a DERIVED type: `protected` yes, `private` no.
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(8, true, false)
    assert !CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(2, true, false)

    // `internal`, `protected internal` and an unmarked member are one project away and always offered.
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(4, false, false)
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(12, false, false)
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(0, false, false)
    assert CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility(1, false, false)
}

test "the caret's enclosing type is the last declaration that begins at or above it" {
    unit := CvfUnit("A.Foo", "Sensor", 3, 1)
    assert CompletionVisibilityFacts.EnclosingTypeName(unit, 5) == "Sensor"
    assert CompletionVisibilityFacts.EnclosingTypeName(unit, 3) == "Sensor"

    // Above every declaration there is no enclosing type, and neither is there in an empty unit.
    assert CompletionVisibilityFacts.EnclosingTypeName(unit, 1) == null
    assert CompletionVisibilityFacts.EnclosingTypeName(null, 5) == null
}

test "the derivation walk follows the declared base chain and stops at a base the project did not write" {
    derived := CvfDerivedUnit("A.Foo", "Grower", "Seeded", 7)
    seeded := CvfUnit("A.Foo", "Seeded", 3, 1)
    units := CvfUnits([derived, seeded])

    assert CompletionVisibilityFacts.IsTypeOrDerived("Grower", "Grower", units)
    assert CompletionVisibilityFacts.IsTypeOrDerived("Grower", "Seeded", units)
    assert !CompletionVisibilityFacts.IsTypeOrDerived("Seeded", "Grower", units)
    assert !CompletionVisibilityFacts.IsTypeOrDerived(null, "Seeded", units)
    assert !CompletionVisibilityFacts.IsTypeOrDerived("Grower", null, units)

    // An external base ends the walk rather than answering wrongly.
    assert CompletionVisibilityFacts.DeclaredBaseName("Seeded", units) == null
    assert CompletionVisibilityFacts.DeclaredBaseName("Grower", units) == "Seeded"
}

test "the offered member list drops a protected member for a caret outside the family" {
    members := new DeclaredMemberInfo[](3)
    members[0] = CvfModifiedMember("Open", 0)
    members[1] = CvfModifiedMember("Guarded", 8)
    members[2] = CvfModifiedMember("Secret", 2)
    owner := CvfClassType("Seeded", 3, 1, members)

    outside := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels(), "A.Foo", "A.Foo", false, false)
    assert outside.Count == 1
    assert outside[0].Name == "Open"

    derived := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels(), "A.Foo", "A.Foo", true, false)
    assert derived.Count == 2
    assert derived[0].Name == "Open"
    assert derived[1].Name == "Guarded"

    inside := CompletionDeclarationFacts.GetTypeMemberItems(owner, CvfNoModels(), "A.Foo", "A.Foo", true, true)
    assert inside.Count == 3
}

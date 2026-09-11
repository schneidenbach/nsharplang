namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `TypeReferenceFacts`, IN N#.
//
// These replace `tests/TypeReferenceFactsTests.cs`, the last canonical C# assertion layer over
// `TypeReferenceFacts.nl`. The subject answers three questions about an UNRESOLVED source type
// reference: where does it START (the span every diagnostic anchors on), may it be a `params`
// parameter, and how is it SPELLED for a human.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every input is a constructed `TypeReference`
// tree, and a dependency-assembly constructed object declines at `emit.local.initializer` from a
// `tests/native` project. Here the models and the subject are the same assembly's own.
//
// WHY THE LISTS ARE BUILT BY EXPLICIT-ARITY HELPERS. An array literal whose elements are two
// DIFFERENT `TypeReference` subclasses is refused by this estate's emit; `…Refs2(a, b)` is the
// spelling the rest of the estate uses.
//
// THE FIVE THINGS IT IS EASY TO GET WRONG:
//
// (1) THE EXPLICIT SPAN WINS, BUT ONLY WHEN IT IS VALID. `GetStartSpan` returns `typeRef.Span`
// first — for EVERY shape, composite ones included — but the gate is `Span.IsValid`, which demands
// all four coordinates be positive. An assigned-but-degenerate span therefore falls THROUGH to the
// per-arm walk rather than being returned, and a never-assigned span reads back as `None`.
//
// (2) THE FALLBACK SPAN IS A NAME SPAN, AND ITS LENGTH IS THE NAME'S. `SimpleTypeReference` and
// `GenericTypeReference` answer `FromStartAndLength(Line, Column, Name.Length)`, so the end column
// is `Column + Name.Length` — and `FromStartAndLength` floors the length at 1, so even an empty
// name spans one column. A zero line or column answers `None` instead, which is what makes a
// synthesised reference invisible to the squiggle rather than anchored at (0, 0).
//
// (3) EVERY COMPOSITE ARM RECURSES INTO ONE CHILD, AND WHICH CHILD IS THE CONTRACT. Array →
// element, nullable/by-ref → inner, union → FIRST arm, tuple → FIRST element's type, and function
// → the RETURN type rather than the first parameter. The function arm is the one that looks wrong
// and is not: `(int) -> Guid` starts, for span purposes, at `Guid`.
//
// (4) `IsValidParamsType` IS A NAME TABLE, NOT A TYPE CHECK. Any array qualifies; a generic
// qualifies on its NAME alone — fourteen exact spellings, no arity gate at all — so
// `List<>` with no type argument passes and `Dictionary<string, int>` fails on the name.
//
// (5) THE DISPLAY NAME IS FOR HUMANS AND IT SPACES ITS SEPARATORS. `List<int?[]> | &string` has a
// space either side of the union bar and after each comma; the overload-signature renderer next
// door deliberately does not. Two renderers, two audiences, and neither can be folded into the
// other.
func TypeRefFactsRefs0(): List<TypeReference> {
    return new List<TypeReference>()
}

func TypeRefFactsRefs1(first: TypeReference): List<TypeReference> {
    items := new List<TypeReference>()
    items.Add(first)
    return items
}

func TypeRefFactsRefs2(first: TypeReference, second: TypeReference): List<TypeReference> {
    items := new List<TypeReference>()
    items.Add(first)
    items.Add(second)
    return items
}

func TypeRefFactsTuples0(): List<TupleTypeElement> {
    return new List<TupleTypeElement>()
}

func TypeRefFactsTuples1(first: TupleTypeElement): List<TupleTypeElement> {
    items := new List<TupleTypeElement>()
    items.Add(first)
    return items
}

func TypeRefFactsTuples2(first: TupleTypeElement, second: TupleTypeElement): List<TupleTypeElement> {
    items := new List<TupleTypeElement>()
    items.Add(first)
    items.Add(second)
    return items
}

// The C#'s `new GenericTypeReference(name, new List<TypeReference> { new SimpleTypeReference("string") })`,
// which the params-type sweep builds once per collection name.
func TypeRefFactsCollectionOf(name: string, elementName: string): GenericTypeReference {
    return new GenericTypeReference(name, TypeRefFactsRefs1(new SimpleTypeReference(elementName)))
}

// ---- GetStartSpan: the explicit span --------------------------------------------------------------

// Successor to TypeReferenceFacts_UsesExplicitSpanBeforeFallback.
test "type reference facts use an explicit span before the name fallback" {
    spanned := new SimpleTypeReference("Ignored", 2, 3)
    spanned.Span = new SourceSpan(9, 4, 9, 12)

    assert TypeReferenceFacts.GetStartSpan(spanned) == new SourceSpan(9, 4, 9, 12)
}

// NOT IN THE DELETED FILE. The explicit span outranks the per-arm walk for COMPOSITES too, which
// is the arm order that lets a parser stamp a whole `int[]` rather than just its element.
test "type reference facts use an explicit span on composite references too" {
    spannedArray := new ArrayTypeReference(new SimpleTypeReference("int", 6, 9))
    spannedArray.Span = new SourceSpan(6, 9, 6, 14)
    assert TypeReferenceFacts.GetStartSpan(spannedArray) == new SourceSpan(6, 9, 6, 14)

    spannedUnion := new UnionTypeReference(TypeRefFactsRefs0())
    spannedUnion.Span = new SourceSpan(2, 2, 2, 8)
    assert TypeReferenceFacts.GetStartSpan(spannedUnion) == new SourceSpan(2, 2, 2, 8)
}

// NOT IN THE DELETED FILE. The gate is `IsValid`, not "was assigned" — a degenerate span falls
// THROUGH to the name walk instead of being handed back as (0, 0).
test "type reference facts fall through an invalid explicit span" {
    degenerate := new SimpleTypeReference("Person", 3, 7)
    degenerate.Span = new SourceSpan(0, 0, 0, 0)

    assert TypeReferenceFacts.GetStartSpan(degenerate) == new SourceSpan(3, 7, 3, 13)

    unassigned := new SimpleTypeReference("Person", 3, 7)
    assert unassigned.Span == SourceSpan.None
    assert TypeReferenceFacts.GetStartSpan(unassigned) == new SourceSpan(3, 7, 3, 13)
}

// ---- GetStartSpan: the named arms -----------------------------------------------------------------

// Successor to TypeReferenceFacts_ReturnsNameSpanForNamedTypeReferences.
test "type reference facts return the name span for named references" {
    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("Person", 3, 7)) == new SourceSpan(3, 7, 3, 13)
    assert TypeReferenceFacts.GetStartSpan(new GenericTypeReference("Box", TypeRefFactsRefs0(), 4, 5)) == new SourceSpan(4, 5, 4, 8)
}

// NOT IN THE DELETED FILE. The end column is driven by the NAME's length, and the length is floored
// at one — so the span is never empty, and a synthesised reference with no position is `None`
// rather than an anchor at the top of the file.
test "type reference facts measure the name span by the name length" {
    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("T", 5, 2)) == new SourceSpan(5, 2, 5, 3)
    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("Dictionary", 5, 2)) == new SourceSpan(5, 2, 5, 12)
    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("", 5, 2)) == new SourceSpan(5, 2, 5, 3)
    assert TypeReferenceFacts.GetStartSpan(new GenericTypeReference("Dictionary", TypeRefFactsRefs0(), 5, 2)) == new SourceSpan(5, 2, 5, 12)

    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("Person")) == SourceSpan.None
    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("Person", 0, 7)) == SourceSpan.None
    assert TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("Person", 3, 0)) == SourceSpan.None
    assert TypeReferenceFacts.GetStartSpan(new GenericTypeReference("Box", TypeRefFactsRefs0())) == SourceSpan.None
}

// ---- GetStartSpan: the composite arms -------------------------------------------------------------

// Successor to TypeReferenceFacts_UnwrapsCompositeTypeReferencesWithoutExplicitSpan — all six of
// its assertions, over the same six trees.
test "type reference facts unwrap composite references without an explicit span" {
    assert TypeReferenceFacts.GetStartSpan(new ArrayTypeReference(new SimpleTypeReference("int", 6, 9))) == new SourceSpan(6, 9, 6, 12)
    assert TypeReferenceFacts.GetStartSpan(new NullableTypeReference(new SimpleTypeReference("string", 7, 10))) == new SourceSpan(7, 10, 7, 16)
    assert TypeReferenceFacts.GetStartSpan(new ByRefTypeReference(new SimpleTypeReference("bool", 8, 3))) == new SourceSpan(8, 3, 8, 7)

    unionReference := new UnionTypeReference(
        TypeRefFactsRefs2(
            new SimpleTypeReference("First", 9, 11),
            new SimpleTypeReference("Second", 9, 19)
        )
    )
    assert TypeReferenceFacts.GetStartSpan(unionReference) == new SourceSpan(9, 11, 9, 16)

    tupled := new TupleTypeReference(
        TypeRefFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("double", 10, 4), null),
            new TupleTypeElement(new SimpleTypeReference("string", 10, 12), null)
        )
    )
    assert TypeReferenceFacts.GetStartSpan(tupled) == new SourceSpan(10, 4, 10, 10)

    signature := new FunctionTypeReference(
        TypeRefFactsRefs1(new SimpleTypeReference("int", 11, 5)),
        new SimpleTypeReference("Guid", 11, 14)
    )
    assert TypeReferenceFacts.GetStartSpan(signature) == new SourceSpan(11, 14, 11, 18)
}

// NOT IN THE DELETED FILE. WHICH child each arm recurses into is the whole contract, and three of
// the arms have a second child that must NOT win: the union's later arms, the tuple's later
// elements, and — the one that reads backwards — the function's PARAMETERS.
test "type reference facts recurse into the arm that starts the reference" {
    unionReference := new UnionTypeReference(
        TypeRefFactsRefs2(
            new SimpleTypeReference("First", 9, 11),
            new SimpleTypeReference("Second", 9, 19)
        )
    )
    assert TypeReferenceFacts.GetStartSpan(unionReference) != new SourceSpan(9, 19, 9, 25)

    tupled := new TupleTypeReference(
        TypeRefFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("double", 10, 4), null),
            new TupleTypeElement(new SimpleTypeReference("string", 10, 12), null)
        )
    )
    assert TypeReferenceFacts.GetStartSpan(tupled) != new SourceSpan(10, 12, 10, 18)

    // The function arm answers the RETURN type's span even though the parameter is to its left.
    signature := new FunctionTypeReference(
        TypeRefFactsRefs1(new SimpleTypeReference("int", 11, 5)),
        new SimpleTypeReference("Guid", 11, 14)
    )
    assert TypeReferenceFacts.GetStartSpan(signature) != new SourceSpan(11, 5, 11, 8)

    // A named tuple element is reached through its TYPE, not its name.
    named := new TupleTypeReference(
        TypeRefFactsTuples1(new TupleTypeElement(new SimpleTypeReference("double", 10, 4), "amount"))
    )
    assert TypeReferenceFacts.GetStartSpan(named) == new SourceSpan(10, 4, 10, 10)
}

// NOT IN THE DELETED FILE. The arms compose, and the recursion is unbounded — a nullable array of a
// generic still starts where its innermost name starts.
test "type reference facts unwrap nested composite references" {
    nested := new NullableTypeReference(new ArrayTypeReference(new SimpleTypeReference("int", 6, 9)))
    assert TypeReferenceFacts.GetStartSpan(nested) == new SourceSpan(6, 9, 6, 12)

    deep := new ByRefTypeReference(
        new NullableTypeReference(
            new ArrayTypeReference(new GenericTypeReference("List", TypeRefFactsRefs0(), 2, 2))
        )
    )
    assert TypeReferenceFacts.GetStartSpan(deep) == new SourceSpan(2, 2, 2, 6)

    unionOfComposites := new UnionTypeReference(
        TypeRefFactsRefs2(
            new ArrayTypeReference(new SimpleTypeReference("int", 4, 4)),
            new SimpleTypeReference("string", 4, 12)
        )
    )
    assert TypeReferenceFacts.GetStartSpan(unionOfComposites) == new SourceSpan(4, 4, 4, 7)
}

// Successor to TypeReferenceFacts_ReturnsNoneForEmptyCompositeTypeReferences.
test "type reference facts return none for empty composite references" {
    assert TypeReferenceFacts.GetStartSpan(new UnionTypeReference(TypeRefFactsRefs0())) == SourceSpan.None
    assert TypeReferenceFacts.GetStartSpan(new TupleTypeReference(TypeRefFactsTuples0())) == SourceSpan.None

    // Not in the deleted file: the shape with NO arm at all answers `None` rather than throwing.
    assert TypeReferenceFacts.GetStartSpan(new TypeReference()) == SourceSpan.None
}

// ---- IsValidParamsType ----------------------------------------------------------------------------

// Successor to TypeReferenceFacts_ValidatesParamsTypeReferences — the array row and all fourteen
// collection names.
test "type reference facts validate params type references" {
    assert TypeReferenceFacts.IsValidParamsType(new ArrayTypeReference(new SimpleTypeReference("int")))

    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("Span", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("ReadOnlySpan", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("IEnumerable", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("IReadOnlyCollection", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("IReadOnlyList", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("ICollection", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("IList", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("List", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("HashSet", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("Queue", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("Stack", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("ArraySegment", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("Memory", "string"))
    assert TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("ReadOnlyMemory", "string"))
}

// Successor to the same test's two refusals.
test "type reference facts refuse non params type references" {
    assert !TypeReferenceFacts.IsValidParamsType(new SimpleTypeReference("int"))

    dictionary := new GenericTypeReference(
        "Dictionary",
        TypeRefFactsRefs2(new SimpleTypeReference("string"), new SimpleTypeReference("int"))
    )
    assert !TypeReferenceFacts.IsValidParamsType(dictionary)
}

// NOT IN THE DELETED FILE. The gate is the NAME and nothing else — no arity check, no element
// check, and no case folding — and every non-generic composite is refused outright.
test "type reference facts gate params types on the name alone" {
    // Arity is not consulted: a bare `List<>` passes and a two-argument `Span` passes.
    assert TypeReferenceFacts.IsValidParamsType(new GenericTypeReference("List", TypeRefFactsRefs0()))
    assert TypeReferenceFacts.IsValidParamsType(new GenericTypeReference("Span", TypeRefFactsRefs2(new SimpleTypeReference("string"), new SimpleTypeReference("int"))))

    // The names are ordinal and case-sensitive.
    assert !TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("list", "string"))
    assert !TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("IEnumerator", "string"))
    assert !TypeReferenceFacts.IsValidParamsType(TypeRefFactsCollectionOf("SpanOwner", "string"))

    // Every array qualifies, whatever it is an array OF.
    assert TypeReferenceFacts.IsValidParamsType(new ArrayTypeReference(new ArrayTypeReference(new SimpleTypeReference("int"))))
    assert TypeReferenceFacts.IsValidParamsType(new ArrayTypeReference(new NullableTypeReference(new SimpleTypeReference("string"))))

    // The other composites have no arm and answer false.
    assert !TypeReferenceFacts.IsValidParamsType(new NullableTypeReference(new SimpleTypeReference("int")))
    assert !TypeReferenceFacts.IsValidParamsType(new ByRefTypeReference(new SimpleTypeReference("int")))
    assert !TypeReferenceFacts.IsValidParamsType(new UnionTypeReference(TypeRefFactsRefs1(new SimpleTypeReference("int"))))
    assert !TypeReferenceFacts.IsValidParamsType(new TupleTypeReference(TypeRefFactsTuples1(new TupleTypeElement(new SimpleTypeReference("int"), null))))
    assert !TypeReferenceFacts.IsValidParamsType(new FunctionTypeReference(TypeRefFactsRefs0(), new SimpleTypeReference("int")))
    assert !TypeReferenceFacts.IsValidParamsType(new TypeReference())
}

// ---- GetDisplayName -------------------------------------------------------------------------------

// Successor to TypeReferenceFacts_DisplaysNestedTypeReferences.
test "type reference facts display nested type references" {
    displayType := new UnionTypeReference(
        TypeRefFactsRefs2(
            new GenericTypeReference(
                "List",
                TypeRefFactsRefs1(new ArrayTypeReference(new NullableTypeReference(new SimpleTypeReference("int"))))
            ),
            new ByRefTypeReference(new SimpleTypeReference("string"))
        )
    )

    assert TypeReferenceFacts.GetDisplayName(displayType) == "List<int?[]> | &string"
}

// NOT IN THE DELETED FILE. Each of the eight arms alone, so a broken arm cannot hide inside a
// composed tree that another arm happens to render correctly.
test "type reference facts display every reference arm alone" {
    assert TypeReferenceFacts.GetDisplayName(new SimpleTypeReference("int")) == "int"
    assert TypeReferenceFacts.GetDisplayName(new ArrayTypeReference(new SimpleTypeReference("int"))) == "int[]"
    assert TypeReferenceFacts.GetDisplayName(new NullableTypeReference(new SimpleTypeReference("int"))) == "int?"
    assert TypeReferenceFacts.GetDisplayName(new ByRefTypeReference(new SimpleTypeReference("int"))) == "&int"
    assert TypeReferenceFacts.GetDisplayName(new GenericTypeReference("List", TypeRefFactsRefs1(new SimpleTypeReference("int")))) == "List<int>"
    assert TypeReferenceFacts.GetDisplayName(new UnionTypeReference(TypeRefFactsRefs2(new SimpleTypeReference("int"), new SimpleTypeReference("string")))) == "int | string"
    assert TypeReferenceFacts.GetDisplayName(new TupleTypeReference(TypeRefFactsTuples2(new TupleTypeElement(new SimpleTypeReference("int"), null), new TupleTypeElement(new SimpleTypeReference("string"), null)))) == "(int, string)"
    assert TypeReferenceFacts.GetDisplayName(new FunctionTypeReference(TypeRefFactsRefs1(new SimpleTypeReference("int")), new SimpleTypeReference("bool"))) == "(int) -> bool"

    // The shape with no arm falls back to its own runtime type name.
    assert TypeReferenceFacts.GetDisplayName(new TypeReference()) == "TypeReference"
}

// NOT IN THE DELETED FILE. The separators are where an off-by-one lives: the empty and
// single-element shapes of the three list-walking arms.
test "type reference facts display the empty and single element shapes" {
    assert TypeReferenceFacts.GetDisplayName(new GenericTypeReference("Box", TypeRefFactsRefs0())) == "Box<>"
    assert TypeReferenceFacts.GetDisplayName(new UnionTypeReference(TypeRefFactsRefs0())) == ""
    assert TypeReferenceFacts.GetDisplayName(new TupleTypeReference(TypeRefFactsTuples0())) == "()"
    assert TypeReferenceFacts.GetDisplayName(new TupleTypeReference(TypeRefFactsTuples1(new TupleTypeElement(new SimpleTypeReference("int"), null)))) == "(int)"
    assert TypeReferenceFacts.GetDisplayName(new FunctionTypeReference(TypeRefFactsRefs0(), new SimpleTypeReference("void"))) == "() -> void"
    assert TypeReferenceFacts.GetDisplayName(new GenericTypeReference("Dictionary", TypeRefFactsRefs2(new SimpleTypeReference("string"), new SimpleTypeReference("int")))) == "Dictionary<string, int>"
}

// NOT IN THE DELETED FILE. A tuple element's NAME is part of the human spelling — which is the
// difference from the overload-signature renderer, where it is dropped.
test "type reference facts display tuple element names" {
    named := new TupleTypeReference(
        TypeRefFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("string"), "name"),
            new TupleTypeElement(new SimpleTypeReference("int"), "age")
        )
    )
    assert TypeReferenceFacts.GetDisplayName(named) == "(name: string, age: int)"

    partlyNamed := new TupleTypeReference(
        TypeRefFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("string"), "name"),
            new TupleTypeElement(new SimpleTypeReference("int"), null)
        )
    )
    assert TypeReferenceFacts.GetDisplayName(partlyNamed) == "(name: string, int)"
}

// NOT IN THE DELETED FILE. The null gate and the two join entry points, which production reaches
// directly when it renders a signature rather than a single type.
test "type reference facts join display names and default to void" {
    assert TypeReferenceFacts.GetDisplayNameOrVoid(null) == "void"
    assert TypeReferenceFacts.GetDisplayNameOrVoid(new SimpleTypeReference("int")) == "int"
    assert TypeReferenceFacts.GetDisplayNameOrVoid(new ArrayTypeReference(new SimpleTypeReference("int"))) == "int[]"

    assert TypeReferenceFacts.JoinDisplayNames(TypeRefFactsRefs0(), ", ") == ""
    assert TypeReferenceFacts.JoinDisplayNames(TypeRefFactsRefs1(new SimpleTypeReference("int")), ", ") == "int"
    assert TypeReferenceFacts.JoinDisplayNames(TypeRefFactsRefs2(new SimpleTypeReference("int"), new SimpleTypeReference("string")), ", ") == "int, string"
    assert TypeReferenceFacts.JoinDisplayNames(TypeRefFactsRefs2(new SimpleTypeReference("int"), new SimpleTypeReference("string")), " | ") == "int | string"

    assert TypeReferenceFacts.JoinTupleElementDisplayNames(TypeRefFactsTuples0()) == ""
    assert TypeReferenceFacts.JoinTupleElementDisplayNames(TypeRefFactsTuples1(new TupleTypeElement(new SimpleTypeReference("int"), null))) == "int"
    assert TypeReferenceFacts.JoinTupleElementDisplayNames(TypeRefFactsTuples2(new TupleTypeElement(new SimpleTypeReference("string"), "name"), new TupleTypeElement(new SimpleTypeReference("int"), null))) == "name: string, int"
}

namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// THE LEXICAL SCOPE OWNS EVERY POSITION IN A TYPE SPELLING, NOT ONLY ITS HEAD.
//
// A nested declaration is named from its owner's body by its simple name, and the walk that
// assembles the CLR shape of a spelling sees only FILE and IMPORT scope. Before this rule the
// declaration-signature resolver rewrote only the generic HEAD into its exact identity, so
// `List<Cached>` written inside `Outer` resolved by luck — through the exported-name fallback — and
// a `private` nested declaration, which is exported nowhere, could not be a generic argument at all.
// Each position is now rewritten to its exact source identity before that walk runs, and the
// identity is written RELATIVE to the file's namespace so the walk recognises a declaration of its
// own file instead of holding a global name to the export rule.
func LexicalArgumentSources(): string[] {
    sources := new string[](1)
    sources[0] = "namespace LexicalArguments\nimport System\nimport System.Collections.Generic\nclass Outer {\n    private class Cached {}\n    class Slot<T> {}\n    class Mid {\n        class Leaf {}\n    }\n}\nclass Other {}\n"
    return sources
}

func LexicalArgumentResolution(enclosingSourceDeclarationName: string): ColumnarSemanticTypeResolution {
    owner := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("LexicalArguments.Outer", false),
        "LexicalArguments.Outer"
    )
    middle := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("LexicalArguments.Outer.Mid", false),
        "LexicalArguments.Outer.Mid"
    )
    other := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("LexicalArguments.Other", false),
        "LexicalArguments.Other"
    )
    nested := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("LexicalArguments.Outer.Cached", false),
        "LexicalArguments.Outer.Cached"
    )
    nestedConsumer := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("LexicalArguments.Outer.CachedList", false),
        "LexicalArguments.Outer.CachedList"
    )
    nestedGeneric := ExactTypeDefinition(
        TypeOfCreateBuilder("LexicalArguments.Outer.Slot`1", "LexicalArgumentNestedGeneric", 1),
        "LexicalArguments.Outer.Slot`1"
    )
    nestedGenericParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    nestedGenericParameters["T"] = nestedGeneric.Builder.GetGenericArguments()[0]
    nestedGeneric.GenericParameters = nestedGenericParameters
    deep := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("LexicalArguments.Outer.Mid.Leaf", false),
        "LexicalArguments.Outer.Mid.Leaf"
    )
    structs := SemanticEmptyStructs()
    structs[owner.DeclaredTypeName] = owner
    structs[middle.DeclaredTypeName] = middle
    structs[other.DeclaredTypeName] = other
    structs[nested.DeclaredTypeName] = nested
    structs[nestedConsumer.DeclaredTypeName] = nestedConsumer
    structs[nestedGeneric.DeclaredTypeName] = nestedGeneric
    structs[deep.DeclaredTypeName] = deep

    fileNames := new string[](1)
    fileNames[0] = "lexical-arguments/owner.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(LexicalArgumentSources(), fileNames),
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        enclosingSourceDeclarationName
    )
    genericParameterNames := new string[](1)
    genericParameterNames[0] = "T"
    resolution.StructuralTypeReferences.RegisterTypeGenericParameters(0, nestedGeneric.DeclaredTypeName, genericParameterNames, nestedGeneric.Builder)
    return resolution
}

func LexicalArgumentSelects(
    canonical: string,
    enclosingSourceDeclarationName: string,
    out resolved: Type
): bool {
    resolution := LexicalArgumentResolution(enclosingSourceDeclarationName)
    resolved = null
    return ColumnarCanonicalTypeResolver.TryResolveType(
        canonical,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
}

func LexicalArgumentSingleArgument(constructed: Type): Type {
    assert constructed.get_IsGenericType()
    arguments := constructed.GetGenericArguments()
    assert arguments.Length == 1
    return arguments[0]
}

test "a nested declaration is the generic argument of a modelled head from inside its owner" {
    resolved: Type = null
    assert LexicalArgumentSelects("List<Cached>", "LexicalArguments.Outer", out resolved)
    assert resolved.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()
    assert LexicalArgumentSingleArgument(resolved).FullName == "LexicalArguments.Outer.Cached"
}

test "a nested declaration sees a sibling type through its enclosing owner" {
    resolved: Type = null
    assert LexicalArgumentSelects("List<Cached>", "LexicalArguments.Outer.CachedList", out resolved)
    assert resolved.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()
    assert LexicalArgumentSingleArgument(resolved).FullName == "LexicalArguments.Outer.Cached"
}

test "a nested source generic closes over its sibling source type" {
    resolved: Type = null
    assert LexicalArgumentSelects("List<Slot<Cached>>", "LexicalArguments.Outer", out resolved), "selection"
    slot := LexicalArgumentSingleArgument(resolved)
    assert slot.GetGenericTypeDefinition().FullName == "LexicalArguments.Outer.Slot`1", slot.GetGenericTypeDefinition().FullName ?? "<null>"
    assert LexicalArgumentSingleArgument(slot).FullName == "LexicalArguments.Outer.Cached", LexicalArgumentSingleArgument(slot).FullName ?? "<null>"
}

test "a nested declaration is a delegate argument from inside its owner" {
    resolved: Type = null
    assert LexicalArgumentSelects("Func<Cached,int>", "LexicalArguments.Outer", out resolved), "Func<Cached,int> resolves"
    assert resolved.GetGenericTypeDefinition() == typeof(Func<int, int>).GetGenericTypeDefinition()
    arguments := resolved.GetGenericArguments()
    assert arguments.Length == 2
    assert arguments[0].FullName == "LexicalArguments.Outer.Cached"
    assert arguments[1] == typeof(int)
}

test "every position of a composed spelling carries the lexical scope" {
    arrayOfNested: Type = null
    assert LexicalArgumentSelects("List<Cached[]>", "LexicalArguments.Outer", out arrayOfNested)
    element := LexicalArgumentSingleArgument(arrayOfNested)
    assert element.get_IsArray()
    assert (must element.GetElementType()).FullName == "LexicalArguments.Outer.Cached"

    nestedGeneric: Type = null
    assert LexicalArgumentSelects("Dictionary<string,List<Cached>>", "LexicalArguments.Outer", out nestedGeneric)
    nestedArguments := nestedGeneric.GetGenericArguments()
    assert nestedArguments.Length == 2
    assert nestedArguments[0] == typeof(string)
    assert LexicalArgumentSingleArgument(nestedArguments[1]).FullName == "LexicalArguments.Outer.Cached"

    bare: Type = null
    assert LexicalArgumentSelects("Cached", "LexicalArguments.Outer", out bare)
    assert bare.FullName == "LexicalArguments.Outer.Cached"
}

// The owner walk climbs through EVERY enclosing declaration, and a spelling may be PARTIALLY
// qualified: `Leaf` names `Outer.Mid.Leaf` from inside `Mid`, and `Mid.Leaf` names the same type
// from inside `Outer`.
test "the owner walk climbs every enclosing declaration and accepts a partial qualification" {
    fromInner: Type = null
    assert LexicalArgumentSelects("List<Leaf>", "LexicalArguments.Outer.Mid", out fromInner), "List<Leaf> from Mid"
    assert LexicalArgumentSingleArgument(fromInner).FullName == "LexicalArguments.Outer.Mid.Leaf"

    siblingFromInner: Type = null
    assert LexicalArgumentSelects("List<Cached>", "LexicalArguments.Outer.Mid", out siblingFromInner), "List<Cached> from Mid"
    assert LexicalArgumentSingleArgument(siblingFromInner).FullName == "LexicalArguments.Outer.Cached"

    partiallyQualified: Type = null
    assert LexicalArgumentSelects("List<Mid.Leaf>", "LexicalArguments.Outer", out partiallyQualified), "List<Mid.Leaf> from Outer"
    assert LexicalArgumentSingleArgument(partiallyQualified).FullName == "LexicalArguments.Outer.Mid.Leaf"
}

// THE NEGATIVE CONTRACT. The rewrite is scoped, not global: a declaration no enclosing owner
// declares is not reached by it, and the spelling stays exactly as written — which is the answer a
// reader expects, because the name means nothing at that site.
test "a nested declaration is out of scope from another declaration and from file scope" {
    fromSibling: Type = null
    assert !LexicalArgumentSelects("List<Cached>", "LexicalArguments.Other", out fromSibling)
    assert fromSibling == null

    fromFileScope: Type = null
    assert !LexicalArgumentSelects("List<Cached>", "", out fromFileScope)
    assert fromFileScope == null

    leafFromOwnerOfMid: Type = null
    assert !LexicalArgumentSelects("List<Leaf>", "LexicalArguments.Outer", out leafFromOwnerOfMid)
    assert leafFromOwnerOfMid == null
}

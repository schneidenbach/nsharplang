namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection


// CONTRACTS FOR WHICH CLR TYPE A NAME MEANS (task 019 slice 6). These are the semantic assertions
// that came out of `DocQuery.cs` with the type index and the resolution order, INCLUDING THE TWO
// THAT USED TO REACH THEIR SUBJECT BY REFLECTING ON A PRIVATE C# METHOD BY STRING NAME:
// `DocQueryTests.DeduplicateTypeCandidates_PreservesFirstSourceOrder` and
// `DocQueryTests.DeduplicateReferencePackAssemblyNames_PreservesFirstSourceOrder`, both
// `typeof(DocQuery).GetMethod(…, NonPublic | Static)` with a throwing guard. They are here, calling
// their subject directly, because the C# they reached through no longer exists.
//
// STABILITY IS THE POINT OF BOTH OF THEM. The scorer's last tie-break is source order, so a dedupe
// that reordered would make `nlc query doc List` answer differently on different runs — which is
// exactly the failure a first-source-order assertion catches and an equality-of-sets one does not.

func DqtiIndexOfCoreLibrary(): DocQueryTypeIndex {
    index := new DocQueryTypeIndex()
    index.AddAssembly(typeof(string).get_Assembly())
    return index
}

func DqtiTypeList(values: Type[]): List<Type> {
    items := new List<Type>()
    index := 0
    while index < values.Length {
        items.Add(values[index])
        index = index + 1
    }

    return items
}

func DqtiStringList(values: string[]): List<string> {
    items := new List<string>()
    index := 0
    while index < values.Length {
        items.Add(values[index])
        index = index + 1
    }

    return items
}

// MIGRATED FROM `tests/DocQueryTests.cs` :117 — the reflection door, now a direct call.
test "type-candidate dedupe keeps the FIRST occurrence and the rest of the source order" {
    candidates := new Type[](5)
    candidates[0] = typeof(string)
    candidates[1] = typeof(int)
    candidates[2] = typeof(string)
    candidates[3] = typeof(DateTime)
    candidates[4] = typeof(int)

    actual := DocQueryTypeIndex.DeduplicateTypeCandidates(DqtiTypeList(candidates))

    assert actual.Length == 3
    assert actual[0] == typeof(string)
    assert actual[1] == typeof(int)
    assert actual[2] == typeof(DateTime)
}

// MIGRATED FROM `tests/DocQueryTests.cs` :89 — the second reflection door. The C# relay it named is
// deleted; the behaviour it pinned belongs to the kernel the reference-pack scan actually calls,
// which is what this asserts.
test "reference-pack assembly-name dedupe is ordinal-ignore-case and keeps the first spelling" {
    names := new string[](6)
    names[0] = "System.Console"
    names[1] = "system.console"
    names[2] = "System.Text.Json"
    names[3] = "System.Runtime"
    names[4] = "SYSTEM.TEXT.JSON"
    names[5] = "system.runtime"

    actual := DocQueryKernels.DeduplicateStableStringsOrdinalIgnoreCase(DqtiStringList(names))

    assert actual.Length == 3
    assert actual[0] == "System.Console"
    assert actual[1] == "System.Text.Json"
    assert actual[2] == "System.Runtime"
}

test "an empty candidate set dedupes to an empty result rather than failing" {
    assert DocQueryTypeIndex.DeduplicateTypeCandidates(new List<Type>()).Length == 0
    assert DocQueryKernels.DeduplicateStableStringsOrdinalIgnoreCase(new List<string>()).Length == 0
}

test "an indexed assembly answers a simple name, a qualified name and both cases" {
    index := DqtiIndexOfCoreLibrary()

    assert index.ResolveType("String") == typeof(string)
    assert index.ResolveType("System.String") == typeof(string)
    assert index.ResolveType("string") == typeof(string)
    assert index.ResolveType("system.string") == typeof(string)
    assert index.ResolveType("DateTime") == typeof(DateTime)
}

// BOTH SPELLINGS OF A GENERIC NAME REACH THE SAME ROW, because the index carries two keys per type:
// the CLR full name as it stands, and the same name with its arity suffix stripped.
test "a generic name resolves with or without its arity, and to the DEFINITION" {
    index := DqtiIndexOfCoreLibrary()

    withoutArity := index.ResolveType("System.Collections.Generic.List")
    assert withoutArity != null
    assert withoutArity.get_IsGenericTypeDefinition()

    assert index.ResolveType("System.Collections.Generic.List`1") == withoutArity
    assert index.ResolveType("List") == withoutArity
    assert index.ResolveType("list") == withoutArity
}

// THE SUFFIX DOOR IS GATED ON A DOT, AND THIS IS WHAT THE GATE BUYS. `Collections.Generic.List`
// is a suffix a user can mean; a bare name must go to the simple-name index instead, which is a
// different and weaker question.
test "a suffix search is offered only to a name that already contains a dot" {
    index := DqtiIndexOfCoreLibrary()

    assert DocQueryKernels.ShouldSearchQualifiedSuffix("Collections.Generic.List")
    assert !DocQueryKernels.ShouldSearchQualifiedSuffix("List")

    bySuffix := index.ResolveType("Collections.Generic.List")
    assert bySuffix != null
    assert bySuffix == index.ResolveType("System.Collections.Generic.List")
}

test "a name nothing indexes answers null, and asking twice still answers null" {
    index := DqtiIndexOfCoreLibrary()

    assert index.ResolveType("NoSuchTypeAnywhereAtAll") == null
    assert index.ResolveType("NoSuchTypeAnywhereAtAll") == null
}

test "a resolved name is memoised and answers identically on every later ask" {
    index := DqtiIndexOfCoreLibrary()

    first := index.ResolveType("String")
    assert first == index.ResolveType("String")
    assert first == index.ResolveType("String")
}

test "adding the same assembly twice indexes it once and changes no answer" {
    index := new DocQueryTypeIndex()
    index.AddAssembly(typeof(string).get_Assembly())
    before := index.ResolveType("String")

    index.AddAssembly(typeof(string).get_Assembly())
    index.AddAssembly(typeof(int).get_Assembly())

    assert index.ResolveType("String") == before
}

test "an index with no assemblies resolves nothing at all" {
    index := new DocQueryTypeIndex()

    assert index.ResolveType("String") == null
    assert index.ResolveType("System.String") == null
}

// A NESTED PUBLIC TYPE IS NOT `IsPublic`, AND EXCLUDING IT WOULD LOSE `Environment.SpecialFolder`.
test "the public-type filter admits nested public types as well as top-level ones" {
    assert DocQueryKernels.ShouldIncludePublicType(true, false)
    assert DocQueryKernels.ShouldIncludePublicType(false, true)
    assert !DocQueryKernels.ShouldIncludePublicType(false, false)

    publicTypes := DocQueryTypeIndex.GetPublicTypes(typeof(string).get_Assembly())
    assert publicTypes.Count > 0

    sawNested := false
    index := 0
    while index < publicTypes.Count && !sawNested {
        candidate := publicTypes[index]
        if candidate.get_IsNested() {
            sawNested = true
        }

        index = index + 1
    }

    assert sawNested
}

test "a nested chain is WALKED, and a part that does not match ends it with no answer" {
    index := DqtiIndexOfCoreLibrary()

    owner := index.ResolveType("System.Environment")
    assert owner != null

    oneStep := new string[](1)
    oneStep[0] = "SpecialFolder"
    nested := DocQueryTypeIndex.ResolveNestedTypeChain(owner, oneStep)
    assert nested != null
    assert nested.get_IsNested()
    assert nested.get_IsEnum()

    missing := new string[](1)
    missing[0] = "NoSuchNestedType"
    assert DocQueryTypeIndex.ResolveNestedTypeChain(owner, missing) == null

    halfMatch := new string[](2)
    halfMatch[0] = "SpecialFolder"
    halfMatch[1] = "NoSuchNestedType"
    assert DocQueryTypeIndex.ResolveNestedTypeChain(owner, halfMatch) == null
}

test "an empty chain answers the type it started from" {
    index := DqtiIndexOfCoreLibrary()

    owner := index.ResolveType("System.String")
    assert owner != null
    assert DocQueryTypeIndex.ResolveNestedTypeChain(owner, new string[](0)) == owner
}

test "the reference-pack directories are computed once and answered from the cache after that" {
    index := DqtiIndexOfCoreLibrary()

    first := index.GetReferencePackDirectories()
    second := index.GetReferencePackDirectories()

    assert first.Length == second.Length

    directoryIndex := 0
    while directoryIndex < first.Length {
        assert first[directoryIndex] == second[directoryIndex]
        directoryIndex = directoryIndex + 1
    }
}

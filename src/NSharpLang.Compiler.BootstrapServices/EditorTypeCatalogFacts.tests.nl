namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler


// CONTRACTS FOR WHAT THE EDITOR OFFERS OUT OF METADATA (task 021 slice 9b).
//
// These are the decisions that came out of `Services/TypeResolver.cs` — the Language Server's own
// type catalogue. Three of them are worth reading twice:
//
//   * THE EIGHT DERIVED FULL NAMES. Eight roster spellings are answered by
//     `CompletionReflectionFacts` rather than written down again, and the block that pins them
//     asserts the derived answer EQUALS the literal it replaced. If that owner ever moves, these
//     fail rather than the editor quietly losing a completion.
//   * THE TWO PREFIX RULES DISAGREE ON PURPOSE. A type prefix is case-INSENSITIVE and a namespace
//     segment prefix is case-SENSITIVE; both are asserted, together, so neither can be "fixed" into
//     the other by accident.
//   * THE BACKTICK RULE IS PINNED ON BOTH SIDES. `CompletionTypeDisplayName` truncates at the first
//     arity suffix; `DocQueryKernels.StripGenericArity` removes every one. The blocks assert they
//     AGREE on a `Type.Name` and DIFFER on a two-run name, so the divergence stays a recorded fact.
func EtcIndexOf(values: string[], value: string): int {
    index := 0
    while index < values.Length {
        if values[index] == value {
            return index
        }

        index = index + 1
    }

    return -1
}

func EtcContains(values: string[], value: string): bool {
    return EtcIndexOf(values, value) >= 0
}

// Assemblies and types are compared by NAME rather than by reference: the columnar backend does not
// model `Assembly == Assembly`, and a name is the more legible failure message anyway.
func EtcAssemblyNameOf(metadataName: string): string {
    resolved := Type.GetType(metadataName)
    if resolved == null {
        return "<unresolved>"
    }

    name := resolved.get_Assembly().GetName().get_Name()
    if name == null {
        return "<unnamed>"
    }

    return name
}

func EtcFullNameOf(clrType: Type?): string {
    if clrType == null {
        return "<null>"
    }

    fullName := clrType.get_FullName()
    if fullName == null {
        return "<no full name>"
    }

    return fullName
}

func EtcSeedAssemblies(): List<Assembly> {
    seeds := EditorTypeCatalogFacts.EditorUniverseSeedTypeNames()
    assemblies := new List<Assembly>()
    seen := new List<string>()
    index := 0
    while index < seeds.Length {
        resolved := Type.GetType(seeds[index])
        if resolved != null {
            assembly := resolved.get_Assembly()
            name := EtcAssemblyNameOf(seeds[index])
            if !seen.Contains(name) {
                seen.Add(name)
                assemblies.Add(assembly)
            }
        }

        index = index + 1
    }

    return assemblies
}

func EtcJoin(values: string[]): string {
    text := ""
    index := 0
    while index < values.Length {
        if index > 0 {
            text = text + "|"
        }

        text = text + values[index]
        index = index + 1
    }

    return text
}

// ── the universe ─────────────────────────────────────────────────────────────────────────────

test "the editor universe is four seed names and every one of them resolves" {
    seeds := EditorTypeCatalogFacts.EditorUniverseSeedTypeNames()

    assert seeds.Length == 4
    assert seeds[0] == "System.Object"
    assert seeds[1] == "System.Console, System.Console"
    assert seeds[2] == "System.Linq.Enumerable, System.Linq"
    assert seeds[3] == "System.Collections.Generic.List`1"

    index := 0
    while index < seeds.Length {
        assert Type.GetType(seeds[index]) != null
        index = index + 1
    }
}

test "the four seed names reach THREE assemblies because List and object share the core library" {
    seeds := EditorTypeCatalogFacts.EditorUniverseSeedTypeNames()

    coreFromObject := EtcAssemblyNameOf(seeds[0])
    console := EtcAssemblyNameOf(seeds[1])
    linq := EtcAssemblyNameOf(seeds[2])
    coreFromList := EtcAssemblyNameOf(seeds[3])

    // The fourth entry is NOT a fourth assembly. The C# this replaced carried a `// System.Collections`
    // comment beside it, which was wrong.
    assert coreFromObject == "System.Private.CoreLib"
    assert coreFromList == coreFromObject
    assert console == "System.Console"
    assert linq == "System.Linq"
    assert EtcSeedAssemblies().Count == 3
}

test "the metadata-name spelling is the only one N# has and it answers the same types typeof would" {
    seeds := EditorTypeCatalogFacts.EditorUniverseSeedTypeNames()

    // `typeof(object)` is spellable; `typeof(Console)` does not EMIT (static class) and an open
    // `typeof(List<>)` does not PARSE, which is why all four are named rather than three of them.
    assert Type.GetType(seeds[0]) == typeof(object)
    assert EtcFullNameOf(Type.GetType(seeds[1])) == "System.Console"
    assert EtcFullNameOf(Type.GetType(seeds[2])) == "System.Linq.Enumerable"
    assert Type.GetType(seeds[3]) == typeof(List<int>).GetGenericTypeDefinition()
}

// ── the roster ───────────────────────────────────────────────────────────────────────────────

test "the roster is twelve spellings and they are the CLR ones a user types at a type position" {
    names := EditorTypeCatalogFacts.CommonShortTypeNames()

    assert names.Length == 12
    assert EtcJoin(names) == "Console|String|Math|DateTime|Guid|Exception|List|Dictionary|HashSet|IEnumerable|Task|CancellationToken"

    // `String` and not `string`: the built-in aliases are resolved by `AnalyzerTypeReferenceFacts`
    // before this table is ever consulted, so the lowercase spellings never reach it.
    assert EtcContains(names, "String")
    assert !EtcContains(names, "string")
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("string") == "System.String"
    assert AnalyzerTypeReferenceFacts.BuiltInClrTypeName("String") == null
}

test "eight of the twelve full names are DERIVED from CompletionReflectionFacts and equal what they replaced" {
    // The literal on the right of each pair is exactly what `TypeResolver.CommonShortTypeToFullName`
    // spelled. The left is what the derivation answers. A drift in the other owner fails HERE.
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Console") == "System.Console"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("String") == "System.String"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Math") == "System.Math"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("DateTime") == "System.DateTime"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("List") == "System.Collections.Generic.List`1"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Dictionary") == "System.Collections.Generic.Dictionary`2"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("HashSet") == "System.Collections.Generic.HashSet`1"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("IEnumerable") == "System.Collections.Generic.IEnumerable`1"

    // And they really are the other owner's answers, not a coincidence of spelling.
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Console") == EtcFullNameOf(CompletionReflectionFacts.KnownReceiverType("Console"))
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("String") == EtcFullNameOf(CompletionReflectionFacts.KnownReceiverType("string"))
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("List") == EtcFullNameOf(CompletionReflectionFacts.KnownReceiverGenericDefinition("List"))
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("IEnumerable") == EtcFullNameOf(CompletionReflectionFacts.KnownReceiverGenericDefinition("IEnumerable"))
}

test "the four with no owner are spelled here and the roster Task is the NON-generic one" {
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Guid") == "System.Guid"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Exception") == "System.Exception"
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("CancellationToken") == "System.Threading.CancellationToken"

    // This is why the derivation stops at eight: the other owner's `Task` is `Task`1`, a DIFFERENT
    // type from the one an editor offers under the bare name `Task`.
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Task") == "System.Threading.Tasks.Task"
    assert EtcFullNameOf(CompletionReflectionFacts.KnownReceiverGenericDefinition("Task")) == "System.Threading.Tasks.Task`1"
}

test "a name outside the roster has no full name and the lookup is ORDINAL" {
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("Widget") == null
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("") == null
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("console") == null
    assert EditorTypeCatalogFacts.CommonShortTypeFullName("CONSOLE") == null
}

test "the force-include list is DEFINED from the roster and carries all twelve in roster order" {
    spellings := EditorTypeCatalogFacts.CommonShortTypeNames()
    fullNames := EditorTypeCatalogFacts.CommonShortTypeFullNames()

    assert fullNames.Length == 12
    assert fullNames.Length == spellings.Length

    index := 0
    while index < spellings.Length {
        assert fullNames[index] == EditorTypeCatalogFacts.CommonShortTypeFullName(spellings[index])
        index = index + 1
    }

    assert fullNames[0] == "System.Console"
    assert fullNames[11] == "System.Threading.CancellationToken"
}

test "every force-included full name resolves inside the three-assembly seed universe" {
    // The roster is the ONE part of a completion that must always be offerable, so a name that the
    // editor's universe cannot reach would be a silently missing item.
    assemblies := EtcSeedAssemblies()
    assert assemblies.Count == 3

    fullNames := EditorTypeCatalogFacts.CommonShortTypeFullNames()
    index := 0
    while index < fullNames.Length {
        found := false
        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            if assemblies[assemblyIndex].GetType(fullNames[index]) != null {
                found = true
            }

            assemblyIndex = assemblyIndex + 1
        }

        assert found
        index = index + 1
    }
}

// ── how a name is looked up ──────────────────────────────────────────────────────────────────

test "the probe prefixes are seven, System first and the two Threading namespaces last" {
    prefixes := EditorTypeCatalogFacts.NamespaceProbePrefixes()

    assert prefixes.Length == 7
    assert EtcJoin(prefixes) == "System|System.Collections|System.Collections.Generic|System.Linq|System.Text|System.Threading|System.Threading.Tasks"
}

test "a name carrying a dot is already qualified and one without is not" {
    assert EditorTypeCatalogFacts.IsQualifiedTypeName("System.Console")
    assert EditorTypeCatalogFacts.IsQualifiedTypeName("A.B")
    assert !EditorTypeCatalogFacts.IsQualifiedTypeName("Console")
    assert !EditorTypeCatalogFacts.IsQualifiedTypeName("")
}

test "a qualified name is probed EXACTLY ONCE and never under a prefix" {
    candidates := EditorTypeCatalogFacts.CandidateTypeFullNames("System.Text.StringBuilder")

    assert candidates.Length == 1
    assert candidates[0] == "System.Text.StringBuilder"
}

test "an unqualified name is probed as written FIRST and then under each prefix in order" {
    candidates := EditorTypeCatalogFacts.CandidateTypeFullNames("Console")

    assert candidates.Length == 8
    assert candidates[0] == "Console"
    assert candidates[1] == "System.Console"
    assert candidates[2] == "System.Collections.Console"
    assert candidates[7] == "System.Threading.Tasks.Console"

    // DEFINED from the prefix list, not a second copy of it.
    prefixes := EditorTypeCatalogFacts.NamespaceProbePrefixes()
    index := 0
    while index < prefixes.Length {
        assert candidates[index + 1] == prefixes[index] + ".Console"
        index = index + 1
    }
}

// ── how a type name is spelled ───────────────────────────────────────────────────────────────

test "a trailing question mark is nullability and the trim after it lets a space through" {
    assert EditorTypeCatalogFacts.StripNullableSuffix("string?") == "string"
    assert EditorTypeCatalogFacts.StripNullableSuffix("string ?") == "string"
    assert EditorTypeCatalogFacts.StripNullableSuffix("string") == "string"
    assert EditorTypeCatalogFacts.StripNullableSuffix("") == ""

    // Only ONE suffix is removed per call; the caller does not loop and neither does this.
    assert EditorTypeCatalogFacts.StripNullableSuffix("string??") == "string?"
}

test "an array peels ONE rank and the element name is what gets resolved" {
    assert EditorTypeCatalogFacts.IsArrayTypeName("int[]")
    assert EditorTypeCatalogFacts.IsArrayTypeName("int[][]")
    assert !EditorTypeCatalogFacts.IsArrayTypeName("int")
    assert !EditorTypeCatalogFacts.IsArrayTypeName("")
    assert !EditorTypeCatalogFacts.IsArrayTypeName("List<int>")

    assert EditorTypeCatalogFacts.ArrayElementTypeName("int[]") == "int"
    assert EditorTypeCatalogFacts.ArrayElementTypeName("int []") == "int"
    assert EditorTypeCatalogFacts.ArrayElementTypeName("int[][]") == "int[]"
    assert EditorTypeCatalogFacts.ArrayElementTypeName("int") == "int"
}

test "a written generic resolves to its OPEN definition and the arguments are discarded" {
    assert EditorTypeCatalogFacts.StripGenericArgumentList("Task<string>") == "Task"
    assert EditorTypeCatalogFacts.StripGenericArgumentList("Dictionary<string, List<int>>") == "Dictionary"
    assert EditorTypeCatalogFacts.StripGenericArgumentList("Task <string>") == "Task"
    assert EditorTypeCatalogFacts.StripGenericArgumentList("Task") == "Task"
}

test "the completion display name truncates at the FIRST arity backtick" {
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("List`1") == "List"
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("Dictionary`2") == "Dictionary"
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("Console") == "Console"
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("") == ""
}

test "the display rule AGREES with StripGenericArity on a Type name and DIFFERS on a two-run one" {
    // A `Type.Name` carries at most ONE arity suffix, and over all 1,391 exported types the
    // editor's universe can reach the two rules were measured identical.
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("List`1") == DocQueryKernels.StripGenericArity("List`1")
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("Dictionary`2") == DocQueryKernels.StripGenericArity("Dictionary`2")
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("Console") == DocQueryKernels.StripGenericArity("Console")

    // They are DIFFERENT total functions, and this is where they part. Recorded rather than
    // unified, because unifying them changes what `nlc query` prints too.
    assert EditorTypeCatalogFacts.CompletionTypeDisplayName("Outer`1Inner`2") == "Outer"
    assert DocQueryKernels.StripGenericArity("Outer`1Inner`2") == "OuterInner"
}

// ── what may be offered ──────────────────────────────────────────────────────────────────────

test "an offerable type is public, top-level, namespaced and not compiler-generated" {
    assert EditorTypeCatalogFacts.IsOfferableCompletionType("Console", "System", "System.Console", true, false)
}

test "a non-public or NESTED type is never offered" {
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Console", "System", "System.Console", false, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Enumerator", "System", "System.List+Enumerator", true, true)
}

test "a type with no namespace or no full name has no import edit to write and is not offered" {
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Global", null, "Global", true, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Global", "", "Global", true, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Global", "   ", "Global", true, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Global", "System", null, true, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Global", "System", "", true, false)
}

test "a compiler-generated name is not offered, by either of the two spellings the CLR uses" {
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("<>c", "System", "System.<>c", true, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("<Foo>d__1", "System", "System.<Foo>d__1", true, false)
    assert !EditorTypeCatalogFacts.IsOfferableCompletionType("Foo__Bar", "System", "System.Foo__Bar", true, false)

    // One underscore is a legal name a user can write, and it stays offerable.
    assert EditorTypeCatalogFacts.IsOfferableCompletionType("Foo_Bar", "System", "System.Foo_Bar", true, false)
}

test "a TYPE prefix matches case-INSENSITIVELY and an empty prefix matches everything" {
    assert EditorTypeCatalogFacts.MatchesCompletionPrefix("Console", "Cons")
    assert EditorTypeCatalogFacts.MatchesCompletionPrefix("Console", "cons")
    assert EditorTypeCatalogFacts.MatchesCompletionPrefix("Console", "CONS")
    assert EditorTypeCatalogFacts.MatchesCompletionPrefix("Console", "")
    assert !EditorTypeCatalogFacts.MatchesCompletionPrefix("Console", "Xyz")
}

test "a NAMESPACE segment prefix matches case-SENSITIVELY and the asymmetry is deliberate" {
    assert EditorTypeCatalogFacts.MatchesNamespaceSegmentPrefix("Collections", "Coll")
    assert !EditorTypeCatalogFacts.MatchesNamespaceSegmentPrefix("Collections", "coll")
    assert EditorTypeCatalogFacts.MatchesNamespaceSegmentPrefix("Collections", "")

    // The two rules disagree on the SAME pair of strings, and that is the whole point.
    assert EditorTypeCatalogFacts.MatchesCompletionPrefix("Collections", "coll")
    assert !EditorTypeCatalogFacts.MatchesNamespaceSegmentPrefix("Collections", "coll")
}

test "one completion carries at most two hundred importable types" {
    assert EditorTypeCatalogFacts.MaxImportableTypeResults() == 200
}

// ── the order they come out in ───────────────────────────────────────────────────────────────

test "the four hand-named namespaces rank ahead of every other System one, which ranks ahead of the rest" {
    assert EditorTypeCatalogFacts.NamespacePriority("System") == 0
    assert EditorTypeCatalogFacts.NamespacePriority("System.Collections.Generic") == 1
    assert EditorTypeCatalogFacts.NamespacePriority("System.Threading.Tasks") == 2
    assert EditorTypeCatalogFacts.NamespacePriority("System.Linq") == 3
    assert EditorTypeCatalogFacts.NamespacePriority("System.Text") == 10
    assert EditorTypeCatalogFacts.NamespacePriority("System.Collections") == 10
    assert EditorTypeCatalogFacts.NamespacePriority("Microsoft.Extensions.Logging") == 20
    assert EditorTypeCatalogFacts.NamespacePriority("") == 20

    // `System` itself is rank 0 and is NOT caught by the `System.` prefix arm, which needs the dot.
    assert EditorTypeCatalogFacts.NamespacePriority("Systematic") == 20
}

test "rank decides first, then the offered NAME, then the namespace it came from" {
    // rank
    assert EditorTypeCatalogFacts.CompareImportableTypes("Zebra", "System", "Alpha", "System.Text") == -1
    assert EditorTypeCatalogFacts.CompareImportableTypes("Alpha", "System.Text", "Zebra", "System") == 1

    // name, inside one rank
    assert EditorTypeCatalogFacts.CompareImportableTypes("Alpha", "System", "Zebra", "System") == -1
    assert EditorTypeCatalogFacts.CompareImportableTypes("Zebra", "System", "Alpha", "System") == 1

    // namespace, inside one rank and one name
    assert EditorTypeCatalogFacts.CompareImportableTypes("Same", "System.Aaa", "Same", "System.Bbb") == -1
    assert EditorTypeCatalogFacts.CompareImportableTypes("Same", "System.Bbb", "Same", "System.Aaa") == 1
    assert EditorTypeCatalogFacts.CompareImportableTypes("Same", "System", "Same", "System") == 0
}

test "the tie-breaks are ORDINAL so a completion list does not reorder itself under a locale" {
    // Ordinal puts every uppercase letter before every lowercase one; a culture-aware compare does
    // not, and a completion list that reshuffles per machine is a bug.
    assert EditorTypeCatalogFacts.CompareImportableTypes("Zebra", "System", "alpha", "System") == -1
    assert EditorTypeCatalogFacts.CompareImportableTypes("alpha", "System", "Zebra", "System") == 1

    // And it is the owner that already spells ordinal comparison, not a second copy.
    assert AnalyzerMetadataLoadPolicy.CompareOrdinalText("Zebra", "alpha") == -1

    // The namespace list orders the same way, through the same owner.
    assert EditorTypeCatalogFacts.CompareNamespaceSegments("Collections", "Threading") == -1
    assert EditorTypeCatalogFacts.CompareNamespaceSegments("Threading", "Collections") == 1
    assert EditorTypeCatalogFacts.CompareNamespaceSegments("IO", "io") == -1
    assert EditorTypeCatalogFacts.CompareNamespaceSegments("Text", "Text") == 0
}

// ── namespaces ───────────────────────────────────────────────────────────────────────────────

test "the well-known namespace seeds are twenty and every one is a System or Microsoft namespace" {
    seeds := EditorTypeCatalogFacts.WellKnownNamespaceSeeds()

    assert seeds.Length == 20
    assert seeds[0] == "System"
    assert seeds[19] == "Microsoft.AspNetCore.Mvc"
    assert EtcContains(seeds, "System.Text.RegularExpressions")
    assert EtcContains(seeds, "Microsoft.Extensions.DependencyInjection")

    index := 0
    while index < seeds.Length {
        assert seeds[index].StartsWith("System", StringComparison.Ordinal) || seeds[index].StartsWith("Microsoft.", StringComparison.Ordinal)
        index = index + 1
    }
}

test "a prefix ending in a dot means CHILDREN OF and leaves no segment half-typed" {
    assert EditorTypeCatalogFacts.NamespacePrefixParent("System.") == "System"
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("System.") == ""

    assert EditorTypeCatalogFacts.NamespacePrefixParent("System.Collections.") == "System.Collections"
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("System.Collections.") == ""
}

test "a partly typed segment splits at its LAST dot into parent and segment" {
    assert EditorTypeCatalogFacts.NamespacePrefixParent("System.Co") == "System"
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("System.Co") == "Co"

    assert EditorTypeCatalogFacts.NamespacePrefixParent("System.Collections.Gen") == "System.Collections"
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("System.Collections.Gen") == "Gen"
}

test "an empty or dotless prefix sits in the GLOBAL namespace, which is a place and not an absence" {
    assert EditorTypeCatalogFacts.NamespacePrefixParent("") == ""
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("") == ""

    assert EditorTypeCatalogFacts.NamespacePrefixParent("Sys") == ""
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("Sys") == "Sys"

    // Surrounding whitespace is the editor's, not the user's.
    assert EditorTypeCatalogFacts.NamespacePrefixParent("  System.Co  ") == "System"
    assert EditorTypeCatalogFacts.NamespacePrefixSegment("  System.Co  ") == "Co"
}

test "a namespace tree is offered ONE LEVEL AT A TIME" {
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.Collections.Generic", "") == "System"
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.Collections.Generic", "System") == "Collections"
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.Collections.Generic", "System.Collections") == "Generic"
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System", "") == "System"
}

test "a namespace contributes NOTHING under a parent it does not descend from, or under itself" {
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.Text", "Microsoft") == ""
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System", "System") == ""
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.Text", "System.Text") == ""

    // A PREFIX MATCH IS NOT A DESCENDANT. `System.TextIsh` is not under `System.Text`, and the dot
    // in the comparison is what says so.
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.TextIsh", "System.Text") == ""
    assert EditorTypeCatalogFacts.NextNamespaceSegment("System.Text.Json", "System.Text") == "Json"
}

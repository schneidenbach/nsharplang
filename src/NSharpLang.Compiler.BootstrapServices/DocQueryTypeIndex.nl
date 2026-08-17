namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Reflection


// WHICH CLR TYPE A NAME MEANS, AND WHERE THE DOCUMENTATION FOR IT LIVES.
//
// `nlc query doc Console` is one word and there are, on a loaded .NET surface, several thousand
// public types it could be. This file is the whole of the answer: it indexes every public type of
// every assembly it is given under the names a user might type, resolves a name through those
// indexes in a fixed order, and remembers where the reference packs that carry the XML docs are.
//
// THE RESOLUTION ORDER IS THE POLICY, AND IT IS FOUR DOORS TRIED IN ONE DIRECTION.
//   1. the cache — a name already answered answers the same way forever;
//   2. the QUALIFIED index, on the name as typed, then on the name with its generic arity stripped,
//      so `List` and `List<T>` reach the same row;
//   3. a qualified SUFFIX search, but only for a name that already contains a dot — `Text.Json`
//      should find `System.Text.Json`, while a bare `Json` must not drag in every namespace that
//      ends in one;
//   4. the SIMPLE-name index, on the last segment.
// Only the first door is a memo. The other three are ordered by how much the caller told us: an
// exact qualified name is evidence, a suffix is a hint, and a bare simple name is a guess — so a
// guess must never outrank evidence, which is what the order enforces.
//
// AMBIGUITY IS RESOLVED, NOT REPORTED. Every door that can produce more than one candidate hands
// the set to `SelectBestDocType`, which is why the file dedupes STABLY first: the scorer breaks ties
// by namespace and full name, and a tie it cannot break must fall to the FIRST candidate the index
// saw, so an unstable dedupe would make `nlc query doc List` answer differently on different runs.
//
// THE INDEX IS BUILT ONCE PER ASSEMBLY AND NEVER REBUILT. `AddAssembly` is idempotent by assembly
// NAME rather than by identity, so the same logical assembly loaded twice — which the reference-pack
// scan does routinely — indexes once.
class DocQueryTypeIndex {
    assemblies: List<Assembly>
    typeCache: Dictionary<string, Type>
    typesBySimpleName: Dictionary<string, List<Type>>
    typesByQualifiedName: Dictionary<string, List<Type>>
    loadedAssemblyNames: HashSet<string>
    referencePackDirectories: string[]?
    unloadableAssemblyNames: List<string>

    // EVERY INDEX IS CASE-INSENSITIVE AND THAT IS DELIBERATE: `nlc query doc console` answers
    // `System.Console`. The comparer is the ONLY thing that makes it so, and it belongs on the
    // dictionaries rather than on the lookups, so no future door can forget it.
    constructor() {
        assemblies = new List<Assembly>()
        typeCache = new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase)
        typesBySimpleName = new Dictionary<string, List<Type>>(StringComparer.OrdinalIgnoreCase)
        typesByQualifiedName = new Dictionary<string, List<Type>>(StringComparer.OrdinalIgnoreCase)
        loadedAssemblyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        referencePackDirectories = null
        unloadableAssemblyNames = new List<string>()
    }

    // INDEX ONE ASSEMBLY UNDER ALL THREE OF THE NAMES A TYPE ANSWERS TO: its simple name, its
    // lookup name (the full name with nesting flattened to dots and the arity stripped), and its
    // raw full name where that differs. A type is reachable by any of them and by nothing else.
    func AddAssembly(assembly: Assembly) {
        assemblyName := assembly.GetName().get_Name() ?? assembly.get_FullName()
        if assemblyName == null {
            return
        }

        if string.IsNullOrWhiteSpace(assemblyName) {
            return
        }

        if !loadedAssemblyNames.Add(assemblyName) {
            return
        }

        assemblies.Add(assembly)

        for candidateType in GetPublicTypes(assembly) {
            AddTypeIndex(typesBySimpleName, DocQueryKernels.StripGenericArity(candidateType.get_Name()), candidateType)
            AddTypeIndex(typesByQualifiedName, DocQueryKernels.GetReflectionLookupTypeName(candidateType), candidateType)

            qualifiedName := DocQueryKernels.GetQualifiedTypeIndexName(candidateType.get_FullName())
            if qualifiedName != null {
                AddTypeIndex(typesByQualifiedName, qualifiedName, candidateType)
            }
        }
    }

    // ONLY WHAT A USER COULD HAVE WRITTEN. A nested PUBLIC type is included even though its
    // `IsPublic` is false, because `Environment.SpecialFolder` is a name a user types.
    static func GetPublicTypes(assembly: Assembly): List<Type> {
        results := new List<Type>()
        for candidateType in assembly.GetTypes() {
            if DocQueryKernels.ShouldIncludePublicType(candidateType.get_IsPublic(), candidateType.get_IsNestedPublic()) {
                results.Add(candidateType)
            }
        }

        return results
    }

    // APPEND-ONLY AND DUPLICATE-FREE, IN FIRST-SEEN ORDER. The bucket order is the tie-break the
    // scorer falls back on, so appending rather than inserting is what makes resolution stable.
    static func AddTypeIndex(index: Dictionary<string, List<Type>>, key: string, candidate: Type) {
        bucket := new List<Type>()
        if !index.TryGetValue(key, out bucket) {
            bucket = new List<Type>()
            index[key] = bucket
        }

        if !bucket.Contains(candidate) {
            bucket.Add(candidate)
        }
    }

    // THE FOUR DOORS, IN ORDER. See the file note: the order is the policy.
    func ResolveType(name: string): Type? {
        cached := typeof(string)
        if typeCache.TryGetValue(name, out cached) {
            return cached
        }

        strippedName := DocQueryKernels.StripGenericArity(name)

        exactMatches := new List<Type>()
        if typesByQualifiedName.TryGetValue(name, out exactMatches) && exactMatches.Count > 0 {
            return CacheType(name, SelectBestType(name, exactMatches))
        }

        strippedMatches := new List<Type>()
        if typesByQualifiedName.TryGetValue(strippedName, out strippedMatches) && strippedMatches.Count > 0 {
            return CacheType(name, SelectBestType(name, strippedMatches))
        }

        // A SUFFIX SEARCH IS OFFERED ONLY TO A NAME THAT ALREADY HAS A DOT IN IT. Without that
        // gate every bare simple name would scan the whole qualified index and match on its last
        // segment, which is door 4's job and a far weaker one.
        if DocQueryKernels.ShouldSearchQualifiedSuffix(strippedName) {
            suffixCandidates := new List<Type>()
            for indexEntry in typesByQualifiedName {
                if DocQueryKernels.IsQualifiedTypeSuffixMatch(indexEntry.Key, strippedName) {
                    for candidate in indexEntry.Value {
                        suffixCandidates.Add(candidate)
                    }
                }
            }

            suffixMatches := DeduplicateTypeCandidates(suffixCandidates)
            if suffixMatches.Length > 0 {
                return CacheType(name, SelectBestType(name, suffixMatches))
            }
        }

        shortName := DocQueryKernels.GetResolveTypeShortName(strippedName)
        simpleMatches := new List<Type>()
        if typesBySimpleName.TryGetValue(shortName, out simpleMatches) && simpleMatches.Count > 0 {
            return CacheType(name, SelectBestType(name, simpleMatches))
        }

        return null
    }

    // A MISS IS NOT CACHED. Only a hit is, so an assembly added after a failed lookup can still
    // answer it — which is exactly what the reference-pack scan does after the seed load.
    func CacheType(name: string, resolved: Type?): Type? {
        if resolved != null {
            typeCache[name] = resolved
        }

        return resolved
    }

    // DEDUPE STABLY, THEN SCORE. Never the other way round: the scorer's last tie-break is source
    // order, so a dedupe that reordered would make the answer depend on the walk.
    static func SelectBestType(query: string, candidates: IReadOnlyList<Type>): Type? {
        return DocQueryKernels.SelectBestDocType(query, DeduplicateTypeCandidates(candidates))
    }

    // FIRST OCCURRENCE WINS AND THE REST OF THE ORDER SURVIVES. The same type reaches a bucket from
    // several indexes and from several assemblies that forward it.
    static func DeduplicateTypeCandidates(candidates: IReadOnlyList<Type>): Type[] {
        return DocQueryKernels.DeduplicateStableTypes(candidates)
    }

    // `Environment.SpecialFolder.Something` IS WALKED, NOT SEARCHED. Each part must be a public
    // nested type of the one before it, and the first part that is not ends the walk with no answer
    // — a nested chain that half-matches is not a partial hit, it is a miss.
    static func ResolveNestedTypeChain(reflectionType: Type, parts: string[]): Type? {
        publicOnly := BindingFlags.Public
        current := reflectionType
        partIndex := 0
        while partIndex < parts.Length {
            nestedTypes := current.GetNestedTypes(publicOnly)
            next: Type? = null
            nestedIndex := 0
            while nestedIndex < nestedTypes.Length && next == null {
                nestedType := nestedTypes[nestedIndex]
                if DocQueryKernels.IsDocMemberNameMatch(nestedType.get_Name(), parts[partIndex]) {
                    next = nestedType
                }

                nestedIndex = nestedIndex + 1
            }

            if next == null {
                return null
            }

            current = next
            partIndex = partIndex + 1
        }

        return current
    }

    // WHERE THE XML DOCS ARE, COMPUTED ONCE. The directories are derived from where the already
    // indexed assemblies were loaded from, plus `DOTNET_ROOT`; the cache is what stops a
    // per-assembly doc load from re-walking the filesystem for every summary.
    func GetReferencePackDirectories(): string[] {
        cachedDirectories := referencePackDirectories
        if cachedDirectories != null {
            return cachedDirectories
        }

        locations := new string[](assemblies.Count)
        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            indexedAssembly := assemblies[assemblyIndex]
            locations[assemblyIndex] = indexedAssembly.get_Location()
            assemblyIndex = assemblyIndex + 1
        }

        computed := DocQueryKernels.GetReferencePackDirectories(locations, Environment.GetEnvironmentVariable("DOTNET_ROOT"))
        referencePackDirectories = computed
        return computed
    }

    // WHICH ASSEMBLIES THE REFERENCE PACKS OFFER, by name, deduped ordinal-ignore-case in first-seen
    // order — the same file appears under several packs and the first pack found wins.
    func DiscoverReferencePackAssemblyNames(): string[] {
        return DocQueryKernels.DiscoverReferencePackAssemblyNames(GetReferencePackDirectories())
    }

    // A PACK NAME THE RUNTIME CANNOT LOAD IS NOTED, NEVER FATAL. The reference packs offer more
    // assemblies than the CLI's own runtime carries — on a default install the whole ASP.NET Core
    // surface — so an unloadable name is an expected condition, not an error: the loader skips it,
    // records it here, and `DescribeDocLookupMiss` decides what a failed lookup says about it.
    func NoteUnloadableAssembly(assemblyName: string) {
        if string.IsNullOrWhiteSpace(assemblyName) {
            return
        }

        unloadableAssemblyNames.Add(assemblyName)
    }

    // THE NOTED NAMES, deduped ordinal-ignore-case in first-seen order — the same policy the
    // discovery scan applies to the names it offers, so note-time can stay a plain append.
    func GetUnloadableAssemblyNames(): string[] {
        return DocQueryKernels.DeduplicateStableStringsOrdinalIgnoreCase(unloadableAssemblyNames)
    }

    // WHERE ONE ASSEMBLY'S XML FILE IS: beside the assembly if it shipped there, otherwise in a
    // reference pack. The assembly's METADATA name is passed as well as its path, because a
    // single-file or in-memory assembly has no path to derive it from.
    func GetXmlDocPath(assembly: Assembly): string {
        return DocQueryKernels.GetXmlDocPath(assembly.get_Location(), assembly.GetName().get_Name(), GetReferencePackDirectories())
    }
}

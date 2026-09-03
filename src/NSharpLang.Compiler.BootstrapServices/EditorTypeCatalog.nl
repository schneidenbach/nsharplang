namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// A PUBLIC CLR TYPE THE EDITOR CAN OFFER AS AN IDENTIFIER COMPLETION WITH AN IMPORT EDIT.
class EditorImportableType {
    Name: string
    FullName: string
    Namespace: string
    IsInterface: bool
    IsEnum: bool

    constructor(displayName: string, typeFullName: string, typeNamespace: string, isInterfaceType: bool, isEnumType: bool) {
        Name = displayName
        FullName = typeFullName
        Namespace = typeNamespace
        IsInterface = isInterfaceType
        IsEnum = isEnumType
    }
}

// THE EDITOR'S TYPE UNIVERSE, WHICH IS NOW THE ANALYZER'S.
//
// The language server used to reach three assemblies of its own process through four `Type.GetType`
// seed names, while the analyzer sitting beside it held a `MetadataLoadContext` over 27 common
// assemblies PLUS every reference the project declares. So completion could not offer, and hover
// could not name, a type from a package the user depends on. This owner closes that by holding the
// analyzer's `_mlcAssemblies` BY REFERENCE — the seam `AnalyzerExternalTypeProbe`, `AnalyzerImports`
// and `AnalyzerMetadataLoadSurface` already use — and doing the reflection over it.
//
// EVERY READ HERE IS METADATA-ONLY, WHICH IS WHAT MAKES THE MOVE SAFE. The consumers of a resolved
// type ask for `Name`, `Namespace`, `FullName`, `IsPublic`, `IsNested`, `IsInterface`, `IsEnum` and
// `MakeArrayType()`, and every one of those answers over a `MetadataLoadContext` type exactly as it
// does over a runtime one. Nothing here calls `Invoke`, `GetValue` or `TypeHandle`, which are the
// members a metadata context refuses.
//
// THE UNIVERSE IS MUTABLE, AND THAT IS THE WHOLE DIFFICULTY. The old universe was fixed for the life
// of the process, so its caches could be filled once and never invalidated. This list GROWS:
// `DocumentManager` calls `Analyzer.LoadFromProjectConfig` once per project directory, inside the
// analysis of the first file opened from it — which is AFTER the window is up and after completions
// may already have been served. A cache filled before that point and never re-asked would pin a
// namespace set that predates the project's own packages, which is precisely the defect this owner
// exists to remove. So every cache is keyed on the list's identity and dropped when it changes. The
// list is append-only and never reordered, so its COUNT is a sufficient and cheap key; the contract
// states that, and states the behaviour rather than the mechanism.
//
// THE FACADE ASYMMETRY, MEASURED (022/4a). Under a metadata context `Assembly.GetType` FOLLOWS type
// forwarders and `Assembly.GetExportedTypes` DOES NOT. `System.Runtime` is a pure facade and exports
// ZERO types, yet resolves `System.String` by name. So full-name resolution works through the facade
// while the simple-name scan and the namespace set see nothing through it — those depend on
// `System.Private.CoreLib` being in the analyzer's list, which it is, and which a contract pins.
class EditorTypeCatalog {

    // The analyzer's metadata assemblies, held by reference and never resnapshotted.
    assemblies: List<Assembly>

    // Resolution memo, and the exported-type tables parallel to `assemblies` by INDEX. An index is
    // the honest key for an append-only list; keying on the assembly object would ask a metadata
    // type for an identity it does not owe us.
    typeCache: Dictionary<string, Type>
    exportedTypes: List<Type[]>
    namespaceCache: List<string>?

    // THE IDENTITY KEY. Every cache above is valid only while the universe has this many assemblies.
    cachedAssemblyCount: int

    constructor(metadataAssemblies: List<Assembly>) {
        assemblies = metadataAssemblies
        typeCache = new Dictionary<string, Type>(StringComparer.Ordinal)
        exportedTypes = new List<Type[]>()
        namespaceCache = null
        cachedAssemblyCount = -1
    }

    // One call at the top of every entry point. A universe that has grown invalidates everything
    // derived from the old one — including the RESOLUTION memo, because a name that missed before
    // may hit now, and a cached miss is not stored but a cached hit could shadow a nearer answer.
    func EnsureCurrentUniverse() {
        if cachedAssemblyCount == assemblies.Count {
            return
        }

        typeCache.Clear()
        exportedTypes.Clear()
        namespaceCache = null
        cachedAssemblyCount = assemblies.Count
    }

    func ExportedTypesAt(index: int): Type[] {
        while exportedTypes.Count <= index {
            exportedTypes.Add(new Type[](0))
        }

        cached := exportedTypes[index]
        if cached.Length > 0 {
            return cached
        }

        loaded := new Type[](0)
        try {
            loaded = assemblies[index].GetExportedTypes()
        } catch scanError: Exception {
        }

        exportedTypes[index] = loaded
        return loaded
    }

    // Exact, and CASE-SENSITIVE by construction: the one-argument `Assembly.GetType` overload is the
    // case-sensitive read, so a case-flipped spelling answers a different type or none — which is a
    // property of the read rather than a curation choice this owner gets to make.
    func ResolveByFullName(fullName: string): Type? {
        index := 0
        while index < assemblies.Count {
            try {
                found := assemblies[index].GetType(fullName)
                if found != null {
                    return found
                }
            } catch lookupError: Exception {
            }

            index = index + 1
        }

        return null
    }

    // The last resort, and the half that CANNOT see through a facade.
    func ResolveBySimpleName(simpleName: string): Type? {
        index := 0
        while index < assemblies.Count {
            exported := ExportedTypesAt(index)
            typeIndex := 0
            while typeIndex < exported.Length {
                if exported[typeIndex].get_Name() == simpleName {
                    return exported[typeIndex]
                }

                typeIndex = typeIndex + 1
            }

            index = index + 1
        }

        return null
    }

    func ResolveType(typeName: string): Type? {
        EnsureCurrentUniverse()

        if string.IsNullOrWhiteSpace(typeName) {
            return null
        }

        name := EditorTypeCatalogFacts.StripNullableSuffix(typeName.Trim())

        // An array is resolved through its element, one rank per call.
        if EditorTypeCatalogFacts.IsArrayTypeName(name) {
            elementType := ResolveType(EditorTypeCatalogFacts.ArrayElementTypeName(name))
            if elementType == null {
                return null
            }

            arrayType := elementType.MakeArrayType()
            typeCache[name] = arrayType
            return arrayType
        }

        name = EditorTypeCatalogFacts.StripGenericArgumentList(name)

        aliasFullName := AnalyzerTypeReferenceFacts.BuiltInClrTypeName(name)
        if aliasFullName != null {
            name = aliasFullName
        } else if !EditorTypeCatalogFacts.IsQualifiedTypeName(name) {
            name = EditorTypeCatalogFacts.CommonShortTypeFullName(name) ?? name
        }

        cached := typeof(object)
        if typeCache.TryGetValue(name, out cached) {
            return cached
        }

        resolved: Type? = null
        candidates := EditorTypeCatalogFacts.CandidateTypeFullNames(name)
        candidateIndex := 0
        while candidateIndex < candidates.Length && resolved == null {
            resolved = ResolveByFullName(candidates[candidateIndex])
            candidateIndex = candidateIndex + 1
        }

        if resolved == null && !EditorTypeCatalogFacts.IsQualifiedTypeName(name) {
            resolved = ResolveBySimpleName(name)
        }

        if resolved != null {
            typeCache[name] = resolved
            return resolved
        }

        return null
    }

    // ---------------------------------------------------------------------------------------------
    // COMPLETION
    // ---------------------------------------------------------------------------------------------

    func Offerable(candidate: Type?): EditorImportableType? {
        if candidate == null {
            return null
        }

        // `IsPublic` is true only for a TOP-LEVEL public type — a public NESTED type answers false
        // here and is rejected by the same test (022/4a measured 138 of 1,498 exported types
        // answering `IsPublic == false`, and 138 was exactly the nested count).
        if !EditorTypeCatalogFacts.IsOfferableCompletionType(candidate.get_Name(), candidate.get_Namespace(), candidate.get_FullName(), candidate.get_IsPublic(), candidate.get_IsNested()) {
            return null
        }

        return new EditorImportableType(
            EditorTypeCatalogFacts.CompletionTypeDisplayName(candidate.get_Name()),
            candidate.get_FullName() ?? "",
            candidate.get_Namespace() ?? "",
            candidate.get_IsInterface(),
            candidate.get_IsEnum()
        )
    }

    func AddImportable(results: List<EditorImportableType>, seen: HashSet<string>, candidate: Type?, forceInclude: bool, prefix: string) {
        offerable := Offerable(candidate)
        if offerable == null {
            return
        }

        if !forceInclude && !EditorTypeCatalogFacts.MatchesCompletionPrefix(offerable.Name, prefix) {
            return
        }

        if seen.Contains(offerable.FullName) {
            return
        }

        seen.Add(offerable.FullName)
        results.Add(offerable)
    }

    // ORDERED BY THE POLICY OWNER'S COMPARATOR, by insertion. `Comparer<T>.Create` takes a lambda and
    // a lambda over an external delegate is off the columnar surface, so the sort is spelled out —
    // the same route `AnalyzerReferenceLoadReport` took before the ranged `Array.Sort` overload
    // became reachable. The result sets are capped at 200, so an insertion sort is the right size.
    func SortImportable(results: List<EditorImportableType>) {
        position := 1
        while position < results.Count {
            candidate := results[position]
            scan := position - 1
            while scan >= 0 && EditorTypeCatalogFacts.CompareImportableTypes(results[scan].Name, results[scan].Namespace, candidate.Name, candidate.Namespace) > 0 {
                results[scan + 1] = results[scan]
                scan = scan - 1
            }

            results[scan + 1] = candidate
            position = position + 1
        }
    }

    func ImportableTypes(prefix: string): List<EditorImportableType> {
        EnsureCurrentUniverse()

        trimmed := prefix.Trim()
        results := new List<EditorImportableType>()
        seen := new HashSet<string>(StringComparer.Ordinal)

        // The curated roster is offered whatever the prefix, so general completion stays useful
        // without posting the whole framework into the editor.
        roster := EditorTypeCatalogFacts.CommonShortTypeFullNames()
        rosterIndex := 0
        while rosterIndex < roster.Length {
            AddImportable(results, seen, ResolveByFullName(roster[rosterIndex]), true, trimmed)
            rosterIndex = rosterIndex + 1
        }

        if trimmed.Length > 0 {
            index := 0
            while index < assemblies.Count {
                exported := ExportedTypesAt(index)
                typeIndex := 0
                while typeIndex < exported.Length {
                    AddImportable(results, seen, exported[typeIndex], false, trimmed)
                    typeIndex = typeIndex + 1
                }

                index = index + 1
            }
        }

        SortImportable(results)

        capped := new List<EditorImportableType>()
        limit := EditorTypeCatalogFacts.MaxImportableTypeResults()
        position := 0
        while position < results.Count && position < limit {
            capped.Add(results[position])
            position = position + 1
        }

        return capped
    }

    // ---------------------------------------------------------------------------------------------
    // NAMESPACES
    // ---------------------------------------------------------------------------------------------

    // The policy owner's seed list unioned with every namespace of every assembly the editor can see.
    // The seed answers the first keystroke after `import`, before any scan has run.
    func KnownNamespaces(): List<string> {
        EnsureCurrentUniverse()

        existing := namespaceCache
        if existing != null {
            return existing
        }

        namespaces := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)

        seeds := EditorTypeCatalogFacts.WellKnownNamespaceSeeds()
        seedIndex := 0
        while seedIndex < seeds.Length {
            if !seen.Contains(seeds[seedIndex]) {
                seen.Add(seeds[seedIndex])
                namespaces.Add(seeds[seedIndex])
            }

            seedIndex = seedIndex + 1
        }

        index := 0
        while index < assemblies.Count {
            exported := ExportedTypesAt(index)
            typeIndex := 0
            while typeIndex < exported.Length {
                candidateNamespace := exported[typeIndex].get_Namespace() ?? ""
                if !string.IsNullOrWhiteSpace(candidateNamespace) && !seen.Contains(candidateNamespace) {
                    seen.Add(candidateNamespace)
                    namespaces.Add(candidateNamespace)
                }

                typeIndex = typeIndex + 1
            }

            index = index + 1
        }

        namespaceCache = namespaces
        return namespaces
    }

    func SortSegments(segments: List<string>) {
        position := 1
        while position < segments.Count {
            candidate := segments[position]
            scan := position - 1
            while scan >= 0 && EditorTypeCatalogFacts.CompareNamespaceSegments(segments[scan], candidate) > 0 {
                segments[scan + 1] = segments[scan]
                scan = scan - 1
            }

            segments[scan + 1] = candidate
            position = position + 1
        }
    }

    func NamespaceSuggestions(prefix: string): List<string> {
        namespaces := KnownNamespaces()
        results := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        parentNamespace := EditorTypeCatalogFacts.NamespacePrefixParent(prefix)
        segmentPrefix := EditorTypeCatalogFacts.NamespacePrefixSegment(prefix)

        index := 0
        while index < namespaces.Count {
            nextSegment := EditorTypeCatalogFacts.NextNamespaceSegment(namespaces[index], parentNamespace)
            if nextSegment.Length > 0 && EditorTypeCatalogFacts.MatchesNamespaceSegmentPrefix(nextSegment, segmentPrefix) {
                if !seen.Contains(nextSegment) {
                    seen.Add(nextSegment)
                    results.Add(nextSegment)
                }
            }

            index = index + 1
        }

        SortSegments(results)
        return results
    }
}

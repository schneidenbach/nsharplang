namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// The analyzer's EXTERNAL (MetadataLoadContext) type probe: every question the semantic phase
// answers by looking at referenced assembly metadata rather than at source.
//
// One instance is built per analyzer and holds the memo cache that makes the probe affordable. The
// assembly list and the ordered using-namespace list are the ANALYZER's live collections, handed in
// once by reference: both grow while a file's imports are processed, and this owner must see those
// additions, so it stores the references rather than copies. Do not snapshot them.
//
// `NamespaceExists` deliberately did NOT move with the rest of the metadata probe: it deduplicates the
// loaded assemblies by `Assembly.FullName`, and neither `Assembly.get_FullName` nor
// `AssemblyName.get_Name` is on the columnar external binding surface. Extending that surface is a
// compiler-capability change requiring a two-stage bootstrap, so that member and its own cache stay in
// the shell until the surface grows.
//
// THE PROBE ORDER IS BEHAVIOUR, NOT AN OPTIMISATION, and the cache participates in it:
//
//   1. the bare name as previously cached,
//   2. for each imported namespace IN IMPORT ORDER, "<namespace>.<name>" as previously cached, then
//      resolved against every loaded assembly in load order,
//   3. failing all of that, the first assembly (in load order) that EXPORTS a type whose simple name
//      or full name equals the spelling.
//
// Step 3 caches under the BARE name, so a later call takes step 1 and never reconsiders step 2 —
// which means dropping this cache mid-analysis can change an answer. That is why the cache lives
// with the probe and the probe is never rebuilt, and why the analyzer never clears it between
// `Analyze` calls: the assemblies it answers from outlive any single file.
//
// This owner is SILENT: it reports no diagnostic and records nothing into the semantic model. A name
// it cannot resolve is a null answer, and the caller decides what that means. Do not reintroduce any
// of this in C#.
//
// Not to be confused with `ColumnarBindingScopeFacts.TryResolveExternalType`: that one verifies a
// candidate against an EXPECTED emitted type identity for the columnar back end. This one answers
// "what, if anything, does this spelling name" for the analyzer's diagnostics.
class AnalyzerExternalTypeProbe {
    assemblies: List<Assembly>
    usingNamespaces: List<string>
    typeCache: Dictionary<string, Type>

    constructor(mlcAssemblies: List<Assembly>, importedNamespaces: List<string>) {
        assemblies = mlcAssemblies
        usingNamespaces = importedNamespaces
        typeCache = new Dictionary<string, Type>()
    }

    // The ordered probe. A fresh ReflectionTypeInfo per call, exactly as the analyzer's own resolver
    // produced: callers compare these by TYPE identity, never by reference.
    func ResolveExternalType(name: string): TypeInfo? {
        cachedType := typeof(object)
        if typeCache.TryGetValue(name, out cachedType) {
            return new ReflectionTypeInfo(cachedType)
        }

        namespaceIndex := 0
        while namespaceIndex < usingNamespaces.Count {
            fullName := usingNamespaces[namespaceIndex] + "." + name

            cachedFullType := typeof(object)
            if typeCache.TryGetValue(fullName, out cachedFullType) {
                return new ReflectionTypeInfo(cachedFullType)
            }

            assemblyIndex := 0
            while assemblyIndex < assemblies.Count {
                resolved := assemblies[assemblyIndex].GetType(fullName)
                if resolved != null {
                    typeCache[fullName] = resolved
                    return new ReflectionTypeInfo(resolved)
                }
                assemblyIndex = assemblyIndex + 1
            }

            namespaceIndex = namespaceIndex + 1
        }

        bareIndex := 0
        while bareIndex < assemblies.Count {
            exportedTypes := assemblies[bareIndex].GetExportedTypes()
            exportedIndex := 0
            while exportedIndex < exportedTypes.Length {
                candidate := exportedTypes[exportedIndex]
                if candidate.Name == name || candidate.FullName == name {
                    typeCache[name] = candidate
                    return new ReflectionTypeInfo(candidate)
                }
                exportedIndex = exportedIndex + 1
            }
            bareIndex = bareIndex + 1
        }

        return null
    }

    // The EXACT probe: no using-namespace prefixing and no exported-name scan, so it answers only
    // for a fully-qualified spelling. Shares the same cache as the ordered probe, which is why an
    // exact hit here is visible to a later bare-name lookup and vice versa.
    func ResolveExactExternalType(fullName: string): Type? {
        cachedType := typeof(object)
        if typeCache.TryGetValue(fullName, out cachedType) {
            return cachedType
        }

        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            resolved := assemblies[assemblyIndex].GetType(fullName)
            if resolved != null {
                typeCache[fullName] = resolved
                return resolved
            }
            assemblyIndex = assemblyIndex + 1
        }

        return null
    }

    // Every generic arity a spelling is available at, ascending: compiler-known first, then the
    // arity-qualified metadata probe (`Name`1`, `Name`2`, ...), which must land on an open
    // DEFINITION to count. 17 is the CLR's own limit on generic parameters.
    func KnownGenericHeadArities(wellKnownTypes: AnalyzerWellKnownTypes?, name: string): List<int> {
        arities := new List<int>()

        arity := 1
        while arity <= 17 {
            if AnalyzerWellKnownTypeFacts.KnownOpenGenericType(wellKnownTypes, name, arity) != null {
                arities.Add(arity)
            } else {
                arityQualified := ResolveExternalType(name + "`" + arity.ToString())
                reflection := arityQualified as ReflectionTypeInfo
                if reflection != null {
                    reflectionType := reflection.Type
                    if reflectionType.get_IsGenericTypeDefinition() {
                        arities.Add(arity)
                    }
                }
            }
            arity = arity + 1
        }

        return arities
    }
}

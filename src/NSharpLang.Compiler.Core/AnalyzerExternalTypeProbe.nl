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
// `NamespaceExists` is NOT here, and the reason is no longer the one this comment used to give. It
// once said that neither `Assembly.get_FullName` nor `AssemblyName.get_Name` was on the columnar
// external binding surface; both are, measured by execution against the pinned toolset. The question
// it answers simply belongs to a different owner: "does anything DECLARE this namespace" is an
// import's question, not a type reference's, and it lives with the rest of the import family in
// `AnalyzerImports` — with its own cache, because that cache is per-analysis while this one is not.
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

    // THE FRIEND RULE'S ONE OWNER, handed in by the analyzer so that the probe, member resolution and
    // completion all answer from the same grants. It is the analyzer's live instance, not a copy: the
    // compiling assembly name is set when the project config loads, which is after this probe is built.
    grants: InternalsVisibleToGrants

    // A FULL NAME NO LOADED ASSEMBLY DECLARES, REMEMBERED AGAINST THE ASSEMBLY COUNT THAT PROVED IT.
    //
    // Every question this owner answers is a sweep of `assemblies x Assembly.GetType`, and the MISS
    // is the expensive half: a hit stops at the assembly that answers, a miss pays for all of them,
    // and the import-ordered probe walks a whole PREFIX of misses before reaching the namespace that
    // answers. Re-sweeping those misses on every call is what made "does a SECOND import also supply
    // this spelling" look unaffordable, and that cost — not the rule — is why an imported-CLR tie
    // went unreported. Remembering the miss makes the second half of the sweep free after the first
    // file pays for it.
    //
    // THE COUNT IS THE INVALIDATION, AND IT IS EXACT. The assembly list is the analyzer's own and
    // only ever GROWS — imports load references into it as a file is read — so a remembered miss is
    // still a miss for as long as the count is unchanged, and a newly loaded assembly retries every
    // one of them. That is the same guarantee the previous "a miss is deliberately not cached"
    // comment was protecting, kept without paying for it twice.
    missedFullNames: Dictionary<string, int>

    // A PROBE WITH NO PROJECT BEHIND IT IS THE FRIEND OF NOTHING. The analyzer hands in its own
    // grants; a caller that builds a probe over a bare assembly list has no assembly identity to be
    // named by an `InternalsVisibleTo`, so it gets an unnamed instance and sees exactly the visible
    // surface.
    constructor(mlcAssemblies: List<Assembly>, importedNamespaces: List<string>): this(mlcAssemblies, importedNamespaces, new InternalsVisibleToGrants()) {
    }

    constructor(mlcAssemblies: List<Assembly>, importedNamespaces: List<string>, friendGrants: InternalsVisibleToGrants) {
        assemblies = mlcAssemblies
        usingNamespaces = importedNamespaces
        typeCache = new Dictionary<string, Type>()
        missedFullNames = new Dictionary<string, int>(StringComparer.Ordinal)
        grants = friendGrants
    }

    Grants: InternalsVisibleToGrants {
        get {
            return grants
        }
    }

    // THE ONE SWEEP EVERY QUESTION BELOW IS MADE OF: does any loaded assembly declare this exact full
    // name? A hit is cached under the full name and a miss under the assembly count, so the three
    // callers share one memo and cannot disagree about what the metadata says.
    func TryResolveFullName(fullName: string, out resolved: Type): bool {
        resolved = typeof(object)
        if typeCache.TryGetValue(fullName, out resolved) {
            return true
        }

        missedAtCount := 0
        if missedFullNames.TryGetValue(fullName, out missedAtCount) && missedAtCount == assemblies.Count {
            return false
        }

        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            candidate := assemblies[assemblyIndex].GetType(fullName)
            // `Assembly.GetType` answers for INTERNAL types too (`System.TokenType` lives in
            // System.Private.CoreLib); only a NAMEABLE type is a name this program can spell, so an
            // unnameable one is no rival for NL209 and no answer for a qualified spelling — the rule
            // C# lookup applies to every metadata type. An assembly that named this compilation in an
            // `InternalsVisibleTo` widens "nameable" to its internals, exactly as it does for C#.
            if grants.IsNameableType(candidate) {
                typeCache[fullName] = candidate
                resolved = candidate
                return true
            }
            assemblyIndex = assemblyIndex + 1
        }

        missedFullNames[fullName] = assemblies.Count
        return false
    }

    // WHY A FULLY-QUALIFIED SPELLING FAILED: because the type IS THERE and this compilation may not
    // name it.
    //
    // `TryResolveFullName` answers a single yes/no, and a `no` reaches the resolver's fall-through
    // where a DOTTED name is deliberately left unreported — namespace-qualified externals and
    // `Union.Case` references legitimately resolve through other channels, so a dotted miss is not
    // evidence of a typo. That leniency let `new <namespace>.<InternalType>()` compile and EMIT a
    // reference the CLR refuses at load, while the very same type written as a SIMPLE name was
    // NL201: one rule, two answers, decided by the spelling.
    //
    // This question closes exactly that hole and nothing wider. It says yes only when a referenced
    // assembly really declares the name and the friend rule is the only reason it was rejected, so
    // the resolver can report the SAME NL201 the simple spelling reports, for the same reason, and
    // every other dotted miss keeps the leniency it had. The nested spelling is walked the way
    // `ExternalQualifiedTypeResolver` walks it, because `A.B.C` may be `A.B+C` in metadata.
    func DeclaresUnnameableFullName(fullName: string): bool {
        if fullName == null || fullName.Length == 0 || !fullName.Contains(".") {
            return false
        }

        candidate := fullName
        searchEnd := candidate.Length
        while searchEnd > 0 {
            if DeclaredButUnnameable(candidate) {
                return true
            }

            separator := candidate.LastIndexOf('.', searchEnd - 1)
            if separator <= 0 {
                return false
            }

            candidate = candidate.Substring(0, separator) + "+" + candidate.Substring(separator + 1)
            searchEnd = separator
        }

        return false
    }

    private func DeclaredButUnnameable(fullName: string): bool {
        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            declared: Type? = null
            try {
                declared = assemblies[assemblyIndex].GetType(fullName)
            } catch {
                declared = null
            }

            if declared != null && !grants.IsNameableType(declared) {
                return true
            }

            assemblyIndex = assemblyIndex + 1
        }

        return false
    }

    // The ordered probe. A fresh ReflectionTypeInfo per call, exactly as the analyzer's own resolver
    // produced: callers compare these by TYPE identity, never by reference.
    func ResolveExternalType(name: string): TypeInfo? {
        cachedType := typeof(object)
        if typeCache.TryGetValue(name, out cachedType) {
            return new ReflectionTypeInfo(cachedType)
        }

        imported := ResolveImportedExternalType(name)
        if imported != null {
            return imported
        }

        bareIndex := 0
        while bareIndex < assemblies.Count {
            assembly := assemblies[bareIndex]
            // THE SCAN'S SURFACE IS THE NAMEABLE SURFACE. `GetExportedTypes()` is the public one and
            // stays the answer for an ordinary reference; a reference that made this compilation a
            // friend also offers its internals, and `GetTypes()` is the only reader that returns them.
            // The wider read is paid for ONLY by a granting assembly, so an ordinary project's scan
            // costs exactly what it did before.
            scanned := assembly.GetExportedTypes()
            if grants.GrantsAccess(assembly) {
                scanned = assembly.GetTypes()
            }

            exportedIndex := 0
            while exportedIndex < scanned.Length {
                candidate := scanned[exportedIndex]
                if (candidate.Name == name || candidate.FullName == name) && grants.IsNameableType(candidate) {
                    typeCache[name] = candidate
                    return new ReflectionTypeInfo(candidate)
                }
                exportedIndex = exportedIndex + 1
            }
            bareIndex = bareIndex + 1
        }

        return null
    }

    // STEP 2 ON ITS OWN: what an EXPLICITLY IMPORTED namespace declares, with no exported-name scan
    // behind it. The separation is what lets a caller ask the two halves different questions — an
    // import-qualified hit is an explicit reference the developer wrote an `import` for, while the
    // scan is a project-wide guess — and the ordered probe above is still the two halves in order,
    // so nothing about `ResolveExternalType` changes.
    //
    // The cache participates exactly as before: a hit caches under the FULL name, and a miss is
    // remembered only against the assembly count that proved it, so a namespace whose assembly loads
    // later is genuinely retried.
    func ResolveImportedExternalType(name: string): TypeInfo? {
        namespaceIndex := 0
        while namespaceIndex < usingNamespaces.Count {
            resolved := typeof(object)
            if TryResolveFullName(usingNamespaces[namespaceIndex] + "." + name, out resolved) {
                return new ReflectionTypeInfo(resolved)
            }

            namespaceIndex = namespaceIndex + 1
        }

        return null
    }

    // DOES THIS ONE NAMESPACE DECLARE THIS SPELLING — the single step both sweeps above are built
    // from, exposed so a caller that owns its own namespace ORDER and its own exclusions can take the
    // walk itself. `AnalyzerProjectTypeDiscovery` needs exactly that for NL209: it skips an import
    // that merely names a LEXICAL namespace (redundant, not a rival — `SimpleNamePrecedence` rules 1
    // and 2) and the namespace a source declaration already claimed, which is not something a single
    // `skipNamespace` argument can say.
    func ImportedNamespaceDeclares(namespaceName: string, name: string): bool {
        resolved := typeof(object)
        return TryResolveFullName(namespaceName + "." + name, out resolved)
    }

    // The EXACT probe: no using-namespace prefixing and no exported-name scan, so it answers only
    // for a fully-qualified spelling. Shares the same cache as the ordered probe, which is why an
    // exact hit here is visible to a later bare-name lookup and vice versa.
    func ResolveExactExternalType(fullName: string): Type? {
        resolved := typeof(object)
        if TryResolveFullName(fullName, out resolved) {
            return resolved
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

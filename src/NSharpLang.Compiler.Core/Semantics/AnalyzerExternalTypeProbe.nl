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
// THE PROBE ORDER IS BEHAVIOUR, NOT AN OPTIMISATION, and it is `SimpleNamePrecedence`'s:
//
//   1. the file's LEXICAL chain — its own namespace, each enclosing one outward, then the global
//      namespace, where the spelling is read as written — "<namespace>.<name>" resolved against every
//      loaded assembly in load order,
//   2. for each imported namespace IN IMPORT ORDER, "<namespace>.<name>" the same way,
//   3. the bare name as previously cached by step 4,
//   4. failing all of that, the first assembly (in load order) that EXPORTS a type whose simple name
//      or full name equals the spelling.
//
// Steps 1 and 2 are per FILE (its namespace and its imports) and are asked before the bare-name
// cache, so a guess step 4 made for one file never answers for another that has a nearer candidate.
// The full-name memo behind every step lives with the probe and the probe is never rebuilt, and the
// analyzer never clears it between `Analyze` calls: the assemblies it answers from outlive any
// single file.
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

    // THE SCAN'S GUESSES, kept apart from the full-name memo above. A full name answers the same in
    // every file; a scan hit (`TypeInfo` -> whichever assembly exported one first) is a guess that a
    // file's own chain or its imports must still be able to overrule, so it may not sit where a
    // full-name lookup of the same spelling would find it.
    scanCache: Dictionary<string, Type>

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

    // THE NAMESPACE THE FILE UNDER ANALYSIS DECLARES, for `SimpleNamePrecedence` rules 1 and 2. A
    // referenced assembly's type in that namespace, or in any enclosing one, is a member of the
    // file's own scope and outranks every import, exactly as a source declaration there does. Set per
    // analysis with the import list; null is the global namespace.
    currentNamespace: string?

    // The free-function holders each namespace was found to have, and the assembly count that found
    // them (`FreeFunctionHolders`).
    holdersByNamespace: Dictionary<string, List<Type>>
    holderCountsByNamespace: Dictionary<string, int>

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
        scanCache = new Dictionary<string, Type>(StringComparer.Ordinal)
        missedFullNames = new Dictionary<string, int>(StringComparer.Ordinal)
        grants = friendGrants
        currentNamespace = null
        holdersByNamespace = new Dictionary<string, List<Type>>(StringComparer.Ordinal)
        holderCountsByNamespace = new Dictionary<string, int>(StringComparer.Ordinal)
    }

    // One call per analysis: the file's namespace is the start of the lexical chain every bare
    // spelling below climbs before it asks an import.
    func BeginAnalysis(namespaceName: string?) {
        currentNamespace = namespaceName
    }

    // How many assemblies the probe answers from. The list only grows, so a caller that memoises an
    // answer keys it on this and is invalidated exactly when a new reference could change it.
    AssemblyCount: int => assemblies.Count

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

        for assemblyItem in assemblies {
            candidate := assemblyItem.GetType(fullName)
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
        for assembly in assemblies {
            declared: Type? = null
            try {
                declared = assembly.GetType(fullName)
            } catch {
                declared = null
            }

            if declared != null && !grants.IsNameableType(declared) {
                return true
            }
        }

        return false
    }

    // The ordered probe. A fresh ReflectionTypeInfo per call, exactly as the analyzer's own resolver
    // produced: callers compare these by TYPE identity, never by reference.
    //
    // THE LEXICAL CHAIN COMES FIRST (`SimpleNamePrecedence` rules 1 and 2): the file's own namespace
    // and each enclosing one declare their referenced-assembly types exactly as they declare their
    // source ones, so `TypeInfo` inside `NSharpLang.Compiler.Columnar` names
    // `NSharpLang.Compiler.TypeInfo` from a referenced assembly before `import System.Reflection` is
    // asked, and a qualified `Ast.Node` there names `NSharpLang.Compiler.Ast.Node`. Only then the
    // imports in order, and only after every import the bare-name cache and the exported-name scan —
    // the cache is filled by the SCAN, which answers the same for every file, so consulting it before
    // a file's own chain and imports would hand one file's guess to the next.
    func ResolveExternalType(name: string): TypeInfo? {
        if name == null || name.Length == 0 {
            return null
        }

        lexical := ResolveLexicalExternalType(name)
        if lexical != null {
            return lexical
        }

        imported := ResolveImportedExternalType(name)
        if imported != null {
            return imported
        }

        cachedType := typeof(object)
        if scanCache.TryGetValue(name, out cachedType) {
            return new ReflectionTypeInfo(cachedType)
        }

        for assembly in assemblies {
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
                    scanCache[name] = candidate
                    return new ReflectionTypeInfo(candidate)
                }
                exportedIndex = exportedIndex + 1
            }
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
        for usingNamespace in usingNamespaces {
            resolved := typeof(object)
            if TryResolveFullName(usingNamespace + "." + name, out resolved) {
                return new ReflectionTypeInfo(resolved)
            }
        }

        return null
    }

    // RULES 1 AND 2 ON THEIR OWN: the first namespace of the file's lexical chain — its own, then
    // each enclosing one, ending at the global namespace — whose referenced assemblies declare this
    // spelling. The global end is the spelling read as written, so an absolute full name resolves
    // here too.
    func ResolveLexicalExternalType(name: string): TypeInfo? {
        lexical := SimpleNamePrecedence.LexicalNamespaces(currentNamespace)
        for lexicalNamespace in lexical {
            resolved := ResolveInNamespace(lexicalNamespace, name)
            if resolved != null {
                return resolved
            }
        }

        return null
    }

    // DOES THIS ONE NAMESPACE DECLARE THIS SPELLING — the metadata answer `SimpleNamePrecedence`
    // asks of every candidate namespace, exposed so the walks that own the SOURCE answer can drive the
    // selection themselves. Null is the global namespace.
    func NamespaceDeclares(namespaceName: string?, name: string): bool {
        resolved := typeof(object)
        return TryResolveInNamespace(namespaceName, name, out resolved)
    }

    // A REFERENCED ASSEMBLY'S FREE FUNCTION OF THIS NAME IN THIS ONE NAMESPACE -- the metadata answer
    // the function channel asks of each candidate namespace, as the type channel asks
    // `NamespaceDeclares`. An N# assembly holds a namespace's free functions on `<namespace>.Program`,
    // or on `<namespace>.<Program>` where the namespace declares a type named `Program` itself (that
    // name is then the user's type), and a free function is one of the holder's PUBLIC static
    // methods: a camelCase one is emitted CLR `assembly` and is not exported.
    //
    // EVERY LOADED ASSEMBLY IS ASKED, not the first whose holder answers: two referenced assemblies may
    // each hold free functions of one namespace -- the global one above all -- and a first-wins answer
    // would hide the second one's functions entirely. The answer is the one method of that name across
    // all of them; two (one name held twice, in one holder or in two) are not one free function and
    // answer nothing, which is the emitter's answer too (`ColumnarFreeFunctionScope`). Empty when no
    // holder declares it.
    func NamespaceFreeFunctions(namespaceName: string?, name: string): List<MethodInfo> {
        functions := new List<MethodInfo>()
        if name == null || name.Length == 0 {
            return functions
        }

        holders := FreeFunctionHolders(namespaceName)
        if holders.Count == 0 {
            return functions
        }

        for holder in holders {
            for method in holder.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly) {
                if !method.IsSpecialName && method.Name == name {
                    functions.Add(method)
                }
            }
        }

        if functions.Count > 1 {
            functions.Clear()
        }

        return functions
    }

    // The holders `NamespaceFreeFunctions` reads, one per assembly that declares one, remembered
    // against the assembly count that found them -- the list only grows, so a new reference is
    // exactly what can add a holder.
    func FreeFunctionHolders(namespaceName: string?): List<Type> {
        key := namespaceName ?? ""
        cached: List<Type>? = null
        cachedCount := 0
        if holdersByNamespace.TryGetValue(key, out cached) && holderCountsByNamespace.TryGetValue(key, out cachedCount) && cachedCount == assemblies.Count {
            return cached
        }

        prefix := ""
        if key.Length > 0 {
            prefix = key + "."
        }
        holders := new List<Type>()
        for assemblyItem in assemblies {
            candidate := assemblyItem.GetType(prefix + "<Program>")
            if candidate == null {
                ordinary := assemblyItem.GetType(prefix + "Program")
                if ordinary != null && ordinary.IsClass {
                    candidate = ordinary
                }
            }
            if candidate != null && grants.IsNameableType(candidate) {
                holders.Add(candidate)
            }
        }

        holdersByNamespace[key] = holders
        holderCountsByNamespace[key] = assemblies.Count
        return holders
    }

    // The type that `NamespaceDeclares` found, or null.
    func ResolveInNamespace(namespaceName: string?, name: string): TypeInfo? {
        resolved := typeof(object)
        if TryResolveInNamespace(namespaceName, name, out resolved) {
            return new ReflectionTypeInfo(resolved)
        }

        return null
    }

    // The spelling as written inside the namespace, then with ITS OWN trailing dots read as nesting
    // one at a time — `Outer.Inner` is `Outer+Inner` in metadata. A dot of the namespace is never
    // read as nesting: a namespace is not a type. Every attempt shares the probe's one memo.
    func TryResolveInNamespace(namespaceName: string?, name: string, out resolved: Type): bool {
        resolved = typeof(object)
        if name == null || name.Length == 0 {
            return false
        }

        prefix := ""
        if namespaceName != null && namespaceName.Length > 0 {
            prefix = namespaceName + "."
        }

        if TryResolveFullName(prefix + name, out resolved) {
            return true
        }

        candidate := name
        searchEnd := candidate.Length
        while searchEnd > 0 {
            separator := candidate.LastIndexOf('.', searchEnd - 1)
            if separator <= 0 {
                return false
            }

            candidate = candidate.Substring(0, separator) + "+" + candidate.Substring(separator + 1)
            if TryResolveFullName(prefix + candidate, out resolved) {
                return true
            }

            searchEnd = separator
        }

        return false
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
                    if reflectionType.IsGenericTypeDefinition {
                        arities.Add(arity)
                    }
                }
            }
            arity = arity + 1
        }

        return arities
    }
}

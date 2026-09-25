namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import System.Runtime.Loader
import NSharpLang.Cli

enum ExternalAssemblyTypeLookupStatus {
    Missing,
    Found,
    Unknown
}

class ExternalAssemblyTypeResolution {
    Status: ExternalAssemblyTypeLookupStatus
    SemanticTypeIdentity: string
    RuntimeType: Type
    HasRuntimeType: bool

    constructor(status: ExternalAssemblyTypeLookupStatus, semanticTypeIdentity: string, runtimeType: Type, hasRuntimeType: bool) {
        Status = status
        SemanticTypeIdentity = semanticTypeIdentity
        RuntimeType = runtimeType
        HasRuntimeType = hasRuntimeType
    }
}

class ExternalAssemblyCatalogEntry {
    IdentityName: AssemblyName?
    Identity: string
    MetadataPath: string
    MetadataAssembly: Assembly?
    RuntimeAssembly: Assembly?
    IsInspectable: bool

    constructor(identityName: AssemblyName?, identity: string, metadataPath: string, runtimeAssembly: Assembly?, isInspectable: bool) {
        IdentityName = identityName
        Identity = identity
        MetadataPath = metadataPath
        MetadataAssembly = null
        RuntimeAssembly = runtimeAssembly
        IsInspectable = isInspectable
    }

    func AttachRuntimeAssembly(runtimeAssembly: Assembly?) {
        RuntimeAssembly = runtimeAssembly
    }

    func AttachMetadataAssembly(metadataAssembly: Assembly) {
        MetadataAssembly = metadataAssembly
    }

    func MarkUninspectable() {
        IsInspectable = false
        MetadataAssembly = null
    }
}

// THE COMPILER'S OWNED REFERENCE CONTEXT, and the one rule it adds to the default fallback.
//
// A reference loaded here resolves its OWN dependencies through this context, and an identity it does
// not carry falls back to the default context. Under the standalone CLI that is the compiler's own
// context, so nothing changes. Under MSBuild it is not: the build task runs in a context of its own, and
// the compilation's executable handles for the identities the COMPILER itself references come from
// THAT context (`PreferEmissionRuntimeAssemblies`, `IsCompilerBoundRuntimeAssembly`). A referenced
// assembly's member typed by one of those identities then named the DEFAULT context's build instead,
// so `scan.Context` -- a `MetadataLoadContext?` declared by a referenced N# assembly -- was a different
// `MetadataLoadContext` from the one the project names, and `F(scan.Context)` declined in the SDK build
// while the identical project built through `nlc build`. That is exactly the shape carving
// `Compiler.Model` out of Core creates.
//
// So a dependency whose identity the compiler assembly references is answered with the handle the
// COMPILER'S context binds for it -- the same handle the reference set is paired with -- and every
// other name keeps the default fallback. The compiler's own product assemblies are excluded by name
// (`CompilerBoundAssemblyForReferencedIdentity`): Core references Model and Syntax, so they ARE among
// the compiler's references, and a project's own build of them must still bind from its reference path.
//
// `Load` is only asked for a name this context does not ALREADY hold, so the rule is kept on the way in
// as well: `TryLoadExactIdentityAssembly` never loads a second file of a compiler-referenced identity
// into this context (see there), or that file -- not the compiler's handle -- would answer every
// dependency edge of every reference loaded here.
class ExactIdentityReferenceLoadContext: AssemblyLoadContext {
    constructor(): base("nsharp-exact-identity-references", false) {
    }

    protected override func Load(assemblyName: AssemblyName): Assembly? {
        // Null is the default fallback, exactly as for every name the compiler does not reference.
        return ExternalAssemblyScan.CompilerBoundAssemblyForReferencedIdentity(assemblyName.FullName)
    }
}

class ExternalAssemblyScanResult {
    Entries: ExternalAssemblyCatalogEntry[]
    Context: MetadataLoadContext?

    constructor(entries: ExternalAssemblyCatalogEntry[], context: MetadataLoadContext?) {
        Entries = entries
        Context = context
    }

    func Dispose() {
        if Context != null {
            Context.Dispose()
            Context = null
        }
    }
}

// Metadata determines binding; an exact runtime implementation only supplies the Reflection.Emit
// handle. The two identities must match byte-for-byte. Arbitrary AppDomain assemblies never enter
// semantic order, and a broken later slot cannot invalidate an earlier winner.
class ExternalAssemblyScan {

    // WHY THE COMPILER OWNS A LOAD CONTEXT OF ITS OWN.
    //
    // `Assembly.LoadFrom` binds into the DEFAULT load context, and the default context holds at
    // most one assembly per SIMPLE NAME. That is invisible under the standalone CLI, whose default
    // context carries nothing but the compiler. It is decisive when the compiler runs as an MSBuild
    // task: the .NET SDK directory ships `Microsoft.Extensions.Logging.Abstractions`,
    // `Microsoft.Extensions.DependencyInjection.Abstractions` and the rest of that family at the
    // SDK's own version, so `LoadFrom` of a project's 9.0.0 package FILE answers with the host's
    // 10.0.0 assembly. The identity does not match, the reference is correctly refused as an
    // executable handle, and the entry stays metadata-only -- so every signature naming one of its
    // types declines at `emit.declaration.field-type`, while the identical project builds through
    // `nlc build`. MEASURED: a field typed `ILogger` from the 9.0.0 package declines through the
    // SDK and emits through the CLI; the same field from the 10.0.0 package, whose identity is the
    // one the host already holds, emits through both.
    //
    // A context of the compiler's own gives the requested FILE an executable handle without
    // displacing the host's. Unresolved dependencies of an assembly loaded here still fall back to
    // the default context, so it keeps binding `System.Runtime` and friends exactly as before.
    private static readonly s_exactIdentityReferences: AssemblyLoadContext = new ExactIdentityReferenceLoadContext()

    static func ExactIdentityLoadContext(): AssemblyLoadContext {
        return s_exactIdentityReferences
    }

    // ── THE ONE OWNER OF "WHAT DOES THIS REFERENCE PATH LOAD" ────────────────────────────────────
    //
    // Every consumer in the compiler -- this scan, `ColumnarCompilerReferenceResolver`'s
    // reference-path walks, the AspNet route residual, the runtime member resolvers -- asks THIS
    // function, so a reference path can never mean two different runtime assemblies in one process.
    // A second `Assembly.LoadFrom` elsewhere is a second load CONTEXT, and types from two contexts
    // share their names and nothing else.
    //
    // THE RULE, AND WHY IT IS NOT "THE DEFAULT CONTEXT FIRST".
    //
    // A reference's own DEPENDENCIES are resolved by the context it was loaded into, and the two
    // contexts answer differently. `Assembly.LoadFrom` PLACES a new assembly in the default context,
    // and that split the project's reference closure in half under MSBuild, in the direction nobody
    // expects: a package whose simple name the host ALSO carries was refused by the default context
    // on identity, landed in the owned context, and resolved its dependencies out of the owned
    // context's own cache -- so it was CONSISTENT with the project. A package whose simple name the
    // host does NOT carry was TAKEN by the default context, and its dependencies then resolved out
    // of the default context, which serves the HOST's build of every shared name. MEASURED:
    // `ILoggingBuilder.SetMinimumLevel` (`Microsoft.Extensions.Logging`, a name MSBuild carries ->
    // owned) emitted through the SDK while `ILoggingBuilder.AddFile`
    // (`Serilog.Extensions.Logging.File`, a name MSBuild does not carry -> default) declined,
    // because `AddFile`'s `this` parameter was the HOST's `ILoggingBuilder` and the receiver was the
    // project's. An inferred lambda parameter for an external delegate is the same split one hop
    // later. Under the standalone CLI the default context carries nothing but the compiler, so every
    // reference was consistent and the same program built -- which is the whole of the parity gap.
    //
    // So: THE DEFAULT CONTEXT IS CONSULTED ONLY FOR AN IDENTITY IT ALREADY ANSWERS FOR, AND IS NEVER
    // ASKED TO TAKE THE PROJECT'S FILE. That is the same first question `Assembly.LoadFrom` asked --
    // a build the host already owns still wins when its identity is exactly the requested one, so
    // the framework, the compiler's own assemblies under the CLI, and every host dependency bind
    // exactly as before. What changes is the answer for a file the default context did NOT already
    // have: it goes into the ONE owned context rather than being placed in the default one, so the
    // rest of the project's closure resolves it out of that context's own cache.
    //
    // THE CONTEXT THE DEFAULT ONE IS **NOT** ALLOWED TO STAND IN FOR IS THE COMPILER'S OWN. Under
    // MSBuild the build task IS `NSharpLang.Compiler.Driver.dll`, loaded into MSBuild's task context,
    // and a project that references the compiler (`src/NSharpLang.Playground`,
    // `src/NSharpLang.TestHost`) has a DIFFERENT build of that same identity on its reference path.
    // Answering that path with the task's own assembly leaves the project's `Compiler.dll` -- which
    // the default context has never heard of, so it lands in the owned context -- with no
    // `NSharpLang.Compiler.Core` to bind at all, and the code generator fails with `Could not load
    // file or assembly 'NSharpLang.Compiler.Core'`. Asking the DEFAULT context, rather than every
    // context in the process, is what keeps the project's own build the answer for the project's own
    // reference path.
    //
    // AND A COMPILER-REFERENCED IDENTITY IS ANSWERED WITH THE COMPILER'S HANDLE, NEVER WITH A SECOND
    // COPY IN THE OWNED CONTEXT. Under MSBuild the default context answers for such an identity only
    // when the .NET SDK directory happens to ship EXACTLY the version the compiler references: the SDK
    // carries its own `System.Reflection.MetadataLoadContext`, 10.0.0.5 in SDK 10.0.105 but 10.0.0.3 in
    // 10.0.103 and 10.0.0.12 in 10.0.401, and the default binder rolls a 10.0.0.5 request forward to
    // the SDK's build. When it did not match, the project's `System.Reflection.MetadataLoadContext`
    // package file was loaded into the owned context -- and the owned context answers a dependency
    // edge from its own cache BEFORE `ExactIdentityReferenceLoadContext.Load` is ever asked, so
    // `Compiler.Model`'s `ExternalAssemblyScanResult.Context` named that copy while the project's own
    // `MetadataLoadContext` named the compiler's (the pairing below). Core's estate then declined
    // `AssignabilityWithWellKnownTypes(context)` on every Linux CI runner and passed on the one macOS
    // SDK whose version happened to agree.
    static func TryLoadExactIdentityAssembly(path: string, identity: string): Assembly? {
        carried := DefaultContextAssemblyForIdentity(identity)
        if carried != null {
            return carried
        }

        compilerBound := CompilerBoundAssemblyForReferencedIdentity(identity)
        if compilerBound != null {
            return compilerBound
        }

        try {
            owned := ExactIdentityLoadContext().LoadFromAssemblyPath(Path.GetFullPath(path))
            if RuntimeAssemblyHasIdentity(owned, identity) {
                return owned
            }
        } catch {
            // An image that will not load at all has no executable handle; stay metadata-only.
            return null
        }

        return null
    }

    // THE ONE QUESTION THE DEFAULT CONTEXT IS ASKED: "do you already answer for this exact
    // identity?". `LoadFromAssemblyName` is the same binder call `Assembly.LoadFrom` made before it
    // touched the file, so a name the host publishes still binds to the host's copy and a name it
    // does not publish raises rather than pulling the project's file in. The answer is accepted only
    // when the identity matches byte-for-byte AND the assembly really is the default context's, so a
    // host that rolls a request forward to a higher version is refused here exactly as it was.
    static func DefaultContextAssemblyForIdentity(identity: string): Assembly? {
        if identity == null || identity.Length == 0 {
            return null
        }

        try {
            bound := AssemblyLoadContext.Default.LoadFromAssemblyName(new AssemblyName(identity))
            if RuntimeAssemblyHasIdentity(bound, identity) && Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(bound), AssemblyLoadContext.Default) {
                return bound
            }
        } catch {
            // No build of this identity is the default context's to give; the owned context answers.
            return null
        }

        return null
    }

    // THE HOST'S OWN ASSEMBLIES, BY NAME RATHER THAN BY PATH, and the second of the two documented
    // routes into the default context. A framework reference pack and the test framework name a
    // runtime assembly the HOST supplies, not a file in the project's closure, so the default
    // context is the right owner for both -- but the call still lives here, so the compiler has one
    // place that loads an assembly and one place where the rule is written down.
    static func LoadHostAssemblyByName(name: string): Assembly {
        return Assembly.Load(name)
    }

    static func TryLoadHostAssemblyByName(name: AssemblyName): Assembly? {
        try {
            return Assembly.Load(name)
        } catch {

            // A name this host does not carry is not an executable handle; the caller's next
            // candidate is.
            return null
        }
    }

    // THE PROCESS'S ASSEMBLIES ACROSS EVERY CONTEXT, unfiltered and in load order, so the walks that
    // used to call `AppDomain.CurrentDomain.GetAssemblies()` for themselves now read the same
    // snapshot this owner does. Order and membership are deliberately identical to that call --
    // dynamic and collectible assemblies included -- because these walks answer type lookups and
    // dropping either would change which type a program binds.
    static func LoadedAcrossContexts(): Assembly[] {
        return AppDomain.CurrentDomain.GetAssemblies()
    }

    static func Loaded(): Assembly[] {
        assemblies := LoadedAcrossContexts()
        loaded := new List<Assembly>()
        for assembly in assemblies {
            if !assembly.IsDynamic && !assembly.IsCollectible {
                loaded.Add(assembly)
            }
        }

        return loaded.ToArray()
    }

    // The same snapshot `Loaded` returns, keyed by assembly full name in load order so an exact
    // identity is one hash lookup instead of a walk of every loaded assembly per reference path.
    // FIRST WINS, exactly as the walk's first match did; an assembly whose name cannot be read is
    // skipped, exactly as the walk's per-assembly catch skipped it.
    static func LoadedByIdentity(): Dictionary<string, Assembly> {
        byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
        assemblies := Loaded()
        for assembly in assemblies {
            try {
                identity := assembly.GetName().FullName
                if !byIdentity.ContainsKey(identity) {
                    byIdentity[identity] = assembly
                }
            } catch {
                // A hostile loaded assembly is not semantic evidence; keep indexing.
                continue
            }
        }

        return byIdentity
    }

    static func LoadedForEmissionByIdentity(): Dictionary<string, Assembly> {
        return PreferEmissionRuntimeAssemblies(LoadedByIdentity())
    }

    // Runtime handles must come from the compiler's own load context when that context already
    // carries the exact assembly identity. MSBuild can load the compiler and an ambient copy of the
    // same dependency from the same file into different contexts; those Type objects have identical
    // names but are not executable against each other. The metadata path and semantic entry order are
    // unchanged. An owned collectible context is deliberately eligible: its dependencies are the only
    // executable handles for that compiler instance, while unrelated collectible contexts stay absent.
    static func PreferEmissionRuntimeAssemblies(byIdentity: Dictionary<string, Assembly>): Dictionary<string, Assembly> {
        compilerContext := AssemblyLoadContext.GetLoadContext(typeof(ExternalAssemblyScan).Assembly)
        if compilerContext == null {
            return byIdentity
        }

        loaded := LoadedAcrossContexts()
        for candidate in loaded {
            if !candidate.IsDynamic && Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(candidate), compilerContext) {
                try {
                    identity := candidate.GetName().FullName
                    if !byIdentity.ContainsKey(identity) {
                        byIdentity[identity] = candidate
                    } else {
                        current := byIdentity[identity]
                        if !Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(current), compilerContext) {
                            byIdentity[identity] = candidate
                        }
                    }
                } catch {
                    // An assembly whose name cannot be read is skipped, as `LoadedByIdentity` skips it.
                    continue
                }
            }
        }

        return byIdentity
    }

    static func OpenWithReferences(referenceAssemblyPaths: IReadOnlyList<string>?): ExternalAssemblyScanResult {
        entries := new List<ExternalAssemblyCatalogEntry>()
        searchDirectories := CommonAssemblySearchDirectories(referenceAssemblyPaths)
        commonNames := CommonAssemblyNames()
        for name in commonNames {
            try {
                runtimeAssembly := LoadHostAssemblyByName(name)
                identityName := runtimeAssembly.GetName()
                identity := identityName.FullName
                metadataPath := CommonAssemblyMetadataPath(searchDirectories, name)
                AddSemanticEntry(entries, identityName, identity, metadataPath, runtimeAssembly)
            } catch {
                entries.Add(new ExternalAssemblyCatalogEntry(null, "unresolved-common:" + name, "", null, false))
            }
        }

        runtimeAssemblies := LoadedForEmissionByIdentity()
        if referenceAssemblyPaths != null {
            pathIndex := 0
            while pathIndex < referenceAssemblyPaths.Count {
                path := referenceAssemblyPaths[pathIndex]
                if path == null || path.Length == 0 {
                    entries.Add(new ExternalAssemblyCatalogEntry(null, "unresolved-path:" + pathIndex.ToString(), "", null, false))

                    pathIndex = pathIndex + 1
                    continue
                }

                identityName := TryReadAssemblyName(path)
                if identityName == null {
                    entries.Add(new ExternalAssemblyCatalogEntry(null, "unresolved-path:" + path, "", null, false))

                    pathIndex = pathIndex + 1
                    continue
                }

                identity := identityName.FullName
                existing := FindSemanticIdentity(entries, identityName)
                if existing >= 0 {
                    if entries[existing].Identity == identity && entries[existing].RuntimeAssembly == null {
                        exactRuntime := TryLoadExactRuntimeAssembly(runtimeAssemblies, path, identity)

                        entries[existing].AttachRuntimeAssembly(exactRuntime)
                    }

                    pathIndex = pathIndex + 1
                    continue
                }

                runtimeAssembly := TryLoadExactRuntimeAssembly(runtimeAssemblies, path, identity)

                AddSemanticEntry(entries, identityName, identity, path, runtimeAssembly)

                pathIndex = pathIndex + 1
            }
        }

        resolverPaths := new List<string>()
        resolverNames := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        entryIndex := 0
        while entryIndex < entries.Count {
            entry := entries[entryIndex]
            if entry.IsInspectable && entry.MetadataPath.Length > 0 {
                resolverPaths.Add(entry.MetadataPath)
                resolverNames.Add(Path.GetFileName(entry.MetadataPath))
            }

            entryIndex = entryIndex + 1
        }

        AddForwardTargetPaths(resolverPaths, resolverNames, searchDirectories)

        context := TryCreateMetadataLoadContext(resolverPaths.ToArray())
        if context == null {
            entryIndex = 0
            while entryIndex < entries.Count {
                entries[entryIndex].MarkUninspectable()
                entryIndex = entryIndex + 1
            }

            return new ExternalAssemblyScanResult(entries.ToArray(), null)
        }

        entryIndex = 0
        while entryIndex < entries.Count {
            entry := entries[entryIndex]
            if entry.IsInspectable {
                try {
                    metadataAssembly := context.LoadFromAssemblyPath(entry.MetadataPath)
                    entry.AttachMetadataAssembly(metadataAssembly)
                } catch {
                    entry.MarkUninspectable()
                }
            }

            entryIndex = entryIndex + 1
        }

        ReconcileRuntimeAssemblies(entries, runtimeAssemblies)

        return new ExternalAssemblyScanResult(entries.ToArray(), context)
    }

    // WHERE A COMMON ASSEMBLY'S METADATA IS, FOUND ON DISK RATHER THAN READ OFF A LOADED ASSEMBLY.
    // `runtimeAssembly.Location` answers the EMPTY STRING under a single-file binary -- measured,
    // not assumed -- and an entry with an empty metadata path is not inspectable, so the metadata
    // context would quietly be handed nothing and every common assembly would drop out of binding with
    // no error anywhere. The path is therefore resolved from DIRECTORIES.
    //
    // The runtime directory comes FIRST deliberately. It is the directory `Location` used to
    // answer out of, so for a framework-dependent host every one of the 27 common names resolves to the
    // byte-identical file the old reading returned, and the change moves nothing. The project's own
    // resolved reference directories come after, as the answer for a name the runtime directory does
    // not carry -- never as an override of one it does, because a reference-pack facade and a runtime
    // implementation of the same name do not carry the same types.
    static func CommonAssemblySearchDirectories(referenceAssemblyPaths: IReadOnlyList<string>?): string[] {
        directories := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
        if runtimeDirectory != null && runtimeDirectory.Length > 0 {
            AddUniquePath(directories, seen, runtimeDirectory)
        }

        if referenceAssemblyPaths != null {
            for path in referenceAssemblyPaths {
                if path != null && path.Length > 0 {
                    directory := Path.GetDirectoryName(path) ?? ""
                    if directory.Length > 0 {
                        AddUniquePath(directories, seen, directory)
                    }
                }
            }
        }

        return directories.ToArray()
    }

    // First directory that carries `<name>.dll` wins. An empty answer marks the entry uninspectable,
    // exactly as an empty `Location` did -- the difference is that it can now only happen when the file
    // is genuinely absent, not because the host is single-file.
    static func CommonAssemblyMetadataPath(searchDirectories: string[], name: string): string {
        fileName := name + ".dll"
        for searchDirectory in searchDirectories {
            candidate := Path.Combine(searchDirectory, fileName)
            if File.Exists(candidate) {
                return candidate
            }
        }

        return ""
    }

    // Existing project.yml DLL references can be relative to the project root. Selection and path
    // normalization live here in N#; MultiFileCompiler only routes the resulting ordered strings.
    static func ResolveReferencePaths(projectRoot: string, dependencies: IReadOnlyList<Reference>?): IReadOnlyList<string> {
        return CanonicalizeReferencePaths(ResolveConfiguredDllPaths(projectRoot, dependencies))
    }

    // Runtime copy-local selection is distinct from metadata selection. Normal DLLs copy
    // themselves; ref/refint inputs copy only an exact paired runtime implementation when one
    // exists. A metadata-only reference remains inspectable but is never deployed as executable IL.
    static func ResolveRuntimeAssetPaths(projectRoot: string, dependencies: IReadOnlyList<Reference>?): IReadOnlyList<string> {
        configuredPaths := ResolveConfiguredDllPaths(projectRoot, dependencies)
        runtimePaths := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for path in configuredPaths {
            runtimePath := GetRuntimePathCandidate(path)
            if runtimePath.Length > 0 {
                if IsExactAssemblyPair(path, runtimePath) {
                    AddUniquePath(runtimePaths, seen, runtimePath)
                }
            } else if File.Exists(path) {
                AddUniquePath(runtimePaths, seen, path)
            }
        }

        return runtimePaths
    }

    static func ResolveConfiguredDllPaths(projectRoot: string, dependencies: IReadOnlyList<Reference>?): List<string> {
        normalizedPaths := new List<string>()
        if dependencies == null {
            return normalizedPaths
        }

        normalizedProjectRoot := Path.GetFullPath(projectRoot)
        for dependency in dependencies {
            if dependency != null && dependency.Type == ReferenceType.Dll && !string.IsNullOrWhiteSpace(dependency.Dll ?? "") {
                path := dependency.Dll ?? ""
                if !Path.IsPathRooted(path) {
                    path = Path.Combine(normalizedProjectRoot, path)
                }

                normalizedPaths.Add(Path.GetFullPath(path))
            }
        }

        return normalizedPaths
    }

    // A restored package contributes a reference assembly for binding and a runtime assembly for
    // Reflection.Emit. The CLI resolver already supplies both. MSBuild's ReferencePath supplies
    // only the reference side, so recover the exact paired runtime path from standard NuGet and
    // project-output layouts. Reference metadata remains usable when no runtime pair exists.
    static func CanonicalizeReferencePaths(normalizedPaths: List<string>): IReadOnlyList<string> {
        paths := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        index := 0
        while index < normalizedPaths.Count {
            path := normalizedPaths[index]
            referencePath := FindReferencePathForRuntime(normalizedPaths, path)

            if referencePath.Length > 0 {
                AddUniquePath(paths, seen, referencePath)
                AddUniquePath(paths, seen, path)
                index = index + 1
                continue
            }

            AddUniquePath(paths, seen, path)
            runtimePath := GetRuntimePathCandidate(path)
            if runtimePath.Length > 0 && IsExactAssemblyPair(path, runtimePath) {
                AddUniquePath(paths, seen, runtimePath)
            }

            index = index + 1
        }

        return paths
    }

    static func FindReferencePathForRuntime(paths: List<string>, runtimePath: string): string {
        for referencePath in paths {
            candidate := GetRuntimePathCandidate(referencePath)
            if candidate.Length > 0 && string.Equals(candidate, runtimePath, StringComparison.OrdinalIgnoreCase) && IsExactAssemblyPair(referencePath, runtimePath) {
                return referencePath
            }
        }

        return ""
    }

    static func IsExactAssemblyPair(referencePath: string, runtimePath: string): bool {
        if !File.Exists(referencePath) || !File.Exists(runtimePath) {
            return false
        }

        try {
            referenceIdentity := AssemblyName.GetAssemblyName(referencePath).FullName
            runtimeIdentity := AssemblyName.GetAssemblyName(runtimePath).FullName
            return referenceIdentity != null && runtimeIdentity != null && string.Equals(referenceIdentity, runtimeIdentity, StringComparison.Ordinal)
        } catch {

            // Invalid or hostile images cannot establish an executable pairing.
            return false
        }
    }

    static func GetRuntimePathCandidate(referencePath: string): string {
        fileName := Path.GetFileName(referencePath)
        referenceDirectory := Path.GetDirectoryName(referencePath)
        if string.IsNullOrWhiteSpace(fileName) || string.IsNullOrWhiteSpace(referenceDirectory ?? "") {
            return ""
        }

        // MSBuild project references point at a ref/refint image below the project's obj/.
        projectRuntimePath := ProjectOutputRuntimePath(referencePath)
        if projectRuntimePath.Length > 0 {
            return projectRuntimePath
        }

        // NuGet compile/runtime pairs use <package>/<version>/ref/<tfm> and lib/<tfm>.
        targetFrameworkDirectory := referenceDirectory ?? ""
        referenceRoot := Path.GetDirectoryName(targetFrameworkDirectory)
        packageVersionDirectory := Path.GetDirectoryName(referenceRoot ?? "")
        if string.Equals(Path.GetFileName(referenceRoot ?? ""), "ref", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(packageVersionDirectory ?? "") {
            runtimeRoot := Path.Combine(packageVersionDirectory ?? "", "lib")
            runtimeDirectory := Path.Combine(runtimeRoot, Path.GetFileName(targetFrameworkDirectory))

            return Path.GetFullPath(Path.Combine(runtimeDirectory, fileName))
        }

        return ""
    }

    // An MSBuild project's reference image sits in a `ref` or `refint` directory below the
    // project's intermediate root, and its implementation sits at the SAME relative location below
    // the output root beside it. The intermediate root is the nearest `obj` ancestor, and at least a
    // configuration and a target framework separate it from the reference directory:
    //   obj/<configuration>/<tfm>/ref/A.dll                 -> bin/<configuration>/<tfm>/A.dll
    //   obj/<configuration>/<tfm>/<rid>/refint/A.dll        -> bin/<configuration>/<tfm>/<rid>/A.dll
    //   obj/tests-included/<configuration>/<tfm>/refint/A.dll -> bin/tests-included/<configuration>/<tfm>/A.dll
    // The last is the N# SDK's own tested-project layout: Sdk.props chooses `obj/tests-included/`
    // and `bin/tests-included/` under one condition. Counting a fixed three directories up to `obj`
    // knew only the first shape, so a tested project's own image paired with no implementation and
    // stayed metadata-only. Any other shape answers "" and pairs through the NuGet layout, if at all.
    static func ProjectOutputRuntimePath(referencePath: string): string {
        fileName := Path.GetFileName(referencePath)
        referenceDirectory := Path.GetDirectoryName(referencePath) ?? ""
        referenceDirectoryName := Path.GetFileName(referenceDirectory)
        if string.IsNullOrWhiteSpace(fileName) || (!string.Equals(referenceDirectoryName, "ref", StringComparison.OrdinalIgnoreCase) && !string.Equals(referenceDirectoryName, "refint", StringComparison.OrdinalIgnoreCase)) {
            return ""
        }

        segments := new List<string>()
        objectDirectory := Path.GetDirectoryName(referenceDirectory) ?? ""
        while objectDirectory.Length > 0 && !string.Equals(Path.GetFileName(objectDirectory), "obj", StringComparison.OrdinalIgnoreCase) {
            segments.Insert(0, Path.GetFileName(objectDirectory))
            objectDirectory = Path.GetDirectoryName(objectDirectory) ?? ""
        }

        if objectDirectory.Length == 0 || segments.Count < 2 {
            return ""
        }

        projectDirectory := Path.GetDirectoryName(objectDirectory) ?? ""
        if string.IsNullOrWhiteSpace(projectDirectory) {
            return ""
        }

        runtimeDirectory := Path.Combine(projectDirectory, "bin")
        for segment in segments {
            runtimeDirectory = Path.Combine(runtimeDirectory, segment)
        }

        return Path.GetFullPath(Path.Combine(runtimeDirectory, fileName))
    }

    static func AddUniquePath(paths: List<string>, seen: HashSet<string>, path: string) {
        if seen.Add(path) {
            paths.Add(path)
        }
    }

    static func ReconcileRuntimeAssemblies(entries: List<ExternalAssemblyCatalogEntry>, runtimeAssemblies: Dictionary<string, Assembly>) {
        for entry in entries {
            if entry != null && entry.IsInspectable && entry.MetadataAssembly != null {
                if !RuntimeAssemblyMatchesSelectedMetadata(entry) {
                    replacement := SelectRuntimeAssemblyForMetadata(runtimeAssemblies, entry.MetadataAssembly, entry.Identity, entry.MetadataPath)
                    entry.AttachRuntimeAssembly(replacement)
                }
            }
        }
    }

    static func RuntimeAssemblyMatchesSelectedMetadata(entry: ExternalAssemblyCatalogEntry): bool {
        runtimeAssembly := entry.RuntimeAssembly
        metadataAssembly := entry.MetadataAssembly
        if runtimeAssembly == null || metadataAssembly == null {
            return false
        }

        if !RuntimeAssemblyHasIdentity(runtimeAssembly, entry.Identity) {
            return false
        }

        // Project reference assemblies intentionally have a different module identity from their
        // bin companion. The selected project's exact output is the only executable handle allowed
        // for an obj/ref or obj/refint input. A same-AQN compiler dependency must not replace it.
        if IsProjectReferenceAssemblyPath(entry.MetadataPath) {
            runtimePath := GetRuntimePathCandidate(entry.MetadataPath)
            if runtimePath.Length == 0 || !File.Exists(runtimePath) {
                return false
            }

            return RuntimeAssemblyPathMatches(runtimeAssembly, runtimePath)
        }

        // Framework packs and NuGet compile assets are metadata images. The implementation the
        // compiler binds for that identity may already be loaded from a different path (the
        // compiler running as an MSBuild task, against MSBuild's own `Microsoft.Build.*`, is the
        // important example), so the handle the compiler's binder answers with is executable when
        // the path-shaped runtime contract is present even if the physical paths differ. Foreign
        // same-AQN handles remain ineligible and reference-only inputs stay metadata-only when no
        // usable contract exists.
        if IsHostDependencyReferencePath(entry.MetadataPath) {
            if !HasUsableRuntimeContract(entry.MetadataPath) {
                return false
            }

            runtimePath := RuntimePathForReferenceContract(entry.MetadataPath)
            if RuntimeAssemblyPathMatches(runtimeAssembly, runtimePath) {
                return true
            }

            return CompilerAssemblyReferencesIdentity(entry.Identity) && IsCompilerBoundRuntimeAssembly(runtimeAssembly, entry.Identity)
        }

        runtimeModuleVersionId := RuntimeAssemblyModuleVersionId(runtimeAssembly)
        metadataModuleVersionId := RuntimeAssemblyModuleVersionId(metadataAssembly)
        return runtimeModuleVersionId.Length > 0 && runtimeModuleVersionId == metadataModuleVersionId
    }

    static func SelectRuntimeAssemblyForMetadata(runtimeAssemblies: Dictionary<string, Assembly>, metadataAssembly: Assembly, identity: string, metadataPath: string): Assembly? {
        if metadataAssembly == null || identity == null || identity.Length == 0 {
            return null
        }

        // A framework-pack reference is never executable. Resolve its implementation from the
        // selected shared framework directory before considering the generic ref/lib pairing rules.
        // The helper validates the full assembly identity, so a same-name framework image cannot
        // leak into emission.
        if IsFrameworkPackReferencePath(metadataPath) {
            frameworkRuntime := TryLoadFrameworkRuntimeAssembly(runtimeAssemblies, metadataPath, identity)
            if frameworkRuntime != null {
                return frameworkRuntime
            }
        }

        candidates := new List<Assembly>()
        if runtimeAssemblies != null && runtimeAssemblies.ContainsKey(identity) {
            candidates.Add(runtimeAssemblies[identity])
        }

        loaded := Loaded()
        for candidate in loaded {
            if candidate != null && !ContainsAssemblyReference(candidates, candidate) {
                candidates.Add(candidate)
            }
        }

        return SelectRuntimeAssemblyByMetadata(candidates, metadataAssembly, identity, metadataPath)
    }

    static func SelectRuntimeAssemblyByMetadata(candidates: IReadOnlyList<Assembly>, metadataAssembly: Assembly, identity: string, metadataPath: string): Assembly? {
        if candidates == null || metadataAssembly == null || identity == null || identity.Length == 0 {
            return null
        }

        pairedRuntimePath := GetRuntimePathCandidate(metadataPath)
        index := 0
        if IsProjectReferenceAssemblyPath(metadataPath) {
            if pairedRuntimePath.Length == 0 || !File.Exists(pairedRuntimePath) {
                return null
            }

            index = 0
            while index < candidates.Count {
                candidate := candidates[index]
                if RuntimeAssemblyHasIdentity(candidate, identity) && RuntimeAssemblyPathMatches(candidate, pairedRuntimePath) {
                    return candidate
                }

                index = index + 1
            }

            return null
        }

        // NuGet/framework reference contracts may have no matching loaded path in the host process.
        // Preserve the exact-AQN dependency the compiler's own binder answers with in that case;
        // arbitrary loaded assemblies and project ref/refint paths never enter this branch.
        if IsHostDependencyReferencePath(metadataPath) {
            runtimePath := RuntimePathForReferenceContract(metadataPath)
            index = 0
            while index < candidates.Count {
                candidate := candidates[index]
                if RuntimeAssemblyHasIdentity(candidate, identity) && RuntimeAssemblyPathMatches(candidate, runtimePath) {
                    return candidate
                }

                index = index + 1
            }

            if !CompilerAssemblyReferencesIdentity(identity) || !HasUsableRuntimeContract(metadataPath) {
                return null
            }

            index = 0
            while index < candidates.Count {
                candidate := candidates[index]
                if IsCompilerBoundRuntimeAssembly(candidate, identity) {
                    return candidate
                }

                index = index + 1
            }

            return null
        }

        metadataModuleVersionId := RuntimeAssemblyModuleVersionId(metadataAssembly)
        if metadataModuleVersionId.Length > 0 {

            // A matching path is stronger than load order when two builds carry the same CLR identity.
            index = 0
            while index < candidates.Count {
                candidate := candidates[index]
                if RuntimeAssemblyHasIdentity(candidate, identity) && RuntimeAssemblyModuleVersionId(candidate) == metadataModuleVersionId && RuntimeAssemblyPathMatches(candidate, metadataPath) {
                    return candidate
                }

                index = index + 1
            }

            index = 0
            while index < candidates.Count {
                candidate := candidates[index]
                if RuntimeAssemblyHasIdentity(candidate, identity) && RuntimeAssemblyModuleVersionId(candidate) == metadataModuleVersionId {
                    return candidate
                }

                index = index + 1
            }
        }

        // THE HOST'S OWN COPY OF THE SAME IDENTITY, WHICH IS THE ONLY HANDLE THERE CAN BE. A module
        // identity separates two BUILDS that share a CLR identity, and it is the right tie-break
        // while several candidates are in play. It is the wrong REQUIREMENT: a process cannot hold
        // two assemblies of one identity in one load context, so when the compiler's own context
        // already binds this identity from a file of its own -- the SDK's copy of a package the
        // project also restored, which is ordinary whenever the compiler runs inside MSBuild -- that
        // handle is the only executable implementation the contract can ever have, and refusing it
        // leaves the reference with no runtime types rather than with a better one. Project
        // reference contracts return above and never reach this; a same-identity build sitting in
        // some unrelated context is still refused, because the binder must answer with it.
        index = 0
        while index < candidates.Count {
            candidate := candidates[index]
            if IsCompilerBoundRuntimeAssembly(candidate, identity) {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    static func ContainsAssemblyReference(assemblies: List<Assembly>, candidate: Assembly): bool {
        for assembly in assemblies {
            if Object.ReferenceEquals(assembly, candidate) {
                return true
            }
        }

        return false
    }

    static func RuntimeAssemblyHasIdentity(assembly: Assembly?, identity: string): bool {
        if assembly == null || identity == null || identity.Length == 0 {
            return false
        }

        try {
            return assembly.GetName().FullName == identity
        } catch {
            return false
        }
    }

    static func RuntimeAssemblyPathMatches(assembly: Assembly?, path: string): bool {
        if assembly == null || path == null || path.Length == 0 || !File.Exists(path) {
            return false
        }

        try {
            location := assembly.Location
            return location != null && location.Length > 0 && string.Equals(Path.GetFullPath(location), Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase)
        } catch {
            return false
        }
    }

    static func RuntimeAssemblyModuleVersionId(assembly: Assembly?): string {
        if assembly == null {
            return ""
        }

        try {
            return assembly.ManifestModule.ModuleVersionId.ToString()
        } catch {
            return ""
        }
    }

    // THE "SAME BYTES, KEEP WHAT THE HOST ALREADY HAS" SHORTCUT MAY NOT STAND IN FOR THE COMPILER
    // ITSELF.
    //
    // Two builds of one unchanged source now carry the same module version id -- that is what
    // `ColumnarDeterministicPeIdentity` is for -- so the seed's `tools/NSharpLang.Compiler.Core.dll`
    // and the copy on a project's reference path became byte-identical, and the two module-version-id
    // shortcuts below began answering a project's reference path with the HOST's build of the
    // compiler. Under MSBuild the host's build is the TASK's, in MSBuild's plugin context, while the
    // rest of that project's closure lands in the owned context -- which is exactly the split
    // `TryLoadExactIdentityAssembly` is written about, and the sentence it ends with: the context the
    // host is NOT allowed to stand in for is the compiler's own. `NSharpLang.TestHost`,
    // `LanguageServer` and `NSharpLang.Playground` all began declining calls into the compiler they
    // reference, and only a republished seed could see it.
    //
    // The compiler's assemblies are named rather than inferred, deliberately: every OTHER identity
    // the host carries -- `YamlDotNet`, `Mono.Cecil`, `Microsoft.Build.*` -- is the same FILE the
    // project resolves, and for those the shortcut is not an optimization but the thing that keeps
    // one identity from being loaded into two contexts. Only the compiler ships a second, separately
    // built copy of itself -- of every slice of itself.
    static func IsCompilerProductAssembly(assembly: Assembly?): bool {
        if assembly == null {
            return false
        }

        try {
            name := assembly.GetName().Name ?? ""
            return IsCompilerSliceAssemblyName(name) || name == "Compiler"
        } catch {
            return false
        }
    }

    // THE COMPILER IS SEVERAL ASSEMBLIES. Compiler.Core is being carved into slice projects, lowest
    // first, and each slice is a separately built assembly of the one compiler: this one
    // (`NSharpLang.Compiler.Model`), `NSharpLang.Compiler.Syntax` above it, Core above both,
    // `NSharpLang.Compiler.CodeIntel` -- completion, navigation, code fixes, DocQuery and the Linter
    // -- above Core, `NSharpLang.Compiler.Tooling` -- the formatter and the JSON output models --
    // above CodeIntel, and
    // `NSharpLang.Compiler.Driver` -- the command kernels, MultiFileCompiler and the SDK's MSBuild
    // tasks -- on top. `Compiler` is the facade over them, not a slice.
    static func CompilerSliceAssemblyNames(): string[] {
        return ["NSharpLang.Compiler.Model", "NSharpLang.Compiler.Syntax", "NSharpLang.Compiler.Core", "NSharpLang.Compiler.CodeIntel", "NSharpLang.Compiler.Tooling", "NSharpLang.Compiler.Driver"]
    }

    static func IsCompilerSliceAssemblyName(name: string): bool {
        for slice in CompilerSliceAssemblyNames() {
            if name == slice {
                return true
            }
        }

        return false
    }

    // Every slice of the compiler this copy of it runs beside: this assembly, and each other slice the
    // compiler's own load context carries. A slice is loaded as soon as any of its code has run, and
    // the code that asks the questions below is Core's, so under the CLI (the default context),
    // MSBuild (the task's plugin context) and a test host alike the answer is the whole compiler.
    static func CompilerSliceAssemblies(): List<Assembly> {
        own := typeof(ExternalAssemblyScan).Assembly
        slices := new List<Assembly>()
        slices.Add(own)
        context := CompilerLoadContext()
        if context == null {
            return slices
        }

        for candidate in context.Assemblies {
            if candidate.IsDynamic || Object.ReferenceEquals(candidate, own) {
                continue
            }

            try {
                if IsCompilerSliceAssemblyName(candidate.GetName().Name ?? "") {
                    slices.Add(candidate)
                }
            } catch {
                // An assembly whose name cannot be read is not one of the compiler's slices.
                continue
            }
        }

        return slices
    }

    static func IsReferenceAssemblyPath(path: string): bool {
        if path == null || path.Length == 0 {
            return false
        }

        directory := Path.GetDirectoryName(path)
        directoryName := Path.GetFileName(directory ?? "")
        if string.Equals(directoryName, "ref", StringComparison.OrdinalIgnoreCase) || string.Equals(directoryName, "refint", StringComparison.OrdinalIgnoreCase) {
            return true
        }

        // NuGet compile assets use <package>/<version>/ref/<tfm>/Assembly.dll; the immediate
        // parent is the target framework, while the project ref/refint layout above places the
        // image directly in the ref directory.
        referenceRoot := Path.GetDirectoryName(directory ?? "")
        referenceRootName := Path.GetFileName(referenceRoot ?? "")
        return string.Equals(referenceRootName, "ref", StringComparison.OrdinalIgnoreCase) || string.Equals(referenceRootName, "refint", StringComparison.OrdinalIgnoreCase)
    }

    static func IsProjectReferenceAssemblyPath(path: string): bool {
        if path == null || path.Length == 0 {
            return false
        }

        return ProjectOutputRuntimePath(path).Length > 0
    }

    static func IsFrameworkPackReferencePath(path: string): bool {
        if path == null || path.Length == 0 {
            return false
        }

        targetFrameworkDirectory := Path.GetDirectoryName(path)
        referenceRoot := Path.GetDirectoryName(targetFrameworkDirectory ?? "")
        versionDirectory := Path.GetDirectoryName(referenceRoot ?? "")
        packDirectory := Path.GetDirectoryName(versionDirectory ?? "")
        packsDirectory := Path.GetDirectoryName(packDirectory ?? "")
        packName := Path.GetFileName(packDirectory ?? "")
        return string.Equals(Path.GetFileName(referenceRoot ?? ""), "ref", StringComparison.OrdinalIgnoreCase) && string.Equals(Path.GetFileName(packsDirectory ?? ""), "packs", StringComparison.OrdinalIgnoreCase) && packName.Length > 4 && string.Equals(packName.Substring(packName.Length - 4), ".Ref", StringComparison.OrdinalIgnoreCase)
    }

    // WHETHER AN ASSEMBLY IS ONE A .NET INSTALLATION SHIPS: a shared-framework implementation
    // (`<dotnet>/shared/<framework>/<version>/X.dll`) or a targeting-pack reference image
    // (`<dotnet>/packs/<framework>.Ref/<version>/ref/<tfm>/X.dll`). Read from where the assembly was
    // loaded, because both the runtime handles the compiler holds and the metadata the scan loads
    // answer `Location` with the file they came from. An assembly with no file (in-memory, dynamic)
    // answers yes: nothing says it is a program's own, and the caller keeps its framework behaviour.
    //
    // The analyzer asks it for exactly one rule: reference nullability the framework's metadata
    // states for a CLASS type is not enforced (it never was), while the same metadata from any other
    // referenced assembly -- an N# library a program was split into, above all -- is enforced exactly
    // as the same declaration would be in source.
    static func IsSharedFrameworkAssembly(assembly: Assembly?): bool {
        if assembly == null {
            return true
        }

        location := ""
        try {
            if assembly.IsDynamic {
                return true
            }
            location = assembly.Location
        } catch {
            return true
        }

        if location == null || location.Length == 0 {
            return true
        }

        if IsFrameworkPackReferencePath(location) {
            return true
        }

        versionDirectory := Path.GetDirectoryName(Path.GetFullPath(location)) ?? ""
        frameworkDirectory := Path.GetDirectoryName(versionDirectory) ?? ""
        sharedDirectory := Path.GetDirectoryName(frameworkDirectory) ?? ""
        return string.Equals(Path.GetFileName(sharedDirectory), "shared", StringComparison.OrdinalIgnoreCase) && Path.GetFileName(frameworkDirectory).StartsWith("Microsoft.", StringComparison.Ordinal)
    }

    static func IsHostDependencyReferencePath(path: string): bool {
        if !IsReferenceAssemblyPath(path) || IsProjectReferenceAssemblyPath(path) {
            return false
        }

        return IsFrameworkPackReferencePath(path) || GetRuntimePathCandidate(path).Length > 0
    }

    static func HasUsableRuntimeContract(path: string): bool {
        runtimePath := RuntimePathForReferenceContract(path)
        return runtimePath.Length > 0 && IsExactAssemblyPair(path, runtimePath)
    }

    static func RuntimePathForReferenceContract(path: string): string {
        if IsFrameworkPackReferencePath(path) {
            return FrameworkRuntimePathForReference(path)
        }

        return GetRuntimePathCandidate(path)
    }

    // Whether the COMPILER references an identity: any of its slices, not just the one this code is
    // compiled into. Model alone references neither `Microsoft.Build.Framework` nor `Mono.Cecil`;
    // the compiler does, through Core, and a host-dependency reference the compiler binds must keep
    // pairing with the host's handle whichever slice declares the edge.
    static func CompilerAssemblyReferencesIdentity(identity: string): bool {
        if identity == null || identity.Length == 0 {
            return false
        }

        for slice in CompilerSliceAssemblies() {
            for reference in slice.GetReferencedAssemblies() {
                if reference.FullName == identity {
                    return true
                }
            }
        }

        return false
    }

    static func CompilerLoadContext(): AssemblyLoadContext? {
        return AssemblyLoadContext.GetLoadContext(typeof(ExternalAssemblyScan).Assembly)
    }

    // THE ONE RULE FOR "WHICH HANDLE ANSWERS AN IDENTITY THE COMPILER REFERENCES", asked both when a
    // reference path is loaded (`TryLoadExactIdentityAssembly`) and when a reference loaded into the
    // owned context resolves a dependency (`ExactIdentityReferenceLoadContext.Load`), so the two can
    // never pick different builds of one identity. The answer is the handle the compiler's own context
    // binds, and only when that binding is EXACTLY the identity -- a context that rolls the request
    // forward to another version is not an answer. The compiler's own product assemblies are never
    // answered here: a project that references the compiler (or is one of its slices) carries its OWN
    // build of them, and that build is the one its reference path means.
    static func CompilerBoundAssemblyForReferencedIdentity(identity: string): Assembly? {
        if identity == null || identity.Length == 0 {
            return null
        }

        simpleName := ""
        try {
            simpleName = new AssemblyName(identity).Name ?? ""
        } catch {
            return null
        }

        if IsCompilerSliceAssemblyName(simpleName) || simpleName == "Compiler" || !CompilerAssemblyReferencesIdentity(identity) {
            return null
        }

        compilerContext := CompilerLoadContext()
        if compilerContext == null {
            return null
        }

        try {
            bound := compilerContext.LoadFromAssemblyName(new AssemblyName(identity))
            if RuntimeAssemblyHasIdentity(bound, identity) {
                return bound
            }
        } catch {
            // The compiler's context cannot bind it after all; the caller's next route answers.
            return null
        }

        return null
    }

    // WHICH HANDLE A LOAD CONTEXT EXECUTES AGAINST FOR AN IDENTITY -- asked of the binder rather
    // than answered by comparing load-context objects. Owning the assembly is only ONE of the ways
    // a context supplies it: a context that does not carry a name delegates the load, so the exact
    // handle a context binds can legitimately live in the context it defers to.
    //
    // That is not an exotic case, it is how the compiler runs inside MSBuild. MSBuild loads the
    // build task and this library into a load context of its own and keeps its own
    // `Microsoft.Build.*` implementation in the context that one defers to, so a context-OBJECT
    // comparison calls the host's implementation foreign, leaves the package reference contract for
    // it with no executable implementation, and the field type `ITaskItem[]` resolves to nothing --
    // which is exactly what stopped the compiler rebuilding itself.
    //
    // The question stays exact in both directions: the binder must answer with THIS assembly, so a
    // same-identity build loaded into an unrelated context is still refused, and an identity the
    // context cannot bind at all answers no.
    static func IsContextBoundRuntimeAssembly(context: AssemblyLoadContext?, assembly: Assembly?, identity: string): bool {
        if context == null || assembly == null || !RuntimeAssemblyHasIdentity(assembly, identity) {
            return false
        }

        if Object.ReferenceEquals(AssemblyLoadContext.GetLoadContext(assembly), context) {
            return true
        }

        try {
            bound := context.LoadFromAssemblyName(new AssemblyName(identity))
            return Object.ReferenceEquals(bound, assembly)
        } catch {

            // A name this context cannot bind is not an executable implementation for it.
            return false
        }
    }

    static func IsCompilerBoundRuntimeAssembly(assembly: Assembly?, identity: string): bool {
        return IsContextBoundRuntimeAssembly(CompilerLoadContext(), assembly, identity)
    }

    // Framework reference packs do not have NuGet's lib/<tfm> sibling. The implementation is in
    // the matching shared framework directory selected by the same TFM/version policy as ordinary
    // framework resolution. This path is only used for the executable handle; MetadataLoadContext
    // continues to read the original reference image.
    static func FrameworkRuntimePathForReference(referencePath: string): string {
        if !IsFrameworkPackReferencePath(referencePath) {
            return ""
        }

        targetFrameworkDirectory := Path.GetDirectoryName(referencePath)
        referenceRoot := Path.GetDirectoryName(targetFrameworkDirectory ?? "")
        versionDirectory := Path.GetDirectoryName(referenceRoot ?? "")
        packDirectory := Path.GetDirectoryName(versionDirectory ?? "")
        packsDirectory := Path.GetDirectoryName(packDirectory ?? "")
        dotnetRoot := Path.GetDirectoryName(packsDirectory ?? "")
        packName := Path.GetFileName(packDirectory ?? "")
        targetFramework := Path.GetFileName(targetFrameworkDirectory ?? "")
        if dotnetRoot == null || packName.Length <= 4 || targetFramework == null || targetFramework.Length == 0 {
            return ""
        }

        frameworkName := packName.Substring(0, packName.Length - 4)
        sharedRoots := CompilationReferenceResolverKernels.GetDotnetSharedRootCandidates(RuntimeEnvironment.GetRuntimeDirectory())
        for sharedRoot in sharedRoots {
            frameworkRoot := CompilationReferenceResolverKernels.GetSharedFrameworkRoot(sharedRoot, frameworkName)
            if Directory.Exists(frameworkRoot) {
                selectedDirectory := CompilationReferenceResolverKernels.SelectSharedFrameworkDirectory(Directory.GetDirectories(frameworkRoot), targetFramework)
                if selectedDirectory != null {
                    candidate := Path.Combine(selectedDirectory, Path.GetFileName(referencePath))
                    if File.Exists(candidate) {
                        return Path.GetFullPath(candidate)
                    }
                }
            }
        }

        return ""
    }

    static func TryLoadFrameworkRuntimeAssembly(runtimeAssemblies: Dictionary<string, Assembly>, referencePath: string, identity: string): Assembly? {
        runtimePath := FrameworkRuntimePathForReference(referencePath)
        if runtimePath.Length == 0 {
            return null
        }

        loadedAssemblies := Loaded()
        for loaded in loadedAssemblies {
            if RuntimeAssemblyHasIdentity(loaded, identity) && RuntimeAssemblyPathMatches(loaded, runtimePath) {
                return loaded
            }
        }

        if runtimeAssemblies != null && runtimeAssemblies.ContainsKey(identity) {
            selected := runtimeAssemblies[identity]
            if CompilerAssemblyReferencesIdentity(identity) && IsCompilerBoundRuntimeAssembly(selected, identity) && HasUsableRuntimeContract(referencePath) {
                return selected
            }
        }

        // THE THIRD AND LAST DOCUMENTED ROUTE INTO THE DEFAULT CONTEXT, and the narrowest: a
        // SHARED-FRAMEWORK implementation file selected by framework resolution, never a file from
        // the project's own package closure. The framework is the one closure the host and the
        // project always agree about -- `FrameworkRuntimePathForReference` only answers for a
        // `packs/*.Ref` reference image, and the answer is the matching `shared/<pack>/<version>`
        // file the host itself binds -- so placing it in the default context cannot give a project
        // reference the host's build of anything.
        try {
            runtimeAssembly := Assembly.LoadFrom(runtimePath)
            if RuntimeAssemblyHasIdentity(runtimeAssembly, identity) {
                return runtimeAssembly
            }
        } catch {
            // A framework file that will not load has no executable handle to offer.
            return null
        }

        return null
    }

    static func FindExactType(scan: ExternalAssemblyScanResult, fullName: string): ExternalAssemblyTypeResolution {
        if scan == null || scan.Entries == null || fullName == null || fullName.Length == 0 {
            return UnknownResolution()
        }

        for entry in scan.Entries {
            if entry == null || !entry.IsInspectable || entry.MetadataAssembly == null {
                return UnknownResolution()
            }

            try {
                candidate := entry.MetadataAssembly.GetType(fullName)
                if candidate != null {
                    return FoundResolution(entry, candidate)
                }
            } catch {
                return UnknownResolution()
            }
        }

        return MissingResolution()
    }

    static func FindExactOrNestedType(scan: ExternalAssemblyScanResult, fullName: string): ExternalAssemblyTypeResolution {
        resolution := FindExactType(scan, fullName)
        if resolution.Status != ExternalAssemblyTypeLookupStatus.Missing {
            return resolution
        }

        candidate := fullName
        searchEnd := candidate.Length
        while searchEnd > 0 {
            separator := -1
            index := searchEnd - 1
            while index >= 0 {
                if candidate[index] == '.' {
                    separator = index
                    index = -1
                } else {
                    index = index - 1
                }
            }

            if separator <= 0 {
                return MissingResolution()
            }

            candidate = candidate.Substring(0, separator) + "+" + candidate.Substring(separator + 1)
            resolution = FindExactType(scan, candidate)
            if resolution.Status != ExternalAssemblyTypeLookupStatus.Missing {
                return resolution
            }

            searchEnd = separator
        }

        return MissingResolution()
    }

    static func FindFirstVisibleType(scan: ExternalAssemblyScanResult, name: string): ExternalAssemblyTypeResolution {
        if scan == null || scan.Entries == null || name == null || name.Length == 0 {
            return UnknownResolution()
        }

        for entry in scan.Entries {
            if entry == null || !entry.IsInspectable || entry.MetadataAssembly == null {
                return UnknownResolution()
            }

            try {
                types := entry.MetadataAssembly.GetExportedTypes()
                typeIndex := 0
                while typeIndex < types.Length {
                    candidate := types[typeIndex]
                    if candidate == null {
                        return UnknownResolution()
                    }

                    if candidate.Name == name || candidate.FullName == name {
                        return FoundResolution(entry, candidate)
                    }

                    typeIndex = typeIndex + 1
                }
            } catch {
                return UnknownResolution()
            }
        }

        return MissingResolution()
    }

    static func HasExactTypeIdentity(candidate: Type, identity: string): bool {
        if candidate == null || identity == null || identity.Length == 0 {
            return false
        }

        actual := candidate.AssemblyQualifiedName
        return actual != null && (actual == identity || actual.StartsWith(identity + ",", StringComparison.Ordinal))
    }

    static func SemanticIdentityMatches(semanticIdentity: string, plannedIdentity: string): bool {
        return semanticIdentity != null && plannedIdentity != null && (semanticIdentity == plannedIdentity || semanticIdentity.StartsWith(plannedIdentity + ",", StringComparison.Ordinal))
    }

    static func FoundResolution(entry: ExternalAssemblyCatalogEntry, metadataType: Type): ExternalAssemblyTypeResolution {
        identity := metadataType.AssemblyQualifiedName
        fullName := metadataType.FullName
        if identity == null || fullName == null || identity.Length == 0 || fullName.Length == 0 {
            return UnknownResolution()
        }

        runtimeType := typeof(object)
        hasRuntimeType := false
        if entry.RuntimeAssembly != null {
            candidate := ExactRuntimeType(entry.RuntimeAssembly, fullName, identity)
            if candidate != null {
                runtimeType = candidate
                hasRuntimeType = true
            }
        }

        return new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Found, identity, runtimeType, hasRuntimeType)
    }

    // The runtime type that carries exactly the metadata identity, or null. A hostile runtime
    // assembly cannot replace the exact metadata identity: one that throws on the lookup offers none.
    static func ExactRuntimeType(runtimeAssembly: Assembly, fullName: string, identity: string): Type? {
        try {
            candidate := runtimeAssembly.GetType(fullName)
            if candidate != null && candidate.AssemblyQualifiedName == identity {
                return candidate
            }
        } catch {
            return null
        }

        return null
    }

    static func MissingResolution(): ExternalAssemblyTypeResolution {
        return new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Missing, "", typeof(object), false)
    }

    static func UnknownResolution(): ExternalAssemblyTypeResolution {
        return new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    }

    static func AddSemanticEntry(entries: List<ExternalAssemblyCatalogEntry>, identityName: AssemblyName, identity: string, metadataPath: string, runtimeAssembly: Assembly?) {
        if FindSemanticIdentity(entries, identityName) >= 0 {
            return
        }

        entries.Add(new ExternalAssemblyCatalogEntry(identityName, identity, metadataPath, runtimeAssembly, metadataPath.Length > 0))
    }

    static func FindSemanticIdentity(entries: List<ExternalAssemblyCatalogEntry>, identityName: AssemblyName): int {
        index := 0
        while index < entries.Count {
            existing := entries[index].IdentityName
            if existing != null && AssemblyName.ReferenceMatchesDefinition(existing, identityName) {
                return index
            }

            index = index + 1
        }

        return -1
    }

    static func TryLoadExactRuntimeAssembly(runtimeAssemblies: Dictionary<string, Assembly>, path: string, identity: string): Assembly? {
        if runtimeAssemblies.ContainsKey(identity) {
            selected := runtimeAssemblies[identity]
            if !RuntimeAssemblyHasIdentity(selected, identity) {
                return null
            }

            if path == null || path.Length == 0 || RuntimeAssemblyPathMatches(selected, path) {
                return selected
            }

            if !File.Exists(path) {
                if IsProjectReferenceAssemblyPath(path) {
                    return null
                }

                return selected
            }

            selectedModuleVersionId := RuntimeAssemblyModuleVersionId(selected)
            loadedAssemblies := Loaded()
            for loaded in loadedAssemblies {
                if RuntimeAssemblyHasIdentity(loaded, identity) && RuntimeAssemblyPathMatches(loaded, path) {
                    if !IsCompilerProductAssembly(selected) && selectedModuleVersionId.Length > 0 && RuntimeAssemblyModuleVersionId(loaded) == selectedModuleVersionId {
                        return selected
                    }

                    return loaded
                }
            }

            if IsProjectReferenceAssemblyPath(path) {
                return null
            }

            if IsHostDependencyReferencePath(path) && CompilerAssemblyReferencesIdentity(identity) && IsCompilerBoundRuntimeAssembly(selected, identity) && HasUsableRuntimeContract(path) {
                return selected
            }

            if IsFrameworkPackReferencePath(path) {
                frameworkRuntime := TryLoadFrameworkRuntimeAssembly(runtimeAssemblies, path, identity)
                if frameworkRuntime != null {
                    return frameworkRuntime
                }
            }

            // Reference images are metadata inputs. The framework helper and exact paired
            // runtime-path probe above are the only routes that may supply their executable
            // implementation; never pass a ref/refint image to Assembly.LoadFrom.
            if IsReferenceAssemblyPath(path) {
                return null
            }

            exactLoaded := TryLoadExactIdentityAssembly(path, identity)
            if exactLoaded != null {
                if !IsCompilerProductAssembly(selected) && selectedModuleVersionId.Length > 0 && RuntimeAssemblyModuleVersionId(exactLoaded) == selectedModuleVersionId {
                    return selected
                }

                return exactLoaded
            }

            // An incompatible runtime image cannot satisfy this exact identity. Let the metadata
            // entry remain runtime-free rather than binding a different same-AQN build.
            return null
        }

        if IsFrameworkPackReferencePath(path) {
            frameworkRuntime := TryLoadFrameworkRuntimeAssembly(runtimeAssemblies, path, identity)
            if frameworkRuntime != null {
                return frameworkRuntime
            }
        }

        if IsReferenceAssemblyPath(path) {
            return null
        }

        exactPathLoaded := TryLoadExactIdentityAssembly(path, identity)
        if exactPathLoaded != null {
            return exactPathLoaded
        }

        // Reference assemblies and incompatible runtime images intentionally remain metadata-only.

        return null
    }

    // DIRECT CONSTRUCTION. This reflected until 022/3a: `GetConstructor` on both types, two `object[]`
    // argument arrays and two `ConstructorInfo.Invoke` calls, written that way because `new` on an
    // external type only emitted for the types on a hand-written allow-list and neither of these was on
    // it. The construction planner now selects any public constructor by argument flow, so the
    // reflection is gone -- and with it `ConstructorInfo::Invoke`, which a `MetadataLoadContext` refuses
    // outright (`Cannot invoke a method on objects loaded by a MetadataLoadContext.`), i.e. the one
    // remaining call shape that could not survive the universe this task is moving the catalog to.
    // The identity a path's image declares, or null when the file is not an assembly that can be
    // read at all.
    static func TryReadAssemblyName(path: string): AssemblyName? {
        try {
            return AssemblyName.GetAssemblyName(path)
        } catch {
            return null
        }
    }

    // The metadata context over `paths`, or null when one cannot be built over them.
    static func TryCreateMetadataLoadContext(paths: string[]): MetadataLoadContext? {
        try {
            return CreateMetadataLoadContext(paths)
        } catch {
            return null
        }
    }

    static func CreateMetadataLoadContext(paths: string[]): MetadataLoadContext {
        resolver := new PathAssemblyResolver(paths)
        return new MetadataLoadContext(resolver, "System.Runtime")
    }

    // A TYPE FORWARDER MUST BE ABLE TO LAND, AND THAT IS WHY A NAME LIST CANNOT BE THE CATALOG.
    //
    // `System.Runtime` is the reference surface of the framework: it DECLARES almost nothing and
    // FORWARDS almost everything. `System.Runtime.dll.GetType("System.Uri")` answers only when the
    // assembly the forwarder names — `System.Private.Uri` — is something the resolver can open. The
    // scan's resolver was handed exactly the files the scan had already chosen to INSPECT, so every
    // forwarder whose target was not itself on that list dead-ended and the type simply did not
    // exist for the back end.
    //
    // That is the whole of the `System.Uri` report, and it was never about `Uri`: `UriKind`,
    // `System.Net.WebUtility`, `System.Text.Encodings.Web` and every other name the framework
    // forwards out of an assembly nobody happened to list behaved identically. The ANALYZER never
    // had the problem, because `AnalyzerMetadataLoadSurface.Open` resolves from the runtime and
    // shared-framework DIRECTORIES — so analysis accepted `new Uri(...)` and `u.AbsoluteUri` and
    // emission then declined the very same program at NL103, which is exactly the two-walk
    // disagreement `SimpleNamePrecedence` exists to prevent.
    //
    // The two walks resolve the same way now. WHICH ASSEMBLIES ARE INSPECTED IS UNCHANGED — a
    // simple-name scan still sees only the entries the caller asked for, so no name starts resolving
    // because some unrelated framework assembly happens to export it — and these paths are
    // FORWARD TARGETS ONLY. An entry's own file keeps precedence: a path is added only when no entry
    // already supplies that file name, so a reference-pack facade a project chose is never displaced
    // by the implementation beside it.
    static func AddForwardTargetPaths(resolverPaths: List<string>, resolverNames: HashSet<string>, searchDirectories: string[]) {
        for directory in searchDirectories {
            candidates := new string[](0)
            try {
                candidates = Directory.GetFiles(directory, "*.dll")
            } catch {
                // A DIRECTORY THAT CANNOT BE LISTED CONTRIBUTES NOTHING, and that is the whole
                // handling: these paths are forward targets, so a missing one costs a forwarder that
                // could not be followed anyway. Every entry the caller asked for still stands.
                candidates = new string[](0)
            }

            candidateIndex := 0
            while candidateIndex < candidates.Length {
                candidate := candidates[candidateIndex]
                fileName := Path.GetFileName(candidate)
                if resolverNames.Add(fileName) {
                    resolverPaths.Add(candidate)
                }

                candidateIndex = candidateIndex + 1
            }
        }
    }

    static func CommonAssemblyNames(): string[] {
        names := new string[](33)
        names[0] = "System.Runtime"
        names[1] = "System.Console"
        names[2] = "System.Collections"
        names[3] = "System.Linq"
        names[4] = "System.Linq.Queryable"
        names[5] = "System.Net.Http"
        names[6] = "System.Text.Json"
        names[7] = "System.Threading"
        names[8] = "System.Threading.Tasks"
        names[9] = "System.IO.FileSystem"
        names[10] = "System.Text.RegularExpressions"
        names[11] = "System.ComponentModel.Annotations"
        names[12] = "System.Collections.Concurrent"
        names[13] = "System.Diagnostics.Debug"
        names[14] = "System.Diagnostics.Process"
        names[15] = "System.Runtime.InteropServices"
        names[16] = "System.ObjectModel"
        names[17] = "System.Linq.Expressions"
        names[18] = "System.Memory"
        names[19] = "System.IO.Pipes"
        names[20] = "System.Net.Primitives"
        names[21] = "System.Net.Sockets"
        names[22] = "System.Security.Cryptography"
        names[23] = "System.Text.Encoding.Extensions"
        names[24] = "System.Xml.ReaderWriter"
        names[25] = "System.Private.CoreLib"
        // LINQ-to-XML, named by its IMPLEMENTATION assembly. The `System.Xml.Linq` a project
        // references is a facade of type forwarders that exports nothing a metadata scan can see, so
        // a facade entry would put a path in the resolver and still resolve no type name. The 23
        // types live here. (`System.Xml.ReaderWriter` above is the same kind of facade and admits
        // nothing either — recorded rather than changed, because nothing depends on it.)
        names[26] = "System.Private.Xml.Linq"
        // 023/1b -- THE METADATA WRITER'S OWN ASSEMBLY. `System.Reflection.Metadata.dll` ships in
        // Microsoft.NETCore.App and carries BOTH the `System.Reflection.Metadata[.Ecma335]` and the
        // `System.Reflection.PortableExecutable` namespaces, so one entry opens the whole ECMA-335
        // writer surface. Without it `import System.Reflection.Metadata.Ecma335` is NL704 and
        // `import System.Reflection.Metadata` types are NL201 -- and neither can be worked around by
        // fully qualifying, because a fully-qualified STATIC RECEIVER does not bind at all
        // (`System.Reflection.Metadata.Ecma335.MetadataTokens.X` answers "Variable 'System' not
        // found"), which is what makes this entry load-bearing rather than a convenience.
        names[27] = "System.Reflection.Metadata"
        // THE FILE-SYSTEM WATCHER AND THE ZIP WRITER, which are the two BCL surfaces a `nlc`-shaped
        // program reaches for and neither of which lives in an assembly already named above.
        // `FileSystemWatcher` (with `NotifyFilters`, `FileSystemEventArgs`, `RenamedEventArgs`) is
        // the whole of `System.IO.FileSystem.Watcher`; without it a watch loop reports NL201 "Type
        // 'FileSystemWatcher' not found" with no import that could fix it. `ZipArchive` /
        // `ZipArchiveMode` live in `System.IO.Compression` and the `ZipFile` /
        // `ZipArchive.CreateEntryFromFile` pair in `System.IO.Compression.ZipFile`, so writing a
        // NuGet package — a zip — needed both entries: `import System.IO.Compression` itself
        // reported NL704 "namespace not found" because nothing in the loaded set declared it.
        names[28] = "System.IO.FileSystem.Watcher"
        names[29] = "System.IO.Compression"
        names[30] = "System.IO.Compression.ZipFile"
        // THE PERSISTED ASSEMBLY BUILDER'S OWN ASSEMBLY, which is the one Reflection.Emit name that
        // CoreLib does not answer for. Every other emit type a program spells — `AssemblyBuilder`,
        // `TypeBuilder`, `ModuleBuilder`, `EnumBuilder`, `ILGenerator` — is declared in
        // `System.Private.CoreLib` and therefore already resolved through the entry above; measured
        // in this runtime, `Type.GetType("System.Reflection.Emit.PersistedAssemblyBuilder")` is the
        // only one that answers null, because that type is declared in `System.Reflection.Emit.dll`
        // alone. Without this entry a parameter or a `new` annotated with the type the compiler's
        // own IL back end constructs reported NL201 "Type 'PersistedAssemblyBuilder' not found" —
        // on the compiler's own source, through its own front door — and the `import
        // System.Reflection.Emit` that supplies it was then reported NL010 as unused. Neither could
        // be worked around by fully qualifying the name.
        names[31] = "System.Reflection.Emit"
        // THE PIPE. `System.IO.Pipelines` ships in Microsoft.NETCore.App and declares `Pipe`,
        // `PipeReader`, `PipeWriter`, `PipeOptions`, `PipeScheduler`, `ReadResult` and
        // `FlushResult` — the stdin pump a long-running stdio server needs so that EOF on its input
        // terminates it, which is the language server's "must not outlive its client" behaviour.
        // Nothing else declares the namespace, so without this entry `import System.IO.Pipelines`
        // was NL704 and a fully-qualified `new System.IO.Pipelines.Pipe()` passed `check` and then
        // declined at emit with no name the scan could resolve.
        names[32] = "System.IO.Pipelines"
        return names
    }
}

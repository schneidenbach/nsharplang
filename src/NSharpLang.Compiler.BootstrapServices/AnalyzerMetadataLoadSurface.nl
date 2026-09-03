namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection


// THE MECHANISM THAT PUTS AN ASSEMBLY IN FRONT OF THE ANALYZER.
//
// `AnalyzerMetadataLoadPolicy` already owns every DECISION this surface makes — which name is the
// same name, which path is the same path, whether a directory is worth searching, whether a failure
// is worth recording. What lived on in `Analyzer.cs` was the MECHANISM those decisions serve: open
// the file, ask the load context, keep the registry, remember what went wrong. That is not a
// mechanical host's work either, and it is the last thing keeping `System.Reflection.MetadataLoadContext`
// spelled in the compiler's C#.
//
// THE THREE COLLECTIONS ARE HELD BY REFERENCE AND NEVER RESNAPSHOTTED. `assemblies` is the
// analyzer's `_mlcAssemblies`, which six N# owners already hold the same way (the external type
// probe, the extension-method scan, the declaration context, the member resolver); `failures` is the
// analyzer's `_referenceLoadFailures`, which `AnalyzerReferenceLoadReport` also holds by reference
// and READS at the end of every analysis. A snapshot of either would be empty at the moment it was
// taken and stale forever after. `searchDirectories` is the third, and the resolver reads it in
// place: this owner writes the directories, the resolver walks them.
//
// THE LOAD CONTEXT IS BUILT AND TORN DOWN HERE (022/3b-3). `Analyzer.LoadSystemAssemblies` hands over
// a resolver and nothing else; `Open` cores the context on the one identity
// `AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName()` names, and `Close` disposes it. So `Context`
// is the one field that changes after construction, and it changes for a reason the type's own
// lifetime cannot express: the analyzer holds ONE surface across a context that is opened and closed.
// Every entry point therefore reads it into a local first and answers nothing when it is absent — an
// unopened surface is a no-op, exactly as the C# `if (_mlc == null) return;` was.
//
// THE WELL-KNOWN-TYPE BAG IS BUILT HERE TOO, and that is why the context does not have to leave. The
// bag needs the context AND its core assembly, and the core assembly is the one thing a context can
// fail to produce; asking for it in C# meant a `?? throw` in a file that is supposed to decide
// nothing. `CreateWellKnownTypes` asks, refuses loudly when the answer is absent, and hands back the
// built bag.
//
// LOADING BY PATH IS A FOUR-STAGE PROBE AND THE ORDER IS THE POLICY:
//   1. the requested path's DIRECTORY joins the resolver's search list, so this assembly's
//      neighbours can answer for its own references — and it joins BEFORE the dedupe checks, so a
//      second request for an already-loaded path still contributes its directory;
//   2. the path is checked against what is already registered, because re-reading a file that is
//      already in the registry would build a second `Assembly` for it;
//   3. the assembly's IDENTITY is checked against what is already registered, because two different
//      files can carry one identity and the first one loaded is the one the analyzer resolves
//      against;
//   4. the identity is checked against the whole LOAD CONTEXT, not just this registry, because the
//      resolver loads assemblies the registry never sees. Skipping this stage is not a missed
//      optimisation: `MetadataLoadContext.LoadFromAssemblyPath` THROWS `FileLoadException` when the
//      identity is already loaded ("has already loaded been loaded into this MetadataLoadContext"),
//      so the second copy of a stale-beside-restored NuGet extraction would be recorded as a load
//      FAILURE instead of resolving. The already-loaded copy is adopted into the registry instead.
//
// A FAILED LOAD IS RECORDED, NEVER THROWN. Reference probing is best-effort: the analyzer tries
// paths that legitimately miss, and one bad reference must not end the analysis. The failure joins
// the table `AnalyzerReferenceLoadReport` pairs against unresolved-type errors, first failure per
// identity, and the analysis continues with one less assembly.
class AnalyzerMetadataLoadSurface {

    // The live load context, or null before `Open` and after `Close`.
    Context: MetadataLoadContext?

    // The analyzer's registry of metadata assemblies, held by reference.
    assemblies: List<Assembly>

    // The analyzer's failure table, held by reference.
    failures: Dictionary<string, string>

    // The resolver's search directories. Written here, read by the resolver in place.
    searchDirectories: List<string>

    // The versions the project RESTORED, keyed by package name. Same seam as the directories: the
    // orchestration writes them, the resolver reads them when a cache fallback has to choose between
    // several extracted versions.
    pinnedPackageVersions: Dictionary<string, string>

    constructor(loadedAssemblies: List<Assembly>, referenceLoadFailures: Dictionary<string, string>) {
        Context = null
        assemblies = loadedAssemblies
        failures = referenceLoadFailures
        searchDirectories = new List<string>()
        pinnedPackageVersions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    }

    // A NEW RESOLVER IS BEING BUILT, which means a new load context is beginning. The directories
    // the previous context accumulated are not this one's, so the shared list is cleared and handed
    // to the resolver, which holds it and walks it.
    func BeginResolverDirectories(): List<string> {
        searchDirectories.Clear()
        return searchDirectories
    }

    func BeginResolverPinnedVersions(): Dictionary<string, string> {
        pinnedPackageVersions.Clear()
        return pinnedPackageVersions
    }

    // The last write wins, which is what a project that names one version twice means.
    func PinPackageVersion(packageName: string, version: string) {
        pinnedPackageVersions[packageName] = version
    }

    // The resolver is built first and the context is cored over it. The core assembly identity is a
    // decision and lives in the policy owner; the construction is mechanism and lives here.
    func Open(resolver: MetadataAssemblyResolver) {
        Context = new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())
    }

    // The analyzer is being disposed. The context is released and nothing may be loaded afterwards.
    func Close() {
        loadContext := Context
        if loadContext != null {
            loadContext.Dispose()
        }

        Context = null
    }

    // EVERY `int`, `string` and `object` A REFERENCED ASSEMBLY NAMES resolves through the context's
    // core assembly, so a context that produced none cannot answer a single semantic question. The
    // refusal is loud rather than a null bag, because a silent one degrades every later diagnostic
    // into "type not found".
    func CreateWellKnownTypes(): AnalyzerWellKnownTypes {
        loadContext := Context
        if loadContext == null {
            throw new InvalidOperationException("MLC not opened")
        }

        core := loadContext.get_CoreAssembly()
        if core == null {
            throw new InvalidOperationException("MLC core assembly not loaded")
        }

        return new AnalyzerWellKnownTypes(loadContext, core)
    }

    func AddSearchDirectory(directory: string) {
        if AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory(directory, Directory.Exists(directory), searchDirectories) {
            searchDirectories.Add(directory)
        }
    }

    func RecordFailure(identity: string, detail: string) {
        if AnalyzerMetadataLoadPolicy.ShouldRecordLoadFailure(failures.ContainsKey(identity)) {
            failures[identity] = detail
        }
    }

    // The exception's TYPE NAME carries the diagnosis, so it is read rather than the message alone.
    // The receiver is boxed first because `GetType()` on a typed receiver is off the columnar
    // surface; the phrasing itself belongs to `AnalyzerReferenceLoadReport`.
    func RecordExceptionFailure(identity: string, error: Exception) {
        boxed := error as object
        errorType := boxed.GetType()
        RecordFailure(identity, AnalyzerReferenceLoadReport.ExceptionDetail(errorType.get_Name(), error.Message))
    }

    // Idempotent by IDENTITY, not by reference: the same assembly can arrive from the registry probe
    // and from a fresh load in one analysis.
    func Register(assembly: Assembly) {
        if !IsIdentityLoaded(assembly.GetName()) {
            assemblies.Add(assembly)
        }
    }

    func IsIdentityLoaded(identity: AssemblyName): bool {
        index := 0
        while index < assemblies.Count {
            loadedName := assemblies[index].GetName()
            if AssemblyName.ReferenceMatchesDefinition(loadedName, identity) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The by-NAME dedupe is deliberately weaker than the by-identity one: a caller asking for
    // "System.Text.Json" is asking for whatever version this analysis resolved, so any loaded
    // assembly with that simple name answers.
    func IsSimpleNameLoaded(simpleName: string): bool {
        index := 0
        while index < assemblies.Count {
            loadedName := assemblies[index].GetName()
            if AnalyzerMetadataLoadPolicy.IsSameSimpleName(loadedName.get_Name(), simpleName) {
                return true
            }

            index = index + 1
        }

        return false
    }

    func IsPathLoaded(assemblyPath: string): bool {
        normalizedPath := Path.GetFullPath(assemblyPath)
        index := 0
        while index < assemblies.Count {
            location := assemblies[index].get_Location()
            if AnalyzerMetadataLoadPolicy.IsSameAssemblyPath(Path.GetFullPath(location), normalizedPath) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // Stage 4 of the by-path probe: the identity the LOAD CONTEXT already holds, which is a superset
    // of the registry.
    func FindLoadedInContext(loadContext: MetadataLoadContext, identity: AssemblyName): Assembly? {
        for candidate in loadContext.GetAssemblies() {
            if AssemblyName.ReferenceMatchesDefinition(candidate.GetName(), identity) {
                return candidate
            }
        }

        return null
    }

    func LoadByPath(assemblyPath: string) {
        loadContext := Context
        if loadContext == null {
            return
        }

        try {
            fullPath := Path.GetFullPath(assemblyPath)
            directory := Path.GetDirectoryName(fullPath)
            if directory != null {
                AddSearchDirectory(directory)
            }

            if IsPathLoaded(fullPath) {
                return
            }

            identity := AssemblyName.GetAssemblyName(fullPath)
            if IsIdentityLoaded(identity) {
                return
            }

            adopted := FindLoadedInContext(loadContext, identity)
            if adopted != null {
                Register(adopted)
                return
            }

            Register(loadContext.LoadFromAssemblyPath(fullPath))
        } catch error: Exception {
            RecordExceptionFailure(assemblyPath, error)
        }
    }

    func LoadByName(simpleName: string) {
        loadContext := Context
        if loadContext == null {
            return
        }

        if IsSimpleNameLoaded(simpleName) {
            return
        }

        try {
            Register(loadContext.LoadFromAssemblyName(simpleName))
        } catch error: Exception {
            RecordExceptionFailure(simpleName, error)
        }
    }
}

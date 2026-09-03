namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices


// NATIVE CONTRACTS FOR THE ANALYZER'S METADATA LOAD SURFACE.
//
// The first two blocks are MIGRATED, not restated: they are the two `[Fact]`s that were the whole
// remainder of `tests/AnalyzerMetadataLoadContextTests.cs`, and that file said in its own header why
// they could not move — "migrating them needs an estate kernel that can compile a throwaway managed
// library and hand back its path; no such kernel exists yet". That reading was about the FIXTURE, not
// about the rule, and the fixture it asked for is not the only one that produces the shape. What both
// blocks need is ONE assembly identity present at TWO paths, and the machine that runs this gate
// already ships exactly that: `System.Console, Version=10.0.0.0, PublicKeyToken=b03f5f7f11d50a3a`
// exists both as the shared framework's 208 KB implementation and as the reference pack's 16 KB
// reference assembly -- two very different files, one identity. Both paths are DERIVED at run time
// (`RuntimeEnvironment.GetRuntimeDirectory` and `DocQueryKernels.GetReferencePackDirectories`), never
// written down, because a hard-coded SDK path is a contract about this machine rather than about the
// rule.
//
// The `PersistedAssemblyBuilder` route to the same fixture was considered and REFUSED: emitting two
// throwaway libraries from the estate would add a modeled-type dependency (the builder surface) to a
// contract whose subject is the LOAD side, and it would make this file republish-gated for a reason
// unrelated to what it pins.
//
// The last three blocks are new. The C# never pinned them, and each is a live branch of the surface:
// the by-path dedupe, the record-instead-of-throw rule, and the unattached state that `Dispose` puts
// the surface back into.
func MetadataLoadSurfaceFrameworkDirectory(): string {
    return RuntimeEnvironment.GetRuntimeDirectory()
}

func MetadataLoadSurfaceFrameworkPath(simpleName: string): string {
    return Path.Combine(MetadataLoadSurfaceFrameworkDirectory(), simpleName + ".dll")
}

// THE FIXTURE IS DELIBERATELY NOT THE CORE ASSEMBLY (022/3b-3). `Open` cores the context on
// `MetadataCoreAssemblyName()`, and a `MetadataLoadContext` binds its core eagerly -- so the core
// identity is ALREADY loaded before any of these blocks asks for anything, and the adopt stage would
// claim it by construction. `System.Console` ships in both directories under one identity and is not
// the core, so the dedupe rules are demonstrated on an identity the context has not pre-decided.
func MetadataLoadSurfaceTwinName(): string {
    return "System.Console"
}

// The SAME identity from the reference pack. `GetReferencePackDirectories` is the analyzer's own
// root discovery -- the one that climbs the runtime directory rather than reading `Assembly.Location`
// -- so this fixture is built out of a production kernel rather than a path guess.
func MetadataLoadSurfaceReferencePackPath(simpleName: string): string {
    seeds := new string[](1)
    seeds[0] = MetadataLoadSurfaceFrameworkDirectory()
    directories := DocQueryKernels.GetReferencePackDirectories(seeds, Environment.GetEnvironmentVariable("DOTNET_ROOT"))
    index := 0
    while index < directories.Length {
        candidate := Path.Combine(directories[index], simpleName + ".dll")
        if File.Exists(candidate) {
            return candidate
        }

        index = index + 1
    }

    return ""
}

// `Open` builds the resolver AND the context AND the search-directory ladder (022/3b-4b), so these
// blocks open exactly what production opens. The shared framework directory is one of the
// directories it registers, which is what makes the first block's question real: the resolver would
// happily answer for the twin out of that directory, and the requested path must still win.

func MetadataLoadSurfaceContextOf(surface: AnalyzerMetadataLoadSurface): MetadataLoadContext {
    loadContext := surface.Context
    if loadContext == null {
        throw new InvalidOperationException("The surface did not open a load context.")
    }

    return loadContext
}

func MetadataLoadSurfaceNew(assemblies: List<Assembly>, failures: Dictionary<string, string>): AnalyzerMetadataLoadSurface {
    return new AnalyzerMetadataLoadSurface(assemblies, failures)
}

func MetadataLoadSurfaceLocationOf(assemblies: List<Assembly>, position: int): string {
    return Path.GetFullPath(assemblies[position].get_Location())
}

func MetadataLoadSurfaceHolds(directories: List<string>, value: string): bool {
    index := 0
    while index < directories.Count {
        if directories[index] == value {
            return true
        }

        index = index + 1
    }

    return false
}

// ── the two fixture facts every block below leans on ─────────────────────────

test "the two copies of the twin assembly are two files carrying one identity" {
    frameworkPath := MetadataLoadSurfaceFrameworkPath(MetadataLoadSurfaceTwinName())
    referencePath := MetadataLoadSurfaceReferencePackPath(MetadataLoadSurfaceTwinName())

    assert File.Exists(frameworkPath)
    assert referencePath.Length > 0
    assert File.Exists(referencePath)
    assert Path.GetFullPath(frameworkPath) != Path.GetFullPath(referencePath)

    frameworkIdentity := AssemblyName.GetAssemblyName(frameworkPath)
    referenceIdentity := AssemblyName.GetAssemblyName(referencePath)
    assert frameworkIdentity.get_Name() == MetadataLoadSurfaceTwinName()
    assert frameworkIdentity.get_FullName() == referenceIdentity.get_FullName()
    assert AssemblyName.ReferenceMatchesDefinition(frameworkIdentity, referenceIdentity)
}

// ── migrated: LoadReferencedAssembly_UsesRequestedAssemblyPathWhenSearchDirectoryAlreadyContainsSameName

test "a search directory holding the same identity does not win over the requested path" {
    frameworkDirectory := MetadataLoadSurfaceFrameworkDirectory()
    referencePath := MetadataLoadSurfaceReferencePackPath(MetadataLoadSurfaceTwinName())
    assert File.Exists(referencePath)

    assemblies := new List<Assembly>()
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    surface := MetadataLoadSurfaceNew(assemblies, failures)

    surface.Open()

    // `Open` registered the shared framework directory itself; the resolver can serve the twin from
    // there, and the block below asks for it by a path somewhere else entirely.
    assert MetadataLoadSurfaceHolds(surface.SearchDirectories, frameworkDirectory)

    surface.LoadByPath(referencePath)

    assert failures.Count == 0
    assert assemblies.Count == 1
    assert MetadataLoadSurfaceLocationOf(assemblies, 0) == Path.GetFullPath(referencePath)

    loadedName := assemblies[0].GetName()
    assert loadedName.get_Name() == MetadataLoadSurfaceTwinName()

    // The requested path's own directory joins the search list too -- that is stage 1 of the probe,
    // and it happens whether or not the load goes on to dedupe.
    assert MetadataLoadSurfaceHolds(surface.SearchDirectories, Path.GetDirectoryName(referencePath) ?? "")
}

// ── migrated: LoadReferencedAssembly_AdoptsAlreadyLoadedIdentityInsteadOfThrowing

test "a second load of an already-loaded identity adopts the first copy instead of throwing" {
    frameworkPath := MetadataLoadSurfaceFrameworkPath(MetadataLoadSurfaceTwinName())
    referencePath := MetadataLoadSurfaceReferencePackPath(MetadataLoadSurfaceTwinName())
    assert File.Exists(referencePath)

    assemblies := new List<Assembly>()
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    surface := MetadataLoadSurfaceNew(assemblies, failures)
    surface.Open()
    context := MetadataLoadSurfaceContextOf(surface)

    // Staged the way the metadata RESOLVER stages one: straight into the load context, bypassing the
    // analyzer's registry. This is the stale-beside-restored NuGet extraction, exactly.
    staged := context.LoadFromAssemblyPath(frameworkPath)
    stagedName := staged.GetName()
    assert stagedName.get_Name() == MetadataLoadSurfaceTwinName()

    surface.LoadByPath(referencePath)

    // The FIRST-loaded copy wins, and the second load neither throws nor is recorded as a failure.
    assert failures.Count == 0
    assert assemblies.Count == 1
    assert MetadataLoadSurfaceLocationOf(assemblies, 0) == Path.GetFullPath(frameworkPath)

    // THE GUARD IS LOAD-BEARING, AND THIS IS WHAT IT PREVENTS. Without the context probe the surface
    // would reach `LoadFromAssemblyPath` and the reference copy would be recorded as a load FAILURE
    // rather than resolved -- which is a "type not found" on types that plainly exist.
    threw := false
    try {
        context.LoadFromAssemblyPath(referencePath)
    } catch duplicateError: Exception {
        threw = true
    }

    assert threw
}

// ── new: the by-path dedupe

test "the same path loaded twice registers once and contributes its directory once" {
    referencePath := MetadataLoadSurfaceReferencePackPath(MetadataLoadSurfaceTwinName())
    assert File.Exists(referencePath)

    assemblies := new List<Assembly>()
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    surface := MetadataLoadSurfaceNew(assemblies, failures)
    surface.Open()
    openedDirectoryCount := surface.SearchDirectories.Count

    surface.LoadByPath(referencePath)
    surface.LoadByPath(referencePath)
    surface.LoadByPath(referencePath)

    assert assemblies.Count == 1
    assert failures.Count == 0
    assert surface.SearchDirectories.Count == openedDirectoryCount + 1

    // The by-NAME door dedupes on the SIMPLE name, which is weaker on purpose: a caller asking for
    // a simple name is asking for whatever version this analysis already resolved.
    surface.LoadByName(MetadataLoadSurfaceTwinName())
    assert assemblies.Count == 1
}

// ── new: a failed load is recorded, never thrown, and the FIRST failure per identity is kept

test "a failed load is recorded rather than thrown and the first failure per identity stands" {
    missingPath := Path.Combine(MetadataLoadSurfaceFrameworkDirectory(), "NSharpLangNoSuchAssembly.dll")
    assert !File.Exists(missingPath)

    assemblies := new List<Assembly>()
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    surface := MetadataLoadSurfaceNew(assemblies, failures)
    surface.Open()

    surface.LoadByPath(missingPath)

    assert assemblies.Count == 0
    assert failures.Count == 1
    assert failures.ContainsKey(missingPath)

    // The detail is phrased by `AnalyzerReferenceLoadReport`, and the exception's TYPE NAME leads it
    // because that name is the diagnosis a user acts on.
    firstDetail := failures[missingPath]
    assert firstDetail.StartsWith("FileNotFoundException: ")

    // A later probe of the same identity does NOT overwrite the first failure.
    surface.RecordFailure(missingPath, "a later probe said something else")
    assert failures[missingPath] == firstDetail
    assert failures.Count == 1

    // The by-name door records the same way, under the NAME as its identity.
    surface.LoadByName("NSharpLangNoSuchAssemblyByName")
    assert failures.Count == 2
    assert failures.ContainsKey("NSharpLangNoSuchAssemblyByName")
    assert assemblies.Count == 0
}

// ── new: an unattached surface is a no-op, which is what `Dispose` restores

test "an unattached surface loads nothing, and Detach puts it back into that state" {
    referencePath := MetadataLoadSurfaceReferencePackPath(MetadataLoadSurfaceTwinName())
    assert File.Exists(referencePath)

    assemblies := new List<Assembly>()
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    surface := MetadataLoadSurfaceNew(assemblies, failures)

    // Before `Attach`: both doors answer nothing, and neither records a failure. A surface with no
    // context is not a broken surface -- it is an analyzer that never loaded one.
    surface.LoadByPath(referencePath)
    surface.LoadByName(MetadataLoadSurfaceTwinName())
    assert assemblies.Count == 0
    assert failures.Count == 0

    surface.Open()
    surface.LoadByName(MetadataLoadSurfaceTwinName())
    assert assemblies.Count == 1

    // `Dispose` disposes the context and detaches. Loading through a disposed context would throw
    // inside the load and be recorded as a failure; detaching means nothing is attempted at all.
    surface.Close()
    surface.LoadByPath(referencePath)
    surface.LoadByName("System.Linq")
    assert assemblies.Count == 1
    assert failures.Count == 0
}

// ── 022/3b-3: the context is opened, cored and closed here, and so is the well-known-type bag ──

test "the surface cores the context on the policy's core assembly and builds the well-known bag" {
    assemblies := new List<Assembly>()
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    surface := MetadataLoadSurfaceNew(assemblies, failures)

    // Before `Open` there is no context at all, and the bag cannot be built from one.
    assert surface.Context == null

    surface.Open()
    context := MetadataLoadSurfaceContextOf(surface)

    // THE CORE IDENTITY IS THE POLICY'S, NOT A LITERAL WRITTEN HERE. Every `int`, `string` and
    // `object` a referenced assembly names binds through it, so a second spelling of the name would
    // be a second answer to the question the whole context is built around.
    core := context.get_CoreAssembly()
    assert core != null
    coreName := core.GetName()
    assert coreName.get_Name() == AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName()

    // The bag arrives BUILT. The `?? throw` this replaces used to live in `Analyzer.cs`, which is
    // supposed to decide nothing -- and "the context produced no core assembly" is a decision about
    // whether analysis can proceed at all.
    facts := surface.CreateWellKnownTypes()
    resolvedString := facts.Resolve("System.String")
    assert resolvedString != null
    assert facts.ResolveRequired("System.Object").get_FullName() == "System.Object"

    // `Close` releases the context, and the surface is a no-op again.
    surface.Close()
    assert surface.Context == null
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection


// WHERE THE METADATA LOAD CONTEXT LOOKS WHEN IT NEEDS AN ASSEMBLY IT HAS NOT GOT.
//
// A `MetadataLoadContext` resolves nothing by itself: every reference an assembly names comes back
// here, and whatever this returns is what the analyzer's type universe contains. It is therefore not
// a helper. It is the outer boundary of the whole external type model, and it is the LAST thing in
// the compiler's C# that named `MetadataLoadContext`.
//
// D3 — THE FOUR-STAGE PROBE ORDER, AND WHY IT IS THAT ORDER. Like D1 and D2 (022/3b-4a) this decision
// carries no literal, so nothing could pin it while it lived beside the IO that performs it:
//
//   1. ALREADY LOADED, BY SIMPLE NAME. First, because a second copy of an identity the context has
//      already bound is a second `System.String` — type identity inside a load context is per
//      assembly object, so admitting a duplicate makes `IsAssignable` answer no about a type that
//      plainly is one. The match is deliberately by SIMPLE NAME and case-insensitive: the caller has
//      a reference with a version this analysis may not have loaded, and the version already loaded
//      is the one every other type in the universe was resolved against.
//   2. THE SEARCH DIRECTORIES, IN ORDER. These are the shared framework, the host's own directory,
//      and the directory of every assembly loaded by path — the places where the assemblies this
//      project actually builds against live. They come before the cache because they are the copies
//      the project resolved, not merely copies that exist on the machine.
//   3. THE EXACT NUGET PACKAGE DIRECTORY, lowercased, which is how the cache is laid out.
//   4. A PREFIX SCAN OF THE CACHE, last and slowest, because it is a guess: `Foo.Bar` may live in a
//      package called `Foo`. It is the only stage that can bind an assembly the project never named,
//      which is why nothing else may come after it.
//
// A FAILURE HERE IS NEVER THROWN AND NEVER STOPS THE PROBE. A file that exists but will not load is
// recorded and the walk CONTINUES to the next candidate — the next target framework, the next
// directory, the next package. Throwing would abandon a resolution that the very next candidate would
// have satisfied. The failures land in the resolver's own table, which
// `AnalyzerReferenceLoadReport` merges UNDER the analyzer's: these describe a probe, those describe
// the point the compiler actually needed the assembly.
class AnalyzerMetadataAssemblyResolver: MetadataAssemblyResolver {

    // All three tables are the load surface's, held by reference: this resolver is rebuilt with every
    // load context and they outlive it.
    searchDirectories: List<string>
    pinnedPackageVersions: Dictionary<string, string>
    failures: Dictionary<string, string>

    constructor(directories: List<string>, pinnedVersions: Dictionary<string, string>, loadFailures: Dictionary<string, string>) {
        searchDirectories = directories
        pinnedPackageVersions = pinnedVersions
        failures = loadFailures
    }

    func RecordLoadFailure(path: string, error: Exception) {
        if AnalyzerMetadataLoadPolicy.ShouldRecordLoadFailure(failures.ContainsKey(path)) {
            boxed := error as object
            errorType := boxed.GetType()
            failures[path] = AnalyzerReferenceLoadReport.ExceptionDetail(errorType.get_Name(), error.Message)
        }
    }

    func NuGetPackagesRoot(): string {
        return AnalyzerMetadataLoadPolicy.NuGetPackagesRoot(
            Environment.GetEnvironmentVariable("NUGET_PACKAGES"),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        )
    }

    // THE PINNED VERSION WINS OVER THE HIGHEST ONE. A project that restored 13.0.1 must be analysed
    // against 13.0.1 even when 13.0.3 is also extracted on the machine, or a diagnostic is computed
    // against metadata the build will never see.
    func PickPackageVersionDirectory(packageDirectory: string): string? {
        packageName := Path.GetFileName(packageDirectory)
        if packageName != null {
            if pinnedPackageVersions.ContainsKey(packageName) {
                pinnedDirectory := AnalyzerMetadataLoadPolicy.PinnedPackageVersionDirectory(packageDirectory, pinnedPackageVersions[packageName])
                if pinnedDirectory != null {
                    if Directory.Exists(pinnedDirectory) {
                        return pinnedDirectory
                    }
                }
            }
        }

        return AnalyzerMetadataLoadPolicy.PickHighestVersionDirectory(Directory.GetDirectories(packageDirectory))
    }

    func TryLoadFromPackageDirectory(context: MetadataLoadContext, packageDirectory: string, simpleName: string): Assembly? {
        if !Directory.Exists(packageDirectory) {
            return null
        }

        versionDirectory := PickPackageVersionDirectory(packageDirectory)
        if versionDirectory == null {
            return null
        }

        targetFrameworks := AnalyzerMetadataLoadPolicy.FallbackTargetFrameworks()
        index := 0
        while index < targetFrameworks.Length {
            assemblyPath := AnalyzerMetadataLoadPolicy.PackageLibAssetPath(versionDirectory, targetFrameworks[index], simpleName)
            if File.Exists(assemblyPath) {
                loaded := TryLoadFromPath(context, assemblyPath)
                if loaded != null {
                    return loaded
                }
            }

            index = index + 1
        }

        return null
    }

    // The one place a candidate file is turned into an assembly, so the record-and-continue rule is
    // written once rather than at each of the three probe stages that can hit a bad file.
    func TryLoadFromPath(context: MetadataLoadContext, assemblyPath: string): Assembly? {
        try {
            return context.LoadFromAssemblyPath(assemblyPath)
        } catch loadError: Exception {
            RecordLoadFailure(assemblyPath, loadError)
        }

        return null
    }

    override func Resolve(context: MetadataLoadContext, assemblyName: AssemblyName): Assembly? {
        simpleName := assemblyName.get_Name()
        if simpleName == null {
            return null
        }

        // Stage 1 — an identity the context already holds.
        for loaded in context.GetAssemblies() {
            loadedName := loaded.GetName()
            if AnalyzerMetadataLoadPolicy.IsSameSimpleName(loadedName.get_Name(), simpleName) {
                return loaded
            }
        }

        // Stage 2 — the search directories, in the order they were added.
        directoryIndex := 0
        while directoryIndex < searchDirectories.Count {
            candidate := AnalyzerMetadataLoadPolicy.SearchDirectoryAssemblyPath(searchDirectories[directoryIndex], simpleName)
            if File.Exists(candidate) {
                fromDirectory := TryLoadFromPath(context, candidate)
                if fromDirectory != null {
                    return fromDirectory
                }
            }

            directoryIndex = directoryIndex + 1
        }

        nugetRoot := NuGetPackagesRoot()

        // Stage 3 — the package directory this name would have if it named a package.
        exact := TryLoadFromPackageDirectory(context, Path.Combine(nugetRoot, simpleName.ToLowerInvariant()), simpleName)
        if exact != null {
            return exact
        }

        // Stage 4 — the guess. `Foo.Bar` may ship inside the package `Foo`.
        if Directory.Exists(nugetRoot) {
            for packageDirectory in Directory.GetDirectories(nugetRoot) {
                if AnalyzerMetadataLoadPolicy.NuGetPackageDirectoryMatchesPrefix(Path.GetFileName(packageDirectory), simpleName) {
                    fromPackage := TryLoadFromPackageDirectory(context, packageDirectory, simpleName)
                    if fromPackage != null {
                        return fromPackage
                    }
                }
            }
        }

        return null
    }
}

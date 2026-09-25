namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

class ReferenceResolutionOptions {
    configurationValue: string
    includeTestsValue: bool
    buildProjectReferencesValue: bool
    quietValue: bool
    aotModeValue: bool
    useBuiltProjectReferencesValue: bool
    packagesFolderValue: string?

    constructor() {
        configurationValue = "Debug"
        includeTestsValue = false
        buildProjectReferencesValue = true
        quietValue = false
        aotModeValue = false
    }

    Configuration: string {
        get {
            return configurationValue
        }
        set {
            configurationValue = value
        }
    }

    IncludeTests: bool {
        get {
            return includeTestsValue
        }
        set {
            includeTestsValue = value
        }
    }

    BuildProjectReferences: bool {
        get {
            return buildProjectReferencesValue
        }
        set {
            buildProjectReferencesValue = value
        }
    }

    Quiet: bool {
        get {
            return quietValue
        }
        set {
            quietValue = value
        }
    }

    AotMode: bool {
        get {
            return aotModeValue
        }
        set {
            aotModeValue = value
        }
    }

    // A `project:` DEPENDENCY IS READ FROM ITS BUILT ASSEMBLY, NOT COMPILED FROM SOURCE. Off, each
    // project reference (and each of its own) is compiled in-process by this resolution, which is how
    // `nlc build` stays self-contained. On, the reference is the assembly that project's own build
    // already wrote to its stable output directory (`bin/<Configuration>/<targetFramework>`, the
    // directory both `nlc build` and `dotnet build` write), found the same way transitively -- the
    // shape of `cargo check` or `go vet` over dependencies that are already compiled. A reference that
    // was never built, or whose product sources are newer than its assembly, is an error that names
    // it rather than a silently stale answer. It is what lets `nlc check` measure a project whose
    // dependency cannot be compiled by `nlc` itself yet but IS built (the compiler's own slices).
    UseBuiltProjectReferences: bool {
        get {
            return useBuiltProjectReferencesValue
        }
        set {
            useBuiltProjectReferencesValue = value
        }
    }

    // THE NUGET GLOBAL PACKAGES FOLDER THIS RESOLUTION READS. Null is NuGet's own rule --
    // `NUGET_PACKAGES`, else `~/.nuget/packages` -- read once when the resolution begins. A caller that
    // resolves against a different cache names it here instead of rewriting the process environment,
    // which every other reader in the process would see too.
    PackagesFolder: string? {
        get {
            return packagesFolderValue
        }
        set {
            packagesFolderValue = value
        }
    }

    constructor(Configuration: string, IncludeTests: bool, BuildProjectReferences: bool, Quiet: bool, AotMode: bool) {
        configurationValue = Configuration
        includeTestsValue = IncludeTests
        buildProjectReferencesValue = BuildProjectReferences
        quietValue = Quiet
        aotModeValue = AotMode
    }
}

class ReferenceResolutionResult {
    runtimeAssets: HashSet<string>?
    projectOutputs: List<string>?

    // EVERY PROJECT THIS PROJECT REFERENCES, TRANSITIVELY: the output assembly of each `project:`
    // reference and of each of ITS project references, in the order they were first reached. A project
    // compiles against all of them, as MSBuild's transitive `ProjectReference` does -- a type of C that
    // A names through A -> B -> C is a type A's compilation must be able to see, not only a file copied
    // beside A's output.
    ProjectOutputAssemblies: IReadOnlyList<string> => ProjectOutputList

    RuntimeAssets: IReadOnlyList<string> => BuildRuntimeAssets()

    static func Create(projectRoot: string, dependencies: IReadOnlyList<Reference>?): ReferenceResolutionResult {
        result := new ReferenceResolutionResult()
        paths := ExternalAssemblyScan.ResolveRuntimeAssetPaths(projectRoot, dependencies)

        for path in paths {
            result.AddRuntimeAsset(path)
        }

        return result
    }

    func AddRuntimeAsset(path: string) {
        if !string.IsNullOrWhiteSpace(path) && File.Exists(path) {
            RuntimeAssetSet.Add(Path.GetFullPath(path))
        }
    }

    func Add(other: ReferenceResolutionResult) {
        for asset in other.RuntimeAssets {
            AddRuntimeAsset(asset)
        }
    }

    // One referenced project's output, once, by full path.
    func AddProjectOutput(path: string) {
        if string.IsNullOrWhiteSpace(path) {
            return
        }

        fullPath := Path.GetFullPath(path)
        for existing in ProjectOutputList {
            if string.Equals(existing, fullPath, StringComparison.OrdinalIgnoreCase) {
                return
            }
        }

        ProjectOutputList.Add(fullPath)
    }

    func CopyRuntimeAssets(outputDirectory: string) {
        assets := RuntimeAssets

        // A diamond dependency can restore two versions of the same assembly (for example a project
        // that pulls both Swashbuckle and Microsoft.AspNetCore.OpenApi resolves two Microsoft.OpenApi
        // versions). NuGet unifies such a conflict to the single highest version; mirror that here so
        // exactly one file per name is copied instead of failing on the runtime-asset name clash.
        destinations := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for asset in assets {
            fileName := Path.GetFileName(asset)
            existing := ""
            if destinations.TryGetValue(fileName, out existing) {
                if !string.Equals(existing, asset, StringComparison.OrdinalIgnoreCase) && PrefersReplacementRuntimeAsset(existing, asset) {
                    destinations[fileName] = asset
                }

                continue
            }

            destinations.Add(fileName, asset)
        }

        Directory.CreateDirectory(outputDirectory)

        for entry in destinations {
            asset := entry.Value
            destination := Path.Combine(outputDirectory, Path.GetFileName(asset))
            if string.Equals(Path.GetFullPath(asset), Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase) {
                continue
            }

            File.Copy(asset, destination, true)
        }
    }

    static func PrefersReplacementRuntimeAsset(existingAsset: string, candidateAsset: string): bool {
        return IsHigherVersion(ExtractRuntimeAssetVersion(candidateAsset), ExtractRuntimeAssetVersion(existingAsset))
    }

    // Recover a runtime asset's package version from the standard NuGet cache layout
    // (`<id>/<version>/lib/<tfm>/<file>`) by walking ancestor directories until one parses as a
    // version. An unrecognizable layout falls back to the default version so a parseable candidate
    // still wins.
    static func ExtractRuntimeAssetVersion(assetPath: string): Version {
        directory := Path.GetDirectoryName(assetPath)
        guard := 0
        while directory != null && directory.Length > 0 && guard < 32 {
            segment := Path.GetFileName(directory)
            parsedVersion := AssemblyVersionUtilities.DefaultAssemblyVersion
            if AssemblyVersionUtilities.TryGetAssemblyVersion(segment, out parsedVersion) {
                return parsedVersion
            }

            directory = Path.GetDirectoryName(directory)
            guard = guard + 1
        }

        return AssemblyVersionUtilities.DefaultAssemblyVersion
    }

    static func IsHigherVersion(candidate: Version, existing: Version): bool {
        if candidate.Major != existing.Major {
            return candidate.Major > existing.Major
        }

        if candidate.Minor != existing.Minor {
            return candidate.Minor > existing.Minor
        }

        if candidate.Build != existing.Build {
            return candidate.Build > existing.Build
        }

        return candidate.Revision > existing.Revision
    }

    func BuildRuntimeAssets(): string[] {
        assets := new string[](RuntimeAssetSet.Count)
        index := 0
        for asset in RuntimeAssetSet {
            assets[index] = asset
            index = index + 1
        }

        Array.Sort(assets, 0, index, StringComparer.OrdinalIgnoreCase)
        return assets
    }

    RuntimeAssetSet: HashSet<string> {
        get {
            if runtimeAssets == null {
                runtimeAssets = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            }

            return runtimeAssets
        }
    }

    ProjectOutputList: List<string> {
        get {
            if projectOutputs == null {
                projectOutputs = new List<string>()
            }

            return projectOutputs
        }
    }
}

class ResolutionContext {
    packagesRootValue: string
    packageAssetsValue: Dictionary<string, NuGetPackageAssets>?
    projectOutputsValue: Dictionary<string, ResolvedProjectReference>?
    activeProjectRootsValue: Stack<string>?

    // ONE RESOLUTION READS ONE PACKAGES FOLDER, decided when it begins. It used to be re-read from
    // `NUGET_PACKAGES` at every package the walk touched, so the only way to point a resolution at a
    // fixture cache was to rewrite that variable -- and the process environment is shared by every
    // thread in it. The compiler-service estate runs its test classes in parallel, and a resolver row
    // that did exactly that sent `ExternalAssemblyRuntimePairing`'s concurrent NuGet lookups into its
    // temporary cache, where `microsoft.build.framework` does not exist. The folder is state of the
    // resolution, so it lives here with the rest of it, and a project reference built inside this
    // resolution reads the same cache as the project that references it.
    constructor() {
        packagesRootValue = CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
            Environment.GetEnvironmentVariable("NUGET_PACKAGES"),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        )
    }

    // A named folder wins; null or blank falls back to NuGet's own rule, exactly as the parameterless
    // constructor decides it.
    constructor(packagesFolder: string?) {
        configuredPackagesFolder := packagesFolder
        if string.IsNullOrWhiteSpace(configuredPackagesFolder ?? "") {
            configuredPackagesFolder = Environment.GetEnvironmentVariable("NUGET_PACKAGES")
        }

        packagesRootValue = CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
            configuredPackagesFolder,
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        )
    }

    PackagesRoot: string {
        get {
            return packagesRootValue
        }
    }

    PackageAssets: Dictionary<string, NuGetPackageAssets> {
        get {
            if packageAssetsValue == null {
                packageAssetsValue = new Dictionary<string, NuGetPackageAssets>(StringComparer.OrdinalIgnoreCase)
            }

            return packageAssetsValue
        }
    }

    ProjectOutputs: Dictionary<string, ResolvedProjectReference> {
        get {
            if projectOutputsValue == null {
                projectOutputsValue = new Dictionary<string, ResolvedProjectReference>(StringComparer.OrdinalIgnoreCase)
            }

            return projectOutputsValue
        }
    }

    ActiveProjectRoots: Stack<string> {
        get {
            if activeProjectRootsValue == null {
                activeProjectRootsValue = new Stack<string>()
            }

            return activeProjectRootsValue
        }
    }
}

class ResolvedProjectReference {
    OutputAssemblyPath: string
    References: ReferenceResolutionResult

    constructor(OutputAssemblyPath: string, References: ReferenceResolutionResult) {
        this.OutputAssemblyPath = OutputAssemblyPath
        this.References = References
    }
}

class ReferenceTypeFilterScratch {
    TypeRanks: int[]
    ResultIndices: int[]

    func EnsureCapacity(referenceCount: int) {
        EnsureInitialized()
        if TypeRanks.Length != referenceCount {
            TypeRanks = new int[](referenceCount)
        }

        if ResultIndices.Length != referenceCount {
            ResultIndices = new int[](referenceCount)
        }
    }

    func EnsureInitialized() {
        if TypeRanks != null {
            return
        }

        TypeRanks = new int[](0)
        ResultIndices = new int[](0)
    }
}

class NuGetPackageAssets {
    compileAssembliesValue: HashSet<string>?
    runtimeAssembliesValue: HashSet<string>?

    CompileAssemblies: HashSet<string> {
        get {
            if compileAssembliesValue == null {
                compileAssembliesValue = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            }

            return compileAssembliesValue
        }
    }

    RuntimeAssemblies: HashSet<string> {
        get {
            if runtimeAssembliesValue == null {
                runtimeAssembliesValue = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            }

            return runtimeAssembliesValue
        }
    }

    func Add(other: NuGetPackageAssets) {
        for assembly in other.CompileAssemblies {
            CompileAssemblies.Add(assembly)
        }

        for assembly in other.RuntimeAssemblies {
            RuntimeAssemblies.Add(assembly)
        }
    }
}

class PackageIdentity {
    Id: string?
    Version: string?

    constructor(Id: string?, Version: string?) {
        this.Id = Id
        this.Version = Version
    }
}

class PackageDependency {
    Id: string
    Version: string?

    constructor(Id: string, Version: string?) {
        this.Id = Id
        this.Version = Version
    }
}

// One occurrence of a package id in the dependency graph, with its DISTANCE from the project.
// A declared `nuget:` entry is at distance zero; everything a package brings with it is one
// further out. The distance is the whole of NuGet's nearest-wins rule.
class PackageResolutionNode {
    Id: string
    Version: string?
    Depth: int

    constructor(Id: string, Version: string?, Depth: int) {
        this.Id = Id
        this.Version = Version
        this.Depth = Depth
    }
}

class ImplicitTestDependencyPlan {
    ShouldAdd: bool
    PackageName: string
    Version: string

    constructor(ShouldAdd: bool, PackageName: string, Version: string) {
        this.ShouldAdd = ShouldAdd
        this.PackageName = PackageName
        this.Version = Version
    }
}

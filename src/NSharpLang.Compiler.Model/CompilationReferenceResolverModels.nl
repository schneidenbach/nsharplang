namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Text.Json
import System.Threading
import NSharpLang.Compiler

class ReferenceResolutionOptions {
    configurationValue: string
    includeTestsValue: bool
    buildProjectReferencesValue: bool
    quietValue: bool
    aotModeValue: bool
    useBuiltProjectReferencesValue: bool
    packagesFolderValue: string?
    testSourcesPresentValue: bool?
    workspaceContextValue: ResolutionContext?

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

    // Workspace checks pass the owning member's already-filtered test-file fact so reference
    // resolution does not walk a parent's child projects a second time.
    TestSourcesPresent: bool? {
        get {
            return testSourcesPresentValue
        }
        set {
            testSourcesPresentValue = value
        }
    }

    // Workspace checks assign one shared resolver context to each member's options. Ordinary
    // single-project checks leave this empty and get a fresh context for their own resolution.
    WorkspaceContext: ResolutionContext? {
        get {
            return workspaceContextValue
        }
        set {
            workspaceContextValue = value
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
    packageFiles: List<PackageRuntimeFile>?
    packageFileKeys: HashSet<string>?
    compileReferences: List<string>?
    compileReferenceKeys: HashSet<string>?
    contentRoots: SortedDictionary<string, string>?

    // EVERY PROJECT THIS PROJECT REFERENCES, TRANSITIVELY: the output assembly of each `project:`
    // reference and of each of ITS project references, in the order they were first reached. A project
    // compiles against all of them, as MSBuild's transitive `ProjectReference` does -- a type of C that
    // A names through A -> B -> C is a type A's compilation must be able to see, not only a file copied
    // beside A's output.
    ProjectOutputAssemblies: IReadOnlyList<string> => ProjectOutputList

    RuntimeAssets: IReadOnlyList<string> => BuildRuntimeAssets()

    // EVERY FILE A RESTORED PACKAGE CONTRIBUTES AT RUN TIME, with the package that owns it: the
    // portable `lib/<tfm>` assemblies and the RID-specific `runtimes/<rid>/native` and
    // `runtimes/<rid>/lib/<tfm>` files. `RuntimeAssets` is the flat managed set the build copies;
    // this is what the copy of the `runtimes/` layout and the `deps.json` read.
    PackageFiles: IReadOnlyList<PackageRuntimeFile> => PackageFileList

    // THE COMPILE-TIME ASSEMBLIES OF EVERY PACKAGE THIS PROJECT REACHES, its project references'
    // included. A project that references another compiles against the packages the other one
    // depends on, as MSBuild's transitive `PackageReference` flow does.
    CompileReferences: IReadOnlyList<string> => CompileReferenceList

    ContentRoots: IReadOnlyDictionary<string, string> => ContentRootMap

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

        for packageFile in other.PackageFiles {
            AddPackageFile(packageFile)
        }

        for compileReference in other.CompileReferences {
            AddCompileReference(compileReference)
        }

        for contentRoot in other.ContentRoots {
            AddContentRoot(contentRoot.Key, contentRoot.Value)
        }
    }

    // THE CONTENT ROOT OF A HOSTED APPLICATION: its assembly's full name -> its project directory.
    // `WebApplicationFactory<TEntryPoint>` reads `MvcTestingAppManifest.json` in the test output
    // directory to find the application's content root; Microsoft.AspNetCore.Mvc.Testing's MSBuild
    // targets write that file from the test project's `ProjectReference`s, and `CopyRuntimeAssets`
    // writes it from the same facts.
    func AddContentRoot(assemblyFullName: string, projectDirectory: string) {
        ContentRootMap[assemblyFullName] = Path.GetFullPath(projectDirectory)
    }

    func AddPackageFile(packageFile: PackageRuntimeFile) {
        if PackageFileKeySet.Add(Path.GetFullPath(packageFile.SourcePath)) {
            PackageFileList.Add(packageFile)
        }
    }

    func AddCompileReference(path: string) {
        if string.IsNullOrWhiteSpace(path) || !File.Exists(path) {
            return
        }

        fullPath := Path.GetFullPath(path)
        if CompileReferenceKeySet.Add(fullPath) {
            CompileReferenceList.Add(fullPath)
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

    // THE FLAT MANAGED SET THE BUILD COPIES, one file per name. A diamond dependency can restore two
    // versions of the same assembly (for example a project that pulls both Swashbuckle and
    // Microsoft.AspNetCore.OpenApi resolves two Microsoft.OpenApi versions). NuGet unifies such a
    // conflict to the single highest version; mirror that here so exactly one file per name is
    // copied instead of failing on the runtime-asset name clash. The copy and the `deps.json` both
    // read this, so the manifest names exactly the files that were copied.
    func SelectFlatRuntimeAssets(): Dictionary<string, string> {
        destinations := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for asset in RuntimeAssets {
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

        return destinations
    }

    // THE `runtimes/<rid>/...` FILES THE BUILD COPIES, one per package-relative path (the highest
    // package version wins a conflict, as above). They keep their layout under the output directory
    // because the host resolves them through `deps.json` `runtimeTargets` rows by that path.
    func SelectRuntimeTargetFiles(): List<PackageRuntimeFile> {
        byPath := new Dictionary<string, PackageRuntimeFile>(StringComparer.OrdinalIgnoreCase)
        for packageFile in PackageFileList {
            if packageFile.Rid == null {
                continue
            }

            let existing: PackageRuntimeFile? = null
            if byPath.TryGetValue(packageFile.RelativePath, out existing) && existing != null {
                if PrefersReplacementRuntimeAsset(existing.SourcePath, packageFile.SourcePath) {
                    byPath[packageFile.RelativePath] = packageFile
                }

                continue
            }

            byPath[packageFile.RelativePath] = packageFile
        }

        paths := new string[](byPath.Count)
        pathIndex := 0
        for entry in byPath {
            paths[pathIndex] = entry.Key
            pathIndex = pathIndex + 1
        }

        Array.Sort(paths, StringComparer.OrdinalIgnoreCase)
        selected := new List<PackageRuntimeFile>()
        for path in paths {
            selected.Add(byPath[path])
        }

        return selected
    }

    func CopyRuntimeAssets(outputDirectory: string) {
        Directory.CreateDirectory(outputDirectory)

        for entry in SelectFlatRuntimeAssets() {
            CopyIfChanged(entry.Value, Path.Combine(outputDirectory, Path.GetFileName(entry.Value)))
        }

        for runtimeTarget in SelectRuntimeTargetFiles() {
            CopyIfChanged(runtimeTarget.SourcePath, Path.Combine(outputDirectory, runtimeTarget.RelativePath))
        }

        if ContentRootMap.Count > 0 {
            manifestPath := Path.Combine(outputDirectory, "MvcTestingAppManifest.json")
            manifest := JsonSerializer.Serialize(ContentRootMap, new JsonSerializerOptions { WriteIndented: true }) + Environment.NewLine
            if !File.Exists(manifestPath) || File.ReadAllText(manifestPath) != manifest {
                File.WriteAllText(manifestPath, manifest)
            }
        }
    }

    static func CopyIfChanged(source: string, destination: string) {
        if string.Equals(Path.GetFullPath(source), Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase) {
            return
        }

        parent := Path.GetDirectoryName(destination)
        if parent != null && parent.Length > 0 {
            Directory.CreateDirectory(parent)
        }

        File.Copy(source, destination, true)
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

    ContentRootMap: SortedDictionary<string, string> {
        get {
            if contentRoots == null {
                contentRoots = new SortedDictionary<string, string>(StringComparer.Ordinal)
            }

            return contentRoots
        }
    }

    PackageFileList: List<PackageRuntimeFile> {
        get {
            if packageFiles == null {
                packageFiles = new List<PackageRuntimeFile>()
            }

            return packageFiles
        }
    }

    PackageFileKeySet: HashSet<string> {
        get {
            if packageFileKeys == null {
                packageFileKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            }

            return packageFileKeys
        }
    }

    CompileReferenceList: List<string> {
        get {
            if compileReferences == null {
                compileReferences = new List<string>()
            }

            return compileReferences
        }
    }

    CompileReferenceKeySet: HashSet<string> {
        get {
            if compileReferenceKeys == null {
                compileReferenceKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            }

            return compileReferenceKeys
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
    private readonly resolutionGateValue: SemaphoreSlim
    packageAssetsValue: Dictionary<string, NuGetPackageAssets>?
    projectOutputsValue: Dictionary<string, ResolvedProjectReference>?
    projectFailuresValue: Dictionary<string, string>?
    activeProjectRootsValue: Stack<string>?
    cacheProjectFailuresValue: bool
    compilesConcurrentlyValue: bool

    // ONE RESOLUTION READS ONE PACKAGES FOLDER, decided when it begins. It used to be re-read from
    // `NUGET_PACKAGES` at every package the walk touched, so the only way to point a resolution at a
    // fixture cache was to rewrite that variable -- and the process environment is shared by every
    // thread in it. The compiler-service estate runs its test classes in parallel, and a resolver row
    // that did exactly that sent `ExternalAssemblyRuntimePairing`'s concurrent NuGet lookups into its
    // temporary cache, where `microsoft.build.framework` does not exist. The folder is state of the
    // resolution, so it lives here with the rest of it, and a project reference built inside this
    // resolution reads the same cache as the project that references it.
    constructor() {
        resolutionGateValue = new SemaphoreSlim(1, 1)
        packagesRootValue = CompilationReferenceResolverKernels.GetGlobalPackagesFolder(
            Environment.GetEnvironmentVariable("NUGET_PACKAGES"),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        )
    }

    // A named folder wins; null or blank falls back to NuGet's own rule, exactly as the parameterless
    // constructor decides it.
    constructor(packagesFolder: string?) {
        resolutionGateValue = new SemaphoreSlim(1, 1)
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

    // Workspace checks share the package-asset and project-output caches through one context. The
    // resolver holds this gate while mutating them; analysis of each member remains parallel.
    ResolutionGate: SemaphoreSlim => resolutionGateValue

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

    ProjectFailures: Dictionary<string, string> {
        get {
            if projectFailuresValue == null {
                projectFailuresValue = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            }

            return projectFailuresValue
        }
    }

    CacheProjectFailures: bool {
        get {
            return cacheProjectFailuresValue
        }
        set {
            cacheProjectFailuresValue = value
        }
    }

    // WHETHER THE CALLER ALREADY RUNS ITS COMPILATIONS CONCURRENTLY (a workspace `nlc check`). A
    // project reference built inside such a resolution analyses on one worker, as the workspace's own
    // members do (`CodeIntelligenceService.LoadWorkspaceProjectIncludingTests`): one pool is not nested
    // inside the other.
    CompilesConcurrently: bool {
        get {
            return compilesConcurrentlyValue
        }
        set {
            compilesConcurrentlyValue = value
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
    runtimeFilesValue: List<PackageRuntimeFile>?
    runtimeFileKeysValue: HashSet<string>?

    // Every run-time file of this package and of the packages it reaches, with its owner.
    RuntimeFiles: IReadOnlyList<PackageRuntimeFile> {
        get {
            return RuntimeFileList
        }
    }

    RuntimeFileList: List<PackageRuntimeFile> {
        get {
            if runtimeFilesValue == null {
                runtimeFilesValue = new List<PackageRuntimeFile>()
            }

            return runtimeFilesValue
        }
    }

    RuntimeFileKeys: HashSet<string> {
        get {
            if runtimeFileKeysValue == null {
                runtimeFileKeysValue = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            }

            return runtimeFileKeysValue
        }
    }

    func AddRuntimeFile(file: PackageRuntimeFile) {
        if RuntimeFileKeys.Add(file.SourcePath) {
            RuntimeFileList.Add(file)
        }
    }

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

        for file in other.RuntimeFiles {
            AddRuntimeFile(file)
        }
    }
}

// ONE FILE A RESTORED PACKAGE CONTRIBUTES AT RUN TIME. `Rid` is null for a portable `lib/<tfm>`
// assembly and names the runtime identifier for a `runtimes/<rid>/native` file (`AssetType`
// `native`) or a `runtimes/<rid>/lib/<tfm>` assembly (`AssetType` `runtime`).
// `RelativePath` is the path under the package's version directory with `/` separators.
class PackageRuntimeFile {
    PackageId: string
    PackageVersion: string
    PackageDirectory: string
    SourcePath: string
    RelativePath: string
    Rid: string?
    AssetType: string

    constructor(PackageId: string, PackageVersion: string, PackageDirectory: string, SourcePath: string, RelativePath: string, Rid: string?, AssetType: string) {
        this.PackageId = PackageId
        this.PackageVersion = PackageVersion
        this.PackageDirectory = PackageDirectory
        this.SourcePath = SourcePath
        this.RelativePath = RelativePath
        this.Rid = Rid
        this.AssetType = AssetType
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

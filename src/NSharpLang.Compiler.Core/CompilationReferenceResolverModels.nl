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

    RuntimeAssets: IReadOnlyList<string> => BuildRuntimeAssets()

    static func Create(projectRoot: string, dependencies: IReadOnlyList<Reference>?): ReferenceResolutionResult {
        result := new ReferenceResolutionResult()
        paths := ExternalAssemblyScan.ResolveRuntimeAssetPaths(projectRoot, dependencies)

        index := 0
        while index < paths.Count {
            result.AddRuntimeAsset(paths[index])
            index = index + 1
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
        if candidate.get_Major() != existing.get_Major() {
            return candidate.get_Major() > existing.get_Major()
        }

        if candidate.get_Minor() != existing.get_Minor() {
            return candidate.get_Minor() > existing.get_Minor()
        }

        if candidate.get_Build() != existing.get_Build() {
            return candidate.get_Build() > existing.get_Build()
        }

        return candidate.get_Revision() > existing.get_Revision()
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
}

class ResolutionContext {
    packageAssetsValue: Dictionary<string, NuGetPackageAssets>?
    projectOutputsValue: Dictionary<string, ResolvedProjectReference>?
    activeProjectRootsValue: Stack<string>?

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

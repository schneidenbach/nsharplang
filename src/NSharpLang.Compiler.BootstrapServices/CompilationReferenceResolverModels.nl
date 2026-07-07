namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO

public class ReferenceResolutionOptions {
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
        get { return configurationValue }
        set { configurationValue = value }
    }

    IncludeTests: bool {
        get { return includeTestsValue }
        set { includeTestsValue = value }
    }

    BuildProjectReferences: bool {
        get { return buildProjectReferencesValue }
        set { buildProjectReferencesValue = value }
    }

    Quiet: bool {
        get { return quietValue }
        set { quietValue = value }
    }

    AotMode: bool {
        get { return aotModeValue }
        set { aotModeValue = value }
    }

    constructor(Configuration: string, IncludeTests: bool, BuildProjectReferences: bool, Quiet: bool, AotMode: bool) {
        configurationValue = Configuration
        includeTestsValue = IncludeTests
        buildProjectReferencesValue = BuildProjectReferences
        quietValue = Quiet
        aotModeValue = AotMode
    }
}

public class ReferenceResolutionResult {
    runtimeAssets: HashSet<string>?

    RuntimeAssets: IReadOnlyList<string> => BuildRuntimeAssets()

    public func AddRuntimeAsset(path: string) {
        if !string.IsNullOrWhiteSpace(path) && File.Exists(path) {
            RuntimeAssetSet.Add(Path.GetFullPath(path))
        }
    }

    public func Add(other: ReferenceResolutionResult) {
        foreach asset in other.RuntimeAssets {
            AddRuntimeAsset(asset)
        }
    }

    public func CopyRuntimeAssets(outputDirectory: string) {
        Directory.CreateDirectory(outputDirectory)

        foreach asset in RuntimeAssets {
            destination := Path.Combine(outputDirectory, Path.GetFileName(asset))
            if string.Equals(Path.GetFullPath(asset), Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase) {
                continue
            }

            File.Copy(asset, destination, true)
        }
    }

    func BuildRuntimeAssets(): string[] {
        assets := new string[](RuntimeAssetSet.Count)
        index := 0
        foreach asset in RuntimeAssetSet {
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

public class ResolutionContext {
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

public class ResolvedProjectReference {
    OutputAssemblyPath: string
    References: ReferenceResolutionResult

    constructor(OutputAssemblyPath: string, References: ReferenceResolutionResult) {
        this.OutputAssemblyPath = OutputAssemblyPath
        this.References = References
    }
}

public class ReferenceTypeFilterScratch {
    TypeRanks: int[]
    ResultIndices: int[]

    public func EnsureCapacity(referenceCount: int) {
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

public class SharedFrameworkCandidateScratch {
    MajorVersions: int[]
    MinorVersions: int[]
    BuildVersions: int[]
    RevisionVersions: int[]

    public func EnsureCapacity(candidateCount: int) {
        EnsureInitialized()
        if MajorVersions.Length >= candidateCount {
            return
        }

        MajorVersions = new int[](candidateCount)
        MinorVersions = new int[](candidateCount)
        BuildVersions = new int[](candidateCount)
        RevisionVersions = new int[](candidateCount)
    }

    func EnsureInitialized() {
        if MajorVersions != null {
            return
        }

        MajorVersions = new int[](0)
        MinorVersions = new int[](0)
        BuildVersions = new int[](0)
        RevisionVersions = new int[](0)
    }
}

public class NuGetPackageAssets {
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

    public func Add(other: NuGetPackageAssets) {
        foreach assembly in other.CompileAssemblies {
            CompileAssemblies.Add(assembly)
        }

        foreach assembly in other.RuntimeAssemblies {
            RuntimeAssemblies.Add(assembly)
        }
    }
}

public class PackageIdentity {
    Id: string?
    Version: string?

    constructor(Id: string?, Version: string?) {
        this.Id = Id
        this.Version = Version
    }
}

public class PackageDependency {
    Id: string
    Version: string?

    constructor(Id: string, Version: string?) {
        this.Id = Id
        this.Version = Version
    }
}

public class FrameworkCandidate {
    Directory: string
    Version: Version

    constructor(Directory: string, Version: Version) {
        this.Directory = Directory
        this.Version = Version
    }
}

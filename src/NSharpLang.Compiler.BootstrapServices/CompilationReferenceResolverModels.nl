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

    constructor() {
        configurationValue = "Debug"
        includeTestsValue = false
        buildProjectReferencesValue = true
        quietValue = false
        aotModeValue = false
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
    runtimeAssets: HashSet<string> = new HashSet<string>(StringComparer.OrdinalIgnoreCase)

    RuntimeAssets: IReadOnlyList<string> => BuildRuntimeAssets()

    public func AddRuntimeAsset(path: string) {
        if !string.IsNullOrWhiteSpace(path) && File.Exists(path) {
            runtimeAssets.Add(Path.GetFullPath(path))
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
        assets := new string[](runtimeAssets.Count)
        index := 0
        foreach asset in runtimeAssets {
            assets[index] = asset
            index = index + 1
        }

        Array.Sort(assets, 0, index, StringComparer.OrdinalIgnoreCase)
        return assets
    }
}

public class ResolutionContext {
    PackageAssets: Dictionary<string, NuGetPackageAssets> = new Dictionary<string, NuGetPackageAssets>(StringComparer.OrdinalIgnoreCase)
    ProjectOutputs: Dictionary<string, ResolvedProjectReference> = new Dictionary<string, ResolvedProjectReference>(StringComparer.OrdinalIgnoreCase)
    ActiveProjectRoots: Stack<string> = new Stack<string>()
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
    TypeRanks: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)

    public func EnsureCapacity(referenceCount: int) {
        if TypeRanks.Length != referenceCount {
            TypeRanks = new int[](referenceCount)
        }

        if ResultIndices.Length != referenceCount {
            ResultIndices = new int[](referenceCount)
        }
    }
}

public class SharedFrameworkCandidateScratch {
    MajorVersions: int[] = new int[](0)
    MinorVersions: int[] = new int[](0)
    BuildVersions: int[] = new int[](0)
    RevisionVersions: int[] = new int[](0)

    public func EnsureCapacity(candidateCount: int) {
        if MajorVersions.Length >= candidateCount {
            return
        }

        MajorVersions = new int[](candidateCount)
        MinorVersions = new int[](candidateCount)
        BuildVersions = new int[](candidateCount)
        RevisionVersions = new int[](candidateCount)
    }
}

public class NuGetPackageAssets {
    CompileAssemblies: HashSet<string> = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    RuntimeAssemblies: HashSet<string> = new HashSet<string>(StringComparer.OrdinalIgnoreCase)

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

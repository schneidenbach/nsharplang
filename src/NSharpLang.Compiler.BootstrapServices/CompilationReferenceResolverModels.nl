namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO

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

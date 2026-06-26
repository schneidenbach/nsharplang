namespace NSharpLang.Cli

import System
import System.Collections.Generic

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

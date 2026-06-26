namespace NSharpLang.Cli

import System
import System.IO

public class NSharpInstallRoot {
    public static DefaultFeedValue: string => "%HOME%/.nsharp/packages"
    public static InstallRootFeedValue: string => "%NSHARP_INSTALL_DIR%/packages"
    public static InstallDirEnvironmentVariable: string => "NSHARP_INSTALL_DIR"

    public static func Resolve(): string {
        return Resolve(
            AppContext.BaseDirectory,
            Environment.GetEnvironmentVariable(NSharpInstallRoot.InstallDirEnvironmentVariable),
            DefaultInstallRoot())
    }

    public static func Resolve(baseDirectory: string, installDirOverride: string?, defaultInstallRoot: string): string {
        if !string.IsNullOrWhiteSpace(installDirOverride ?? "") {
            return NormalizeDirectory(installDirOverride ?? "")
        }

        hostDirectory := NormalizeDirectory(baseDirectory)
        libDirectory := Path.GetDirectoryName(hostDirectory)
        root: string? = null
        if libDirectory != null {
            root = Path.GetDirectoryName(libDirectory)
        }

        if root != null
            && libDirectory != null
            && string.Equals(Path.GetFileName(libDirectory), "lib", StringComparison.OrdinalIgnoreCase)
            && Directory.Exists(Path.Combine(root, "bin"))
            && Directory.Exists(Path.Combine(root, "packages")) {
            return root
        }

        return NormalizeDirectory(defaultInstallRoot)
    }

    public static func PackagesDirectory(): string {
        return PackagesDirectory(Resolve())
    }

    public static func PackagesDirectory(installRoot: string): string {
        return Path.Combine(installRoot, "packages")
    }

    public static func ProjectFeedValue(): string {
        return ProjectFeedValue(
            AppContext.BaseDirectory,
            Environment.GetEnvironmentVariable(NSharpInstallRoot.InstallDirEnvironmentVariable),
            DefaultInstallRoot())
    }

    public static func ProjectFeedValue(baseDirectory: string, installDirOverride: string?, defaultInstallRoot: string): string {
        if !string.IsNullOrWhiteSpace(installDirOverride ?? "") {
            return NSharpInstallRoot.InstallRootFeedValue
        }

        return ProjectFeedValue(Resolve(baseDirectory, installDirOverride, defaultInstallRoot), defaultInstallRoot)
    }

    public static func ProjectFeedValue(installRoot: string, defaultInstallRoot: string): string {
        if PathsEqual(installRoot, defaultInstallRoot) {
            return NSharpInstallRoot.DefaultFeedValue
        }

        return PackagesDirectory(NormalizeDirectory(installRoot))
    }

    public static func DefaultInstallRoot(): string {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nsharp")
    }

    static func NormalizeDirectory(path: string): string {
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path))
    }

    static func PathsEqual(left: string, right: string): bool {
        comparison := StringComparison.Ordinal
        if OperatingSystem.IsWindows() {
            comparison = StringComparison.OrdinalIgnoreCase
        }

        return string.Equals(
            NormalizeDirectory(left),
            NormalizeDirectory(right),
            comparison)
    }
}

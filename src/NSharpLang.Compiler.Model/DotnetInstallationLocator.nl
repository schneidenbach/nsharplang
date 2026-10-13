namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Runtime.InteropServices

// Locates the installed .NET shared frameworks when the compiler runs as NativeAOT. In that host,
// RuntimeEnvironment.GetRuntimeDirectory() points at the native executable's directory, which does
// not contain the framework metadata assemblies that analysis must read. The CLI front door and
// compiler metadata resolver share this installation lookup so they use the same .NET root rules.
static class DotnetInstallationLocator {
    static func FindRoot(): string? {
        isWindows := OperatingSystem.IsWindows()
        architectureVariable := ArchitectureRootVariable(RuntimeInformation.ProcessArchitecture.ToString())
        architectureRoot: string? = null
        if architectureVariable != null {
            architectureRoot = Environment.GetEnvironmentVariable(architectureVariable)
        }

        candidates := GetRootCandidates(
            architectureRoot,
            Environment.GetEnvironmentVariable("DOTNET_ROOT"),
            FindDotnetOnPath(isWindows),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            isWindows,
            Environment.GetEnvironmentVariable("ProgramFiles"),
            Environment.GetEnvironmentVariable("ProgramFiles(x86)")
        )
        for candidate in candidates {
            if IsUsableRoot(candidate, isWindows) {
                return Path.TrimEndingDirectorySeparator(Path.GetFullPath(candidate))
            }
        }

        return null
    }

    static func SharedRootCandidates(runtimeDirectory: string?): string[] {
        installedRoot: string? = null
        if AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory(runtimeDirectory) == null {
            installedRoot = FindRoot()
        }
        return CompilationReferenceResolverKernels.GetDotnetSharedRootCandidates(runtimeDirectory, installedRoot)
    }

    static func ArchitectureRootVariable(architecture: string): string? {
        if architecture == "Arm64" {
            return "DOTNET_ROOT_ARM64"
        }
        if architecture == "X64" {
            return "DOTNET_ROOT_X64"
        }
        if architecture == "X86" {
            return "DOTNET_ROOT_X86"
        }
        return null
    }

    static func ExecutableName(isWindows: bool): string {
        if isWindows {
            return "dotnet.exe"
        }
        return "dotnet"
    }

    static func GetRootCandidates(architectureRoot: string?, dotnetRoot: string?, dotnetOnPath: string?, home: string?, isWindows: bool, programFiles: string?, programFilesX86: string?): List<string> {
        candidates := new List<string>()
        AddCandidate(candidates, architectureRoot)
        AddCandidate(candidates, dotnetRoot)
        if dotnetOnPath != null && dotnetOnPath.Length > 0 {
            binDirectory := Path.GetDirectoryName(dotnetOnPath)
            if binDirectory != null && binDirectory.Length > 0 {
                AddCandidate(candidates, binDirectory)
                parent := Path.GetDirectoryName(binDirectory)
                if parent != null && parent.Length > 0 {
                    if !isWindows {
                        AddCandidate(candidates, Path.Combine(parent, "libexec"))
                    }
                    AddCandidate(candidates, parent)
                }
            }
        }

        if home != null && home.Length > 0 {
            AddCandidate(candidates, Path.Combine(home, ".dotnet"))
        }

        if isWindows {
            if programFiles != null && programFiles.Length > 0 {
                AddCandidate(candidates, Path.Combine(programFiles, "dotnet"))
            }
            if programFilesX86 != null && programFilesX86.Length > 0 {
                AddCandidate(candidates, Path.Combine(programFilesX86, "dotnet"))
            }
        } else {
            AddCandidate(candidates, "/opt/homebrew/opt/dotnet/libexec")
            AddCandidate(candidates, "/usr/local/opt/dotnet/libexec")
            AddCandidate(candidates, "/usr/local/share/dotnet")
            AddCandidate(candidates, "/usr/share/dotnet")
        }

        return candidates
    }

    static func HasRequiredRuntime(runtimeVersions: string[]): bool {
        for version in runtimeVersions {
            if version.StartsWith("10.", StringComparison.Ordinal) {
                return true
            }
        }
        return false
    }

    static func IsUsableRoot(candidate: string, isWindows: bool): bool {
        if !File.Exists(Path.Combine(candidate, ExecutableName(isWindows))) {
            return false
        }

        runtimeRoot := Path.Combine(Path.Combine(candidate, "shared"), "Microsoft.NETCore.App")
        if !Directory.Exists(runtimeRoot) {
            return false
        }

        directories := Directory.GetDirectories(runtimeRoot)
        names := new string[](directories.Length)
        index := 0
        while index < directories.Length {
            names[index] = Path.GetFileName(directories[index])
            index = index + 1
        }
        return HasRequiredRuntime(names)
    }

    static func FindDotnetOnPath(isWindows: bool): string? {
        pathValue := Environment.GetEnvironmentVariable("PATH")
        if pathValue == null || pathValue.Length == 0 {
            return null
        }

        executableName := ExecutableName(isWindows)
        for entry in pathValue.Split(Path.PathSeparator) {
            if entry.Length == 0 {
                continue
            }

            candidate := Path.Combine(entry, executableName)
            if File.Exists(candidate) {
                return ResolveFinalPath(Path.GetFullPath(candidate))
            }
        }
        return null
    }

    static func ResolveFinalPath(path: string): string {
        try {
            target := File.ResolveLinkTarget(path, true)
            if target != null {
                return target.FullName
            }
        } catch {
            return path
        }
        return path
    }

    private static func AddCandidate(candidates: List<string>, candidate: string?) {
        if candidate == null || candidate.Length == 0 {
            return
        }
        if !candidates.Contains(candidate) {
            candidates.Add(candidate)
        }
    }
}

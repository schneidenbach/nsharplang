namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.IO

// Which directory's server a command talks to. The rule is `DaemonExecKernels.ResolveWorkspaceRoot`;
// this owner only answers the two filesystem questions it asks.
class DaemonWorkspace {

    // The workspace the router sends a command to, or null when the directory belongs to no
    // workspace (no `.git`, no `project.yml` above it) and the command should simply run in-process.
    static func ResolveForRouting(startDirectory: string): string? {
        return DaemonExecKernels.ResolveWorkspaceRoot(
            Path.GetFullPath(startDirectory),
            directory => HasGitMarker(directory),
            directory => HasProjectFile(directory),
            true
        )
    }

    // The workspace `nlc daemon start|stop|status` acts on: the same rule, falling back to the
    // directory itself so an explicit request always has an answer.
    static func Resolve(startDirectory: string): string {
        resolved := DaemonExecKernels.ResolveWorkspaceRoot(
            Path.GetFullPath(startDirectory),
            directory => HasGitMarker(directory),
            directory => HasProjectFile(directory),
            false
        )
        return resolved ?? Path.GetFullPath(startDirectory)
    }

    static func HasGitMarker(directory: string): bool {
        marker := Path.Combine(directory, ".git")
        return Directory.Exists(marker) || File.Exists(marker)
    }

    static func HasProjectFile(directory: string): bool {
        return File.Exists(Path.Combine(directory, "project.yml"))
    }
}

// The build identity a client and a server must share. See `DaemonExecKernels.ComposeIdentitySource`
// for what it covers and why.
class DaemonBuildIdentity {
    private static cliVersion: string?

    // The CLI pipeline records its version once, first thing, so code with no version in hand (the
    // query client) can still name the build it is.
    static func SetCliVersion(version: string) {
        DaemonBuildIdentity.cliVersion = version
    }

    static func Current(): string {
        return Compute(DaemonBuildIdentity.cliVersion ?? "unknown")
    }

    static func Compute(version: string): string {
        baseDirectory := AppContext.BaseDirectory
        return DaemonExecKernels.HashIdentity(DaemonExecKernels.ComposeIdentitySource(
            version,
            baseDirectory,
            Environment.Version.ToString(),
            GetAssemblyFacts(baseDirectory),
            GetRuntimeVariables()
        ))
    }

    static func GetAssemblyFacts(baseDirectory: string): string[] {
        files := Directory.GetFiles(baseDirectory, "*.dll")
        Array.Sort(files, StringComparer.Ordinal)
        facts := new string[](files.Length)
        index := 0
        while index < files.Length {
            info := new FileInfo(files[index])
            facts[index] = info.Name + "|" + info.Length.ToString() + "|" + info.LastWriteTimeUtc.Ticks.ToString()
            index = index + 1
        }

        return facts
    }

    static func GetRuntimeVariables(): string[] {
        variables := new List<string>()
        for name in DaemonProcessEnvironment.GetNames() {
            if DaemonExecKernels.IsRuntimeConfigurationVariable(name) {
                variables.Add(name + "=" + (Environment.GetEnvironmentVariable(name) ?? ""))
            }
        }

        return variables.ToArray()
    }
}

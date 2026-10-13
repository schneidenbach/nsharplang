namespace NSharpLang.Cli

import System
import System.Collections
import System.Collections.Generic
import System.IO

// THE OPTIONAL MANAGED-HOST HANDOFF'S DECISIONS.
//
// Normal NativeAOT, JIT, and ReadyToRun invocations enter the compiler pipeline directly. The
// explicit `NSHARP_FRONT_DOOR=1` path remains for launcher-contract checks and starts a separately
// built managed host; `FrontDoor` performs that handoff. The compiler's NativeAOT path is being
// brought up in this worktree, so this helper must not be used as a compiler fallback.
//
// Everything here is a pure answer so the estate can pin it; `FrontDoor` performs the I/O.
class FrontDoorKernels {

    // Forces the front-door path in a JIT process, so its hand-off can be exercised by tests and
    // diagnosed on machines without a NativeAOT build. The host never sees it (see
    // `BuildHostEnvironment`), so a forced front door cannot hand off to itself.
    static func ForceEnvironmentVariableName(): string {
        return "NSHARP_FRONT_DOOR"
    }

    static func IsForced(setting: string?): bool {
        if setting == null {
            return false
        }

        return setting == "1" || string.Equals(setting, "true", StringComparison.OrdinalIgnoreCase)
    }

    static func HostAssemblyFileName(): string {
        return "Cli.dll"
    }

    static func GetArchitectureRootVariable(architecture: string): string? {
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

    static func GetDotnetExecutableName(isWindows: bool): string {
        if isWindows {
            return "dotnet.exe"
        }
        return "dotnet"
    }

    // `nlc`, `nlc help`/`--help`/`-h` (29) and `nlc --version`/`-v` (30) print text that depends on
    // nothing but the version, which the entry point hands over. Every other command — including an
    // unknown one, whose error text the host owns — runs in the host.
    static func AnswersInFrontDoor(commandKind: int): bool {
        return commandKind == 29 || commandKind == 30
    }

    // The front door sits either beside the host (`lib/nlc/nlc`, reached from `bin/nlc` through a
    // symlink) or in `bin/` of the toolset (a copy, where symlinks are unavailable). `directories`
    // are the directories the running executable is known by, most specific first.
    static func GetHostAssemblyCandidates(directories: List<string>): List<string> {
        candidates := new List<string>()
        for directory in directories {
            AddDistinct(candidates, Path.Combine(directory, FrontDoorKernels.HostAssemblyFileName()))
        }

        for directory in directories {
            parent := Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(directory))
            if parent != null && parent.Length > 0 {
                AddDistinct(candidates, Path.Combine(Path.Combine(Path.Combine(parent, "lib"), "nlc"), FrontDoorKernels.HostAssemblyFileName()))
            }
        }

        return candidates
    }

    // `dotnet <host> <args...>`: argv[0] is the muxer itself, as a shell would pass it.
    static func BuildHostArgumentVector(dotnetExecutable: string, hostAssembly: string, args: string[]): string[] {
        vector := new string[](args.Length + 2)
        vector[0] = dotnetExecutable
        vector[1] = hostAssembly
        index := 0
        while index < args.Length {
            vector[index + 2] = args[index]
            index = index + 1
        }

        return vector
    }

    // The host's environment is this process's, with `DOTNET_ROOT` pointing at the runtime that was
    // found and the architecture variable defaulted to it — exactly what the launcher scripts
    // exported — and without the force switch. Entries are `NAME=value`, sorted for determinism.
    static func BuildHostEnvironment(current: IDictionary, dotnetRoot: string, architectureVariable: string?): string[] {
        values := new SortedDictionary<string, string>(StringComparer.Ordinal)
        for entry in current.Keys {
            name := entry.ToString() ?? ""
            if name.Length == 0 || name == FrontDoorKernels.ForceEnvironmentVariableName() {
                continue
            }

            value := current[entry]
            text := ""
            if value != null {
                text = value.ToString() ?? ""
            }

            values[name] = text
        }

        values["DOTNET_ROOT"] = dotnetRoot
        if architectureVariable != null {
            existing := ""
            if values.ContainsKey(architectureVariable) {
                existing = values[architectureVariable]
            }

            if existing.Length == 0 {
                values[architectureVariable] = dotnetRoot
            }
        }

        entries := new string[](values.Count)
        index := 0
        for pair in values {
            entries[index] = pair.Key + "=" + pair.Value
            index = index + 1
        }

        return entries
    }

    static func GetMissingHostMessage(candidates: List<string>): string {
        return "Error: N# installation is incomplete; missing nlc payload: " + string.Join(", ", candidates)
    }

    static func GetMissingDotnetMessage(isWindows: bool): string {
        if isWindows {
            return "N# requires .NET 10, but no usable dotnet runtime was found. Install .NET with winget install Microsoft.DotNet.SDK.10 and retry."
        }

        return "Error: N# requires .NET 10, but no usable dotnet runtime was found.\n\nInstall .NET first, then retry:\n  macOS:   brew install dotnet\n  Linux:   use your distro package manager or https://dotnet.microsoft.com/download\n  Windows: winget install Microsoft.DotNet.SDK.10"
    }

    static func GetHostStartFailureMessage(dotnetExecutable: string, detail: string): string {
        return "Error: could not start the N# compiler host with " + dotnetExecutable + ": " + detail
    }

    // The exit status the launcher scripts used for "cannot start": the shell's "command not found".
    static func GetStartFailureExitCode(): int {
        return 127
    }

    private static func AddDistinct(candidates: List<string>, candidate: string) {
        if !candidates.Contains(candidate) {
            candidates.Add(candidate)
        }
    }
}

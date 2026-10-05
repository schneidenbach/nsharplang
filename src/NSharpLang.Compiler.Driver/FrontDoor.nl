namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.ComponentModel
import System.Diagnostics
import System.IO
import System.Runtime.InteropServices

// THE NATIVE FRONT DOOR: `nlc` AS A NATIVEAOT EXECUTABLE. The decisions are `FrontDoorKernels`;
// this class performs them.
//
// `CliPipeline.Execute` tests `RuntimeFeature.IsDynamicCodeSupported` first. Under NativeAOT that is a
// compile-time `false`, so the AOT compiler sees that the front door is the ONLY path and trims
// the compiler out of the executable: the image carries this class, the help/version text and the
// .NET base library, and starts in a few milliseconds. In a JIT process the same check is `true`
// and the pipeline runs every command in-process exactly as before.
//
// THE HAND-OFF REPLACES THE PROCESS. On Unix the front door `execve`s `dotnet <lib>/Cli.dll <args>`:
// the host inherits the process id, the terminal, every descriptor and every signal, so exit codes,
// Ctrl+C and a caller's `kill <pid>` mean exactly what they meant under the launcher script (which
// also `exec`ed). Windows has no `exec`; there the front door starts the host on the same console,
// lets Ctrl+C reach it, and returns its exit code.
class FrontDoor {
    static func IsForced(): bool {
        return FrontDoorKernels.IsForced(Environment.GetEnvironmentVariable(FrontDoorKernels.ForceEnvironmentVariableName()))
    }

    static func Execute(args: string[], version: string): int {
        commandKind := ProgramCommandKernels.GetCommandKind(args)
        if FrontDoorKernels.AnswersInFrontDoor(commandKind) {
            if commandKind == 29 {
                Console.WriteLine(ProgramCommandKernels.GetHelpText(version))
            } else {
                Console.WriteLine(ProgramCommandKernels.GetVersionText(version))
            }

            return 0
        }

        return ExecuteInHost(args)
    }

    static func ExecuteInHost(args: string[]): int {
        hostCandidates := FrontDoorKernels.GetHostAssemblyCandidates(GetExecutableDirectories())
        hostAssembly: string? = null
        for candidate in hostCandidates {
            if hostAssembly == null && File.Exists(candidate) {
                hostAssembly = Path.GetFullPath(candidate)
            }
        }

        if hostAssembly == null {
            Console.Error.WriteLine(FrontDoorKernels.GetMissingHostMessage(hostCandidates))
            return FrontDoorKernels.GetStartFailureExitCode()
        }

        isWindows := OperatingSystem.IsWindows()
        dotnetRoot := ResolveDotnetRoot(isWindows)
        if dotnetRoot == null {
            Console.Error.WriteLine(FrontDoorKernels.GetMissingDotnetMessage(isWindows))
            return FrontDoorKernels.GetStartFailureExitCode()
        }

        dotnetExecutable := Path.Combine(dotnetRoot, FrontDoorKernels.GetDotnetExecutableName(isWindows))
        argumentVector := FrontDoorKernels.BuildHostArgumentVector(dotnetExecutable, hostAssembly, args)
        architectureVariable := FrontDoorKernels.GetArchitectureRootVariable(RuntimeInformation.ProcessArchitecture.ToString())
        environment := FrontDoorKernels.BuildHostEnvironment(Environment.GetEnvironmentVariables(), dotnetRoot, architectureVariable)

        if isWindows {
            return RunHostProcess(argumentVector, environment)
        }

        return ReplaceProcess(argumentVector, environment)
    }

    // The directories this executable is known by: where its RESOLVED file lives (`bin/nlc` is a
    // symlink to `lib/nlc/nlc`), where it was invoked from, and the runtime's base directory, which
    // in a forced JIT front door is the directory of `Cli.dll` itself.
    static func GetExecutableDirectories(): List<string> {
        directories := new List<string>()
        processPath := Environment.ProcessPath
        if processPath != null && processPath.Length > 0 {
            resolved := ResolveFinalPath(processPath)
            AddDirectoryOf(directories, resolved)
            AddDirectoryOf(directories, processPath)
        }

        baseDirectory := Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory)
        if baseDirectory.Length > 0 && !directories.Contains(baseDirectory) {
            directories.Add(baseDirectory)
        }

        return directories
    }

    static func ResolveDotnetRoot(isWindows: bool): string? {
        architectureVariable := FrontDoorKernels.GetArchitectureRootVariable(RuntimeInformation.ProcessArchitecture.ToString())
        architectureRoot: string? = null
        if architectureVariable != null {
            architectureRoot = Environment.GetEnvironmentVariable(architectureVariable)
        }

        candidates := FrontDoorKernels.GetDotnetRootCandidates(
            architectureRoot,
            Environment.GetEnvironmentVariable("DOTNET_ROOT"),
            FindDotnetOnPath(isWindows),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            isWindows,
            Environment.GetEnvironmentVariable("ProgramFiles"),
            Environment.GetEnvironmentVariable("ProgramFiles(x86)")
        )
        for candidate in candidates {
            if IsUsableDotnetRoot(candidate, isWindows) {
                return Path.TrimEndingDirectorySeparator(Path.GetFullPath(candidate))
            }
        }

        return null
    }

    static func IsUsableDotnetRoot(candidate: string, isWindows: bool): bool {
        if !File.Exists(Path.Combine(candidate, FrontDoorKernels.GetDotnetExecutableName(isWindows))) {
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

        return FrontDoorKernels.HasRequiredRuntime(names)
    }

    static func FindDotnetOnPath(isWindows: bool): string? {
        pathValue := Environment.GetEnvironmentVariable("PATH")
        if pathValue == null || pathValue.Length == 0 {
            return null
        }

        executableName := FrontDoorKernels.GetDotnetExecutableName(isWindows)
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
            // A dangling or unreadable link is reported by whoever opens the path next.
            return path
        }

        return path
    }

    static func AddDirectoryOf(directories: List<string>, path: string) {
        directory := Path.GetDirectoryName(path)
        if directory != null && directory.Length > 0 && !directories.Contains(directory) {
            directories.Add(directory)
        }
    }

    // `execve` returns only on failure; the host owns the process from then on.
    static func ReplaceProcess(argumentVector: string[], environment: string[]): int {
        path := FrontDoorNative.ToNative(argumentVector[0])
        argv := FrontDoorNative.ToNativeVector(argumentVector)
        envp := FrontDoorNative.ToNativeVector(environment)
        failure := ""
        try {
            FrontDoorNative.Execve(path, argv, envp)
            failure = new Win32Exception(Marshal.GetLastSystemError()).Message
        } catch error: Exception {
            failure = error.Message
        }

        Console.Error.WriteLine(FrontDoorKernels.GetHostStartFailureMessage(argumentVector[0], failure))
        return FrontDoorKernels.GetStartFailureExitCode()
    }

    static func RunHostProcess(argumentVector: string[], environment: string[]): int {
        startInfo := new ProcessStartInfo()
        startInfo.FileName = argumentVector[0]
        index := 1
        while index < argumentVector.Length {
            startInfo.ArgumentList.Add(argumentVector[index])
            index = index + 1
        }

        startInfo.UseShellExecute = false
        startInfo.Environment.Clear()
        for entry in environment {
            separator := entry.IndexOf('=')
            startInfo.Environment[entry.Substring(0, separator)] = entry.Substring(separator + 1)
        }

        // Ctrl+C reaches every process on the console; the host decides what it means, and the
        // front door waits for the host's answer instead of dying first.
        on Console.CancelKeyPress (sender, cancel) => {
            cancel.Cancel = true
        }

        try {
            process := Process.Start(startInfo)
            if process == null {
                Console.Error.WriteLine(FrontDoorKernels.GetHostStartFailureMessage(argumentVector[0], "the process did not start"))
                return FrontDoorKernels.GetStartFailureExitCode()
            }

            process.WaitForExit()
            exitCode := process.ExitCode
            process.Dispose()
            return exitCode
        } catch error: Exception {
            Console.Error.WriteLine(FrontDoorKernels.GetHostStartFailureMessage(argumentVector[0], error.Message))
            return FrontDoorKernels.GetStartFailureExitCode()
        }
    }
}

// `execve(2)`. macOS keeps it in libSystem and glibc in `libc.so.6`; the two declarations differ
// only in the library, and `FrontDoorNative.Execve` picks one. Every argument is a pointer to
// NUL-terminated UTF-8 or a NULL-terminated pointer vector, so nothing needs runtime marshalling.
static class FrontDoorNative {
    [LibraryImport("/usr/lib/libSystem.B.dylib", EntryPoint = "execve")]
    static func ExecveDarwin(path: IntPtr, argv: IntPtr[], envp: IntPtr[]): int

    [LibraryImport("libc.so.6", EntryPoint = "execve")]
    static func ExecveGlibc(path: IntPtr, argv: IntPtr[], envp: IntPtr[]): int

    static func Execve(path: IntPtr, argv: IntPtr[], envp: IntPtr[]): int {
        if OperatingSystem.IsMacOS() {
            return ExecveDarwin(path, argv, envp)
        }

        return ExecveGlibc(path, argv, envp)
    }

    static func ToNative(text: string): IntPtr {
        return Marshal.StringToCoTaskMemUTF8(text)
    }

    static func ToNativeVector(values: string[]): IntPtr[] {
        vector := new IntPtr[](values.Length + 1)
        index := 0
        while index < values.Length {
            vector[index] = Marshal.StringToCoTaskMemUTF8(values[index])
            index = index + 1
        }

        vector[values.Length] = IntPtr.Zero
        return vector
    }
}

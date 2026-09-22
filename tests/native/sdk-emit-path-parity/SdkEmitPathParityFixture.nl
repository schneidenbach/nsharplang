namespace NSharpLang.SdkEmitPathParity.Tests

import System
import System.Diagnostics
import System.IO

// ─── ONE PROJECT, TWO ENTRY POINTS ───────────────────────────────────────────────────────────
//
// `nlc build` resolves a project's `nuget:` references itself and emits in a process that holds
// nothing but the compiler. `dotnet build` of a one-line `<Project Sdk="NSharpLang.Sdk" />` hands
// MSBuild's `@(ReferencePath)` to the same emitter running INSIDE MSBuild, whose own directory
// ships `Microsoft.Extensions.Logging(.Abstractions)`, `Microsoft.Extensions.DependencyInjection`
// and the rest of that family. The LanguageServer is built by `dotnet build`, so a shape the CLI
// emits and the SDK declines is not a curiosity -- it is a shape the product cannot ship.
//
// These rows compile ONE source tree through BOTH doors and require the same answer. They exist
// because the two doors once disagreed: a reference whose simple name MSBuild does NOT carry was
// taken by the DEFAULT load context and resolved its own dependencies out of the HOST's build of
// every shared name, while a reference whose simple name MSBuild DOES carry was refused there and
// landed in the compiler's own context, consistent with the project. An extension method split
// across that line had the host's type in its `this` parameter and the project's type in the
// receiver, so it matched nothing.
class ParityRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }

    func Output(): string {
        return Stdout + Stderr
    }
}

class ParityPackage {
    Feed: string
    Version: string

    constructor(feed: string, version: string) {
        Feed = feed
        Version = version
    }
}

func ParityCommandTimeoutMilliseconds(): int {
    return 20 * 60 * 1000
}

func ParityRepositoryRoot(): string {
    current: string? = Path.GetFullPath(Environment.CurrentDirectory)
    while current != null {
        candidate := current ?? ""
        if File.Exists(Path.Combine(candidate, "AGENTS.md")) && Directory.Exists(Path.Combine(candidate, "src")) && Directory.Exists(Path.Combine(candidate, "tests")) {
            return candidate
        }

        parent := Path.GetDirectoryName(candidate)
        if parent == null || parent == "" || parent == candidate {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root.")
}

func ParityQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

// Both pipes are drained as tasks before the wait: a chatty child deadlocks against a full pipe
// buffer otherwise, and the gate parses this project's own stdout as JSON, so nothing a child
// prints may reach it.
func ParityRunProcess(fileName: string, arguments: string, workingDirectory: string): ParityRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(ParityCommandTimeoutMilliseconds()) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("Process '" + fileName + " " + arguments + "' did not complete within " + ParityCommandTimeoutMilliseconds().ToString() + " ms.")
    }

    exitCode := process.ExitCode
    process.Dispose()
    return new ParityRun(exitCode, stdoutTask.Result, stderrTask.Result)
}

func ParityRunDotnet(arguments: string, workingDirectory: string): ParityRun {
    return ParityRunProcess("dotnet", arguments, workingDirectory)
}

func ParityRequireSuccess(result: ParityRun, operation: string) {
    if result.ExitCode != 0 {
        throw new InvalidOperationException(operation + " failed with exit " + result.ExitCode.ToString() + ":\n" + result.Output())
    }
}

// The same environment contract `tests/native/sdk-project-reference-boundary` uses, so a runner
// that already packed one feed can hand it to both projects instead of paying for two.
func ParityPreparePackage(root: string, scratch: string): ParityPackage {
    suppliedFeed := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_FEED") ?? ""
    suppliedVersion := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_VERSION") ?? ""
    if suppliedFeed.Length > 0 && suppliedVersion.Length > 0 {
        return new ParityPackage(suppliedFeed, suppliedVersion)
    }

    feed := Path.Combine(scratch, "feed")
    Directory.CreateDirectory(feed)
    version := "0.1.0-emitparity" + Guid.NewGuid().ToString("N")
    runtimeProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Runtime"), "NSharpLang.Runtime.csproj")
    sdkProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj")
    ParityRequireSuccess(
        ParityRunDotnet("pack " + ParityQuote(runtimeProject) + " -o " + ParityQuote(feed) + " -p:Version=0.1.0 --disable-build-servers -v q", root),
        "private Runtime package"
    )
    ParityRequireSuccess(
        ParityRunDotnet("pack " + ParityQuote(sdkProject) + " -o " + ParityQuote(feed) + " -p:Version=" + version + " --disable-build-servers -v q", root),
        "private SDK package"
    )
    return new ParityPackage(feed, version)
}

// The real global packages folder is a FALLBACK, never the write target: the packages these rows
// reference are already in it because the repository itself references them, so the restore is
// offline, and the throwaway `NSharpLang.Sdk` version this fixture packs never lands there.
func ParitySharedPackagesFolder(): string {
    configured := Environment.GetEnvironmentVariable("NUGET_PACKAGES") ?? ""
    if configured.Length > 0 {
        return configured
    }

    return Path.Combine(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget"), "packages")
}

func ParityWriteResolution(projectDirectory: string, sdkPackage: ParityPackage, packagesCache: string) {
    File.WriteAllText(
        Path.Combine(projectDirectory, "global.json"),
        "{\"sdk\":{\"version\":\"10.0.100\",\"rollForward\":\"latestFeature\"},\"msbuild-sdks\":{\"NSharpLang.Sdk\":\"" + sdkPackage.Version + "\"}}"
    )
    File.WriteAllText(
        Path.Combine(projectDirectory, "NuGet.config"),
        "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + packagesCache + "\" /></config><fallbackPackageFolders><clear /><add key=\"shared\" value=\"" + ParitySharedPackagesFolder() + "\" /></fallbackPackageFolders><packageSources><clear /><add key=\"sdk-emit-path-parity-private\" value=\"" + sdkPackage.Feed + "\" /></packageSources></configuration>"
    )
    File.WriteAllText(
        Path.Combine(projectDirectory, "Directory.Build.props"),
        "<Project><PropertyGroup><NSharpLangRuntimeVersion>0.1.0</NSharpLangRuntimeVersion></PropertyGroup></Project>"
    )
}

func ParityCliPath(root: string): string {
    return Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0/Cli.dll")
}

func ParityOutputAssembly(projectDirectory: string, assemblyName: string): string {
    return Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0"), assemblyName + ".dll")
}

func ParityDeleteOutput(projectDirectory: string) {
    names: string[] = ["bin", "obj"]
    for name in names {
        directory := Path.Combine(projectDirectory, name)
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }
    }
}

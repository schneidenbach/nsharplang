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
    return ParityRunProcessWith(fileName, arguments, workingDirectory, null, null)
}

// `variable`, when named, is set in the CHILD'S environment block only - never on this process,
// whose environment the other files of this project read while they run.
func ParityRunProcessWith(fileName: string, arguments: string, workingDirectory: string, variable: string?, setting: string?): ParityRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    if variable != null && setting != null {
        startInfo.Environment[variable ?? ""] = setting
    }

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

// A `dotnet` child that evaluates a row's own SDK project, with `NUGET_PACKAGES` pointed at the row's
// own throwaway cache - the folder the row's `NuGet.config` names as `globalPackagesFolder`. The
// variable outranks that setting, and the product gate always sets it, so without this every row
// restored the ONE private `NSharpLang.Sdk` version the gate supplies into the gate's shared cache
// at once, alongside the other SDK-path projects of the sweep - a restore that found another's
// extraction half-done failed "a package with the ID of NSharpLang.Sdk was not installed" - and the
// disposable version landed in a real cache after all. `nlc` itself stays on `ParityRunDotnet`: it
// reads `NUGET_PACKAGES` directly, never a `NuGet.config`, and evaluates no SDK project.
func ParityRunInCache(arguments: string, workingDirectory: string, packagesCache: string): ParityRun {
    return ParityRunProcessWith("dotnet", arguments, workingDirectory, "NUGET_PACKAGES", packagesCache)
}

func ParityPackages(scratch: string): string {
    return Path.Combine(scratch, "packages")
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

// THE SAMPLE'S PACKAGES COME FROM `nuget.org`, NOT FROM WHATEVER THE AMBIENT CACHE HAPPENS TO HOLD,
// AND THAT IS A MEASURED FINDING ABOUT THE PRODUCT GATE RATHER THAN A PREFERENCE.
//
// This row once wrote `fallbackPackageFolders` pointing at `NUGET_PACKAGES` and cleared the sources
// down to the private feed, on the theory that the repository already references everything the
// sample names, so door two's restore would be offline. In the WORKING TREE that held, because
// `NUGET_PACKAGES` was unset and the developer's `~/.nuget/packages` had accumulated every version
// anyone ever restored. Under the gate it does not: the gate copies the repository to a scratch
// directory and points `NUGET_PACKAGES` at a cache of its OWN, holding exactly what `dotnet restore`
// of THIS repository resolved. Nothing here references `Microsoft.Extensions.Logging` directly --
// the language server reaches it through OmniSharp and Serilog -- so that cache carries 2.0.0 and
// 6.0.0 and NOT the 9.0.0 the sample PINS ON PURPOSE, and door two failed NU1101 with the private
// feed as its only source.
//
// Door one never noticed, and could not have: `nlc build` resolved `nuget:` itself against
// api.nuget.org and unzipped straight into the packages folder, writing none of NuGet's install
// markers. So after door one there WAS a 9.0.0 directory in the fallback folder and NuGet still
// refused to see it. `nlc build` now writes the `.nupkg` and its `.sha512` beside the content, so
// such a directory IS an install both doors can read -- `tests/native/nuget-resolution-fidelity`
// is the row for that -- but the fallback folder stays gone rather than merely supplemented: a row
// about what the two doors bind must not depend on ambient cache state either way.
// `globalPackagesFolder` stays redirected at the run's own throwaway cache, so the disposable
// `NSharpLang.Sdk` version this fixture packs never lands in a real one.
//
// Private feed for the packed SDK and Runtime, `nuget.org` for everything the sample names, is the
// contract every other SDK-path row already uses: `tests/native/sdk-project-reference-boundary`
// restores YamlDotNet and System.Reflection.MetadataLoadContext that way, and
// `tests/native/compilation-backend/TestSdkFeed.nl` writes the same pair.
func ParityWriteResolution(projectDirectory: string, sdkPackage: ParityPackage, packagesCache: string) {
    File.WriteAllText(
        Path.Combine(projectDirectory, "global.json"),
        "{\"sdk\":{\"version\":\"10.0.100\",\"rollForward\":\"latestFeature\"},\"msbuild-sdks\":{\"NSharpLang.Sdk\":\"" + sdkPackage.Version + "\"}}"
    )
    File.WriteAllText(
        Path.Combine(projectDirectory, "NuGet.config"),
        "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + packagesCache + "\" /></config><fallbackPackageFolders><clear /></fallbackPackageFolders><packageSources><clear /><add key=\"sdk-emit-path-parity-private\" value=\"" + sdkPackage.Feed + "\" /><add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" /></packageSources></configuration>"
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

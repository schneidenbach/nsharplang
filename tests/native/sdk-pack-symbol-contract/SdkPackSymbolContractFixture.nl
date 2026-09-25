namespace NSharpLang.SdkPackSymbolContract.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.IO.Compression

// ─── `dotnet pack` OF AN N# PROJECT, WITH NOTHING ON THE COMMAND LINE ────────────────────────────
//
// `EmitNSharpIlAssembly` writes the assembly with the compiler's own IL emitter, which has no
// symbol writer, so an N# project's output directory holds a `.dll` and NO `.pdb`. Nothing in the
// base SDK knows that: `Microsoft.NET.Sdk.props` defaults `DebugType` to `portable`, the common
// targets put `$(IntermediateOutputPath)$(TargetName).pdb` into
// `@(DebugSymbolsProjectOutputGroupOutput)`, and `NuGet.Build.Tasks.Pack.targets` turns that item
// into `@(_TargetPathsToSymbolsWithTfm)` and hands it to `PackTask`, which fails NU5026 for a file
// the compiler never claimed to write.
//
// So every caller that packed an N# project had to repair the project's own declaration from
// OUTSIDE it. `scripts/lib/packages.sh` passes `-p:DebugSymbols=false -p:DebugType=None` for
// every N# package it packs; the deleted `tests/NSharpLang.IntegrationTests/ToolchainFixture.cs` passed
// them for `NSharpLang.Compiler.Core` and NOT for `NSharpLang.Compiler`, and that one plain
// `dotnet pack` is where CI run 35806417973 failed NU5026 on `Compiler.pdb` -- taking every
// ToolchainTests row with it, because the fixture packs before any row runs. Its successor,
// `tests/native/installed-toolchain-integration`, repairs each and holds a row that takes the
// repaired set from `scripts/lib/packages.sh` running, so the two callers can no longer disagree -- and
// THIS project is still the one that will retire the repair entirely.
//
// These rows pack N# projects THE WAY A USER WOULD: a one-line `.csproj`, everything else in
// `project.yml`, and a bare `dotnet pack`. A command-line repair would hide exactly the defect
// this project exists to hold, so nothing here passes `-p:DebugType` or `-p:DebugSymbols`.
class PackRun {
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

class PackFeed {
    Directory: string
    SdkVersion: string

    constructor(directory: string, sdkVersion: string) {
        Directory = directory
        SdkVersion = sdkVersion
    }
}

func PackCommandTimeoutMilliseconds(): int {
    return 20 * 60 * 1000
}

func PackRepositoryRoot(): string {
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

func PackQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

// Both pipes are drained as tasks before the wait: a chatty child deadlocks against a full pipe
// buffer otherwise, and the gate parses this project's own stdout, so nothing a child prints may
// reach it.
func PackRunProcess(fileName: string, arguments: string, workingDirectory: string, packagesCache: string?): PackRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    if packagesCache != null {
        startInfo.Environment["NUGET_PACKAGES"] = packagesCache
    }

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(PackCommandTimeoutMilliseconds()) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("Process '" + fileName + " " + arguments + "' did not complete within " + PackCommandTimeoutMilliseconds().ToString() + " ms.")
    }

    exitCode := process.ExitCode
    process.Dispose()
    return new PackRun(exitCode, stdoutTask.Result, stderrTask.Result)
}

func PackRunDotnet(arguments: string, workingDirectory: string): PackRun {
    return PackRunProcess("dotnet", arguments, workingDirectory, null)
}

// A `dotnet` child that evaluates the row's own sample, with `NUGET_PACKAGES` pointed at the row's
// throwaway cache - the folder its `NuGet.config` names as `globalPackagesFolder`. The variable
// outranks that setting, and the product gate always sets it: without this the sample restored the
// private `NSharpLang.Sdk` version the gate supplies into the gate's shared cache, at the same moment
// as the other SDK-path projects of the sweep restoring that same version, and the OFFLINE contract
// below held only because that cache already answered whatever the SDK asked for. It is written into
// the CHILD'S environment block only, never this process's.
func PackRunInCache(arguments: string, workingDirectory: string, packagesCache: string): PackRun {
    return PackRunProcess("dotnet", arguments, workingDirectory, packagesCache)
}

func PackRequireSuccess(result: PackRun, operation: string) {
    if result.ExitCode != 0 {
        throw new InvalidOperationException(operation + " failed with exit " + result.ExitCode.ToString() + ":\n" + result.Output())
    }
}

// The same environment contract `tests/native/sdk-project-reference-boundary` and
// `tests/native/sdk-emit-path-parity` use, so a runner that already packed one feed can hand it to
// all three instead of paying for three. `NSharpLang.Runtime` is packed at the version the SDK's
// own `NSharpLangRuntimeVersion` default names, because the SDK adds that PackageReference to every
// project it builds and this feed is the ONLY source the samples are given.
func PackPrepareFeed(root: string, scratch: string): PackFeed {
    suppliedFeed := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_FEED") ?? ""
    suppliedVersion := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_VERSION") ?? ""
    if suppliedFeed.Length > 0 && suppliedVersion.Length > 0 {
        return new PackFeed(suppliedFeed, suppliedVersion)
    }

    feed := Path.Combine(scratch, "feed")
    Directory.CreateDirectory(feed)
    version := "0.1.0-packsymbols" + Guid.NewGuid().ToString("N")
    runtimeProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Runtime"), "NSharpLang.Runtime.csproj")
    sdkProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj")
    PackRequireSuccess(
        PackRunDotnet("pack " + PackQuote(runtimeProject) + " -o " + PackQuote(feed) + " -p:Version=0.1.0 --disable-build-servers -v q", root),
        "private Runtime package"
    )
    PackRequireSuccess(
        PackRunDotnet("pack " + PackQuote(sdkProject) + " -o " + PackQuote(feed) + " -p:Version=" + version + " --disable-build-servers -v q", root),
        "private SDK package"
    )
    return new PackFeed(feed, version)
}

// OFFLINE, AND THAT IS PART OF THE CONTRACT RATHER THAN A CONVENIENCE. The samples name no
// `nuget:` dependency and declare no `test` block, so the only packages their restore can need are
// the two this fixture just built. `nuget.org` is therefore absent from the source list, not merely
// deprioritized: if the SDK ever starts asking for a package a packing project does not need, this
// project says so by failing to restore instead of quietly reaching the network.
func PackWriteResolution(projectDirectory: string, feed: PackFeed, packagesCache: string) {
    File.WriteAllText(
        Path.Combine(projectDirectory, "global.json"),
        "{\"sdk\":{\"version\":\"10.0.100\",\"rollForward\":\"latestFeature\"},\"msbuild-sdks\":{\"NSharpLang.Sdk\":\"" + feed.SdkVersion + "\"}}"
    )
    File.WriteAllText(
        Path.Combine(projectDirectory, "NuGet.config"),
        "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + packagesCache + "\" /></config><fallbackPackageFolders><clear /></fallbackPackageFolders><packageSources><clear /><add key=\"sdk-pack-symbol-contract-private\" value=\"" + feed.Directory + "\" /></packageSources></configuration>"
    )
}

func PackWriteSample(projectDirectory: string, assemblyName: string, projectYml: string, program: string) {
    Directory.CreateDirectory(projectDirectory)
    File.WriteAllText(Path.Combine(projectDirectory, assemblyName + ".csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(Path.Combine(projectDirectory, "project.yml"), projectYml)
    File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), program)
}

func PackDeleteOutput(projectDirectory: string) {
    names: string[] = ["bin", "obj"]
    for name in names {
        directory := Path.Combine(projectDirectory, name)
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }
    }
}

// THE EXACT SHAPE THE WORKFLOW RUNS, MINUS THE REPAIR. `.github/workflows/build.yml` reaches
// `dotnet pack <project> -c Release -o <dir> --disable-build-servers` through the integration
// fixture; the only difference here is that nothing supplies `-p:DebugType` or `-p:DebugSymbols`.
func PackSample(projectDirectory: string, assemblyName: string, outputDirectory: string, packagesCache: string): PackRun {
    return PackRunInCache(
        "pack " + assemblyName + ".csproj -c Release -o " + PackQuote(outputDirectory) + " --disable-build-servers -v q",
        projectDirectory,
        packagesCache
    )
}

func PackEntryNames(packagePath: string): List<string> {
    archive := ZipFile.OpenRead(packagePath)
    names := new List<string>()
    for entry in archive.Entries {
        names.Add(entry.FullName.Replace("\\", "/"))
    }

    archive.Dispose()
    names.Sort(StringComparer.Ordinal)
    return names
}

func PackJoin(values: List<string>): string {
    text := ""
    index := 0
    while index < values.Count {
        if index > 0 {
            text = text + "|"
        }

        text = text + values[index]
        index = index + 1
    }

    return text
}

func PackEntriesWithExtension(names: List<string>, extension: string): List<string> {
    matches := new List<string>()
    for name in names {
        if name.EndsWith(extension, StringComparison.OrdinalIgnoreCase) {
            matches.Add(name)
        }
    }

    return matches
}

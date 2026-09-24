namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

class SdkBoundaryRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

class SdkBoundaryPackage {
    Feed: string
    Version: string

    constructor(feed: string, version: string) {
        Feed = feed
        Version = version
    }
}

func SdkBoundaryRepositoryRoot(): string {
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

func SdkBoundaryQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

func SdkBoundaryRunDotnet(arguments: string, workingDirectory: string): SdkBoundaryRun {
    return EmitTaskRunProcess("dotnet", arguments, workingDirectory)
}

func SdkBoundaryRequireSuccess(result: SdkBoundaryRun, operation: string) {
    if result.ExitCode != 0 {
        throw new InvalidOperationException(operation + " failed with exit " + result.ExitCode.ToString() + ":\n" + result.Stdout + result.Stderr)
    }
}

func SdkBoundaryCopyRuntime(root: string, destination: string) {
    source := Path.Combine(Path.Combine(root, "src"), "NSharpLang.Runtime")
    Directory.CreateDirectory(destination)
    files := Directory.GetFiles(source, "*", SearchOption.TopDirectoryOnly)
    for sourceFile in files {
        extension := Path.GetExtension(sourceFile)
        if extension == ".cs" || extension == ".csproj" {
            File.Copy(sourceFile, Path.Combine(destination, Path.GetFileName(sourceFile)))
        }
    }
}

// ONE PACK PER PROCESS, OF A PRIVATE COPY, AND THE FEED OUTLIVES THE ROW THAT BUILT IT.
//
// Eight rows in this project ask for a private feed. Packing `src/NSharpLang.Runtime` and
// `src/NSharpLang.Sdk` IN PLACE is not confined to the pack's output directory: the SDK
// project-references the Runtime and MSBuilds Build.Tasks for its `tools/` payload, so every in-place
// pack writes `src/NSharpLang.Runtime/bin` and `obj` - paths shared with every other process in the
// repository. Any other build of the Runtime at the same moment (a developer's, another sweep
// project's) lost a file-lock race: "NSharpLang.Runtime.deps.json ... being used by another process".
// And the old cache was not the once-per-process it claimed: the eight rows live in four files, every
// file is its own test class, and the classes run in parallel, so two rows that found the cache empty
// packed the same two projects AT ONCE, in one process - about one `dev.sh` run in three failed.
//
// So the pack runs once per process under a lock, and it packs COPIES: the Runtime's sources and the
// SDK's project and `Sdk/` tree are copied into a directory of their own under the system temp root,
// with the `tools/` payload beside them, and packed there. The payload is Build.Tasks' own output,
// built in place first in Release - the configuration `dotnet pack` builds - which touches Build.Tasks,
// Compiler and Compiler.Core but never the Runtime project, and is a no-op when they are current; the
// copied SDK project is then packed with `NoBuild`, which is how its `None` items pick the copied
// payload up rather than rebuilding it. Nothing a row CLAIMS changes: each row still writes its own
// `global.json`, its own `NuGet.config` and its own throwaway `globalPackagesFolder`, and still
// resolves the SDK by version out of this feed; the version is asserted nowhere, only resolved. A
// `ProcessExit` handler removes the copy and its feed.
//
// Under the gate no pack happens here at all: Step 3a packs one feed for the whole sweep and exports
// it through the environment contract above, which is what the two `Supplied` reads honor.
class SdkBoundaryFeed {
    static Root: string = ""
    static SdkVersion: string = ""
    static Gate: object = new object()
}

func SdkBoundaryPreparePackage(root: string): SdkBoundaryPackage {
    suppliedFeed := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_FEED") ?? ""
    suppliedVersion := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_VERSION") ?? ""
    if suppliedFeed.Length > 0 && suppliedVersion.Length > 0 {
        return new SdkBoundaryPackage(suppliedFeed, suppliedVersion)
    }

    lock SdkBoundaryFeed.Gate {
        if SdkBoundaryFeed.Root.Length == 0 {
            SdkBoundaryPackPrivateCopy(root)
        }
    }

    return new SdkBoundaryPackage(SdkBoundaryFeed.Root, SdkBoundaryFeed.SdkVersion)
}

func SdkBoundaryCopyTree(source: string, destination: string) {
    Directory.CreateDirectory(destination)
    for sourceFile in Directory.GetFiles(source, "*", SearchOption.AllDirectories) {
        target := Path.Combine(destination, Path.GetRelativePath(source, sourceFile))
        Directory.CreateDirectory(Path.GetDirectoryName(target) ?? destination)
        File.Copy(sourceFile, target, true)
    }
}

func SdkBoundaryPackPrivateCopy(root: string) {
    stage := Path.Combine(Path.GetTempPath(), "nsharp-sdk-boundary-pack-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(stage)
    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        if Directory.Exists(stage) {
            Directory.Delete(stage, true)
        }
    }

    // The repository's SDK pin, and a package source list with no repository-relative entries.
    File.Copy(Path.Combine(root, "global.json"), Path.Combine(stage, "global.json"))
    File.WriteAllText(
        Path.Combine(stage, "NuGet.config"),
        "<configuration><packageSources><clear /><add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" /></packageSources></configuration>"
    )

    source := Path.Combine(root, "src")
    stagedSource := Path.Combine(stage, "src")
    SdkBoundaryCopyRuntime(root, Path.Combine(stagedSource, "NSharpLang.Runtime"))
    stagedSdk := Path.Combine(stagedSource, "NSharpLang.Sdk")
    SdkBoundaryCopyTree(Path.Combine(Path.Combine(source, "NSharpLang.Sdk"), "Sdk"), Path.Combine(stagedSdk, "Sdk"))
    File.Copy(Path.Combine(Path.Combine(source, "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj"), Path.Combine(stagedSdk, "NSharpLang.Sdk.csproj"))

    tasksDirectory := Path.Combine(source, "NSharpLang.Build.Tasks")
    SdkBoundaryRequireSuccess(
        SdkBoundaryRunDotnet("build " + SdkBoundaryQuote(Path.Combine(tasksDirectory, "NSharpLang.Build.Tasks.csproj")) + " -c Release --disable-build-servers -v q", root),
        "Build.Tasks payload for the private SDK package"
    )
    payload := Path.Combine(Path.Combine("bin", "Release"), "net10.0")
    SdkBoundaryCopyTree(Path.Combine(tasksDirectory, payload), Path.Combine(Path.Combine(stagedSource, "NSharpLang.Build.Tasks"), payload))

    feed := Path.Combine(stage, "feed")
    Directory.CreateDirectory(feed)
    version := "0.1.0-projectref" + Guid.NewGuid().ToString("N")
    SdkBoundaryRequireSuccess(
        SdkBoundaryRunDotnet("pack " + SdkBoundaryQuote(Path.Combine(Path.Combine(stagedSource, "NSharpLang.Runtime"), "NSharpLang.Runtime.csproj")) + " -o " + SdkBoundaryQuote(feed) + " -p:Version=0.1.0 --disable-build-servers -v q", stage),
        "private Runtime package"
    )
    SdkBoundaryRequireSuccess(
        SdkBoundaryRunDotnet("pack " + SdkBoundaryQuote(Path.Combine(stagedSdk, "NSharpLang.Sdk.csproj")) + " -o " + SdkBoundaryQuote(feed) + " -p:Version=" + version + " -p:NoBuild=true --disable-build-servers -v q", stage),
        "private SDK package"
    )
    SdkBoundaryFeed.Root = feed
    SdkBoundaryFeed.SdkVersion = version
}

func SdkBoundaryWriteResolution(projectDirectory: string, sdkPackage: SdkBoundaryPackage, packagesCache: string) {
    File.WriteAllText(
        Path.Combine(projectDirectory, "global.json"),
        "{\"sdk\":{\"version\":\"10.0.100\",\"rollForward\":\"latestFeature\"},\"msbuild-sdks\":{\"NSharpLang.Sdk\":\"" + sdkPackage.Version + "\"}}"
    )
    File.WriteAllText(
        Path.Combine(projectDirectory, "NuGet.config"),
        "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + packagesCache + "\" /></config><packageSources><clear /><add key=\"sdk-project-reference-private\" value=\"" + sdkPackage.Feed + "\" /><add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" /></packageSources></configuration>"
    )
}

func SdkBoundaryReferenceOutput(projectDirectory: string): SdkBoundaryRun {
    return SdkBoundaryRunDotnet("msbuild NSharpLang.Compiler.Core.csproj -t:PrintSdkProjectReferences -v m --disable-build-servers", projectDirectory)
}

func SdkBoundaryReferenceDiagnosticOutput(projectDirectory: string): SdkBoundaryRun {
    return SdkBoundaryRunDotnet("msbuild NSharpLang.Compiler.Core.csproj -t:PrintSdkProjectReferences -v d --disable-build-servers", projectDirectory)
}

func SdkBoundaryRequireReferenceOutput(result: SdkBoundaryRun, runtimeProject: string, operation: string) {
    SdkBoundaryRequireSuccess(result, operation)
    packageOrder := "YamlDotNet@16.3.0|System.Reflection.MetadataLoadContext@10.0.5"
    assert result.Stdout.Contains(packageOrder), result.Stdout
    assert !result.Stdout.Contains(packageOrder + "|" + packageOrder), result.Stdout
    assert result.Stdout.Contains("sdk-frameworks=Microsoft.NETCore.App|Microsoft.AspNetCore.App"), result.Stdout
    assert result.Stdout.Contains("sdk-project-references=" + runtimeProject), result.Stdout
    assert !result.Stdout.Contains("sdk-project-references=" + runtimeProject + "|"), result.Stdout
    assert result.Stdout.Contains("sdk-config=|||xunit"), result.Stdout
}

test "a clean SDK-only project builds an exact Runtime type deduplicates generated props and reports invalid project paths" {
    root := SdkBoundaryRepositoryRoot()
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "sdk-project-reference-boundary-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        sdkPackage := SdkBoundaryPreparePackage(root)
        runtimeDirectory := Path.Combine(scratch, "Runtime")
        projectDirectory := Path.Combine(scratch, "App")
        packagesCache := Path.Combine(scratch, "packages")
        SdkBoundaryCopyRuntime(root, runtimeDirectory)
        Directory.CreateDirectory(projectDirectory)
        SdkBoundaryWriteResolution(projectDirectory, sdkPackage, packagesCache)

        runtimeProject := Path.Combine(runtimeDirectory, "NSharpLang.Runtime.csproj")
        File.WriteAllText(Path.Combine(projectDirectory, "NSharpLang.Compiler.Core.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n  - nuget: System.Reflection.MetadataLoadContext\n    version: 10.0.5\n  - framework: Microsoft.AspNetCore.App\n  - project: ../Runtime/NSharpLang.Runtime.csproj\n"
        )
        File.WriteAllText(
            Path.Combine(projectDirectory, "Program.nl"),
            "func main() {\n    print typeof(NSharpLang.Runtime.NSharpEventSubscription).get_FullName()\n}\n"
        )
        File.WriteAllText(
            Path.Combine(projectDirectory, "Directory.Build.targets"),
            "<Project><Target Name=\"PrintSdkProjectReferences\" DependsOnTargets=\"PrepareProjectReferences\"><Message Importance=\"High\" Text=\"sdk-config=$(_NSharpProjectVersion)|$(_NSharpProjectAssemblyVersion)|$(_NSharpProjectFileVersion)|$(NSharpTestFramework)\" /><Message Importance=\"High\" Text=\"sdk-packages=@(PackageReference->'%(Identity)@%(Version)', '|')\" /><Message Importance=\"High\" Text=\"sdk-frameworks=@(FrameworkReference->'%(Identity)', '|')\" /><Message Importance=\"High\" Text=\"sdk-project-references=@(ProjectReference->'%(FullPath)', '|')\" /></Target></Project>"
        )

        generatedProps := Path.Combine(Path.Combine(projectDirectory, "obj"), "project.g.props")
        assert !File.Exists(generatedProps), "clean fixture unexpectedly contains " + generatedProps
        restore := SdkBoundaryRunDotnet("restore NSharpLang.Compiler.Core.csproj --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(restore, "clean restore graph")
        assert !File.Exists(generatedProps), "dotnet restore unexpectedly generated " + generatedProps

        directReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(directReferences, runtimeProject, "direct reference projection")

        firstBuild := SdkBoundaryRunDotnet("build NSharpLang.Compiler.Core.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(firstBuild, "clean SDK build")
        assembly := Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0"), "App.dll")
        firstRun := SdkBoundaryRunDotnet(SdkBoundaryQuote(assembly), projectDirectory)
        SdkBoundaryRequireSuccess(firstRun, "exact Runtime typeof execution")
        assert firstRun.Stdout.Trim() == "NSharpLang.Runtime.NSharpEventSubscription", firstRun.Stdout

        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\nversion: 1.2.3\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n  - nuget: System.Reflection.MetadataLoadContext\n    version: 10.0.5\n  - framework: Microsoft.AspNetCore.App\n  - project: ../Runtime/NSharpLang.Runtime.csproj\n"
        )
        versionedReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireSuccess(versionedReferences, "versioned configuration projection")
        assert versionedReferences.Stdout.Contains("sdk-config=1.2.3|1.2.3.0|1.2.3.0|xunit"), versionedReferences.Stdout

        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n  - nuget: System.Reflection.MetadataLoadContext\n    version: 10.0.5\n  - framework: Microsoft.AspNetCore.App\n  - project: ../Runtime/NSharpLang.Runtime.csproj\n"
        )
        resetReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(resetReferences, runtimeProject, "blank version reset projection")

        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\noutputType: Exe\ntargetFramework: net10.0\n"
        )
        invalidConfig := SdkBoundaryReferenceDiagnosticOutput(projectDirectory)
        invalidConfigOutput := invalidConfig.Stdout + invalidConfig.Stderr
        assert invalidConfig.ExitCode != 0, invalidConfigOutput
        assert invalidConfigOutput.Contains("Loading project configuration from " + Path.Combine(projectDirectory, "project.yml")), invalidConfigOutput
        assert invalidConfigOutput.Contains("Invalid outputType: 'Exe'. Must be 'exe' or 'library'."), invalidConfigOutput

        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n  - nuget: System.Reflection.MetadataLoadContext\n    version: 10.0.5\n  - framework: Microsoft.AspNetCore.App\n  - project: ../Runtime/NSharpLang.Runtime.csproj\n"
        )

        repeatedBuild := SdkBoundaryRunDotnet("build NSharpLang.Compiler.Core.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(repeatedBuild, "incremental SDK build")
        repeatedReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(repeatedReferences, runtimeProject, "repeated reference projection")

        cli := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0/Cli.dll")
        generated := SdkBoundaryRunDotnet(SdkBoundaryQuote(cli) + " restore", projectDirectory)
        SdkBoundaryRequireSuccess(generated, "generated props compatibility setup")
        assert File.Exists(generatedProps), "nlc restore did not generate " + generatedProps
        generatedReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(generatedReferences, runtimeProject, "generated props compatibility")
        generatedBuild := SdkBoundaryRunDotnet("build NSharpLang.Compiler.Core.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(generatedBuild, "generated props SDK build")

        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n  - framework: Microsoft.AspNetCore.App\n  - project: ../Runtime/NSharpLang.Runtime.dll\n"
        )
        invalidRestore := SdkBoundaryRunDotnet("restore NSharpLang.Compiler.Core.csproj --force-evaluate --disable-build-servers -v q", projectDirectory)
        invalidOutput := invalidRestore.Stdout + invalidRestore.Stderr
        assert invalidRestore.ExitCode != 0, "invalid project reference unexpectedly restored successfully"
        assert invalidOutput.Contains("Project file not found: ../Runtime/NSharpLang.Runtime.dll"), invalidOutput
        invalidResolvedPath := Path.Combine(Path.Combine(projectDirectory, "../Runtime"), "NSharpLang.Runtime.dll")
        assert invalidOutput.Contains("resolved to " + invalidResolvedPath), invalidOutput
    } finally {
        Directory.Delete(scratch, true)
    }
}

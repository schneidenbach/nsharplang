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

// ONE PACK PER RUN, AND THE FEED OUTLIVES THE ROW THAT BUILT IT.
//
// Eight rows in this project asked for a private feed, and each one packed `src/NSharpLang.Runtime`
// and `src/NSharpLang.Sdk` again. That pack is NOT confined to its own output directory:
// `NSharpLang.Sdk.csproj` project-references Build.Tasks and the Runtime and MSBuilds Build.Tasks
// for its `tools/` payload, so every pack writes `src/*/obj` and `src/*/bin` - paths shared with
// every other process in the repository. Under Step 3a's parallel sweep that made this project race
// `tests/native/sdk-pack-symbol-contract`, which packs the same two projects and is its neighbour in
// discovery order, and one row of 28 lost the race to an MSBuild file-lock IOException.
//
// The pack now happens at most ONCE per `nlc test` process, and every row reuses its result. The
// rows run one at a time - the native runner walks its cases in a single loop - so the cache needs
// no lock. The feed cannot live in the calling row's scratch directory, which that row deletes when
// it finishes, so it gets a directory of its own under `artifacts/` and a `ProcessExit` handler
// removes it. Nothing a row CLAIMS changes: each row still writes its own `global.json`, its own
// `NuGet.config` and its own throwaway `globalPackagesFolder`, and still resolves the SDK by version
// out of this feed; the version is asserted nowhere, only resolved.
//
// Under the gate no pack happens here at all: Step 3a packs one feed for the whole sweep and
// exports it through the environment contract above, which is what the two `Supplied` reads honor.
// This cache is what a run with NO feed supplied gets - `dev.sh`, or `nlc test` on this project
// alone - and the sweep keeps the project in its serial group for the same reason: whenever nobody
// hands it a feed, it packs two shared in-repo projects.
class SdkBoundaryFeed {
    static Root: string = ""
    static SdkVersion: string = ""
}

func SdkBoundaryPreparePackage(root: string): SdkBoundaryPackage {
    suppliedFeed := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_FEED") ?? ""
    suppliedVersion := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_VERSION") ?? ""
    if suppliedFeed.Length > 0 && suppliedVersion.Length > 0 {
        return new SdkBoundaryPackage(suppliedFeed, suppliedVersion)
    }

    if SdkBoundaryFeed.Root.Length > 0 {
        return new SdkBoundaryPackage(SdkBoundaryFeed.Root, SdkBoundaryFeed.SdkVersion)
    }

    feed := Path.Combine(Path.Combine(root, "artifacts"), "sdk-project-reference-feed-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(feed)
    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        if Directory.Exists(feed) {
            Directory.Delete(feed, true)
        }
    }
    version := "0.1.0-projectref" + Guid.NewGuid().ToString("N")
    runtimeProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Runtime"), "NSharpLang.Runtime.csproj")
    sdkProject := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Sdk"), "NSharpLang.Sdk.csproj")
    SdkBoundaryRequireSuccess(
        SdkBoundaryRunDotnet("pack " + SdkBoundaryQuote(runtimeProject) + " -o " + SdkBoundaryQuote(feed) + " -p:Version=0.1.0 --disable-build-servers -v q", root),
        "private Runtime package"
    )
    SdkBoundaryRequireSuccess(
        SdkBoundaryRunDotnet("pack " + SdkBoundaryQuote(sdkProject) + " -o " + SdkBoundaryQuote(feed) + " -p:Version=" + version + " --disable-build-servers -v q", root),
        "private SDK package"
    )
    SdkBoundaryFeed.Root = feed
    SdkBoundaryFeed.SdkVersion = version
    return new SdkBoundaryPackage(feed, version)
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

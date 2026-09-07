namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.Diagnostics
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
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    process.WaitForExit()
    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    exitCode := process.ExitCode
    process.Dispose()
    return new SdkBoundaryRun(exitCode, stdout, stderr)
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

func SdkBoundaryPreparePackage(root: string, scratch: string): SdkBoundaryPackage {
    suppliedFeed := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_FEED") ?? ""
    suppliedVersion := Environment.GetEnvironmentVariable("NSHARP_SDK_PROJECT_REFERENCE_VERSION") ?? ""
    if suppliedFeed.Length > 0 && suppliedVersion.Length > 0 {
        return new SdkBoundaryPackage(suppliedFeed, suppliedVersion)
    }

    feed := Path.Combine(scratch, "feed")
    Directory.CreateDirectory(feed)
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
    return SdkBoundaryRunDotnet("msbuild NSharpLang.Compiler.BootstrapServices.csproj -t:PrintSdkProjectReferences -v m --disable-build-servers", projectDirectory)
}

func SdkBoundaryRequireReferenceOutput(result: SdkBoundaryRun, runtimeProject: string, operation: string) {
    SdkBoundaryRequireSuccess(result, operation)
    packageOrder := "YamlDotNet@16.3.0|System.Reflection.MetadataLoadContext@10.0.5"
    assert result.Stdout.Contains(packageOrder), result.Stdout
    assert !result.Stdout.Contains(packageOrder + "|" + packageOrder), result.Stdout
    assert result.Stdout.Contains("sdk-frameworks=Microsoft.NETCore.App|Microsoft.AspNetCore.App"), result.Stdout
    assert result.Stdout.Contains("sdk-project-references=" + runtimeProject), result.Stdout
    assert !result.Stdout.Contains("sdk-project-references=" + runtimeProject + "|"), result.Stdout
}

test "a clean SDK-only project builds an exact Runtime type deduplicates generated props and reports invalid project paths" {
    root := SdkBoundaryRepositoryRoot()
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "sdk-project-reference-boundary-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        sdkPackage := SdkBoundaryPreparePackage(root, scratch)
        runtimeDirectory := Path.Combine(scratch, "Runtime")
        projectDirectory := Path.Combine(scratch, "App")
        packagesCache := Path.Combine(scratch, "packages")
        SdkBoundaryCopyRuntime(root, runtimeDirectory)
        Directory.CreateDirectory(projectDirectory)
        SdkBoundaryWriteResolution(projectDirectory, sdkPackage, packagesCache)

        runtimeProject := Path.Combine(runtimeDirectory, "NSharpLang.Runtime.csproj")
        File.WriteAllText(Path.Combine(projectDirectory, "NSharpLang.Compiler.BootstrapServices.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
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
            "<Project><Target Name=\"PrintSdkProjectReferences\" DependsOnTargets=\"PrepareProjectReferences\"><Message Importance=\"High\" Text=\"sdk-packages=@(PackageReference->'%(Identity)@%(Version)', '|')\" /><Message Importance=\"High\" Text=\"sdk-frameworks=@(FrameworkReference->'%(Identity)', '|')\" /><Message Importance=\"High\" Text=\"sdk-project-references=@(ProjectReference->'%(FullPath)', '|')\" /></Target></Project>"
        )

        generatedProps := Path.Combine(Path.Combine(projectDirectory, "obj"), "project.g.props")
        assert !File.Exists(generatedProps), "clean fixture unexpectedly contains " + generatedProps
        restore := SdkBoundaryRunDotnet("restore NSharpLang.Compiler.BootstrapServices.csproj --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(restore, "clean restore graph")
        assert !File.Exists(generatedProps), "dotnet restore unexpectedly generated " + generatedProps

        directReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(directReferences, runtimeProject, "direct reference projection")

        firstBuild := SdkBoundaryRunDotnet("build NSharpLang.Compiler.BootstrapServices.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(firstBuild, "clean SDK build")
        assembly := Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0"), "App.dll")
        firstRun := SdkBoundaryRunDotnet(SdkBoundaryQuote(assembly), projectDirectory)
        SdkBoundaryRequireSuccess(firstRun, "exact Runtime typeof execution")
        assert firstRun.Stdout.Trim() == "NSharpLang.Runtime.NSharpEventSubscription", firstRun.Stdout

        repeatedBuild := SdkBoundaryRunDotnet("build NSharpLang.Compiler.BootstrapServices.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(repeatedBuild, "incremental SDK build")
        repeatedReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(repeatedReferences, runtimeProject, "repeated reference projection")

        cli := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0/Cli.dll")
        generated := SdkBoundaryRunDotnet(SdkBoundaryQuote(cli) + " restore", projectDirectory)
        SdkBoundaryRequireSuccess(generated, "generated props compatibility setup")
        assert File.Exists(generatedProps), "nlc restore did not generate " + generatedProps
        generatedReferences := SdkBoundaryReferenceOutput(projectDirectory)
        SdkBoundaryRequireReferenceOutput(generatedReferences, runtimeProject, "generated props compatibility")
        generatedBuild := SdkBoundaryRunDotnet("build NSharpLang.Compiler.BootstrapServices.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        SdkBoundaryRequireSuccess(generatedBuild, "generated props SDK build")

        File.WriteAllText(
            Path.Combine(projectDirectory, "project.yml"),
            "name: App\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n  - framework: Microsoft.AspNetCore.App\n  - project: ../Runtime/NSharpLang.Runtime.dll\n"
        )
        invalidRestore := SdkBoundaryRunDotnet("restore NSharpLang.Compiler.BootstrapServices.csproj --force-evaluate --disable-build-servers -v q", projectDirectory)
        invalidOutput := invalidRestore.Stdout + invalidRestore.Stderr
        assert invalidRestore.ExitCode != 0, "invalid project reference unexpectedly restored successfully"
        assert invalidOutput.Contains("Project file not found: ../Runtime/NSharpLang.Runtime.dll"), invalidOutput
        invalidResolvedPath := Path.Combine(Path.Combine(projectDirectory, "../Runtime"), "NSharpLang.Runtime.dll")
        assert invalidOutput.Contains("resolved to " + invalidResolvedPath), invalidOutput
    } finally {
        Directory.Delete(scratch, true)
    }
}

namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

// `obj/project.g.props` only exists after `nlc restore`, so on a clean checkout every N# project
// evaluates with whatever placeholder Sdk.props supplies for OutputType. That placeholder is not
// private: the base SDK derives `_IsExecutable`, `HasRuntimeOutput` and `IsRidAgnostic` from it during
// EVALUATION, and a referencing project reads those back as this project's outer facts. An
// `outputType: library` project therefore announced itself as a non self-contained executable, and
// `_GetRequiredWorkloads` -- the target `dotnet workload restore` runs -- failed NETSDK1150 in a
// self-contained consumer before anything was compiled. These assertions pin the announcement, the
// consumer's view of it, and the fact that an `outputType: exe` project still announces an executable.
// A portable RID keeps the consumer offline and workload-free; browser-wasm only made the CI failure
// visible first.
func SdkExecutableReferenceScratch(root: string): string {
    directory := Path.Combine(Path.Combine(root, "artifacts"), "sdk-executable-reference-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func SdkExecutableReferenceOuterFacts(libraryDirectory: string, packagesCache: string): SdkBoundaryRun {
    return SdkBoundaryRunInCache(
        "msbuild Library.csproj -t:GetTargetFrameworksWithPlatformForSingleTargetFramework -getProperty:OutputType -getProperty:_IsExecutable -getProperty:IsRidAgnostic --disable-build-servers",
        libraryDirectory,
        packagesCache
    )
}

test "an unrestored project announces its project.yml outputType and survives ValidateExecutableReferences" {
    root := SdkBoundaryRepositoryRoot()
    scratch := SdkExecutableReferenceScratch(root)
    try {
        sdkPackage := SdkBoundaryPreparePackage(root)
        packagesCache := Path.Combine(scratch, "packages")
        libraryDirectory := Path.Combine(scratch, "Library")
        consumerDirectory := Path.Combine(scratch, "Consumer")
        Directory.CreateDirectory(libraryDirectory)
        Directory.CreateDirectory(consumerDirectory)
        SdkBoundaryWriteResolution(libraryDirectory, sdkPackage, packagesCache)
        SdkBoundaryWriteResolution(consumerDirectory, sdkPackage, packagesCache)

        projectFile := Path.Combine(libraryDirectory, "project.yml")
        File.WriteAllText(Path.Combine(libraryDirectory, "Library.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
        File.WriteAllText(projectFile, "name: Library\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(
            Path.Combine(libraryDirectory, "Library.nl"),
            "namespace Library\n\nfunc Answer(): int {\n    return 42\n}\n"
        )

        generatedProps := Path.Combine(Path.Combine(libraryDirectory, "obj"), "project.g.props")
        assert !File.Exists(generatedProps), "clean fixture unexpectedly contains " + generatedProps

        facts := SdkExecutableReferenceOuterFacts(libraryDirectory, packagesCache)
        SdkBoundaryRequireSuccess(facts, "unrestored library outer facts")
        assert facts.Stdout.Contains("\"OutputType\": \"Library\""), facts.Stdout
        assert facts.Stdout.Contains("\"_IsExecutable\": \"\""), facts.Stdout
        assert facts.Stdout.Contains("\"IsRidAgnostic\": \"true\""), facts.Stdout
        assert !File.Exists(generatedProps), "reading the outer facts unexpectedly generated " + generatedProps

        File.WriteAllText(
            Path.Combine(consumerDirectory, "Consumer.csproj"),
            "<Project Sdk=\"Microsoft.NET.Sdk\">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n    <OutputType>Exe</OutputType>\n    <RuntimeIdentifier>linux-x64</RuntimeIdentifier>\n    <SelfContained>true</SelfContained>\n  </PropertyGroup>\n  <ItemGroup>\n    <ProjectReference Include=\"../Library/Library.csproj\" />\n  </ItemGroup>\n</Project>\n"
        )
        File.WriteAllText(
            Path.Combine(consumerDirectory, "Program.cs"),
            "internal static class Program\n{\n    private static void Main() { }\n}\n"
        )

        // The exact MSBuild target and property `dotnet workload restore <project>` drives, without the
        // machine-wide workload reconciliation that wrapping CLI command performs.
        workloads := SdkBoundaryRunInCache(
            "msbuild Consumer.csproj -t:_GetRequiredWorkloads -p:SkipResolvePackageAssets=true --disable-build-servers",
            consumerDirectory,
            packagesCache
        )
        workloadOutput := workloads.Stdout + workloads.Stderr
        assert !workloadOutput.Contains("NETSDK1150"), workloadOutput
        SdkBoundaryRequireSuccess(workloads, "workload graph for a self-contained consumer of an unrestored N# library")

        // The placeholder still has to answer Exe for the projects that really are executables.
        File.WriteAllText(projectFile, "name: Library\nbackend: il\noutputType: exe\ntargetFramework: net10.0\n")
        executableFacts := SdkExecutableReferenceOuterFacts(libraryDirectory, packagesCache)
        SdkBoundaryRequireSuccess(executableFacts, "unrestored executable outer facts")
        assert executableFacts.Stdout.Contains("\"OutputType\": \"Exe\""), executableFacts.Stdout
        assert executableFacts.Stdout.Contains("\"_IsExecutable\": \"true\""), executableFacts.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}

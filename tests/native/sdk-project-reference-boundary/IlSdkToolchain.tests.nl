namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO
import System.Xml.Linq

// These are the native successors to tests/IlSdkToolchainTests.cs. They deliberately use the
// existing MSBuild/package fixture so every assertion reaches the shipped SDK and its generated
// props, while keeping each test's temporary project and package cache isolated.
func IlSdkScratch(root: string, label: string): string {
    directory := Path.Combine(Path.Combine(root, "artifacts"), "nsharp-sdk-il-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func IlSdkProject(directory: string, name: string, yaml: string, sdkPackage: SdkBoundaryPackage): string {
    Directory.CreateDirectory(directory)
    SdkBoundaryWriteResolution(directory, sdkPackage, Path.Combine(directory, "packages"))
    File.WriteAllText(Path.Combine(directory, name + ".csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(Path.Combine(directory, "project.yml"), yaml)
    restore := SdkBoundaryRunDotnet("restore " + SdkBoundaryQuote(name + ".csproj") + " --disable-build-servers -v q", directory)
    SdkBoundaryRequireSuccess(restore, "SDK restore for " + name)
    return Path.Combine(directory, name + ".csproj")
}

func IlSdkAssembly(directory: string, name: string): string {
    return Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "bin"), "Debug"), "net10.0"), name + ".dll")
}

func IlSdkHasPassedTrx(path: string): bool {
    document := XDocument.Load(path)
    root := document.Root
    if root == null {
        return false
    }

    return IlSdkHasPassedTrxElement(root)
}

func IlSdkHasPassedTrxElement(element: XElement): bool {
    elementName := element.Name
    if elementName.LocalName == "UnitTestResult" {
        outcome := element.Attribute(XName.Get("outcome"))
        if outcome != null && outcome.Value == "Passed" {
            return true
        }
    }

    for node in element.Nodes() {
        child := node as XElement
        if child != null && IlSdkHasPassedTrxElement(child) {
            return true
        }
    }

    return false
}

test "dotnet build uses the IL backend through the SDK" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "build")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root, scratch)
        projectDirectory := Path.Combine(scratch, "SdkIlBuild")
        projectPath := IlSdkProject(
            projectDirectory,
            "SdkIlBuild",
            "name: SdkIlBuild\nbackend: il\noutputType: exe\ntargetFramework: net10.0\n",
            sdkPackage
        )
        File.WriteAllText(
            Path.Combine(projectDirectory, "Program.nl"),
            "func main() {\n    print \"sdk il build\"\n}\n"
        )

        build := SdkBoundaryRunDotnet("build " + SdkBoundaryQuote(projectPath) + " -v q --disable-build-servers", projectDirectory)
        SdkBoundaryRequireSuccess(build, "SDK IL build")

        assemblyPath := IlSdkAssembly(projectDirectory, "SdkIlBuild")
        assert File.Exists(assemblyPath)
        assert File.Exists(Path.Combine(Path.GetDirectoryName(assemblyPath) ?? "", "SdkIlBuild.runtimeconfig.json"))

        run := SdkBoundaryRunDotnet(SdkBoundaryQuote(assemblyPath), projectDirectory)
        SdkBoundaryRequireSuccess(run, "SDK IL build output")
        assert run.Stdout.Contains("sdk il build"), run.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "dotnet build resolves runtime for an anonymous union and an N# project reference" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "union-project-reference")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root, scratch)

        libraryDirectory := Path.Combine(scratch, "UnionLib")
        libraryProject := IlSdkProject(
            libraryDirectory,
            "UnionLib",
            "name: UnionLib\nbackend: il\noutputType: library\ntargetFramework: net10.0\n",
            sdkPackage
        )
        File.WriteAllText(
            Path.Combine(libraryDirectory, "UnionApi.nl"),
            "namespace UnionLib\n\nclass UnionApi {\n    static func Describe(value: int | string): string {\n        return match value {\n            int number => number.ToString(),\n            string text => text\n        }\n    }\n\n    static func Choose(flag: bool): int | string {\n        if flag {\n            return 42\n        }\n\n        return \"runtime\"\n    }\n}\n"
        )

        consumerDirectory := Path.Combine(scratch, "Consumer")
        Directory.CreateDirectory(consumerDirectory)
        consumerProject := Path.Combine(consumerDirectory, "Consumer.csproj")
        File.WriteAllText(
            consumerProject,
            "<Project Sdk=\"Microsoft.NET.Sdk\">\n" + "  <PropertyGroup>\n" + "    <OutputType>Exe</OutputType>\n" + "    <TargetFramework>net10.0</TargetFramework>\n" + "    <ImplicitUsings>enable</ImplicitUsings>\n" + "    <Nullable>enable</Nullable>\n" + "  </PropertyGroup>\n" + "  <ItemGroup>\n" + "    <ProjectReference Include=\"" + IlSdkXml(Path.Combine("..", "UnionLib", "UnionLib.csproj")) + "\" />\n" + "  </ItemGroup>\n" + "</Project>\n"
        )
        File.WriteAllText(
            Path.Combine(consumerDirectory, "project.yml"),
            "name: Consumer\noutputType: exe\ntargetFramework: net10.0\n"
        )
        SdkBoundaryWriteResolution(consumerDirectory, sdkPackage, Path.Combine(consumerDirectory, "packages"))
        restore := SdkBoundaryRunDotnet("restore " + SdkBoundaryQuote(consumerProject) + " --disable-build-servers -v q", consumerDirectory)
        SdkBoundaryRequireSuccess(restore, "consumer restore")
        File.WriteAllText(Path.Combine(consumerDirectory, "Program.cs"), "var direct = UnionLib.UnionApi.Describe(7);\nvar returned = UnionLib.UnionApi.Choose(false).As<string>();\nConsole.WriteLine($\"{direct}|{returned}\");\n")

        build := SdkBoundaryRunDotnet("build " + SdkBoundaryQuote(consumerProject) + " -v q --disable-build-servers", consumerDirectory)
        SdkBoundaryRequireSuccess(build, "consumer build")
        run := SdkBoundaryRunDotnet("run --project " + SdkBoundaryQuote(consumerProject) + " --no-build --disable-build-servers", consumerDirectory)
        SdkBoundaryRequireSuccess(run, "consumer run")
        assert run.Stdout.Contains("7|runtime"), run.Stdout
        _ = libraryProject
    } finally {
        Directory.Delete(scratch, true)
    }
}

func IlSdkXml(value: string): string {
    return value.Replace("&", "&amp;").Replace("\"", "&quot;").Replace("<", "&lt;").Replace(">", "&gt;")
}

test "dotnet build keeps a SemVer package version and numeric CLR versions" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "semver")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root, scratch)
        projectDirectory := Path.Combine(scratch, "SdkSemVerBuild")
        projectPath := IlSdkProject(
            projectDirectory,
            "SdkSemVerBuild",
            "name: SdkSemVerBuild\nversion: 1.2.0-beta.1+build.5\nbackend: il\noutputType: library\ntargetFramework: net10.0\n",
            sdkPackage
        )
        File.WriteAllText(
            Path.Combine(projectDirectory, "Library.nl"),
            "namespace SdkSemVerBuild\n\nclass Api {\n    static func Answer(): int {\n        return 42\n    }\n}\n"
        )
        File.WriteAllText(
            Path.Combine(projectDirectory, "Directory.Build.targets"),
            "<Project>\n" + "  <Target Name=\"PrintNSharpVersionProperties\" DependsOnTargets=\"_ApplyNSharpProjectConfigForCurrentBuild\">\n" + "    <Message Importance=\"High\" Text=\"nsharp-version-props Version=$(Version);PackageVersion=$(PackageVersion);AssemblyVersion=$(AssemblyVersion);FileVersion=$(FileVersion)\" />\n" + "  </Target>\n" + "</Project>\n"
        )

        properties := SdkBoundaryRunDotnet("msbuild " + SdkBoundaryQuote(projectPath) + " -t:PrintNSharpVersionProperties -v m --disable-build-servers", projectDirectory)
        SdkBoundaryRequireSuccess(properties, "SemVer property projection")
        assert properties.Stdout.Contains("nsharp-version-props Version=1.2.0-beta.1+build.5;PackageVersion=1.2.0-beta.1+build.5;AssemblyVersion=1.2.0.0;FileVersion=1.2.0.0"), properties.Stdout

        build := SdkBoundaryRunDotnet("build " + SdkBoundaryQuote(projectPath) + " -v q --disable-build-servers", projectDirectory)
        SdkBoundaryRequireSuccess(build, "SemVer SDK build")
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "dotnet run uses the IL backend through the SDK" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "run")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root, scratch)
        projectDirectory := Path.Combine(scratch, "SdkIlRun")
        projectPath := IlSdkProject(
            projectDirectory,
            "SdkIlRun",
            "name: SdkIlRun\nbackend: il\noutputType: exe\ntargetFramework: net10.0\n",
            sdkPackage
        )
        File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), "func main() {\n    print \"sdk il run\"\n}\n")

        run := SdkBoundaryRunDotnet("run --project " + SdkBoundaryQuote(projectPath) + " --disable-build-servers", projectDirectory)
        SdkBoundaryRequireSuccess(run, "SDK IL run")
        assert run.Stdout.Contains("sdk il run"), run.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "dotnet test uses the IL backend through the SDK" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "tests")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root, scratch)
        projectDirectory := Path.Combine(scratch, "SdkIlTests")
        projectPath := IlSdkProject(
            projectDirectory,
            "SdkIlTests",
            "name: SdkIlTests\nbackend: il\noutputType: library\ntargetFramework: net10.0\n",
            sdkPackage
        )
        File.WriteAllText(Path.Combine(projectDirectory, "Math.nl"), "func Add(a: int, b: int): int {\n    return a + b\n}\n")
        File.WriteAllText(Path.Combine(projectDirectory, "Math.tests.nl"), "test \"addition works\" {\n    assert Add(2, 3) == 5\n}\n")

        trxPath := Path.Combine(scratch, "results.trx")
        command := "test " + SdkBoundaryQuote(projectPath) + " -v q --disable-build-servers --logger " + SdkBoundaryQuote("trx;LogFileName=" + trxPath)
        result := SdkBoundaryRunDotnet(command, projectDirectory)
        SdkBoundaryRequireSuccess(result, "SDK IL test run")
        assert File.Exists(trxPath)
        assert IlSdkHasPassedTrx(trxPath)
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "TRX assertion requires a UnitTestResult with an exact Passed outcome" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "trx-negative")
    try {
        decoyPath := Path.Combine(scratch, "decoy.trx")
        File.WriteAllText(
            decoyPath,
            "<TestResults><Message>outcome=\"Passed\"</Message><UnitTestResult outcome=\"Failed\" /></TestResults>"
        )
        assert !IlSdkHasPassedTrx(decoyPath)

        passingPath := Path.Combine(scratch, "passing.trx")
        File.WriteAllText(
            passingPath,
            "<TestResults><UnitTestResult outcome=\"Passed\" /></TestResults>"
        )
        assert IlSdkHasPassedTrx(passingPath)
    } finally {
        Directory.Delete(scratch, true)
    }
}

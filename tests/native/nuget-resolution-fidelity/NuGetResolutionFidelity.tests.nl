namespace NSharpLang.NuGetResolutionFidelity.Tests

import System
import System.IO
import System.Security.Cryptography

// One library name built twice, each build carrying its package's version as its ASSEMBLY version
// and answering with its own marker. Which of the two the compiler bound is then readable from the
// emitted `AssemblyRef` — see `ResolutionReferencedAssembly` for why running the program is not
// enough to tell them apart.
func ResolutionLeafSource(marker: string): string {
    return "namespace ResolutionLeaf\n\nclass LeafMarker {\n    static func Name(): string {\n        return \"" + marker + "\"\n    }\n}\n"
}

func ResolutionLeafProjectYml(version: string): string {
    return "name: ResolutionLeaf\nversion: " + version + "\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
}

func ResolutionBuildLeaf(cli: string, scratch: string, version: string, marker: string): string {
    projectDirectory := Path.Combine(scratch, "leaf-" + marker)
    ResolutionWriteProject(projectDirectory, ResolutionLeafProjectYml(version), "Leaf.nl", ResolutionLeafSource(marker))
    build := ResolutionRunDotnet(ResolutionQuote(cli) + " build", projectDirectory)
    ResolutionRequireSuccess(build, "nlc build of the " + marker + " leaf library")
    return Path.Combine(ResolutionOutputDirectory(projectDirectory), "ResolutionLeaf.dll")
}

// ── THE GRAPH EACH ROW BUILDS, AND WHY THE ORDER OF THE LIST IS PART OF IT ───────────────────
//
// Every row below declares its `nuget:` entries in the order that makes a first-wins resolver give
// the WRONG answer, so the list order is under test rather than routed around.
func ResolutionAppProjectYml(dependencies: string): string {
    return "name: ResolutionApp\nversion: 1.0.0\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n" + dependencies
}

func ResolutionDependency(packageId: string, version: string): string {
    return "  - nuget: " + packageId + "\n    version: " + version + "\n"
}

func ResolutionAppSource(): string {
    return "namespace ResolutionApp\n\nimport ResolutionLeaf\n\nfunc main() {\n    name := LeafMarker.Name()\n    print name\n}\n"
}

func ResolutionNoDependencies(): string {
    return "      <group targetFramework=\"net10.0\" />\n"
}

func ResolutionDependsOn(packageId: string, version: string): string {
    return "      <group targetFramework=\"net10.0\">\n        <dependency id=\"" + packageId + "\" version=\"" + version + "\" />\n      </group>\n"
}

// Both leaf builds installed as packages, so a row only has to describe the graph ABOVE them.
func ResolutionInstallLeaves(cli: string, scratch: string, cache: string) {
    leafOne := ResolutionBuildLeaf(cli, scratch, "1.0.0", "leaf-1")
    leafTwo := ResolutionBuildLeaf(cli, scratch, "2.0.0", "leaf-2")

    leafOneDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Leaf", "1.0.0")
    ResolutionWriteNuspec(leafOneDirectory, "NlcResolution.Leaf", "1.0.0", ResolutionNoDependencies())
    ResolutionInstallLibrary(leafOneDirectory, leafOne)

    leafTwoDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Leaf", "2.0.0")
    ResolutionWriteNuspec(leafTwoDirectory, "NlcResolution.Leaf", "2.0.0", ResolutionNoDependencies())
    ResolutionInstallLibrary(leafTwoDirectory, leafTwo)
}

func ResolutionWriteCarrierVersion(cache: string, packageId: string, version: string, dependenciesXml: string) {
    ResolutionWriteNuspec(ResolutionPackageDirectory(cache, packageId, version), packageId, version, dependenciesXml)
}

func ResolutionWriteCarrier(cache: string, packageId: string, dependenciesXml: string) {
    ResolutionWriteCarrierVersion(cache, packageId, "1.0.0", dependenciesXml)
}

// The answer to "which version did the COMPILER bind", read out of the emitted assembly, plus the
// program's own answer as a second, independent witness that the binding is usable.
func ResolutionBoundLeaf(cli: string, scratch: string, cache: string, dependencies: string, contextName: string, appDirectoryName: string = "app"): ResolutionRun {
    appDirectory := Path.Combine(scratch, appDirectoryName)
    ResolutionWriteProject(appDirectory, ResolutionAppProjectYml(dependencies), "Program.nl", ResolutionAppSource())
    build := ResolutionRunInCache(ResolutionQuote(cli) + " build", appDirectory, cache)
    ResolutionRequireSuccess(build, "nlc build of the resolution sample")

    appAssembly := Path.Combine(ResolutionOutputDirectory(appDirectory), "ResolutionApp.dll")
    bound := ResolutionReferencedAssembly(appAssembly, contextName, "ResolutionLeaf,")
    run := ResolutionRunDotnet(ResolutionQuote(appAssembly), appDirectory)
    ResolutionRequireSuccess(run, "running the resolution sample")
    return new ResolutionRun(0, bound, run.Stdout.Trim())
}

func ResolutionSha512Base64(path: string): string {
    algorithm := SHA512.Create()
    try {
        bytes := File.ReadAllBytes(path)
        hashBytes := algorithm.ComputeHash(bytes)
        return Convert.ToBase64String(hashBytes)
    } finally {
        algorithm.Dispose()
    }
}

// The scaffolding every resolution row shares: a throwaway cache, both leaf builds installed, and
// whatever carrier packages the row's graph needs.
func ResolutionScratch(name: string): string {
    scratch := Path.Combine(Path.Combine(ResolutionRepositoryRoot(), "artifacts"), "nuget-resolution-" + name + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    return scratch
}

test "a direct nuget reference beats a transitive one however the list is ordered" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("direct")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        ResolutionInstallLeaves(cli, scratch, cache)

        // `NlcResolution.Mid` carries leaf 1.0.0 and is declared FIRST, so a resolver that takes
        // each root's closure in turn and keeps the first version it reaches binds 1.0.0 and the
        // pin below does nothing at all.
        ResolutionWriteCarrier(cache, "NlcResolution.Mid", ResolutionDependsOn("NlcResolution.Leaf", "1.0.0"))
        dependencies := ResolutionDependency("NlcResolution.Mid", "1.0.0") + ResolutionDependency("NlcResolution.Leaf", "2.0.0")

        answer := ResolutionBoundLeaf(cli, scratch, cache, dependencies, "resolution-direct")
        assert answer.Stdout.StartsWith("ResolutionLeaf, Version=2.0.0.0", StringComparison.Ordinal), "the build bound " + answer.Stdout
        assert answer.Stderr == "leaf-2", answer.Stderr
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE ROW THAT SAYS DIRECT-WINS IS NOT MERELY HIGHEST-WINS, and the one a plain nearest-wins rule
// also satisfies while getting the row below wrong. `dotnet restore` of the same shape resolves the
// DIRECT version and reports NU1605: a direct `Microsoft.OpenApi 1.6.17` under a transitive 1.6.22
// lands 1.6.17. So must this.
test "a direct nuget reference wins even when it is a downgrade" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("downgrade")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        ResolutionInstallLeaves(cli, scratch, cache)

        ResolutionWriteCarrier(cache, "NlcResolution.Mid", ResolutionDependsOn("NlcResolution.Leaf", "2.0.0"))
        dependencies := ResolutionDependency("NlcResolution.Mid", "1.0.0") + ResolutionDependency("NlcResolution.Leaf", "1.0.0")

        answer := ResolutionBoundLeaf(cli, scratch, cache, dependencies, "resolution-downgrade")
        assert answer.Stdout.StartsWith("ResolutionLeaf, Version=1.0.0.0", StringComparison.Ordinal), "the build bound " + answer.Stdout
        assert answer.Stderr == "leaf-1", answer.Stderr
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE SHAPE THAT BROKE THE `nsharp-webapi` TEMPLATE UNDER A PLAIN NEAREST-WINS RULE. `Near` names
// leaf 1.0.0 one level closer than `Deep -> Deeper` names 2.0.0, exactly as
// `Microsoft.AspNetCore.OpenApi 9.0.0` names `Microsoft.OpenApi 1.6.17` closer than
// `Swashbuckle.AspNetCore -> ...Swagger` names 1.6.22. `dotnet restore` of those two resolves
// 1.6.22: a dependency version is a MINIMUM, so satisfying every edge means taking the highest,
// and distance decides nothing between two transitive occurrences. Selecting the nearer one bound
// 1.6.17 and `IServiceCollection.AddSwaggerGen` stopped being modeled at all.
test "two transitive occurrences unify on the higher version whatever their distance" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("transitive")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        ResolutionInstallLeaves(cli, scratch, cache)

        ResolutionWriteCarrier(cache, "NlcResolution.Near", ResolutionDependsOn("NlcResolution.Leaf", "1.0.0"))
        ResolutionWriteCarrier(cache, "NlcResolution.Deep", ResolutionDependsOn("NlcResolution.Deeper", "1.0.0"))
        ResolutionWriteCarrier(cache, "NlcResolution.Deeper", ResolutionDependsOn("NlcResolution.Leaf", "2.0.0"))
        dependencies := ResolutionDependency("NlcResolution.Near", "1.0.0") + ResolutionDependency("NlcResolution.Deep", "1.0.0")

        answer := ResolutionBoundLeaf(cli, scratch, cache, dependencies, "resolution-transitive")
        assert answer.Stdout.StartsWith("ResolutionLeaf, Version=2.0.0.0", StringComparison.Ordinal), "the build bound " + answer.Stdout
        assert answer.Stderr == "leaf-2", answer.Stderr
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "losing package versions drop their dependency edges, while a winning parent's edge remains" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("losing-package-branch")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        ResolutionInstallLeaves(cli, scratch, cache)

        leafNine := ResolutionBuildLeaf(cli, scratch, "9.0.0", "leaf-9")
        leafNineDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Leaf", "9.0.0")
        ResolutionWriteNuspec(leafNineDirectory, "NlcResolution.Leaf", "9.0.0", ResolutionNoDependencies())
        ResolutionInstallLibrary(leafNineDirectory, leafNine)

        // Near and Deep are cousin subgraphs. Shared 2 wins their conflict even though Near's
        // version is closer; Leaf 9 belongs only to Shared 1, so that edge must disappear when
        // the winning Shared version is used to recompute the closure. Other still contributes
        // Leaf 1, which is then the only applicable Leaf request.
        ResolutionWriteCarrier(cache, "NlcResolution.Near", ResolutionDependsOn("NlcResolution.Shared", "1.0.0"))
        ResolutionWriteCarrier(cache, "NlcResolution.Shared", ResolutionDependsOn("NlcResolution.Leaf", "9.0.0"))
        ResolutionWriteCarrierVersion(cache, "NlcResolution.Shared", "2.0.0", ResolutionNoDependencies())
        ResolutionWriteCarrier(cache, "NlcResolution.Deep", ResolutionDependsOn("NlcResolution.Bridge", "1.0.0"))
        ResolutionWriteCarrier(cache, "NlcResolution.Bridge", ResolutionDependsOn("NlcResolution.Shared", "2.0.0"))
        ResolutionWriteCarrier(cache, "NlcResolution.Other", ResolutionDependsOn("NlcResolution.Leaf", "1.0.0"))

        winningDependencies := ResolutionDependency("NlcResolution.Near", "1.0.0") +
            ResolutionDependency("NlcResolution.Deep", "1.0.0") +
            ResolutionDependency("NlcResolution.Other", "1.0.0")
        winningAnswer := ResolutionBoundLeaf(cli, scratch, cache, winningDependencies, "nuget-losing-branch", "winning-app")
        assert winningAnswer.Stdout.StartsWith("ResolutionLeaf, Version=1.0.0.0", StringComparison.Ordinal), "the build bound " + winningAnswer.Stdout
        assert winningAnswer.Stderr == "leaf-1", winningAnswer.Stderr

        // Control: without Deep's Shared 2 request, Shared 1 still wins and Leaf 9 remains in
        // the closure. Recomputing must not drop edges just because another cousin asks for less.
        retainedDependencies := ResolutionDependency("NlcResolution.Near", "1.0.0") +
            ResolutionDependency("NlcResolution.Other", "1.0.0")
        retainedAnswer := ResolutionBoundLeaf(cli, scratch, cache, retainedDependencies, "nuget-retained-branch", "retained-app")
        assert retainedAnswer.Stdout.StartsWith("ResolutionLeaf, Version=9.0.0.0", StringComparison.Ordinal), "the control bound " + retainedAnswer.Stdout
        assert retainedAnswer.Stderr == "leaf-9", retainedAnswer.Stderr
    } finally {
        Directory.Delete(scratch, true)
    }
}

// ─── THE INSTALL `dotnet restore` CAN SEE ────────────────────────────────────────────────────
//
// The install itself has to be real — markers are written by the download path and there is
// nothing to read otherwise — but the assertion is offline in the only sense that matters here:
// the consumer restores with EVERY package source cleared and no fallback folder, so the one
// place `YamlDotNet` can come from is the cache `nlc build` just wrote. Before the markers were
// written this restore answered NU1101 for a package whose files were already on disk.
test "a package nlc build installed is one dotnet restore can resolve with no sources" {
    root := ResolutionRepositoryRoot()
    cli := ResolutionCliPath(root)
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "nuget-resolution-markers-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)

        appDirectory := Path.Combine(scratch, "app")
        ResolutionWriteProject(
            appDirectory,
            "name: MarkerApp\nversion: 1.0.0\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: YamlDotNet\n    version: 16.3.0\n",
            "Program.nl",
            "namespace MarkerApp\n\nfunc main() {\n    print \"markers\"\n}\n"
        )

        build := ResolutionRunInCache(ResolutionQuote(cli) + " build", appDirectory, cache)
        ResolutionRequireSuccess(build, "nlc build of the marker sample")

        versionDirectory := ResolutionPackageDirectory(cache, "YamlDotNet", "16.3.0")
        packagePath := Path.Combine(versionDirectory, "yamldotnet.16.3.0.nupkg")
        hashPath := Path.Combine(versionDirectory, "yamldotnet.16.3.0.nupkg.sha512")
        assert File.Exists(packagePath), "nlc build left no .nupkg in " + versionDirectory
        assert File.Exists(hashPath), "nlc build left no .sha512 in " + versionDirectory

        // The marker must be the hash of the file it sits beside, not a placeholder: NuGet reads
        // it as the package's content hash, so a wrong value is a false claim about the cache.
        assert File.ReadAllText(hashPath) == ResolutionSha512Base64(packagePath), "the .sha512 marker is not the base64 SHA-512 of the .nupkg"

        consumerDirectory := Path.Combine(scratch, "consumer")
        Directory.CreateDirectory(consumerDirectory)
        File.WriteAllText(
            Path.Combine(consumerDirectory, "Consumer.csproj"),
            "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup><PackageReference Include=\"YamlDotNet\" Version=\"16.3.0\" /></ItemGroup></Project>\n"
        )
        File.WriteAllText(
            Path.Combine(consumerDirectory, "NuGet.config"),
            "<configuration><config><add key=\"globalPackagesFolder\" value=\"" + cache + "\" /></config><fallbackPackageFolders><clear /></fallbackPackageFolders><packageSources><clear /></packageSources></configuration>"
        )

        restore := ResolutionRunDotnet("restore Consumer.csproj --disable-build-servers -v q", consumerDirectory)
        ResolutionRequireSuccess(restore, "offline restore against the cache nlc build wrote")
        assert !restore.Output().Contains("NU1101"), restore.Output()
    } finally {
        Directory.Delete(scratch, true)
    }
}

// A PACKAGE THAT SHIPS NATIVE ASSETS, built by hand so the row needs no network and no real
// native library. The host reads the application's `deps.json` to build `NATIVE_DLL_SEARCH_DIRECTORIES`
// from its `runtimeTargets` rows for the RID it runs on, so the directory appearing there is the
// host's own witness that the manifest resolves `runtimes/<rid>/native/*` -- which is what the
// `e_sqlite3` of Microsoft.EntityFrameworkCore.Sqlite needs and `DllNotFoundException` said was missing.
test "nlc build copies a package's native assets and writes the deps.json the host resolves them through" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("native-assets")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        leaf := ResolutionBuildLeaf(cli, scratch, "1.0.0", "leaf-1")
        packageDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Native", "1.0.0")
        ResolutionWriteNuspec(packageDirectory, "NlcResolution.Native", "1.0.0", ResolutionNoDependencies())
        ResolutionInstallLibrary(packageDirectory, leaf)
        nativeFiles := [
            "osx-arm64/native/libfake.dylib",
            "osx-x64/native/libfake.dylib",
            "linux-x64/native/libfake.so",
            "linux-arm64/native/libfake.so",
            "linux-musl-x64/native/libfake.so",
            "win-x64/native/fake.dll",
            "win-arm64/native/fake.dll",
            "android-arm64/native/libfake.so"
        ]
        for nativeFile in nativeFiles {
            path := Path.Combine(Path.Combine(packageDirectory, "runtimes"), nativeFile)
            Directory.CreateDirectory(Path.GetDirectoryName(path) ?? "")
            File.WriteAllText(path, "not a real library")
        }

        appDirectory := Path.Combine(scratch, "app")
        source := "namespace ResolutionApp\n\nimport System\nimport ResolutionLeaf\n\nfunc main() {\n    print LeafMarker.Name()\n    print AppContext.GetData(\"NATIVE_DLL_SEARCH_DIRECTORIES\")\n}\n"
        ResolutionWriteProject(appDirectory, ResolutionAppProjectYml(ResolutionDependency("NlcResolution.Native", "1.0.0")), "Program.nl", source)
        build := ResolutionRunInCache(ResolutionQuote(cli) + " build", appDirectory, cache)
        ResolutionRequireSuccess(build, "nlc build of the native-assets sample")

        output := ResolutionOutputDirectory(appDirectory)
        assert File.Exists(Path.Combine(output, "ResolutionLeaf.dll"))
        assert File.Exists(Path.Combine(output, "runtimes/osx-arm64/native/libfake.dylib"))
        assert File.Exists(Path.Combine(output, "runtimes/linux-x64/native/libfake.so"))
        assert File.Exists(Path.Combine(output, "runtimes/win-x64/native/fake.dll"))
        manifest := File.ReadAllText(Path.Combine(output, "ResolutionApp.deps.json"))
        assert manifest.Contains("\"NlcResolution.Native/1.0.0\""), manifest
        assert manifest.Contains("\"runtimes/linux-x64/native/libfake.so\""), manifest

        run := ResolutionRunDotnet(ResolutionQuote(Path.Combine(output, "ResolutionApp.dll")), appDirectory)
        ResolutionRequireSuccess(run, "running the native-assets sample")
        assert run.Stdout.Contains("leaf-1"), run.Output()
        assert run.Stdout.Contains("runtimes"), "the host did not resolve a runtimes/<rid>/native directory from deps.json: " + run.Output()
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE PACKAGE ONLY THE REFERENCED PROJECT DECLARES. `Maker.Make()` returns a type of a package the
// consuming project never lists; before the package flowed through the `project:` reference, naming
// or touching a member of that type declined emission with 'Could not load file or assembly'.
test "a project reference flows its package so the consumer can use the package's types" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("package-flow")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        leafDirectory := Path.Combine(scratch, "leaf")
        ResolutionWriteProject(
            leafDirectory,
            "name: FlowLeaf\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n",
            "Leaf.nl",
            "namespace FlowLeaf\n\nclass Marker {\n    func Describe(): string {\n        return \"from the package\"\n    }\n}\n"
        )
        build := ResolutionRunDotnet(ResolutionQuote(cli) + " build", leafDirectory)
        ResolutionRequireSuccess(build, "nlc build of the flow leaf")
        packageDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Flow", "1.0.0")
        ResolutionWriteNuspec(packageDirectory, "NlcResolution.Flow", "1.0.0", ResolutionNoDependencies())
        ResolutionInstallLibrary(packageDirectory, Path.Combine(ResolutionOutputDirectory(leafDirectory), "FlowLeaf.dll"))

        ResolutionWriteProject(
            Path.Combine(scratch, "lib"),
            "name: FlowLib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n" + ResolutionDependency("NlcResolution.Flow", "1.0.0"),
            "Lib.nl",
            "namespace FlowLib\n\nimport FlowLeaf\n\nclass Maker {\n    static func Make(): Marker {\n        return new Marker()\n    }\n}\n"
        )
        appDirectory := Path.Combine(scratch, "app")
        ResolutionWriteProject(
            appDirectory,
            "name: FlowApp\nversion: 1.0.0\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: ../lib/project.yml\n",
            "Program.nl",
            "namespace FlowApp\n\nimport FlowLib\n\nfunc main() {\n    marker := Maker.Make()\n    print marker.Describe()\n}\n"
        )
        appBuild := ResolutionRunInCache(ResolutionQuote(cli) + " build", appDirectory, cache)
        ResolutionRequireSuccess(appBuild, "nlc build of the project that only references the library")
        output := ResolutionOutputDirectory(appDirectory)
        assert File.Exists(Path.Combine(output, "FlowLeaf.dll")), "the package's assembly was not copied beside the consumer"
        run := ResolutionRunDotnet(ResolutionQuote(Path.Combine(output, "FlowApp.dll")), appDirectory)
        ResolutionRequireSuccess(run, "running the project that only references the library")
        assert run.Stdout.Trim() == "from the package", run.Output()
    } finally {
        Directory.Delete(scratch, true)
    }
}

// THE ISSUE #247 PACKAGE, restored by this native project so the regression stays offline after the
// gate has populated NUGET_PACKAGES. B alone declares HtmlAgilityPack; A imports its namespace,
// annotates a parameter with HtmlDocument, and reads Maker.Make().DocumentNode.InnerText.
test "HtmlAgilityPack flows through a project reference for nlc test and build" {
    cli := ResolutionCliPath(ResolutionRepositoryRoot())
    scratch := ResolutionScratch("html-agility-flow")
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)
        restoredPackages := Environment.GetEnvironmentVariable("NUGET_PACKAGES") ?? ""
        restoredAssembly := Path.Combine(
            Path.Combine(Path.Combine(Path.Combine(restoredPackages, "htmlagilitypack"), "1.12.4"), "lib/netstandard2.0"),
            "HtmlAgilityPack.dll"
        )
        assert File.Exists(restoredAssembly), "HtmlAgilityPack 1.12.4 must be restored with the native test project's dependencies."

        packageDirectory := ResolutionPackageDirectory(cache, "HtmlAgilityPack", "1.12.4")
        ResolutionWriteNuspec(packageDirectory, "HtmlAgilityPack", "1.12.4", ResolutionNoDependencies())
        packageLibrary := Path.Combine(packageDirectory, "lib/netstandard2.0")
        Directory.CreateDirectory(packageLibrary)
        File.Copy(restoredAssembly, Path.Combine(packageLibrary, "HtmlAgilityPack.dll"), true)

        libDirectory := Path.Combine(scratch, "lib")
        ResolutionWriteProject(
            libDirectory,
            "name: FlowLib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n" + ResolutionDependency("HtmlAgilityPack", "1.12.4"),
            "Lib.nl",
            "namespace FlowLib\n\nimport HtmlAgilityPack\n\nclass Maker {\n    static func Make(): HtmlDocument {\n        d := new HtmlDocument()\n        d.LoadHtml(\"<p>hi</p>\")\n        return d\n    }\n}\n"
        )

        appDirectory := Path.Combine(scratch, "app")
        ResolutionWriteProject(
            appDirectory,
            "name: FlowApp\nversion: 1.0.0\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: ../lib/project.yml\n",
            "Program.nl",
            "namespace FlowApp\n\nimport FlowLib\nimport HtmlAgilityPack\n\nfunc DocumentText(document: HtmlDocument): string {\n    return document.DocumentNode.InnerText\n}\n\nfunc main() {\n    print Maker.Make().DocumentNode.InnerText\n    print DocumentText(Maker.Make())\n}\n"
        )
        appBuild := ResolutionRunInCache(ResolutionQuote(cli) + " build", appDirectory, cache)
        ResolutionRequireSuccess(appBuild, "nlc build of the project that only references the library")
        appOutput := ResolutionOutputDirectory(appDirectory)
        assert File.Exists(Path.Combine(appOutput, "HtmlAgilityPack.dll")), "the package assembly was not copied beside the consumer"
        appRun := ResolutionRunDotnet(ResolutionQuote(Path.Combine(appOutput, "FlowApp.dll")), appDirectory)
        ResolutionRequireSuccess(appRun, "running the project that only references the library")
        assert appRun.Stdout.Trim() == "hi\nhi", appRun.Output()

        testDirectory := Path.Combine(scratch, "tests")
        ResolutionWriteProject(
            testDirectory,
            "name: FlowTests\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../lib/project.yml\n",
            "Flow.tests.nl",
            "namespace FlowTests\n\nimport FlowLib\nimport HtmlAgilityPack\n\nfunc DocumentText(document: HtmlDocument): string {\n    return document.DocumentNode.InnerText\n}\n\ntest \"a test can use the package type returned by a project reference\" {\n    assert DocumentText(Maker.Make()) == \"hi\"\n}\n"
        )
        testRun := ResolutionRunInCache(ResolutionQuote(cli) + " test", testDirectory, cache)
        ResolutionRequireSuccess(testRun, "nlc test of the project that only references the library")
        assert testRun.Stdout.Contains("Passed: 1, Failed: 0"), testRun.Output()
    } finally {
        Directory.Delete(scratch, true)
    }
}

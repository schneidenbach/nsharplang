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

func ResolutionWriteCarrier(cache: string, packageId: string, dependenciesXml: string) {
    ResolutionWriteNuspec(ResolutionPackageDirectory(cache, packageId, "1.0.0"), packageId, "1.0.0", dependenciesXml)
}

// The answer to "which version did the COMPILER bind", read out of the emitted assembly, plus the
// program's own answer as a second, independent witness that the binding is usable.
func ResolutionBoundLeaf(cli: string, scratch: string, cache: string, dependencies: string, contextName: string): ResolutionRun {
    appDirectory := Path.Combine(scratch, "app")
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

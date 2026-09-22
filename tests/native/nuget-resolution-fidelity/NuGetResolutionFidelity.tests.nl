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

// THE PIN IS WRITTEN LAST, ON PURPOSE. `NlcResolution.Mid` carries `NlcResolution.Leaf 1.0.0`
// transitively and is declared first, so a resolver that takes each root's closure in turn and
// keeps the first version it reaches binds 1.0.0 and the pin below does nothing at all. NuGet
// binds 2.0.0: the declared reference is at distance zero.
func ResolutionAppProjectYml(): string {
    return """
name: ResolutionApp
version: 1.0.0
backend: il
outputType: exe
targetFramework: net10.0
dependencies:
  - nuget: NlcResolution.Mid
    version: 1.0.0
  - nuget: NlcResolution.Leaf
    version: 2.0.0
"""
}

func ResolutionAppSource(): string {
    return "namespace ResolutionApp\n\nimport ResolutionLeaf\n\nfunc main() {\n    name := LeafMarker.Name()\n    print name\n}\n"
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

test "a direct nuget pin binds even when a package declared earlier already carries it" {
    root := ResolutionRepositoryRoot()
    cli := ResolutionCliPath(root)
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "nuget-resolution-nearest-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        cache := Path.Combine(scratch, "packages")
        Directory.CreateDirectory(cache)

        leafOne := ResolutionBuildLeaf(cli, scratch, "1.0.0", "leaf-1")
        leafTwo := ResolutionBuildLeaf(cli, scratch, "2.0.0", "leaf-2")

        leafOneDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Leaf", "1.0.0")
        ResolutionWriteNuspec(leafOneDirectory, "NlcResolution.Leaf", "1.0.0", "      <group targetFramework=\"net10.0\" />\n")
        ResolutionInstallLibrary(leafOneDirectory, leafOne)

        leafTwoDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Leaf", "2.0.0")
        ResolutionWriteNuspec(leafTwoDirectory, "NlcResolution.Leaf", "2.0.0", "      <group targetFramework=\"net10.0\" />\n")
        ResolutionInstallLibrary(leafTwoDirectory, leafTwo)

        midDirectory := ResolutionPackageDirectory(cache, "NlcResolution.Mid", "1.0.0")
        ResolutionWriteNuspec(
            midDirectory,
            "NlcResolution.Mid",
            "1.0.0",
            "      <group targetFramework=\"net10.0\">\n        <dependency id=\"NlcResolution.Leaf\" version=\"1.0.0\" />\n      </group>\n"
        )

        appDirectory := Path.Combine(scratch, "app")
        ResolutionWriteProject(appDirectory, ResolutionAppProjectYml(), "Program.nl", ResolutionAppSource())

        build := ResolutionRunInCache(ResolutionQuote(cli) + " build", appDirectory, cache)
        ResolutionRequireSuccess(build, "nlc build of the resolution sample")

        appAssembly := Path.Combine(ResolutionOutputDirectory(appDirectory), "ResolutionApp.dll")
        bound := ResolutionReferencedAssembly(appAssembly, "resolution-nearest", "ResolutionLeaf,")
        assert bound.StartsWith("ResolutionLeaf, Version=2.0.0.0", StringComparison.Ordinal), "the build bound " + bound + "; the pinned NlcResolution.Leaf 2.0.0 is nearer than the 1.0.0 NlcResolution.Mid carries"

        run := ResolutionRunDotnet(ResolutionQuote(appAssembly), appDirectory)
        ResolutionRequireSuccess(run, "running the resolution sample")
        assert run.Stdout.Trim() == "leaf-2", run.Output()
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

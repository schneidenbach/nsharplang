namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// THE CONTRACT FOR EVERY DECISION THE ANALYZER'S METADATA-LOADING SURFACE MAKES.
//
// The C# these blocks replace is `tests/AnalyzerMetadataLoadContextTests.cs` — 189 lines carrying
// four `[Fact]`s and one `[Theory]` with seven `[InlineData]` rows, so ELEVEN xUnit cases and 22
// assertions. Nine of the eleven were about version precedence and are restated here directly. The
// other two drove a real `MetadataLoadContext` through private-field reflection to prove the two
// dedupe rules; those rules are now named predicates and are asserted as such, which is a stronger
// statement than the C# made because it says what the rule IS rather than what one scenario did.
//
// Every block below pins an answer a user can see: which assembly a name resolves from, which
// version's metadata a diagnostic is computed against, and whether a broken reference becomes an
// `NL923`.
func VersionDirectories(values: string[]): string[] {
    directories := new string[](values.Length)
    index := 0
    while index < values.Length {
        directories[index] = Path.Combine("/cache/pkg", values[index])
        index = index + 1
    }

    return directories
}

func LeafNames(directories: string[]): string {
    joined := ""
    index := 0
    while index < directories.Length {
        if index > 0 {
            joined = joined + "|"
        }

        joined = joined + Path.GetFileName(directories[index])
        index = index + 1
    }

    return joined
}

func JoinNames(values: string[]): string {
    return string.Join("|", values)
}

// ── SEMVER PRECEDENCE — THE NINE RESTATED ROWS ───────────────────────────────────────────────────

test "a release outranks its own prerelease, which ORDINAL ordering gets backwards" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("0.1.0", "0.1.0-runtimeffffffffffffffff") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("0.1.0-runtimeffffffffffffffff", "0.1.0") < 0
}

test "numeric parts compare NUMERICALLY, so 0.10.0 outranks 0.9.0" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("0.10.0", "0.9.0") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("0.9.0", "0.10.0") < 0
}

test "a NUMERIC prerelease identifier compares numerically too: beta.11 outranks beta.2" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-beta.11", "1.0.0-beta.2") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-beta.2", "1.0.0-beta.11") < 0
}

test "prerelease identifiers compare ORDINALLY when they are not numbers: rc outranks beta" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-rc.1", "1.0.0-beta.11") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-beta.11", "1.0.0-rc.1") < 0
}

test "a LONGER run of prerelease identifiers outranks the prefix it extends" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-alpha.1", "1.0.0-alpha") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-alpha", "1.0.0-alpha.1") < 0
}

test "a release outranks EVERY prerelease of the same numbers, including one that sorts last ordinally" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0", "1.0.0-zzz") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-zzz", "1.0.0") < 0
}

test "a spelling that is not a version at all sorts BELOW every one that is" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("0.0.1", "not-a-version") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("not-a-version", "0.0.1") < 0
}

test "build metadata is NOT part of precedence — 1.2.0+build.5 and 1.2.0 are the same version" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.2.0+build.5", "1.2.0") == 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.2.0", "1.2.0+build.5") == 0
}

test "the highest extracted version directory is the RELEASE, not the lexically greater prerelease" {
    directories := VersionDirectories(["0.1.0", "0.1.0-runtimeffffffffffffffff"])

    picked := AnalyzerMetadataLoadPolicy.PickHighestVersionDirectory(directories)

    assert picked == Path.Combine("/cache/pkg", "0.1.0")
}

// ── SEMVER PRECEDENCE — WHAT THE C# NEVER SAID ───────────────────────────────────────────────────

test "the order is TOTAL: two unparseable spellings still answer deterministically, ordinally" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("zeta", "alpha") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("alpha", "zeta") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("alpha", "alpha") == 0
}

test "a missing numeric part is ZERO, so 1.0 and 1.0.0 and 1.0.0.0 are one version" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0", "1.0.0") == 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0", "1.0.0.0") == 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0.1", "1.0.0") > 0
}

test "FIVE numeric parts is not a version, and neither is a signed, spaced or empty part" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0.0.0", "1.0.0") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("-1.0.0", "1.0.0") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings(" 1.0.0", "1.0.0") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1..0", "1.0.0") < 0
}

test "a numeric part too large to fit is a parse FAILURE, so it sorts below every real version" {
    // 9223372036854775807 is the largest part that parses; one more digit is not a version.
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("9223372036854775807.0.0", "1.0.0") > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("9223372036854775808.0.0", "1.0.0") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("99999999999999999999.0.0", "1.0.0") < 0
}

test "a NUMERIC prerelease identifier sorts BELOW an alphanumeric one at the same position" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-1", "1.0.0-alpha") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0-alpha", "1.0.0-1") > 0
}

test "null is not a version spelling and sorts below everything, itself included" {
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings(null, "1.0.0") < 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings("1.0.0", null) > 0
    assert AnalyzerMetadataLoadPolicy.CompareVersionSpellings(null, null) == 0
}

test "an empty directory list has no highest version and answers null rather than throwing" {
    assert AnalyzerMetadataLoadPolicy.PickHighestVersionDirectory(new string[](0)) == null
}

test "ties keep the FIRST directory listed, so the answer does not depend on filesystem order" {
    directories := VersionDirectories(["1.0.0+a", "1.0.0+b"])

    assert Path.GetFileName(AnalyzerMetadataLoadPolicy.PickHighestVersionDirectory(directories) ?? "") == "1.0.0+a"
}

test "the descending order is the SEARCH order: every installed version stays reachable, newest first" {
    directories := VersionDirectories(["9.0.1", "10.0.0", "8.0.14", "10.0.0-rc.2"])

    ordered := AnalyzerMetadataLoadPolicy.OrderVersionDirectoriesDescending(directories)

    assert LeafNames(ordered) == "10.0.0|10.0.0-rc.2|9.0.1|8.0.14"
}

test "ordering an empty set is empty, and ordering agrees with the single-pick answer" {
    assert AnalyzerMetadataLoadPolicy.OrderVersionDirectoriesDescending(new string[](0)).Length == 0

    directories := VersionDirectories(["0.9.0", "0.10.0", "0.10.0-beta"])
    ordered := AnalyzerMetadataLoadPolicy.OrderVersionDirectoriesDescending(directories)

    assert ordered[0] == AnalyzerMetadataLoadPolicy.PickHighestVersionDirectory(directories)
}

// ── THE ONE COMMON-ASSEMBLY TABLE ────────────────────────────────────────────────────────────────

test "the analyzer pre-loads exactly the table the columnar scan pre-loads — one list, not two" {
    assert JoinNames(AnalyzerMetadataLoadPolicy.CommonAssemblyNames()) == JoinNames(ExternalAssemblyScan.CommonAssemblyNames())
}

test "the table is the 27 names the drift used to be measured against, and it still opens with the core assembly" {
    names := AnalyzerMetadataLoadPolicy.CommonAssemblyNames()

    assert names.Length == 27
    assert names[0] == AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName()
    assert names[0] == "System.Runtime"
}

test "the name the analyzer's own copy was missing is IN the table — LINQ-to-XML by its implementation assembly" {
    names := AnalyzerMetadataLoadPolicy.CommonAssemblyNames()

    found := false
    index := 0
    while index < names.Length {
        if names[index] == "System.Private.Xml.Linq" {
            found = true
        }

        index = index + 1
    }

    assert found
}

// ── THE ASP.NET TABLE AND WHAT SELECTS IT ────────────────────────────────────────────────────────

test "a Web SDK asks for the ASP.NET assemblies and a plain one does not" {
    assert AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies("Microsoft.NET.Sdk.Web")
    assert !AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies("Microsoft.NET.Sdk")
    assert !AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies(null)
    assert !AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies("")
}

test "the trigger is a CONTAINS test, because the SDK id a user writes is not a closed set" {
    assert AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies("Contoso.Web.Sdk")
    assert !AnalyzerMetadataLoadPolicy.RequiresAspNetCoreAssemblies("Microsoft.NET.Sdk.web")
}

test "the ASP.NET table is eight names and every one of them is loaded by NAME, not by path" {
    names := AnalyzerMetadataLoadPolicy.AspNetCoreAssemblyNames()

    assert names.Length == 8
    assert names[0] == "Microsoft.AspNetCore"
    assert names[7] == "Microsoft.Extensions.DependencyInjection.Abstractions"
    assert JoinNames(names) == "Microsoft.AspNetCore|Microsoft.AspNetCore.Http|Microsoft.AspNetCore.Http.Abstractions|Microsoft.AspNetCore.Mvc.Core|Microsoft.AspNetCore.Mvc.Abstractions|Microsoft.AspNetCore.Routing|Microsoft.Extensions.DependencyInjection|Microsoft.Extensions.DependencyInjection.Abstractions"
}

// ── THE SHARED-FRAMEWORK WALK ────────────────────────────────────────────────────────────────────

test "the walk climbs from the runtime directory to the `shared` root that holds both frameworks" {
    runtime := Path.Combine(Path.Combine(Path.Combine("/usr/share/dotnet", "shared"), "Microsoft.NETCore.App"), "10.0.0")

    assert AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory(runtime) == Path.Combine("/usr/share/dotnet", "shared")
}

test "the walk is BOUNDED at five levels, so an unexpected layout does not climb to the filesystem root" {
    assert AnalyzerMetadataLoadPolicy.MaximumSharedRootSearchDepth() == 5

    // `shared` sits five parents above, which the walk reaches on its last iteration.
    assert AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory("/shared/a/b/c/d/e") == "/shared"
    // One level further and the walk gives up rather than climbing on.
    assert AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory("/shared/a/b/c/d/e/f") == null
}

test "a runtime directory with no `shared` above it contributes no framework search directories" {
    assert AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory("/opt/custom/runtime") == null
    assert AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory(null) == null
    assert AnalyzerMetadataLoadPolicy.SharedRootFromRuntimeDirectory("") == null
}

test "both shipped frameworks are searched and ASP.NET is searched FIRST" {
    names := AnalyzerMetadataLoadPolicy.SharedFrameworkDirectoryNames()

    assert names.Length == 2
    assert names[0] == "Microsoft.AspNetCore.App"
    assert names[1] == "Microsoft.NETCore.App"
}

// ── WHERE A PACKAGE LIVES ────────────────────────────────────────────────────────────────────────

test "NUGET_PACKAGES wins over the user profile, and the analyzer answers the same folder `nlc restore` does" {
    assert AnalyzerMetadataLoadPolicy.NuGetPackagesRoot("/custom/cache", "/home/dev") == Path.GetFullPath("/custom/cache")
    assert AnalyzerMetadataLoadPolicy.NuGetPackagesRoot(null, "/home/dev") == Path.Combine(Path.Combine("/home/dev", ".nuget"), "packages")
    assert AnalyzerMetadataLoadPolicy.NuGetPackagesRoot("   ", "/home/dev") == Path.Combine(Path.Combine("/home/dev", ".nuget"), "packages")

    assert AnalyzerMetadataLoadPolicy.NuGetPackagesRoot(null, "/home/dev") == CompilationReferenceResolverKernels.GetGlobalPackagesFolder(null, "/home/dev")
}

test "a package's cache directory is its LOWERCASED id under the root, the same normalisation restore uses" {
    directory := AnalyzerMetadataLoadPolicy.NuGetPackageCacheDirectory(null, "/home/dev", "YamlDotNet")

    assert directory == Path.Combine(Path.Combine(Path.Combine("/home/dev", ".nuget"), "packages"), "yamldotnet")
    assert directory == CompilationReferenceResolverKernels.GetNuGetPackageDirectory(CompilationReferenceResolverKernels.GetGlobalPackagesFolder(null, "/home/dev"), "YamlDotNet")
}

test "a locally built copy is looked for under the project's own Debug output before the cache" {
    assert AnalyzerMetadataLoadPolicy.LocallyBuiltPackageAssemblyPath("/src/app", "net10.0", "Contoso.Lib") == Path.Combine(Path.Combine(Path.Combine(Path.Combine("/src/app", "bin"), "Debug"), "net10.0"), "Contoso.Lib.dll")
}

test "a declared version PINS the cache directory and an undeclared one takes the highest extracted" {
    extracted := VersionDirectories(["1.4.0", "2.0.0"])

    assert AnalyzerMetadataLoadPolicy.PackageVersionDirectory("/cache/pkg", "1.4.0", extracted) == Path.Combine("/cache/pkg", "1.4.0")
    assert AnalyzerMetadataLoadPolicy.PackageVersionDirectory("/cache/pkg", null, extracted) == Path.Combine("/cache/pkg", "2.0.0")
    assert AnalyzerMetadataLoadPolicy.PackageVersionDirectory("/cache/pkg", null, new string[](0)) == null
}

test "a pinned version outranks the highest extracted one, reached from the restore record's side" {
    assert AnalyzerMetadataLoadPolicy.PinnedPackageVersionDirectory("/cache/pkg", "1.4.0") == Path.Combine("/cache/pkg", "1.4.0")
    assert AnalyzerMetadataLoadPolicy.PinnedPackageVersionDirectory("/cache/pkg", null) == null
    assert AnalyzerMetadataLoadPolicy.PinnedPackageVersionDirectory("/cache/pkg", "") == null
}

test "the lib asset a package publishes is read from lib/<tfm>/<id>.dll under the version directory" {
    assert AnalyzerMetadataLoadPolicy.PackageLibRoot("/cache/pkg/1.4.0") == Path.Combine("/cache/pkg/1.4.0", "lib")
    assert AnalyzerMetadataLoadPolicy.PackageLibAssetPath("/cache/pkg/1.4.0", "net8.0", "Contoso.Lib") == Path.Combine(Path.Combine(Path.Combine("/cache/pkg/1.4.0", "lib"), "net8.0"), "Contoso.Lib.dll")
}

// ── THE TARGET-FRAMEWORK LADDER, AND THE DRIFT IT ENDS ───────────────────────────────────────────

test "there is ONE fallback ladder and it is seven frameworks deep, newest first" {
    ladder := AnalyzerMetadataLoadPolicy.FallbackTargetFrameworks()

    assert ladder.Length == 7
    assert JoinNames(ladder) == "net10.0|net9.0|net8.0|net7.0|net6.0|netstandard2.1|netstandard2.0"
}

test "the project's own framework is probed FIRST and never probed twice" {
    probe := AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks("net10.0")

    assert probe[0] == "net10.0"
    assert probe.Length == 7
    assert JoinNames(probe) == "net10.0|net9.0|net8.0|net7.0|net6.0|netstandard2.1|netstandard2.0"
}

test "a project framework outside the ladder is prepended to it rather than replacing it" {
    probe := AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks("net11.0")

    assert probe.Length == 8
    assert probe[0] == "net11.0"
    assert probe[1] == "net10.0"
    assert probe[7] == "netstandard2.0"
}

test "with no project framework the probe IS the ladder — the resolver's view of the same order" {
    assert JoinNames(AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks(null)) == JoinNames(AnalyzerMetadataLoadPolicy.FallbackTargetFrameworks())
    assert JoinNames(AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks("  ")) == JoinNames(AnalyzerMetadataLoadPolicy.FallbackTargetFrameworks())
}

test "the ladder reaches net7.0 and net6.0, which the direct probe used to be unable to see" {
    probe := AnalyzerMetadataLoadPolicy.MetadataProbeTargetFrameworks("net10.0")

    hasNet7 := false
    hasNet6 := false
    index := 0
    while index < probe.Length {
        if probe[index] == "net7.0" {
            hasNet7 = true
        }

        if probe[index] == "net6.0" {
            hasNet6 = true
        }

        index = index + 1
    }

    assert hasNet7
    assert hasNet6
}

// ── WHAT THE PROJECT RESTORED ────────────────────────────────────────────────────────────────────

test "the restore record is read from the project's own obj/project.assets.json, under `libraries`" {
    assert AnalyzerMetadataLoadPolicy.RestoredPackageAssetsPath("/src/app") == Path.Combine(Path.Combine("/src/app", "obj"), "project.assets.json")
    assert AnalyzerMetadataLoadPolicy.RestoredLibrariesPropertyName() == "libraries"
}

test "an assembly's simple name is its file name, and every probe in the surface spells it ONCE" {
    assert AnalyzerMetadataLoadPolicy.AssemblyFileName("System.Runtime") == "System.Runtime.dll"
    assert AnalyzerMetadataLoadPolicy.SearchDirectoryAssemblyPath("/runtime", "System.Runtime") == Path.Combine("/runtime", "System.Runtime.dll")
    assert AnalyzerMetadataLoadPolicy.PackageLibAssetPath("/cache/pkg/1.0.0", "net10.0", "Contoso.Lib") == Path.Combine(Path.Combine(Path.Combine("/cache/pkg/1.0.0", "lib"), "net10.0"), AnalyzerMetadataLoadPolicy.AssemblyFileName("Contoso.Lib"))
    assert AnalyzerMetadataLoadPolicy.LocallyBuiltPackageAssemblyPath("/src/app", "net10.0", "Contoso.Lib") == Path.Combine(Path.Combine(Path.Combine(Path.Combine("/src/app", "bin"), "Debug"), "net10.0"), AnalyzerMetadataLoadPolicy.AssemblyFileName("Contoso.Lib"))
    assert AnalyzerMetadataLoadPolicy.ProjectReferenceOutputPath("/src/Lib", "net10.0", "Contoso.Lib") == Path.Combine(Path.Combine(Path.Combine(Path.Combine("/src/Lib", "bin"), "Debug"), "net10.0"), AnalyzerMetadataLoadPolicy.AssemblyFileName("Contoso.Lib"))
}

test "a libraries key splits at the FIRST slash into package and version" {
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageName("YamlDotNet/16.3.0") == "YamlDotNet"
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageVersion("YamlDotNet/16.3.0") == "16.3.0"
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageVersion("A/1.0.0/2.0.0") == "1.0.0/2.0.0"
}

test "a key that names no package version is DROPPED rather than guessed at" {
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageName("YamlDotNet") == null
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageName("/16.3.0") == null
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageName("YamlDotNet/") == null
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageVersion("YamlDotNet/") == null
    assert AnalyzerMetadataLoadPolicy.RestoredLibraryPackageName("") == null
}

// ── WHAT A PROJECT REFERENCE RESOLVES TO ─────────────────────────────────────────────────────────

test "two project spellings are recognised and anything else is reported rather than silently skipped" {
    assert AnalyzerMetadataLoadPolicy.IsRecognizedProjectReference("/src/Lib/Lib.csproj")
    assert AnalyzerMetadataLoadPolicy.IsRecognizedProjectReference("/src/Lib/project.yml")
    assert !AnalyzerMetadataLoadPolicy.IsRecognizedProjectReference("/src/Lib/Lib.fsproj")
    assert !AnalyzerMetadataLoadPolicy.IsRecognizedProjectReference("/src/Lib")

    assert AnalyzerMetadataLoadPolicy.UnknownProjectReferenceWarning("/src/Lib/Lib.fsproj") == "Warning: Unknown project reference type: /src/Lib/Lib.fsproj"
}

test "the recognition is CASE-INSENSITIVE on the extension, because the filesystem is" {
    assert AnalyzerMetadataLoadPolicy.IsCSharpProjectReference("/src/Lib/Lib.CSPROJ")
    assert AnalyzerMetadataLoadPolicy.IsNSharpProjectReference("/src/Lib/PROJECT.YML")
}

test "a .csproj's assembly is its own file name; a project.yml's is whatever `name:` made effective" {
    assert AnalyzerMetadataLoadPolicy.ProjectReferenceAssemblyName("/src/Lib/Lib.csproj", "Ignored") == "Lib"
    assert AnalyzerMetadataLoadPolicy.ProjectReferenceAssemblyName("/src/Lib/project.yml", "Contoso.Lib") == "Contoso.Lib"
}

test "a project reference resolves to the Debug output of the referenced project, not to its source" {
    assert AnalyzerMetadataLoadPolicy.ProjectReferenceOutputPath("/src/Lib", "net10.0", "Contoso.Lib") == Path.Combine(Path.Combine(Path.Combine(Path.Combine("/src/Lib", "bin"), "Debug"), "net10.0"), "Contoso.Lib.dll")
}

test "a reference path is taken as written when rooted and resolved against the project when not — dll: and project: alike" {
    assert AnalyzerMetadataLoadPolicy.ResolvedReferencePath("/src/app", "/abs/Lib.dll") == "/abs/Lib.dll"
    assert AnalyzerMetadataLoadPolicy.ResolvedReferencePath("/src/app", "../lib/Lib.dll") == Path.Combine("/src/app", "../lib/Lib.dll")
}

// ── WHEN TWO LOADS ARE THE SAME LOAD ─────────────────────────────────────────────────────────────

test "an assembly already loaded from the same PATH is not loaded twice, case-insensitively" {
    assert AnalyzerMetadataLoadPolicy.IsSameAssemblyPath("/out/Lib.dll", "/out/Lib.dll")
    assert AnalyzerMetadataLoadPolicy.IsSameAssemblyPath("/out/LIB.DLL", "/out/lib.dll")
    assert !AnalyzerMetadataLoadPolicy.IsSameAssemblyPath("/out/Lib.dll", "/other/Lib.dll")
    assert !AnalyzerMetadataLoadPolicy.IsSameAssemblyPath(null, "/out/Lib.dll")
}

test "an assembly already loaded under the same SIMPLE NAME is not loaded twice, case-insensitively" {
    assert AnalyzerMetadataLoadPolicy.IsSameSimpleName("System.Runtime", "System.Runtime")
    assert AnalyzerMetadataLoadPolicy.IsSameSimpleName("system.runtime", "System.Runtime")
    assert !AnalyzerMetadataLoadPolicy.IsSameSimpleName("System.Runtime", "System.Console")
    assert !AnalyzerMetadataLoadPolicy.IsSameSimpleName(null, "System.Runtime")
    assert !AnalyzerMetadataLoadPolicy.IsSameSimpleName("System.Runtime", null)
}

test "a search directory is admitted once, only when it names something, and the duplicate test is ORDINAL" {
    existing := new List<string>()
    existing.Add("/runtime")

    assert AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory("/out", true, existing)
    assert !AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory("/runtime", true, existing)
    assert AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory("/RUNTIME", true, existing)
    assert !AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory("/out", false, existing)
    assert !AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory("", true, existing)
    assert !AnalyzerMetadataLoadPolicy.ShouldAddSearchDirectory(null, true, existing)
}

test "the FIRST failure per identity is the one NL923 reports; later ones describe the fallback" {
    assert AnalyzerMetadataLoadPolicy.ShouldRecordLoadFailure(false)
    assert !AnalyzerMetadataLoadPolicy.ShouldRecordLoadFailure(true)
}

// ── THE RESOLVER'S CACHE SWEEP ───────────────────────────────────────────────────────────────────

test "the cache sweep is a PREFIX test on the normalised package id, never a substring test" {
    assert AnalyzerMetadataLoadPolicy.NuGetPackageDirectoryMatchesPrefix("system.text.json", "System.Text.Json")
    assert AnalyzerMetadataLoadPolicy.NuGetPackageDirectoryMatchesPrefix("system.text.json.sourcegeneration", "System.Text.Json")
    assert !AnalyzerMetadataLoadPolicy.NuGetPackageDirectoryMatchesPrefix("contoso.system.text.json", "System.Text.Json")
    assert !AnalyzerMetadataLoadPolicy.NuGetPackageDirectoryMatchesPrefix(null, "System.Text.Json")
}

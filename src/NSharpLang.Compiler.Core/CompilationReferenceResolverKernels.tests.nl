namespace NSharpLang.Cli

import System
import NSharpLang.Compiler

// THE COMPILATION REFERENCE RESOLVER'S SELECTION AND PARSING KERNELS.
//
// These replace NINE `[Fact]`/`[Theory]` bodies deleted from `tests/CliCommandTests.cs`:
// `..._FiltersReferenceValuesByType`, `..._SelectsFirstHighestCompatibleScore`,
// `..._SelectsSharedFrameworkCandidate`, `..._SelectsLatestNuGetVersion`,
// `..._SelectsBestNuGetVersion`, `..._DetectsPathSegments`,
// `..._NormalizesNuGetDependencyVersions`, `..._ParsesTargetFrameworkVersions` and
// `..._ScoresFrameworkCompatibility`.
//
// WHY THE ESTATE. Every claim is a static call on a class that lives in this same compilation
// unit, with arguments that are literals or values built from them. Nothing here reads a console,
// a process or a file, so no part of this family needs the spawned-CLI route.
//
// THE ONE `[Theory]` IN THE SET BECOMES TEN NAMED ROWS. `..._DetectsPathSegments` carried ten
// `[InlineData]` cases through one body; each is written out below so a failure reports WHICH
// path shape moved rather than one anonymous parameterised case.

// ── the reference-type filter ─────────────────────────────────────────────────
test "the reference filter keeps only the requested kind, in source order" {
    references := [
        new Reference { Nuget: "Serilog", Version: "3.1.1" },
        new Reference { Framework: "Microsoft.AspNetCore.App" },
        new Reference { Dll: "lib/Analyzer.dll" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference { Nuget: "YamlDotNet", Version: "16.0.0" }
    ]

    packageReferences := CompilationReferenceResolverKernels.FilterReferencesByType(references, ReferenceType.NuGet)

    assert packageReferences.Count == 2
    assert packageReferences[0].Nuget == "Serilog"
    assert packageReferences[1].Nuget == "YamlDotNet"
}

test "the reference filter answers each of the other three kinds from the same list" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It asked only for `NuGet` over this list, so a
    // filter that ignored its argument and always answered "the NuGet ones" would have passed.
    references := [
        new Reference { Nuget: "Serilog", Version: "3.1.1" },
        new Reference { Framework: "Microsoft.AspNetCore.App" },
        new Reference { Dll: "lib/Analyzer.dll" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference { Nuget: "YamlDotNet", Version: "16.0.0" }
    ]

    frameworks := CompilationReferenceResolverKernels.FilterReferencesByType(references, ReferenceType.Framework)
    assert frameworks.Count == 1
    assert frameworks[0].Framework == "Microsoft.AspNetCore.App"

    dlls := CompilationReferenceResolverKernels.FilterReferencesByType(references, ReferenceType.Dll)
    assert dlls.Count == 1
    assert dlls[0].Dll == "lib/Analyzer.dll"

    projects := CompilationReferenceResolverKernels.FilterReferencesByType(references, ReferenceType.Project)
    assert projects.Count == 1
    assert projects[0].Project == "../Shared/project.yml"
}

// ── the best-score selector ───────────────────────────────────────────────────

test "the score selector takes the FIRST of the tied highest scores and ignores negatives" {
    scores := [-1, 40, 900, 120, 900, 30]

    assert CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, scores.Length) == 2
    assert CompilationReferenceResolverKernels.SelectBestScoreIndex([-1, -1], 2) == -1
    assert CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, 0) == -1
}

test "the score selector honours the count, so a prefix answers from the prefix only" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It passed the whole length and zero; a kernel that
    // ignored `count` entirely would have satisfied both. The first three scores exclude the
    // second 900, so the prefix's answer is still index 2 — but a prefix of TWO must answer 1.
    scores := [-1, 40, 900, 120, 900, 30]

    assert CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, 2) == 1
    assert CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, 3) == 2
}

test "the score selector refuses a count past the end of its array" {
    scores := [-1, 40, 900, 120, 900, 30]
    refused := false

    try {
        CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, scores.Length + 1)
    } catch error: ArgumentOutOfRangeException {
        refused = true
    }

    assert refused
}

// ── the shared-framework candidate ────────────────────────────────────────────

func SharedFrameworkVersions(): Version[] {
    versions := new Version[](5)
    versions[0] = Version.Parse("8.0.12")
    versions[1] = Version.Parse("10.0.0")
    versions[2] = Version.Parse("10.0.3")
    versions[3] = Version.Parse("9.1.0")
    versions[4] = Version.Parse("10.0.3.1")
    return versions
}

test "the shared-framework selector prefers a matching major and otherwise the highest overall" {
    versions := SharedFrameworkVersions()

    // major 10 is present: 10.0.3.1 at index 4 is the highest of the three tens
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, 10) == 4
    // major 9 is present exactly once
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, 9) == 3
    // major 7 is absent, so the answer falls back to the highest overall
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, 7) == 4
    // no target at all is the same fallback
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, null) == 4
    // an empty candidate set has no answer
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(new Version[](0), 10) == -1
}

test "the shared-framework selector orders a four-field version above its three-field prefix" {
    // The mechanism the deleted body's `10 => 4` row depended on but never isolated: 10.0.3.1 beats
    // 10.0.3 only because the fourth field is compared. With those two alone the answer must be
    // the four-field one, and reversing their positions must move the answer with them.
    ascending := new Version[](2)
    ascending[0] = Version.Parse("10.0.3")
    ascending[1] = Version.Parse("10.0.3.1")
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(ascending, 10) == 1

    descending := new Version[](2)
    descending[0] = Version.Parse("10.0.3.1")
    descending[1] = Version.Parse("10.0.3")
    assert CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(descending, 10) == 0
}

// ── the NuGet version selectors ───────────────────────────────────────────────

test "the latest-version selector takes the LAST stable and falls back to the last entry" {
    assert CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(["1.0.0", "1.1.0-beta", "1.1.0"]) == 2
    assert CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(["1.0.0", "2.0.0-preview", "1.9.0"]) == 2
    // no stable entry at all: the LAST is taken, prerelease or not
    assert CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(["2.0.0-alpha", "2.0.0-beta"]) == 1
    assert CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(["1.0.0"]) == 0
    assert CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(new string[](0)) == -1
}

test "the best-version selector compares numerically and ranks a release above its prerelease" {
    assert CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(["1.0.0", "2.0.0", "1.9.9"]) == 1
    // "1.2" is 1.2.0, so the explicit patch wins over both
    assert CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(["1.2", "1.2.1", "1.2.0"]) == 1
    assert CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(["1.0.0", "1.0.0-preview"]) == 1
    assert CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(["2.0.0-alpha", "2.0.0"]) == 0
    // an unparseable entry never displaces the running best, so index 0 keeps its place
    assert CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(["bad", "1.0.0"]) == 0
    assert CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(new string[](0)) == -1
}

// ── the path-segment probe ────────────────────────────────────────────────────

test "the path-segment probe matches a WHOLE segment, case-insensitively" {
    // The ten `[InlineData]` rows of the deleted `[Theory]`, one assertion each.
    assert !CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("/tmp/project/bin/Debug/net10.0/App.dll", '/', "ref")
    assert CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("/tmp/project/bin/Debug/net10.0/ref/App.dll", '/', "ref")
    assert CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("/tmp/project/bin/Debug/net10.0/REF/App.dll", '/', "ref")
    assert !CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("/tmp/project/bin/Debug/net10.0/reference/App.dll", '/', "ref")
    assert CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("ref/App.dll", '/', "ref")
    // the LAST segment counts, with no trailing separator
    assert CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("lib/ref", '/', "ref")
    assert CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("lib//ref/App.dll", '/', "ref")
    assert !CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("lib/ref2/App.dll", '/', "ref")
    // the separator is an ARGUMENT, so a backslash path does not split on '/'
    assert !CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("lib\\ref\\App.dll", '/', "ref")
    assert CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase("lib\\ref\\App.dll", '\\', "ref")
}

// ── the NuGet dependency version normaliser ───────────────────────────────────

test "the dependency version normaliser unwraps a range and refuses an empty one" {
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion(null) == null
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("") == null
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("   ") == null
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("13.0.3") == "13.0.3"
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("[13.0.3]") == "13.0.3"
    // a two-ended range answers its LOWER bound
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("(1.0.0, 2.0.0]") == "1.0.0"
    // an open lower bound answers the upper one
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("[, 2.0.0)") == "2.0.0"
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("[ 1.2.3 , 2.0.0)") == "1.2.3"
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion(" (, 2.0.0 ] ") == "2.0.0"
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("(,)") == null
    assert CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion("[]") == null
}

// ── the target-framework parser ───────────────────────────────────────────────

test "the target-framework parser reads a major and an optional minor" {
    net10 := CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net10.0")
    assert net10.Parsed
    assert net10.Major == 10
    assert net10.Minor == 0

    netstandard := CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("netstandard2.1")
    assert netstandard.Parsed
    assert netstandard.Major == 2
    assert netstandard.Minor == 1

    // the packed `net472` form is read as major 472, NOT as 4.7.2
    net472 := CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net472")
    assert net472.Parsed
    assert net472.Major == 472
    assert net472.Minor == 0
}

test "the target-framework parser is permissive about the minor field and strict about the major" {
    doubleDot := CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net10..2")
    assert doubleDot.Parsed
    assert doubleDot.Major == 10
    assert doubleDot.Minor == 2

    badMinor := CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net10.bad")
    assert badMinor.Parsed
    assert badMinor.Major == 10
    assert badMinor.Minor == 0

    // a minor past int range is dropped rather than failing the parse
    overflowMinor := CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net10.2147483648")
    assert overflowMinor.Parsed
    assert overflowMinor.Major == 10
    assert overflowMinor.Minor == 0

    // no digits at all, and an overflowing MAJOR, both fail
    assert !CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net").Parsed
    assert !CompilationReferenceResolverKernels.ParseTargetFrameworkVersion("net2147483648.0").Parsed
}

// ── the framework compatibility score ─────────────────────────────────────────

test "an absent asset framework scores 1, the any-framework floor" {
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore(null, "net10.0") == 1
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("", "net10.0") == 1
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("   ", "net10.0") == 1
}

test "an exact framework match scores 10,000, in both the short and the long spelling" {
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("net10.0", "net10.0") == 10000
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore(".NETFramework,Version=v4.7.2", "net472") == 10000
}

test "a compatible older framework scores by family and version, and a newer one is refused" {
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("netstandard2.1", "net10.0") == 4201
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("netcoreapp3.1", "net10.0") == 7301
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore(".NETCoreApp,Version=v10.0", "net10.0") == 8000
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("net8.0", "net10.0") == 8800
    // a framework NEWER than the target cannot be consumed by it
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("net11.0", "net10.0") == -1
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("unsupported", "net10.0") == -1
    assert CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore("netbad", "net10.0") == -1
}

// ── direct wins, then highest wins ───────────────────────────────────────────
//
// A `nuget:` list is a set of ROOTS. A DIRECT reference overrides the graph however the list is
// written; among transitive occurrences the highest version wins, because a declared dependency
// version is a minimum bound and satisfying every edge means taking the highest of them. Both
// halves are what `dotnet restore` was measured doing — see the kernel's own comment for the two
// graphs and their resolved answers.

test "the first occurrence of a package id is always taken" {
    assert CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(false, "", false, "1.0.0", true)
    assert CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(false, "", false, "6.0.0", false)
}

test "a direct reference overrides a transitive one, including downwards" {
    // the round-11 shape: a transitive 6.0.0 reached first, then the project's own 9.0.0 pin
    assert CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "6.0.0", false, "9.0.0", true)
    // and a direct DOWNGRADE still wins, which is `dotnet restore`'s answer too: a direct
    // `Microsoft.OpenApi 1.6.17` beneath a transitive 1.6.22 resolves 1.6.17 and warns NU1605
    assert CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "1.6.22", false, "1.6.17", true)
}

test "a transitive occurrence never displaces a direct one" {
    assert !CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "9.0.0", true, "10.0.0", false)
    assert !CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "1.6.17", true, "1.6.22", false)
}

test "two transitive occurrences unify on the higher version whatever their distance" {
    // the `nsharp-webapi` graph: `Microsoft.AspNetCore.OpenApi` names 1.6.17 one level NEARER than
    // `Swashbuckle.AspNetCore -> ...Swagger` names 1.6.22, and `dotnet restore` resolves 1.6.22
    assert CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "1.6.17", false, "1.6.22", false)
    assert !CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "1.6.22", false, "1.6.17", false)
    // an equal version is not higher, so the standing selection stands and its subtree is not rewalked
    assert !CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "9.0.0", false, "9.0.0", false)
    assert !CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "9.0.0", true, "9.0.0", true)
    // Ordering is `BestNuGetVersionCompare`, the SAME comparison `SelectBestNuGetVersionIndex`
    // already uses to pick an installed version, so the two places that order versions cannot
    // drift apart. It compares the numeric core and falls back to an ordinal string compare, which
    // ranks `2.0.0-preview` ABOVE `2.0.0`; that is this kernel's established behavior, pinned by
    // the rows above, and the selection inherits it rather than introducing a second ordering.
    assert CompilationReferenceResolverKernels.ShouldSelectNuGetPackageCandidate(true, "2.0.0", false, "2.0.0-preview", false)
}

// ── the install markers that make a version directory a package ───────────────

test "the install marker names are the lowercased id, version and extensions NuGet looks for" {
    assert CompilationReferenceResolverKernels.GetNuGetPackageFileName("YamlDotNet", "16.3.0") == "yamldotnet.16.3.0.nupkg"
    assert CompilationReferenceResolverKernels.GetNuGetPackageHashFileName("YamlDotNet", "16.3.0") == "yamldotnet.16.3.0.nupkg.sha512"
    assert CompilationReferenceResolverKernels.GetInstalledNuGetPackagePath("/c/yamldotnet/16.3.0", "YamlDotNet", "16.3.0") == "/c/yamldotnet/16.3.0/yamldotnet.16.3.0.nupkg"
    assert CompilationReferenceResolverKernels.GetInstalledNuGetPackageHashPath("/c/yamldotnet/16.3.0", "YamlDotNet", "16.3.0") == "/c/yamldotnet/16.3.0/yamldotnet.16.3.0.nupkg.sha512"
}

test "the content hash marker is the base64 SHA-512 of the package bytes and nothing else" {
    // the published SHA-512 of the empty input, base64-encoded: the marker is a hash of the file
    // it sits beside, so a placeholder or a hex spelling would be a false claim about the cache
    assert CompilationReferenceResolverKernels.GetNuGetPackageContentHash(new byte[](0)) == "z4PhNX7vuL3xVChQ1m2AB9Yg5AULVxXcg/SpIdNs6c5H0NE8XYXysP+DGNKHfuwvY7kxvUdBeoGlODJ6+SfaPg=="
    assert CompilationReferenceResolverKernels.GetNuGetPackageContentHash(new byte[](0)).Length == 88
}

test "an installed version directory names its own version" {
    assert CompilationReferenceResolverKernels.GetInstalledNuGetPackageVersion("/c/yamldotnet/16.3.0") == "16.3.0"
    assert CompilationReferenceResolverKernels.GetInstalledNuGetPackageVersion("/c/omnisharp.extensions.languageserver/0.19.9") == "0.19.9"
}

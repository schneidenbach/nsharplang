namespace NSharpLang.Cli

import System
import System.IO

// THE INSTALL-ROOT DETECTION THAT DECIDES WHAT `nlc new` WRITES INTO A PROJECT'S NuGet FEED.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliParityAuditTests.cs`:
// `NewCommand_CustomInstallLayoutWithoutEnvironment_WritesDetectedFeed` (25 declaration lines, ONE
// `Assert.` row). Its row asked `ProjectFeedValue(cliBaseDirectory, null, defaultRoot)` for a
// custom toolset laid out as `<root>/lib/nlc` beside `<root>/bin` and `<root>/packages`, and
// asserted the answer was `<root>/packages`.
//
// THE BODY'S NAME PROMISED SOMETHING IT NEVER DID, AND THAT IS RECORDED RATHER THAN INHERITED. It
// is called `NewCommand_…_WritesDetectedFeed` and it neither runs `nlc new` nor writes anything: it
// is a pure call on one kernel. The successor drops the misleading framing and states the rule the
// kernel actually carries — with the THREE arms the deleted row did not distinguish.
//
// THE THREE ARMS. `ProjectFeedValue` answers a LITERAL MSBuild placeholder in two of its three
// cases and a real path in only one, which is the whole point of the function and is what the
// single deleted assertion could not show:
//
//   * an explicit `NSHARP_INSTALL_DIR` override  → the literal `%NSHARP_INSTALL_DIR%/packages`
//   * a detected root that IS the default root   → the literal `%HOME%/.nsharp/packages`
//   * a detected root that is NOT the default    → a resolved `<root>/packages` path
//
// A custom layout that fails ANY of the three detection conditions falls back to the default arm,
// and each condition is separated below.

// ── the deleted row, reproduced whole ─────────────────────────────────────────
func MakeToolsetLayout(rootName: string, withBin: bool, withPackages: bool, libDirectoryName: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-installroot-" + Guid.NewGuid().ToString("N"))
    customRoot := Path.Combine(root, rootName)
    Directory.CreateDirectory(Path.Combine(Path.Combine(customRoot, libDirectoryName), "nlc"))
    if withBin {
        Directory.CreateDirectory(Path.Combine(customRoot, "bin"))
    }

    if withPackages {
        Directory.CreateDirectory(Path.Combine(customRoot, "packages"))
    }

    return root
}

test "a complete custom toolset layout is detected and its own packages directory is the feed" {
    // THE DELETED ROW, WITH THE SPACE IN THE DIRECTORY NAME IT USED KEPT DELIBERATELY.
    root := MakeToolsetLayout("toolset root", true, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")
    defaultRoot := Path.Combine(root, "default")

    feed := NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, null, defaultRoot)

    assert feed == Path.Combine(customRoot, "packages")
    // and it is a REAL PATH, not either placeholder — which the deleted row did not say
    assert (feed == NSharpInstallRoot.DefaultFeedValue) == false
    assert (feed == NSharpInstallRoot.InstallRootFeedValue) == false

    Directory.Delete(root, true)
}

// ── the two literal arms ──────────────────────────────────────────────────────

test "an explicit install-directory override wins before any detection runs" {
    // THE OVERRIDE ARM SHORT-CIRCUITS: the base directory below is the SAME complete layout the
    // block above detects, and the override still wins — so the answer is the placeholder, not
    // that layout's packages directory.
    root := MakeToolsetLayout("toolset root", true, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")

    feed := NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, "/some/other/place", Path.Combine(root, "default"))

    assert feed == "%NSHARP_INSTALL_DIR%/packages"
    assert feed == NSharpInstallRoot.InstallRootFeedValue

    Directory.Delete(root, true)
}

test "a whitespace-only override is NOT an override, so detection still runs" {
    root := MakeToolsetLayout("toolset root", true, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")

    assert NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, "   ", Path.Combine(root, "default")) == Path.Combine(customRoot, "packages")
    assert NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, "", Path.Combine(root, "default")) == Path.Combine(customRoot, "packages")

    Directory.Delete(root, true)
}

test "a detected root that IS the default root answers the HOME placeholder, not its own path" {
    root := MakeToolsetLayout("toolset root", true, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")

    // the SAME layout, but now named as the default root — the answer flips to the placeholder
    feed := NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, null, customRoot)

    assert feed == "%HOME%/.nsharp/packages"
    assert feed == NSharpInstallRoot.DefaultFeedValue

    Directory.Delete(root, true)
}

// ── the three detection conditions, separated ─────────────────────────────────

test "a layout missing bin/ is not detected and falls back to the default root" {
    root := MakeToolsetLayout("toolset root", false, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")
    defaultRoot := Path.Combine(root, "default")
    Directory.CreateDirectory(defaultRoot)

    feed := NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, null, defaultRoot)

    assert feed == NSharpInstallRoot.DefaultFeedValue
    assert (feed == Path.Combine(customRoot, "packages")) == false

    Directory.Delete(root, true)
}

test "a layout missing packages/ is not detected and falls back to the default root" {
    root := MakeToolsetLayout("toolset root", true, false, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")
    defaultRoot := Path.Combine(root, "default")
    Directory.CreateDirectory(defaultRoot)

    assert NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, null, defaultRoot) == NSharpInstallRoot.DefaultFeedValue

    Directory.Delete(root, true)
}

test "the parent directory must be named lib, and the name check ignores case" {
    // A `share/nlc` layout is NOT a toolset, however complete the rest of it is.
    shareRoot := MakeToolsetLayout("toolset root", true, true, "share")
    shareCustom := Path.Combine(shareRoot, "toolset root")
    shareDefault := Path.Combine(shareRoot, "default")
    Directory.CreateDirectory(shareDefault)

    assert NSharpInstallRoot.ProjectFeedValue(Path.Combine(Path.Combine(shareCustom, "share"), "nlc"), null, shareDefault) == NSharpInstallRoot.DefaultFeedValue

    // …while `LIB/nlc` IS one, because the comparison is case-insensitive
    libRoot := MakeToolsetLayout("toolset root", true, true, "LIB")
    libCustom := Path.Combine(libRoot, "toolset root")

    assert NSharpInstallRoot.ProjectFeedValue(Path.Combine(Path.Combine(libCustom, "LIB"), "nlc"), null, Path.Combine(libRoot, "default")) == Path.Combine(libCustom, "packages")

    Directory.Delete(shareRoot, true)
    Directory.Delete(libRoot, true)
}

// ── the resolver underneath, and the two-argument overload ────────────────────

test "Resolve answers the ROOT while ProjectFeedValue answers its packages directory" {
    root := MakeToolsetLayout("toolset root", true, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")
    defaultRoot := Path.Combine(root, "default")

    assert NSharpInstallRoot.Resolve(cliBaseDirectory, null, defaultRoot) == customRoot
    assert NSharpInstallRoot.PackagesDirectory(customRoot) == Path.Combine(customRoot, "packages")
    assert NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, null, defaultRoot) == NSharpInstallRoot.PackagesDirectory(customRoot)

    Directory.Delete(root, true)
}

test "an override is returned as a NORMALIZED directory by Resolve but as a placeholder by the feed" {
    // THE TWO FUNCTIONS DISAGREE ON PURPOSE, and this is the pair that says so: the resolver has
    // to hand back a usable path, while the feed value has to hand back a string MSBuild will
    // expand at build time.
    root := MakeToolsetLayout("toolset root", true, true, "lib")
    customRoot := Path.Combine(root, "toolset root")
    cliBaseDirectory := Path.Combine(Path.Combine(customRoot, "lib"), "nlc")

    assert NSharpInstallRoot.Resolve(cliBaseDirectory, customRoot, Path.Combine(root, "default")) == customRoot
    assert NSharpInstallRoot.ProjectFeedValue(cliBaseDirectory, customRoot, Path.Combine(root, "default")) == NSharpInstallRoot.InstallRootFeedValue

    Directory.Delete(root, true)
}

test "the two-argument feed overload compares the roots directly" {
    assert NSharpInstallRoot.ProjectFeedValue("/tmp/nsharp-a", "/tmp/nsharp-a") == NSharpInstallRoot.DefaultFeedValue
    assert NSharpInstallRoot.ProjectFeedValue("/tmp/nsharp-a", "/tmp/nsharp-b") == Path.Combine("/tmp/nsharp-a", "packages")

    // …and it compares them AFTER normalizing, so a trailing separator is not a difference
    assert NSharpInstallRoot.ProjectFeedValue("/tmp/nsharp-a/", "/tmp/nsharp-a") == NSharpInstallRoot.DefaultFeedValue
}

test "the environment variable name and both placeholder literals are the shipped strings" {
    assert NSharpInstallRoot.InstallDirEnvironmentVariable == "NSHARP_INSTALL_DIR"
    assert NSharpInstallRoot.DefaultFeedValue == "%HOME%/.nsharp/packages"
    assert NSharpInstallRoot.InstallRootFeedValue == "%NSHARP_INSTALL_DIR%/packages"
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// CONTRACTS FOR `ProjectConfig` AND ITS SOURCE WALK (020 slice 15).
//
// These came out of `tests/ProjectFileTests.cs`, which is deleted. That file asked four questions of
// this type: two `EffectiveName` shapes, the `TestFramework` default, and two `GetSourceFiles`
// walks over a hand-built temp tree.
//
// THE SKIP LIST IS THE POINT AND IT WAS SAMPLED. `ShouldSkipSourceDirectory` names TWELVE
// directories, and the deleted file's tree exercised exactly two of them (`.worktrees` and `bin`)
// while proving that `server` and `docs` are NOT skipped. A row silently deleted from that list
// makes `nlc build` start compiling `obj/`, `node_modules/` or a nested `.git` worktree — every one
// of those is a build that hangs or fails on somebody else's source. All twelve are below, plus the
// case-insensitivity the comparison is written with and two names that are deliberately kept.
func PcmNamesOf(paths: string[]): string {
    names := new string[](paths.Length)
    index := 0
    while index < paths.Length {
        names[index] = Path.GetFileName(paths[index]) ?? ""
        index = index + 1
    }

    outer := 1
    while outer < names.Length {
        current := names[outer]
        inner := outer - 1
        while inner >= 0 && String.CompareOrdinal(names[inner], current) > 0 {
            names[inner + 1] = names[inner]
            inner = inner - 1
        }

        names[inner + 1] = current
        outer = outer + 1
    }

    census := ""
    j := 0
    while j < names.Length {
        census = census + names[j] + ";"
        j = j + 1
    }

    return census
}

func PcmTempDirectory(tag: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-project-config-" + tag + "-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    return directory
}

func PcmWriteSource(directory: string, relativePath: string, text: string) {
    fullPath := Path.Combine(directory, relativePath)
    parent := Path.GetDirectoryName(fullPath)
    if parent != null {
        Directory.CreateDirectory(parent)
    }

    File.WriteAllText(fullPath, text)
}

// One `.nl` file inside a directory of the given name, and the census of what the walk finds.
func PcmWalkWithDirectory(directoryName: string): string {
    directory := PcmTempDirectory("skip")
    PcmWriteSource(directory, "Program.nl", "func main() {}\n")
    PcmWriteSource(directory, Path.Combine(directoryName, "Hidden.nl"), "func hidden() {}\n")
    config := new ProjectConfig()
    census := PcmNamesOf(config.GetSourceFiles(directory, false))
    Directory.Delete(directory, true)
    return census
}

// ── the defaults ──────────────────────────────────────────────────────────────────────────────

test "a bare ProjectConfig carries every default the compiler reads off it" {
    config := new ProjectConfig()
    assert config.TestFramework == "xunit"
    assert config.Backend == "il"
    assert config.OutputType == "exe"
    assert config.TargetFramework == "net10.0"
    assert config.Sdk == "Microsoft.NET.Sdk"
    assert config.Name == null
    assert config.Version == null
    assert config.Entry == null
    assert config.Package == null
    assert config.Dependencies.Count == 0
    assert config.TestDependencies.Count == 0
    assert config.Exclude.Count == 0
    assert config.Defines.Count == 0
}

test "the collection properties MATERIALIZE on first read, so a caller can add to them" {
    // Every one of these getters replaces a null field with a new list and returns the SAME list
    // afterwards. A getter that answered a fresh list each time would silently drop every `.Add`,
    // which is exactly how `exclude:` is populated by the deserializer.
    config := new ProjectConfig()
    config.Exclude.Add("Generated/*.nl")
    config.Exclude.Add("**/snapshots/*.nl")
    assert config.Exclude.Count == 2
    assert config.Exclude[0] == "Generated/*.nl"
    assert config.Exclude[1] == "**/snapshots/*.nl"

    config.Defines.Add("DEBUG")
    assert config.Defines.Count == 1

    config.Dependencies.Add(new Reference { Nuget: "Dapper" })
    assert config.Dependencies.Count == 1

    config.TestDependencies.Add(new Reference { Nuget: "xunit" })
    assert config.TestDependencies.Count == 1
}

test "the language and systems sections carry their own defaults" {
    language := new LanguageConfig()
    assert language.Profile == "default"
    assert language.AsyncDefaultType == "ValueTask"
    assert language.PooledAsync == false
    assert language.Systems.Mode == "strict"
    assert language.Systems.UnknownExternalCalls == "warn"
    assert language.Systems.AotTarget == "nativeaot"
    assert language.Systems.StackBudgetBytes == 4096
    assert language.Systems.AllowHotSidecars == false
    assert language.Systems.Warmup.Count == 0
    assert language.Systems.HotSummaryFiles.Count == 0

    // The stack budget's default is answered by a SEPARATE assigned-flag, so writing the default
    // value down explicitly is not the same state as leaving it out — and writing 0 is a state the
    // parser refuses rather than a state that silently reads back as 4096.
    systems := new SystemsConfig()
    systems.StackBudgetBytes = 4096
    assert systems.StackBudgetBytes == 4096
    systems.StackBudgetBytes = 0
    assert systems.StackBudgetBytes == 0
}

test "EffectiveName is the explicit name, and falls back to something non-empty when there is none" {
    named := new ProjectConfig { Name: "ExplicitName" }
    assert named.EffectiveName == "ExplicitName"

    anonymous := new ProjectConfig { Name: null }
    assert anonymous.Name == null
    fallback := anonymous.EffectiveName
    assert fallback.Length > 0

    // The C# asserted only `NotNull` and `NotEmpty`. The fallback is the CURRENT DIRECTORY's name,
    // which is what makes `nlc build` in an unnamed project produce a sensibly named assembly.
    assert fallback == Path.GetFileName(Environment.CurrentDirectory)
}

// ── the source walk ───────────────────────────────────────────────────────────────────────────

test "the source walk finds every .nl file, skips the tooling directories and hides test files" {
    directory := PcmTempDirectory("walk")
    PcmWriteSource(directory, "Program.nl", "func main() {}\n")
    PcmWriteSource(directory, "Program.tests.nl", "func test_main() {}\n")
    PcmWriteSource(directory, Path.Combine(".worktrees", "mirror/Mirror.nl"), "func mirror() {}\n")
    PcmWriteSource(directory, Path.Combine("bin", "Generated.nl"), "func generated() {}\n")
    PcmWriteSource(directory, Path.Combine("server", "Api.nl"), "func api() {}\n")
    PcmWriteSource(directory, Path.Combine("docs", "Example.nl"), "func example() {}\n")

    config := new ProjectConfig()
    assert PcmNamesOf(config.GetSourceFiles(directory, false)) == "Api.nl;Example.nl;Program.nl;"
    assert PcmNamesOf(config.GetSourceFiles(directory, true)) == "Api.nl;Example.nl;Program.nl;Program.tests.nl;"

    Directory.Delete(directory, true)
}

test "ALL TWELVE SKIPPED DIRECTORY NAMES, ONE AT A TIME" {
    // The deleted file's tree reached two of these. Each row below is the SAME tree with one
    // directory name substituted, so a name lost from the list shows up as its own failure.
    assert PcmWalkWithDirectory(".context") == "Program.nl;"
    assert PcmWalkWithDirectory(".git") == "Program.nl;"
    assert PcmWalkWithDirectory(".github") == "Program.nl;"
    assert PcmWalkWithDirectory(".hermes") == "Program.nl;"
    assert PcmWalkWithDirectory(".vscode") == "Program.nl;"
    assert PcmWalkWithDirectory(".vscode-test") == "Program.nl;"
    assert PcmWalkWithDirectory(".worktrees") == "Program.nl;"
    assert PcmWalkWithDirectory("bin") == "Program.nl;"
    assert PcmWalkWithDirectory("node_modules") == "Program.nl;"
    assert PcmWalkWithDirectory("nsharp") == "Program.nl;"
    assert PcmWalkWithDirectory("obj") == "Program.nl;"
    assert PcmWalkWithDirectory("out") == "Program.nl;"

    // The comparison is ordinal-IGNORE-CASE, so a Windows-cased `Bin` is skipped too.
    assert PcmWalkWithDirectory("BIN") == "Program.nl;"
    assert PcmWalkWithDirectory("Obj") == "Program.nl;"

    // THE CONTROL. Neighbouring names that are NOT on the list are walked — including the two the
    // deleted file relied on, and one that merely starts with a skipped name.
    assert PcmWalkWithDirectory("server") == "Hidden.nl;Program.nl;"
    assert PcmWalkWithDirectory("docs") == "Hidden.nl;Program.nl;"
    assert PcmWalkWithDirectory("binaries") == "Hidden.nl;Program.nl;"
    assert PcmWalkWithDirectory("src") == "Hidden.nl;Program.nl;"
}

test "the exclude globs are applied to the RELATIVE path, in all three glob shapes" {
    directory := PcmTempDirectory("exclude")
    PcmWriteSource(directory, "Program.nl", "func main() {}\n")
    PcmWriteSource(directory, "Program.tests.nl", "func test_main() {}\n")
    PcmWriteSource(directory, "scratch3.nl", "func scratch() {}\n")
    PcmWriteSource(directory, Path.Combine("Generated", "Api.nl"), "func api() {}\n")
    PcmWriteSource(directory, Path.Combine("tools", "snapshots/Snap.nl"), "func snap() {}\n")
    PcmWriteSource(directory, Path.Combine("Core", "Service.nl"), "func service() {}\n")

    config := new ProjectConfig()
    config.Exclude.Add("Generated/*.nl")
    config.Exclude.Add("**/snapshots/*.nl")
    config.Exclude.Add("scratch?.nl")

    assert PcmNamesOf(config.GetSourceFiles(directory, false)) == "Program.nl;Service.nl;"
    assert PcmNamesOf(config.GetSourceFiles(directory, true)) == "Program.nl;Program.tests.nl;Service.nl;"

    // THE CONTROL FOR THE THREE GLOBS. With no exclude list at all the same tree answers all five
    // files, so each pattern above is removing something rather than matching nothing.
    plain := new ProjectConfig()
    assert PcmNamesOf(plain.GetSourceFiles(directory, false)) == "Api.nl;Program.nl;Service.nl;Snap.nl;scratch3.nl;"

    Directory.Delete(directory, true)
}

test "a project root that does not exist is an EMPTY walk rather than a throw" {
    // `nlc check` on a path the user mistyped must report a diagnostic, not an unhandled
    // `DirectoryNotFoundException` out of the enumerator.
    missing := Path.Combine(Path.GetTempPath(), "nsharp-project-config-missing-" + Guid.NewGuid().ToString())
    assert !Directory.Exists(missing)

    config := new ProjectConfig()
    files := config.GetSourceFiles(missing, false)
    assert files.Length == 0

    enumerated := ProjectConfig.EnumerateSourceFileArray(missing)
    assert enumerated.Length == 0
}

test "the walk answers FULL paths, and it recurses to any depth" {
    directory := PcmTempDirectory("depth")
    PcmWriteSource(directory, Path.Combine("a", "b/c/d/Deep.nl"), "func deep() {}\n")

    config := new ProjectConfig()
    files := config.GetSourceFiles(directory, false)
    assert files.Length == 1
    assert Path.IsPathRooted(files[0])
    assert files[0].EndsWith("Deep.nl")

    Directory.Delete(directory, true)
}

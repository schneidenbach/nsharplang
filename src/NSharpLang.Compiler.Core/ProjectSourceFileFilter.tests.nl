namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// CONTRACTS FOR THE SOURCE-FILE FILTER KERNEL (020 slice 15).
//
// These came out of `tests/ProjectFileTests.cs`, which is deleted. That file asked ONE question of
// this kernel — four hand-built paths and one `Generated/*.nl` pattern, with and without tests —
// and reached the glob matcher only through that one pattern.
//
// THE MATCHER IS A HAND-WRITTEN BACKTRACKING GLOB ENGINE with a `*` arm, a `**/` arm, a `?` arm,
// a backslash-normalising comparison and a newline guard, and it decides which files `nlc build`
// compiles. Every arm is separated below. A `*` that crossed a directory separator, or a `**/` that
// did not, would have passed the deleted file's single pattern and would silently change what an
// `exclude:` list means in every project that has one.
func PsfPaths(a: string, b: string, c: string, d: string): string[] {
    result := new string[](4)
    result[0] = a
    result[1] = b
    result[2] = c
    result[3] = d
    return result
}

func PsfOne(value: string): string[] {
    result := new string[](1)
    result[0] = value
    return result
}

func PsfNone(): string[] {
    return new string[](0)
}

func PsfJoin(values: string[]): string {
    census := ""
    index := 0
    while index < values.Length {
        census = census + values[index] + ";"
        index = index + 1
    }

    return census
}

func PsfMatches(path: string, pattern: string): bool {
    return ProjectSourceFileFilter.ProjectSourceFilterMatchesPattern(path, pattern)
}

// ── the whole filter, on the deleted file's own tree ──────────────────────────────────────────

test "the filter keeps the project's own sources, drops the excluded ones and hides test files" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-source-filter-" + Guid.NewGuid().ToString())
    programFile := Path.Combine(root, "Program.nl")
    testFile := Path.Combine(root, "Program.tests.nl")
    generatedFile := Path.Combine(root, "Generated/Api.nl")
    serviceFile := Path.Combine(root, "Core/Service.nl")

    files := PsfPaths(programFile, testFile, generatedFile, serviceFile)
    excludes := PsfOne("Generated/*.nl")

    assert PsfJoin(ProjectSourceFileFilter.Filter(files, root, excludes, false)) == programFile + ";" + serviceFile + ";"
    assert PsfJoin(ProjectSourceFileFilter.Filter(files, root, excludes, true)) == programFile + ";" + testFile + ";" + serviceFile + ";"

    // THE ORDER IS THE INPUT ORDER, not a sorted one — the deleted file compared against an array
    // and therefore stated this by accident. The compiler feeds this list to the parser in order, so
    // a filter that reordered it would reorder every diagnostic in a multi-file project.
    reversed := PsfPaths(serviceFile, generatedFile, testFile, programFile)
    assert PsfJoin(ProjectSourceFileFilter.Filter(reversed, root, excludes, false)) == serviceFile + ";" + programFile + ";"

    // With no patterns at all nothing but the test file is dropped, which is the control that says
    // the pattern above did the dropping.
    assert PsfJoin(ProjectSourceFileFilter.Filter(files, root, PsfNone(), false)) == programFile + ";" + generatedFile + ";" + serviceFile + ";"
}

test "the kept-index kernel counts what it keeps even when the caller's buffer is too small" {
    // `Filter` sizes the index buffer to the input, but the kernel is written to answer the COUNT
    // regardless — the arm that makes a two-pass caller possible. Nothing exercised it.
    relativePaths := PsfPaths("Program.nl", "Program.tests.nl", "Generated/Api.nl", "Core/Service.nl")
    excludes := PsfOne("Generated/*.nl")

    roomy := new int[](4)
    assert ProjectSourceFileFilter.ProjectSourceFilterKeptIndices(relativePaths, excludes, false, roomy) == 2
    assert roomy[0] == 0
    assert roomy[1] == 3

    tiny := new int[](1)
    assert ProjectSourceFileFilter.ProjectSourceFilterKeptIndices(relativePaths, excludes, false, tiny) == 2
    assert tiny[0] == 0

    none := new int[](0)
    assert ProjectSourceFileFilter.ProjectSourceFilterKeptIndices(relativePaths, excludes, true, none) == 3
}

// ── the test-file suffix ──────────────────────────────────────────────────────────────────────

test "A TEST FILE IS ANYTHING ENDING IN `.tests.nl`, MATCHED CASE-INSENSITIVELY" {
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("Program.tests.nl")
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("a/b/Program.TESTS.NL")
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("Program.Tests.Nl")
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile(".tests.nl")

    // The near misses. Each of these is a real file name somebody writes, and each one is a SOURCE
    // file: dropping any of them from a build is a missing-type error the user cannot explain.
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("Program.nl") == false
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("Program.test.nl") == false
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("Programtests.nl") == false
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("Program.tests.nlx") == false
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("tests.nl") == false
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("") == false
    assert ProjectSourceFileFilter.ProjectSourceFilterIsTestFile("tests.n") == false
}

// ── the glob engine, one arm at a time ────────────────────────────────────────────────────────

test "a literal pattern matches the whole relative path and nothing shorter or longer" {
    assert PsfMatches("Program.nl", "Program.nl")
    assert PsfMatches("Program.nl", "Program") == false
    assert PsfMatches("Program.nl", "Program.nlx") == false
    assert PsfMatches("a/Program.nl", "Program.nl") == false
}

test "A SINGLE `*` DOES NOT CROSS A DIRECTORY SEPARATOR" {
    assert PsfMatches("Generated/Api.nl", "Generated/*.nl")
    assert PsfMatches("Generated/Api.nl", "*.nl") == false
    assert PsfMatches("Generated/Nested/Api.nl", "Generated/*.nl") == false
    assert PsfMatches("Api.nl", "*.nl")
    assert PsfMatches("Api.nl", "*")
    assert PsfMatches("a/b.nl", "*") == false

    // A `*` matches the EMPTY span too, which is what makes `Generated/*Api.nl` match `Api.nl`.
    assert PsfMatches("Generated/Api.nl", "Generated/*Api.nl")
    assert PsfMatches("Generated/XApi.nl", "Generated/*Api.nl")
}

test "`**/` CROSSES ANY NUMBER OF DIRECTORY SEPARATORS — BUT AT LEAST ONE" {
    assert PsfMatches("tools/snapshots/Snap.nl", "**/snapshots/*.nl")
    assert PsfMatches("a/b/c/snapshots/Snap.nl", "**/snapshots/*.nl")
    assert PsfMatches("tools/other/Snap.nl", "**/snapshots/*.nl") == false
    assert PsfMatches("tools/snapshots/deep/Snap.nl", "**/snapshots/*.nl") == false

    // AND HERE IS A DIVERGENCE FROM MSBUILD's GLOBS, MEASURED RATHER THAN ASSUMED. The `**/` arm
    // only retries a match AFTER it has crossed a separator, so a file sitting at the project root
    // is NOT matched by `**/name` — where MSBuild's `**/name` matches zero directories as well as
    // many. A user who writes `exclude: ["**/snapshots/*.nl"]` keeps a root-level `snapshots/`
    // directory in the build. It is pinned rather than corrected: changing what an `exclude:`
    // pattern means changes what every existing project compiles, which is a product decision and
    // not a test migration.
    assert PsfMatches("snapshots/Snap.nl", "**/snapshots/*.nl") == false
    assert PsfMatches("x/snapshots/Snap.nl", "**/snapshots/*.nl")

    // A bare `**` with no slash after it swallows the rest of the path, separators and all.
    assert PsfMatches("a/b/c/Snap.nl", "**")
    assert PsfMatches("a/b/c/Snap.nl", "a/**")
}

test "`?` matches exactly one character and never a separator" {
    assert PsfMatches("scratch3.nl", "scratch?.nl")
    assert PsfMatches("scratch33.nl", "scratch?.nl") == false
    assert PsfMatches("scratch.nl", "scratch?.nl") == false
    assert PsfMatches("a/b.nl", "a?b.nl")
}

test "a BACKSLASH in the path is normalised to a forward slash before it is compared" {
    // A Windows-shaped relative path must match the forward-slash pattern a `project.yml` carries,
    // or every `exclude:` entry silently stops working on Windows.
    assert PsfMatches("Generated\\Api.nl", "Generated/*.nl")
    assert PsfMatches("tools\\snapshots\\Snap.nl", "**/snapshots/*.nl")
    assert PsfMatches("Generated/Api.nl", "Generated\\*.nl")
}

test "the matcher is case-SENSITIVE, which the walk's directory skip list is not" {
    // Two different rules live next to each other and nothing said they disagree: a directory NAME
    // is skipped case-insensitively, while an `exclude:` PATTERN is matched exactly.
    assert PsfMatches("Generated/Api.nl", "generated/*.nl") == false
    assert PsfMatches("Generated/Api.nl", "Generated/*.NL") == false
    assert PsfMatches("Generated/Api.nl", "Generated/*.nl")
}

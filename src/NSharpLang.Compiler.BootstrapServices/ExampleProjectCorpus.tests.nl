namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// CONTRACTS FOR THE SHIPPED `examples/` CORPUS (020 slice 15).
//
// These came out of `tests/ExampleLintTests.cs`, which is deleted. Six of its declarations —
// seventeen xUnit cases once the two `[Theory]` rows are expanded — ran `nlc check --project` over
// nineteen example directories and asserted that the JSON summary reported zero errors, and that
// no result carried `NL010`.
//
// EVERY ONE OF THOSE SEVENTEEN OPENED WITH `if (!Directory.Exists(projectPath)) return;`. That is
// the skip emulation this task exists to remove: a corpus that had been moved, renamed or not
// checked out reported PASS on all seventeen. The directory list below is a hard requirement — a
// missing example fails, loudly, naming the directory.
//
// WHAT THIS FILE OWNS AND WHAT IT DOES NOT. `CheckCommand` lives in `NSharpLang.Cli` and reaches
// `CodeIntelligenceService` and `MultiFileCompiler` in `NSharpLang.Compiler`; both sit ABOVE this
// assembly, so no contract here can call them. Three of the four phases `nlc check` runs are owned
// down here and are stated below at full fidelity, against the very entry points the compiler
// itself calls:
//   * DISCOVERY — `MultiFileCompilerInputBuilder.BuildFromProject`, which is literally what
//     `MultiFileCompiler`'s project constructor calls;
//   * PARSE — `ColumnarParserRecovery.ParseFileAst`, the parser the compiler runs; and
//   * LINT — `new Linter(LinterConfig.FromEditorConfig(fileDirectory)).Lint(unit, fullPath, source)`,
//     which is character for character what `MultiFileCompiler.RunLinter` runs.
// The remaining phase, semantic analysis and IL emission, is held by the product gate's Step 10a,
// which runs the REAL `nlc` binary over a SUPERSET of these directories and fails on any error.
//
// AND THE DISCOVERY COUNTS ARE PINNED, WHICH `nlc check` NEVER STATED. A project that silently
// stops seeing half its files still reports zero errors — it just compiles less. `12-multi-file-
// projects/TestExample` carries two `.nl` files and discovers ONE, because the other is a
// `.tests.nl`; nothing anywhere said so.
//
// ONE OF THE NINETEEN IS COVERED BY NOTHING ELSE IN THE REPOSITORY. The gate's Step 10a walks
// `examples/*` and keeps a directory only when it has a `project.yml` or a top-level `.nl` file;
// `11-advanced-features` has neither (its eight sources live in eight sub-directories), so the gate
// skips it and the deleted C# theory was its only coverage. It is stated below.

func EpcRepoRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        if Directory.Exists(Path.Combine(current, "examples")) && Directory.Exists(Path.Combine(current, "src")) {
            return current
        }

        current = Path.GetDirectoryName(current)
    }

    throw new InvalidOperationException("Could not find the repository root from " + AppContext.BaseDirectory)
}

func EpcExamplesRoot(): string {
    return Path.Combine(EpcRepoRoot(), "examples")
}

// `files=<n> parseErrors=<n> lint=<code@file;…>` for one example project, walked exactly the way
// the compiler walks it. `<missing directory>` is a REPORTED answer rather than a skip.
func EpcProjectReport(relativePath: string): string {
    directory := Path.Combine(EpcExamplesRoot(), relativePath)
    if !Directory.Exists(directory) {
        return "<missing directory>"
    }

    config := ProjectFileParser.ParseFromDirectoryOrDefault(directory)
    noOverridePaths := new string[](0)
    noOverrideTexts := new string[](0)
    inputs := MultiFileCompilerInputBuilder.BuildFromProject(directory, config, noOverridePaths, noOverrideTexts)
    files := inputs.SourceFiles

    parseErrors := 0
    lint := ""
    for sourcePath in files {
        source := File.ReadAllText(sourcePath)
        parsed := ColumnarParserRecovery.ParseFileAst(source, sourcePath)
        parseErrors = parseErrors + parsed.Errors.Count
        unit := parsed.CompilationUnit
        if unit == null {
            lint = lint + "<no compilation unit>@" + (Path.GetFileName(sourcePath) ?? "") + ";"
        } else {
            fileDirectory := Path.GetDirectoryName(sourcePath) ?? directory
            linter := new Linter(LinterConfig.FromEditorConfig(fileDirectory))
            diagnostics := linter.Lint(unit, sourcePath, source)
            for diagnostic in diagnostics {
                lint = lint + diagnostic.Code + "@" + (Path.GetFileName(sourcePath) ?? "") + ";"
            }
        }
    }

    return "files=" + files.Count.ToString() + " parseErrors=" + parseErrors.ToString() + " lint=" + lint
}

func EpcDirectories(): List<string> {
    directories := new List<string>()
    directories.Add("01-hello-world")
    directories.Add("03-functions")
    directories.Add("04-pattern-matching")
    directories.Add("05-unions")
    directories.Add("06-classes-and-records")
    directories.Add("07-interfaces")
    directories.Add("08-async")
    directories.Add("09-linq-and-collections")
    directories.Add("10-interop")
    directories.Add("11-advanced-features")
    directories.Add("14-minimal-api")
    directories.Add("12-multi-file-projects/AutoDiscovery")
    directories.Add("12-multi-file-projects/MultiFileProject")
    directories.Add("12-multi-file-projects/SimpleProject")
    directories.Add("12-multi-file-projects/TestExample")
    directories.Add("12-multi-file-projects/WeatherDemo")
    directories.Add("12-multi-file-projects/imports")
    directories.Add("16-task-cli")
    directories.Add("17-issue-tracker/backend")
    return directories
}

// ── the eleven single-directory examples ──────────────────────────────────────────────────────

test "every single-directory example discovers its sources, parses clean and lints silent" {
    assert EpcProjectReport("01-hello-world") == "files=1 parseErrors=0 lint="
    assert EpcProjectReport("03-functions") == "files=7 parseErrors=0 lint="
    assert EpcProjectReport("04-pattern-matching") == "files=9 parseErrors=0 lint="
    assert EpcProjectReport("05-unions") == "files=3 parseErrors=0 lint="
    assert EpcProjectReport("06-classes-and-records") == "files=7 parseErrors=0 lint="
    assert EpcProjectReport("07-interfaces") == "files=2 parseErrors=0 lint="
    assert EpcProjectReport("08-async") == "files=1 parseErrors=0 lint="
    assert EpcProjectReport("09-linq-and-collections") == "files=5 parseErrors=0 lint="
    assert EpcProjectReport("10-interop") == "files=2 parseErrors=0 lint="
    assert EpcProjectReport("14-minimal-api") == "files=1 parseErrors=0 lint="
}

test "11-advanced-features, THE ONE EXAMPLE THE PRODUCT GATE'S OWN FILTER SKIPS" {
    // Eight sources in eight sub-directories, no top-level `.nl` and no `project.yml`, so the gate's
    // `nlc check` sweep drops it and the deleted `[Theory]` row was the only thing that looked at
    // it. The recursive walk finds all eight.
    assert EpcProjectReport("11-advanced-features") == "files=8 parseErrors=0 lint="
}

// ── the six multi-file examples ───────────────────────────────────────────────────────────────

test "every multi-file example discovers its whole file set, parses clean and lints silent" {
    assert EpcProjectReport("12-multi-file-projects/AutoDiscovery") == "files=3 parseErrors=0 lint="
    assert EpcProjectReport("12-multi-file-projects/MultiFileProject") == "files=3 parseErrors=0 lint="
    assert EpcProjectReport("12-multi-file-projects/SimpleProject") == "files=1 parseErrors=0 lint="
    assert EpcProjectReport("12-multi-file-projects/WeatherDemo") == "files=3 parseErrors=0 lint="
    assert EpcProjectReport("12-multi-file-projects/imports") == "files=2 parseErrors=0 lint="
}

test "A `.tests.nl` BESIDE A SOURCE FILE IS NOT A SOURCE FILE, AND TestExample IS WHERE IT SHOWS" {
    // Two `.nl` files on disk, one discovered. `nlc check`'s error count cannot see this, and a
    // filter that stopped hiding test files would silently start compiling them into the product
    // assembly.
    assert EpcProjectReport("12-multi-file-projects/TestExample") == "files=1 parseErrors=0 lint="

    directory := Path.Combine(EpcExamplesRoot(), "12-multi-file-projects/TestExample")
    config := ProjectFileParser.ParseFromDirectoryOrDefault(directory)
    withTests := config.GetSourceFiles(directory, true)
    withoutTests := config.GetSourceFiles(directory, false)
    assert withTests.Length == 2
    assert withoutTests.Length == 1
}

// ── the two applications ──────────────────────────────────────────────────────────────────────

test "16-task-cli — the whole application discovers, parses and lints clean" {
    // One of the two projects the deleted file asked about NL010 specifically. The census is stated
    // whole, so a NEW diagnostic of any code fails here rather than only an NL010.
    assert EpcProjectReport("16-task-cli") == "files=11 parseErrors=0 lint="
}

test "17-issue-tracker/backend — the other application, stated the same way" {
    assert EpcProjectReport("17-issue-tracker/backend") == "files=7 parseErrors=0 lint="
}

// ── the corpus as a whole ─────────────────────────────────────────────────────────────────────

test "THE CORPUS IS NINETEEN DIRECTORIES AND EVERY ONE OF THEM IS REQUIRED TO BE THERE" {
    // This is the assertion the deleted file could not make: it opened every one of its seventeen
    // cases by RETURNING when the directory was absent. A corpus that lost a project reported
    // seventeen passes.
    directories := EpcDirectories()
    assert directories.Count == 19

    root := EpcExamplesRoot()
    assert Directory.Exists(root)

    for relativePath in directories {
        assert Directory.Exists(Path.Combine(root, relativePath))
    }
}

test "the whole corpus is 77 discovered files, zero parse errors and zero lint diagnostics" {
    // The sum is what catches a project that silently stops discovering: nineteen per-project
    // equalities can all be updated one at a time, and this row makes that a visible arithmetic
    // change rather than a quiet one.
    totalFiles := 0
    totalParseErrors := 0
    census := ""

    for relativePath in EpcDirectories() {
        directory := Path.Combine(EpcExamplesRoot(), relativePath)
        config := ProjectFileParser.ParseFromDirectoryOrDefault(directory)
        noOverridePaths := new string[](0)
        noOverrideTexts := new string[](0)
        inputs := MultiFileCompilerInputBuilder.BuildFromProject(directory, config, noOverridePaths, noOverrideTexts)
        files := inputs.SourceFiles
        totalFiles = totalFiles + files.Count

        for sourcePath in files {
            source := File.ReadAllText(sourcePath)
            parsed := ColumnarParserRecovery.ParseFileAst(source, sourcePath)
            totalParseErrors = totalParseErrors + parsed.Errors.Count
            unit := parsed.CompilationUnit
            if unit != null {
                fileDirectory := Path.GetDirectoryName(sourcePath) ?? directory
                linter := new Linter(LinterConfig.FromEditorConfig(fileDirectory))
                diagnostics := linter.Lint(unit, sourcePath, source)
                for diagnostic in diagnostics {
                    census = census + relativePath + ":" + diagnostic.Code + ";"
                }
            }
        }
    }

    assert totalFiles == 77
    assert totalParseErrors == 0
    assert census == ""
}

test "THE MISSING-DIRECTORY ANSWER IS REPORTED, WHICH IS WHAT MAKES THE NINETEEN ABOVE MEAN ANYTHING" {
    // The control for the whole file. `EpcProjectReport` answers `<missing directory>` rather than
    // an empty, silently-passing report — so if any of the nineteen equalities above were reading a
    // directory that is not there, it would fail on this string rather than on `files=0`.
    assert EpcProjectReport("99-not-a-real-example") == "<missing directory>"
    assert EpcProjectReport("16-task-cli") != "<missing directory>"
}

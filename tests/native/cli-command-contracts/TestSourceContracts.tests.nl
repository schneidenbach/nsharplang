namespace NSharpLang.CliCommandContracts.Tests

import System.IO
import System.Text.Json

// THE `*.tests.nl` CONTRACT ACROSS THE COMMANDS, PROVEN AS PROCESSES.
//
// A test file is N# source. `nlc check`, `nlc fix`, `nlc lint`, `nlc format` and `nlc test` all
// read it. `nlc build` is the one command that does not: it compiles the product, exactly as
// `go build` ignores `_test.go`, so test-file errors surface through `nlc check` and `nlc test`.
// These rows pin each command's side of that rule against the shipped binary.

func WriteTestSourceProject(directory: string) {
    WriteProjectYml(directory, "name: TestSources\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
}

test "nlc build of a library made only of test files fails with a reason, never a bare decline" {
    directory := NewTempDirectory("nlc-tests-only-build")
    try {
        WriteTestSourceProject(directory)
        File.WriteAllText(Path.Combine(directory, "T.tests.nl"), "namespace T\n\ntest \"adds\" {\n    assert 1 + 1 == 2\n}\n")

        run := NlcIn(directory, "build")

        assert run.ExitCode == 1, run.Stdout + run.Stderr
        output := run.Stdout + run.Stderr
        assert output.Contains("emit.no-sources"), output
        assert output.Contains("*.tests.nl"), output
        assert output.Contains("nlc test"), output

        // The same directory is still runnable by `nlc test`.
        tested := NlcIn(directory, "test")
        assert tested.ExitCode == 0, tested.Stdout + tested.Stderr
        assert tested.Stdout.Contains("Passed: 1"), tested.Stdout
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc build compiles the product only, while nlc check reports the errors in a test file" {
    directory := NewTempDirectory("nlc-tests-check")
    try {
        WriteTestSourceProject(directory)
        File.WriteAllText(Path.Combine(directory, "Lib.nl"), "namespace L\n\nfunc one(): int => 1\n")
        File.WriteAllText(Path.Combine(directory, "Lib.tests.nl"), "namespace L\n\ntest \"bad\" {\n    x := 5\n    x\n}\n")

        built := NlcIn(directory, "build")
        assert built.ExitCode == 0, built.Stdout + built.Stderr

        checkRun := NlcIn(directory, "check")
        assert checkRun.ExitCode == 1, checkRun.Stdout + checkRun.Stderr
        document := JsonDocument.Parse(checkRun.Stdout)
        root := document.RootElement
        assert !root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("checkedFiles").GetInt32() == 2
        assert TextOf(ElementAt(root.GetProperty("results"), 0).GetProperty("file")) == "Lib.tests.nl"
        document.Dispose()

        tested := NlcIn(directory, "test")
        assert tested.ExitCode == 1, tested.Stdout + tested.Stderr
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc fix --include-review-needed removes an unused import from a test file like any other source" {
    directory := NewTempDirectory("nlc-tests-fix")
    try {
        WriteTestSourceProject(directory)
        File.WriteAllText(Path.Combine(directory, "Lib.nl"), "namespace L\n\nimport System.Text\n\nfunc one(): int => 1\n")
        testPath := Path.Combine(directory, "Lib.tests.nl")
        File.WriteAllText(testPath, "namespace L\n\nimport System.Text\n\ntest \"one\" {\n    assert one() == 1\n}\n")

        run := NlcIn(directory, "fix --include-review-needed")

        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout.Contains("\"filesModified\": 2"), run.Stdout
        assert !File.ReadAllText(testPath).Contains("import System.Text")
        assert !File.ReadAllText(Path.Combine(directory, "Lib.nl")).Contains("import System.Text")

        tested := NlcIn(directory, "test")
        assert tested.ExitCode == 0, tested.Stdout + tested.Stderr
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc lint reports an unused import in a test file" {
    directory := NewTempDirectory("nlc-tests-lint")
    try {
        WriteTestSourceProject(directory)
        File.WriteAllText(Path.Combine(directory, "Lib.nl"), "namespace L\n\nfunc one(): int => 1\n")
        File.WriteAllText(Path.Combine(directory, "Lib.tests.nl"), "namespace L\n\nimport System.Text\n\ntest \"one\" {\n    assert one() == 1\n}\n")

        run := NlcIn(directory, "lint --json")

        assert run.ExitCode == 1, run.Stdout + run.Stderr
        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("lintedFiles").GetInt32() == 2
        first := ElementAt(root.GetProperty("results"), 0)
        assert TextOf(first.GetProperty("code")) == "NL010"
        assert TextOf(first.GetProperty("file")) == "Lib.tests.nl"
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

namespace NSharpLang.CliParityAudit.Tests

import System.IO
import System.Text.Json

// `nlc test`, `nlc watch`, and `nlc doc`.

// ─── nlc test ─────────────────────────────────────────────────────────────────────────────────
test "nlc test --help documents the backend, the filter, the verbose flag, and the coverage gap" {
    run := Nlc(["test", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("Compilation backend: il")
    assert run.Stdout.Contains("--filter")
    assert run.Stdout.Contains("--verbose")
    assert run.Stdout.Contains("--coverage")
    assert run.Stdout.Contains("Coverage collection is not available")
}

test "nlc test --project --help prints help rather than resolving the missing project argument" {
    run := Nlc(["test", "--project", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Contains("Usage: nlc test")
}

test "nlc test over a project with no .tests.nl files exits 0 and says so" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", "func Main() {\n    print \"hello\"\n}\n")

        run := Nlc(["test", "--project", directory], directory)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert run.Stdout.Contains("No test files (*.tests.nl) found.")
    } finally {
        DeleteTempDirectory(directory)
    }
}

// The regression this row pins: a failed test BUILD used to fall through to the test runner and
// surface as an "invalid DLL argument" error instead of a non-zero exit.
test "nlc test exits non-zero when the test sources do not compile" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", "name: TestProject\noutputType: library\ntargetFramework: net10.0\n")
        WriteFile(directory, "Lib.nl", "func Add(a int, b int) int {\n    return a + b\n}\n")
        WriteFile(directory, "Lib.tests.nl", "test \"add works\" {\n    result := Multiply(2, 3)\n}\n")

        run := Nlc(["test", "--project", directory], directory)

        assert run.ExitCode != 0
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ─── nlc watch ────────────────────────────────────────────────────────────────────────────────

// The deleted body called `WatchCommand.Execute` in process and raced a `Task.Run` against it.
// Here the watcher is the shipped binary and the racing edit happens in this process, which is the
// same race with the roles swapped — and it additionally proves `nlc watch check` dispatches.
test "nlc watch check re-runs on a file change and returns the LAST run's exit code" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", "func Main() {\n    print \"ok\"\n}\n")

        run := NlcWithDelayedWrite(
            ["watch", "check", "--project", directory, "--debounce-ms", "50", "--max-runs", "2"],
            directory,
            Path.Combine(directory, "Program.nl"),
            "func Main() {\n    sb := new StringBuilder()\n}\n",
            1500
        )

        assert run.ExitCode == 1
        assert run.Stdout.Contains("Watching")
        assert run.Stdout.Contains("Change detected")
        assert IsBlank(run.Stderr)
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ─── nlc doc ──────────────────────────────────────────────────────────────────────────────────

func DocSource(): string {
    return "func Add(x: int, y: int): int {\n    return x + y\n}\n"
}

test "nlc doc --json writes the HTML tree and reports an ok manifest on stdout" {
    directory := NewTempDirectory()
    try {
        outputDirectory := Path.Combine(directory, "docs-out")
        WriteFile(directory, "Program.nl", DocSource())

        run := Nlc(["doc", "--project", directory, "--output", outputDirectory, "--json"], directory)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)

        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()

        assert File.Exists(Path.Combine(outputDirectory, "index.html"))
        assert File.Exists(Path.Combine(Path.Combine(outputDirectory, "symbols"), "functionaddprogram.html"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc doc without --json writes the same HTML tree and a text summary carrying no JSON envelope" {
    directory := NewTempDirectory()
    try {
        outputDirectory := Path.Combine(directory, "docs-out")
        WriteFile(directory, "Program.nl", DocSource())

        run := Nlc(["doc", "--project", directory, "--output", outputDirectory], directory)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert run.Stdout.Contains("Generated API docs for")
        assert run.Stdout.Contains("Output: " + outputDirectory)
        assert !run.Stdout.Contains("\"command\"")
        assert File.Exists(Path.Combine(outputDirectory, "index.html"))
        assert File.Exists(Path.Combine(Path.Combine(outputDirectory, "symbols"), "functionaddprogram.html"))
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc doc --json over a missing project directory exits 1 with the doc error envelope" {
    directory := NewTempDirectory()
    try {
        missingProject := Path.Combine(directory, "missing-project")

        run := Nlc(["doc", "--project", missingProject, "--json"], directory)

        assert run.ExitCode == 1
        assert IsBlank(run.Stderr)

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert (root.GetProperty("command").GetString() ?? "") == "doc"
        assert !root.GetProperty("ok").GetBoolean()
        message := root.GetProperty("error").GetProperty("message").GetString() ?? ""
        assert message.Contains("Project directory not found")
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

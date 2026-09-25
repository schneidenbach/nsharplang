namespace NSharpLang.CliParityAudit.Tests

import System.Text.Json

// `nlc lint` — the eight rows the deleted `CliParityAuditTests` made about the lint command and
// its schemaVersion 1 envelope.
func UnusedLocalSource(): string {
    return "func Main() {\n    value := 42\n}\n"
}

func CleanSource(): string {
    return "func Main() {\n    print \"hello\"\n}\n"
}

test "nlc lint --help documents its output modes, its project flag, the shipped rules, and the ignore pragma" {
    run := Nlc(["lint", "--help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("--json")
    assert run.Stdout.Contains("--text")
    assert run.Stdout.Contains("--project")
    assert run.Stdout.Contains("NL001")
    assert run.Stdout.Contains("NL006")
    assert run.Stdout.Contains("nlc:ignore")
}

test "nlc lint --json over a project with an unused local emits the versioned envelope and exits 1" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", UnusedLocalSource())

        run := Nlc(["lint", "--project", directory, "--json"], directory)

        assert run.ExitCode == 1
        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert (root.GetProperty("command").GetString() ?? "") == "lint"
        assert !root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("lintedFiles").GetInt32() > 0
        assert root.GetProperty("results").GetArrayLength() > 0
        assert root.GetProperty("summary").GetProperty("errors").GetInt32() > 0
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc lint --text also exits 1 when the project has lint errors" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", UnusedLocalSource())

        run := Nlc(["lint", "--project", directory, "--text"], directory)

        assert run.ExitCode == 1
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc lint --json over a clean project exits 0 with an ok envelope and no results" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", CleanSource())

        run := Nlc(["lint", "--project", directory, "--json"], directory)

        assert run.ExitCode == 0
        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("ok").GetBoolean()
        assert document.RootElement.GetProperty("results").GetArrayLength() == 0
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc lint --json over a missing project directory exits 1 with a structured error envelope" {
    missing := MissingDirectoryPath()

    run := Nlc(["lint", "--project", missing, "--json"], HelpWorkingDirectory())

    assert run.ExitCode == 1
    document := JsonDocument.Parse(run.Stdout)
    assert !document.RootElement.GetProperty("ok").GetBoolean()
    message := document.RootElement.GetProperty("error").GetProperty("message").GetString() ?? ""
    assert message.Contains("not found")
    document.Dispose()
}

test "nlc lint over a missing file reports it as an error result rather than an error envelope" {
    directory := NewTempDirectory()
    try {
        run := Nlc(["lint", "--project", directory, "NonExistent.nl"], directory)

        assert run.ExitCode == 1
        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert !root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("results").GetArrayLength() > 0
        firstResult := FirstElement(root.GetProperty("results"))
        assert (firstResult.GetProperty("severity").GetString() ?? "") == "error"
        message := firstResult.GetProperty("message").GetString() ?? ""
        assert message.Contains("not found")
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc lint with file arguments and no --json still defaults to the JSON envelope" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", UnusedLocalSource())

        run := Nlc(["lint", "--project", directory, "Program.nl"], directory)

        assert run.ExitCode == 1
        document := JsonDocument.Parse(run.Stdout)
        assert (document.RootElement.GetProperty("command").GetString() ?? "") == "lint"
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc lint does not mistake the --project VALUE for a file argument" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", CleanSource())

        run := Nlc(["lint", "--project", directory, directory, "Program.nl", "--json"], directory)

        assert run.ExitCode == 0
        document := JsonDocument.Parse(run.Stdout)
        assert document.RootElement.GetProperty("ok").GetBoolean()
        assert document.RootElement.GetProperty("lintedFiles").GetInt32() == 1
        assert document.RootElement.GetProperty("results").GetArrayLength() == 0
        document.Dispose()
    } finally {
        DeleteTempDirectory(directory)
    }
}

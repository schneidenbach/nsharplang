namespace NSharpLang.CliParityAudit.Tests

import System.IO

// `nlc format` — the five rows the deleted `CliParityAuditTests` made about formatting.
test "nlc format --check exits 1, names the unformatted file on stderr, and stays silent on stdout" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", "func main(){print 5}")

        run := Nlc(["format", "--project", directory, "--check"], directory)

        assert run.ExitCode == 1
        assert run.Stderr.Contains("Formatting check failed")
        assert IsBlank(run.Stdout)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc format --diff writes a unified diff for the named file and exits 0" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", "func main(){print 5}")

        run := Nlc(["format", "--project", directory, "--diff", "Program.nl"], directory)

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert run.Stdout.Contains("--- a/Program.nl")
        assert run.Stdout.Contains("+++ b/Program.nl")
        assert run.Stdout.Contains("@@ -")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc format --check discovery skips .worktrees, generated fixtures, and editor fixture trees" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "Program.nl", "func Main() {\n    print \"ok\"\n}\n")
        WriteFile(directory, "Program.tests.nl", "test \"discovered\" {\n    assert true\n}\n")

        worktree := Path.Combine(Path.Combine(directory, ".worktrees"), "old")
        Directory.CreateDirectory(worktree)
        WriteFile(worktree, "Bad.nl", "func Broken(x y) {")

        generated := Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "tests"), "fixtures"), "generated"), "Models")
        Directory.CreateDirectory(generated)
        WriteFile(generated, "Customer.nl", "record Order(id: string)\n")

        editorFixtures := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "editors"), "vscode"), "test"), "fixtures"), "errors")
        Directory.CreateDirectory(editorFixtures)
        WriteFile(editorFixtures, "MultipleSyntaxErrors.tests.nl", "func Broken(x y) {")

        run := Nlc(["format", "--project", directory, "--check"], directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("All files are properly formatted")
        assert IsBlank(run.Stderr)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc format --stdin formats the source it reads off stdin and writes the result to stdout" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "input.nl", "func main(){print 5}")

        run := NlcWithStdinFile(["format", "--stdin"], directory, Path.Combine(directory, "input.nl"))

        assert run.ExitCode == 0
        assert IsBlank(run.Stderr)
        assert run.Stdout.Contains("func main() {")
        assert run.Stdout.Contains("print 5")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc format --stdin on malformed input reports parse diagnostics on stderr and formats nothing" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "input.nl", "func main() {\n    first := 1 +\n    second := 2\n}")

        run := NlcWithStdinFile(["format", "--stdin"], directory, Path.Combine(directory, "input.nl"))

        assert run.ExitCode == 1
        assert IsBlank(run.Stdout)
        assert run.Stderr.Contains("Format failed")
        assert run.Stderr.Contains("Parse errors in stdin.nl")
    } finally {
        DeleteTempDirectory(directory)
    }
}

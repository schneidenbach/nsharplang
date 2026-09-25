namespace NSharpLang.CliParityAudit.Tests

import System.Text.RegularExpressions

// The top-level `nlc` surface: the version flags, the grouped help screen, and the unknown-command
// error. `Assert.Matches(pattern, text)` becomes `Regex.IsMatch(text, pattern)`.
func SemanticVersionPattern(): string {
    return "\\d+\\.\\d+\\.\\d+"
}

test "nlc --version exits 0 and prints a semver-shaped nlc version to stdout" {
    run := Nlc(["--version"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert IsBlank(run.Stderr)
    assert run.Stdout.Trim().StartsWith("nlc ")
    assert Regex.IsMatch(run.Stdout.Trim(), "nlc " + SemanticVersionPattern())
}

test "nlc -V is the same version flag as nlc --version" {
    run := Nlc(["-V"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert run.Stdout.Trim().StartsWith("nlc ")
}

test "nlc help groups the commands and advertises the version flag" {
    run := Nlc(["help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("Build & Run:")
    assert run.Stdout.Contains("Analysis & Fix:")
    assert run.Stdout.Contains("Code Quality:")
    assert run.Stdout.Contains("Project:")
    assert run.Stdout.Contains("Common Workflows:")
    assert run.Stdout.Contains("--version, -V")
}

test "nlc help states its own version in the header" {
    run := Nlc(["help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert Regex.IsMatch(run.Stdout, "N# Compiler \\(nlc\\) " + SemanticVersionPattern())
}

test "nlc help points at the per-command help" {
    run := Nlc(["help"], HelpWorkingDirectory())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("nlc <command> --help")
}

test "an unknown nlc command exits 1 and names both the command and nlc help on stderr" {
    run := Nlc(["frobnicate"], HelpWorkingDirectory())

    assert run.ExitCode == 1
    assert run.Stderr.Contains("Unknown command: frobnicate")
    assert run.Stderr.Contains("nlc help")
}

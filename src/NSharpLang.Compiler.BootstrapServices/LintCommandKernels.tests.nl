namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler

// THE `nlc lint` OPTION, FILE-SELECTION, OUTPUT-MODE AND MESSAGE KERNELS.
//
// These replace THREE `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `LintCommandKernels_SelectsFileArgsAfterProjectValueExclusion`, `..._SummarizesOptions` and
// `..._SelectsEffectiveOutputMode`.
//
// ONE OF THE THREE IS SPLIT, AND THE SPLIT IS FORCED. `..._SummarizesOptions` ended by driving
// `LintCommand.Execute` through a console capture for `--help` and a missing project.
// `Console.SetOut` declines on this emit path at `emit.call.static-member-unmodeled`, so those
// rows are in `tests/native/cli-command-contracts` against the spawned binary.

// ── the file arguments ────────────────────────────────────────────────────────

test "the file selector answers nothing for an empty command line" {
    assert LintCommandKernels.GetFileArgs(new string[](0)).Length == 0
}

test "the file selector excludes flags, the bare word help, and every --project VALUE" {
    files := LintCommandKernels.GetFileArgs([
        "--json",
        "--project",
        "src",
        "Program.nl",
        "src",
        "help",
        "-v",
        "Other.nl",
        "--project",
        "tests",
        "tests"
    ])

    // THE MECHANISM THE DELETED BODY'S NAME PROMISED: `src` and `tests` each appear TWICE — once
    // as a `--project` value and once as a bare word — and BOTH occurrences are excluded, because
    // the selector collects the project values first and then filters every argument equal to one
    // of them. So a file that happens to share a name with a project directory is unreachable.
    assert files.Length == 2
    assert files[0] == "Program.nl"
    assert files[1] == "Other.nl"
}

// ── the option summary ────────────────────────────────────────────────────────

test "an empty lint command line sets no option and asks for no help" {
    summary := LintCommandKernels.GetOptionSummary(new string[](0))

    assert summary.ProjectOption == null
    assert !summary.UseText
    assert !summary.UseJson
    assert !summary.ShowHelp
}

test "the lint option summary reads the project and BOTH format flags at once" {
    summary := LintCommandKernels.GetOptionSummary(["--project", "src", "--text", "--json", "Program.nl", "-h"])

    assert summary.ProjectOption == "src"
    // `--text` and `--json` are recorded independently; the CONFLICT is resolved by the output
    // mode kernel below, not here
    assert summary.UseText
    assert summary.UseJson
    assert summary.ShowHelp
}

test "lint option values are taken permissively, so a flag can be consumed as a value" {
    summary := LintCommandKernels.GetOptionSummary(["--project", "--json"])

    assert summary.ProjectOption == "--json"
    assert summary.UseJson
}

test "the bare word help asks lint for help" {
    assert LintCommandKernels.GetOptionSummary(["help"]).ShowHelp
}

// ── the output mode ───────────────────────────────────────────────────────────

test "lint defaults to json, and json WINS when both flags are given" {
    assert LintCommandKernels.GetEffectiveOutputMode(false, false) == 1
    assert LintCommandKernels.GetEffectiveOutputMode(false, true) == 1
    assert LintCommandKernels.GetEffectiveOutputMode(true, false) == 2
    // `--text --json` is not refused the way `nlc check` refuses its pair; json simply wins
    assert LintCommandKernels.GetEffectiveOutputMode(true, true) == 1
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the lint help text names the command, its usage and its failure exit condition" {
    helpText := LintCommandKernels.GetHelpText()

    assert helpText.Contains("N# Lint")
    assert helpText.Contains("Usage: nlc lint [options] [files...]")
    assert helpText.Contains("One or more errors were reported")
}

test "each diagnostic severity has the lowercase word the JSON and text output use" {
    assert LintCommandKernels.GetSeverityText(DiagnosticSeverity.Warning) == "warning"
    assert LintCommandKernels.GetSeverityText(DiagnosticSeverity.Error) == "error"
    assert LintCommandKernels.GetSeverityText(DiagnosticSeverity.Info) == "info"
}

test "the lint command's sentences singularise on one file and pluralise on more" {
    assert LintCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-lint-project") == "Directory not found: /tmp/missing-lint-project"
    assert LintCommandKernels.GetNoFilesFoundMessage() == "No .nl files found. Ensure you are in a project directory or specify files explicitly."
    assert LintCommandKernels.GetFileNotFoundMessage("Missing.nl") == "File not found: Missing.nl"
    assert LintCommandKernels.GetParseErrorsMessage("Broken.nl", "expected expression") == "Parse errors in Broken.nl: expected expression"
    assert LintCommandKernels.GetErrorLintingDiagnosticMessage("disk full") == "Error linting: disk full"
    assert LintCommandKernels.GetErrorLintingFileMessage("Broken.nl", "disk full") == "Error linting Broken.nl: disk full"
    assert LintCommandKernels.GetNoIssuesMessage(1, "0.1s") == "  Linted 1 file — no issues. [0.1s]"
    assert LintCommandKernels.GetNoIssuesMessage(2, "0.2s") == "  Linted 2 files — no issues. [0.2s]"
    assert LintCommandKernels.GetLintedInMessage("0.3s") == "  Linted in 0.3s"
    assert LintCommandKernels.GetFailedMessage("backend exploded") == "Lint failed: backend exploded"
}

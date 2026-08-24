namespace NSharpLang.Cli.Commands

// THE `nlc fix` AND `nlc check` ARGUMENT KERNELS.
//
// These replace FOUR `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `FixCommandArgumentKernels_SummarizesOptionsAndProject`, `..._SelectsEffectiveOutputMode`,
// `CheckCommandKernels_SummarizesOptionsAndSkipsBackendValue` and
// `CheckCommandKernels_SelectsEffectiveOutputMode`. Both argument kernels live in one production
// file, so their tests live in one file too.
//
// THE CHECK BODY IS SPLIT, AND THE SPLIT IS FORCED. It ended by driving `CheckCommand.Execute`
// through a console capture for `--help` and for a missing project. `Console.SetOut` declines on
// this emit path at `emit.call.static-member-unmodeled`, so those rows are in
// `tests/native/cli-command-contracts` against the spawned binary. That is strictly stronger than
// what was deleted: `CheckCommand` is still a C# file, and calling its `Execute` directly never
// proved that `nlc check` REACHES it.

// ── the fix argument summary ──────────────────────────────────────────────────

test "the fix argument summary separates a positional project from the --project option" {
    summary := FixCommandArgumentKernels.GetArgumentSummary([
        "--dry-run",
        "--text",
        "--include-review-needed",
        "--file",
        "Program.nl",
        "samples/demo"
    ])

    // `--project` was never given, so the option stays null and the trailing word is positional.
    assert summary.ProjectOption == null
    assert summary.FileOption == "Program.nl"
    assert summary.PositionalProject == "samples/demo"
    assert summary.DryRun
    assert summary.UseText
    assert summary.IncludeReviewNeeded
    assert !summary.ShowHelp
}

test "an explicit --project and a positional project are BOTH recorded" {
    // The kernel does not choose between them; it reports both and the command decides.
    summary := FixCommandArgumentKernels.GetArgumentSummary(["--project", "ignored", "samples/demo"])

    assert summary.ProjectOption == "ignored"
    assert summary.PositionalProject == "samples/demo"
}

test "fix option values are taken permissively, so a flag can be consumed as a value" {
    summary := FixCommandArgumentKernels.GetArgumentSummary(["--project", "--file", "Program.nl"])

    assert summary.ProjectOption == "--file"
    // `--file` was consumed as the project value, so the NEXT `--file` is the one that binds
    assert summary.FileOption == "Program.nl"
}

test "the bare word help asks fix for help" {
    assert FixCommandArgumentKernels.GetArgumentSummary(["help"]).ShowHelp
}

test "fix output mode is 1 for json and 2 for text" {
    assert FixCommandArgumentKernels.GetEffectiveOutputMode(false) == 1
    assert FixCommandArgumentKernels.GetEffectiveOutputMode(true) == 2
}

// ── the check argument summary ────────────────────────────────────────────────

test "the check argument summary skips the --backend VALUE when choosing the positional project" {
    // THIS IS THE MECHANISM THE DELETED BODY'S NAME PROMISED. `il` follows `--backend`, so it is
    // that option's value and NOT the positional project; `samples/demo` is.
    summary := CheckCommandKernels.GetArgumentSummary(["--backend", "il", "samples/demo", "--text", "--aot", "--systems-report"])

    assert summary.ProjectOption == null
    assert summary.BackendOption == "il"
    assert summary.PositionalProject == "samples/demo"
    assert summary.UseText
    assert summary.Aot
    assert summary.SystemsReport
    assert !summary.ShowHelp
}

test "check option values are taken permissively, so --backend can be consumed as the project" {
    summary := CheckCommandKernels.GetArgumentSummary(["--project", "--backend", "il"])

    assert summary.ProjectOption == "--backend"
    // `--backend` was consumed as the project value, and `il` is then a positional — yet the
    // backend option still reads `il`, because the parser records it as it walks
    assert summary.BackendOption == "il"
}

test "the bare word help asks check for help" {
    assert CheckCommandKernels.GetArgumentSummary(["help"]).ShowHelp
}

test "check output mode is 1 for json, 2 for text, 3 for the systems report, and -1 for both" {
    assert CheckCommandKernels.GetEffectiveOutputMode(false, false) == 1
    assert CheckCommandKernels.GetEffectiveOutputMode(true, false) == 2
    assert CheckCommandKernels.GetEffectiveOutputMode(false, true) == 3
    // `--text --systems-report` is the invalid pair the command refuses
    assert CheckCommandKernels.GetEffectiveOutputMode(true, true) == -1
}

// ── the check sentences ───────────────────────────────────────────────────────

test "the check help text names the command, its usage and its failure exit condition" {
    helpText := CheckCommandKernels.GetHelpText()

    assert helpText.Contains("N# Type Check")
    assert helpText.Contains("Usage: nlc check [options] [project-dir]")
    assert helpText.Contains("One or more errors detected")
}

test "the check command's sentences singularise on one file and pluralise on more" {
    assert CheckCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-check-project") == "Directory not found: /tmp/missing-check-project"
    assert CheckCommandKernels.GetSystemsReportTextUnavailableMessage() == "--systems-report is only available as JSON output."
    assert CheckCommandKernels.GetNoErrorsMessage(1, "0.1s") == "  Checked 1 file — no errors. [0.1s]"
    assert CheckCommandKernels.GetNoErrorsMessage(2, "0.2s") == "  Checked 2 files — no errors. [0.2s]"
    assert CheckCommandKernels.GetCheckedInMessage("0.3s") == "  Checked in 0.3s"
    assert CheckCommandKernels.GetFailedElapsedMessage("0.4s") == "  Check failed in 0.4s"
    assert CheckCommandKernels.GetFailedMessage("backend exploded") == "Check failed: backend exploded"
}

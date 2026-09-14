namespace NSharpLang.Cli.Commands

// THE `nlc clean` OPTION AND ARTIFACT-REPORT KERNELS.
//
// The kernel half of `CleanCommandKernels_SummarizesOptions`, deleted from
// `tests/CliCommandTests.cs`. That body's nine shipped-command rows — the `--help` run, the
// missing-directory run that must write to STDERR and exit 1, and the empty-directory run that
// must write to STDOUT and exit 0 — run as processes in `tests/native/cli-command-contracts`.
//
// `GetClearNuGetCachesFailedMessage` HAS TWO SHAPES AND BOTH ARE PINNED: given an empty detail it
// is one line, and given a detail it appends a NEWLINE and the detail. A single assertion on the
// non-empty case would have let the empty case grow a trailing blank line unnoticed.
test "clean option summary reads the project, all and help flags" {
    summary := CleanCommandKernels.GetOptionSummary(["--project", "samples/demo", "--all", "-h"])

    assert summary.ProjectOption == "samples/demo"
    assert summary.CleanAll
    assert summary.ShowHelp
}

test "clean option values are taken permissively, so a flag can be consumed as a value" {
    summary := CleanCommandKernels.GetOptionSummary(["--project", "--all"])

    assert summary.ProjectOption == "--all"
    assert summary.CleanAll
    assert !summary.ShowHelp
}

test "the bare word help asks clean for help" {
    assert CleanCommandKernels.GetOptionSummary(["help"]).ShowHelp
}

test "the clean help text names the command, its usage and its failure banner" {
    helpText := CleanCommandKernels.GetHelpText()

    assert helpText.Contains("N# Clean")
    assert helpText.Contains("Usage: nlc clean [options]")
    assert helpText.Contains("Clean failed")
}

test "every clean sentence is spelled by a kernel, character for character" {
    assert CleanCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/nsharp-missing") == "Project directory not found: /tmp/nsharp-missing"
    assert CleanCommandKernels.GetNoArtifactsFoundMessage("/tmp/nsharp") == "No build artifacts found under /tmp/nsharp."
    assert CleanCommandKernels.GetRemovedArtifactLine("bin/Debug") == "  bin/Debug"
    assert CleanCommandKernels.GetClearedNuGetCachesMessage() == "Cleared NuGet caches."
    assert CleanCommandKernels.GetCleanFailedMessage("access denied") == "Clean failed: access denied"
}

test "the removed-artifacts header is singular for one directory and plural for two" {
    assert CleanCommandKernels.GetRemovedArtifactsHeader(1) == "Removed 1 build artifact directory:"
    assert CleanCommandKernels.GetRemovedArtifactsHeader(2) == "Removed 2 build artifact directories:"
}

test "a nuget-cache failure appends its detail on a second line, and appends nothing when empty" {
    assert CleanCommandKernels.GetClearNuGetCachesFailedMessage("") == "Failed to clear NuGet caches."
    assert CleanCommandKernels.GetClearNuGetCachesFailedMessage("nuget failed") == "Failed to clear NuGet caches.\nnuget failed"
}

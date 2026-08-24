namespace NSharpLang.Cli.Commands

// THE `nlc doctor` OPTION, MARKER AND REMEDY-SENTENCE KERNELS.
//
// The kernel half of `DoctorCommandKernels_SummarizesOptions`, deleted from
// `tests/CliCommandTests.cs`. Its three shipped-command rows run as a process in
// `tests/native/cli-command-contracts`.
//
// EVERY SENTENCE HERE IS A REMEDY, AND THAT IS WHY THEY ARE PINNED WHOLE RATHER THAN BY SUBSTRING.
// `nlc doctor` is the command a user runs when something is already wrong, so each of its lines
// has to name both the symptom and the fix — and a substring assertion would let the fix half
// rot silently. The eleven message rows below are exact-match for that reason.

test "doctor option summary reads json, both vscode switches and help together" {
    summary := DoctorCommandKernels.GetOptionSummary(["--json", "--require-vscode", "--skip-vscode", "-h"])

    assert summary.Json
    assert summary.RequireVscode
    assert summary.SkipVscode
    assert summary.ShowHelp
}

test "doctor asks for help on the bare word and on a trailing short flag, and reads json alone" {
    assert DoctorCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert DoctorCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
    assert DoctorCommandKernels.GetOptionSummary(["--json"]).Json
}

test "doctor output mode is 2 for text and 1 for json" {
    assert DoctorCommandKernels.GetOutputMode(false) == 2
    assert DoctorCommandKernels.GetOutputMode(true) == 1
}

test "the doctor help text names the command, its usage and its failure banner" {
    helpText := DoctorCommandKernels.GetHelpText()

    assert helpText.Contains("N# Doctor")
    assert helpText.Contains("Usage: nlc doctor [options]")
    assert helpText.Contains("One or more required checks failed")
}

test "every doctor remedy sentence is spelled by a kernel, character for character" {
    assert DoctorCommandKernels.GetDotnetNotFoundMessage() == "dotnet CLI was not found on PATH"
    assert DoctorCommandKernels.GetDotnetVersionFailedMessage() == "dotnet --version failed"
    assert DoctorCommandKernels.GetNlcCommandMissingMessage()
        == "nlc is running, but no nlc command was found on PATH; source ~/.nsharp/env or use your package manager shell integration"
    assert DoctorCommandKernels.GetPackageCacheMissingMessage("/tmp/nsharp")
        == "N# package cache was not found at /tmp/nsharp; rerun the N# installer"
    assert DoctorCommandKernels.GetTemplateInstalledMessage() == "nsharp-console template is installed"
    assert DoctorCommandKernels.GetTemplatesMissingMessage()
        == "nsharp-console template was not found; run the N# installer or dotnet new install NSharpLang.Templates"
    assert DoctorCommandKernels.GetLanguageServerMissingMessage()
        == "nsharp-lsp was not found on PATH; source ~/.nsharp/env or reinstall N#"
    assert DoctorCommandKernels.GetVscodeSkippedMessage() == "skipped by --skip-vscode"
    assert DoctorCommandKernels.GetVscodeRequiredMissingMessage() == "VS Code 'code' CLI was not found on PATH"
    assert DoctorCommandKernels.GetVscodeOptionalMissingMessage()
        == "VS Code 'code' CLI was not found; install VS Code or rerun with --require-vscode on developer machines"
    assert DoctorCommandKernels.GetVscodeExtensionMissingMessage("nsharp.nsharp")
        == "nsharp.nsharp is not installed; run code --install-extension nsharp.nsharp"
}

test "the doctor report's header, status line and three check markers are kernel-spelled" {
    assert DoctorCommandKernels.GetTextHeader() == "N# doctor"
    assert DoctorCommandKernels.GetStatusLine(true) == "status: ok"
    assert DoctorCommandKernels.GetStatusLine(false) == "status: problems found"
    assert DoctorCommandKernels.GetCheckMarker("pass") == "✓"
    assert DoctorCommandKernels.GetCheckMarker("warn") == "!"
    assert DoctorCommandKernels.GetCheckMarker("fail") == "x"
    assert DoctorCommandKernels.GetCheckLine("✓", "dotnet", "10.0.105") == "✓ dotnet: 10.0.105"
}

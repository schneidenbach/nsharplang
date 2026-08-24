namespace NSharpLang.Cli.Commands

// THE `nlc daemon` SUBCOMMAND AND LIFECYCLE-MESSAGE KERNELS.
//
// The kernel half of `DaemonCommandKernels_SummarizesOptions`, deleted from
// `tests/CliCommandTests.cs`. Its three shipped-command rows run as a process in
// `tests/native/cli-command-contracts`.
//
// THE SUBCOMMAND IS CASE-INSENSITIVE AND THE OPTION PARSER IS NOT. `GetOptionSummary` compares the
// first token with `String.Compare(..., OrdinalIgnoreCase)` — so `START`, `Start` and `start` are
// one subcommand — while `--project` and `--help` are matched by ordinal equality. Both halves are
// pinned, because a user who types `nlc daemon Start --PROJECT x` should get the subcommand they
// asked for and an unrecognised option, not the reverse.
//
// AN UNKNOWN SUBCOMMAND DOES **NOT** ASK FOR HELP. `["bogus"]` answers `Unknown` with `ShowHelp`
// FALSE, whereas NO arguments at all answers `ShowHelp` TRUE. The two are pinned separately below
// because the command prints its help for one and an error for the other.

test "the daemon subcommand, project option and help flag are read off the argument list" {
    summary := DaemonCommandKernels.GetOptionSummary(["status", "--project", "samples/demo"])

    assert summary.SubcommandKind == DaemonSubcommandKind.Status
    assert summary.ProjectOption == "samples/demo"
    assert !summary.ShowHelp
}

test "a subcommand and a project can be asked about with --help in the same breath" {
    summary := DaemonCommandKernels.GetOptionSummary(["start", "--project", "samples/demo", "--help"])

    assert summary.SubcommandKind == DaemonSubcommandKind.Start
    assert summary.ProjectOption == "samples/demo"
    assert summary.ShowHelp
}

test "the project option value is taken permissively, so --help lands in both places at once" {
    summary := DaemonCommandKernels.GetOptionSummary(["run", "--project", "--help"])

    assert summary.SubcommandKind == DaemonSubcommandKind.Run
    assert summary.ProjectOption == "--help"
    assert summary.ShowHelp
}

test "an unknown subcommand is Unknown and does NOT ask for help, but no arguments does" {
    unknown := DaemonCommandKernels.GetOptionSummary(["bogus"])

    assert unknown.SubcommandKind == DaemonSubcommandKind.Unknown
    assert !unknown.ShowHelp

    assert DaemonCommandKernels.GetOptionSummary(new string[](0)).ShowHelp
}

test "the daemon help text names the command, its usage and its failure banner" {
    helpText := DaemonCommandKernels.GetHelpText()

    assert helpText.Contains("N# Analysis Daemon")
    assert helpText.Contains("Usage: nlc daemon <command> [options]")
    assert helpText.Contains("Command failed")
}

test "every daemon lifecycle sentence is spelled by a kernel, character for character" {
    assert DaemonCommandKernels.GetAlreadyRunningMessage() == "Daemon is already running."
    assert DaemonCommandKernels.GetStartingMessage("samples/demo") == "Starting daemon for samples/demo..."
    assert DaemonCommandKernels.GetStartedMessage() == "Daemon started."
    assert DaemonCommandKernels.GetStartFailedMessage() == "Failed to start daemon."
    assert DaemonCommandKernels.GetNoDaemonRunningMessage() == "No daemon running."
    assert DaemonCommandKernels.GetStoppedMessage() == "Daemon stopped."
    assert DaemonCommandKernels.GetStopFailedMessage() == "Failed to stop daemon."
    assert DaemonCommandKernels.GetStatusNotRespondingMessage()
        == "Daemon is running but not responding to status queries."
}

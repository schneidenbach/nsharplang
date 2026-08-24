namespace NSharpLang.Cli

// THE TOP-LEVEL COMMAND DISPATCH, ITS VERSION LINE AND ITS ERROR LINE.
//
// The kernel half of `ProgramCommandKernels_SummarizesTopLevelCommands`, deleted from
// `tests/CliCommandTests.cs`. That body's twelve remaining rows drove the CLI — and drove it BY
// REFLECTION, through `typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program")` and
// `GetMethod("Execute", Static | Public | NonPublic).Invoke(...)`. That reflective binding is
// exactly what the AOT single-binary end state forbids, so those rows are not carried in this
// shape at all: they run as SPAWNED PROCESSES in `tests/native/cli-command-contracts`.
//
// THE COMMAND NAME IS CASE-INSENSITIVE AND THE VERSION FLAG IS NOT, AND BOTH HALVES ARE PINNED.
// `CommandEquals` goes through `String.Compare(..., OrdinalIgnoreCase)`, so `BUILD` dispatches;
// `--VERSION` and `-V` are matched by the same case-insensitive rule and answer 30, while `-v`
// LOWERCASE answers 0 — it is not the version flag. A user who types `nlc -v` gets an unknown
// command, which is the behaviour the deleted body pinned and which is easy to break by
// "tidying" the comparison.

test "an empty argument list is its own command kind" {
    assert ProgramCommandKernels.GetCommandKind(new string[](0)) == 29
}

test "a command name dispatches case-insensitively, and its own flags do not disturb it" {
    assert ProgramCommandKernels.GetCommandKind(["BUILD", "--help"]) == 1
    assert ProgramCommandKernels.GetCommandKind(["build"]) == 1
    assert ProgramCommandKernels.GetCommandKind(["run"]) == 2
    assert ProgramCommandKernels.GetCommandKind(["test"]) == 5
}

test "the version flag is case-insensitive in its long form and in its UPPERCASE short form only" {
    assert ProgramCommandKernels.GetCommandKind(["--VERSION"]) == 30
    assert ProgramCommandKernels.GetCommandKind(["--version"]) == 30
    assert ProgramCommandKernels.GetCommandKind(["-V"]) == 30

    // LOWERCASE `-v` is NOT the version flag. It answers 0 — unknown — and the CLI writes an
    // error for it.
    assert ProgramCommandKernels.GetCommandKind(["-v"]) == 0
}

test "an unrecognised command answers zero" {
    assert ProgramCommandKernels.GetCommandKind(["frobnicate"]) == 0
}

test "the version line and the error line are one-line kernels" {
    assert ProgramCommandKernels.GetVersionText("1.2.3") == "nlc 1.2.3"
    assert ProgramCommandKernels.GetErrorLine("boom") == "Error: boom"
    assert ProgramCommandKernels.GetUnknownCommandMessage("frobnicate")
        == "Unknown command: frobnicate. Run 'nlc help' to see available commands."
}

test "the help text opens with a version-stamped header and names both of its section banners" {
    helpText := ProgramCommandKernels.GetHelpText("1.2.3")

    assert helpText.StartsWith("N# Compiler (nlc) 1.2.3\n\nUsage: nlc <command> [options]")
    assert helpText.Contains("Build & Run:")
    assert helpText.Contains("Common Workflows:")
}

test "the elapsed-time formatter switches from tenths of a second to minutes at one minute" {
    // Not a row the deleted body made — `FormatElapsedMilliseconds` had NO coverage in
    // `tests/CliCommandTests.cs` at all, and it writes a number a user reads after every build.
    // The zero-padding of the seconds field is the part most likely to rot.
    assert ProgramCommandKernels.FormatElapsedMilliseconds(0) == "0.0s"
    assert ProgramCommandKernels.FormatElapsedMilliseconds(1234) == "1.2s"
    assert ProgramCommandKernels.FormatElapsedMilliseconds(59949) == "59.9s"
    assert ProgramCommandKernels.FormatElapsedMilliseconds(60000) == "1m 00s"
    assert ProgramCommandKernels.FormatElapsedMilliseconds(65000) == "1m 05s"
    assert ProgramCommandKernels.FormatElapsedMilliseconds(125000) == "2m 05s"
    assert ProgramCommandKernels.FormatElapsedMilliseconds(730000) == "12m 10s"
}

namespace NSharpLang.Cli

// THE `nlc run` OPTION, OPERAND AND MESSAGE KERNELS.
//
// This replaces `RunCommandKernels_SummarizesOptionsAndMessages`, deleted whole from
// `tests/CliCommandTests.cs`. Nothing in that body reached a process or the filesystem, so the
// whole of it lands here.
//
// `GetOptionSummary` AND `GetSourceOperand` DISAGREE ABOUT `--backend`, DELIBERATELY. The summary
// takes the FIRST `--backend` value it sees and never overwrites it; the operand scanner SKIPS the
// pair and returns the first token that is not part of it. So `["--backend", "--help"]` yields a
// backend of `--help` and NO source operand — the same two tokens read two ways, and both readings
// are pinned below because the command needs both.
test "run option summary reads the backend option and the source operand beside it" {
    args := ["--backend", "il", "Program.nl"]
    summary := RunCommandKernels.GetOptionSummary(args)

    assert summary.BackendOption == "il"
    assert !summary.ShowHelp
    assert RunCommandKernels.GetSourceOperand(args) == "Program.nl"
}

test "the bare word help asks for help, and no arguments means no source operand" {
    assert RunCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert RunCommandKernels.GetSourceOperand(new string[](0)) == null
}

test "a flag is consumed as the backend value, and the operand scanner then finds nothing" {
    args := ["--backend", "--help"]
    summary := RunCommandKernels.GetOptionSummary(args)

    assert summary.BackendOption == "--help"
    assert summary.ShowHelp
    assert RunCommandKernels.GetSourceOperand(args) == null
}

test "a trailing short help flag asks for help even behind an unrelated operand" {
    assert RunCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
}

test "the run help text names the command, its usage and its success exit code" {
    helpText := RunCommandKernels.GetHelpText()

    assert helpText.Contains("N# Run")
    assert helpText.Contains("Usage: nlc run [file.nl | --project <dir>] [options] [-- <program arguments>]")
    assert helpText.Contains("--project <dir>")
    assert helpText.Contains("Everything after -- is passed to the program unchanged.")
    assert helpText.Contains("Program ran successfully")
}

test "every run sentence is spelled by a kernel, character for character" {
    assert CommandOutputKernels.GetFileNotFoundMessage("missing.nl") == "File not found: missing.nl"
    assert RunCommandKernels.GetSourceStartingMessage("Program.nl") == "Running Program.nl..."
    assert RunCommandKernels.GetMissingProjectFileMessage() == "No project.yml found in current directory. Run 'nlc new <name>' to create a project."
    assert RunCommandKernels.GetLibraryProjectMessage() == "Cannot run a library project."
    assert RunCommandKernels.GetProjectStartingMessage() == "Running..."
    assert RunCommandKernels.GetSingleFileBackendStartMessage("Program.nl") == "Running Program.nl with the IL backend..."
    assert RunCommandKernels.GetLibrarySourceFileMessage() == "Cannot run a library source file."
    assert RunCommandKernels.GetFailedMessage("denied") == "Run failed: denied"
}

test "--project is an option with a value, never the source file to run" {
    args := ["--project", "app"]

    assert RunCommandKernels.GetProjectOption(args) == "app"
    assert RunCommandKernels.GetSourceOperand(args) == null
    assert RunCommandKernels.GetSourceOperand(["--backend", "il", "--project", "app", "Program.nl"]) == "Program.nl"
    assert RunCommandKernels.GetProjectOption(["Program.nl"]) == null
}

test "a --project with no value is reported rather than read as a file" {
    assert RunCommandKernels.IsProjectOptionMissingValue(["--project"])
    assert RunCommandKernels.IsProjectOptionMissingValue(["--backend", "il", "--project"])
    assert !RunCommandKernels.IsProjectOptionMissingValue(["--project", "app"])
    assert !RunCommandKernels.IsProjectOptionMissingValue(new string[](0))
    assert RunCommandKernels.GetSourceOperand(["--project"]) == null
}

test "the -- separator splits nlc's arguments from the program's" {
    args := ["--project", "app", "--", "--help", "--project", "x"]

    launcher := RunCommandKernels.GetLauncherArguments(args)
    program := RunCommandKernels.GetProgramArguments(args)
    assert launcher.Length == 2
    assert launcher[0] == "--project" && launcher[1] == "app"
    assert program.Length == 3
    assert program[0] == "--help" && program[1] == "--project" && program[2] == "x"
    assert !RunCommandKernels.GetOptionSummary(launcher).ShowHelp
}

test "without a separator every argument is nlc's and the program gets none" {
    args := ["Program.nl"]

    assert RunCommandKernels.GetLauncherArguments(args).Length == 1
    assert RunCommandKernels.GetProgramArguments(args).Length == 0
    assert RunCommandKernels.GetProgramArguments(["--"]).Length == 0
    assert RunCommandKernels.GetLauncherArguments(["--"]).Length == 0
}

test "the launch command line quotes each program argument for the .NET host" {
    assert RunCommandKernels.GetLaunchArguments("/out/App.dll", new string[](0)) == "\"/out/App.dll\""
    assert RunCommandKernels.GetLaunchArguments("/out/App.dll", ["plain", "two words", ""]) == "\"/out/App.dll\" \"plain\" \"two words\" \"\""
    assert RunCommandKernels.QuoteProcessArgument("say \"hi\"") == "\"say \\\"hi\\\"\""
    assert RunCommandKernels.QuoteProcessArgument("C:\\dir\\") == "\"C:\\dir\\\\\""
    assert RunCommandKernels.QuoteProcessArgument("a\\\"b") == "\"a\\\\\\\"b\""
}

test "the --project sentences are spelled by kernels" {
    assert RunCommandKernels.GetProjectOptionMissingValueMessage() == "--project requires a directory."
    assert RunCommandKernels.GetMissingProjectFileAtMessage("/p") == "No project.yml found in /p. Run 'nlc new <name>' to create a project."
    assert RunCommandKernels.GetProjectAndFileConflictMessage().Contains("Cannot combine --project with a source file")
}

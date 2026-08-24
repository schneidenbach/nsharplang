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
    assert helpText.Contains("Usage: nlc run [file.nl]")
    assert helpText.Contains("Program ran successfully")
}

test "every run sentence is spelled by a kernel, character for character" {
    assert RunCommandKernels.GetFileNotFoundMessage("missing.nl") == "File not found: missing.nl"
    assert RunCommandKernels.GetSourceStartingMessage("Program.nl") == "Running Program.nl..."
    assert RunCommandKernels.GetMissingProjectFileMessage()
        == "No project.yml found in current directory. Run 'nlc new <name>' to create a project."
    assert RunCommandKernels.GetLibraryProjectMessage() == "Cannot run a library project."
    assert RunCommandKernels.GetProjectStartingMessage() == "Running..."
    assert RunCommandKernels.GetSingleFileBackendStartMessage("Program.nl")
        == "Running Program.nl with the IL backend..."
    assert RunCommandKernels.GetLibrarySourceFileMessage() == "Cannot run a library source file."
    assert RunCommandKernels.GetFailedMessage("denied") == "Run failed: denied"
}

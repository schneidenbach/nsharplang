namespace NSharpLang.Cli.Commands

// THE `nlc env` OPTION AND TEXT-LINE KERNELS.
//
// The kernel half of `EnvCommandKernels_SummarizesOptions`, deleted from `tests/CliCommandTests.cs`.
// The three rows that body made about the SHIPPED command — exit code 0, a silent stderr and
// `Usage: nlc env [options]` on stdout — are not spellable here, because `Console.SetOut` declines
// at `emit.call.static-member-unmodeled` on this emit path; they run as processes in
// `tests/native/cli-command-contracts`.
//
// `GetTextLine`'s FIRST argument is an int, not an enum, and the three rows below pin three
// different widths of the label column: `nlc version:` pads to one width, `nsharp packages:` is
// long enough to set the column itself, and `project:` pads to the same width as the first. That
// is the whole reason the kernel exists rather than an interpolation at each call site.
test "env option summary reads the json and help flags" {
    summary := EnvCommandKernels.GetOptionSummary(["--json", "-h"])

    assert summary.Json
    assert summary.ShowHelp
}

test "env asks for help on the bare word, on a trailing short flag, and reads json alone" {
    assert EnvCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert EnvCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
    assert EnvCommandKernels.GetOptionSummary(["--json"]).Json
    assert !EnvCommandKernels.GetOptionSummary(["--json"]).ShowHelp
}

test "env output mode is 2 for text and 1 for json" {
    assert EnvCommandKernels.GetOutputMode(false) == 2
    assert EnvCommandKernels.GetOutputMode(true) == 1
}

test "the env help text names the command, its usage and its always-succeeds contract" {
    helpText := EnvCommandKernels.GetHelpText()

    assert helpText.Contains("N# Environment Info")
    assert helpText.Contains("Usage: nlc env [options]")
    assert helpText.Contains("Always succeeds")
}

test "the env text lines are label-padded by the kernel, and three widths are pinned" {
    assert EnvCommandKernels.GetTextLine(1, "1.2.3") == "nlc version:    1.2.3"
    assert EnvCommandKernels.GetTextLine(8, "/tmp/packages") == "nsharp packages: /tmp/packages"
    assert EnvCommandKernels.GetTextLine(9, "Demo") == "project:        Demo"
}

namespace NSharpLang.Cli.Commands

// THE `nlc completion` SHELL-SELECTION AND MESSAGE KERNELS.
//
// These blocks replace the kernel rows of ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `CompletionCommandKernels_SummarizesOptions` (40 declaration lines, 21 `Assert.` rows).
//
// THE BODY IS SPLIT, AND THE SPLIT IS FORCED. Its last eight rows drove
// `CompletionCommand.Execute` through a console capture to read an exit code, which STREAM the
// error reached, and stdout silence. `Console.SetOut` declines on this emit path at
// `emit.call.static-member-unmodeled`, so those rows cannot be made here; they are in
// `tests/native/cli-command-contracts`, spawned against the real binary — which is strictly
// stronger, because the deleted body called `CompletionCommand.Execute` directly and never proved
// that `nlc completion` reaches it.
test "the shell name is matched case-insensitively, and each of the three has its own kind" {
    bash := CompletionCommandKernels.GetOptionSummary(["BASH"])
    assert bash.ShellKind == CompletionShellKind.Bash
    assert !bash.ShowHelp

    zshHelp := CompletionCommandKernels.GetOptionSummary(["zsh", "--help"])
    assert zshHelp.ShellKind == CompletionShellKind.Zsh
    assert zshHelp.ShowHelp

    fish := CompletionCommandKernels.GetOptionSummary(["fish"])
    assert fish.ShellKind == CompletionShellKind.Fish
    assert !fish.ShowHelp
}

test "an unrecognised shell is Unknown and does NOT ask for help" {
    unknown := CompletionCommandKernels.GetOptionSummary(["PowerShell"])

    assert unknown.ShellKind == CompletionShellKind.Unknown
    assert !unknown.ShowHelp
}

test "no arguments at all asks for help, and so do the three help spellings" {
    assert CompletionCommandKernels.GetOptionSummary([]).ShowHelp
    assert CompletionCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert CompletionCommandKernels.GetOptionSummary(["-h"]).ShowHelp
    assert CompletionCommandKernels.GetOptionSummary(["--help"]).ShowHelp
}

test "the empty argument list reports Unknown as its shell, not a default one" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It read only `.ShowHelp` from the empty call, so a
    // kernel that defaulted the shell to `Bash` on the way out would have passed it.
    assert CompletionCommandKernels.GetOptionSummary([]).ShellKind == CompletionShellKind.Unknown
}

test "the SHELL is taken from position 0 only, and the help flag from anywhere" {
    // A CONTROL THE DELETED BODY DID NOT HAVE, AND IT SEPARATES THE TWO SCANS. The shell name is
    // read from `args[0]`; the help flag is looked for across every argument. So `--help zsh`
    // asks for help and selects NOTHING, while `zsh --help` asks for help and selects zsh.
    flagFirst := CompletionCommandKernels.GetOptionSummary(["--help", "zsh"])
    assert flagFirst.ShowHelp
    assert flagFirst.ShellKind == CompletionShellKind.Unknown

    shellFirst := CompletionCommandKernels.GetOptionSummary(["zsh", "--help"])
    assert shellFirst.ShowHelp
    assert shellFirst.ShellKind == CompletionShellKind.Zsh
}

test "the bare word help is position-sensitive and is NOT a shell name" {
    // `help` at index 0 asks for help; anywhere else it is just an unrecognised first-argument
    // neighbour and the shell still comes from index 0.
    assert CompletionCommandKernels.GetOptionSummary(["help"]).ShellKind == CompletionShellKind.Unknown
    later := CompletionCommandKernels.GetOptionSummary(["bash", "help"])
    assert !later.ShowHelp
    assert later.ShellKind == CompletionShellKind.Bash
}

test "the completion help text names the command, its usage and the invalid-shell exit code" {
    helpText := CompletionCommandKernels.GetHelpText()

    assert helpText.StartsWith("N# Shell Completion")
    assert helpText.Contains("Usage: nlc completion <bash|zsh|fish>")
    assert helpText.Contains("Invalid shell name")
}

test "the unknown-shell sentence is exactly this, and it echoes the name it was given" {
    assert CompletionCommandKernels.GetUnknownShellMessage("powershell") == "Unknown shell 'powershell'. Expected bash, zsh, or fish."
    // the sentence is a pure function of its argument — a kernel hard-coding one name would pass
    // the row above and fail this one
    assert CompletionCommandKernels.GetUnknownShellMessage("tcsh") == "Unknown shell 'tcsh'. Expected bash, zsh, or fish."
}

namespace NSharpLang.Cli

// THE POSITIONAL-ARGUMENT SELECTOR EVERY COMMAND SHARES.
//
// This replaces `PositionalArgumentKernels_SelectsAllPositionals`, deleted whole from
// `tests/CliCommandTests.cs`, which made ONE `Assert.Equal` over a four-element array.
//
// THE EMPTY STRING IS A POSITIONAL, AND THAT IS THE ROW WORTH NAMING. `IsPositional` answers TRUE
// for `""` before it ever looks at a first character — so `nlc new ""` reaches the command with an
// empty project name rather than being silently swallowed, and the command gets to write the error.
// A selector that dropped it would turn a user's typo into a confusing "missing argument".
//
// THE THREE REJECTION RULES ARE INDEPENDENT AND ARE PINNED SEPARATELY: a known option CONSUMES the
// token after it, a known value-less flag consumes only itself, and any other `-`-leading token is
// skipped without consuming anything.
func PositionalOptionsWithValues(): string[] {
    return ["--template", "--type"]
}

test "the selector keeps operands, drops flags, and consumes each option's value" {
    args := [
        "--template",
        "library",
        "systems-cli",
        "PacketTool",
        "--systems",
        "--diff",
        "src/App.nl",
        "-x",
        "",
        "--type",
        "console"
    ]

    positional := PositionalArgumentKernels.GetArgs(args, PositionalOptionsWithValues())

    assert positional.Length == 4
    assert positional[0] == "systems-cli"
    assert positional[1] == "PacketTool"
    assert positional[2] == "src/App.nl"
    assert positional[3] == ""
}

test "the count kernel and the selector agree, because the selector sizes itself from the count" {
    args := [
        "--template",
        "library",
        "systems-cli",
        "PacketTool",
        "--systems",
        "--diff",
        "src/App.nl",
        "-x",
        "",
        "--type",
        "console"
    ]

    assert PositionalArgumentKernels.CountArgs(args, PositionalOptionsWithValues()) == PositionalArgumentKernels.GetArgs(args, PositionalOptionsWithValues()).Length
}

test "the empty string is a positional, so an empty operand reaches the command" {
    assert PositionalArgumentKernels.IsPositional("")
    assert PositionalArgumentKernels.IsPositional("src/App.nl")
    assert !PositionalArgumentKernels.IsPositional("-x")
    assert !PositionalArgumentKernels.IsPositional("--template")
}

test "a known option consumes the token after it, whatever that token looks like" {
    // `--template --type` yields NO positionals: `--template` eats `--type`, and there is nothing
    // left. The permissive value rule the per-command summaries use is the same rule here.
    assert PositionalArgumentKernels.GetArgs(["--template", "--type"], PositionalOptionsWithValues()).Length == 0
    assert PositionalArgumentKernels.GetArgs(["--template", "keep"], PositionalOptionsWithValues()).Length == 0
    assert PositionalArgumentKernels.IsOptionWithValue("--template", PositionalOptionsWithValues())
    assert !PositionalArgumentKernels.IsOptionWithValue("--systems", PositionalOptionsWithValues())
}

test "a value-less flag consumes only itself, so the token after it is still an operand" {
    positional := PositionalArgumentKernels.GetArgs(["--diff", "src/App.nl"], PositionalOptionsWithValues())

    assert positional.Length == 1
    assert positional[0] == "src/App.nl"
    assert PositionalArgumentKernels.IsValueLessFlag("--diff")
    assert PositionalArgumentKernels.IsValueLessFlag("--check")
    assert PositionalArgumentKernels.IsValueLessFlag("--verify-no-changes")
    assert !PositionalArgumentKernels.IsValueLessFlag("--template")
}

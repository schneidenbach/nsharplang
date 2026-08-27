namespace NSharpLang.Cli.Commands

// THE `nlc watch` TARGET, FORWARDING, OPTION, INT-PARSING AND PATH-TRIGGER KERNELS.
//
// These replace FIVE `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `WatchCommandKernels_SelectsForwardedArgs`, `..._SummarizesTargets`, `..._SummarizesOptions`,
// `..._ParsePositiveIntsWithNSharpKernel` and `..._ClassifiesChangedPathsWithNSharpKernel`.
//
// TWO OF THE FIVE ARE SPLIT, AND THE SPLIT IS FORCED, NOT CHOSEN. `..._SummarizesTargets` and
// `..._SummarizesOptions` each ended by driving `WatchCommand.Execute` through a console capture
// to read an exit code and a stderr sentence. `Console.SetOut` declines on this emit path at
// `emit.call.static-member-unmodeled`, so those rows are in `tests/native/cli-command-contracts`
// against the SPAWNED binary — which also proves that `nlc watch` reaches `WatchCommand`, a thing
// the deleted in-process calls never showed.
//
// THE TWO `foreach`-DRIVEN BODIES BECOME ONE ROW PER CASE. `..._ParsePositiveIntsWithNSharpKernel`
// looped ten `(value, expected)` tuples through one assertion and `..._ClassifiesChangedPaths...`
// looped fifteen; each is named below so a failure reports WHICH case moved.

// ── the forwarded arguments ───────────────────────────────────────────────────

test "the forwarder drops the target and the watch-only options, and keeps the rest in order" {
    forwardedArgs := WatchCommandKernels.GetForwardedArgs([
        "test",
        "--project",
        "samples/demo",
        "--filter",
        "AddPerson",
        "--debounce-ms",
        "50",
        "--json",
        "--max-runs",
        "2",
        "--coverage",
        "-h",
        "--backend",
        "il"
    ])

    // `test` is the target; `--project`, `--debounce-ms`, `--max-runs` and their values belong to
    // the watcher; `-h` is consumed as help. Everything else is handed to the inner command.
    assert forwardedArgs.Length == 6
    assert forwardedArgs[0] == "--filter"
    assert forwardedArgs[1] == "AddPerson"
    assert forwardedArgs[2] == "--json"
    assert forwardedArgs[3] == "--coverage"
    assert forwardedArgs[4] == "--backend"
    assert forwardedArgs[5] == "il"
}

// ── the target summary ────────────────────────────────────────────────────────

test "the watch target is read case-insensitively, and an unknown word is kind 0" {
    assert WatchCommandKernels.GetTargetSummary(["BUILD", "--max-runs", "1"]).TargetKind == 2
    assert WatchCommandKernels.GetTargetSummary(["serve", "--max-runs", "1"]).TargetKind == 0
}

test "each target kind maps back to the command name the user sees" {
    assert WatchCommandKernels.GetTargetCommandName(1) == "check"
    assert WatchCommandKernels.GetTargetCommandName(2) == "build"
    assert WatchCommandKernels.GetTargetCommandName(3) == "test"
    assert WatchCommandKernels.GetTargetCommandName(4) == "lint"
    assert WatchCommandKernels.GetTargetCommandName(5) == "format"
    assert WatchCommandKernels.GetTargetCommandName(0) == ""
}

test "the unsupported-target sentence names the target and lists the five that work" {
    assert WatchCommandKernels.GetUnsupportedTargetMessage("serve") == "Unsupported watch target 'serve'. Expected check, build, test, lint, or format."
}

// ── the option summary ────────────────────────────────────────────────────────

test "the watch option summary reads the project, debounce, max-runs and help flags" {
    summary := WatchCommandKernels.GetOptionSummary([
        "test",
        "--project",
        "samples/demo",
        "--debounce-ms",
        "50",
        "--max-runs",
        "2",
        "--json",
        "-h"
    ])

    assert summary.ProjectOption == "samples/demo"
    assert summary.DebounceMsOption == "50"
    assert summary.MaxRunsOption == "2"
    assert summary.ShowHelp
}

test "watch option values are taken permissively, so a flag can be consumed as a value" {
    // DELIBERATE AND PINNED. `--project` swallows `--debounce-ms`, which then swallows
    // `--max-runs`, which is left with nothing after it — so the third option ends up unset and
    // NO help is requested even though a `-`-prefixed word was consumed.
    summary := WatchCommandKernels.GetOptionSummary(["test", "--project", "--debounce-ms", "--max-runs"])

    assert summary.ProjectOption == "--debounce-ms"
    assert summary.DebounceMsOption == "--max-runs"
    assert summary.MaxRunsOption == null
    assert !summary.ShowHelp
}

test "watch with no arguments at all asks for help, and so does the bare word help" {
    assert WatchCommandKernels.GetOptionSummary(new string[](0)).ShowHelp
    assert WatchCommandKernels.GetOptionSummary(["help"]).ShowHelp
}

test "the watch help text names the command, its usage and its failure exit condition" {
    helpText := WatchCommandKernels.GetHelpText()

    assert helpText.Contains("N# Watch")
    assert helpText.Contains("Usage: nlc watch <check|build|test|lint|format>")
    assert helpText.Contains("Invalid usage or the last watched run failed")
}

test "the watch command's sentences are exactly these" {
    assert WatchCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/nsharp-missing") == "Project directory not found: /tmp/nsharp-missing"
    assert WatchCommandKernels.GetPositiveIntExpectedMessage("--debounce-ms") == "--debounce-ms expects a positive integer."
    assert WatchCommandKernels.GetStartedMessage("/tmp/nsharp") == "Watching /tmp/nsharp for N# changes. Press Ctrl+C to stop."
    assert WatchCommandKernels.GetChangeDetectedMessage("12:34:56", "check") == "Change detected at 12:34:56. Re-running `nlc check`."
}

// ── the positive-integer parser ───────────────────────────────────────────────

test "the positive-int parser trims, accepts a leading plus, and answers 0 for everything else" {
    // The ten `(value, expected)` rows of the deleted `foreach`, one assertion each.
    assert WatchCommandKernels.ParsePositiveInt("1") == 1
    assert WatchCommandKernels.ParsePositiveInt(" 25 ") == 25
    assert WatchCommandKernels.ParsePositiveInt("+3") == 3
    assert WatchCommandKernels.ParsePositiveInt("0") == 0
    assert WatchCommandKernels.ParsePositiveInt("-1") == 0
    assert WatchCommandKernels.ParsePositiveInt("2147483647") == 2147483647
    // one past Int32 is a refusal, not a wrap
    assert WatchCommandKernels.ParsePositiveInt("2147483648") == 0
    // digit-group separators are NOT accepted
    assert WatchCommandKernels.ParsePositiveInt("1_000") == 0
    assert WatchCommandKernels.ParsePositiveInt("") == 0
    assert WatchCommandKernels.ParsePositiveInt("   ") == 0
}

// ── the changed-path trigger ──────────────────────────────────────────────────

test "an N# source file triggers a re-run, on either separator and in any case" {
    // The first four rows of the deleted `foreach`.
    assert WatchCommandKernels.ShouldTriggerForChangedPath("Program.nl")
    assert WatchCommandKernels.ShouldTriggerForChangedPath("Program.NL")
    assert WatchCommandKernels.ShouldTriggerForChangedPath("src/Program.nl")
    assert WatchCommandKernels.ShouldTriggerForChangedPath("src\\Program.nl")
}

test "project.yml and .editorconfig trigger too, and a backup of one does not" {
    assert WatchCommandKernels.ShouldTriggerForChangedPath("project.yml")
    assert WatchCommandKernels.ShouldTriggerForChangedPath("PROJECT.YML")
    assert WatchCommandKernels.ShouldTriggerForChangedPath("src/project.yml")
    assert WatchCommandKernels.ShouldTriggerForChangedPath(".editorconfig")
    assert WatchCommandKernels.ShouldTriggerForChangedPath("src/.editorconfig")
    // `project.yml.bak` is NOT project.yml
    assert !WatchCommandKernels.ShouldTriggerForChangedPath("src/project.yml.bak")
}

test "a bare .nl extension with no stem still triggers, and a non-N# path does not" {
    // DELIBERATE AND PINNED: the trigger looks at the extension, so a dotfile named exactly `.nl`
    // is treated as N# source.
    assert WatchCommandKernels.ShouldTriggerForChangedPath("src/.nl")
    assert WatchCommandKernels.ShouldTriggerForChangedPath(".nl")
    assert !WatchCommandKernels.ShouldTriggerForChangedPath("src/Program.cs")
    assert !WatchCommandKernels.ShouldTriggerForChangedPath("src/nested/")
    assert !WatchCommandKernels.ShouldTriggerForChangedPath("")
}


// ══ 021/6: THE WATCH DEFAULTS ═════════════════════════════════════════════════════════════════
//
// The debounce window is the one number `nlc watch` picks for the user, and the time format is what
// every rebuild line prints. Both were spelled in `WatchCommand.cs`, one screen from the kernels
// that consume them.

test "the default debounce window is 250 ms" {
    assert WatchCommandKernels.GetDefaultDebounceMilliseconds() == 250
    // it is a POSITIVE default, which is what `ParsePositiveIntOption` requires of one
    assert WatchCommandKernels.GetDefaultDebounceMilliseconds() > 0
}

test "an absent --debounce-ms takes the default, and a given one overrides it" {
    absent := WatchCommandKernels.ParsePositiveIntOption(null, true, WatchCommandKernels.GetDefaultDebounceMilliseconds())
    given := WatchCommandKernels.ParsePositiveIntOption("40", true, WatchCommandKernels.GetDefaultDebounceMilliseconds())

    absentValue := WatchCommandKernels.GetParsedOptionalIntValue(absent)
    givenValue := WatchCommandKernels.GetParsedOptionalIntValue(given)

    assert (absentValue ?? 0) == 250
    assert (givenValue ?? 0) == 40
}

test "the change line prints a short time, not a full date" {
    assert WatchCommandKernels.GetChangeTimeFormat() == "T"
}

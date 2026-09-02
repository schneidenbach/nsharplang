namespace NSharpLang.Cli

// THE `nlc format` DISCOVERY, OPTION AND MESSAGE KERNELS.
//
// These replace TWO `[Theory]`s and one `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `FormatCommandKernels_SelectsDiscoveredPaths` (10 `[InlineData]`),
// `..._SelectsDiscoveredDirectorySkips` (8 `[InlineData]`) and `..._SummarizesOptions`.
//
// THE `[Fact]` IS SPLIT, AND THE SPLIT IS FORCED. It ended by driving `ExecuteProgram("format",
// …)` — the CLI's own top-level dispatcher — through a console capture, for a `--help` run and a
// `--stdin` misuse. `Console.SetOut` declines on this emit path at
// `emit.call.static-member-unmodeled`, so those rows are in `tests/native/cli-command-contracts`
// against the spawned binary, which proves the same dispatch for real.
//
// THE 18 `[InlineData]` CASES BECOME NAMED ROWS grouped by the rule each one exercises, so a
// failure reports WHICH exclusion moved rather than one anonymous parameterised case.

// ── the discovered-path filter ────────────────────────────────────────────────
test "a source file under src is formatted, and one under an artifact directory is not" {
    assert FormatCommandKernels.ShouldFormatDiscoveredPath("src/Program.nl")
    assert !FormatCommandKernels.ShouldFormatDiscoveredPath("bin/Debug/Generated.nl")
    assert !FormatCommandKernels.ShouldFormatDiscoveredPath("obj/generated/Temporary.nl")
    assert !FormatCommandKernels.ShouldFormatDiscoveredPath(".nlc/cache/File.nl")
}

test "a fixtures segment is excluded case-insensitively, on either separator" {
    assert !FormatCommandKernels.ShouldFormatDiscoveredPath("Tests/FIXTURES/format/case.nl")
    assert !FormatCommandKernels.ShouldFormatDiscoveredPath("editors\\vscode\\test\\fixtures\\errors\\Bad.nl")
}

test "the exclusions match a WHOLE segment, never a prefix of one" {
    // `node_modulesx` is not `node_modules`, and `Contest.nl` merely contains `test`.
    assert FormatCommandKernels.ShouldFormatDiscoveredPath("src/node_modulesx/File.nl")
    assert FormatCommandKernels.ShouldFormatDiscoveredPath("src/Contest.nl")
}

// A `.tests.nl` FILE IS DISCOVERED LIKE ANY OTHER N# SOURCE, AND THIS ROW IS THE REVERSAL OF AN
// EARLIER ONE. Discovery used to refuse the suffix, so `nlc format --project X` and
// `nlc format <file>` answered different questions about the same file and the whole contract
// estate sat outside the product gate's formatting check. Both spellings are asserted because the
// deleted rule was case-insensitive and its removal must be too.
test "a .tests.nl file IS formatted by discovery, in any case" {
    assert FormatCommandKernels.ShouldFormatDiscoveredPath("src/Calculator.tests.nl")
    assert FormatCommandKernels.ShouldFormatDiscoveredPath("src/Calculator.TESTS.NL")
}

// The one exclusion that still keeps a test source out: a fixture is deliberately malformed.
test "a .tests.nl file under a fixtures directory is still excluded" {
    assert !FormatCommandKernels.ShouldFormatDiscoveredPath("tests/fixtures/format/Case.tests.nl")
}

// ── the skipped directory names ───────────────────────────────────────────────

test "the walker skips VCS, artifact and package directories, case-insensitively" {
    assert FormatCommandKernels.ShouldSkipDiscoveredDirectoryName(".git")
    assert FormatCommandKernels.ShouldSkipDiscoveredDirectoryName(".HG")
    assert FormatCommandKernels.ShouldSkipDiscoveredDirectoryName("bin")
    assert FormatCommandKernels.ShouldSkipDiscoveredDirectoryName("OBJ")
    assert FormatCommandKernels.ShouldSkipDiscoveredDirectoryName("node_modules")
}

test "the directory skip is an EXACT name match, and fixtures is not one of the skipped names" {
    assert !FormatCommandKernels.ShouldSkipDiscoveredDirectoryName("node_modulesx")
    // `fixtures` is excluded by the PATH filter above, not by the directory walker — the two
    // rules are separate, and this row is what keeps them from being conflated.
    assert !FormatCommandKernels.ShouldSkipDiscoveredDirectoryName("fixtures")
    assert !FormatCommandKernels.ShouldSkipDiscoveredDirectoryName("src")
}

// ── the option summary ────────────────────────────────────────────────────────

test "an empty format command line sets no option and asks for no help" {
    summary := FormatCommandKernels.GetOptionSummary(new string[](0))

    assert summary.ProjectOption == null
    assert !summary.VerifyOnly
    assert !summary.DiffOnly
    assert !summary.StdinMode
    assert !summary.ShowHelp
}

test "the format option summary reads the project and the check, diff and stdin flags" {
    summary := FormatCommandKernels.GetOptionSummary(["--project", "samples/demo", "--check", "--diff", "--stdin", "-h"])

    assert summary.ProjectOption == "samples/demo"
    assert summary.VerifyOnly
    assert summary.DiffOnly
    assert summary.StdinMode
    assert summary.ShowHelp
}

test "--verify-no-changes is a second spelling of --check, and values are taken permissively" {
    summary := FormatCommandKernels.GetOptionSummary(["--project", "--check", "--verify-no-changes"])

    // `--check` was consumed as the project value, and `--verify-no-changes` still sets the same
    // verify-only flag — so the option has two names and one meaning.
    assert summary.ProjectOption == "--check"
    assert summary.VerifyOnly
    assert !summary.DiffOnly
    assert !summary.StdinMode
    assert !summary.ShowHelp
}

test "format takes help from the bare word and from either flag spelling" {
    assert FormatCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert FormatCommandKernels.GetOptionSummary(["--help"]).ShowHelp
    assert FormatCommandKernels.GetOptionSummary(["-h"]).ShowHelp
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the format help text names the command, its usage and its failure exit condition" {
    helpText := FormatCommandKernels.GetHelpText()

    assert helpText.Contains("N# Format")
    assert helpText.Contains("Usage: nlc format [options] [files...]")
    assert helpText.Contains("Formatting failed or --check found unformatted files")
}

test "the format command's failure sentences are exactly these" {
    assert FormatCommandKernels.GetStdinWithFilesMessage() == "Cannot combine --stdin with file arguments."
    assert FormatCommandKernels.GetNoFilesFoundMessage() == "No .nl files found to format."
    assert FormatCommandKernels.GetFileNotFoundMessage("Missing.nl") == "File not found: Missing.nl"
    assert FormatCommandKernels.GetErrorFormattingMessage("Broken.nl", "parse failed") == "Error formatting Broken.nl: parse failed"
    assert FormatCommandKernels.GetFailedMessage("disk full") == "Format failed: disk full"
    assert FormatCommandKernels.GetParseErrorsMessage("src/Broken.nl", "expected expression") == "Parse errors in src/Broken.nl: expected expression"
}

test "the formatter's safety-check sentences are exactly these" {
    assert FormatCommandKernels.GetWarningLine("src/Program.nl", "Formatter safety check changed trivia.") == "Warning [src/Program.nl]: Formatter safety check changed trivia."
    assert FormatCommandKernels.GetSafetyCheckFailedMessage("changed trivia; moved comment") == "Formatter safety check failed: changed trivia; moved comment"
}

test "the --check result sentences are exactly these" {
    assert FormatCommandKernels.GetCheckFailedHeader(2) == "Formatting check failed for 2 file(s):"
    assert FormatCommandKernels.GetCheckFailedPathLine("src/Program.nl") == "  src/Program.nl"
    assert FormatCommandKernels.GetAllFilesFormattedMessage() == "All files are properly formatted."
    assert FormatCommandKernels.GetFormattedCountMessage(3) == "Formatted 3 file(s)."
}

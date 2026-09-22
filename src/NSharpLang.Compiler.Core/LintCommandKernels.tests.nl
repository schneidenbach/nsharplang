namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// THE `nlc lint` OPTION, FILE-SELECTION, OUTPUT-MODE AND MESSAGE KERNELS.
//
// These replace THREE `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `LintCommandKernels_SelectsFileArgsAfterProjectValueExclusion`, `..._SummarizesOptions` and
// `..._SelectsEffectiveOutputMode`.
//
// ONE OF THE THREE IS SPLIT, AND THE SPLIT IS FORCED. `..._SummarizesOptions` ended by driving
// `LintCommand.Execute` through a console capture for `--help` and a missing project.
// `Console.SetOut` declines on this emit path at `emit.call.static-member-unmodeled`, so those
// rows are in `tests/native/cli-command-contracts` against the spawned binary.

// ── the file arguments ────────────────────────────────────────────────────────
test "the file selector answers nothing for an empty command line" {
    assert LintCommandKernels.GetFileArgs(new string[](0)).Length == 0
}

test "the file selector excludes flags, the bare word help, and every --project VALUE" {
    files := LintCommandKernels.GetFileArgs([
        "--json",
        "--project",
        "src",
        "Program.nl",
        "src",
        "help",
        "-v",
        "Other.nl",
        "--project",
        "tests",
        "tests"
    ])

    // THE MECHANISM THE DELETED BODY'S NAME PROMISED: `src` and `tests` each appear TWICE — once
    // as a `--project` value and once as a bare word — and BOTH occurrences are excluded, because
    // the selector collects the project values first and then filters every argument equal to one
    // of them. So a file that happens to share a name with a project directory is unreachable.
    assert files.Length == 2
    assert files[0] == "Program.nl"
    assert files[1] == "Other.nl"
}

// ── the option summary ────────────────────────────────────────────────────────

test "an empty lint command line sets no option and asks for no help" {
    summary := LintCommandKernels.GetOptionSummary(new string[](0))

    assert summary.ProjectOption == null
    assert !summary.UseText
    assert !summary.UseJson
    assert !summary.ShowHelp
}

test "the lint option summary reads the project and BOTH format flags at once" {
    summary := LintCommandKernels.GetOptionSummary(["--project", "src", "--text", "--json", "Program.nl", "-h"])

    assert summary.ProjectOption == "src"
    // `--text` and `--json` are recorded independently; the CONFLICT is resolved by the output
    // mode kernel below, not here
    assert summary.UseText
    assert summary.UseJson
    assert summary.ShowHelp
}

test "lint option values are taken permissively, so a flag can be consumed as a value" {
    summary := LintCommandKernels.GetOptionSummary(["--project", "--json"])

    assert summary.ProjectOption == "--json"
    assert summary.UseJson
}

test "the bare word help asks lint for help" {
    assert LintCommandKernels.GetOptionSummary(["help"]).ShowHelp
}

// ── the output mode ───────────────────────────────────────────────────────────

test "lint defaults to json, and json WINS when both flags are given" {
    assert LintCommandKernels.GetEffectiveOutputMode(false, false) == 1
    assert LintCommandKernels.GetEffectiveOutputMode(false, true) == 1
    assert LintCommandKernels.GetEffectiveOutputMode(true, false) == 2
    // `--text --json` is not refused the way `nlc check` refuses its pair; json simply wins
    assert LintCommandKernels.GetEffectiveOutputMode(true, true) == 1
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the lint help text names the command, its usage and its failure exit condition" {
    helpText := LintCommandKernels.GetHelpText()

    assert helpText.Contains("N# Lint")
    assert helpText.Contains("Usage: nlc lint [options] [files...]")
    assert helpText.Contains("One or more errors were reported")
}

test "each diagnostic severity has the lowercase word the JSON and text output use" {
    assert LintCommandKernels.GetSeverityText(DiagnosticSeverity.Warning) == "warning"
    assert LintCommandKernels.GetSeverityText(DiagnosticSeverity.Error) == "error"
    assert LintCommandKernels.GetSeverityText(DiagnosticSeverity.Info) == "info"
}

test "the lint command's sentences singularise on one file and pluralise on more" {
    assert LintCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-lint-project") == "Directory not found: /tmp/missing-lint-project"
    assert LintCommandKernels.GetNoFilesFoundMessage() == "No .nl files found. Ensure you are in a project directory or specify files explicitly."
    assert CommandOutputKernels.GetFileNotFoundMessage("Missing.nl") == "File not found: Missing.nl"
    assert LintCommandKernels.GetParseErrorsMessage("Broken.nl", "expected expression") == "Parse errors in Broken.nl: expected expression"
    assert LintCommandKernels.GetErrorLintingDiagnosticMessage("disk full") == "Error linting: disk full"
    assert LintCommandKernels.GetErrorLintingFileMessage("Broken.nl", "disk full") == "Error linting Broken.nl: disk full"
    assert LintCommandKernels.GetNoIssuesMessage(1, "0.1s") == "  Linted 1 file — no issues. [0.1s]"
    assert LintCommandKernels.GetNoIssuesMessage(2, "0.2s") == "  Linted 2 files — no issues. [0.2s]"
    assert LintCommandKernels.GetLintedInMessage("0.3s") == "  Linted in 0.3s"
    assert LintCommandKernels.GetFailedMessage("backend exploded") == "Lint failed: backend exploded"
}

// ══ 021/6: THE DIAGNOSTIC SOURCE TOKENS, THE SEVERITY WORD AND THE COMMAND NAME ════════════════
//
// `LintCommand.cs` built three `DiagnosticResult`s by hand with a literal CODE and a literal
// `"error"`, and named the command a fourth time inside its JSON error envelope. Every one of those
// four strings reaches `nlc lint --json` — the codes land in the same `code` field that carries
// `NL001`, which the seam for this slice confirms by reading both out of one envelope.

test "the two hand-built diagnostic codes are exactly these tokens" {
    assert LintCommandKernels.GetLintDiagnosticCode() == "LINT"
    assert LintCommandKernels.GetParseDiagnosticCode() == "PARSE"
    // a missing file and a parse failure are DIFFERENT codes — a JSON consumer separates them
    assert LintCommandKernels.GetLintDiagnosticCode() != LintCommandKernels.GetParseDiagnosticCode()
    // and neither collides with a real rule id
    assert LintCommandKernels.GetLintDiagnosticCode() != "NL001"
}

test "the hand-built severity is the SAME word a rule-driven row carries" {
    // The literal `"error"` in the CLI and `GetSeverityText`'s answer were two spellings of one
    // word; the accessor is defined from the severity table, so they cannot diverge.
    assert LintCommandKernels.GetErrorSeverityText() == "error"
    assert LintCommandKernels.GetErrorSeverityText() == LintCommandKernels.GetSeverityText(DiagnosticSeverity.Error)
    assert LintCommandKernels.GetErrorSeverityText() != LintCommandKernels.GetSeverityText(DiagnosticSeverity.Warning)
}

test "the lint command names itself in its JSON error envelope" {
    assert LintCommandKernels.GetCommandName() == "lint"
}

test "parse error messages join with a comma and a space" {
    assert LintCommandKernels.JoinParseErrorMessages(["expected expression"]) == "expected expression"
    assert LintCommandKernels.JoinParseErrorMessages(["expected expression", "unexpected }"]) == "expected expression, unexpected }"
    assert LintCommandKernels.JoinParseErrorMessages(new string[](0)) == ""
}

// ── the three row shapes ──────────────────────────────────────────────────────
//
// `nlc lint --json` prints results from THREE sources and only one of them is a rule. The other two
// are the command's own: a source it could not read at all, and a source the parser refused. All
// three carry the command's normalized relative path, and the rule row is otherwise field-for-field
// the row `nlc check` prints for the same diagnostic — the docs URL off the catalog included, which
// is what lets a reader follow the same link from either command.
test "a rule row carries the catalog docs URL, the rule's own suggestion, and a widened span" {
    diagnostic := new Diagnostic("NL010", "The import 'import System' is not used by any code in this file", new Location(3, 8, "Program.nl"), DiagnosticSeverity.Error, "Remove 'import System' to keep your imports clean", 6)

    result := LintCommandKernels.ToLintDiagnosticResult(diagnostic, "src/Program.nl", "import System")

    assert result.Code == "NL010"
    assert result.Severity == "error"
    assert result.File == "src/Program.nl"
    assert result.Line == 3
    assert result.Column == 8
    assert result.Length == 6
    assert result.SourceSnippet == "import System"
    assert result.Suggestion == "Remove 'import System' to keep your imports clean"
    assert result.DocsUrl == DiagnosticCatalog.DocsUrlFor("NL010")

    // A rule row states the rule and nothing more: the three fields a COMPILER error fills are
    // empty here, which is how a reader tells the two sources apart in one envelope.
    assert result.Explanation == null
    assert result.Hint == null
    assert result.ExpectedType == null
    assert result.ActualType == null
}

test "a zero-width rule span is widened to one column so the squiggle is visible" {
    diagnostic := new Diagnostic("NL001", "unused", new Location(1, 1, "Program.nl"), DiagnosticSeverity.Warning, null, 0)

    result := LintCommandKernels.ToLintDiagnosticResult(diagnostic, "Program.nl", null)

    assert result.Length == 1
    assert result.Severity == "warning"
    assert result.Suggestion == null
    assert result.SourceSnippet == null
}

test "a PARSE row reports the parser's own span under the command's invented code" {
    parseError := new CompilerError(ErrorCode.UnexpectedToken, "expected expression", 7, 12, ErrorSeverity.Error) {
        FileName: "Program.nl",
        Length: 3
    }

    result := LintCommandKernels.ToParseDiagnosticResult(parseError, "Program.nl", "    foo(")

    assert result.Code == LintCommandKernels.GetParseDiagnosticCode()
    assert result.Code == "PARSE"
    assert result.Severity == "error"
    assert result.Message == "expected expression"
    assert result.Line == 7
    assert result.Column == 12
    assert result.Length == 3
    assert result.SourceSnippet == "    foo("

    // The parser refused the source, so no rule ran on it and there is no rule to link to.
    assert result.DocsUrl == null
    assert result.Suggestion == null
}

test "a command row has no position because there is no text to point into" {
    result := LintCommandKernels.ToCommandDiagnosticResult(
        LintCommandKernels.GetLintDiagnosticCode(),
        CommandOutputKernels.GetFileNotFoundMessage("Missing.nl"),
        "Missing.nl"
    )

    assert result.Code == "LINT"
    assert result.Severity == "error"
    assert result.Message == "File not found: Missing.nl"
    assert result.File == "Missing.nl"
    assert result.Line == 0
    assert result.Column == 0
    assert result.Length == 0
    assert result.SourceSnippet == null
    assert result.DocsUrl == null
}

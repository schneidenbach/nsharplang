namespace NSharpLang.Cli.Commands

// THE `nlc audit` OPTION AND VULNERABILITY-REPORT KERNELS.
//
// The kernel half of `AuditCommandKernels_SummarizesOptions`, deleted from
// `tests/CliCommandTests.cs`. That body's three shipped-command rows, and the whole of the two
// neighbouring bodies `AuditCommand_MissingProjectDirectory_ReturnsHelpfulMessage` and
// `AuditCommand_NoCsproj_ReturnsHelpfulMessage`, run as processes in
// `tests/native/cli-command-contracts` — they assert on exit codes and on which STREAM a sentence
// reaches, and neither is observable from this emit path.
//
// THE SINGULAR/PLURAL SPLIT IS THE POINT OF `GetVulnerabilitySummaryMessage`. One vulnerability
// reads `1 vulnerability found:` and two read `2 vulnerabilities found:`; both are pinned, because
// a report a user reads under pressure should not say "1 vulnerabilities".
test "audit option summary reads the project, json and help flags" {
    summary := AuditCommandKernels.GetOptionSummary(["--project", "samples/demo", "--json", "-h"])

    assert summary.ProjectOption == "samples/demo"
    assert summary.Json
    assert summary.ShowHelp
}

test "audit option values are taken permissively, so a flag can be consumed as a value" {
    summary := AuditCommandKernels.GetOptionSummary(["--project", "--json"])

    assert summary.ProjectOption == "--json"
    assert summary.Json
    assert !summary.ShowHelp
}

test "audit asks for help on the bare word and on a trailing short flag" {
    assert AuditCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert AuditCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
}

test "audit output mode is 2 for text and 1 for json" {
    assert AuditCommandKernels.GetOutputMode(false) == 2
    assert AuditCommandKernels.GetOutputMode(true) == 1
}

test "the audit help text names the command, its usage and its failure banner" {
    helpText := AuditCommandKernels.GetHelpText()

    assert helpText.Contains("N# Security Audit")
    assert helpText.Contains("Usage: nlc audit [options]")
    assert helpText.Contains("Vulnerabilities found or audit failed")
}

test "every audit sentence is spelled by a kernel, character for character" {
    assert AuditCommandKernels.GetProjectDirectoryNotFoundMessage("/missing/project") == "Project directory not found: /missing/project"
    assert AuditCommandKernels.GetNoCsprojFileMessage() == "No .csproj file found. Run 'nlc init' to create one."
    assert AuditCommandKernels.GetVulnerableFlagUnsupportedMessage() == "The --vulnerable flag requires .NET SDK 8.0 or later."
    assert AuditCommandKernels.GetFailedMessage("denied") == "Audit failed: denied"
    assert AuditCommandKernels.GetNoKnownVulnerabilitiesMessage() == "No known vulnerabilities found."
}

test "the vulnerability summary is singular for one and plural for two" {
    assert AuditCommandKernels.GetVulnerabilitySummaryMessage(1) == "1 vulnerability found:"
    assert AuditCommandKernels.GetVulnerabilitySummaryMessage(2) == "2 vulnerabilities found:"
}

test "each vulnerability renders as an indented severity line and a further-indented url line" {
    assert AuditCommandKernels.GetVulnerabilityLine("High", "Serilog", "3.1.0") == "  High: Serilog@3.1.0"
    assert AuditCommandKernels.GetVulnerabilityUrlLine("https://example.test/advisory") == "    https://example.test/advisory"
    assert AuditCommandKernels.GetParseFailureMessage() == "  (could not parse vulnerability details)"
}

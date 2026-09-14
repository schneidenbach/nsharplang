namespace NSharpLang.Cli.Commands

// EVERY USER-FACING SENTENCE `nlc query` CAN WRITE.
//
// The kernel rows of `QueryCommandKernels_ShapesMessages`, deleted from `tests/CliCommandTests.cs`.
// That body's two shipped-command rows — `nlc query help` on stdout, and `nlc query wat` writing
// `Error: <unknown subcommand>` to stderr with exit 1 — run as processes in
// `tests/native/cli-command-contracts`, because neither the exit code nor the STREAM a sentence
// lands on is observable from this emit path.
//
// THE HELP TEXT TAKES ITS COMMAND TABLE AS AN ARGUMENT, which is what makes `nlc query help`,
// `nlc completion` and `docs/cli-reference.md` able to agree: one caller owns the list and three
// consumers render it. The row below passes a one-line table and proves it is interpolated
// verbatim rather than reformatted.
test "the query help text frames a caller-supplied command table" {
    help := QueryCommandKernels.GetHelpText("  symbols       List symbols")

    assert help.Contains("N# Code Intelligence CLI")
    assert help.Contains("Usage: nlc query <command> [options]")
    assert help.Contains("  symbols       List symbols")
    assert help.Contains("JSON queries reuse `nlc daemon` automatically")
}

test "a description gains an alias suffix only when there are aliases to name" {
    assert QueryCommandKernels.GetDescriptionWithAliases("List symbols", "ls, names") == "List symbols (aliases: ls, names)"
    assert QueryCommandKernels.GetDescriptionWithAliases("List symbols", "") == "List symbols"
}

test "the routing refusals name the subcommand and the way out of them" {
    assert QueryCommandKernels.GetUnknownSubcommandMessage("nope") == "Unknown query subcommand: nope. Run 'nlc query help' for usage."
    assert QueryCommandKernels.GetNoCompilationUnitForFileMessage("Missing.nl") == "No compilation unit found for --file Missing.nl"
    assert QueryCommandKernels.GetNoCompilationUnitsMessage() == "No compilation units in project."
    assert QueryCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing") == "Project directory not found: /tmp/missing"
    assert QueryCommandKernels.GetFailedAnalyzeProjectMessage("bad parse") == "Failed to analyze project: bad parse"
    assert QueryCommandKernels.GetFileNotFoundMessage("Missing.nl") == "File not found: Missing.nl"
}

test "the position sentences all carry file, line and column in the same shape" {
    assert QueryCommandKernels.GetPositionUsageMessage("hover") == "Usage: nlc query hover --file <path> --pos <line>:<col>"
    assert QueryCommandKernels.GetInvalidPositionMessage("bad") == "Invalid position format: bad. Expected <line>:<col> (e.g. 5:12)"
    assert QueryCommandKernels.GetNoSymbolAtPositionMessage("Program.nl", 5, 12) == "No symbol found at Program.nl:5:12"
    assert QueryCommandKernels.GetNoTypeInformationAtPositionMessage("Program.nl", 5, 12) == "No type information found at Program.nl:5:12"
    assert QueryCommandKernels.GetNoDefinitionAtPositionMessage("Program.nl", 5, 12) == "No definition found at Program.nl:5:12"
    assert QueryCommandKernels.GetNoInterfaceAtPositionMessage("Program.nl", 5, 12) == "No interface found at Program.nl:5:12"
}

test "the json-only routes say so in their own words" {
    assert QueryCommandKernels.GetPerformanceJsonOnlyMessage() == "Performance facts are only available as JSON output."
    assert QueryCommandKernels.GetTrustedJsonOnlyMessage() == "Trusted-site reports are only available as JSON output."
    assert QueryCommandKernels.GetBatchJsonOnlyMessage() == "Batch queries only support JSON output."
    assert QueryCommandKernels.GetInspectCompactTextUnsupportedMessage() == "--compact/--summary is only supported with JSON output."
}

test "the usage sentences name their own invocation" {
    assert QueryCommandKernels.GetImplementorsUsageMessage().Contains("nlc query implementors --name <interface>")
    assert QueryCommandKernels.GetBatchUsageMessage() == "Usage: nlc query batch --requests <path-to-json>"
    assert QueryCommandKernels.GetEmptyBatchMessage() == "Batch request file did not contain any requests."
    assert QueryCommandKernels.GetOutlineUsageMessage() == "Usage: nlc query outline <file>"
    assert QueryCommandKernels.GetDefinitionUsageMessage().Contains("nlc query definition --file")
    assert QueryCommandKernels.GetReferencesUsageMessage().Contains("Position-based only")
    assert QueryCommandKernels.GetDocUsageMessage().Contains("nlc query doc Console.WriteLine")
}

test "the semantic-references refusal promises, in words, that no fallback was used" {
    // This sentence is a CONTRACT, not a status line: `nlc query refs` is documented never to
    // degrade into a name or text search, and the sentence is where that promise is made to the
    // user. It is pinned whole for that reason.
    assert QueryCommandKernels.GetSemanticReferencesUnavailableMessage() == "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. No name-based or text-based fallback was used."
}

test "the documentation miss quotes the query it could not answer" {
    assert QueryCommandKernels.GetNoDocumentationMessage("Missing.Type", null) == "No documentation found for 'Missing.Type'."
}

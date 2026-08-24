namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler.CodeIntelligence

// THE `nlc query` OPTION, POSITION, OUTPUT-MODE AND MESSAGE KERNELS.
//
// These replace eleven `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `QueryCommandKernels_SummarizesDaemonParameters`, `_SummarizesCommandOptions`,
// `_SummarizesTopLevelOptions`, `_SelectsInspectOutputMode`, `_SelectsDiagnosticsOutputMode`,
// `_SelectsJsonOnlyOutputMode`, `_SelectsTextJsonOutputMode`, `_SelectsDaemonRouting`,
// `_ParsePositions`, `_ParsePositiveInts` and `_ParseSymbolKinds`, plus the message rows of
// `QueryCommandKernels_ShapesMessages`.
//
// FIVE OF THOSE BODIES ASSERTED INSIDE A `foreach` OVER A TUPLE ARRAY, so xUnit saw ONE assertion
// covering four to seventeen rows and a failure named the loop rather than the row. Every row is
// spelled out here for that reason: a regression now reports WHICH input moved.
//
// THE POSITION PARSER ACCEPTS NEGATIVE AND ZERO COORDINATES, AND THAT IS NOT A BUG TO FIX HERE.
// `-1:5` and `0:0` both parse. The kernel's contract is "is this two integers separated by one
// colon", and the RANGE check belongs to the caller that has a file to compare against. The rows
// are pinned as they are so a future narrowing is a deliberate, visible change.

// ── the daemon parameter summary ──────────────────────────────────────────────

test "the daemon parameter summary reads all five values and both flags" {
    summary := QueryCommandKernels.GetDaemonParameterSummary([
        "--file", "Program.nl",
        "--pos", "12:4",
        "--name", "Main",
        "--kind", "Function",
        "--severity", "warning",
        "--include-keywords",
        "--clusters"])

    assert summary.File == "Program.nl"
    assert summary.Pos == "12:4"
    assert summary.Name == "Main"
    assert summary.Kind == "Function"
    assert summary.Severity == "warning"
    assert summary.IncludeKeywords
    assert summary.Clusters
}

test "a daemon parameter value is taken permissively, and a trailing option keeps its null" {
    summary := QueryCommandKernels.GetDaemonParameterSummary(
        ["--file", "--include-keywords", "--pos", "--clusters", "--severity"])

    assert summary.File == "--include-keywords"
    assert summary.Pos == "--clusters"
    assert summary.Severity == null
    assert summary.IncludeKeywords
    assert summary.Clusters
}

test "a lone --file sets no flags" {
    assert !QueryCommandKernels.GetDaemonParameterSummary(["--file"]).IncludeKeywords
}

// ── the command option summary ────────────────────────────────────────────────

test "the command option summary reads the filter, function, limit, requests and operand" {
    summary := QueryCommandKernels.GetCommandOptionSummary([
        "Type.Name",
        "--filter", "*Service",
        "--function", "Main",
        "--limit", "25",
        "--requests", "batch.json"])

    assert summary.Filter == "*Service"
    assert summary.Function == "Main"
    assert summary.Limit == "25"
    assert summary.Requests == "batch.json"
    assert summary.LeadingOperand == "Type.Name"
}

test "command option values are taken permissively and a leading option is not an operand" {
    summary := QueryCommandKernels.GetCommandOptionSummary(
        ["--filter", "--function", "--limit", "--requests", "--requests"])

    assert summary.Filter == "--function"
    assert summary.Function == "--limit"
    assert summary.Limit == "--requests"
    assert summary.Requests == "--requests"
    assert summary.LeadingOperand == null
}

test "a trailing option with no value leaves both its own slot and the operand null" {
    summary := QueryCommandKernels.GetCommandOptionSummary(["--requests"])

    assert summary.Requests == null
    assert summary.LeadingOperand == null
}

// ── the top-level option summary ──────────────────────────────────────────────

test "the top-level summary takes the LAST project, keeps the first subcommand, and collects the rest" {
    summary := QueryCommandKernels.GetTopLevelOptionSummary([
        "symbols",
        "--project", "demo",
        "--file", "Program.nl",
        "--pos", "12:4",
        "--text", "--json", "--text",
        "--no-daemon", "--compact",
        "loose",
        "--project", "other"])

    assert summary.Subcommand == "symbols"
    assert summary.ProjectDir == "other"
    assert summary.File == "Program.nl"
    assert summary.Pos == "12:4"
    assert summary.UseText
    assert summary.NoDaemon
    assert summary.InspectCompact
    assert summary.RemainingArgs.Length == 1
    assert summary.RemainingArgs[0] == "loose"
}

test "a permissively consumed project value leaves nothing behind in the remaining args" {
    summary := QueryCommandKernels.GetTopLevelOptionSummary(["symbols", "--project", "--file"])

    assert summary.ProjectDir == "--file"
    assert summary.RemainingArgs.Length == 0
}

test "a trailing --project keeps its null AND survives into the remaining args" {
    // The asymmetry is the point: an option that never received a value is not consumed, so the
    // token is still there for a caller that wants to complain about it.
    summary := QueryCommandKernels.GetTopLevelOptionSummary(["symbols", "--project"])

    assert summary.ProjectDir == null
    assert summary.RemainingArgs.Length == 1
    assert summary.RemainingArgs[0] == "--project"
}

// ── the output modes ──────────────────────────────────────────────────────────

test "the inspect output mode refuses compact text and otherwise ranks compact, json, text" {
    assert QueryCommandKernels.GetInspectOutputMode(false, false) == 1
    assert QueryCommandKernels.GetInspectOutputMode(false, true) == 2
    assert QueryCommandKernels.GetInspectOutputMode(true, false) == 3
    assert QueryCommandKernels.GetInspectOutputMode(true, true) == -1
}

test "the diagnostics output mode lets clusters win over text" {
    assert QueryCommandKernels.GetDiagnosticsOutputMode(false, false) == 1
    assert QueryCommandKernels.GetDiagnosticsOutputMode(true, false) == 2
    assert QueryCommandKernels.GetDiagnosticsOutputMode(false, true) == 3
    assert QueryCommandKernels.GetDiagnosticsOutputMode(true, true) == 3
}

test "a json-only route refuses text outright, and a text-or-json route accepts both" {
    assert QueryCommandKernels.GetJsonOnlyOutputMode(false) == 1
    assert QueryCommandKernels.GetJsonOnlyOutputMode(true) == -1
    assert QueryCommandKernels.GetTextJsonOutputMode(false) == 1
    assert QueryCommandKernels.GetTextJsonOutputMode(true) == 2
}

test "the daemon is used only for json output that did not ask to bypass it" {
    assert QueryCommandKernels.ShouldUseDaemon(false, false)
    assert !QueryCommandKernels.ShouldUseDaemon(false, true)
    assert !QueryCommandKernels.ShouldUseDaemon(true, false)
    assert !QueryCommandKernels.ShouldUseDaemon(true, true)
}

// ── the position parser ───────────────────────────────────────────────────────

func QueryPositionText(position: string): string {
    line := 0
    column := 0
    parsed := QueryCommandKernels.ParsePosition(position, out line, out column)
    if parsed {
        return "ok " + line.ToString() + " " + column.ToString()
    }

    return "no " + line.ToString() + " " + column.ToString()
}

test "a position parses from two integers separated by exactly one colon" {
    assert QueryPositionText("1:1") == "ok 1 1"
    assert QueryPositionText("42:17") == "ok 42 17"
    assert QueryPositionText(" 42 : 17 ") == "ok 42 17"
    assert QueryPositionText("+64:+10") == "ok 64 10"
    assert QueryPositionText("7 :\t8") == "ok 7 8"
}

test "the position parser accepts negative and zero coordinates and the int32 extremes" {
    assert QueryPositionText("-1:5") == "ok -1 5"
    assert QueryPositionText("0:0") == "ok 0 0"
    assert QueryPositionText("2147483647:2147483647") == "ok 2147483647 2147483647"
    assert QueryPositionText("-2147483648:-2147483648") == "ok -2147483648 -2147483648"
}

test "a refused position reports what it had already read, and the out values are not uniform" {
    // These four rows are the reason the answer is rendered as text rather than as a bool: on a
    // refusal the kernel leaves DIFFERENT residue depending on how far it got, and the deleted
    // `foreach` pinned that residue too. `12:` keeps the line it parsed; `:34` keeps nothing.
    assert QueryPositionText("12:") == "no 12 0"
    assert QueryPositionText(":34") == "no 0 0"
    assert QueryPositionText("12:abc") == "no 12 0"
    assert QueryPositionText("abc:12") == "no 0 0"
    assert QueryPositionText("1:-2147483649") == "no 1 0"
}

test "two colons, an overflowing coordinate and a digit separator are all refused outright" {
    assert QueryPositionText("12:34:56") == "no 0 0"
    assert QueryPositionText("2147483648:1") == "no 0 0"
    assert QueryPositionText("1_000:2") == "no 0 0"
}

// ── the positive-integer parser ───────────────────────────────────────────────

func QueryPositiveIntText(valueText: string): string {
    value := 0
    parsed := QueryCommandKernels.ParsePositiveInt(valueText, out value)
    if parsed {
        return "ok " + value.ToString()
    }

    return "no " + value.ToString()
}

test "a positive integer parses with surrounding space and an explicit plus sign" {
    assert QueryPositiveIntText("1") == "ok 1"
    assert QueryPositiveIntText("25") == "ok 25"
    assert QueryPositiveIntText(" 25 ") == "ok 25"
    assert QueryPositiveIntText("+64") == "ok 64"
    assert QueryPositiveIntText("2147483647") == "ok 2147483647"
}

test "zero, negatives, overflow, separators, blanks and decimals are all refused with a zero out" {
    assert QueryPositiveIntText("0") == "no 0"
    assert QueryPositiveIntText("-1") == "no 0"
    assert QueryPositiveIntText("-2147483648") == "no 0"
    assert QueryPositiveIntText("2147483648") == "no 0"
    assert QueryPositiveIntText("-2147483649") == "no 0"
    assert QueryPositiveIntText("1_000") == "no 0"
    assert QueryPositiveIntText("") == "no 0"
    assert QueryPositiveIntText("   ") == "no 0"
    assert QueryPositiveIntText("12.5") == "no 0"
}

// ── the symbol-kind parser ────────────────────────────────────────────────────

func QuerySymbolKindText(valueText: string): string {
    parsed := QueryCommandKernels.ParseSymbolKind(valueText)
    value := (int)parsed.GetValueOrDefault()
    if parsed.HasValue {
        return "ok " + value.ToString()
    }

    return "no " + value.ToString()
}

test "a symbol kind parses by name, case-insensitively, with surrounding space" {
    assert QuerySymbolKindText("Function") == "ok " + ((int)SymbolKind.Function).ToString()
    assert QuerySymbolKindText("function") == "ok " + ((int)SymbolKind.Function).ToString()
    assert QuerySymbolKindText(" TypeAlias ") == "ok " + ((int)SymbolKind.TypeAlias).ToString()
    assert QuerySymbolKindText("EnumMember") == "ok " + ((int)SymbolKind.EnumMember).ToString()
}

test "a symbol kind also parses as a RAW NUMBER, including numbers no member has" {
    // This is the surprising half of the kernel and the deleted body pinned it: `15` is accepted
    // as `SymbolKind.Test`, and `-1` and `999` are accepted AS THEMSELVES even though no enum
    // member carries either value. The parser validates syntax, not membership.
    assert QuerySymbolKindText("15") == "ok " + ((int)SymbolKind.Test).ToString()
    assert QuerySymbolKindText("-1") == "ok -1"
    assert QuerySymbolKindText("999") == "ok 999"
}

test "a comma-separated list keeps the LAST kind it parsed" {
    assert QuerySymbolKindText("Function, Class") == "ok " + ((int)SymbolKind.Class).ToString()
}

test "a stranger, an empty string and blank space are refused with a zero value" {
    assert QuerySymbolKindText("not-a-kind") == "no 0"
    assert QuerySymbolKindText("") == "no 0"
    assert QuerySymbolKindText("   ") == "no 0"
}

// ── the interface-kind predicate ──────────────────────────────────────────────

test "the interface-kind predicate is case-insensitive and null-safe" {
    assert QueryCommandKernels.IsInterfaceKind("interface")
    assert QueryCommandKernels.IsInterfaceKind("INTERFACE")
    assert !QueryCommandKernels.IsInterfaceKind("class")
    assert !QueryCommandKernels.IsInterfaceKind(null)
}

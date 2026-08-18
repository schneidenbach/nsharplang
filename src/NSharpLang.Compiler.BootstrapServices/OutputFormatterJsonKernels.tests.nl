namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text.Json


// `OutputFormatterJsonKernels`: THE VERSIONED ENVELOPES EVERY `nlc query --json` ANSWER TRAVELS IN.
//
// THIS TYPE HAD NO ESTATE COVERAGE AT ALL BEFORE THIS FILE. Its only assertion layer anywhere was
// `tests/CodeIntelligenceTests.cs`, a C# file whose `OutputFormatter` receiver is a PURE FORWARDER
// — 271 lines, 38 members, each a single call into this class or its three siblings. So this is
// not a move of coverage from one place to another; it is the first time the JSON contract lives
// beside the code that writes it.
//
// THE ROOT-KEY DECODER, AND WHY IT IS NOT `EnumerateObject`. `JsonElement.EnumerateObject()` and
// `EnumerateArray()` are unreachable from N# — a `for` over either reports
// `NL202: foreach collection must be enumerable, but this collection is 'ObjectEnumerator' /
// 'ArrayEnumerator'`, casting the enumerator to `IEnumerable<JsonProperty>` declines at
// `emit.local.initializer`, `JsonSerializer.Deserialize<Dictionary<string, JsonElement>>` declines
// at `emit.call.generic-unresolved`, and the `JsonElement` INDEXER declines too. The recovery is
// not a weakening: `System.Text.Json` indents every ROOT member by exactly two spaces and escapes
// every newline that occurs inside a string, so **a rendered line that begins with two spaces and
// then a quote is a root key and nothing else can be**. `OfjkRootKeys` reads that, in document
// order, which is the same ordered list `EnumerateObject().Select(p => p.Name)` produced.
// IT SELF-VALIDATES TWICE: `OfjkRootKeysValidated` requires every key it scanned to answer
// `TryGetProperty` on the root — a scanned key that the parser cannot find fails the contract by
// name — and a dedicated negative below states that a NESTED key (`summary.errors`) never appears
// in a root-key list while it does answer as a nested property.
//
// THE GOLDEN ROOT KEYS ARE STATED HERE RATHER THAN READ FROM DISK, AND THE FIXTURE IS NOT
// ORPHANED. The C# found `tests/fixtures/json-contract-root-keys.golden.json` by walking ten
// directories upward, and `Directory.GetParent` / `DirectoryInfo.FullName` decline from N#. The
// claim — "this envelope's root keys are exactly these, in this order" — is stated inline instead,
// one contract per envelope rather than fourteen inside a single case, which is strictly more
// precise about which envelope changed. `tests/CliCommandTests.cs` still reads the same golden
// fixture, so the file remains live and cross-checked.
//
// FOUR THINGS THAT WERE IMPLICIT IN THE DELETED C# ARE STATED HERE:
//   (a) `ErrorToJson`'s `details` IS A PLAIN OBJECT GRAPH, NOT AN ANONYMOUS TYPE. The C# passed a
//       C# anonymous object; a `Dictionary<string, object>` carrying the same members serialises
//       byte-identically, and stating it that way records that the kernel never reflects over a
//       compiler-generated type.
//   (b) THE `isDefinition` FLAGS OF A REFERENCE LIST ARE STATED IN ORDER, ALL OF THEM. The C# read
//       `results[0]` only; the decoder here recovers every occurrence in document order, so a
//       reordering or a lost flag anywhere in the array fails.
//   (c) `InspectSummaryToJson` EMITS `summary` AND NOT `result` — the presence AND the absence are
//       both stated, which is what makes the compact payload a different envelope rather than a
//       superset.
//   (d) CLUSTER FILE ORDERING IS CASE-INSENSITIVE BUT CASE-PRESERVING. `src/a.nl` sorts before
//       `src/B.nl`, and `SRC/A.NL` collapses into `src/a.nl` rather than sorting apart from it.

// ── The decoders ────────────────────────────────────────────────────────────────────────────────

func OfjkHasRootKey(json: string, key: string): bool {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    probe := root
    return root.TryGetProperty(key, out probe)
}

// A rendered root member is indented by exactly two spaces; nothing nested and no string content
// can produce that shape, because every newline inside a JSON string is escaped.
func OfjkRootKeys(json: string): string {
    keys := ""
    lines := json.Split('\n')
    index := 0
    while index < lines.Length {
        line := lines[index]
        if line.Length > 3 && line[0] == ' ' && line[1] == ' ' && line[2] == '"' {
            closing := line.IndexOf('"', 3)
            if closing > 3 {
                if keys.Length > 0 {
                    keys = keys + ","
                }

                keys = keys + line.Substring(3, closing - 3)
            }
        }

        index = index + 1
    }

    return keys
}

// Every scanned key must also answer the parser. A key the scanner invented would come back here
// named, and every contract below reads this function rather than the raw scan.
func OfjkRootKeysValidated(json: string): string {
    keys := OfjkRootKeys(json)
    parts := keys.Split(',')
    index := 0
    while index < parts.Length {
        if parts[index].Length > 0 && !OfjkHasRootKey(json, parts[index]) {
            return "unvalidated:" + parts[index]
        }

        index = index + 1
    }

    return keys
}

// The ordered values of every occurrence of one scalar key, at any depth — the replacement for the
// array indexer.
func OfjkKeyValues(json: string, key: string): string {
    values := ""
    marker := "\"" + key + "\": "
    lines := json.Split('\n')
    index := 0
    while index < lines.Length {
        trimmed := lines[index].Trim()
        if trimmed.StartsWith(marker, StringComparison.Ordinal) {
            value := trimmed.Substring(marker.Length)
            if value.EndsWith(",", StringComparison.Ordinal) {
                value = value.Substring(0, value.Length - 1)
            }

            if values.Length > 0 {
                values = values + ","
            }

            values = values + value
        }

        index = index + 1
    }

    return values
}

// The ordered contents of a named array of strings, unquoted and comma-joined.
func OfjkArrayStrings(json: string, key: string): string {
    values := ""
    marker := "\"" + key + "\": ["
    lines := json.Split('\n')
    index := 0
    while index < lines.Length {
        if lines[index].Trim() == marker {
            index = index + 1
            while index < lines.Length {
                inner := lines[index].Trim()
                if inner.StartsWith("]", StringComparison.Ordinal) {
                    return values
                }

                value := inner
                if value.EndsWith(",", StringComparison.Ordinal) {
                    value = value.Substring(0, value.Length - 1)
                }

                if value.Length >= 2 {
                    value = value.Substring(1, value.Length - 2)
                }

                if values.Length > 0 {
                    values = values + ","
                }

                values = values + value
                index = index + 1
            }

            return values
        }

        index = index + 1
    }

    return values
}

func OfjkString1(json: string, key: string): string? {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(key).GetString()
}

func OfjkString2(json: string, first: string, second: string): string? {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(first).GetProperty(second).GetString()
}

func OfjkString3(json: string, first: string, second: string, third: string): string? {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(first).GetProperty(second).GetProperty(third).GetString()
}

func OfjkInt1(json: string, key: string): int {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(key).GetInt32()
}

func OfjkInt2(json: string, first: string, second: string): int {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(first).GetProperty(second).GetInt32()
}

func OfjkInt3(json: string, first: string, second: string, third: string): int {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(first).GetProperty(second).GetProperty(third).GetInt32()
}

func OfjkInt4(json: string, first: string, second: string, third: string, fourth: string): int {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(first).GetProperty(second).GetProperty(third).GetProperty(fourth).GetInt32()
}

func OfjkBool1(json: string, key: string): bool {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(key).GetBoolean()
}

func OfjkArrayLength1(json: string, key: string): int {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(key).GetArrayLength()
}

// ── The fixtures ────────────────────────────────────────────────────────────────────────────────

func OfjkPlainDiagnostic(code: string, severity: string, message: string, fileName: string, line: int, column: int, length: int): DiagnosticResult {
    return new DiagnosticResult(code, severity, message, fileName, line, column, length, null, null, null, null, null, null, null)
}

func OfjkTypedDiagnostic(code: string, severity: string, message: string, fileName: string, line: int, column: int, length: int, expectedType: string, actualType: string): DiagnosticResult {
    return new DiagnosticResult(code, severity, message, fileName, line, column, length, null, null, null, null, expectedType, actualType, null)
}

// One error and one warning: the summary fixture and the `diagnostics` / `diagnosticsClusters`
// envelope fixture are the same list.
func OfjkDiagnosticsFixture(): List<DiagnosticResult> {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfjkTypedDiagnostic("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3, "int", "string"))
    diagnostics.Add(OfjkPlainDiagnostic("NL901", "warning", "Unused variable", "Program.nl", 10, 4, 1))
    return diagnostics
}

func OfjkCheckDiagnosticsFixture(): List<DiagnosticResult> {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfjkTypedDiagnostic("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3, "int", "string"))
    return diagnostics
}

func OfjkMinimalSymbols(): List<SymbolResult> {
    symbols := new List<SymbolResult>()
    symbols.Add(new SymbolResult("Main", SymbolKind.Function, "Program.nl", 1, 0, "void", null, null, null))
    return symbols
}

func OfjkFullSymbols(): List<SymbolResult> {
    members := new SymbolResult[](1)
    members[0] = new SymbolResult("Run", SymbolKind.Function, "Program.nl", 2, 4, "void", null, null, null)

    parameters := new ParameterResult[](1)
    parameters[0] = new ParameterResult("args", "string[]", false, null)

    symbols := new List<SymbolResult>()
    symbols.Add(new SymbolResult("Main", SymbolKind.Function, "Program.nl", 1, 0, "void", ["pub"], members, parameters))
    return symbols
}

func OfjkOutlineFixture(): OutlineResult {
    children := new OutlineEntry[](1)
    children[0] = new OutlineEntry("Name", SymbolKind.Property, 13, 13, null, "string", null)

    entries := new OutlineEntry[](2)
    entries[0] = new OutlineEntry("Main", SymbolKind.Function, 3, 10, "void", null, null)
    entries[1] = new OutlineEntry("Person", SymbolKind.Class, 12, 20, null, null, children)

    return new OutlineResult("Program.nl", ["System", "System.Linq"], entries)
}

func OfjkReferencesFixture(): List<ReferenceResult> {
    results := new List<ReferenceResult>()
    results.Add(new ReferenceResult("Models.nl", 5, 0, 6, "class Person {", true))
    results.Add(new ReferenceResult("Program.nl", 3, 8, 6, "p := Person{}", false))
    return results
}

func OfjkDocFixture(): DocResult {
    members := new DocMemberResult[](1)
    members[0] = new DocMemberResult("WriteLine", "method", "void", "Writes a line", "(string value)")

    parameters := new DocParameterResult[](1)
    parameters[0] = new DocParameterResult("value", "string", "The text to write")

    return new DocResult(
        "Console",
        "System.Console",
        "class",
        "Represents the standard input, output, and error streams.",
        "System",
        members,
        parameters,
        null,
        null,
        ["Object"])
}

func OfjkCompletionsFixture(documentation: string?): CompletionResult {
    items := new List<CompletionItem>()
    items.Add(new CompletionItem("GetStats", "function", "TaskStats", "()", documentation, false))

    completions := new Dictionary<string, List<CompletionItem>>()
    completions["functions"] = items

    return new CompletionResult(CompletionContext.MemberAccess, "service", "TaskService", completions)
}

func OfjkInspectFixture(): InspectResult {
    references := new ReferenceResult[](2)
    references[0] = new ReferenceResult("Services/TaskService.nl", 93, 5, 8, "func GetStats(): TaskStats {", true)
    references[1] = new ReferenceResult("Program.nl", 85, 22, 8, "stats := service.GetStats()", false)

    return new InspectResult(
        new InspectSymbolResult("GetStats", "function", new LocationResult("Services/TaskService.nl", 93, 5)),
        new TypeResult("GetStats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1), null),
        new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8),
        new InspectReferencesResult(2, 1, references),
        OfjkCompletionsFixture(null))
}

// Five references across three files, two of them written with a backslash separator, and a
// three-group completion set — the fixture the compact summary is measured on.
func OfjkSummaryInspectFixture(): InspectResult {
    references := new ReferenceResult[](5)
    references[0] = new ReferenceResult("Services/TaskService.nl", 93, 5, 8, "func GetStats(): TaskStats {", true)
    references[1] = new ReferenceResult("Program.nl", 85, 22, 8, "stats := service.GetStats()", false)
    references[2] = new ReferenceResult("Program.nl", 87, 14, 8, "Log(service.GetStats())", false)
    references[3] = new ReferenceResult("Generated\\Stats.nl", 12, 9, 8, "value = service.GetStats()", false)
    references[4] = new ReferenceResult("Services/TaskService.nl", 101, 13, 8, "return GetStats()", false)

    functions := new List<CompletionItem>()
    functions.Add(new CompletionItem("GetStats", "function", "TaskStats", "()", null, false))
    functions.Add(new CompletionItem("CreateTask", "function", "TaskResult", "(string title)", null, false))

    properties := new List<CompletionItem>()
    properties.Add(new CompletionItem("Total", "property", "int", null, null, false))

    completions := new Dictionary<string, List<CompletionItem>>()
    completions["functions"] = functions
    completions["properties"] = properties

    return new InspectResult(
        new InspectSymbolResult("GetStats", "function", new LocationResult("Services/TaskService.nl", 93, 5)),
        new TypeResult("GetStats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1), null),
        new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8),
        new InspectReferencesResult(5, 1, references),
        new CompletionResult(CompletionContext.MemberAccess, "service", "TaskService", completions))
}

func OfjkEmptySystemsReport(): SystemsReport {
    return SystemsReport.Empty(ProjectFileParser.CreateDefault("JsonContract"))
}


// ---- THE DECODER STATES ITS OWN LIMITS -----------------------------------------------------------

test "a nested key never reads as a root key, and the root scan validates against the parser" {
    json := OutputFormatterJsonKernels.DiagnosticsToJson(OfjkDiagnosticsFixture(), "/project")

    // `errors` lives under `summary` and answers there.
    assert OfjkInt2(json, "summary", "errors") == 1

    // It is not a root key, and the parser agrees with the scanner in both directions.
    assert !OfjkHasRootKey(json, "errors")
    assert !OfjkRootKeysValidated(json).Contains("errors")
    assert OfjkHasRootKey(json, "summary")
}


// ---- THE SYMBOL ENVELOPE -------------------------------------------------------------------------

test "the symbols envelope is versioned, named and rooted" {
    json := OutputFormatterJsonKernels.SymbolsToJson(OfjkMinimalSymbols(), "/project")

    assert json.Contains("\"schemaVersion\": 1")
    assert json.Contains("\"command\": \"symbols\"")
    assert json.Contains("\"projectRoot\": \"/project\"")
    assert json.Contains("\"Main\"")
}

test "a symbol kind serialises as its lower-case name, not as its ordinal" {
    json := OutputFormatterJsonKernels.SymbolsToJson(OfjkMinimalSymbols(), null)

    assert json.Contains("\"function\"")
}

test "the symbols envelope root keys are exactly schemaVersion, command, ok, projectRoot, results" {
    json := OutputFormatterJsonKernels.SymbolsToJson(OfjkFullSymbols(), "/project")

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,projectRoot,results"
}


// ---- THE OUTLINE ENVELOPE ------------------------------------------------------------------------

test "the outline envelope carries the imports and the nested structure" {
    json := OutputFormatterJsonKernels.OutlineToJson(OfjkOutlineFixture())

    assert json.Contains("\"schemaVersion\": 1")
    assert json.Contains("\"System\"")
    assert json.Contains("\"System.Linq\"")
    assert json.Contains("\"Main\"")
    assert json.Contains("\"Person\"")
    assert json.Contains("\"Name\"")
}

test "the outline envelope root keys are exactly schemaVersion, command, ok, file, imports, outline" {
    json := OutputFormatterJsonKernels.OutlineToJson(OfjkOutlineFixture())

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,file,imports,outline"
}


// ---- THE DIAGNOSTIC ENVELOPES --------------------------------------------------------------------

test "the diagnostics envelope carries a severity summary counted from the results" {
    json := OutputFormatterJsonKernels.DiagnosticsToJson(OfjkDiagnosticsFixture(), "/project")

    assert OfjkString1(json, "command") == "diagnostics"
    assert OfjkInt2(json, "summary", "errors") == 1
    assert OfjkInt2(json, "summary", "warnings") == 1
    assert OfjkInt2(json, "summary", "info") == 0
}

test "the diagnostics envelope root keys are exactly schemaVersion, command, ok, projectRoot, results, summary" {
    json := OutputFormatterJsonKernels.DiagnosticsToJson(OfjkDiagnosticsFixture(), "/project")

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,projectRoot,results,summary"
}

test "cluster files sort case-insensitively, preserve their case and collapse case aliases" {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfjkPlainDiagnostic("NL301", "error", "Undefined variable 'customer'", "src/B.nl", 1, 5, 8))
    diagnostics.Add(OfjkPlainDiagnostic("NL301", "error", "Undefined variable 'customer'", "src/a.nl", 2, 5, 8))
    diagnostics.Add(OfjkPlainDiagnostic("NL301", "error", "Undefined variable 'customer'", "SRC/A.NL", 3, 5, 8))
    diagnostics.Add(OfjkPlainDiagnostic("NL301", "error", "Undefined variable 'customer'", "src/C.nl", 4, 5, 8))

    json := OutputFormatterJsonKernels.DiagnosticClustersToJson(diagnostics, "/project")

    assert OfjkArrayLength1(json, "clusters") == 1
    assert OfjkArrayStrings(json, "files") == "src/a.nl,src/B.nl,src/C.nl"
}

test "the diagnostics-clusters envelope root keys are exactly schemaVersion, command, ok, projectRoot, clusters, summary" {
    json := OutputFormatterJsonKernels.DiagnosticClustersToJson(OfjkDiagnosticsFixture(), "/project")

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,projectRoot,clusters,summary"
}

test "the check envelope is not ok when it carries an error, and it counts the files it checked" {
    json := OutputFormatterJsonKernels.CheckToJson(OfjkCheckDiagnosticsFixture(), "/project", 3)

    assert OfjkInt1(json, "schemaVersion") == 1
    assert OfjkString1(json, "command") == "check"
    assert OfjkString1(json, "projectRoot") == "/project"
    assert OfjkInt1(json, "checkedFiles") == 3
    assert !OfjkBool1(json, "ok")
    assert OfjkInt2(json, "summary", "errors") == 1
}

test "the check envelope root keys are exactly schemaVersion, command, projectRoot, checkedFiles, ok, results, summary" {
    json := OutputFormatterJsonKernels.CheckToJson(OfjkCheckDiagnosticsFixture(), "/project", 3)

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,projectRoot,checkedFiles,ok,results,summary"
}

test "the check-systems-report envelope root keys add diagnostics and systemsReport" {
    json := OutputFormatterJsonKernels.CheckSystemsReportToJson(
        new List<DiagnosticResult>(),
        "/project",
        1,
        OfjkEmptySystemsReport())

    assert OfjkRootKeysValidated(json)
        == "schemaVersion,command,projectRoot,checkedFiles,ok,diagnostics,summary,systemsReport"
}

test "the trusted envelope root keys are exactly schemaVersion, command, ok, projectRoot, results, summary" {
    json := OutputFormatterJsonKernels.TrustedToJson(OfjkEmptySystemsReport(), "/project")

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,projectRoot,results,summary"
}


// ---- THE NAVIGATION ENVELOPES --------------------------------------------------------------------

test "the type envelope carries the queried position and the resolved type" {
    json := OutputFormatterJsonKernels.TypeToJson(
        new TypeResult("p", "Person", "class", new LocationResult("Models.nl", 5, 0), null),
        "Program.nl",
        8,
        4)

    assert OfjkInt1(json, "schemaVersion") == 1
    assert OfjkString1(json, "command") == "type"
    assert OfjkString1(json, "file") == "Program.nl"
    assert OfjkInt2(json, "position", "line") == 8
    assert OfjkString2(json, "result", "resolvedType") == "Person"
}

test "the type envelope root keys are exactly schemaVersion, command, ok, file, position, result" {
    json := OutputFormatterJsonKernels.TypeToJson(
        new TypeResult("stats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1), null),
        "Program.nl",
        85,
        22)

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,file,position,result"
}

test "the definition envelope carries the name, kind and file of one result" {
    json := OutputFormatterJsonKernels.DefinitionToJson(new DefinitionResult("Person", "class", "Models.nl", 5, 0, 6))

    assert OfjkString1(json, "command") == "definition"
    assert OfjkString2(json, "result", "name") == "Person"
    assert OfjkString2(json, "result", "kind") == "class"
    assert OfjkString2(json, "result", "file") == "Models.nl"
}

test "the definition envelope root keys are exactly schemaVersion, command, ok, result" {
    json := OutputFormatterJsonKernels.DefinitionToJson(
        new DefinitionResult("GetStats", "function", "Services/TaskService.nl", 93, 5, 8))

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,result"
}

test "the references envelope carries the symbol, the count and every definition flag in order" {
    json := OutputFormatterJsonKernels.ReferencesToJson(
        "Person",
        "class",
        new LocationResult("Models.nl", 5, 0),
        OfjkReferencesFixture())

    assert OfjkString1(json, "command") == "references"
    assert OfjkInt1(json, "count") == 2
    assert OfjkString2(json, "symbol", "name") == "Person"
    assert OfjkKeyValues(json, "isDefinition") == "true,false"
}

test "the references envelope root keys are exactly schemaVersion, command, ok, symbol, count, results" {
    json := OutputFormatterJsonKernels.ReferencesToJson(
        "Person",
        "class",
        new LocationResult("Models.nl", 5, 0),
        OfjkReferencesFixture())

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,symbol,count,results"
}

test "the completions envelope root keys are exactly schemaVersion, command, ok, file, position, context, receiver, completions" {
    json := OutputFormatterJsonKernels.CompletionsToJson(
        OfjkCompletionsFixture("Returns the task statistics"),
        "Program.nl",
        85,
        22)

    assert OfjkRootKeysValidated(json)
        == "schemaVersion,command,ok,file,position,context,receiver,completions"
}

test "the doc envelope root keys are exactly schemaVersion, command, ok, query, result" {
    json := OutputFormatterJsonKernels.DocToJson(OfjkDocFixture(), "Console")

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,query,result"
}

test "the perf envelope root keys are exactly schemaVersion, command, ok, projectRoot, file, position, facts" {
    json := OutputFormatterJsonKernels.PerfToJson("Program.nl", 5, 12, "/project", new List<object>())

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,projectRoot,file,position,facts"
}


// ---- INSPECT, FULL AND COMPACT -------------------------------------------------------------------

test "the inspect envelope bundles the symbol, the reference counts and the completion receiver" {
    json := OutputFormatterJsonKernels.InspectToJson(OfjkInspectFixture(), "Program.nl", 85, 22)

    assert OfjkString1(json, "command") == "inspect"
    assert OfjkString3(json, "result", "symbol", "name") == "GetStats"
    assert OfjkInt3(json, "result", "references", "definitionCount") == 1
    assert OfjkString3(json, "result", "completions", "receiver") == "service"
}

test "the inspect envelope root keys are exactly schemaVersion, command, ok, file, position, result" {
    json := OutputFormatterJsonKernels.InspectToJson(OfjkInspectFixture(), "Program.nl", 85, 22)

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,file,position,result"
}

test "the compact inspect summary carries summary instead of result" {
    json := OutputFormatterJsonKernels.InspectSummaryToJson(OfjkSummaryInspectFixture(), "Program.nl", 85, 22)

    assert OfjkString1(json, "command") == "inspect"
    assert OfjkBool1(json, "ok")
    assert OfjkHasRootKey(json, "summary")
    assert !OfjkHasRootKey(json, "result")
}

test "the compact inspect summary counts references, normalises their files and names each group" {
    json := OutputFormatterJsonKernels.InspectSummaryToJson(OfjkSummaryInspectFixture(), "Program.nl", 85, 22)

    assert OfjkInt3(json, "summary", "references", "count") == 5

    // Five references over three distinct files: the backslash-separated one normalises to the
    // forward-slash spelling and the two same-file references collapse.
    assert OfjkArrayStrings(json, "files") == "Generated/Stats.nl,Program.nl,Services/TaskService.nl"

    assert OfjkInt3(json, "summary", "completions", "totalCount") == 3
    assert OfjkInt4(json, "summary", "completions", "groupCounts", "functions") == 2
    assert OfjkArrayStrings(json, "functions") == "GetStats,CreateTask"
}

test "the compact inspect envelope root keys are exactly schemaVersion, command, ok, file, position, summary" {
    json := OutputFormatterJsonKernels.InspectSummaryToJson(OfjkInspectFixture(), "Program.nl", 85, 22)

    assert OfjkRootKeysValidated(json) == "schemaVersion,command,ok,file,position,summary"
}


// ---- THE ERROR ENVELOPE --------------------------------------------------------------------------

test "the error envelope is not ok and carries a coded, detailed payload" {
    position := new Dictionary<string, object>()
    position["line"] = 83
    position["column"] = 1

    details := new Dictionary<string, object>()
    details["file"] = "Program.nl"
    details["position"] = position

    json := OutputFormatterJsonKernels.ErrorToJson(
        "type",
        "No symbol found at Program.nl:83:1",
        "/project",
        "noSymbol",
        details)

    assert OfjkString1(json, "command") == "type"
    assert !OfjkBool1(json, "ok")
    assert OfjkString1(json, "projectRoot") == "/project"
    assert OfjkString2(json, "error", "code") == "noSymbol"
    assert OfjkString3(json, "error", "details", "file") == "Program.nl"
}

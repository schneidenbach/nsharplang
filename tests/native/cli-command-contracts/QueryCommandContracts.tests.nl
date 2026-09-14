namespace NSharpLang.CliCommandContracts.Tests

import System
import System.IO
import System.Text.Json


// THE `nlc query` COMMAND SURFACE, PROVEN AS PROCESSES.
//
// These rows are the query-family half of `tests/CliCommandTests.cs`. Every deleted body reached
// the command through `QueryCommand.Execute(args)` in process and read the answer back out of a
// `Console.SetOut` capture.
//
// WHY A PROCESS AND NOT AN IN-PROCESS CALL. Not because the capture is unavailable: re-measured on
// 2026-09-14 against the tip CLI, a `.tests.nl` that saves `Console.Out`, swaps in a `StringWriter`
// and restores it in a `finally` checks clean and passes. The route is a process because a process
// proves strictly more than the deleted C# did. An in-process `QueryCommand.Execute` call never
// shows that `nlc query <sub>` REACHES `QueryCommand` at all, never shows the real exit code the
// shell sees, and never shows which STREAM a sentence actually landed on — and stream and exit code
// are most of what these rows are about.
//
// THE STDERR SILENCE CLAIMS ARE NOT VACUOUS. Every `Assert.True(IsNullOrWhiteSpace(stderr))` below
// is paired, in this same file, with a row on the SAME command family that DOES write to stderr —
// the `--text --compact` refusal, the batch text refusal, the missing-`--name` usage refusal and
// the six text-mode error routes — so the stream is demonstrably reachable and the silence is a
// measured fact rather than a structurally unfailable assertion.

// ─── THE JSON ROOT-KEY CONTRACT ───────────────────────────────────────────────────────────────
//
// The deleted `AssertJsonContract(name, json)` loaded `tests/fixtures/json-contract-root-keys.golden.json`
// and required the command's root property names to equal the recorded list AS A SEQUENCE — same
// names, same order. Both sides are reduced to one comma-joined string here so the equality is a
// single `assert` whose failure prints both lists, which is what the C# had to hand-assemble into
// a message. The walks use `EnumerateObject`/`EnumerateArray`, matching the file beside this one.
func QcGoldenContractPath(): string {
    return Path.Combine(Path.Combine(Path.Combine(CliRepositoryRoot(), "tests"), "fixtures"), "json-contract-root-keys.golden.json")
}

func QcJoinStringArray(items: JsonElement): string {
    text := ""
    enumerator := items.EnumerateArray()
    while enumerator.MoveNext() {
        if text != "" {
            text = text + ","
        }

        text = text + TextOf(enumerator.Current)
    }

    return text
}

// The recorded root-key sequence for one contract name, comma-joined.
func QcContractKeys(contractName: string): string {
    document := JsonDocument.Parse(File.ReadAllText(QcGoldenContractPath()))
    found := false
    text := ""
    enumerator := document.RootElement.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        if property.Name == contractName {
            found = true
            text = QcJoinStringArray(property.Value)
        }
    }

    document.Dispose()
    if !found {
        throw new InvalidOperationException("Missing JSON contract snapshot: " + contractName)
    }

    return text
}

// The root property names of an answer, in document order, comma-joined.
func QcRootKeys(json: string): string {
    document := JsonDocument.Parse(json)
    text := ""
    enumerator := document.RootElement.EnumerateObject()
    while enumerator.MoveNext() {
        if text != "" {
            text = text + ","
        }

        text = text + enumerator.Current.Name
    }

    document.Dispose()
    return text
}

func QcHasProperty(element: JsonElement, name: string): bool {
    enumerator := element.EnumerateObject()
    while enumerator.MoveNext() {
        if enumerator.Current.Name == name {
            return true
        }
    }

    return false
}

// ─── SMALL READERS THE DELETED LINQ USED ──────────────────────────────────────────────────────
//
// `Assert.Single(items, predicate)`, `Assert.All(items, ...)` and `Assert.Contains(items, ...)`
// have no direct N# spelling; these are the equivalents, and each one FAILS LOUDLY rather than
// degrading to "at least one" the way a naive `Contains` rewrite would.

func QcSingleByString(items: JsonElement, propertyName: string, wanted: string): JsonElement {
    matches := 0
    chosen := items
    enumerator := items.EnumerateArray()
    while enumerator.MoveNext() {
        item := enumerator.Current
        if TextOf(item.GetProperty(propertyName)) == wanted {
            matches = matches + 1
            chosen = item
        }
    }

    if matches != 1 {
        throw new InvalidOperationException("Expected exactly one element whose " + propertyName + " is '" + wanted + "', found " + matches.ToString() + ".")
    }

    return chosen
}

func QcCountByString(items: JsonElement, propertyName: string, wanted: string): int {
    matches := 0
    enumerator := items.EnumerateArray()
    while enumerator.MoveNext() {
        if TextOf(enumerator.Current.GetProperty(propertyName)) == wanted {
            matches = matches + 1
        }
    }

    return matches
}

func QcAllHaveString(items: JsonElement, propertyName: string, wanted: string): bool {
    enumerator := items.EnumerateArray()
    while enumerator.MoveNext() {
        if TextOf(enumerator.Current.GetProperty(propertyName)) != wanted {
            return false
        }
    }

    return true
}

// ─── THE PROJECTS THE QUERY ROWS READ ─────────────────────────────────────────────────────────

func QcHelloWorld(): string {
    return CheckExampleProject("01-hello-world")
}

func QcClassesAndRecords(): string {
    return CheckExampleProject("06-classes-and-records")
}

func QcMultiFileProject(): string {
    return Path.Combine(CheckExampleProject("12-multi-file-projects"), "MultiFileProject")
}

func QcQuoted(path: string): string {
    return "\"" + path + "\""
}

// ═══ THE STABLE JSON ENVELOPE, ONE ROW PER CONTRACT ═══════════════════════════════════════════
//
// The deleted `[Theory] QueryCommand_EmitsStableJsonEnvelope(contractName, args)` carried FOURTEEN
// `[MemberData]` rows and made the same three claims about each: exit 0, a silent stderr, and root
// keys equal to the golden sequence. A theory failure named only the data row's index, so each of
// the fourteen is unrolled into its own `test` here and a failure names the CONTRACT.

test "nlc query symbols emits the recorded symbols envelope root keys, in order" {
    run := Nlc("query symbols --project " + QcQuoted(QcHelloWorld()))

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("symbols")
}

test "nlc query outline emits the recorded outline envelope root keys, in order" {
    run := Nlc("query outline --project " + QcQuoted(QcHelloWorld()) + " Program.nl")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("outline")
}

test "nlc query diagnostics emits the recorded diagnostics envelope root keys, in order" {
    run := Nlc("query diagnostics --project " + QcQuoted(QcHelloWorld()))

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("diagnostics")
}

test "nlc query doc emits the recorded doc envelope root keys, in order" {
    run := Nlc("query doc Console.WriteLine")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("doc")
}

test "nlc query type emits the recorded type envelope root keys, in order" {
    run := Nlc("query type --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 11:5")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("type")
}

test "nlc query definition --name emits the recorded definitionSearch envelope root keys, in order" {
    run := Nlc("query definition --project " + QcQuoted(QcClassesAndRecords()) + " --name Point")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("definitionSearch")
}

test "nlc query definition --pos emits the recorded definition envelope root keys, in order" {
    run := Nlc("query definition --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 22:10")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("definition")
}

test "nlc query references emits the recorded references envelope root keys, in order" {
    run := Nlc("query references --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 10:7")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("references")
}

test "nlc query completions emits the recorded completions envelope root keys, in order" {
    run := Nlc("query completions --project " + QcQuoted(QcMultiFileProject()) + " --file Services/PersonService.nl --pos 14:15")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("completions")
}

test "nlc query inspect emits the recorded inspect envelope root keys, in order" {
    run := Nlc("query inspect --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 11:5")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("inspect")
}

test "nlc query inspect --compact emits the recorded inspectSummary envelope root keys, in order" {
    run := Nlc("query inspect --compact --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 11:5")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("inspectSummary")
}

test "nlc query hover emits the recorded hover envelope root keys, in order" {
    run := Nlc("query hover --project " + QcQuoted(QcHelloWorld()) + " --file Program.nl --pos 18:10")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("hover")
}

test "nlc query call-graph emits the recorded callGraph envelope root keys, in order" {
    run := Nlc("query call-graph --project " + QcQuoted(QcHelloWorld()) + " --function Main")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("callGraph")
}

test "nlc query implementors emits the recorded implementors envelope root keys, in order" {
    run := Nlc("query implementors --project " + QcQuoted(QcClassesAndRecords()) + " --name IShape")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert QcRootKeys(run.Stdout) == QcContractKeys("implementors")
}

// ═══ THE DIAGNOSTIC FAMILY ════════════════════════════════════════════════════════════════════

func QcWriteProject(directory: string, name: string, source: string) {
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: " + name + "\n" + "outputType: exe\n" + "targetFramework: net10.0\n"
    )
    File.WriteAllText(Path.Combine(directory, "Program.nl"), source)
}

test "nlc query diagnostics --clusters groups the unresolved identifiers into one recipe-bearing cluster" {
    directory := NewTempDirectory("nsharp-diagnostic-clusters")
    try {
        QcWriteProject(
            directory,
            "DiagnosticClusters",
            "func Main() {\n" + "    Console.WriteLine(undefinedVar1)\n" + "    Console.WriteLine(undefinedVar2)\n" + "}\n"
        )

        run := Nlc("query diagnostics --clusters --project " + QcQuoted(directory))
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert TextOf(root.GetProperty("command")) == "diagnostics.clusters"
        assert QcRootKeys(run.Stdout) == QcContractKeys("diagnosticsClusters")
        assert !root.GetProperty("ok").GetBoolean()

        cluster := QcSingleByString(root.GetProperty("clusters"), "category", "identifier-resolution")
        assert TextOf(cluster.GetProperty("recipe")) == "symbols:missing-import-or-qualification"
        assert TextOf(cluster.GetProperty("risk")) == "medium"
        assert cluster.GetProperty("files").GetArrayLength() == 1
        assert TextOf(ElementAt(cluster.GetProperty("files"), 0)) == "Program.nl"
        assert cluster.GetProperty("relatedDiagnostics").GetArrayLength() >= 2
        assert TextOf(cluster.GetProperty("nextCommand")).StartsWith("nlc query inspect --file Program.nl --pos ")
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc query ast names every node type and keeps the concrete statement through the Statement base" {
    directory := NewTempDirectory("nsharp-query-ast")
    try {
        QcWriteProject(directory, "AstQuery", "func add(x: int, y: int): int {\n" + "    return x + y\n" + "}\n")

        run := Nlc("query ast --file Program.nl --project " + QcQuoted(directory))
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert TextOf(root.GetProperty("command")) == "query.ast"
        assert root.GetProperty("ok").GetBoolean()

        assert root.GetProperty("files").GetArrayLength() == 1
        astFile := ElementAt(root.GetProperty("files"), 0)
        assert TextOf(astFile.GetProperty("file")).EndsWith("Program.nl")

        ast := astFile.GetProperty("ast")
        assert TextOf(ast.GetProperty("node")) == "CompilationUnit"

        assert ast.GetProperty("declarations").GetArrayLength() == 1
        declaration := ElementAt(ast.GetProperty("declarations"), 0)
        assert TextOf(declaration.GetProperty("node")) == "FunctionDeclaration"
        assert TextOf(declaration.GetProperty("name")) == "add"
        assert declaration.GetProperty("parameters").GetArrayLength() == 2
        assert TextOf(ElementAt(declaration.GetProperty("parameters"), 0).GetProperty("name")) == "x"

        // The concrete node type survives the polymorphic `Statement` base, with positions.
        body := declaration.GetProperty("body")
        assert body.GetProperty("line").GetInt32() >= 1
        assert body.GetProperty("statements").GetArrayLength() == 1
        assert TextOf(ElementAt(body.GetProperty("statements"), 0).GetProperty("node")) == "ReturnStatement"
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc query diagnostics answers malformed source with a parseable failing envelope, not a crash" {
    directory := NewTempDirectory("nsharp-malformed-diagnostics")
    try {
        QcWriteProject(
            directory,
            "MalformedDiagnostics",
            "class User {\n" + "    Name: string\n" + "}\n" + "\n" + "func main() {\n" + "    first := 1 +\n" + "    Console.WriteLine(undefinedFromCli)\n" + "}\n"
        )

        run := Nlc("query diagnostics --project " + QcQuoted(directory) + " --file Program.nl --no-daemon")
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert TextOf(root.GetProperty("command")) == "diagnostics"
        assert !root.GetProperty("ok").GetBoolean()
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc query diagnostics fails source that only breaks a strict LINT rule, not the type checker" {
    directory := NewTempDirectory("nsharp-lint-diagnostics")
    try {
        QcWriteProject(directory, "LintDiagnostics", "func main() {\n" + "    unused := 42\n" + "}\n")

        run := Nlc("query diagnostics --project " + QcQuoted(directory) + " --file Program.nl --no-daemon")
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        assert !document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "the --severity filter is case-insensitive, so WARNING keeps only the editorconfig warning" {
    directory := NewTempDirectory("nsharp-diagnostic-severity-filter")
    try {
        QcWriteProject(
            directory,
            "SeverityFilterDiagnostics",
            "func main() {\n" + "    unused := 42\n" + "    undefinedFromCli()\n" + "}\n"
        )
        File.WriteAllText(
            Path.Combine(directory, ".editorconfig"),
            "root = true\n" + "\n" + "[*.nl]\n" + "dotnet_diagnostic.NL001.severity = warning\n"
        )

        run := Nlc("query diagnostics --project " + QcQuoted(directory) + " --file Program.nl --severity WARNING --no-daemon")
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("results").GetArrayLength() == 1
        only := ElementAt(root.GetProperty("results"), 0)
        assert TextOf(only.GetProperty("code")) == "NL001"
        assert TextOf(only.GetProperty("severity")) == "warning"
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

// ═══ POSITION SNAPPING, MISSING SYMBOLS AND THE COMPACT ENVELOPE ══════════════════════════════

test "nlc query definition snaps from a call's CLOSING paren back to the function it calls" {
    run := Nlc("query definition --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 64:10")

    assert run.ExitCode == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("result").GetProperty("name")) == "GetAll"
    assert TextOf(root.GetProperty("result").GetProperty("file")) == "Service.nl"
    document.Dispose()
}

test "nlc query type on a comment line answers noSymbol with the file and position in the details" {
    // Line 1 of the fixture's Program.nl is a comment, so there is no symbol there.
    run := Nlc("query type --project " + QcQuoted(IssueTrackerFixture()) + " --file Program.nl --pos 1:1")

    assert run.ExitCode == 1

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert !root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("command")) == "type"
    assert TextOf(root.GetProperty("error").GetProperty("code")) == "noSymbol"
    details := root.GetProperty("error").GetProperty("details")
    assert TextOf(details.GetProperty("file")) == "Program.nl"
    assert details.GetProperty("position").GetProperty("line").GetInt32() == 1
    document.Dispose()
}

test "nlc query inspect --summary carries a summary and NO result, which is what makes it compact" {
    run := Nlc("query inspect --summary --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 11:5")

    assert QcRootKeys(run.Stdout) == QcContractKeys("inspectSummary")

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert QcHasProperty(root, "summary")
    assert !QcHasProperty(root, "result")
    document.Dispose()
}

test "a type used as a GENERIC ARGUMENT binds semantically, so the near Widget wins over the far one" {
    directory := NewTempDirectory("nsharp-query-type-use")
    try {
        Directory.CreateDirectory(Path.Combine(directory, "Foo"))
        Directory.CreateDirectory(Path.Combine(directory, "Bar"))
        File.WriteAllText(
            Path.Combine(directory, "project.yml"),
            "name: QueryTypeUse\n" + "version: 1.0.0\n" + "entry: Program.nl\n" + "outputType: exe\n" + "targetFramework: net10.0\n"
        )
        File.WriteAllText(
            Path.Combine(Path.Combine(directory, "Foo"), "Widget.nl"),
            "namespace QueryTypeUse.Foo\n" + "\n" + "record Widget {\n" + "    Value: string\n" + "}\n"
        )
        File.WriteAllText(
            Path.Combine(Path.Combine(directory, "Bar"), "Widget.nl"),
            "namespace QueryTypeUse.Bar\n" + "\n" + "record Widget {\n" + "    Value: int\n" + "}\n"
        )
        useSource := "namespace QueryTypeUse.Foo\n" + "import System.Collections.Generic\n" + "\n" + "func Read(items: List<Widget>): string {\n" + "    return \"\"\n" + "}\n"
        File.WriteAllText(Path.Combine(Path.Combine(directory, "Foo"), "UseWidget.nl"), useSource)
        File.WriteAllText(
            Path.Combine(directory, "Program.nl"),
            "namespace QueryTypeUse\n" + "\n" + "func Main() {\n" + "}\n"
        )

        // The column is derived from the source the way the deleted C# derived it, so the row
        // cannot silently drift onto a neighbouring token if the fixture text changes.
        useLine := useSource.Split('\n')[3]
        typeUseColumn := useLine.IndexOf("Widget", StringComparison.Ordinal) + 1

        run := Nlc("query inspect --project " + QcQuoted(directory) + " --file Foo/UseWidget.nl --pos 4:" + typeUseColumn.ToString())
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("ok").GetBoolean()
        symbol := root.GetProperty("result").GetProperty("symbol")
        assert TextOf(symbol.GetProperty("name")) == "Widget"
        assert TextOf(symbol.GetProperty("kind")) == "record"
        assert TextOf(symbol.GetProperty("definition").GetProperty("file")) == "Foo/Widget.nl"
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

// ═══ THE BATCH ROUTE ══════════════════════════════════════════════════════════════════════════

test "a batch symbols request parses its kind through the SAME query kernel the flag route uses" {
    directory := NewTempDirectory("nsharp-batch-symbol-kind")
    try {
        requestsPath := WriteRequests(directory, "[\n" + "  {\n" + "    \"command\": \"symbols\",\n" + "    \"kind\": \"class\"\n" + "  }\n" + "]\n")

        run := NlcBatch(requestsPath)
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        response := ElementAt(document.RootElement.GetProperty("results"), 0).GetProperty("response")
        symbols := response.GetProperty("results")
        assert symbols.GetArrayLength() > 0
        assert QcAllHaveString(symbols, "kind", "class")
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc query batch refuses --text on STDERR, leaves stdout empty and exits 1" {
    directory := NewTempDirectory("nsharp-batch")
    try {
        requestsPath := WriteRequests(directory, "[]")

        run := Nlc("query batch --text --requests " + QcQuoted(requestsPath))
        assert run.ExitCode == 1
        assert run.Stdout.Trim().Length == 0
        assert run.Stderr.Contains("Batch queries only support JSON output.")
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc query inspect refuses --compact beside --text on STDERR, leaves stdout empty and exits 1" {
    run := Nlc("query inspect --file Program.nl --pos 1:1 --text --compact --no-daemon")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("--compact/--summary is only supported with JSON output.")
}

// ═══ HOVER, CALL GRAPH, IMPLEMENTORS AND SYMBOLS ══════════════════════════════════════════════

// The deleted body FOUND the `func Hi(` line rather than hard-coding it, so the row could not
// drift when the example gained a comment. That search is kept.
func QcHelloWorldLineStartingWith(prefix: string): int {
    lines := File.ReadAllLines(Path.Combine(QcHelloWorld(), "Program.nl"))
    index := 0
    while index < lines.Length {
        if lines[index].TrimStart().StartsWith(prefix, StringComparison.Ordinal) {
            return index + 1
        }

        index = index + 1
    }

    throw new InvalidOperationException("No line in the hello-world example starts with '" + prefix + "'.")
}

test "nlc query hover at a function definition returns its signature in the recorded envelope" {
    hiLine := QcHelloWorldLineStartingWith("func Hi(")

    run := Nlc("query hover --project " + QcQuoted(QcHelloWorld()) + " --file Program.nl --pos " + hiLine.ToString() + ":6")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("command")) == "hover"
    assert QcRootKeys(run.Stdout) == QcContractKeys("hover")
    document.Dispose()
}

test "nlc query hover on a blank line answers the structured noSymbol error and exits 1" {
    run := Nlc("query hover --project " + QcQuoted(QcHelloWorld()) + " --file Program.nl --pos 6:1")

    assert run.ExitCode == 1

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert !root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("command")) == "hover"
    assert TextOf(root.GetProperty("error").GetProperty("code")) == "noSymbol"
    document.Dispose()
}

test "nlc query call-graph --function Main finds the callees of Main" {
    run := Nlc("query call-graph --project " + QcQuoted(QcHelloWorld()) + " --function Main")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("command")) == "callGraph"
    assert QcRootKeys(run.Stdout) == QcContractKeys("callGraph")
    document.Dispose()
}

test "nlc query call-graph without --function returns every edge and names no single function" {
    run := Nlc("query call-graph --project " + QcQuoted(QcHelloWorld()))

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("command")) == "callGraph"

    // The deleted body allowed the key to be absent OR null. Both are still accepted; what is
    // pinned is that it never carries a function NAME when none was asked for.
    if QcHasProperty(root, "function") {
        assert root.GetProperty("function").ValueKind == JsonValueKind.Null
    }

    assert root.GetProperty("callees").GetArrayLength() > 0
    document.Dispose()
}

test "nlc query implementors --name IShape finds Circle in the recorded envelope" {
    run := Nlc("query implementors --project " + QcQuoted(QcClassesAndRecords()) + " --name IShape")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("command")) == "implementors"
    assert QcRootKeys(run.Stdout) == QcContractKeys("implementors")
    document.Dispose()
}

test "nlc query implementors with neither --name nor --pos puts its usage on STDERR and exits 1" {
    run := Nlc("query implementors --project " + QcQuoted(QcHelloWorld()))

    assert run.ExitCode == 1
    assert run.Stderr.Contains("Usage:")
}

test "the symbols --filter glob matches Circle by its tail and leaves Square out" {
    run := Nlc("query symbols --project " + QcQuoted(QcClassesAndRecords()) + " --filter \"*ircle\"")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()

    results := root.GetProperty("results")
    assert QcCountByString(results, "name", "Circle") == 1
    assert QcCountByString(results, "name", "Square") == 0
    document.Dispose()
}

test "the symbols --kind flag parses through the query kernel, so every answer is a class" {
    run := Nlc("query symbols --project " + QcQuoted(IssueTrackerFixture()) + " --kind class --no-daemon")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    results := document.RootElement.GetProperty("results")
    assert results.GetArrayLength() > 0
    assert QcAllHaveString(results, "kind", "class")
    document.Dispose()
}

test "a --filter with no glob character matches by SUBSTRING, so quare finds Square only" {
    run := Nlc("query symbols --project " + QcQuoted(QcClassesAndRecords()) + " --filter quare")

    assert run.ExitCode == 0

    document := JsonDocument.Parse(run.Stdout)
    results := document.RootElement.GetProperty("results")
    assert QcCountByString(results, "name", "Square") == 1
    assert QcCountByString(results, "name", "Circle") == 0
    document.Dispose()
}

// ═══ THE TEXT OUTPUT MODE ═════════════════════════════════════════════════════════════════════
//
// `--text` must produce prose on the RIGHT stream and never leak the JSON envelope. The deleted
// file made that claim in two large bodies; both are kept whole, because each one's value is that
// it sweeps a whole family of subcommands in one place rather than proving any single sentence.

test "symbols, hover and call-graph honour --text and never leak the JSON envelope" {
    hiLine := QcHelloWorldLineStartingWith("func Hi(")

    symbols := Nlc("query symbols --project " + QcQuoted(QcClassesAndRecords()) + " --filter \"*ircle\" --text")
    assert symbols.ExitCode == 0
    assert symbols.Stderr.Trim().Length == 0
    assert symbols.Stdout.Contains("Class Circle")
    assert !symbols.Stdout.Contains("\"command\"")

    hover := Nlc("query hover --project " + QcQuoted(QcHelloWorld()) + " --file Program.nl --pos " + hiLine.ToString() + ":6 --text")
    assert hover.ExitCode == 0
    assert hover.Stderr.Trim().Length == 0
    assert hover.Stdout.Contains("Signature:")
    assert !hover.Stdout.Contains("\"command\"")

    callGraph := Nlc("query call-graph --project " + QcQuoted(QcHelloWorld()) + " --function Main --text")
    assert callGraph.ExitCode == 0
    assert callGraph.Stderr.Trim().Length == 0
    assert callGraph.Stdout.Contains("Call graph for: Main")
    assert !callGraph.Stdout.Contains("\"command\"")
}

test "the remaining query subcommands honour --text, and their failures speak prose on STDERR" {
    // Successes: prose on STDOUT, nothing on STDERR, and no JSON envelope anywhere.
    implementors := Nlc("query implementors --project " + QcQuoted(QcClassesAndRecords()) + " --name IShape --text")
    assert implementors.ExitCode == 0
    assert implementors.Stderr.Trim().Length == 0
    assert implementors.Stdout.Contains("Implementors of IShape")
    assert implementors.Stdout.Contains("Circle")
    assert !implementors.Stdout.Contains("\"command\"")

    outline := Nlc("query outline --project " + QcQuoted(QcHelloWorld()) + " Program.nl --text")
    assert outline.ExitCode == 0
    assert outline.Stderr.Trim().Length == 0
    assert outline.Stdout.Contains("File: Program.nl")
    assert outline.Stdout.Contains("Function Main")
    assert !outline.Stdout.Contains("\"command\"")

    typeText := Nlc("query type --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 11:5 --text")
    assert typeText.ExitCode == 0
    assert typeText.Stderr.Trim().Length == 0
    assert typeText.Stdout.Contains("At Service.nl:11:5:")
    assert typeText.Stdout.Contains("IssueStore")
    assert !typeText.Stdout.Contains("\"command\"")

    definitionSearch := Nlc("query definition --project " + QcQuoted(QcClassesAndRecords()) + " --name Point --text")
    assert definitionSearch.ExitCode == 0
    assert definitionSearch.Stderr.Trim().Length == 0
    assert definitionSearch.Stdout.Contains("Definitions of 'Point':")
    assert definitionSearch.Stdout.Contains("record Point")
    assert !definitionSearch.Stdout.Contains("\"command\"")

    definition := Nlc("query definition --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 22:10 --text")
    assert definition.ExitCode == 0
    assert definition.Stderr.Trim().Length == 0
    assert definition.Stdout.Contains("CreateIssue")
    assert definition.Stdout.Contains("Service.nl")
    assert !definition.Stdout.Contains("\"command\"")

    references := Nlc("query references --project " + QcQuoted(IssueTrackerFixture()) + " --file Service.nl --pos 10:7 --text")
    assert references.ExitCode == 0
    assert references.Stderr.Trim().Length == 0
    assert references.Stdout.Contains("References to 'IssueService'")
    assert references.Stdout.Contains("Service.nl")
    assert !references.Stdout.Contains("\"command\"")

    completions := Nlc("query completions --project " + QcQuoted(QcMultiFileProject()) + " --file Services/PersonService.nl --pos 14:15 --text")
    assert completions.ExitCode == 0
    assert completions.Stderr.Trim().Length == 0
    assert completions.Stdout.Contains("Completions at Services/PersonService.nl:14:15")
    assert completions.Stdout.Contains("methods")
    assert !completions.Stdout.Contains("\"command\"")

    // Failures: prose on STDERR, an empty STDOUT, exit 1, and still no JSON envelope.
    implementorsError := Nlc("query implementors --project " + QcQuoted(QcClassesAndRecords()) + " --file RecordsAndInterfaces.nl --pos 4:8 --text")
    assert implementorsError.ExitCode == 1
    assert implementorsError.Stdout.Trim().Length == 0
    assert implementorsError.Stderr.Contains("No interface found at RecordsAndInterfaces.nl:4:8")
    assert !implementorsError.Stderr.Contains("\"command\"")

    typeError := Nlc("query type --project " + QcQuoted(IssueTrackerFixture()) + " --file Program.nl --pos 1:1 --text")
    assert typeError.ExitCode == 1
    assert typeError.Stdout.Trim().Length == 0
    assert typeError.Stderr.Contains("No type information found at Program.nl:1:1")
    assert !typeError.Stderr.Contains("\"command\"")

    definitionError := Nlc("query definition --project " + QcQuoted(QcHelloWorld()) + " --file Program.nl --pos 1:1 --text")
    assert definitionError.ExitCode == 1
    assert definitionError.Stdout.Trim().Length == 0
    assert definitionError.Stderr.Contains("No definition found at Program.nl:1:1")
    assert !definitionError.Stderr.Contains("\"command\"")

    referencesError := Nlc("query references --project " + QcQuoted(QcHelloWorld()) + " --file Program.nl --pos 1:1 --text")
    assert referencesError.ExitCode == 1
    assert referencesError.Stdout.Trim().Length == 0
    assert referencesError.Stderr.Contains("No symbol found at Program.nl:1:1")
    assert !referencesError.Stderr.Contains("\"command\"")
}

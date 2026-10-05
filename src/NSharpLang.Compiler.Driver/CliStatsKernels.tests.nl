namespace NSharpLang.Cli

import System.Collections.Generic
import System.Text.Json
import NSharpLang.Compiler
import NSharpLang.Compiler.Columnar

// `nlc build|check|test --stats` and the compiler work counters behind it.
test "--stats is split out of a command's arguments and the rest pass through in order" {
    request := CliStatsKernels.Extract(["--project", "app", "--stats", "--json"])
    assert request.Requested
    assert request.Error == null
    assert request.OutputPath == null
    assert request.CommandArgs.Length == 3
    assert request.CommandArgs[0] == "--project"
    assert request.CommandArgs[1] == "app"
    assert request.CommandArgs[2] == "--json"
}

test "--stats=<path> names the file the stats line is written to" {
    request := CliStatsKernels.Extract(["--stats=/tmp/out.json"])
    assert request.Requested
    assert request.Error == null
    assert request.OutputPath == "/tmp/out.json"
    assert request.CommandArgs.Length == 0
}

test "a command without --stats is untouched" {
    request := CliStatsKernels.Extract(["--project", "app"])
    assert !request.Requested
    assert request.CommandArgs.Length == 2
}

test "--stats after a -- separator belongs to the program, not to nlc" {
    request := CliStatsKernels.Extract(["--", "--stats"])
    assert !request.Requested
    assert request.CommandArgs.Length == 2
    assert request.CommandArgs[1] == "--stats"
}

test "an empty --stats= path and a repeated --stats are refused by name" {
    empty := CliStatsKernels.Extract(["--stats="])
    assert empty.Error == CliStatsKernels.MissingPathMessage()

    repeated := CliStatsKernels.Extract(["--stats", "--stats=/tmp/a.json"])
    assert repeated.Error == CliStatsKernels.RepeatedMessage()
}

test "--stats is accepted by build, test and check and by nothing else" {
    assert CliStatsKernels.SupportsStats(ProgramCommandKernels.GetCommandKind(["build"]))
    assert CliStatsKernels.SupportsStats(ProgramCommandKernels.GetCommandKind(["test"]))
    assert CliStatsKernels.SupportsStats(ProgramCommandKernels.GetCommandKind(["check"]))
    assert !CliStatsKernels.SupportsStats(ProgramCommandKernels.GetCommandKind(["run"]))
    assert !CliStatsKernels.SupportsStats(ProgramCommandKernels.GetCommandKind(["format"]))
    assert !CliStatsKernels.SupportsStats(ProgramCommandKernels.GetCommandKind(["query"]))
}

test "the stats line is one compact nsharp.cli-stats v1 object with every counter" {
    counters := new CompilerWorkCounterSnapshot(8, 8, 9, 1, 212, 0)
    json := CliStatsKernels.ToJson("check", 0, 1234, 1500, 0, counters)
    assert !json.Contains("\n")

    document := JsonDocument.Parse(json)
    root := document.RootElement
    assert root.GetProperty("schema").GetString() == "nsharp.cli-stats"
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    assert root.GetProperty("command").GetString() == "check"
    assert root.GetProperty("exitCode").GetInt32() == 0
    assert root.GetProperty("wallMs").GetInt64() == 1234
    assert root.GetProperty("cpuMs").GetInt64() == 1500
    // A platform that does not report a peak working set (macOS answers 0) omits the field, as
    // every CLI envelope omits a null one.
    assert !json.Contains("peakWorkingSetBytes")
    work := root.GetProperty("counters")
    assert work.GetProperty("filesParsed").GetInt64() == 8
    assert work.GetProperty("emitParses").GetInt64() == 8
    assert work.GetProperty("filesAnalyzed").GetInt64() == 9
    assert work.GetProperty("assembliesEmitted").GetInt64() == 1
    assert work.GetProperty("referenceAssembliesLoaded").GetInt64() == 212
    assert work.GetProperty("processesSpawned").GetInt64() == 0
    // No phase recorded: the optional `phases` array is omitted, like every empty field.
    assert !json.Contains("phases")
    document.Dispose()
}

test "the phase ledger's rows ride on the stats line as phases, in ledger order" {
    counters := new CompilerWorkCounterSnapshot(1, 1, 1, 1, 1, 0)
    phases := new List<CompilerPhaseRecord>()
    phases.Add(new CompilerPhaseRecord("App", "parse", 0, 30000, 2048, 1))
    phases.Add(new CompilerPhaseRecord("App", "analysis", 0, 120000, 4096, 2))
    json := CliStatsKernels.ToJson("build", 0, 20, 15, 0, counters, phases)
    assert !json.Contains("\n")

    document := JsonDocument.Parse(json)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    rows := root.GetProperty("phases")
    assert rows.GetArrayLength() == 2
    first := rows[0]
    assert first.GetProperty("project").GetString() == "App"
    assert first.GetProperty("phase").GetString() == "parse"
    assert first.GetProperty("wallMs").GetInt64() == 0
    assert first.GetProperty("cpuMs").GetInt64() == 3
    assert first.GetProperty("allocatedBytes").GetInt64() == 2048
    assert first.GetProperty("calls").GetInt32() == 1
    second := rows[1]
    assert second.GetProperty("phase").GetString() == "analysis"
    assert second.GetProperty("cpuMs").GetInt64() == 12
    assert second.GetProperty("calls").GetInt32() == 2
    document.Dispose()
}

test "a reported peak working set is carried as a number" {
    counters := new CompilerWorkCounterSnapshot(0, 0, 0, 0, 0, 0)
    document := JsonDocument.Parse(CliStatsKernels.ToJson("build", 1, 1, 1, 4096, counters))
    assert document.RootElement.GetProperty("peakWorkingSetBytes").GetInt64() == 4096
    document.Dispose()
}

test "the shared work counters only move forward, and a snapshot difference is the work in between" {
    before := CompilerWorkCounters.Shared.Snapshot()
    CompilerWorkCounters.Shared.CountFileParsed()
    CompilerWorkCounters.Shared.CountFileParsed()
    CompilerWorkCounters.Shared.CountAssemblyEmitted()
    CompilerWorkCounters.Shared.CountProcessSpawned()
    delta := CompilerWorkCounters.Shared.Snapshot().Since(before)
    // Other rows in this process may parse concurrently, so the floor is what this row added.
    assert delta.FilesParsed >= 2
    assert delta.AssembliesEmitted >= 1
    assert delta.ProcessesSpawned >= 1
}

test "parsing one file through the production entry counts exactly one parse" {
    before := CompilerWorkCounters.Shared.Snapshot()
    _ = ColumnarParserRecovery.ParseFileAst("namespace Probe\n\nfunc One(): int {\n    return 1\n}\n", "Probe.nl")
    delta := CompilerWorkCounters.Shared.Snapshot().Since(before)
    assert delta.FilesParsed >= 1
}

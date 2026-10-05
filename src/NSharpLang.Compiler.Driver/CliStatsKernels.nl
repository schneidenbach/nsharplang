namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Text.Json
import NSharpLang.Compiler

// `nlc check|build|test --stats`: WHAT ONE COMMAND COST, AS ONE VERSIONED JSON LINE.
//
// An agent editing N# runs check, build and test in a tight loop, and the question it needs answered
// after a slow step is not only "how long" but "how much work": did that check parse every file
// again, did that no-op build emit an assembly, how many reference images did it open. So the CLI
// reports both -- its own wall and CPU time, and the structural counters the compiler keeps
// (`CompilerWorkCounters`) -- as a single compact JSON object:
//
//   * `--stats` writes it as ONE line, the LAST line, on STDERR, so stdout (`check`'s JSON envelope,
//     `test --json`) stays exactly the schema it documents;
//   * `--stats=<path>` writes it to that file instead, so a caller that also captures the command's
//     own stderr (the agent-loop benchmark does) reads it without parsing around diagnostics.
//
// The object is schema `nsharp.cli-stats` version 1 (`memory/components/cli-toolchain.md`): adding a
// field is compatible, renaming or retyping one is a new `schemaVersion`.
//
// THE FLAG IS STRIPPED BEFORE THE COMMAND SEES ITS ARGUMENTS, and only before a `--` separator, so
// no command parser has to learn it and no program argument after `--` is ever eaten. It is accepted
// by `build`, `check` and `test` -- the agent loop -- and refused by name everywhere else rather
// than being silently ignored.
class CliStatsRequest {
    Requested: bool
    OutputPath: string?
    Error: string?
    CommandArgs: string[]

    constructor(requested: bool, outputPath: string?, error: string?, commandArgs: string[]) {
        Requested = requested
        OutputPath = outputPath
        Error = error
        CommandArgs = commandArgs
    }
}

class CliStatsKernels {
    static SchemaName: string => "nsharp.cli-stats"
    static SchemaVersion: int => 1

    static func IsStatsArgument(argument: string): bool {
        return argument == "--stats" || argument.StartsWith("--stats=", StringComparison.Ordinal)
    }

    // `build` (1), `test` (5) and `check` (13), by `ProgramCommandKernels.GetCommandKind` number.
    static func SupportsStats(commandKind: int): bool {
        return commandKind == 1 || commandKind == 5 || commandKind == 13
    }

    static func UnsupportedCommandMessage(command: string): string {
        return "--stats is supported by 'nlc build', 'nlc check' and 'nlc test', not by 'nlc " + command + "'."
    }

    static func MissingPathMessage(): string {
        return "--stats=<path> needs a file path after '='; use --stats on its own to write the stats line to stderr."
    }

    static func RepeatedMessage(): string {
        return "--stats was given more than once."
    }

    // Split `--stats` / `--stats=<path>` out of a command's own arguments. Everything at or after a
    // `--` separator is passed through untouched.
    static func Extract(commandArgs: string[]): CliStatsRequest {
        remaining := new List<string>()
        requested := false
        outputPath: string? = null
        error: string? = null
        passthrough := false
        for argument in commandArgs {
            if passthrough || !IsStatsArgument(argument) {
                if argument == "--" {
                    passthrough = true
                }
                remaining.Add(argument)
                continue
            }

            if requested {
                error = RepeatedMessage()
            }
            requested = true
            if argument != "--stats" {
                path := argument.Substring("--stats=".Length)
                if path.Length == 0 {
                    error = MissingPathMessage()
                } else {
                    outputPath = path
                }
            }
        }

        return new CliStatsRequest(requested, outputPath, error, remaining.ToArray())
    }

    static func ToJson(
        command: string,
        exitCode: int,
        wallMs: long,
        cpuMs: long,
        peakWorkingSetBytes: long,
        counters: CompilerWorkCounterSnapshot
    ): string {
        counterObject := new Dictionary<string, object?>()
        counterObject["filesParsed"] = counters.FilesParsed
        counterObject["emitParses"] = counters.EmitParses
        counterObject["filesAnalyzed"] = counters.FilesAnalyzed
        counterObject["assembliesEmitted"] = counters.AssembliesEmitted
        counterObject["referenceAssembliesLoaded"] = counters.ReferenceAssembliesLoaded
        counterObject["processesSpawned"] = counters.ProcessesSpawned

        envelope := new Dictionary<string, object?>()
        envelope["schema"] = SchemaName
        envelope["schemaVersion"] = SchemaVersion
        envelope["command"] = command
        envelope["exitCode"] = exitCode
        envelope["wallMs"] = wallMs
        envelope["cpuMs"] = cpuMs
        // Omitted, like every null field in a CLI envelope, where the platform does not report it:
        // macOS answers 0 for the peak working set.
        if peakWorkingSetBytes > 0 {
            envelope["peakWorkingSetBytes"] = peakWorkingSetBytes
        }
        envelope["counters"] = counterObject
        return JsonSerializer.Serialize<Dictionary<string, object?>>(envelope)
    }
}

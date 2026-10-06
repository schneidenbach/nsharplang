namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.IO

// HOW TO RUN THE AGENT-LOOP BENCHMARK (`--agent-loop`).
//
//     dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll build --project tests/native/compile-time-bench
//     dotnet tests/native/compile-time-bench/bin/Debug/net10.0/NSharpLang.CompileTimeBench.dll --agent-loop
//
// Options:
//     --sizes <list>           small, medium, large (comma-separated) or all (default small,medium)
//     --runs <n>               samples per scenario (default 3)
//     --cli <Cli.dll>          the CLI under test (default: the Debug build beside the repo root)
//     --base-cli <Cli.dll>     interleave this base CLI with head and report paired ratios
//     --daemon                 keep `nlc daemon` running for the project during each sample
//     --judge                  exit 1 when a counter differs from the committed baseline
//     --write-baseline <path>  write the measured rows as a baseline file (the owner's re-baseline)
//     --ratchet                lower the committed baseline's counters to this run's; refuses a rise
//     --out <dir>              output directory (default artifacts/agent-loop/<local date>)
//
// It prints the table and writes `agent-loop.md` to the output directory.
class AgentLoopOptions {
    SizeNames: List<string>
    Runs: int
    CliDll: string
    BaseCliDll: string
    Daemon: bool
    Judge: bool
    Ratchet: bool
    WriteBaseline: string
    OutputDirectory: string
    ShowHelp: bool
    Error: string

    constructor(cliDll: string, outputDirectory: string) {
        SizeNames = AgentLoopGateSizeNames()
        Runs = 3
        CliDll = cliDll
        BaseCliDll = ""
        Daemon = false
        Judge = false
        Ratchet = false
        WriteBaseline = ""
        OutputDirectory = outputDirectory
        ShowHelp = false
        Error = ""
    }
}

func AgentLoopRequested(args: string[]): bool {
    i := 1
    while i < args.Length {
        if args[i] == "--agent-loop" {
            return true
        }

        i = i + 1
    }

    return false
}

func AgentLoopHelpText(): string {
    return "N# agent-loop performance benchmark\n" + "\n" + "Usage: NSharpLang.CompileTimeBench --agent-loop [options]\n" + "\n" + "Measures cold and daemon-warm edit/check/build/test scenarios on small, medium and large projects.\n" + "Structural CompilerWorkCounters are gated exactly; timings are paired against --base-cli in the same run.\n" + "\n" + "Options:\n" + "  --sizes <list>           small, medium, large (comma-separated) or all (default small,medium)\n" + "  --runs <n>               paired samples per scenario (default 3)\n" + "  --cli <path>             head Cli.dll (default: src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll)\n" + "  --base-cli <path>        base Cli.dll measured interleaved with head; prints head/base ratios\n" + "  --daemon                 Keep nlc daemon running for each single-CLI sample\n" + "  --judge                  Exit 1 when structural counters differ from the committed baseline\n" + "  --write-baseline <path>  Write structural counters only (the owner's re-baseline)\n" + "  --ratchet                Lower the committed counter baseline; refuses any rise\n" + "  --out <dir>              Output directory (default artifacts/agent-loop/<local date>)\n" + "  --help, -h               Show this help text"
}

func AgentLoopParseSizes(text: string): List<string> {
    names := new List<string>()
    if text == "all" {
        sizes := AgentLoopSizes()
        i := 0
        while i < sizes.Count {
            names.Add(sizes[i].Name)
            i = i + 1
        }

        return names
    }

    parts := text.Split(',')
    j := 0
    while j < parts.Length {
        name := parts[j].Trim()
        if name != "" {
            names.Add(name)
        }

        j = j + 1
    }

    return names
}

func AgentLoopParseOptions(args: string[], repositoryRoot: string): AgentLoopOptions {
    options := new AgentLoopOptions(
        BenchDefaultCliDll(repositoryRoot),
        Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "artifacts"), "agent-loop"), BenchLocalDateStamp())
    )

    i := 1
    while i < args.Length {
        argument := args[i]
        hasValue := i + 1 < args.Length
        if argument == "--agent-loop" {
            i = i + 1
            continue
        }

        if argument == "--help" || argument == "-h" {
            options.ShowHelp = true
        } else if argument == "--daemon" {
            options.Daemon = true
        } else if argument == "--judge" {
            options.Judge = true
        } else if argument == "--ratchet" {
            options.Ratchet = true
        } else if !hasValue && (argument == "--sizes" || argument == "--runs" || argument == "--cli" || argument == "--base-cli" || argument == "--write-baseline" || argument == "--out") {
            options.Error = argument + " needs a value. Run with --agent-loop --help for the option list."
            return options
        } else if argument == "--sizes" {
            options.SizeNames = AgentLoopParseSizes(args[i + 1])
            k := 0
            while k < options.SizeNames.Count {
                if AgentLoopFindSize(options.SizeNames[k]) == null {
                    options.Error = "--sizes takes small, medium, large or all, not '" + options.SizeNames[k] + "'."
                    return options
                }

                k = k + 1
            }

            i = i + 1
        } else if argument == "--runs" {
            runs := BenchParseCount(args[i + 1])
            if runs <= 0 {
                options.Error = "--runs needs a positive whole number of samples, not '" + args[i + 1] + "'."
                return options
            }

            options.Runs = runs
            i = i + 1
        } else if argument == "--cli" {
            options.CliDll = Path.GetFullPath(args[i + 1])
            i = i + 1
        } else if argument == "--base-cli" {
            options.BaseCliDll = Path.GetFullPath(args[i + 1])
            i = i + 1
        } else if argument == "--write-baseline" {
            options.WriteBaseline = Path.GetFullPath(args[i + 1])
            i = i + 1
        } else if argument == "--out" {
            options.OutputDirectory = Path.GetFullPath(args[i + 1])
            i = i + 1
        } else {
            options.Error = "Unknown option '" + argument + "'. Run with --agent-loop --help for the option list."
            return options
        }

        i = i + 1
    }

    return options
}

func AgentLoopCliIdentity(cliDll: string): string {
    run := BenchRunProcess("dotnet", BenchQuote(cliDll) + " --version", Path.GetTempPath())
    if run.ExitCode == 0 && run.Stdout.Trim() != "" {
        return run.Stdout.Trim()
    }

    return cliDll
}

func AgentLoopMachineText(environment: BenchEnvironmentFacts): string {
    return environment.Architecture + ", " + environment.OsDescription + ", " + BenchCountText(environment.ProcessorCount) + " logical cores, .NET SDK " + environment.DotnetVersion + ", " + environment.TimeUtility
}

func AgentLoopMain(args: string[], repositoryRoot: string) {
    options := AgentLoopParseOptions(args, repositoryRoot)
    if options.ShowHelp {
        print AgentLoopHelpText()
        return
    }

    if options.Error != "" {
        BenchFailHarness(options.Error)
    }

    if !File.Exists(options.CliDll) {
        BenchFailHarness("The CLI under test was not found at " + options.CliDll + ". Build it with: ./scripts/dev.sh")
    }

    if !AgentLoopCliSupportsStats(options.CliDll) {
        BenchFailHarness("The CLI under test at " + options.CliDll + " does not support --stats, so its structural counters cannot be read.")
    }

    if options.BaseCliDll != "" && !File.Exists(options.BaseCliDll) {
        BenchFailHarness("The base CLI was not found at " + options.BaseCliDll + ".")
    }

    if options.BaseCliDll != "" && (options.WriteBaseline != "" || options.Ratchet) {
        BenchFailHarness("--base-cli cannot be combined with --write-baseline or --ratchet; measure the head CLI alone for structural baseline updates.")
    }

    Directory.CreateDirectory(options.OutputDirectory)
    environment := BenchReadEnvironmentFacts(repositoryRoot)
    loadAtStart := BenchReadMachineLoad()
    print "agent-loop benchmark: sizes " + String.Join(",", options.SizeNames) + ", " + BenchIntText(options.Runs) + " sample(s) per scenario; load " + BenchLoadText(loadAtStart.LoadThousandths) + " on " + BenchCountText(loadAtStart.Cores) + " cores (trend metadata only)"
    print "head CLI: " + options.CliDll

    relative: AgentLoopRelativeMatrix? = null
    rows := new List<AgentLoopRow>()
    if options.BaseCliDll != "" {
        print "base CLI: " + options.BaseCliDll
        relative = AgentLoopMeasureRelativeMatrix(options.CliDll, options.BaseCliDll, repositoryRoot, options.SizeNames, options.Runs, true)
        rows = (relative ?? new AgentLoopRelativeMatrix()).HeadCounterRows
    } else if options.WriteBaseline != "" || options.Ratchet || options.Judge {
        rows = AgentLoopMeasureStructuralRows(options.CliDll, repositoryRoot, options.SizeNames, options.Runs, true)
    } else {
        rows = AgentLoopMeasureMatrix(options.CliDll, repositoryRoot, options.SizeNames, options.Runs, true, options.Daemon, true)
    }

    baselinePath := AgentLoopBaselinePath(repositoryRoot)
    baseline: AgentLoopBaseline? = null
    if File.Exists(baselinePath) {
        baseline = AgentLoopParseBaseline(File.ReadAllText(baselinePath))
    }

    loadAtEnd := BenchReadMachineLoad()
    countersTable := AgentLoopRenderTable(rows, (baseline ?? new AgentLoopBaseline()).Rows, "the committed structural counter baseline " + AgentLoopBaselineRelativePath())
    table := countersTable
    if relative != null {
        table = AgentLoopRelativeTimingTable((relative ?? new AgentLoopRelativeMatrix()).Timings) + "\n\n## Head structural counters\n\n" + countersTable
    }
    header := "Agent-loop benchmark, headCommit=" + environment.CliCommit + ", " + AgentLoopMachineText(environment) + ", loadAtStart=" + BenchLoadText(loadAtStart.LoadThousandths) + ", loadAtEnd=" + BenchLoadText(loadAtEnd.LoadThousandths) + " (trend metadata only), " + BenchIntText(options.Runs) + " sample(s) per scenario."
    if options.BaseCliDll != "" {
        header = header + " Base CLI=" + options.BaseCliDll + "; baseIdentity=" + AgentLoopCliIdentity(options.BaseCliDll) + "."
    }
    File.WriteAllText(Path.Combine(options.OutputDirectory, "agent-loop.md"), header + "\n\n" + table)
    print ""
    print header
    print ""
    print table

    if options.WriteBaseline != "" {
        unbaselinable := AgentLoopUnbaselinableRows(rows)
        if unbaselinable.Count > 0 {
            BenchFailHarness("No baseline written; these rows cannot be a budget: " + String.Join(" | ", unbaselinable))
        }

        written := new AgentLoopBaseline()
        written.SchemaVersion = 2
        written.Rows = rows
        Directory.CreateDirectory(Path.GetDirectoryName(options.WriteBaseline) ?? options.OutputDirectory)
        File.WriteAllText(options.WriteBaseline, AgentLoopBaselineJson(written))
        print "wrote baseline " + options.WriteBaseline
    }

    if options.Ratchet {
        if baseline == null {
            BenchFailHarness("--ratchet needs the committed baseline at " + baselinePath + ".")
        }

        ratcheted := baseline ?? new AgentLoopBaseline()
        refusals := AgentLoopRatchetCounters(ratcheted, rows)
        File.WriteAllText(baselinePath, AgentLoopBaselineJson(ratcheted))
        print "ratcheted the counters of " + AgentLoopBaselineRelativePath()
        if refusals.Count > 0 {
            Console.Error.WriteLine("rows NOT ratcheted:")
            r := 0
            while r < refusals.Count {
                Console.Error.WriteLine("  " + refusals[r])
                r = r + 1
            }

            Environment.Exit(1)
        }
    }

    if options.Judge {
        if baseline == null {
            BenchFailHarness("--judge needs the committed baseline at " + baselinePath + ".")
        }

        failures := AgentLoopCounterFailures(baseline ?? new AgentLoopBaseline(), rows)
        if failures.Count > 0 {
            Console.Error.WriteLine("agent-loop counters differ from " + AgentLoopBaselineRelativePath() + ":")
            j := 0
            while j < failures.Count {
                Console.Error.WriteLine("  " + failures[j])
                j = j + 1
            }

            Environment.Exit(1)
        }

        print "agent-loop counters match " + AgentLoopBaselineRelativePath()
    }

    if relative != null {
        failures := AgentLoopRelativeTimingFailures((relative ?? new AgentLoopRelativeMatrix()).Timings)
        if (relative ?? new AgentLoopRelativeMatrix()).Failures.Count > 0 {
            failures.AddRange((relative ?? new AgentLoopRelativeMatrix()).Failures)
        }
        if options.Judge {
            failures.AddRange(AgentLoopCounterFailures(baseline ?? new AgentLoopBaseline(), rows))
        }
        relativeReport := "relative benchmark report; headCommit=" + environment.CliCommit + "; baseCli=" + options.BaseCliDll + "; baseIdentity=" + AgentLoopCliIdentity(options.BaseCliDll) + "; machine=" + AgentLoopMachineText(environment) + "; loadAtStart=" + BenchLoadText(loadAtStart.LoadThousandths) + "; loadAtEnd=" + BenchLoadText(loadAtEnd.LoadThousandths) + "; verdicts=" + BenchIntText(failures.Count)
        _ = AgentLoopWriteRelativeGateRecord(repositoryRoot, relativeReport, table)
        if failures.Count > 0 {
            Console.Error.WriteLine("agent-loop relative comparison failures:")
            i := 0
            while i < failures.Count {
                Console.Error.WriteLine("  " + failures[i])
                i = i + 1
            }
            Environment.Exit(1)
        }
    }
}

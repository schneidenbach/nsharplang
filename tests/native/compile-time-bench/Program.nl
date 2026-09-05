namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.IO
import System.Text


// HOW TO RUN THE COMPILE-TIME BENCHMARK.
//
//     dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll build --project tests/native/compile-time-bench
//     dotnet tests/native/compile-time-bench/bin/Debug/net10.0/NSharpLang.CompileTimeBench.dll --runs 5
//
// Options:
//     --runs <n>                 measured runs per project per command (default 5)
//     --out <dir>                output directory (default artifacts/compile-time/<local date>)
//     --cli <path to Cli.dll>    the CLI under test (default: the Debug build beside the repo root)
//     --scope corpus|bootstrap|all   which projects to sweep (default all)
//     --only <substring>         restrict to projects whose repository-relative path contains it
//     --help                     print this list
//
// It writes `runs.csv` (one row per run), `compile-time.csv` (one row per project x command) and
// `compile-time.md` (the readable report), and prints the aggregate table to stdout.
//
// Exit codes: 0 when the sweep completed and the three files were written; 1 on a HARNESS failure
// — a missing CLI, an unwritable output directory, or a build that modified the project directory
// it was told to compile. A project that fails to compile is NOT a harness failure: its row is
// recorded with `ok=false` and its timing kept, because the time the CLI took to reject a project
// is still compile time.
class BenchOptions {
    Runs: int
    OutputDirectory: string
    CliDll: string
    Scope: string
    Only: string
    ShowHelp: bool
    Error: string

    constructor(runs: int, outputDirectory: string, cliDll: string, scope: string, only: string) {
        Runs = runs
        OutputDirectory = outputDirectory
        CliDll = cliDll
        Scope = scope
        Only = only
        ShowHelp = false
        Error = ""
    }
}

func BenchHelpText(): string {
    return "N# compile-time benchmark\n" + "\n" + "Usage: NSharpLang.CompileTimeBench [options]\n" + "\n" + "Measures how long `nlc build` and `nlc check` take over the example, test and template\n" + "corpus and over the large-project case, src/NSharpLang.Compiler.BootstrapServices.\n" + "\n" + "Options:\n" + "  --runs <n>              Measured runs per project per command (default 5)\n" + "  --out <dir>             Output directory (default artifacts/compile-time/<local date>)\n" + "  --cli <path>            Cli.dll under test (default: src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll)\n" + "  --scope <scope>         corpus, bootstrap or all (default all)\n" + "  --only <substring>      Only projects whose repository-relative path contains <substring>\n" + "  --help, -h              Show this help text\n" + "\n" + "Outputs, written to the output directory:\n" + "  runs.csv                One row per individual run\n" + "  compile-time.csv        One row per project and command, with the median\n" + "  compile-time.md         The readable report, aggregate table included\n" + "\n" + "Exit codes:\n" + "  0  The sweep completed and the outputs were written\n" + "  1  A harness failure (missing CLI, unwritable output, or a build that modified the tree)"
}

// Local date as `YYYY-MM-DD`, assembled from the parts rather than a format string so the report
// directory name is the same on every culture.
func BenchLocalDateStamp(): string {
    now := DateTime.Now
    return BenchIntText(now.Year) + "-" + BenchPad2(now.Month) + "-" + BenchPad2(now.Day)
}

func BenchPad2(value: int): string {
    if value < 10 {
        return "0" + BenchIntText(value)
    }

    return BenchIntText(value)
}

func BenchDefaultOutputDirectory(repositoryRoot: string): string {
    return Path.Combine(
        Path.Combine(Path.Combine(repositoryRoot, "artifacts"), "compile-time"),
        BenchLocalDateStamp()
    )
}

func BenchParseOptions(args: string[], repositoryRoot: string): BenchOptions {
    options := new BenchOptions(
        5,
        BenchDefaultOutputDirectory(repositoryRoot),
        BenchDefaultCliDll(repositoryRoot),
        "all",
        ""
    )

    i := 1
    while i < args.Length {
        argument := args[i]
        if argument == "--help" || argument == "-h" {
            options.ShowHelp = true
        } else if argument == "--runs" {
            if i + 1 >= args.Length {
                options.Error = "--runs needs a positive whole number of runs."
                return options
            }

            runs := BenchParseCount(args[i + 1])
            if runs <= 0 {
                options.Error = "--runs needs a positive whole number of runs, not '" + args[i + 1] + "'."
                return options
            }

            options.Runs = runs
            i = i + 1
        } else if argument == "--out" {
            if i + 1 >= args.Length {
                options.Error = "--out needs a directory."
                return options
            }

            options.OutputDirectory = Path.GetFullPath(args[i + 1])
            i = i + 1
        } else if argument == "--cli" {
            if i + 1 >= args.Length {
                options.Error = "--cli needs a path to Cli.dll."
                return options
            }

            options.CliDll = Path.GetFullPath(args[i + 1])
            i = i + 1
        } else if argument == "--scope" {
            if i + 1 >= args.Length {
                options.Error = "--scope needs one of corpus, bootstrap or all."
                return options
            }

            scope := args[i + 1]
            if scope != "corpus" && scope != "bootstrap" && scope != "all" {
                options.Error = "--scope must be corpus, bootstrap or all, not '" + scope + "'."
                return options
            }

            options.Scope = scope
            i = i + 1
        } else if argument == "--only" {
            if i + 1 >= args.Length {
                options.Error = "--only needs a substring of a repository-relative project path."
                return options
            }

            options.Only = args[i + 1]
            i = i + 1
        } else {
            options.Error = "Unknown option '" + argument + "'. Run with --help for the option list."
            return options
        }

        i = i + 1
    }

    return options
}

// The projects this run will sweep, in report order: the large-project case first, then the corpus
// sorted ordinally. `--only` filters both, so a smoke run never pays for BootstrapServices.
func BenchSelectProjects(repositoryRoot: string, options: BenchOptions): List<string> {
    selected := new List<string>()
    if options.Scope == "all" || options.Scope == "bootstrap" {
        if BenchMatchesOnly(BenchBootstrapProjectPath(), options.Only) {
            selected.Add(BenchBootstrapProjectPath())
        }
    }

    if options.Scope == "all" || options.Scope == "corpus" {
        corpus := BenchCollectCorpusProjects(repositoryRoot)
        i := 0
        while i < corpus.Count {
            if BenchMatchesOnly(corpus[i], options.Only) {
                selected.Add(corpus[i])
            }

            i = i + 1
        }
    }

    return selected
}

func BenchMatchesOnly(project: string, only: string): bool {
    if only == "" {
        return true
    }

    return project.IndexOf(only, StringComparison.Ordinal) >= 0
}

func main(): void {
    repositoryRoot := BenchRepositoryRoot()
    options := BenchParseOptions(Environment.GetCommandLineArgs(), repositoryRoot)

    if options.ShowHelp {
        print BenchHelpText()
        return
    }

    if options.Error != "" {
        BenchFailHarness(options.Error)
    }

    if !File.Exists(options.CliDll) {
        BenchFailHarness(
            "The CLI under test was not found at " + options.CliDll + ". Build it with: dotnet build src/NSharpLang.Cli/Cli.csproj -c Debug"
        )
    }

    try {
        Directory.CreateDirectory(options.OutputDirectory)
    } catch {
        BenchFailHarness("The output directory " + options.OutputDirectory + " could not be created.")
    }

    projects := BenchSelectProjects(repositoryRoot, options)
    if projects.Count == 0 {
        BenchFailHarness("No project matched --scope " + options.Scope + " with --only '" + options.Only + "'.")
    }

    environment := BenchReadEnvironmentFacts(repositoryRoot)
    runRows := new StringBuilder()
    runRows.Append(BenchRunCsvHeader())
    runRows.Append("\n")

    results := new List<BenchProjectResult>()
    treeViolations := new List<string>()

    print "compile-time benchmark: " + BenchIntText(projects.Count) + " project(s) x 2 commands x " + BenchIntText(options.Runs) + " run(s), writing to " + options.OutputDirectory

    i := 0
    while i < projects.Count {
        project := projects[i]
        print "  [" + BenchIntText(i + 1) + "/" + BenchIntText(projects.Count) + "] " + project

        buildResult := BenchMeasureProjectCommand(options.CliDll, repositoryRoot, project, "build", options.Runs, runRows)
        results.Add(buildResult)
        BenchRecordTreeViolation(buildResult, treeViolations)

        checkResult := BenchMeasureProjectCommand(options.CliDll, repositoryRoot, project, "check", options.Runs, runRows)
        results.Add(checkResult)
        BenchRecordTreeViolation(checkResult, treeViolations)

        print "      " + BenchProgressText("build", buildResult) + ", " + BenchProgressText("check", checkResult) + ", files=" + BenchIntText(buildResult.Files) + ", lines=" + BenchLongText(buildResult.Lines)

        i = i + 1
    }

    File.WriteAllText(Path.Combine(options.OutputDirectory, "runs.csv"), runRows.ToString() ?? "")
    File.WriteAllText(Path.Combine(options.OutputDirectory, "compile-time.csv"), BenchSummaryCsv(results))
    markdown := BenchRenderMarkdown(repositoryRoot, options, environment, results, treeViolations)
    File.WriteAllText(Path.Combine(options.OutputDirectory, "compile-time.md"), markdown)

    print ""
    print BenchAggregateTable(BenchCorpusResults(results), "measured corpus projects")

    if treeViolations.Count > 0 {
        Console.Error.WriteLine("HARNESS FAILURE: the CLI modified the project directory it was told to compile.")
        j := 0
        while j < treeViolations.Count {
            Console.Error.WriteLine(treeViolations[j])
            j = j + 1
        }

        BenchFailHarness(
            "The outputs were still written to " + options.OutputDirectory + "; the tree violation is recorded in compile-time.md."
        )
    }

    print "compile-time benchmark: wrote runs.csv, compile-time.csv and compile-time.md to " + options.OutputDirectory
}

// A harness failure — a missing CLI, an unwritable output directory, a build that modified the tree
// — ends the process with exit 1. It is deliberately NOT an exception: the message a user needs is
// the one sentence below, not a stack trace.
func BenchFailHarness(message: string) {
    Console.Error.WriteLine(message)
    Environment.Exit(1)
}

// A row that was never spawned reports why, not a median of nothing.
func BenchProgressText(command: string, result: BenchProjectResult): string {
    if BenchHasNoSources(result) {
        return command + " not spawned (" + BenchNoSourcesStatus() + ")"
    }

    return command + " " + BenchLongText(result.MedianWallMs) + " ms (status=" + result.Status + ")"
}

func BenchRecordTreeViolation(result: BenchProjectResult, treeViolations: List<string>) {
    if result.TreeDiff == "" {
        return
    }

    treeViolations.Add("  " + result.Project + " (" + result.Command + "):\n" + result.TreeDiff)
}

func BenchSummaryCsv(results: List<BenchProjectResult>): string {
    builder := new StringBuilder()
    builder.Append(BenchSummaryCsvHeader())
    builder.Append("\n")
    i := 0
    while i < results.Count {
        builder.Append(BenchSummaryCsvRow(results[i]))
        builder.Append("\n")
        i = i + 1
    }

    return builder.ToString() ?? ""
}

func BenchCorpusResults(results: List<BenchProjectResult>): List<BenchProjectResult> {
    corpus := new List<BenchProjectResult>()
    i := 0
    while i < results.Count {
        if results[i].Project != BenchBootstrapProjectPath() {
            corpus.Add(results[i])
        }

        i = i + 1
    }

    return corpus
}

func BenchBootstrapResults(results: List<BenchProjectResult>): List<BenchProjectResult> {
    bootstrap := new List<BenchProjectResult>()
    i := 0
    while i < results.Count {
        if results[i].Project == BenchBootstrapProjectPath() {
            bootstrap.Add(results[i])
        }

        i = i + 1
    }

    return bootstrap
}

func BenchRenderMarkdown(
    repositoryRoot: string,
    options: BenchOptions,
    environment: BenchEnvironmentFacts,
    results: List<BenchProjectResult>,
    treeViolations: List<string>
): string {
    corpusProjects := BenchCollectCorpusProjects(repositoryRoot)
    corpus := BenchCorpusResults(results)
    bootstrap := BenchBootstrapResults(results)

    builder := new StringBuilder()
    BenchAppendLine(builder, "# N# compile time")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "| fact | value |")
    BenchAppendLine(builder, "|---|---|")
    BenchAppendLine(builder, "| measured (local date) | " + BenchLocalDateStamp() + " |")
    BenchAppendLine(builder, "| CLI commit | `" + environment.CliCommit + "` |")
    BenchAppendLine(builder, "| CLI under test | `" + options.CliDll + "` |")
    BenchAppendLine(builder, "| dotnet --version | " + environment.DotnetVersion + " |")
    BenchAppendLine(builder, "| OS (`uname -sr`) | " + environment.OsDescription + " |")
    BenchAppendLine(builder, "| architecture (`uname -m`) | " + environment.Architecture + " |")
    BenchAppendLine(builder, "| logical processors | " + BenchCountText(environment.ProcessorCount) + " |")
    BenchAppendLine(builder, "| peak RSS source | " + environment.TimeUtility + " |")
    BenchAppendLine(builder, "| runs per project per command | " + BenchIntText(options.Runs) + " |")
    BenchAppendLine(builder, "| median rule | the middle value of the sorted runs; for an EVEN run count, the LOWER middle value |")
    BenchAppendLine(builder, "| scope | " + options.Scope + " |")
    BenchAppendLine(builder, "| only | " + BenchOnlyText(options.Only) + " |")
    BenchAppendLine(
        builder,
        "| corpus size | " + BenchIntText(corpusProjects.Count) + " projects with a `project.yml` under `examples/`, `tests/` and `templates/`, of which " + BenchIntText(BenchProjectsWithSources(repositoryRoot, corpusProjects)) + " have non-test sources |"
    )
    BenchAppendLine(builder, "")

    BenchAppendLine(builder, "## How these numbers are produced")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "- **Wall clock** is `DateTime.UtcNow` immediately before `Process.Start()` and immediately")
    BenchAppendLine(builder, "  after `WaitForExit()`, in milliseconds. It is the number the columns below report.")
    BenchAppendLine(builder, "- **resolve / emit / total** are the CLI's OWN `--timings` numbers, read off stderr. The CLI")
    BenchAppendLine(builder, "  formats them to a tenth of a second, so they are coarser than the wall clock by")
    BenchAppendLine(builder, "  construction and are shown for the resolve-versus-emit split, not for precision.")
    BenchAppendLine(builder, "- **peak RSS** is the kernel's maximum resident set for the child, via `" + environment.TimeUtility + "`.")
    BenchAppendLine(builder, "  An em dash means the OS time utility was unavailable, which is never a failure.")
    BenchAppendLine(builder, "- **Every build is fresh.** `nlc build` has no incremental cache and `nlc check` has no daemon")
    BenchAppendLine(builder, "  on this path; the build output goes to a directory created new under the system temp")
    BenchAppendLine(builder, "  directory for every single run and deleted afterwards.")
    BenchAppendLine(builder, "- **Every build is proven not to have touched the tree.** A recursive listing of the project")
    BenchAppendLine(builder, "  directory (relative path and last-write UTC tick, every directory sorted) is taken before and")
    BenchAppendLine(builder, "  after each build, and any difference is a harness failure carried to a non-zero exit code.")
    BenchAppendLine(builder, "  The listing carries no byte length because `FileInfo` is unreachable on this emit path; the")
    BenchAppendLine(builder, "  last-write tick moves on any write regardless of whether the length did.")
    BenchAppendLine(builder, "- **A project that fails to compile keeps its timing.** The `ok` column marks it; the time the")
    BenchAppendLine(builder, "  CLI took to reject the project is still compile time.")
    BenchAppendLine(builder, "- **A FAILING build did not reach emit, and its milliseconds do not cover emit.** `nlc build`")
    BenchAppendLine(builder, "  calls `MultiFileCompiler.CompileToIlAssembly(validateStrictLint: true)`, and")
    BenchAppendLine(builder, "  `RunLegacyValidationPipeline` RETURNS before `AnalyzeAllFiles()` as soon as strict lint reports")
    BenchAppendLine(builder, "  an error. So a row whose `ok` is `no (build)` measures PARSE + STRICT LINT only — read its")
    BenchAppendLine(builder, "  `check results` census below to see what stopped it. The regression gate pins this explicitly:")
    BenchAppendLine(builder, "  its baseline carries a `stage` and an `expectedExitCode`, and a run that stops failing fails")
    BenchAppendLine(builder, "  the gate, because it would then be measuring stages the baseline never covered.")
    BenchAppendLine(builder, "- **A project with no non-test sources is classified, not failed.** Neither command is spawned")
    BenchAppendLine(builder, "  for it; see the section below.")
    BenchAppendLine(builder, "")

    BenchAppendLine(builder, "### The file-selection rule, replicated")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "`files` and `lines` count the `.nl` files the command ACTUALLY compiles. `nlc build` reaches")
    BenchAppendLine(builder, "its source list through `ProjectConfig.GetSourceFiles(projectRoot, includeTests: false)`, and")
    BenchAppendLine(builder, "`nlc check` reaches the SAME function through `CodeIntelligenceService.LoadProject` ->")
    BenchAppendLine(builder, "`MultiFileCompilerInputBuilder.BuildFromProject` -> `DiscoverSourceFiles`, which also passes")
    BenchAppendLine(builder, "`false`. **Build and check therefore select the same file set, so there is one file count and")
    BenchAppendLine(builder, "one line count per project, not two.** The rule is:")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "1. Recursively collect `*.nl` under the project directory.")
    BenchAppendLine(builder, "2. Do not descend into `.context`, `.git`, `.github`, `.hermes`, `.vscode`, `.vscode-test`,")
    BenchAppendLine(builder, "   `.worktrees`, `bin`, `node_modules`, `nsharp`, `obj` or `out` (`ShouldSkipSourceDirectory`).")
    BenchAppendLine(builder, "3. Drop every path ending in `.tests.nl`, case-insensitively.")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "`lines` is the number of `\\n`-terminated lines in those files. Each measured project")
    BenchAppendLine(builder, "cross-checks this replication against the live compiler: the `checkedFiles` field of")
    BenchAppendLine(builder, "`nlc check --json` is `snapshot.SourceFiles.Count`, and a disagreement is reported below.")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "`ProjectSourceFileFilter` also drops paths matching the `exclude:` globs of `project.yml`.")
    BenchAppendLine(builder, "No measured project declares `exclude:`, so that arm is not replicated; the `checkedFiles`")
    BenchAppendLine(builder, "cross-check is what would catch a project that started to.")
    BenchAppendLine(builder, "")

    BenchAppendLine(builder, "## The large-project case: `" + BenchBootstrapProjectPath() + "`")
    BenchAppendLine(builder, "")
    BenchRenderProjectTable(builder, bootstrap)
    BenchAppendLine(builder, "")

    BenchAppendLine(builder, "## The corpus")
    BenchAppendLine(builder, "")
    BenchRenderProjectTable(builder, corpus)
    BenchAppendLine(builder, "")

    BenchAppendLine(builder, "## Aggregate over the corpus")
    BenchAppendLine(builder, "")
    builder.Append(BenchAggregateTable(corpus, "measured corpus projects"))
    BenchAppendLine(builder, "")
    BenchRateSpreadLines(corpus, "build", builder)
    BenchRateSpreadLines(corpus, "check", builder)
    BenchAppendLine(builder, "")

    BenchRenderNoSourcesSection(builder, results)
    BenchRenderFailureSection(builder, results)
    BenchRenderFileCountSection(builder, results)
    BenchRenderTreeSection(builder, treeViolations)
    return builder.ToString() ?? ""
}

// The failing run's stderr is carried VERBATIM, colour escapes included, because that is the text
// a reader has to match against their own terminal. `nlc check --json` puts its diagnostics in the
// envelope on stdout and leaves stderr empty, which is why the empty case is named rather than
// shown as a blank block.
func BenchStderrOrNone(stderr: string): string {
    if stderr == "" {
        return "(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)"
    }

    return stderr
}

// How many of the corpus's projects have anything for `nlc build` and `nlc check` to read. Counted
// over the WHOLE corpus, not over the rows this run measured, because it is a fact about the tree
// and must read the same whether the run was a smoke `--only` or a full sweep.
func BenchProjectsWithSources(repositoryRoot: string, corpusProjects: List<string>): int {
    count := 0
    i := 0
    while i < corpusProjects.Count {
        directory := BenchAbsoluteProjectPath(repositoryRoot, corpusProjects[i])
        if BenchMeasureProjectSources(directory).Files > 0 {
            count = count + 1
        }

        i = i + 1
    }

    return count
}

func BenchOnlyText(only: string): string {
    if only == "" {
        return "(none — every project in scope)"
    }

    return "`" + only + "`"
}

func BenchRenderProjectTable(builder: StringBuilder, results: List<BenchProjectResult>) {
    if results.Count == 0 {
        BenchAppendLine(builder, "_Not measured in this run._")
        return
    }

    BenchProjectTableHeader(builder)
    projects := BenchDistinctProjects(results)
    i := 0
    while i < projects.Count {
        BenchProjectTableRow(
            builder,
            projects[i],
            BenchFindResult(results, projects[i], "build"),
            BenchFindResult(results, projects[i], "check")
        )
        i = i + 1
    }
}

func BenchRenderNoSourcesSection(builder: StringBuilder, results: List<BenchProjectResult>) {
    BenchAppendLine(builder, "## Projects with no non-test sources")
    BenchAppendLine(builder, "")
    listed := new List<string>()
    i := 0
    while i < results.Count {
        result := results[i]
        if BenchHasNoSources(result) && !BenchListContains(listed, result.Project) {
            listed.Add(result.Project)
        }

        i = i + 1
    }

    if listed.Count == 0 {
        BenchAppendLine(builder, "_Every project measured in this run has at least one non-test source file._")
        BenchAppendLine(builder, "")
        return
    }

    BenchAppendLine(builder, "These " + BenchIntText(listed.Count) + " project(s) hold only `.tests.nl` files.")
    BenchAppendLine(builder, "`nlc build` and `nlc check` both exclude `*.tests.nl`, so neither command has anything")
    BenchAppendLine(builder, "to compile here and both exit 1 — which is why NEITHER WAS SPAWNED and these rows are")
    BenchAppendLine(builder, "classified rather than counted as failures. They are compiled by `nlc test`, in the product")
    BenchAppendLine(builder, "gate's Step 3a, and they contribute no lines and no project to the aggregates above.")
    BenchAppendLine(builder, "")
    j := 0
    while j < listed.Count {
        BenchAppendLine(builder, "- `" + listed[j] + "`")
        j = j + 1
    }

    BenchAppendLine(builder, "")
}

func BenchListContains(values: List<string>, value: string): bool {
    i := 0
    while i < values.Count {
        if values[i] == value {
            return true
        }

        i = i + 1
    }

    return false
}

func BenchRenderFailureSection(builder: StringBuilder, results: List<BenchProjectResult>) {
    BenchAppendLine(builder, "## Projects that did not compile")
    BenchAppendLine(builder, "")
    count := 0
    i := 0
    while i < results.Count {
        result := results[i]
        if !result.Ok {
            BenchAppendLine(builder, "**`" + result.Project + "`** (`" + result.Command + "`) — " + result.FailureDetail)
            BenchAppendLine(builder, "")
            if result.DiagnosticCensus != "" {
                BenchAppendLine(
                    builder,
                    "Diagnostic census from the `nlc check --json` envelope: " + result.DiagnosticCensus
                )
                BenchAppendLine(builder, "")
            }

            BenchAppendLine(builder, "```")
            BenchAppendLine(builder, BenchStderrOrNone(result.FailureStderr))
            BenchAppendLine(builder, "```")
            BenchAppendLine(builder, "")
            count = count + 1
        }

        i = i + 1
    }

    if count == 0 {
        BenchAppendLine(builder, "_Every measured project and command exited zero._")
    }

    BenchAppendLine(builder, "")
}

func BenchRenderFileCountSection(builder: StringBuilder, results: List<BenchProjectResult>) {
    BenchAppendLine(builder, "## File-count cross-check against the live compiler")
    BenchAppendLine(builder, "")
    count := 0
    i := 0
    while i < results.Count {
        result := results[i]
        if result.Command == "check" && result.CheckedFiles >= 0 && result.CheckedFiles != result.Files {
            BenchAppendLine(
                builder,
                "- `" + result.Project + "`: this harness selected " + BenchIntText(result.Files) + " file(s), `nlc check --json` reported `checkedFiles` " + BenchIntText(result.CheckedFiles) + "."
            )
            count = count + 1
        }

        i = i + 1
    }

    if count == 0 {
        BenchAppendLine(builder, "_Every project whose `nlc check --json` envelope carried `checkedFiles` agreed with the")
        BenchAppendLine(builder, "replicated selection rule._")
    }

    BenchAppendLine(builder, "")
}

func BenchRenderTreeSection(builder: StringBuilder, treeViolations: List<string>) {
    BenchAppendLine(builder, "## Repository tree after the sweep")
    BenchAppendLine(builder, "")
    if treeViolations.Count == 0 {
        BenchAppendLine(builder, "_Every measured project directory was byte-identical before and after every build._")
        BenchAppendLine(builder, "")
        return
    }

    BenchAppendLine(builder, "**A build modified the project directory it was told to compile. This run exits 1.**")
    BenchAppendLine(builder, "")
    i := 0
    while i < treeViolations.Count {
        BenchAppendLine(builder, "```")
        BenchAppendLine(builder, treeViolations[i])
        BenchAppendLine(builder, "```")
        i = i + 1
    }

    BenchAppendLine(builder, "")
}

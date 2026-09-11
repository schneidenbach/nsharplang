namespace NSharpLang.Cli.Commands

import System.Collections.Generic

// THE `nlc tree` OPTION, DEPTH AND MESSAGE KERNELS.
//
// These replace the kernel half of four `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `TreeCommandKernels_SummarizesOptions`, `TreeCommandKernels_ParseMaxDepthWithNSharpKernel`,
// `TreeCommandKernels_DeduplicateDependencies_DeduplicatesAndOrdersDependencies` and
// `TreeCommandKernels_DeduplicateTargetFrameworks_DeduplicatesTargetFrameworks`.
//
// WHY THE ESTATE AND NOT `tests/native`. Every claim below is a static call on a type that lives
// three files away in this same compilation unit, with arguments that are string, bool and int
// literals. Nothing here needs a process, a project on disk or a JSON reader — so the estate route
// is not merely cheaper, it is the route with the fewest moving parts between the claim and the
// answer. The claims the deleted bodies made about the SHIPPED COMMAND — exit code, stdout and a
// silent stderr from `nlc tree --help` — cannot be made here at all: `Console.SetOut` declines at
// `emit.call.static-member-unmodeled`, measured, so this emit path cannot capture console output.
// Those rows moved to `tests/native/cli-command-contracts`, which spawns the real CLI.

// ── the option summary ────────────────────────────────────────────────────────
test "tree option summary reads the project, depth, json and help flags" {
    summary := TreeCommandKernels.GetOptionSummary(["--project", "samples/demo", "--depth", "2", "--json", "-h"])

    assert summary.ProjectOption == "samples/demo"
    assert summary.DepthOption == "2"
    assert summary.Json
    assert summary.ShowHelp
}

test "tree option values are taken permissively, so a flag can be consumed as a value" {
    // `--project` swallows the next token whatever it is. This is DELIBERATE and pinned: the
    // option parser does not look ahead for a leading `-`, so `--project --json` binds `--json`
    // as the project path AND the later `--json` still sets the flag.
    summary := TreeCommandKernels.GetOptionSummary(["--project", "--json", "--depth", "--help"])

    assert summary.ProjectOption == "--json"
    assert summary.DepthOption == "--help"
    assert summary.Json
    assert summary.ShowHelp
}

test "the bare word help asks for help" {
    assert TreeCommandKernels.GetOptionSummary(["help"]).ShowHelp
}

// ── the output mode ───────────────────────────────────────────────────────────

test "tree output mode is 2 for text and 1 for json" {
    assert TreeCommandKernels.GetOutputMode(false) == 2
    assert TreeCommandKernels.GetOutputMode(true) == 1
}

// ── the depth parser ──────────────────────────────────────────────────────────

test "the max-depth kernel takes the LAST parseable depth and falls back to the default" {
    // The ten rows below are the ten `(args, expected)` tuples of the deleted
    // `TreeCommandKernels_ParseMaxDepthWithNSharpKernel`, which asserted them in a `foreach`. Each
    // is named here so a failure reports WHICH row moved rather than one anonymous loop iteration.
    assert TreeCommandKernels.GetMaxDepth(new string[](0), 99) == 99
    assert TreeCommandKernels.GetMaxDepth(["--depth", "2"], 99) == 2
    assert TreeCommandKernels.GetMaxDepth(["--depth", "bad", "--depth", "2"], 99) == 2
    assert TreeCommandKernels.GetMaxDepth(["--depth", "--json", "--depth", "+3"], 99) == 3
    assert TreeCommandKernels.GetMaxDepth(["--depth", " -1 "], 99) == -1
    assert TreeCommandKernels.GetMaxDepth(["--depth", "2147483648", "--depth", "-2147483648"], 99) == -2147483648
    assert TreeCommandKernels.GetMaxDepth(["--depth", "1_000"], 99) == 99
    assert TreeCommandKernels.GetMaxDepth(["--depth", "2147483647"], 99) == 2147483647
    assert TreeCommandKernels.GetMaxDepth(["--depth", "+"], 99) == 99
    assert TreeCommandKernels.GetMaxDepth(["--depth", " 7 "], 99) == 7
}

// ── deduplication ─────────────────────────────────────────────────────────────

func TreeDependencyOf(name: string, kind: string, version: string?): TreeDependency {
    return new TreeDependency(name, kind, version, "runtime", false, new List<TreeDependency>())
}

func TreeDependencyText(dependency: TreeDependency): string {
    version := dependency.Version
    return dependency.Kind + ":" + dependency.Name + ":" + (version ?? "")
}

test "dependencies deduplicate case-insensitively, keep the first version and sort by kind then name" {
    dependencies := new List<TreeDependency>()
    dependencies.Add(TreeDependencyOf("Serilog", "nuget", "3.1.1"))
    dependencies.Add(TreeDependencyOf("Microsoft.AspNetCore.App", "framework", null))
    dependencies.Add(TreeDependencyOf("serilog", "nuget", "9.9.9"))
    dependencies.Add(TreeDependencyOf("../Shared/Shared.csproj", "project", null))
    dependencies.Add(TreeDependencyOf("Newtonsoft.Json", "nuget", "13.0.3"))
    dependencies.Add(TreeDependencyOf("microsoft.aspnetcore.app", "framework", null))

    deduplicated := TreeCommandKernels.DeduplicateDependencies(dependencies)

    assert deduplicated.Length == 4
    assert TreeDependencyText(deduplicated[0]) == "framework:Microsoft.AspNetCore.App:"
    assert TreeDependencyText(deduplicated[1]) == "nuget:Newtonsoft.Json:13.0.3"
    assert TreeDependencyText(deduplicated[2]) == "nuget:Serilog:3.1.1"
    assert TreeDependencyText(deduplicated[3]) == "project:../Shared/Shared.csproj:"
}

test "target frameworks deduplicate case-insensitively and keep first-seen order" {
    frameworks := new List<string>()
    frameworks.Add("net10.0")
    frameworks.Add("NET10.0")
    frameworks.Add("net9.0")
    frameworks.Add("net8.0")
    frameworks.Add("NET9.0")

    deduplicated := TreeCommandKernels.DeduplicateTargetFrameworks(frameworks)

    assert deduplicated.Length == 3
    assert deduplicated[0] == "net10.0"
    assert deduplicated[1] == "net9.0"
    assert deduplicated[2] == "net8.0"
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the tree help text names the command, its usage and its failure banner" {
    helpText := TreeCommandKernels.GetHelpText()

    assert helpText.Contains("N# Dependency Tree")
    assert helpText.Contains("Usage: nlc tree [options]")
    assert helpText.Contains("Failed to display tree")
}

test "every tree message is spelled by a kernel, character for character" {
    assert TreeCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/nsharp-missing") == "Project directory not found: /tmp/nsharp-missing"
    assert TreeCommandKernels.GetTreeFailedMessage("bad graph") == "Tree failed: bad graph"
    assert TreeCommandKernels.GetNoProjectFileMessage().Contains("No project.yml or .csproj found")
    assert TreeCommandKernels.GetProjectYmlLimitationMessage().Contains("direct runtime dependencies")
    assert TreeCommandKernels.GetTransitiveResolutionFailedLimitation("restore failed") == "Transitive NuGet dependency resolution through MSBuild failed: restore failed"
    assert TreeCommandKernels.GetDotnetRestoreRetryMessage("restore failed") == "restore failed Run 'dotnet restore' and retry."
    assert TreeCommandKernels.GetDotnetListFailedMessage() == "dotnet list package failed."
}

test "the tree renderer's lines are spelled by kernels, including the box-drawing prefixes" {
    assert TreeCommandKernels.GetProjectHeader("Demo", "net10.0") == "Demo (net10.0)"
    assert TreeCommandKernels.GetNoDependenciesLine() == "  (no dependencies)"
    assert TreeCommandKernels.GetDependencyText("Serilog", "3.1.0", "nuget") == "Serilog@3.1.0 [nuget]"
    assert TreeCommandKernels.GetDependencyText("System.Console", null, "framework") == "System.Console [framework]"
    assert TreeCommandKernels.GetDependencyLine(true, "Serilog@3.1.0 [nuget]") == "└── Serilog@3.1.0 [nuget]"
    assert TreeCommandKernels.GetDependencyLine(false, "Serilog@3.1.0 [nuget]") == "├── Serilog@3.1.0 [nuget]"
    assert TreeCommandKernels.GetTransitiveHeader(2) == "  transitive (2 packages):"
    assert TreeCommandKernels.GetTransitiveDependencyLine("Serilog@3.1.0 [nuget]") == "    Serilog@3.1.0 [nuget]"
    assert TreeCommandKernels.GetLimitationsHeader() == "Limitations:"
    assert TreeCommandKernels.GetLimitationLine("direct only") == "  - direct only"
}

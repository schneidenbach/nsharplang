namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import NSharpLang.Compiler

// THE `nlc tidy` OPTION, IMPORT-SCAN, CLASSIFICATION, MESSAGE AND REMOVAL KERNELS.
//
// These replace FOUR `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `TidyCommandKernels_SummarizesOptions`, `..._ShapesMessages`,
// `..._SelectsAndClassifiesDependencies` and `..._FiltersRemovalLines`.
//
// ONE OF THE FOUR IS SPLIT, AND THE SPLIT IS FORCED. `..._ShapesMessages` ended by driving
// `TidyCommand.Execute(["--help"])` through a console capture. `Console.SetOut` declines on this
// emit path at `emit.call.static-member-unmodeled`, so that row is in
// `tests/native/cli-command-contracts` against the spawned binary.
//
// THE DELETED BODY'S `TidyDependency` RECORD IS NOT CARRIED. It was a private test-local record of
// a name and a status, and every kernel it fed takes the STATUS STRINGS directly — so the statuses
// are written as a plain array here and the intermediate type disappears with its only consumer.

// ── the option summary ────────────────────────────────────────────────────────
test "the tidy option summary reads the project, fix and json flags" {
    summary := TidyCommandKernels.GetOptionSummary(["--fix", "--json", "--project", "samples/demo"])

    assert summary.ProjectOption == "samples/demo"
    assert summary.Fix
    assert summary.Json
    assert !summary.ShowHelp
}

test "tidy option values are taken permissively, so a flag can be consumed as a value" {
    // DELIBERATE AND PINNED: `--project` swallows `--json` as its path AND the flag still sets.
    summary := TidyCommandKernels.GetOptionSummary(["--project", "--json"])

    assert summary.ProjectOption == "--json"
    assert summary.Json
}

test "help is asked for by the bare word anywhere, and by -h after a positional" {
    assert TidyCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert TidyCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
}

test "tidy output mode is 2 for text and 1 for json" {
    assert TidyCommandKernels.GetOutputMode(false) == 2
    assert TidyCommandKernels.GetOutputMode(true) == 1
}

// ── the import-line scanner ───────────────────────────────────────────────────

test "the import scanner reads a namespace through leading space, a comment and a semicolon" {
    assert TidyCommandKernels.GetImportedNamespace("  import  Newtonsoft.Json.Linq // trailing comment") == "Newtonsoft.Json.Linq"
    assert TidyCommandKernels.GetImportedNamespace("\timport System.Text;") == "System.Text"
    // non-ASCII identifier characters are part of the namespace
    assert TidyCommandKernels.GetImportedNamespace("import Résumé.Json") == "Résumé.Json"
}

test "the import scanner requires a SPACE after the keyword and a nonempty namespace" {
    // A TAB after `import` is not the separator the scanner accepts, so this is not an import.
    assert TidyCommandKernels.GetImportedNamespace("import\tSystem.Text") == null
    // the word inside a string literal is not an import either
    assert TidyCommandKernels.GetImportedNamespace("print \"import System.Text\"") == null
    assert TidyCommandKernels.GetImportedNamespace("import ;") == null
}

// ── the dependency classifier ─────────────────────────────────────────────────

func TidyImports(): HashSet<string> {
    imports := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    imports.Add("Newtonsoft.Json.Linq")
    imports.Add("Microsoft.Extensions.Logging")
    return imports
}

test "a dependency is used when an import matches it or a prefix of it, and unknown when single-segment" {
    // Rank 1 = possibly-unused, 2 = used, 3 = unknown.
    references := [
        new Reference { Nuget: "Newtonsoft.Json", Version: "13.0.3" },
        new Reference { Nuget: "Serilog.Sinks.Console", Version: "5.0.1" },
        new Reference { Nuget: "Polly", Version: "8.0.0" },
        new Reference { Nuget: "Microsoft.Extensions.Logging", Version: "10.0.0" },
        new Reference { Nuget: "Custom.Package", Version: "1.0.0" }
    ]

    statusRanks := TidyCommandKernels.ClassifyDependencyStatusRanks(references, TidyImports())

    assert statusRanks.Length == 5
    // `Newtonsoft.Json` is covered by the import `Newtonsoft.Json.Linq`
    assert statusRanks[0] == 2
    // nothing imports `Serilog.Sinks.Console` or its first two segments
    assert statusRanks[1] == 1
    // `Polly` is one segment, so no namespace can be derived from it — unknown, not unused
    assert statusRanks[2] == 3
    // an exact import match
    assert statusRanks[3] == 2
    assert statusRanks[4] == 1
}

test "the classifier compares namespaces case-insensitively over non-ASCII names" {
    nonAsciiImports := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    nonAsciiImports.Add("Résumé.Json")

    statusRanks := TidyCommandKernels.ClassifyDependencyStatusRanks(
        [new Reference { Nuget: "Résumé.Json", Version: "1.0.0" }],
        nonAsciiImports
    )

    assert statusRanks.Length == 1
    assert statusRanks[0] == 2
}

test "the possibly-unused selector answers positions, in order, and only for that status" {
    statuses := ["used", "possibly-unused", "unknown", "possibly-unused", "custom"]

    selectedIndices := TidyCommandKernels.SelectPossiblyUnusedDependencyIndices(statuses)

    assert selectedIndices.Length == 2
    assert selectedIndices[0] == 1
    assert selectedIndices[1] == 3
}

test "the selected positions index the CALLER's own array, which is how tidy names what it removes" {
    // The kernel answers positions, not names, and `TidyCommand` maps them back through the
    // dependency list it built. That mapping is the whole contract, so it is walked here: the
    // names below are the deleted body's five fixtures, in its order.
    names := ["Newtonsoft.Json", "Serilog", "Polly", "Humanizer", "Custom.Package"]
    statuses := ["used", "possibly-unused", "unknown", "possibly-unused", "custom"]

    selectedIndices := TidyCommandKernels.SelectPossiblyUnusedDependencyIndices(statuses)

    assert selectedIndices.Length == 2
    assert names[selectedIndices[0]] == "Serilog"
    assert names[selectedIndices[1]] == "Humanizer"
}

test "the status summary counts possibly-unused and unknown, and ignores every other status" {
    summary := TidyCommandKernels.SummarizeDependencyStatuses(["used", "possibly-unused", "unknown", "possibly-unused", "custom"])

    assert summary.PossiblyUnusedCount == 2
    assert summary.UnknownCount == 1
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the tidy help text names the command, its usage and its JSON schema version" {
    helpText := TidyCommandKernels.GetHelpText()

    assert helpText.Contains("N# Tidy")
    assert helpText.Contains("Usage: nlc tidy [options]")
    assert helpText.Contains("schemaVersion 1")
}

test "the missing-project sentence differs between the JSON and the text route" {
    assert TidyCommandKernels.GetMissingProjectFileJsonMessage() == "No project.yml found in the specified directory."
    assert TidyCommandKernels.GetMissingProjectFileTextMessage() == "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project."
}

test "the tidy result sentences singularise on one and pluralise on more" {
    assert TidyCommandKernels.GetParseFailedMessage("bad yaml") == "Failed to parse project.yml: bad yaml"
    assert TidyCommandKernels.GetNothingToRemoveMessage() == "Nothing to remove."
    assert TidyCommandKernels.GetRemovedDependenciesMessage(1) == "Removed 1 possibly-unused dependency."
    assert TidyCommandKernels.GetRemovedDependenciesMessage(2) == "Removed 2 possibly-unused dependencies."
    assert TidyCommandKernels.GetPossiblyUnusedFoundMessage(1) == "1 possibly-unused dependency found. Run 'nlc tidy --fix' to remove them."
    assert TidyCommandKernels.GetPossiblyUnusedFoundMessage(3) == "3 possibly-unused dependencies found. Run 'nlc tidy --fix' to remove them."
    assert TidyCommandKernels.GetNoNuGetDependenciesMessage("/tmp/demo") == "No NuGet dependencies found in /tmp/demo"
    assert TidyCommandKernels.GetAllDependenciesAccountedForMessage(2) == "All dependencies accounted for (2 could not be determined)."
    assert TidyCommandKernels.GetAllDependenciesInUseMessage() == "All dependencies appear to be in use."
}

test "the tidy table pads its own columns rather than trusting the caller's padding" {
    // The header is given ALREADY-PADDED labels and still lays out its own fixed columns.
    assert TidyCommandKernels.GetTableHeader("Package     ", "Status         ") == "  Package       Status           Reason"
    assert TidyCommandKernels.GetTableSeparator("-------", "------") == "  -------  ------  ------"
    assert TidyCommandKernels.GetTableRow("Newtonsoft.Json", "possibly-unused", "No import found.") == "  Newtonsoft.Json  possibly-unused  No import found."
}

test "each status carries the reason sentence the user reads beside it" {
    assert TidyCommandKernels.GetUnknownReasonMessage() == "Cannot determine namespace for single-segment package name; manual review required."
    assert TidyCommandKernels.GetUsedReasonMessage("Newtonsoft.Json") == "Import statement references namespace matching 'Newtonsoft.Json'."
    assert TidyCommandKernels.GetPossiblyUnusedReasonMessage("Serilog", "Serilog.Sinks") == "No import statement found referencing 'Serilog' or 'Serilog.Sinks'."
}

// ── the removal filter ────────────────────────────────────────────────────────

test "the removal filter drops a dependency line whose package part IS a doomed name" {
    filteredLines := TidyCommandKernels.FilterRemovalLines(
        [
            "dependencies:",
            "  - Serilog@3.1.1",
            "  - Serilog.Sinks.Console@5.0.1",
            "  - nuget: Newtonsoft.Json",
            "  - NUGET: unused.package",
            "  - framework: Microsoft.AspNetCore.App",
            "  - project: ../Shared/Shared.csproj",
            "  - Other.Package",
            "  - SerilogExtra",
            "name: Demo"
        ],
        ["Serilog", "Newtonsoft.Json", "Unused.Package"]
    )

    // Non-list lines and lines that are not `- `-prefixed are always kept. The `nuget:` marker is
    // honoured anywhere on the line and case-insensitively, so `NUGET: unused.package` matches the
    // doomed `Unused.Package`. `framework:` and `project:` lines never match a package name.
    //
    // AND THE MATCH IS THE WHOLE NAME, NOT A PREFIX OF IT: the doomed `Serilog` takes
    // `  - Serilog@3.1.1` — `@` ends a package name — and leaves BOTH `Serilog.Sinks.Console`
    // and `SerilogExtra`, which are different packages that merely begin with those seven letters.
    assert filteredLines.Length == 7
    assert filteredLines[0] == "dependencies:"
    assert filteredLines[1] == "  - Serilog.Sinks.Console@5.0.1"
    assert filteredLines[2] == "  - framework: Microsoft.AspNetCore.App"
    assert filteredLines[3] == "  - project: ../Shared/Shared.csproj"
    assert filteredLines[4] == "  - Other.Package"
    assert filteredLines[5] == "  - SerilogExtra"
    assert filteredLines[6] == "name: Demo"
}

test "a doomed name that is a BARE PREFIX of another package leaves that package alone" {
    // THIS IS THE MECHANISM, ISOLATED — AND IT WAS A DATA-LOSS DEFECT UNTIL THE RULE BELOW.
    // `nlc tidy --fix` REWRITES the user's `project.yml` from this answer, and
    // `RemovalLineStartsWithPackage` used to compare `packageName.Length` characters and check
    // NOTHING after them, so every package merely BEGINNING with a doomed name went with it. A
    // project carrying `Serilog` (unused) alongside `SerilogExtra`, `Serilogic.Core` and
    // `Serilog.Sinks.Console` lost all four lines while the command reported removing one.
    //
    // THE RULE NOW: the doomed name must fit, compare equal, and END where it ends on the line —
    // the next character may not be one a package id continues with (letter, digit, `.`, `-`,
    // `_`, `+`). Only the line that IS `Serilog` goes.
    collateral := TidyCommandKernels.FilterRemovalLines(
        ["  - Serilog", "  - SerilogExtra", "  - Serilogic.Core", "  - Serilog.Sinks.Console@5.0.1", "  - Serilog_Extra", "  - Serilog-Extra", "  - Seri"],
        ["Serilog"]
    )

    assert collateral.Length == 6
    assert collateral[0] == "  - SerilogExtra"
    assert collateral[1] == "  - Serilogic.Core"
    assert collateral[2] == "  - Serilog.Sinks.Console@5.0.1"
    assert collateral[3] == "  - Serilog_Extra"
    assert collateral[4] == "  - Serilog-Extra"
    assert collateral[5] == "  - Seri"
}

test "the whole-name rule does not stop a doomed package being removed in any spelling" {
    // THE OTHER DIRECTION OF THE SAME CHANGE, so the fix cannot have been a blanket refusal to
    // remove anything. Every terminator a `project.yml` package name can actually END with is
    // asked for: end of line, the `@` before a version, the space before a YAML comment, and the
    // `nuget:` mapping key — case-insensitively, and for a doomed name that itself carries dots.
    removed := TidyCommandKernels.FilterRemovalLines(
        [
            "  - Serilog.Sinks",
            "  - Serilog.Sinks@1.2.3",
            "  - Serilog.Sinks # legacy sink, drop it",
            "  - nuget: serilog.sinks",
            "  - NUGET: Serilog.Sinks@1.2.3",
            "  - Keep.Me"
        ],
        ["Serilog.Sinks"]
    )

    assert removed.Length == 1
    assert removed[0] == "  - Keep.Me"
}

test "filtering an already-filtered file changes nothing — tidy twice is tidy once" {
    // IDEMPOTENCE, WHICH IS WHAT MAKES `nlc tidy --fix` SAFE TO RERUN. The second pass sees the
    // survivors of the first and must keep every one of them, including the three that survive
    // only because the doomed name is a bare prefix of them.
    original := [
        "dependencies:",
        "  - Serilog@3.1.1",
        "  - SerilogExtra@1.0.0",
        "  - Serilog.Sinks.Console@5.0.1",
        "  - Newtonsoft.Json@13.0.3"
    ]

    once := TidyCommandKernels.FilterRemovalLines(original, ["Serilog"])
    twice := TidyCommandKernels.FilterRemovalLines(once, ["Serilog"])

    assert once.Length == 4
    assert twice.Length == 4
    index := 0
    while index < once.Length {
        assert twice[index] == once[index]
        index = index + 1
    }
}

test "an empty doomed name matches no line at all" {
    // A doomed name of length zero would once have matched at every package start and emptied the
    // list. It cannot reach the filter through `TidyCommand` — a classified dependency always has
    // a name — but the kernel is public and answers for itself.
    kept := TidyCommandKernels.FilterRemovalLines(
        ["  - Serilog", "  - Newtonsoft.Json", "name: Demo"],
        [""]
    )

    assert kept.Length == 3
    assert kept[0] == "  - Serilog"
    assert kept[1] == "  - Newtonsoft.Json"
    assert kept[2] == "name: Demo"
}

test "the removal filter is NOT scoped to the dependencies section — measured, not endorsed" {
    // A SECOND, SEPARATE FINDING, PINNED AS MEASURED. `TidyCommand.RemoveDependencies` hands the
    // filter EVERY line of `project.yml`, and the filter's only structural test is `- ` after the
    // indent. So a `testDependencies:` entry naming exactly a doomed package is removed as well,
    // even though `TidyCommand` classified only `config.Dependencies` and the report never named
    // that line. The whole-name rule above bounds the blast radius to an EXACT name match; the
    // section scoping is a distinct decision and is not made here.
    filteredLines := TidyCommandKernels.FilterRemovalLines(
        [
            "dependencies:",
            "  - Serilog.Sinks@1.0.0",
            "testDependencies:",
            "  - Serilog.Sinks@1.0.0",
            "  - Serilog.SinksExtra@2.0.0"
        ],
        ["Serilog.Sinks"]
    )

    assert filteredLines.Length == 3
    assert filteredLines[0] == "dependencies:"
    assert filteredLines[1] == "testDependencies:"
    assert filteredLines[2] == "  - Serilog.SinksExtra@2.0.0"
}

test "a doomed name LONGER than the line's package still does not match" {
    // The other side of the same rule, and the reason it is a prefix test rather than a substring
    // one: the comparison is anchored at the package start and needs the whole name to fit.
    kept := TidyCommandKernels.FilterRemovalLines(
        ["  - Seri", "  - Extra.Serilog"],
        ["Serilog"]
    )

    assert kept.Length == 2
    assert kept[0] == "  - Seri"
    assert kept[1] == "  - Extra.Serilog"
}

test "the removal filter matches a non-ASCII package name" {
    filteredLines := TidyCommandKernels.FilterRemovalLines(
        ["  - Résumé.Package", "  - Keep.Package"],
        ["Résumé.Package"]
    )

    assert filteredLines.Length == 1
    assert filteredLines[0] == "  - Keep.Package"
}

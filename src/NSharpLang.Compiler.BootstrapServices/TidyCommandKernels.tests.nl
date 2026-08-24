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
        nonAsciiImports)

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

test "the removal filter drops a dependency line whose package part starts with a doomed name" {
    filteredLines := TidyCommandKernels.FilterRemovalLines(
        [
            "dependencies:",
            "  - Serilog.Sinks.Console@5.0.1",
            "  - nuget: Newtonsoft.Json",
            "  - NUGET: unused.package",
            "  - framework: Microsoft.AspNetCore.App",
            "  - project: ../Shared/Shared.csproj",
            "  - Other.Package",
            "  - SerilogExtra",
            "name: Demo"
        ],
        ["Serilog", "Newtonsoft.Json", "Unused.Package"])

    // Non-list lines and lines that are not `- `-prefixed are always kept. The `nuget:` marker is
    // honoured anywhere on the line and case-insensitively, so `NUGET: unused.package` matches the
    // doomed `Unused.Package`. `framework:` and `project:` lines never match a package name.
    assert filteredLines.Length == 5
    assert filteredLines[0] == "dependencies:"
    assert filteredLines[1] == "  - framework: Microsoft.AspNetCore.App"
    assert filteredLines[2] == "  - project: ../Shared/Shared.csproj"
    assert filteredLines[3] == "  - Other.Package"
    assert filteredLines[4] == "name: Demo"
}

test "the removal match is a BARE PREFIX, so removing Serilog also removes SerilogExtra" {
    // THIS IS THE MECHANISM, ISOLATED. The deleted body fed `  - SerilogExtra` into a nine-element
    // array comparison and its disappearance was invisible among the other eight rows. It is
    // pinned here on its own, because `nlc tidy --fix` REWRITES the user's `project.yml` from this
    // answer: `RemovalLineStartsWithPackage` compares `packageName.Length` characters and checks
    // NOTHING after them, so a package that merely begins with a doomed name is deleted with it.
    // `TidyCommand.RemoveDependencies` passes exactly the possibly-unused names, so a user with
    // both `Serilog` (unused) and `SerilogExtra` (used) loses the second line too.
    collateral := TidyCommandKernels.FilterRemovalLines(
        ["  - Serilog", "  - SerilogExtra", "  - Serilogic.Core", "  - Seri"],
        ["Serilog"])

    assert collateral.Length == 1
    assert collateral[0] == "  - Seri"
}

test "a doomed name LONGER than the line's package still does not match" {
    // The other side of the same rule, and the reason it is a prefix test rather than a substring
    // one: the comparison is anchored at the package start and needs the whole name to fit.
    kept := TidyCommandKernels.FilterRemovalLines(
        ["  - Seri", "  - Extra.Serilog"],
        ["Serilog"])

    assert kept.Length == 2
    assert kept[0] == "  - Seri"
    assert kept[1] == "  - Extra.Serilog"
}

test "the removal filter matches a non-ASCII package name" {
    filteredLines := TidyCommandKernels.FilterRemovalLines(
        ["  - Résumé.Package", "  - Keep.Package"],
        ["Résumé.Package"])

    assert filteredLines.Length == 1
    assert filteredLines[0] == "  - Keep.Package"
}

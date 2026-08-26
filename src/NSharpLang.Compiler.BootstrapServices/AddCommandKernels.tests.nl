namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler

// THE `nlc add` ARGUMENT, PACKAGE-SPEC, DEPENDENCY-PROBE AND MESSAGE KERNELS.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `AddCommandKernels_SummarizesArguments` (119 declaration lines, 40 `Assert.` rows). It is pure,
// so the whole of it is here.
//
// THE DELETED BODY'S SHARPEST ROW IS KEPT AND NAMED: `--version --path ../MyLibrary` binds
// `--path` as the VERSION and STILL binds `../MyLibrary` as the path AND as the package operand.
// It called that "permissive" and asserted the three values; the mechanism — an option value is
// taken literally, and the operand scan skips an option TOGETHER WITH the word after it — is now
// stated, with the control that the same skip is what keeps a lone `--version 13.0.3` from
// reporting an operand.

// ── the argument summary ──────────────────────────────────────────────────────

test "the add argument summary reads both option values and all three flags" {
    summary := AddCommandKernels.GetArgumentSummary(["--version", "13.0.3", "--framework", "--prerelease", "Newtonsoft.Json"])

    assert summary.VersionOption == "13.0.3"
    assert summary.PathOption == null
    assert summary.PackageOperand == "Newtonsoft.Json"
    assert summary.Framework
    assert summary.Prerelease
    assert !summary.ShowHelp
}

test "the operand is found after an option and its value are skipped as a pair" {
    assert AddCommandKernels.GetArgumentSummary(["--version", "13.0.3", "--framework", "Newtonsoft.Json"]).PackageOperand == "Newtonsoft.Json"
    assert AddCommandKernels.GetArgumentSummary(["--prerelease", "Serilog@3.1.1"]).PackageOperand == "Serilog@3.1.1"
    // and with nothing left after the pair there is no operand at all
    assert AddCommandKernels.GetArgumentSummary(["--version", "13.0.3"]).PackageOperand == null
}

test "--path is read as an option and its value doubles as the operand" {
    pathSummary := AddCommandKernels.GetArgumentSummary(["--path", "../MyLibrary"])

    assert pathSummary.PathOption == "../MyLibrary"
    // the operand scan skips `--path` WITH its value, so nothing is left to be the operand
    assert pathSummary.PackageOperand == null
}

test "an option value is taken literally, so --version --path swallows the next flag" {
    // THE PERMISSIVE RULE, STATED. `--version` consumes `--path` as its value; the operand scan
    // then skips the `--version --path` PAIR, meets `../MyLibrary` as a bare word, and takes it —
    // while the FIRST pass has already recorded `--path ../MyLibrary` as the path option.
    permissiveValue := AddCommandKernels.GetArgumentSummary(["--version", "--path", "../MyLibrary"])

    assert permissiveValue.VersionOption == "--path"
    assert permissiveValue.PathOption == "../MyLibrary"
    assert permissiveValue.PackageOperand == "../MyLibrary"
}

test "each option takes its FIRST occurrence, not its last" {
    // A CONTROL THE DELETED BODY DID NOT HAVE for either option.
    summary := AddCommandKernels.GetArgumentSummary(["--version", "1.0.0", "--version", "2.0.0", "Serilog"])

    assert summary.VersionOption == "1.0.0"
    assert summary.PackageOperand == "Serilog"
}

test "the bare word help asks for help, and -h and --help do too" {
    assert AddCommandKernels.GetArgumentSummary(["help"]).ShowHelp
    assert AddCommandKernels.GetArgumentSummary(["-h"]).ShowHelp
    assert AddCommandKernels.GetArgumentSummary(["--help"]).ShowHelp
    // A CONTROL THE DELETED BODY DID NOT HAVE: `help` at index 0 only
    assert !AddCommandKernels.GetArgumentSummary(["Serilog", "help"]).ShowHelp
}

test "every argument kind has exactly one code, and an unknown argument is zero" {
    assert AddCommandKernels.ArgumentSummaryKind("--version") == 1
    assert AddCommandKernels.ArgumentSummaryKind("--path") == 2
    assert AddCommandKernels.ArgumentSummaryKind("--framework") == 3
    assert AddCommandKernels.ArgumentSummaryKind("--prerelease") == 4
    assert AddCommandKernels.ArgumentSummaryKind("--help") == 5
    assert AddCommandKernels.ArgumentSummaryKind("-h") == 5
    assert AddCommandKernels.ArgumentSummaryKind("Serilog") == 0
    assert AddCommandKernels.ArgumentSummaryKind("--unknown") == 0
}

// ── the package spec ──────────────────────────────────────────────────────────

test "an inline @version wins over the explicit --version value" {
    inlineSpec := AddCommandKernels.GetPackageSpec("Serilog@3.1.0", "ignored")

    assert inlineSpec.PackageName == "Serilog"
    assert inlineSpec.Version == "3.1.0"
}

test "without an inline separator the explicit version is used, and null stays null" {
    explicitSpec := AddCommandKernels.GetPackageSpec("Serilog", "3.1.0")
    assert explicitSpec.PackageName == "Serilog"
    assert explicitSpec.Version == "3.1.0"

    unversionedSpec := AddCommandKernels.GetPackageSpec("Serilog", null)
    assert unversionedSpec.PackageName == "Serilog"
    assert unversionedSpec.Version == null
}

test "a LEADING at-sign is not a separator, so a scoped-looking name survives whole" {
    leadingAtSpec := AddCommandKernels.GetPackageSpec("@scope@1.0", "2.0.0")

    assert leadingAtSpec.PackageName == "@scope@1.0"
    assert leadingAtSpec.Version == "2.0.0"
}

test "the separator is the FIRST at-sign past position zero, and a trailing one yields an empty version" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. `Serilog@` splits, and the version is the empty
    // string rather than null — a caller that treats "" and null alike would not notice.
    assert AddCommandKernels.InlineVersionSeparatorIndex("Serilog@3.1.0") == 7
    assert AddCommandKernels.InlineVersionSeparatorIndex("@scope@1.0") == -1
    assert AddCommandKernels.InlineVersionSeparatorIndex("Serilog") == -1

    trailing := AddCommandKernels.GetPackageSpec("Serilog@", null)
    assert trailing.PackageName == "Serilog"
    assert trailing.Version == ""
}

// ── the dependency-section insert point ───────────────────────────────────────

test "the insert index is the first line at column zero after the dependencies key" {
    dependencyLines := [
        "name: Demo",
        "dependencies:",
        "  - Newtonsoft.Json@13.0.3",
        "    version: ignored",
        "targetFramework: net10.0"
    ]

    assert AddCommandKernels.GetDependencyInsertIndex(dependencyLines) == 4
}

test "no dependencies section answers minus one, and a trailing section answers past the end" {
    assert AddCommandKernels.GetDependencyInsertIndex(["name: Demo", "targetFramework: net10.0"]) == -1
    // A CONTROL THE DELETED BODY DID NOT HAVE: when the section runs to the end of the file the
    // insert point is the line COUNT, which is what makes the append land last.
    assert AddCommandKernels.GetDependencyInsertIndex(["dependencies:", "  - nuget: Serilog"]) == 2
    // AND A BLANK LINE STOPS THE BLOCK, which a reader would not guess from the indentation rule
    assert AddCommandKernels.GetDependencyInsertIndex(["dependencies:", "  - nuget: Serilog", "", "  - nuget: Late"]) == 2
}

test "the section line and the block terminator are decided on indentation" {
    assert AddCommandKernels.IsDependencySectionLine("dependencies:")
    assert AddCommandKernels.IsDependencySectionLine("   dependencies:")
    assert !AddCommandKernels.IsDependencySectionLine("devDependencies:")
    assert AddCommandKernels.DependencyBlockStopsAtLine("targetFramework: net10.0")
    assert AddCommandKernels.DependencyBlockStopsAtLine("")
    assert !AddCommandKernels.DependencyBlockStopsAtLine("  - nuget: Serilog")
    assert !AddCommandKernels.DependencyBlockStopsAtLine("\t- nuget: Serilog")
}

// ── the existing-dependency probes ────────────────────────────────────────────

test "a package probe matches a nuget OR a framework entry, case-insensitively" {
    dependencies := [
        new Reference { Nuget: "Newtonsoft.Json" },
        new Reference { Framework: "Microsoft.AspNetCore.App" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference()
    ]

    assert AddCommandKernels.PackageOrFrameworkDependencyExists(dependencies, "newtonsoft.json")
    assert AddCommandKernels.PackageOrFrameworkDependencyExists(dependencies, "microsoft.aspnetcore.app")
    assert !AddCommandKernels.PackageOrFrameworkDependencyExists(dependencies, "Serilog")
    // THE EMPTY `Reference` IS THE CONTROL THE DELETED BODY CARRIED AND NEVER NAMED: an entry with
    // every field null must be walked past rather than matched or thrown on.
    assert !AddCommandKernels.PackageOrFrameworkDependencyExists(dependencies, "")
}

test "a project probe matches only the project field, and is case-insensitive over the whole path" {
    dependencies := [
        new Reference { Nuget: "Newtonsoft.Json" },
        new Reference { Framework: "Microsoft.AspNetCore.App" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference()
    ]

    assert AddCommandKernels.ProjectDependencyExists(dependencies, "../shared/PROJECT.yml")
    assert !AddCommandKernels.ProjectDependencyExists(dependencies, "../Other/project.yml")
    // A CONTROL THE DELETED BODY DID NOT HAVE: the two probes do not see each other's fields
    assert !AddCommandKernels.ProjectDependencyExists(dependencies, "Newtonsoft.Json")
    assert !AddCommandKernels.PackageOrFrameworkDependencyExists(dependencies, "../Shared/project.yml")
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the add usage message carries BOTH spellings on two lines" {
    assert AddCommandKernels.GetUsageMessage() == "Usage: nlc add <package> [--version <ver>]\n       nlc add <package>@<version>"
}

test "the add help text names the command, every option and the failure exit code" {
    helpText := AddCommandKernels.GetHelpText()

    assert helpText.StartsWith("N# Add Dependency")
    assert helpText.Contains("--path <path>")
    assert helpText.Contains("--prerelease")
    assert helpText.Contains("--framework")
    assert helpText.Contains("Failed to add dependency")
}

test "the add command's sentences are exactly these" {
    assert AddCommandKernels.GetMissingProjectFileMessage() == "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project."
    assert AddCommandKernels.GetResolvingLatestVersionMessage("Serilog") == "Resolving latest version for Serilog..."
    assert AddCommandKernels.GetPackageNotFoundMessage("Missing.Package") == "Could not find package 'Missing.Package' on NuGet. Check the package name and try again."
    assert AddCommandKernels.GetDuplicatePackageMessage("Serilog") == "'Serilog' is already in dependencies. Use 'nlc update' to change the version."
    assert AddCommandKernels.GetDuplicateProjectReferenceMessage("../Shared/project.yml") == "Project reference '../Shared/project.yml' is already in dependencies."
    assert AddCommandKernels.GetFrameworkAddedMessage("Microsoft.AspNetCore.App") == "Added framework reference 'Microsoft.AspNetCore.App' to project.yml"
    assert AddCommandKernels.GetPackageAddedMessage("Serilog", "3.1.0") == "Added Serilog@3.1.0 to project.yml"
    assert AddCommandKernels.GetProjectReferenceAddedMessage("../Shared/project.yml") == "Added project reference '../Shared/project.yml' to project.yml"
}

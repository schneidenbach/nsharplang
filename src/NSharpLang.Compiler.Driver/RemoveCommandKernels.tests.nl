namespace NSharpLang.Cli.Commands

// THE `nlc remove` ARGUMENT, DEPENDENCY-LINE AND MESSAGE KERNELS.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `RemoveCommandKernels_SummarizesArguments` (63 declaration lines, 23 `Assert.` rows). It is
// pure, so the whole of it is here.
//
// THE DELETED BODY ASKED THE THREE-VALUED LINE CLASSIFIER FOR FIVE LINES AND NEVER SHOWED THAT ITS
// TWO REMOVAL ARMS DIFFER. They do, and the difference is what decides whether `nlc remove` takes
// ONE line out of the user's project.yml or a whole indented block: a shorthand entry
// (`- Serilog`, `- Serilog@3.1.1`) is one line, and a mapping entry (`- nuget: Serilog`) drags its
// continuation lines with it. The continuation rule is pinned beside it, so the pair states the
// whole edit.

// ── the argument summary ──────────────────────────────────────────────────────
test "the remove argument summary reads the package operand and the help flag" {
    summary := RemoveCommandKernels.GetArgumentSummary(["--dry-run", "Serilog", "-h"])

    assert summary.PackageOperand == "Serilog"
    assert summary.ShowHelp
}

test "the operand is the first argument that does not begin with a dash" {
    assert RemoveCommandKernels.GetArgumentSummary(["Newtonsoft.Json"]).PackageOperand == "Newtonsoft.Json"
    assert RemoveCommandKernels.GetArgumentSummary(["--dry-run", "Serilog"]).PackageOperand == "Serilog"
    assert RemoveCommandKernels.GetArgumentSummary(["--dry-run"]).PackageOperand == null
}

test "the bare word help both asks for help AND becomes the package operand" {
    summary := RemoveCommandKernels.GetArgumentSummary(["help"])

    assert summary.ShowHelp
    assert summary.PackageOperand == "help"
}

test "help is only the help WORD at index 0, and the FIRST bare word wins" {
    // TWO CONTROLS THE DELETED BODY DID NOT HAVE.
    later := RemoveCommandKernels.GetArgumentSummary(["--dry-run", "help"])
    assert !later.ShowHelp
    assert later.PackageOperand == "help"

    twoOperands := RemoveCommandKernels.GetArgumentSummary(["Serilog", "Newtonsoft.Json"])
    assert twoOperands.PackageOperand == "Serilog"
}

// ── the dependency-line classifier ────────────────────────────────────────────

test "a shorthand dependency line is removed as ONE line, with or without an inline version" {
    assert RemoveCommandKernels.GetDependencyLineAction("- Newtonsoft.Json@13.0.3", "Newtonsoft.Json") == RemoveDependencyLineAction.RemoveSingleLine
    assert RemoveCommandKernels.GetDependencyLineAction("  - serilog", "Serilog") == RemoveDependencyLineAction.RemoveSingleLine
}

test "a mapping dependency line is removed as a BLOCK, for nuget and for framework alike" {
    assert RemoveCommandKernels.GetDependencyLineAction("- nuget: YamlDotNet", "YamlDotNet") == RemoveDependencyLineAction.RemoveMappingBlock
    assert RemoveCommandKernels.GetDependencyLineAction("- framework: Microsoft.AspNetCore.App", "Microsoft.AspNetCore.App") == RemoveDependencyLineAction.RemoveMappingBlock
    assert RemoveCommandKernels.GetDependencyLineAction(" - nuget: YamlDotNet", "YamlDotNet") == RemoveDependencyLineAction.RemoveMappingBlock
}

test "the two removal arms are DIFFERENT answers, which is what decides how much text is cut" {
    // THE CLAIM THE DELETED BODY COULD NOT MAKE. It asserted five expected values and never put
    // two of them side by side, so a kernel that answered `RemoveMappingBlock` for everything
    // would have failed only the two shorthand rows without ever saying why that matters.
    shorthand := RemoveCommandKernels.GetDependencyLineAction("  - Serilog", "Serilog")
    mapping := RemoveCommandKernels.GetDependencyLineAction("  - nuget: Serilog", "Serilog")

    assert shorthand != mapping
    assert shorthand == RemoveDependencyLineAction.RemoveSingleLine
    assert mapping == RemoveDependencyLineAction.RemoveMappingBlock
}

test "an unrelated line is kept, and so is a line naming a DIFFERENT package" {
    assert RemoveCommandKernels.GetDependencyLineAction("- package: Other", "Serilog") == RemoveDependencyLineAction.Keep
    // A CONTROL THE DELETED BODY DID NOT HAVE: a well-formed mapping for another package must be
    // kept, or `nlc remove` would delete the wrong dependency.
    assert RemoveCommandKernels.GetDependencyLineAction("- nuget: Newtonsoft.Json", "Serilog") == RemoveDependencyLineAction.Keep
    assert RemoveCommandKernels.GetDependencyLineAction("  - Newtonsoft.Json", "Serilog") == RemoveDependencyLineAction.Keep
    assert RemoveCommandKernels.GetDependencyLineAction("name: Demo", "Serilog") == RemoveDependencyLineAction.Keep
    assert RemoveCommandKernels.GetDependencyLineAction("", "Serilog") == RemoveDependencyLineAction.Keep
}

// ── the mapping-block continuation rule ───────────────────────────────────────

test "an indented continuation line belongs to the block being removed" {
    assert !RemoveCommandKernels.ShouldStopDependencyContinuationLine("    version: 1.0.0")
    assert !RemoveCommandKernels.ShouldStopDependencyContinuationLine("  version: 1.0.0")
}

test "the next list item and any top-level key both STOP the block" {
    assert RemoveCommandKernels.ShouldStopDependencyContinuationLine("- nuget: Other")
    assert RemoveCommandKernels.ShouldStopDependencyContinuationLine("dependencies:")
    // A CONTROL THE DELETED BODY DID NOT HAVE: an INDENTED next item also stops it, which is what
    // keeps a sibling dependency from being swallowed by the block above it.
    assert RemoveCommandKernels.ShouldStopDependencyContinuationLine("  - nuget: Other")
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the remove help text names the command, its usage and the failure exit code" {
    helpText := RemoveCommandKernels.GetHelpText()

    assert helpText.StartsWith("N# Remove Dependency")
    assert helpText.Contains("Failed to remove dependency")
    assert helpText.Contains("Usage: nlc remove <package>")
}

test "the remove command's sentences are exactly these" {
    assert RemoveCommandKernels.GetUsageMessage() == "Usage: nlc remove <package>"
    assert RemoveCommandKernels.GetMissingProjectFileMessage() == "No project.yml found."
    assert RemoveCommandKernels.GetPackageNotFoundMessage("Serilog") == "Package 'Serilog' not found in dependencies."
    assert RemoveCommandKernels.GetRemovedMessage("Serilog") == "Removed Serilog from project.yml"
}

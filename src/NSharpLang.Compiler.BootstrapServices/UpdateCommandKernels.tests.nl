namespace NSharpLang.Cli.Commands

// THE `nlc update` ARGUMENT AND MESSAGE KERNELS.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `UpdateCommandKernels_SummarizesArguments` (39 declaration lines, 22 `Assert.` rows). It is
// pure, so the whole of it is here.
//
// THE DELETED BODY PINNED `["help"].TargetPackage == "help"` AND SAID NOTHING ABOUT WHY. It is
// deliberate: the operand scan takes the FIRST argument that does not begin with `-`, and the
// help word is not excluded from it. That is now stated, with the sibling control (`--dry-run` is
// skipped as an operand because it DOES begin with `-`) beside it.

// ── the argument summary ──────────────────────────────────────────────────────

test "the update argument summary reads the package operand, the dry-run flag and the help flag" {
    summary := UpdateCommandKernels.GetArgumentSummary(["--dry-run", "-v", "Newtonsoft.Json", "-h"])

    assert summary.TargetPackage == "Newtonsoft.Json"
    assert summary.DryRun
    assert summary.ShowHelp
}

test "the package operand is the first argument that does not begin with a dash" {
    assert UpdateCommandKernels.GetArgumentSummary(["--dry-run", "Newtonsoft.Json"]).TargetPackage == "Newtonsoft.Json"
    assert UpdateCommandKernels.GetArgumentSummary(["--dry-run", "-v", "Serilog"]).TargetPackage == "Serilog"
    assert UpdateCommandKernels.GetArgumentSummary(["--dry-run"]).TargetPackage == null
}

test "the operand takes the FIRST bare word, and a later one is ignored" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It never passed two operands, so a kernel that let
    // the LAST one win would have passed it.
    summary := UpdateCommandKernels.GetArgumentSummary(["Serilog", "Newtonsoft.Json"])

    assert summary.TargetPackage == "Serilog"
    assert !summary.DryRun
    assert !summary.ShowHelp
}

test "the bare word help both asks for help AND becomes the package operand" {
    // PINNED DELIBERATELY. `help` does not start with `-`, and the operand scan does not exclude
    // it, so `nlc update help` reports a target package named `help`. The help screen wins in the
    // command, but the kernel's answer says both.
    summary := UpdateCommandKernels.GetArgumentSummary(["help"])

    assert summary.ShowHelp
    assert summary.TargetPackage == "help"
}

test "help is only the help WORD at index 0; later it is just an operand" {
    // A CONTROL THE DELETED BODY DID NOT HAVE.
    summary := UpdateCommandKernels.GetArgumentSummary(["--dry-run", "help"])

    assert !summary.ShowHelp
    assert summary.TargetPackage == "help"
    assert summary.DryRun
}

test "an EMPTY argument is accepted as the operand, because it has no leading dash to test" {
    // The kernel special-cases a zero-length argument before it indexes `arg[0]`, which is what
    // keeps `nlc update ""` from throwing. Nothing in the deleted body reached this arm.
    summary := UpdateCommandKernels.GetArgumentSummary(["", "Serilog"])

    assert summary.TargetPackage == ""
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the update help text names the command, its usage and the failure exit code" {
    helpText := UpdateCommandKernels.GetHelpText()

    assert helpText.StartsWith("N# Update Dependencies")
    assert helpText.Contains("Usage: nlc update [package] [options]")
    assert helpText.Contains("Update failed")
    assert helpText.Contains("--dry-run")
}

test "the update command's sentences are exactly these" {
    assert UpdateCommandKernels.GetMissingProjectFileMessage() == "No project.yml found."
    assert UpdateCommandKernels.GetNoNuGetDependenciesMessage() == "No NuGet dependencies to update."
    assert UpdateCommandKernels.GetPackageNotFoundMessage("Serilog") == "Package 'Serilog' not found in dependencies."
    assert UpdateCommandKernels.GetResolveLatestFailureMessage("Serilog") == "  Could not resolve latest version for Serilog"
    assert UpdateCommandKernels.GetPackageUpToDateMessage("Serilog", "3.1.0") == "  Serilog@3.1.0 is up to date"
    assert UpdateCommandKernels.GetDryRunMessage() == "(dry run — no changes made)"
    assert UpdateCommandKernels.GetAllPackagesUpToDateMessage() == "All packages are up to date."
    assert UpdateCommandKernels.GetFailedMessage("boom") == "Update failed: boom"
}

test "an empty current version reads as the word unversioned, and a real one is printed as given" {
    assert UpdateCommandKernels.GetPackageUpdateMessage("Serilog", "", "3.1.0") == "  Serilog: unversioned -> 3.1.0"
    // THE OTHER SIDE OF THE SAME RULE, WHICH THE DELETED BODY DID NOT ASK FOR: a kernel that
    // always printed `unversioned` would have passed it.
    assert UpdateCommandKernels.GetPackageUpdateMessage("Serilog", "2.9.0", "3.1.0") == "  Serilog: 2.9.0 -> 3.1.0"
}

test "the updated-count sentence is singular at one and plural everywhere else, including zero" {
    assert UpdateCommandKernels.GetUpdatedPackagesMessage(1) == "Updated 1 package."
    assert UpdateCommandKernels.GetUpdatedPackagesMessage(2) == "Updated 2 packages."
    // ZERO IS PLURAL — the deleted body asked for 1 and 2 only, so a kernel keyed on `< 2` would
    // have passed it.
    assert UpdateCommandKernels.GetUpdatedPackagesMessage(0) == "Updated 0 packages."
}

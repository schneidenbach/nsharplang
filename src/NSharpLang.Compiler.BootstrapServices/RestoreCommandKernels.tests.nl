namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler

// THE `nlc restore` DEDUPLICATION, FILTER, OPTION, MESSAGE AND PROPS-GENERATION KERNELS.
//
// These replace THREE `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `RestoreCommandKernels_DeduplicatesProjectReferences`, `..._FiltersProjectReferences` and
// `..._SummarizesOptions`. All three are pure: every argument is a literal and every answer is a
// value, so none of this family needs the spawned-CLI route.

// ── the project-reference deduplicator ────────────────────────────────────────

test "duplicate project references collapse case-insensitively, keeping the FIRST spelling" {
    deduplicated := RestoreCommandKernels.DeduplicateProjectReferences([
        "../Shared/Shared.csproj",
        "../shared/shared.csproj",
        "../Models/Models.csproj",
        "../Shared/SHARED.csproj",
        "../Utilities/Utilities.csproj",
        "../models/models.csproj"
    ])

    // Three survive, in first-appearance order, each in the casing it was first written with —
    // which is what lands in the generated `obj/project.g.props`.
    assert deduplicated.Length == 3
    assert deduplicated[0] == "../Shared/Shared.csproj"
    assert deduplicated[1] == "../Models/Models.csproj"
    assert deduplicated[2] == "../Utilities/Utilities.csproj"
}

// ── the reference-type filter ─────────────────────────────────────────────────

test "the restore filter keeps only project references, in source order" {
    references := [
        new Reference { Nuget: "Serilog", Version: "3.1.1" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference { Dll: "lib/Analyzer.dll" },
        new Reference { Project: "../Models/project.yml" },
        new Reference { Framework: "Microsoft.AspNetCore.App" }
    ]

    projectReferences := RestoreCommandKernels.FilterReferencesByType(references, ReferenceType.Project)

    assert projectReferences.Count == 2
    assert projectReferences[0].Project == "../Shared/project.yml"
    assert projectReferences[1].Project == "../Models/project.yml"
}

test "the restore filter answers the other kinds from the same list" {
    // A CONTROL THE DELETED BODY DID NOT HAVE: it asked only for `Project`, so a filter that
    // ignored its argument would have passed.
    references := [
        new Reference { Nuget: "Serilog", Version: "3.1.1" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference { Dll: "lib/Analyzer.dll" },
        new Reference { Project: "../Models/project.yml" },
        new Reference { Framework: "Microsoft.AspNetCore.App" }
    ]

    assert RestoreCommandKernels.FilterReferencesByType(references, ReferenceType.NuGet).Count == 1
    assert RestoreCommandKernels.FilterReferencesByType(references, ReferenceType.Dll).Count == 1
    assert RestoreCommandKernels.FilterReferencesByType(references, ReferenceType.Framework).Count == 1
}

// ── the option summary ────────────────────────────────────────────────────────

test "restore takes help ONLY from a flag, never from the bare word" {
    // DELIBERATE AND PINNED, AND IT DIFFERS FROM EVERY OTHER COMMAND IN THIS FAMILY: `nlc restore
    // help` does NOT print help — it restores. `check`, `fix`, `lint`, `tidy`, `doc`, `test`,
    // `tree` and `format` all accept the bare word; `restore` does not.
    assert RestoreCommandKernels.GetOptionSummary(["--help"]).ShowHelp
    assert RestoreCommandKernels.GetOptionSummary(["-h"]).ShowHelp
    assert !RestoreCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert !RestoreCommandKernels.GetOptionSummary(new string[](0)).ShowHelp
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the restore help text names the command, its usage and the file it writes" {
    helpText := RestoreCommandKernels.GetHelpText()

    assert helpText.Contains("N# Restore")
    assert helpText.Contains("Usage: nlc restore")
    assert helpText.Contains("obj/project.g.props")
}

test "the restore command's sentences are exactly these" {
    assert RestoreCommandKernels.GetMissingProjectFileMessage() == "No project.yml found. Run 'nlc new <name>' to create a project."
    assert RestoreCommandKernels.GetGeneratedPropsMessage() == "Generated obj/project.g.props from project.yml"
    assert RestoreCommandKernels.GetFailedMessage("bad YAML") == "Failed to restore project configuration: bad YAML"
}

// ── the generated props file ──────────────────────────────────────────────────

test "the generated props file is exactly this, and carries no ItemGroup without references" {
    propsWithoutReferences := RestoreCommandKernels.GetGeneratedPropsText(
        "net10.0",
        "Exe",
        "Demo",
        "il",
        "xunit",
        "Microsoft.NET.Sdk",
        new string[](0))

    assert propsWithoutReferences == "<Project xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n    <OutputType>Exe</OutputType>\n    <_NSharpOriginalOutputType>Exe</_NSharpOriginalOutputType>\n    <AssemblyName>Demo</AssemblyName>\n    <NSharpCompilationBackend>il</NSharpCompilationBackend>\n    <NSharpTestFramework>xunit</NSharpTestFramework>\n    <_NSharpBaseSdk>Microsoft.NET.Sdk</_NSharpBaseSdk>\n  </PropertyGroup>\n</Project>\n"
    assert !propsWithoutReferences.Contains("<ItemGroup>")
}

test "a project reference is written as an escaped ProjectReference item" {
    propsWithReferences := RestoreCommandKernels.GetGeneratedPropsText(
        "net10.0",
        "Library",
        "Shared",
        "il",
        "nunit",
        "Microsoft.NET.Sdk.Web",
        ["../Shared/Shared.csproj", "/tmp/a&b<c>d\"e.csproj"])

    assert propsWithReferences.Contains("    <ProjectReference Include=\"../Shared/Shared.csproj\" />\n")
    // ALL FIVE XML attribute escapes are applied, which is what keeps a path with a quote in it
    // from breaking the generated MSBuild file.
    assert propsWithReferences.Contains("    <ProjectReference Include=\"/tmp/a&amp;b&lt;c&gt;d&quot;e.csproj\" />\n")
    assert propsWithReferences.Contains("<ItemGroup>")
}

test "the props file carries the OTHER output type and SDK through unchanged" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. Its second call passed `Library`,
    // `Microsoft.NET.Sdk.Web` and `nunit` but asserted only the two reference lines, so a
    // generator that hard-coded `Exe`/`xunit`/`Microsoft.NET.Sdk` would have passed both rows.
    propsWithReferences := RestoreCommandKernels.GetGeneratedPropsText(
        "net10.0",
        "Library",
        "Shared",
        "il",
        "nunit",
        "Microsoft.NET.Sdk.Web",
        ["../Shared/Shared.csproj"])

    assert propsWithReferences.Contains("<OutputType>Library</OutputType>")
    assert propsWithReferences.Contains("<_NSharpOriginalOutputType>Library</_NSharpOriginalOutputType>")
    assert propsWithReferences.Contains("<AssemblyName>Shared</AssemblyName>")
    assert propsWithReferences.Contains("<NSharpTestFramework>nunit</NSharpTestFramework>")
    assert propsWithReferences.Contains("<_NSharpBaseSdk>Microsoft.NET.Sdk.Web</_NSharpBaseSdk>")
}

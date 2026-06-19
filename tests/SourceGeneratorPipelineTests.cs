using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.SourceGenerators;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class SourceGeneratorPipelineTests
{
    private const string PackageId = "NSharpLang.TestSourceGenerator";
    private const string PackageVersion = "1.0.0";

    private static readonly Lazy<GeneratorAssets> Generator = new(BuildGeneratorAssets);

    [Fact]
    public void SourceGeneratorReferenceResolverKernels_ParsesTargetFrameworkVersions()
    {
        AssertParsed("net10.0", 10, 0);
        AssertParsed("netstandard2.1", 2, 1);
        AssertParsed("net472", 472, 0);
        AssertParsed("net10..2", 10, 2);
        AssertParsed("net10.bad", 10, 0);
        AssertParsed("net10.2147483648", 10, 0);
        AssertInvalid("net");
        AssertInvalid("net2147483648.0");

        static void AssertParsed(string targetFramework, int expectedMajor, int expectedMinor)
        {
            Assert.True(SourceGeneratorReferenceResolverKernels.TryParseTargetFrameworkVersion(
                targetFramework,
                out var parsed,
                out var major,
                out var minor));
            Assert.True(parsed);
            Assert.Equal(expectedMajor, major);
            Assert.Equal(expectedMinor, minor);
        }

        static void AssertInvalid(string targetFramework)
        {
            Assert.True(SourceGeneratorReferenceResolverKernels.TryParseTargetFrameworkVersion(
                targetFramework,
                out var parsed,
                out _,
                out _));
            Assert.False(parsed);
        }
    }

    [Fact]
    public void DirectSourceGenerator_EmitsStandaloneTypeConsumedFromNSharp()
    {
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return GeneratedTools.Value + 1
}
"""));

        var config = CreateLibraryConfig("DirectGeneratedType");
        AddDirectGenerator(config);

        var result = CompileAndInvoke(project.Root, config, "Run");

        Assert.Equal(42, result);
    }

    [Fact]
    public void PackageReferenceSourceGenerator_RunsFromNuGetAnalyzerAssets()
    {
        using var packages = UseSyntheticNuGetPackages();
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return GeneratedTools.Value + 2
}
"""));

        var config = CreateLibraryConfig("PackageGeneratedType");
        config.Dependencies.Add(new Reference { Nuget = PackageId, Version = PackageVersion });

        var result = CompileAndInvoke(project.Root, config, "Run");

        Assert.Equal(43, result);
    }

    [Fact]
    public void ProjectReferenceSourceGenerator_RunsFromCSharpProjectReference()
    {
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return GeneratedTools.Value + 3
}
"""));

        var config = CreateLibraryConfig("ProjectReferenceGeneratedType");
        config.Dependencies.Add(new Reference { Project = Generator.Value.ProjectPath });

        var result = CompileAndInvoke(project.Root, config, "Run");

        Assert.Equal(44, result);
    }

    [Fact]
    public void GeneratedPartialMembers_AreVisibleToAnalyzerAndCodeIntelligence()
    {
        using var project = CreateProject(("Program.nl", """
namespace Demo

partial class Widget {
}

func Run(): int {
    return Widget.Answer
}
"""));

        var config = CreateLibraryConfig("GeneratedPartialAnalyzer");
        AddDirectGenerator(config);

        var service = new CodeIntelligenceService();
        var snapshot = service.LoadProject(project.Root, config);

        Assert.DoesNotContain(snapshot.AllErrors, error => error.DiagnosticId == "NL303");

        var line = FindLine(project.File("Program.nl"), "Widget.Answer");
        var col = FindColumn(project.File("Program.nl"), line, "Widget.") + "Widget.".Length - 1;
        var completions = new CompletionEngine().GetCompletions(snapshot, "Program.nl", line, col);
        var allItems = completions.Completions.Values.SelectMany(items => items).ToArray();

        Assert.Contains(allItems, item => item.Name == "Answer");
        Assert.Contains(allItems, item => item.Name == "Label");
        Assert.DoesNotContain(allItems, item => item.Name == "Caption");
    }

    [Fact]
    public void GeneratedPartialMemberCompletions_RespectReceiverAccessKind()
    {
        using var project = CreateProject(("Program.nl", """
namespace Demo

partial class Widget {
}

func CompleteStatic(): int {
    return Widget.Answer
}

func CompleteInstance(): string {
    widget := new Widget {}
    return widget.Caption
}
"""));

        var config = CreateLibraryConfig("GeneratedPartialCompletionAccess");
        AddDirectGenerator(config);

        var service = new CodeIntelligenceService();
        var snapshot = service.LoadProject(project.Root, config);

        Assert.DoesNotContain(snapshot.AllErrors, error => error.DiagnosticId == "NL303");

        var staticLine = FindLine(project.File("Program.nl"), "Widget.Answer");
        var staticCol = FindColumn(project.File("Program.nl"), staticLine, "Widget.") + "Widget.".Length - 1;
        var staticItems = new CompletionEngine()
            .GetCompletions(snapshot, "Program.nl", staticLine, staticCol)
            .Completions
            .Values
            .SelectMany(items => items)
            .ToArray();

        Assert.Contains(staticItems, item => item.Name == "Answer" && item.IsStatic);
        Assert.Contains(staticItems, item => item.Name == "Label" && item.IsStatic);
        Assert.DoesNotContain(staticItems, item => item.Name == "Caption");

        var instanceLine = FindLine(project.File("Program.nl"), "widget.Caption");
        var instanceCol = FindColumn(project.File("Program.nl"), instanceLine, "widget.") + "widget.".Length - 1;
        var instanceItems = new CompletionEngine()
            .GetCompletions(snapshot, "Program.nl", instanceLine, instanceCol)
            .Completions
            .Values
            .SelectMany(items => items)
            .ToArray();

        Assert.Contains(instanceItems, item => item.Name == "Caption" && !item.IsStatic);
        Assert.DoesNotContain(instanceItems, item => item.Name == "Answer");
        Assert.DoesNotContain(instanceItems, item => item.Name == "Label");
    }

    [Fact]
    public void QueryCommand_LoadsPackageSourceGeneratorsForTypeQueries()
    {
        using var packages = UseSyntheticNuGetPackages();
        using var project = CreateProject(
            ("project.yml", $"""
name: QueryGeneratedMember
version: 1.0.0
entry: Program.nl
outputType: library
targetFramework: net10.0
dependencies:
  - nuget: {PackageId}
    version: {PackageVersion}
"""),
            ("Program.nl", """
namespace Demo

partial class Widget {
}

func Run(): int {
    return Widget.Answer
}
"""));

        var line = FindLine(project.File("Program.nl"), "Widget.Answer");
        var col = FindColumn(project.File("Program.nl"), line, "Answer");
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", project.Root,
            "--no-daemon",
            "--file", "Program.nl",
            "--pos", $"{line}:{col}"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

        using var document = JsonDocument.Parse(stdout);
        Assert.Equal(1, document.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("type", document.RootElement.GetProperty("command").GetString());
        Assert.Equal("int", document.RootElement.GetProperty("result").GetProperty("resolvedType").GetString());
    }

    [Fact]
    public void SystemTextJsonSourceGeneration_RunsActualGeneratorAndCompilesGeneratedOutput()
    {
        using var project = CreateProject(("Program.nl", """
import System.Text.Json
import System.Text.Json.Serialization

record Payload {
    Name: string
    Count: int
}

[JsonSerializable(typeof(Payload))]
partial class PayloadJsonContext : JsonSerializerContext {
}

func Run(): string {
    payload := new Payload { Name: "alpha", Count: 7 }
    return JsonSerializer.Serialize(payload, PayloadJsonContext.Default.Payload)
}
"""));

        var config = CreateLibraryConfig("SystemTextJsonGeneratedContext");
        var result = CompileAndInvoke(project.Root, config, "Run");

        Assert.Equal("""{"Name":"alpha","Count":7}""", result);
        Assert.Contains(
            Directory.GetFiles(project.Root, "PayloadJsonContext.g.cs", SearchOption.AllDirectories),
            path => path.Contains(Path.Combine("obj", "nsharp", "generated"), StringComparison.Ordinal));
        Assert.Empty(Directory.GetFiles(project.Root, "*.cs", SearchOption.AllDirectories)
            .Where(path => File.ReadAllText(path).Contains("__NSharpJson", StringComparison.Ordinal)));
    }

    [Fact]
    public void SystemTextJsonGenerator_WithInferredStackalloc_EmitsAndRuns()
    {
        // F1: an active generator routes the WHOLE build through Roslyn over exported C#, so the
        // inferred-stackalloc declaration must compile there too. Previously the transpiler
        // emitted `var scratch = stackalloc byte[4];` (CS0214 wrapped as NL922) even though the
        // same program built and ran on the IL backend without the generator.
        using var project = CreateProject(("Program.nl", """
import System.Text.Json
import System.Text.Json.Serialization

record Payload {
    Code: int
}

[JsonSerializable(typeof(Payload))]
partial class PayloadJsonContext : JsonSerializerContext {
}

func Run(): string {
    scratch := stackalloc byte[4]
    scratch[0] = 40
    scratch[1] = 2
    total := 0
    for i := 0; i < scratch.Length; i++ {
        total = total + scratch[i]
    }
    payload := new Payload { Code: total }
    return JsonSerializer.Serialize(payload, PayloadJsonContext.Default.Payload)
}
"""));

        var config = CreateLibraryConfig("JsonGeneratorStackalloc");
        var result = CompileAndInvoke(project.Root, config, "Run");

        Assert.Equal("""{"Code":42}""", result);
    }

    public static TheoryData<string, string> ExportParityPrograms => new()
    {
        {
            "inferred-stackalloc",
            """
func Run(): int {
    scratch := stackalloc byte[4]
    scratch[0] = 40
    scratch[1] = 2
    total := 0
    for i := 0; i < scratch.Length; i++ {
        total = total + scratch[i]
    }
    return total
}
"""
        },
        {
            "explicit-span-stackalloc",
            """
import System

func Run(): int {
    scratch: Span<byte> = stackalloc byte[42]
    return scratch.Length
}
"""
        },
        {
            "array-to-readonly-span",
            """
import System

func Sum(values: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < values.Length; i++ {
        total = total + values[i]
    }
    return total
}

func Run(): int {
    values := [20, 22]
    return Sum(values)
}
"""
        },
        {
            "try-catch-finally",
            """
import System

func Run(): int {
    total := 0
    try {
        total = total + 40
        throw new InvalidOperationException("boom")
    } catch (Exception) {
        total = total + 1
    } finally {
        total = total + 1
    }
    return total
}
"""
        },
        {
            "union-match",
            """
union Outcome {
    Success { value: int }
    Failure { error: string }
}

func Make(ok: bool): Outcome {
    if ok {
        return new Outcome.Success { value: 42 }
    }
    return new Outcome.Failure { error: "nope" }
}

func Run(): int {
    return match Make(true) {
        Outcome.Success { value } => value,
        Outcome.Failure { error } => 0
    }
}
"""
        },
        {
            "foreach-array",
            """
func Run(): int {
    values := [40, 2]
    total := 0
    foreach value in values {
        total = total + value
    }
    return total
}
"""
        }
    };

    [Theory]
    [MemberData(nameof(ExportParityPrograms))]
    public void GeneratorActiveBuild_CompilesAndRunsIlBackendConstructs(string name, string source)
    {
        // F1 guardrail: ANY active generator silently reroutes emission from the IL backend to
        // Roslyn over exported C# (by design — generated partial classes must merge with
        // N#-declared types), which makes the transpiler a hidden correctness gate for the whole
        // language surface. Representative IL-backend constructs must emit AND run on that route.
        using var project = CreateProject(("Program.nl", source));

        var config = CreateLibraryConfig($"ExportParity_{name.Replace('-', '_')}");
        AddDirectGenerator(config);

        var result = CompileAndInvoke(project.Root, config, "Run");

        Assert.Equal(42, result);
    }

    [Fact]
    public void GeneratedSourceInvalid_DiagnosticsMapToNSharpSourceLines()
    {
        // Exported C# trees are keyed by the .nl path and carry the transpiler's #line
        // directives; a Roslyn error on a mapped line must surface at the .nl position
        // (file, line, snippet), not at raw generated-C# coordinates (previously NL922
        // reported e.g. Program.nl:29 in a 23-line file, with C# snippets).
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return 1
}
"""));

        var programPath = project.File("Program.nl");
        var exported = $$"""
using System;
#line 2 "{{programPath}}"
public static class Broken { public static int Value = "not an int"; }
""";

        var config = CreateLibraryConfig("MappedGeneratorDiagnostics");
        AddDirectGenerator(config);

        var result = SourceGeneratorPipeline.EmitFinalAssembly(
            config,
            project.Root,
            "MappedGeneratorDiagnostics",
            new Dictionary<string, string> { [programPath] = exported },
            Array.Empty<CompilationUnit>(),
            project.OutputPath("MappedGeneratorDiagnostics"));

        var error = Assert.Single(result.Diagnostics, diagnostic => diagnostic.Severity == ErrorSeverity.Error);
        Assert.Equal("NL922", error.DiagnosticId);
        Assert.Equal(programPath, error.FileName);
        Assert.Equal(2, error.Line);
        Assert.Equal("    return 1", error.SourceSnippet);
    }

    [Fact]
    public void FailingEmit_PersistsExportedCSharpForInspection()
    {
        // The exported C# only exists in memory; when Roslyn rejects it the failing sources
        // must be written under obj/nsharp/generated/<assembly>/emit/exported/ so NL922
        // failures can be inspected.
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return 1
}
"""));

        var programPath = project.File("Program.nl");
        var exported = """
public static class Broken { public static int Value = "not an int"; }
""";

        var config = CreateLibraryConfig("PersistedExportedSources");
        AddDirectGenerator(config);

        var result = SourceGeneratorPipeline.EmitFinalAssembly(
            config,
            project.Root,
            "PersistedExportedSources",
            new Dictionary<string, string> { [programPath] = exported },
            Array.Empty<CompilationUnit>(),
            project.OutputPath("PersistedExportedSources"));

        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Severity == ErrorSeverity.Error);

        var persistedPath = Path.Combine(
            project.Root, "obj", "nsharp", "generated", "PersistedExportedSources", "emit", "exported", "Program.nl.cs");
        Assert.True(File.Exists(persistedPath), $"Expected persisted exported C# at {persistedPath}");
        Assert.Equal(exported, File.ReadAllText(persistedPath));
    }

    [Fact]
    public void MissingGeneratorAssembly_ReportsStableLoadDiagnostic()
    {
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return 1
}
"""));

        var config = CreateLibraryConfig("MissingGenerator");
        config.SourceGenerators.Add(new SourceGeneratorReference(
            Path.Combine(project.Root, "missing-generator.dll"),
            SourceGeneratorReferenceKind.Direct,
            "missing-generator"));

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        var result = compiler.CompileToIlAssembly("MissingGenerator", project.OutputPath("MissingGenerator"));

        Assert.False(result.Success);
        Assert.Contains(result.Errors, error => error.DiagnosticId == "NL920" && error.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void GeneratorDiagnostic_IsSurfacedAsSourceGeneratorDiagnostic()
    {
        using var project = CreateProject(("Program.nl", """
class NSharpGeneratorDiagnosticMarker {
}

func Run(): int {
    return 1
}
"""));

        var config = CreateLibraryConfig("GeneratorDiagnostic");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        var result = compiler.CompileToIlAssembly("GeneratorDiagnostic", project.OutputPath("GeneratorDiagnostic"));

        Assert.True(result.Success, FormatErrors(result.Errors));
        Assert.Contains(result.Errors, error =>
            error.DiagnosticId == "NL921"
            && error.Severity == ErrorSeverity.Warning
            && error.RelatedInfo?["roslynDiagnosticId"] == "TSG001");
    }

    [Fact]
    public void InvalidGeneratedCode_IsReportedAsGeneratedSourceInvalid()
    {
        using var project = CreateProject(("Program.nl", """
class NSharpGeneratorInvalidMarker {
}

func Run(): int {
    return 1
}
"""));

        var config = CreateLibraryConfig("InvalidGeneratedCode");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        var result = compiler.CompileToIlAssembly("InvalidGeneratedCode", project.OutputPath("InvalidGeneratedCode"));

        Assert.False(result.Success);
        Assert.Contains(result.Errors, error => error.DiagnosticId == "NL922" && error.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void GeneratorCrash_IsReportedAsSourceGeneratorFailure()
    {
        using var project = CreateProject(("Program.nl", """
class NSharpGeneratorCrashMarker {
}

func Run(): int {
    return 1
}
"""));

        var config = CreateLibraryConfig("GeneratorCrash");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        var result = compiler.CompileToIlAssembly("GeneratorCrash", project.OutputPath("GeneratorCrash"));

        Assert.False(result.Success);
        Assert.Contains(result.Errors, error =>
            error.DiagnosticId == "NL921"
            && error.Severity == ErrorSeverity.Error
            && error.Message.Contains("crashed", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void DeterministicRebuild_WritesStableGeneratedSources()
    {
        using var project = CreateProject(("Program.nl", """
namespace Demo

partial class Widget {
}

func Run(): int {
    return Widget.Answer
}
"""));

        var config = CreateLibraryConfig("DeterministicGeneratedSources");
        AddDirectGenerator(config);

        var first = CompileProject(project.Root, config, "DeterministicGeneratedSources");
        Assert.True(first.Success, FormatErrors(first.Errors));
        var firstSnapshot = ReadGeneratedSources(project.Root, "DeterministicGeneratedSources");

        var second = CompileProject(project.Root, config, "DeterministicGeneratedSources");
        Assert.True(second.Success, FormatErrors(second.Errors));
        var secondSnapshot = ReadGeneratedSources(project.Root, "DeterministicGeneratedSources");

        Assert.Equal(firstSnapshot, secondSnapshot);
    }

    [Fact]
    public void Rebuild_RemovesStaleGeneratedOutputs()
    {
        using var project = CreateProject(("Program.nl", """
class NSharpStaleOn {
}

func Run(): int {
    return StaleOnly.Value
}
"""));

        var config = CreateLibraryConfig("StaleGeneratedSources");
        AddDirectGenerator(config);

        var first = CompileProject(project.Root, config, "StaleGeneratedSources");
        Assert.True(first.Success, FormatErrors(first.Errors));
        Assert.Contains(
            Directory.GetFiles(project.Root, "StaleOnly.g.cs", SearchOption.AllDirectories),
            path => path.Contains(Path.Combine("obj", "nsharp", "generated"), StringComparison.Ordinal));

        File.WriteAllText(project.File("Program.nl"), """
func Run(): int {
    return GeneratedTools.Value
}
""");

        var second = CompileProject(project.Root, config, "StaleGeneratedSources");
        Assert.True(second.Success, FormatErrors(second.Errors));
        Assert.DoesNotContain(
            Directory.GetFiles(project.Root, "StaleOnly.g.cs", SearchOption.AllDirectories),
            path => path.Contains(Path.Combine("obj", "nsharp", "generated"), StringComparison.Ordinal));
    }

    [Fact]
    public void DuplicateGeneratedSymbols_AreReportedAsGeneratedSourceInvalid()
    {
        using var project = CreateProject(("Program.nl", """
namespace Demo

partial class Widget {
    static Answer: int = 1
}

func Run(): int {
    return Widget.Answer
}
"""));

        var config = CreateLibraryConfig("DuplicateGeneratedSymbols");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        var result = compiler.CompileToIlAssembly("DuplicateGeneratedSymbols", project.OutputPath("DuplicateGeneratedSymbols"));

        Assert.False(result.Success);
        Assert.Contains(result.Errors, error => error.DiagnosticId == "NL922" && error.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void NamespaceCollisions_DoNotLeakGeneratedMembersBetweenTypes()
    {
        using var project = CreateProject(
            ("Alpha.nl", """
namespace Alpha

partial class Widget {
}

func Read(): int {
    return Widget.Answer
}
"""),
            ("Beta.nl", """
namespace Beta

partial class Widget {
}

func Read(): int {
    return Widget.Answer
}
"""));

        var config = CreateLibraryConfig("NamespaceCollision");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        compiler.CompileForAnalysis();

        Assert.Contains(compiler.AllErrors, error =>
            error.DiagnosticId == "NL303"
            && error.FileName != null
            && error.FileName.EndsWith("Beta.nl", StringComparison.Ordinal));
        Assert.DoesNotContain(compiler.AllErrors, error =>
            error.DiagnosticId == "NL303"
            && error.FileName != null
            && error.FileName.EndsWith("Alpha.nl", StringComparison.Ordinal));
    }

    [Fact]
    public void PartialTypes_CanConsumeGeneratedMembersAcrossSourceFiles()
    {
        using var project = CreateProject(
            ("Widget.One.nl", """
namespace Demo

partial class Widget {
}
"""),
            ("Widget.Two.nl", """
namespace Demo

partial class Widget {
    func Value(): int {
        return Widget.Answer
    }
}
"""),
            ("Program.nl", """
namespace Demo

func Run(widget: Widget): int {
    return widget.Value()
}
"""));

        var config = CreateLibraryConfig("PartialGeneratedMembers");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        compiler.CompileForAnalysis();

        Assert.DoesNotContain(compiler.AllErrors, error => error.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void GeneratorDiagnostic_IsReportedExactlyOnce()
    {
        // M7: the run-result diagnostics and the RunGeneratorsAndUpdateCompilation out-param
        // diagnostics previously double-reported every generator diagnostic. CompileForAnalysis
        // runs a single generator pass, so a single reported diagnostic must appear exactly once.
        using var project = CreateProject(("Program.nl", """
class NSharpGeneratorDiagnosticMarker {
}

func Run(): int {
    return 1
}
"""));

        var config = CreateLibraryConfig("GeneratorDiagnosticOnce");
        AddDirectGenerator(config);

        var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
        compiler.CompileForAnalysis();

        var testGeneratorDiagnostics = compiler.AllErrors
            .Where(error =>
                error.DiagnosticId == "NL921"
                && error.RelatedInfo != null
                && error.RelatedInfo.TryGetValue("roslynDiagnosticId", out var id)
                && id == "TSG001")
            .ToList();

        Assert.Single(testGeneratorDiagnostics);
    }

    [Fact]
    public void NonRoslynComponentProjectReference_IsNotBuilt()
    {
        // H5: ordinary library project references must NOT be built by source-generator
        // discovery on the analysis path; only Roslyn-component projects are.
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return 1
}
"""));

        var libraryDirectory = Directory.CreateTempSubdirectory("nsharp-plain-lib-").FullName;
        try
        {
            var libraryProjectPath = Path.Combine(libraryDirectory, "PlainLibrary.csproj");
            File.WriteAllText(libraryProjectPath, """
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>
</Project>
""");

            var config = CreateLibraryConfig("NonComponentReference");
            config.Dependencies.Add(new Reference { Project = libraryProjectPath });

            var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);
            compiler.CompileForAnalysis();

            Assert.False(
                Directory.Exists(Path.Combine(libraryDirectory, "bin")),
                "A non-Roslyn-component project reference must not be built by source-generator discovery (H5).");
            Assert.False(
                Directory.Exists(Path.Combine(libraryDirectory, "obj")),
                "A non-Roslyn-component project reference must not be restored/built by source-generator discovery (H5).");
        }
        finally
        {
            Directory.Delete(libraryDirectory, recursive: true);
        }
    }

    [Fact]
    public void FailingGeneratorProjectReference_ReportsDiagnosticInsteadOfCrashing()
    {
        // H6: a Roslyn-component project reference that fails to build must surface a clean
        // NL920 diagnostic rather than throwing out of analysis / the language server.
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return 1
}
"""));

        var generatorDirectory = Directory.CreateTempSubdirectory("nsharp-broken-generator-").FullName;
        try
        {
            var brokenProjectPath = Path.Combine(generatorDirectory, "BrokenGenerator.csproj");
            File.WriteAllText(brokenProjectPath, """
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <IsRoslynComponent>true</IsRoslynComponent>
  </PropertyGroup>
</Project>
""");
            // A deliberate syntax error so `dotnet build` exits non-zero quickly.
            File.WriteAllText(Path.Combine(generatorDirectory, "Broken.cs"), "public class Broken { this is not valid c# }");

            var config = CreateLibraryConfig("FailingGeneratorReference");
            config.Dependencies.Add(new Reference { Project = brokenProjectPath });

            var compiler = new MultiFileCompiler(project.SourceFiles, project.Root, config);

            // Must not throw.
            compiler.CompileForAnalysis();

            Assert.Contains(
                compiler.AllErrors,
                error => error.DiagnosticId == "NL920" && error.Severity == ErrorSeverity.Error);
        }
        finally
        {
            Directory.Delete(generatorDirectory, recursive: true);
        }
    }

    [Fact]
    public void GeneratorLoadContext_IsReusedAcrossRuns()
    {
        // H7: loading generators previously created a fresh non-collectible AssemblyLoadContext
        // per run, leaking one per analysis/emit. The load cache must reuse the context for the
        // same generator set, so a second identical run creates no new context.
        using var project = CreateProject(("Program.nl", """
func Run(): int {
    return GeneratedTools.Value + 1
}
"""));

        var config = CreateLibraryConfig("GeneratorAlcReuse");
        AddDirectGenerator(config);

        var first = CompileProject(project.Root, config, "GeneratorAlcReuseA");
        Assert.True(first.Success, FormatErrors(first.Errors));

        var contextsBefore = CountGeneratorLoadContexts();

        var second = CompileProject(project.Root, config, "GeneratorAlcReuseB");
        Assert.True(second.Success, FormatErrors(second.Errors));

        var contextsAfter = CountGeneratorLoadContexts();

        Assert.Equal(contextsBefore, contextsAfter);
    }

    private static int CountGeneratorLoadContexts()
        => AssemblyLoadContext.All.Count(context =>
            string.Equals(context.Name, SourceGeneratorPipeline.GeneratorLoadContextName, StringComparison.Ordinal));

    private static void AddDirectGenerator(ProjectConfig config)
    {
        config.SourceGenerators.Add(new SourceGeneratorReference(
            Generator.Value.AssemblyPath,
            SourceGeneratorReferenceKind.Direct,
            "test-generator"));
    }

    private static MultiFileCompilationResult CompileProject(string projectRoot, ProjectConfig config, string assemblyName)
    {
        var sourceFiles = config.GetSourceFiles(projectRoot, includeTests: false);
        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return compiler.CompileToIlAssembly(assemblyName, Path.Combine(projectRoot, "bin", $"{assemblyName}.dll"));
    }

    private static object? CompileAndInvoke(string projectRoot, ProjectConfig config, string functionName)
    {
        var assemblyName = config.Name ?? "SourceGeneratorTest";
        var result = CompileProject(projectRoot, config, assemblyName);
        Assert.True(result.Success, FormatErrors(result.Errors));
        Assert.NotNull(result.OutputAssemblyPath);

        AssemblyLoadContext? loadContext = null;
        try
        {
            loadContext = new AssemblyLoadContext($"{assemblyName}_{Guid.NewGuid():N}", isCollectible: true);
            var assembly = loadContext.LoadFromAssemblyPath(result.OutputAssemblyPath!);
            var method = assembly.GetTypes()
                .Select(type => type.GetMethod(functionName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance))
                .FirstOrDefault(method => method != null && method.GetParameters().Length == 0);
            Assert.NotNull(method);
            return method.IsStatic
                ? method.Invoke(null, null)
                : method.Invoke(Activator.CreateInstance(method.DeclaringType!), null);
        }
        finally
        {
            loadContext?.Unload();
        }
    }

    private static ProjectConfig CreateLibraryConfig(string name)
    {
        return new ProjectConfig
        {
            Name = name,
            OutputType = "library",
            TargetFramework = "net10.0"
        };
    }

    private static TemporaryProject CreateProject(params (string RelativePath, string Source)[] files)
    {
        var root = Directory.CreateTempSubdirectory("nsharp-source-generator-").FullName;
        var hasProjectFile = files.Any(file => string.Equals(file.RelativePath, "project.yml", StringComparison.OrdinalIgnoreCase));
        if (!hasProjectFile)
        {
            File.WriteAllText(Path.Combine(root, "project.yml"), """
name: SourceGeneratorTemp
version: 1.0.0
entry: Program.nl
outputType: library
targetFramework: net10.0
""");
        }

        foreach (var (relativePath, source) in files)
        {
            var path = Path.Combine(root, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, source);
        }

        return new TemporaryProject(root);
    }

    private static IReadOnlyDictionary<string, string> ReadGeneratedSources(string projectRoot, string assemblyName)
    {
        var generatedRoot = Path.Combine(projectRoot, "obj", "nsharp", "generated", assemblyName, "emit");
        return Directory.Exists(generatedRoot)
            ? Directory.GetFiles(generatedRoot, "*.cs", SearchOption.AllDirectories)
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(
                    path => Path.GetRelativePath(generatedRoot, path).Replace('\\', '/'),
                    File.ReadAllText,
                    StringComparer.Ordinal)
            : new Dictionary<string, string>(StringComparer.Ordinal);
    }

    private static GeneratorAssets BuildGeneratorAssets()
    {
        var root = Directory.CreateTempSubdirectory("nsharp-test-generator-assets-").FullName;
        var projectPath = Path.Combine(root, "NSharpLang.TestSourceGenerator.csproj");
        var sourcePath = Path.Combine(root, "TestSourceGenerator.cs");
        File.WriteAllText(projectPath, """
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <AssemblyName>NSharpLang.TestSourceGenerator</AssemblyName>
    <IsRoslynComponent>true</IsRoslynComponent>
    <EnforceExtendedAnalyzerRules>false</EnforceExtendedAnalyzerRules>
    <NoWarn>$(NoWarn);RS1036;RS1042;RS2008</NoWarn>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.14.0" PrivateAssets="all" />
  </ItemGroup>
</Project>
""");
        File.WriteAllText(sourcePath, """"
using System;
using System.Linq;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;

[Generator]
public sealed class TestSourceGenerator : ISourceGenerator
{
    private static readonly DiagnosticDescriptor TestDiagnostic = new(
        "TSG001",
        "Test generator diagnostic",
        "Test generator diagnostic for {0}",
        "NSharpLang.Tests",
        DiagnosticSeverity.Warning,
        isEnabledByDefault: true);

    public void Initialize(GeneratorInitializationContext context)
    {
    }

    public void Execute(GeneratorExecutionContext context)
    {
        var input = string.Join("\n", context.Compilation.SyntaxTrees.Select(tree => tree.GetText().ToString()));

        if (Has(input, "NSharpGeneratorCrashMarker"))
        {
            throw new InvalidOperationException("test generator crash");
        }

        if (Has(input, "NSharpGeneratorDiagnosticMarker"))
        {
            context.ReportDiagnostic(Diagnostic.Create(TestDiagnostic, Location.None, "N#"));
        }

        if (Has(input, "NSharpGeneratorInvalidMarker"))
        {
            Add(context, "InvalidGeneratedCode.g.cs", "public class InvalidGeneratedCode {");
            return;
        }

        Add(context, "GeneratedTools.g.cs", """
public static class GeneratedTools
{
    public static int Value => 41;
}
""");

        Add(context, "Demo.Widget.g.cs", """
namespace Demo
{
    public partial class Widget
    {
        public static int Answer => 42;
        public static string Label => "generated";
        public string Caption => "instance-generated";
    }
}
""");

        Add(context, "Alpha.Widget.g.cs", """
namespace Alpha
{
    public partial class Widget
    {
        public static int Answer => 1;
    }
}
""");

        if (Has(input, "NSharpStaleOn"))
        {
            Add(context, "StaleOnly.g.cs", """
public static class StaleOnly
{
    public static int Value => 7;
}
""");
        }
    }

    private static bool Has(string input, string marker)
        => input.IndexOf(marker, StringComparison.Ordinal) >= 0;

    private static void Add(GeneratorExecutionContext context, string hintName, string source)
        => context.AddSource(hintName, SourceText.From(source, Encoding.UTF8));
}
"""");

        RunDotnetBuild(projectPath, root);

        var assemblyPath = Path.Combine(root, "bin", "Debug", "netstandard2.0", "NSharpLang.TestSourceGenerator.dll");
        Assert.True(File.Exists(assemblyPath), $"Expected generator assembly at {assemblyPath}");

        var packageRoot = Path.Combine(root, "packages");
        var analyzerDirectory = Path.Combine(packageRoot, PackageId.ToLowerInvariant(), PackageVersion, "analyzers", "dotnet", "cs");
        Directory.CreateDirectory(analyzerDirectory);
        File.Copy(assemblyPath, Path.Combine(analyzerDirectory, Path.GetFileName(assemblyPath)), overwrite: true);

        return new GeneratorAssets(root, projectPath, assemblyPath, packageRoot);
    }

    private static IDisposable UseSyntheticNuGetPackages()
    {
        var previous = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", Generator.Value.PackageRoot);
        return new RestoreEnvironmentVariable("NUGET_PACKAGES", previous);
    }

    private static void RunDotnetBuild(string projectPath, string workingDirectory)
    {
        var startInfo = new ProcessStartInfo("dotnet")
        {
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        startInfo.ArgumentList.Add("build");
        startInfo.ArgumentList.Add(projectPath);
        startInfo.ArgumentList.Add("--nologo");
        startInfo.ArgumentList.Add("-v:q");
        startInfo.ArgumentList.Add("--disable-build-servers");

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start dotnet build.");
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        Assert.True(process.ExitCode == 0, stdout + Environment.NewLine + stderr);
    }

    private static int FindLine(string filePath, string needle)
    {
        var lineNumber = 0;
        foreach (var line in File.ReadLines(filePath))
        {
            lineNumber++;
            if (line.Contains(needle, StringComparison.Ordinal))
            {
                return lineNumber;
            }
        }

        throw new Xunit.Sdk.XunitException($"Could not find '{needle}' in {filePath}");
    }

    private static int FindColumn(string filePath, int lineNumber, string needle)
    {
        var line = File.ReadLines(filePath).Skip(lineNumber - 1).First();
        var index = line.IndexOf(needle, StringComparison.Ordinal);
        Assert.True(index >= 0, $"Could not find '{needle}' on line {lineNumber}: {line}");
        return index + 1;
    }

    private static string FormatErrors(IEnumerable<CompilerError> errors)
        => string.Join(Environment.NewLine, errors.Select(error =>
            $"{error.DiagnosticId}: {error.Message} ({error.FileName}:{error.Line}:{error.Column})"));

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        try
        {
            Console.SetOut(stdout);
            Console.SetError(stderr);
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
        }
    }

    private sealed record GeneratorAssets(
        string Root,
        string ProjectPath,
        string AssemblyPath,
        string PackageRoot);

    private sealed class TemporaryProject(string root) : IDisposable
    {
        public string Root { get; } = root;

        public string[] SourceFiles => ProjectConfig.EnumerateSourceFiles(Root).ToArray();

        public string File(string relativePath) => Path.Combine(Root, relativePath);

        public string OutputPath(string assemblyName) => Path.Combine(Root, "bin", $"{assemblyName}.dll");

        public void Dispose()
        {
            if (Directory.Exists(Root))
            {
                Directory.Delete(Root, recursive: true);
            }
        }
    }

    private sealed class RestoreEnvironmentVariable(string name, string? previousValue) : IDisposable
    {
        public void Dispose()
        {
            Environment.SetEnvironmentVariable(name, previousValue);
        }
    }
}

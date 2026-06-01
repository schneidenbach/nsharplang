using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class SystemsNSharpTests
{
    [Fact]
    public void HotFunction_RejectsHeapAllocation()
    {
        var report = Analyze("""
[hot]
func Make(): int {
    value := new Box()
    return 1
}

class Box {}
""");

        var finding = Assert.Single(report.Findings, f => f.Code == "NSYS010");
        Assert.Equal("error", finding.Severity);
        Assert.Equal("allocation", finding.Effect);
        Assert.Equal("Make", finding.Function);
    }

    [Fact]
    public void SystemsStrict_RequiresExplicitAllocMarkerForHeapNew()
    {
        var report = Analyze("""
func Make(): Box {
    return new Box()
}

class Box {}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS001" && f.Severity == "error");
    }

    [Fact]
    public void SystemsStrict_AcceptsExplicitAllocMarkerOutsideHot()
    {
        var report = Analyze("""
func Make(): Box {
    return alloc new Box()
}

class Box {}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS001");
    }

    [Fact]
    public void SystemsStrict_AcceptsAllocBlockForObviousAllocationSugar()
    {
        var report = Analyze("""
func Make(): Box {
    alloc {
        return new Box()
    }
}

class Box {}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS001");
    }

    [Fact]
    public void HotFunction_RejectsUnguardedIndexTrap()
    {
        var report = Analyze("""
[hot]
func First(bytes: byte[]): byte {
    return bytes[0]
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_AcceptsSimpleLengthGuardedIndex()
    {
        var report = Analyze("""
[hot]
func First(bytes: byte[]): byte {
    if bytes.Length < 1 {
        return 0
    }
    return bytes[0]
}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_DoesNotApplyPostIfGuardInsideFailingBranch()
    {
        var report = Analyze("""
[hot]
func First(bytes: byte[]): byte {
    if bytes.Length < 1 {
        return bytes[0]
    }
    return 0
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "implicitTrap");
    }

    [Fact]
    public void HotFunction_AcceptsNarrowAllowAllocBlock()
    {
        var report = Analyze("""
[hot]
func Make(): int {
    allow(alloc, reason: "cold fallback table") {
        value := alloc new Box()
    }
    return 1
}

class Box {}
""");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS010" && f.Effect == "allocation");
    }

    [Fact]
    public void BoundaryFunction_ReportsAllocationAndUnknownExternalCallWithoutBlocking()
    {
        var report = Analyze("""
[boundary]
func Load(): int {
    value := new Box()
    Console.WriteLine("loaded")
    return 1
}

class Box {}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS001" && f.Severity == "warning");
        Assert.Contains(report.Findings, f => f.Code == "NSYS050" && f.Severity == "warning");
        Assert.DoesNotContain(report.Findings, f => f.Severity == "error");
    }

    [Fact]
    public void TrustedFunction_RequiresGovernanceMetadata()
    {
        var report = Analyze("""
[trusted(reason: "wraps native copy")]
func Copy(): int {
    return 1
}
""", profile: "systems");

        Assert.Single(report.TrustedSites);
        Assert.Contains(report.Findings, f => f.Code == "NSYS100" && f.Severity == "error");
    }

    [Fact]
    public void CheckCommand_SystemsReport_EmitsVersionedJson()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
  systems:
    mode: strict
""", """
func Make(): Box {
    return new Box()
}

class Box {}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--systems-report" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check.systemsReport", doc.RootElement.GetProperty("command").GetString());
            Assert.Equal(1, doc.RootElement.GetProperty("systemsReport").GetProperty("schemaVersion").GetInt32());
            Assert.Contains(doc.RootElement.GetProperty("systemsReport").GetProperty("findings").EnumerateArray(),
                finding => finding.GetProperty("code").GetString() == "NSYS001");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void QueryPerf_ReturnsSystemsFindingAtPosition()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
""", """
func Make(): Box {
    return new Box()
}

class Box {}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                QueryCommand.Execute(new[] { "perf", "--project", tempDir, "--file", "Program.nl", "--pos", "2:12" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("perf", doc.RootElement.GetProperty("command").GetString());
            Assert.Contains(doc.RootElement.GetProperty("facts").EnumerateArray(),
                fact => fact.GetProperty("source").GetString() == "systems"
                        && fact.GetProperty("code").GetString() == "NSYS001");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void QueryTrusted_ReturnsTrustedSites()
    {
        var tempDir = CreateTempProject("""
language:
  profile: systems
  systems:
    mode: audit
""", """
[trusted(reason: "reviewed wrapper", owner: "runtime", review: "SYS-1")]
func Copy(): int {
    return 1
}
""");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                QueryCommand.Execute(new[] { "trusted", "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("trusted", doc.RootElement.GetProperty("command").GetString());
            var site = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("Copy", site.GetProperty("function").GetString());
            Assert.Equal("runtime", site.GetProperty("owner").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void SystemsBenchmark_UsesBenchmarkDotNetForPerformanceAndAllocationCoverage()
    {
        var benchmarkPath = Path.Combine(FindRepoRoot(), "benchmarks", "SystemsHotPathBenchmarks.cs");
        var source = File.ReadAllText(benchmarkPath);

        Assert.Contains("class SystemsHotPathBenchmarks", source, StringComparison.Ordinal);
        Assert.Contains("[MemoryDiagnoser]", source, StringComparison.Ordinal);
        Assert.Contains("[Benchmark(Baseline = true)]", source, StringComparison.Ordinal);
        Assert.Contains("[Benchmark]", source, StringComparison.Ordinal);
        Assert.Contains("NSharpCompiledMethod.Bind<Func<int[], int>>", source, StringComparison.Ordinal);
    }

    [Fact]
    public void SystemsPolicyAttributes_AreCompilerOnlyAndDoNotRequireClrAttributeTypes()
    {
        var source = """
[hot]
func Run(): int {
    return 1
}
""";

        var unit = Parse(source);
        var outputPath = Path.Combine(Path.GetTempPath(), $"SystemsPolicyAttributes_{Guid.NewGuid():N}.dll");
        var assemblyName = $"SystemsPolicyAttributes_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(unit, assemblyName, outputPath);
            compiler.Compile();

            loadContext = new AssemblyLoadContext($"SystemsPolicyAttributes_{Guid.NewGuid():N}", isCollectible: true);
            using var stream = new MemoryStream(File.ReadAllBytes(outputPath));
            var assembly = loadContext.LoadFromStream(stream);
            var method = assembly.GetType("Program")!.GetMethod("Run", BindingFlags.Public | BindingFlags.Static)!;

            Assert.DoesNotContain(method.CustomAttributes,
                attribute => attribute.AttributeType.Name.Contains("hot", StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    [Fact]
    public void StackallocExpression_CompilesToSpan()
    {
        var result = CompileAndInvoke("""
import System

func Run(): int {
    scratch := stackalloc int[4]
    return scratch.Length
}
""", "Run");

        Assert.Equal(4, result);
    }

    private static SystemsReport Analyze(string source, string profile = "default", string mode = "strict")
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-analysis-{Guid.NewGuid():N}");
        var file = Path.Combine(projectRoot, "Program.nl");
        var unit = Parse(source, file);

        var config = ProjectFileParser.CreateDefault("SystemsTest");
        config.Language.Profile = profile;
        config.Language.Systems.Mode = mode;

        return new SystemsAnalyzer(projectRoot, config).Analyze(
            new Dictionary<string, CompilationUnit> { [file] = unit },
            new PerformanceFactStore());
    }

    private static CompilationUnit Parse(string source, string file = "Program.nl")
    {
        var lexer = new Lexer(source, file);
        var parser = new Parser(lexer.Tokenize(), file, source);
        var result = parser.ParseCompilationUnit();

        Assert.NotNull(result.CompilationUnit);
        Assert.DoesNotContain(result.Errors, error => error.Severity == ErrorSeverity.Error);
        return result.CompilationUnit!;
    }

    private static object? CompileAndInvoke(string source, string functionName)
    {
        var unit = Parse(source);
        var outputPath = Path.Combine(Path.GetTempPath(), $"SystemsCompile_{Guid.NewGuid():N}.dll");
        var assemblyName = $"SystemsCompile_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(unit, assemblyName, outputPath);
            compiler.Compile();

            loadContext = new AssemblyLoadContext($"SystemsCompile_{Guid.NewGuid():N}", isCollectible: true);
            using var stream = new MemoryStream(File.ReadAllBytes(outputPath));
            var assembly = loadContext.LoadFromStream(stream);
            var method = assembly.GetType("Program")!.GetMethod(functionName, BindingFlags.Public | BindingFlags.Static)!;
            return method.Invoke(null, null);
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static string CreateTempProject(string languageConfig, string program)
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-systems-cli-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "project.yml"), $"""
name: SystemsCliTest
outputType: library
targetFramework: net10.0
{languageConfig}
""");
        File.WriteAllText(Path.Combine(tempDir, "Program.nl"), program);
        return tempDir;
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action)
    {
        var originalOut = Console.Out;
        var originalErr = Console.Error;
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
            Console.SetError(originalErr);
        }
    }

    private static string FindRepoRoot()
    {
        var dir = Directory.GetCurrentDirectory();
        while (true)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            var parent = Directory.GetParent(dir);
            if (parent == null)
            {
                throw new DirectoryNotFoundException("Could not find repository root.");
            }

            dir = parent.FullName;
        }
    }
}

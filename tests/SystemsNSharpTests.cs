using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.RegularExpressions;
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
    public void TrustedMemorySafeWrapper_AllowsRestrictedUnsafeBlock()
    {
        var report = Analyze("""
[memory(safe)]
[trusted(reason: "bounds checked by caller", owner: "runtime-core", review: "SYS-1")]
func Copy(): int {
    unsafe {
        value := 1
    }
    return 1
}
""", profile: "systems");

        Assert.Single(report.TrustedSites);
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS100");
    }

    [Fact]
    public void HotFunction_PropagatesCalleeAllocationWithCallPath()
    {
        var report = Analyze("""
[hot]
func Caller(): int {
    return Cold()
}

func Cold(): int {
    value := new Box()
    return 1
}

class Box {}
""");

        var finding = Assert.Single(report.Findings,
            f => f.Code == "NSYS010" && f.Message.Contains("Cold", StringComparison.Ordinal));
        Assert.Equal(new[] { "Caller", "Cold" }, finding.CallPath);
    }

    [Fact]
    public void RefStruct_AllowsRefLikeFieldsButOrdinaryStructDoesNot()
    {
        var report = Analyze("""
import System

ref struct Reader {
    buf: ReadOnlySpan<byte>
}

struct Holder {
    buf: ReadOnlySpan<byte>
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS080" && f.Function == "Holder");
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS080" && f.Function == "Reader");
    }

    [Fact]
    public void LifetimeSyntax_ParsesScopedParameterAndReturnLifetime()
    {
        var unit = Parse("""
import System

func Slice<'a>(buf: ReadOnlySpan<byte> scoped 'a, start: int, len: int): ReadOnlySpan<byte> returns 'a {
    return buf.Slice(start, len)
}
""");

        var function = Assert.IsType<FunctionDeclaration>(Assert.Single(unit.Declarations.OfType<FunctionDeclaration>()));
        Assert.Equal("'a", Assert.Single(function.TypeParameters!).Name);
        Assert.Equal("'a", function.ReturnLifetime);
        var parameter = Assert.Single(function.Parameters.Where(p => p.Name == "buf"));
        Assert.True(parameter.IsScoped);
        Assert.Equal("'a", parameter.Lifetime);
    }

    [Fact]
    public void HotRefLikeReturn_RequiresReturnLifetime()
    {
        var report = Analyze("""
import System

[hot]
func Slice(buf: ReadOnlySpan<byte>): ReadOnlySpan<byte> {
    return buf.Slice(0, 1)
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS080" && f.Effect == "lifetime");
    }

    [Fact]
    public void Stackalloc_UsesConfiguredBudget()
    {
        var report = Analyze("""
func Scratch(): int {
    scratch := stackalloc byte[65]
    return scratch.Length
}
""", profile: "systems", configure: config => config.Language.Systems.StackBudgetBytes = 64);

        Assert.Contains(report.Findings, f => f.Code == "NSYS080" && f.Message.Contains("64", StringComparison.Ordinal));
    }

    [Fact]
    public void PoolRent_MustBeReturnedOnObviousLexicalPath()
    {
        var report = Analyze("""
func Lease(): int {
    buffer := ArrayPool.Shared.Rent(128)
    return 1
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS130" && f.Effect == "pool");
    }

    [Fact]
    public void SystemsStrict_DisposableResourceMustBeDisposed()
    {
        var report = Analyze("""
func Open(): int {
    stream := alloc new FileStream()
    return 1
}

class FileStream {}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS090" && f.Effect == "resource");
    }

    [Fact]
    public void SystemsStrict_DisposeCallSatisfiesObviousResourceOwnership()
    {
        var report = Analyze("""
func Open(): int {
    stream := alloc new FileStream()
    stream.Dispose()
    return 1
}

class FileStream {}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS090" && f.Effect == "resource");
    }

    [Fact]
    public void BoundaryExceptionControlFlow_IsReportedWithoutBlocking()
    {
        var report = Analyze("""
[boundary]
func Load(): Result<int, string> {
    try {
        return Ok(1)
    } catch ex: Exception {
        return Err("failed")
    }
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS120" && f.Effect == "throw" && f.Severity == "warning");
        Assert.DoesNotContain(report.Findings, f => f.Severity == "error");
    }

    [Fact]
    public void UnsupportedConcurrencyPrimitive_FailsClosedInHotCode()
    {
        var report = Analyze("""
[hot]
func ReadCounter(value: int): int {
    return Interlocked.Read(value)
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS140" && f.Effect == "concurrency");
    }

    [Fact]
    public void HotBoundarySurface_RejectsSystemsHostileTypes()
    {
        var report = Analyze("""
import System.Collections.Generic

[hot]
func Count(values: IEnumerable<int>): int {
    return 0
}
""");

        Assert.Contains(report.Findings, f => f.Code == "NSYS070" && f.Effect == "boundaryLeak");
    }

    [Fact]
    public void FunctionLevelAllow_RequiresReasonAndPublicOwner()
    {
        var report = Analyze("""
[allow(alloc)]
public func Visible(): int {
    return 1
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS150" && f.Message.Contains("reason", StringComparison.Ordinal));
        Assert.Contains(report.Findings, f => f.Code == "NSYS150" && f.Message.Contains("owner", StringComparison.Ordinal));
    }

    [Fact]
    public void ResultHelpers_AreKnownInHotResultContext()
    {
        var report = Analyze("""
enum ParseError {
    Bad
}

[hot]
func Parse(value: int): Result<int, ParseError> {
    if value == 0 {
        return Err(ParseError.Bad)
    }
    return Ok(value)
}
""", profile: "systems");

        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS050" && (f.Message.Contains("Ok", StringComparison.Ordinal) || f.Message.Contains("Err", StringComparison.Ordinal)));
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS070");
    }

    [Fact]
    public void ResultValue_MustBeUsedOnSystemsPaths()
    {
        var report = Analyze("""
enum ParseError {
    Bad
}

func Parse(value: int): Result<int, ParseError> {
    return Ok(value)
}

func Run(): int {
    Parse(1)
    return 0
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS160" && f.Effect == "resultMustUse");
    }

    [Fact]
    public void ResultRuntimeAbi_IsAllocationFreeTaggedStruct()
    {
        var ok = NSharpLang.Runtime.Result<int, string>.Ok(42);
        var err = NSharpLang.Runtime.Result<int, string>.Err("bad");

        Assert.True(ok.IsOk);
        Assert.False(ok.IsErr);
        Assert.True(ok.TryGetOk(out var value));
        Assert.Equal(42, value);
        Assert.False(ok.TryGetErr(out _));

        Assert.True(err.IsErr);
        Assert.False(err.IsOk);
        Assert.True(err.TryGetErr(out var error));
        Assert.Equal("bad", error);
        Assert.False(err.TryGetOk(out _));

        Assert.True(typeof(NSharpLang.Runtime.Result<int, string>).IsValueType);
        Assert.True(typeof(NSharpLang.Runtime.Result<int, string>).IsAssignableTo(typeof(IEquatable<NSharpLang.Runtime.Result<int, string>>)));
    }

    [Fact]
    public void SidecarHotSummary_FailsClosedForHotUnlessPolicyAllowsIt()
    {
        var source = """
[hot]
func Run(): int {
    return External.Fast()
}
""";

        var denied = AnalyzeWithSidecar(source, allowHotSidecars: false);
        Assert.Contains(denied.Findings, f => f.Code == "NSYS050" && f.Message.Contains("sidecar", StringComparison.Ordinal));

        var allowed = AnalyzeWithSidecar(source, allowHotSidecars: true);
        Assert.DoesNotContain(allowed.Findings, f => f.Code == "NSYS050");
    }

    [Fact]
    public void SidecarHotSummary_MissingIdentityReportsEffectDrift()
    {
        var report = AnalyzeWithSidecarDocument("""
[hot]
func Run(): int {
    return External.Fast()
}
""", """
{
  "schemaVersion": 1,
  "entries": [
    {
      "schemaVersion": 1,
      "assemblyIdentity": "External",
      "targetFramework": "*",
      "method": "External.Fast",
      "source": "sidecar",
      "effects": {
        "aotSafe": true,
        "trimSafe": true
      }
    }
  ]
}
""", allowHotSidecars: true);

        Assert.Contains(report.Findings, f => f.Code == "NSYS150" && f.Effect == "effectDrift");
    }

    [Fact]
    public void SourceGeneratedJsonBoundary_IsAotSafeButReportsAllocation()
    {
        var report = Analyze("""
import System.Text.Json
import System.Text.Json.Serialization

record Payload {
    Value: int
}

[JsonSerializable(typeof(Payload))]
partial class PayloadJsonContext : JsonSerializerContext {
}

[boundary]
func Emit(payload: Payload): string {
    return JsonSerializer.Serialize(payload, PayloadJsonContext.Default.Payload)
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS001" && f.Effect == "allocation" && f.Severity == "warning");
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS060");
        Assert.DoesNotContain(report.Findings, f => f.Code == "NSYS050");
    }

    [Fact]
    public void ReflectionJsonBoundary_IsTargetQualifiedAotBlocker()
    {
        var report = Analyze("""
import System.Text.Json

record Payload {
    Value: int
}

[boundary]
func Emit(payload: Payload): string {
    return JsonSerializer.Serialize(payload)
}
""", profile: "systems");

        Assert.Contains(report.Findings, f => f.Code == "NSYS060" && f.Effect == "aot" && f.Severity == "warning");
    }

    [Fact]
    public void AcceptanceGauntlet_FixturesHaveArtifactsAndExpectedDiagnostics()
    {
        var root = Path.Combine(FindRepoRoot(), "tests", "fixtures", "systems-gauntlet");
        var cases = Directory.GetDirectories(root).OrderBy(path => path, StringComparer.Ordinal).ToArray();

        Assert.Equal(10, cases.Length);
        foreach (var dir in cases)
        {
            var sourcePath = Path.Combine(dir, "sample.nl");
            var diagnosticsPath = Path.Combine(dir, "diagnostics.golden.txt");
            Assert.True(File.Exists(sourcePath), $"{dir} is missing sample.nl");
            Assert.True(File.Exists(Path.Combine(dir, "systems.golden.json")), $"{dir} is missing systems.golden.json");
            Assert.True(File.Exists(diagnosticsPath), $"{dir} is missing diagnostics.golden.txt");
            Assert.True(File.Exists(Path.Combine(dir, "perf-report.golden.json")), $"{dir} is missing perf-report.golden.json");
            Assert.True(File.Exists(Path.Combine(dir, "interop.golden.txt")), $"{dir} is missing interop.golden.txt");

            var report = Analyze(File.ReadAllText(sourcePath), profile: "systems");
            var expectedCodes = Regex.Matches(File.ReadAllText(diagnosticsPath), "NSYS\\d{3}")
                .Select(match => match.Value)
                .Distinct(StringComparer.Ordinal)
                .ToArray();

            foreach (var code in expectedCodes)
                Assert.Contains(report.Findings, finding => finding.Code == code);
        }
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
            Assert.False(doc.RootElement.GetProperty("systemsReport").GetProperty("aot").GetProperty("nativeImageEmitted").GetBoolean());
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

        var resultBenchmark = File.ReadAllText(Path.Combine(FindRepoRoot(), "benchmarks", "SystemsResultBenchmarks.cs"));
        Assert.Contains("class SystemsResultBenchmarks", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("[MemoryDiagnoser]", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("Result<int, int>", resultBenchmark, StringComparison.Ordinal);
        Assert.Contains("[Benchmark(Baseline = true)]", resultBenchmark, StringComparison.Ordinal);
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

    private static SystemsReport Analyze(string source, string profile = "default", string mode = "strict", Action<ProjectConfig>? configure = null)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-analysis-{Guid.NewGuid():N}");
        var file = Path.Combine(projectRoot, "Program.nl");
        var unit = Parse(source, file);

        var config = ProjectFileParser.CreateDefault("SystemsTest");
        config.Language.Profile = profile;
        config.Language.Systems.Mode = mode;
        configure?.Invoke(config);

        return new SystemsAnalyzer(projectRoot, config).Analyze(
            new Dictionary<string, CompilationUnit> { [file] = unit },
            new PerformanceFactStore());
    }

    private static SystemsReport AnalyzeWithSidecar(string source, bool allowHotSidecars)
        => AnalyzeWithSidecarDocument(source, """
{
  "schemaVersion": 1,
  "entries": [
    {
      "schemaVersion": 1,
      "assemblyIdentity": "External",
      "targetFramework": "*",
      "method": "External.Fast",
      "source": "sidecar",
      "effects": {
        "aotSafe": true,
        "trimSafe": true
      },
      "bodyIdentity": "test-body"
    }
  ]
}
""", allowHotSidecars);

    private static SystemsReport AnalyzeWithSidecarDocument(string source, string sidecarJson, bool allowHotSidecars)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-systems-sidecar-{Guid.NewGuid():N}");
        Directory.CreateDirectory(projectRoot);
        try
        {
            var sidecarPath = Path.Combine(projectRoot, "external.hotsummary.json");
            File.WriteAllText(sidecarPath, sidecarJson);

            var file = Path.Combine(projectRoot, "Program.nl");
            var unit = Parse(source, file);
            var config = ProjectFileParser.CreateDefault("SystemsSidecar");
            config.Language.Profile = "systems";
            config.Language.Systems.HotSummaryFiles.Add("external.hotsummary.json");
            config.Language.Systems.AllowHotSidecars = allowHotSidecars;

            return new SystemsAnalyzer(projectRoot, config).Analyze(
                new Dictionary<string, CompilationUnit> { [file] = unit },
                new PerformanceFactStore());
        }
        finally
        {
            Directory.Delete(projectRoot, recursive: true);
        }
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

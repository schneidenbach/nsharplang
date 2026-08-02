using System;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class ColumnarDeclineDiagnosticsTests
{
    private const string DeclineLogEnvVar = "NSHARP_COLUMNAR_DECLINE_LOG";

    [Fact]
    public void CompileToIlAssembly_SingleFileDeclineReportsReasonAndSpan() => InTempDir(tempDir =>
    {
        WriteProject(tempDir, "SingleDecline");
        var programPath = Path.Combine(tempDir, "Program.nl");
        File.WriteAllText(programPath, """
func TypeName(value: string): string? {
    return value.GetType().AssemblyQualifiedName
}
""");

        var result = CompileProject(tempDir, "SingleDecline");
        var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

        Assert.False(result.Success);
        Assert.Contains(
            "Declined at emit.return.expression: return expression could not be emitted in 'TypeName' (Program.nl:2:12).", error.Message);
        Assert.Equal(Path.GetFullPath(programPath), Path.GetFullPath(error.FileName!));
        Assert.Equal((2, 12, 37), (error.Line, error.Column, error.Length));
    });

    [Fact]
    public void CompileToIlAssembly_TwoFileDeclineMapsMergedOffsetToOwningFile() => InTempDir(tempDir =>
    {
        WriteProject(tempDir, "TwoFileDecline");
        var firstPath = Path.Combine(tempDir, "First.nl");
        var secondPath = Path.Combine(tempDir, "Second.nl");
        File.WriteAllText(firstPath, """
func Keep(): int {
    return 1
}
""");
        File.WriteAllText(secondPath, """
func TypeName(value: string): string? {
    return value.GetType().AssemblyQualifiedName
}
""");

        var result = CompileExplicitProject(tempDir, "TwoFileDecline", firstPath, secondPath);
        var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

        Assert.False(result.Success);
        Assert.Contains("(Second.nl:2:12).", error.Message);
        Assert.Equal(Path.GetFullPath(secondPath), Path.GetFullPath(error.FileName!));
        Assert.Equal((2, 12), (error.Line, error.Column));
    });

    [Fact]
    public void CompileToIlAssembly_TestDeclarationDeclineReportsDeclarationScanReason() => InTempDir(tempDir =>
    {
        // Plain `test "..." { }` declarations now compile through the columnar route; setup blocks
        // remain unmodeled, so they still exercise the declaration-scan decline reporting contract.
        WriteProject(tempDir, "TestDeclDecline");
        var testPath = Path.Combine(tempDir, "Program.tests.nl");
        File.WriteAllText(testPath, """
setup {
    x := 1
}

test "x" {
    assert 1 == 1
}
""");

        var result = CompileExplicitProject(tempDir, "TestDeclDecline", testPath);
        var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

        Assert.False(result.Success);
        Assert.Contains("Declined at parse.declaration-scan:", error.Message);
        Assert.Contains("setup or teardown", error.Message);
        Assert.Equal(Path.GetFullPath(testPath), Path.GetFullPath(error.FileName!));
        Assert.Equal((1, 1), (error.Line, error.Column));
    });

    [Fact]
    public void CompileToIlAssembly_ReceiverStyleGenericFunctionDeclinesInsteadOfCrashing() => InTempDir(tempDir =>
    {
        // Regression: this shape used to throw an unhandled NotImplementedException out of
        // CompileToIlAssembly, which `nlc check` surfaced as the crash envelope "Check failed: The
        // method or operation is not implemented." The persisted-emit generic parameter T does not
        // implement Type.IsSZArray, and the legacy preflight for the `value.ToString()` receiver read
        // the property raw instead of through IsSafeSzArrayType. Until instance calls on generic
        // parameter receivers are modeled, the correct product outcome is this decline.
        WriteProject(tempDir, "ReceiverGenericDecline");
        File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Tag<T>(this value: T, note: string): string {
    return note + value.ToString()
}
""");

        var result = CompileProject(tempDir, "ReceiverGenericDecline");
        var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

        Assert.False(result.Success);
        Assert.Contains("Declined at emit.call.instance-member-unmodeled:", error.Message);
        Assert.Contains("'T.ToString'", error.Message);
    });

    [Fact]
    public void CompileToIlAssembly_DeclineLogEnvVarWritesTraceToStderr() => InTempDir(tempDir =>
    {
        using var declineLog = SetEnvironmentVariable(DeclineLogEnvVar, "1");
        WriteProject(tempDir, "TraceDecline");
        File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func TypeName(value: string): string? {
    return value.GetType().AssemblyQualifiedName
}
""");

        var (_, stderr) = CaptureStderr(() => CompileProject(tempDir, "TraceDecline"));

        Assert.All(
            new[] { "decline site=emit.return.expression", "return expression could not be emitted", "location=Program.nl:2:12" },
            fragment => Assert.Contains(fragment, stderr));
    });

    private static void InTempDir(Action<string> body)
    {
        var tempDir = CreateTempDir();
        try
        {
            body(tempDir);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    private static MultiFileCompilationResult CompileProject(string projectRoot, string assemblyName)
    {
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var compiler = new MultiFileCompiler(projectRoot, config);
        return Compile(compiler, projectRoot, assemblyName);
    }

    private static MultiFileCompilationResult CompileExplicitProject(string projectRoot, string assemblyName, params string[] sourceFiles)
    {
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return Compile(compiler, projectRoot, assemblyName);
    }

    private static MultiFileCompilationResult Compile(MultiFileCompiler compiler, string projectRoot, string assemblyName)
    {
        var outputDir = Path.Combine(projectRoot, "artifacts");
        Directory.CreateDirectory(outputDir);
        return compiler.CompileToIlAssembly(assemblyName, Path.Combine(outputDir, $"{assemblyName}.dll"));
    }

    private static void WriteProject(string projectRoot, string name)
    {
        File.WriteAllText(Path.Combine(projectRoot, "project.yml"), $"""
name: {name}
backend: il
outputType: library
targetFramework: net10.0
""");
    }

    private static string CreateTempDir()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-columnar-decline-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }

    private static (MultiFileCompilationResult Result, string Stderr) CaptureStderr(Func<MultiFileCompilationResult> action)
    {
        var originalError = Console.Error;
        using var stderr = new StringWriter();
        Console.SetError(stderr);

        try
        {
            var result = action();
            return (result, stderr.ToString());
        }
        finally
        {
            Console.SetError(originalError);
        }
    }

    private static IDisposable SetEnvironmentVariable(string name, string? value)
    {
        var previousValue = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
        return new RestoreEnvironmentVariable(name, previousValue);
    }

    private sealed class RestoreEnvironmentVariable(string name, string? previousValue) : IDisposable
    {
        public void Dispose()
        {
            Environment.SetEnvironmentVariable(name, previousValue);
        }
    }
}

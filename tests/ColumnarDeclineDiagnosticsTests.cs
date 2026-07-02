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
    public void CompileToIlAssembly_SingleFileDeclineReportsReasonAndSpan()
    {
        var tempDir = CreateTempDir();
        try
        {
            WriteProject(tempDir, "SingleDecline");
            var programPath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(programPath, """
func TypeName(value: string): string {
    return value.GetType().Name
}
""");

            var result = CompileProject(tempDir, "SingleDecline");
            var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

            Assert.False(result.Success);
            Assert.Contains(
                "Declined at emit.call.instance-member-unmodeled: instance call 'String.GetType' with 0 argument(s) is not modeled in 'TypeName' (Program.nl:2:12).",
                error.Message);
            Assert.Equal(Path.GetFullPath(programPath), Path.GetFullPath(error.FileName!));
            Assert.Equal(2, error.Line);
            Assert.Equal(12, error.Column);
            Assert.Equal(15, error.Length);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompileToIlAssembly_TwoFileDeclineMapsMergedOffsetToOwningFile()
    {
        var tempDir = CreateTempDir();
        try
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
func TypeName(value: string): string {
    return value.GetType().Name
}
""");

            var result = CompileExplicitProject(tempDir, "TwoFileDecline", firstPath, secondPath);
            var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

            Assert.False(result.Success);
            Assert.Contains("(Second.nl:2:12).", error.Message);
            Assert.Equal(Path.GetFullPath(secondPath), Path.GetFullPath(error.FileName!));
            Assert.Equal(2, error.Line);
            Assert.Equal(12, error.Column);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompileToIlAssembly_TestDeclarationDeclineReportsDeclarationScanReason()
    {
        var tempDir = CreateTempDir();
        try
        {
            WriteProject(tempDir, "TestDeclDecline");
            var testPath = Path.Combine(tempDir, "Program.tests.nl");
            File.WriteAllText(testPath, """
test "x" {
    assert 1 == 1
}
""");

            var result = CompileExplicitProject(tempDir, "TestDeclDecline", testPath);
            var error = Assert.Single(result.Errors.Where(error => error.DiagnosticId == "NL103"));

            Assert.False(result.Success);
            Assert.Contains("Declined at parse.declaration-scan:", error.Message);
            Assert.Contains("test, setup, or teardown", error.Message);
            Assert.Equal(Path.GetFullPath(testPath), Path.GetFullPath(error.FileName!));
            Assert.Equal(1, error.Line);
            Assert.Equal(1, error.Column);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompileToIlAssembly_DeclineLogEnvVarWritesTraceToStderr()
    {
        var tempDir = CreateTempDir();
        using var declineLog = SetEnvironmentVariable(DeclineLogEnvVar, "1");
        try
        {
            WriteProject(tempDir, "TraceDecline");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func TypeName(value: string): string {
    return value.GetType().Name
}
""");

            var (_, stderr) = CaptureStderr(() => CompileProject(tempDir, "TraceDecline"));

            Assert.Contains("decline site=emit.call.instance-member-unmodeled", stderr);
            Assert.Contains("String.GetType", stderr);
            Assert.Contains("location=Program.nl:2:12", stderr);
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

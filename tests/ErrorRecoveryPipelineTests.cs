using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Tests;

/// <summary>
/// Regression tests for multi-error reporting across the full compilation pipeline.
/// Verifies that syntax errors in one file do not suppress semantic errors in another,
/// and that mixed syntax + semantic errors are all reported in a single pass.
/// </summary>
public class ErrorRecoveryPipelineTests
{
    #region Single-file: mixed syntax + semantic errors

    [Fact]
    public void Analyzer_CollectsMultipleSemanticErrors()
    {
        // Two distinct semantic errors: undefined variables
        var source = @"
func test() {
    Console.WriteLine(undefinedVar1)
    Console.WriteLine(undefinedVar2)
}";

        var result = ParseAndAnalyze(source);

        Assert.True(result.Errors.Count >= 2,
            $"Expected at least 2 semantic errors, got {result.Errors.Count}: " +
            string.Join("; ", result.Errors.Select(e => e.Message)));
    }

    [Fact]
    public void QueryDiagnostics_MalformedProject_ReturnsSyntaxAndSemanticDiagnosticsWithoutPlaceholderCascade()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: MalformedDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class User {
    Name: string
}

func main() {
    first := 1 +
    Console.WriteLine(undefinedFromQuery)
}
""");

            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(tempDir);
            var diagnostics = service.GetDiagnostics(snapshot, "Program.nl");

            Assert.Contains(diagnostics, diagnostic =>
                diagnostic.Code == "NL102" &&
                diagnostic.Line == 6 &&
                diagnostic.Message.Contains("Expected expression after '+'"));
            Assert.Contains(diagnostics, diagnostic =>
                diagnostic.Code == "NL301" &&
                diagnostic.Message.Contains("undefinedFromQuery"));
            Assert.DoesNotContain(diagnostics, diagnostic =>
                diagnostic.Message.Contains("<error>", StringComparison.Ordinal));
            Assert.True(diagnostics.Count <= 6,
                $"Expected bounded diagnostics, got {diagnostics.Count}: {string.Join("; ", diagnostics.Select(d => $"{d.Code} {d.Message}"))}");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    #endregion

    #region Multi-file: syntax error in one file, semantic error in another

    [Fact]
    public void MultiFileCompiler_SyntaxErrorInOneFile_SemanticErrorInOther_BothReported()
    {
        var tempDir = CreateTempDir();
        try
        {
            // File A: syntax error
            File.WriteAllText(Path.Combine(tempDir, "FileA.nl"), @"
func broken() {
    let x: int = @@
}
");
            // File B: semantic error (undefined variable — no syntax error)
            File.WriteAllText(Path.Combine(tempDir, "FileB.nl"), @"
func valid_syntax_but_bad_semantics() {
    Console.WriteLine(thisVarDoesNotExist)
}
");

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var errors = compiler.AllErrors.ToList();

            // Should have errors from BOTH files
            Assert.True(errors.Count >= 2,
                $"Expected errors from both files, got {errors.Count}: " +
                string.Join("; ", errors.Select(e => $"[{e.FileName}:{e.Line}] {e.Message}")));

            // Verify at least one error references each file
            var fileAErrors = errors.Where(e => e.FileName?.Contains("FileA") == true).ToList();
            var fileBErrors = errors.Where(e => e.FileName?.Contains("FileB") == true).ToList();

            Assert.True(fileAErrors.Count >= 1,
                "Expected at least 1 error from FileA (syntax error)");
            Assert.True(fileBErrors.Count >= 1,
                $"Expected at least 1 error from FileB (semantic error), got {fileBErrors.Count}. " +
                $"All errors: {string.Join("; ", errors.Select(e => $"[{e.FileName}:{e.Line}] {e.Message}"))}");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllFilesParsedCleanly_AllSemanticErrorsReported()
    {
        var tempDir = CreateTempDir();
        try
        {
            // File A: semantic error
            File.WriteAllText(Path.Combine(tempDir, "FileA.nl"), @"
func funcA() {
    Console.WriteLine(undefinedA)
}
");
            // File B: semantic error
            File.WriteAllText(Path.Combine(tempDir, "FileB.nl"), @"
func funcB() {
    Console.WriteLine(undefinedB)
}
");

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var errors = compiler.AllErrors.ToList();

            // Should have errors from BOTH files
            var fileAErrors = errors.Where(e => e.FileName?.Contains("FileA") == true).ToList();
            var fileBErrors = errors.Where(e => e.FileName?.Contains("FileB") == true).ToList();

            Assert.True(fileAErrors.Count >= 1, "Expected at least 1 error from FileA");
            Assert.True(fileBErrors.Count >= 1, "Expected at least 1 error from FileB");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CircularFileImports_ReportOneBoundedCycleDiagnostic()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "A.nl"), """
import "B"

class A {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "B.nl"), """
import "C"

class B {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "C.nl"), """
import "A"

class C {
}
""");

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var cycle = Assert.Single(compiler.AllErrors,
                error => error.Code == ErrorCode.CircularImport);
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", cycle.Message);
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", cycle.HumanExplanation);
            Assert.Contains("Import path: A.nl -> B.nl -> C.nl -> A.nl", cycle.ContextualHint);
            Assert.Contains("Move shared types", cycle.Suggestion);
            Assert.EndsWith("C.nl", cycle.FileName);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_TwoFileCircularImports_DeduplicatesAnalyzerCycleDiagnostics()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "A.nl"), """
import "B"

class A {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "B.nl"), """
import "A"

class B {
}
""");

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var cycle = Assert.Single(compiler.AllErrors,
                error => error.Code == ErrorCode.CircularImport);
            Assert.Contains("A.nl -> B.nl -> A.nl", cycle.Message);
            Assert.Contains("Import path: A.nl -> B.nl -> A.nl", cycle.ContextualHint);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_LongCircularFileImports_BoundsDiagnosticCyclePath()
    {
        var tempDir = CreateTempDir();
        try
        {
            const int fileCount = 12;
            for (var i = 0; i < fileCount; i++)
            {
                var current = $"F{i:00}";
                var next = $"F{(i + 1) % fileCount:00}";
                File.WriteAllText(Path.Combine(tempDir, $"{current}.nl"), $$"""
import "{{next}}"

class {{current}} {
}
""");
            }

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var cycle = Assert.Single(compiler.AllErrors,
                error => error.Code == ErrorCode.CircularImport);
            Assert.Contains("F00.nl -> F01.nl -> F02.nl -> F03.nl -> F04.nl -> F05.nl", cycle.Message);
            Assert.Contains("... (4 more imports) -> F10.nl -> F11.nl -> F00.nl", cycle.Message);
            Assert.DoesNotContain("F06.nl -> F07.nl -> F08.nl -> F09.nl", cycle.Message);
            Assert.Contains("... (4 more imports)", cycle.ContextualHint);
            Assert.Contains("Move shared types", cycle.Suggestion);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_DenseCircularFileImports_BoundsDiagnosticCount()
    {
        var tempDir = CreateTempDir();
        try
        {
            const int fileCount = 8;
            for (var i = 0; i < fileCount; i++)
            {
                var imports = Enumerable.Range(0, fileCount)
                    .Where(next => next != i)
                    .Select(next => $"import \"F{next:00}\"");
                File.WriteAllText(Path.Combine(tempDir, $"F{i:00}.nl"), $$"""
{{string.Join("\n", imports)}}

class F{{i:00}} {
}
""");
            }

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var cycles = compiler.AllErrors
                .Where(error => error.Code == ErrorCode.CircularImport)
                .ToList();
            Assert.NotEmpty(cycles);
            Assert.True(cycles.Count <= 20, $"Expected bounded cycle diagnostics, got {cycles.Count}.");
            Assert.All(cycles, cycle => Assert.Contains(" -> ", cycle.Message));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CircularFileImports_UsesSourceTextOverridesAndImportCasing()
    {
        var tempDir = CreateTempDir();
        try
        {
            var aPath = Path.Combine(tempDir, "A.nl");
            var bPath = Path.Combine(tempDir, "B.nl");
            var overrides = new Dictionary<string, string>
            {
                [aPath] = """
import "b"

class A {
}
""",
                [bPath] = """
import "A"

class B {
}
"""
            };

            var compiler = new MultiFileCompiler(tempDir, ProjectFileParser.CreateDefault(), overrides);
            compiler.CompileForAnalysis();

            var cycle = Assert.Single(compiler.AllErrors,
                error => error.Code == ErrorCode.CircularImport);
            Assert.Contains("A.nl -> B.nl -> A.nl", cycle.Message);
            Assert.Equal("import \"A\"", cycle.SourceSnippet);
            Assert.DoesNotContain(compiler.AllErrors, error => error.Code == ErrorCode.ImportNotFound);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CircularFileImports_CrLfSourceSnippetHasNoTrailingCarriageReturn()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(
                Path.Combine(tempDir, "A.nl"),
                string.Join("\r\n", new[]
                {
                    "import \"B\"",
                    "",
                    "class A {",
                    "}"
                }));
            File.WriteAllText(
                Path.Combine(tempDir, "B.nl"),
                string.Join("\r\n", new[]
                {
                    "import \"A\"",
                    "",
                    "class B {",
                    "}"
                }));

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var cycle = Assert.Single(compiler.AllErrors,
                error => error.Code == ErrorCode.CircularImport);
            Assert.Equal("import \"A\"", cycle.SourceSnippet);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompileForAnalysis_SyntaxErrorInOneFile_StillReportsSemanticErrors()
    {
        var tempDir = CreateTempDir();
        try
        {
            // File A: syntax error
            File.WriteAllText(Path.Combine(tempDir, "FileA.nl"), @"
func broken() {
    let x: int = @@
}
");
            // File B: valid syntax, semantic error
            File.WriteAllText(Path.Combine(tempDir, "FileB.nl"), @"
func valid_syntax() {
    Console.WriteLine(noSuchVariable)
}
");

            var compiler = new MultiFileCompiler(tempDir);
            compiler.CompileForAnalysis();

            var errors = compiler.AllErrors.ToList();
            var fileAErrors = errors.Where(e => e.FileName?.Contains("FileA") == true).ToList();
            var fileBErrors = errors.Where(e => e.FileName?.Contains("FileB") == true).ToList();

            Assert.True(fileAErrors.Count >= 1, "Expected syntax errors from FileA");
            Assert.True(fileBErrors.Count >= 1,
                $"Expected semantic errors from FileB, got {fileBErrors.Count}. " +
                $"All errors: {string.Join("; ", errors.Select(e => $"[{e.FileName}:{e.Line}] {e.Message}"))}");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    #endregion

    #region Parser always produces CompilationUnit

    #endregion

    #region Helpers

    private static AnalysisResult ParseAndAnalyze(string source)
    {
        var parseResult = ColumnarParserRecovery.ParseFileAst(source, "test.nl");

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(parseResult.CompilationUnit!);
    }

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-errrecovery-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    #endregion
}

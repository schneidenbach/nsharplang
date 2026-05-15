using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;

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
    public void AnalyzeFile_ReportsBothSyntaxAndSemanticErrors()
    {
        // File with a parse error in one function and a semantic error in another
        var tempDir = CreateTempDir();
        try
        {
            var filePath = Path.Combine(tempDir, "Mixed.nl");
            File.WriteAllText(filePath, @"
func broken() {
    let x: int = @@
}

func semantic_error() {
    Console.WriteLine(doesNotExist)
}
");
            var service = new CodeIntelligenceService();
            var snapshot = service.AnalyzeFile(filePath);

            // Should have BOTH parse errors AND semantic errors
            var parseErrors = snapshot.Errors.Where(e =>
                e.Code == ErrorCode.InvalidSyntax || e.Code == ErrorCode.ExpectedToken ||
                e.Code == ErrorCode.UnexpectedToken).ToList();
            var semanticErrors = snapshot.Errors.Where(e =>
                e.Code == ErrorCode.UndefinedVariable &&
                e.Message.Contains("doesNotExist")).ToList();

            Assert.True(snapshot.Errors.Count >= 2,
                $"Expected at least 2 total errors (syntax + semantic), got {snapshot.Errors.Count}: " +
                string.Join("; ", snapshot.Errors.Select(e => $"[{e.Code}] {e.Message}")));

            // Lock in the headline behavior: BOTH syntax and semantic errors present
            Assert.True(parseErrors.Count >= 1,
                $"Expected at least 1 parse error, got {parseErrors.Count}: " +
                string.Join("; ", snapshot.Errors.Select(e => $"[{e.Code}] {e.Message}")));
            Assert.True(semanticErrors.Count >= 1,
                $"Expected at least 1 semantic error, got {semanticErrors.Count}: " +
                string.Join("; ", snapshot.Errors.Select(e => $"[{e.Code}] {e.Message}")));
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
    public void Compile_SyntaxErrorInOneFile_StillReportsSemanticErrors()
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
            var result = compiler.ExportToCSharp();

            Assert.False(result.Success);

            var errors = result.Errors.ToList();
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

    [Fact]
    public void Parser_AlwaysProducesCompilationUnit_EvenWithErrors()
    {
        var sources = new[]
        {
            "func test() { @@ }",
            "func test() { let x: int = @@ }",
            "func test() { x. }",
            @"func test() {
    let x = 5

class Foo { name: string }",
            "@@ ## !! %%",
        };

        foreach (var source in sources)
        {
            var tokens = new Lexer(source, "test.nl").Tokenize();
            var parser = new Parser(tokens, "test.nl", source);
            var result = parser.ParseCompilationUnit();

            Assert.NotNull(result.CompilationUnit);
        }
    }

    #endregion

    #region Helpers

    private static AnalysisResult ParseAndAnalyze(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var parseResult = parser.ParseCompilationUnit();

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

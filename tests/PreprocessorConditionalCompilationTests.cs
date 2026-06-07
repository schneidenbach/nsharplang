using System;
using System.IO;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// End-to-end coverage proving conditional compilation actually affects the emitted
/// program: a project with <c>defines:</c> in project.yml is compiled to IL and run,
/// and the captured output shows that only the live <c>#if</c>/<c>#else</c> branches
/// execute. This is the behavior from the original bug report (both branches ran).
/// </summary>
[Collection("ProcessState")]
public class PreprocessorConditionalCompilationTests
{
    [Fact]
    public void ConditionalCompilation_EmitsOnlyLiveBranches_BasedOnProjectDefines()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CondCompile
backend: il
outputType: exe
targetFramework: net10.0
defines:
  - FEATURE_X
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    #if FEATURE_X
    print "feature-on"
    #else
    print "feature-off"
    #endif

    #if MISSING_SYM
    print "missing-on"
    #else
    print "missing-off"
    #endif
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "CondCompile.dll");
            var result = compiler.CompileToIlAssembly("CondCompile", outputPath);

            Assert.True(result.Success);
            Assert.True(File.Exists(outputPath));

            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);

            // Defined symbol: #if body included, #else excluded.
            Assert.Contains("feature-on", runResult.Stdout);
            Assert.DoesNotContain("feature-off", runResult.Stdout);

            // Undefined symbol: #if body excluded, #else included.
            Assert.Contains("missing-off", runResult.Stdout);
            Assert.DoesNotContain("missing-on", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    private static string CreateTempDir()
    {
        var dir = Path.Combine(Path.GetTempPath(), $"nlc-cond-{Guid.NewGuid():N}");
        Directory.CreateDirectory(dir);
        return dir;
    }
}

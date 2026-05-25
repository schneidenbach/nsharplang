using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class CheckCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var useText = args.Contains("--text");
        var projectDir = GetProjectDir(args);

        if (!Directory.Exists(projectDir))
        {
            return EmitError(useText, $"Directory not found: {projectDir}", projectDir);
        }

        var projectYmlPath = Path.Combine(projectDir, "project.yml");

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var projectConfig = ProjectFileParser.ParseFromDirectory(projectDir);
            if (projectConfig != null)
            {
                CompilationReferenceResolver.AddResolvedDllReferences(projectDir, projectConfig);
            }

            var backend = ResolveCompilationBackend(args, projectConfig);
            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(projectDir, projectConfig);
            var diagnostics = service.GetDiagnostics(snapshot);
            diagnostics.AddRange(GetLintDiagnostics(projectDir, snapshot.SourceFiles));
            diagnostics = DeduplicateAndSort(diagnostics);

            // If analysis found no errors AND this is a proper project (has project.yml),
            // verify the IL backend can emit the assembly successfully. Non-project
            // directories (standalone .nl files) skip this because they aren't meant
            // to be compiled as a single project.
            if (!diagnostics.Any(d => d.Severity == "error")
                && snapshot.SourceFiles.Count > 0
                && File.Exists(projectYmlPath))
            {
                var verificationDiagnostics = VerifyBackendOutput(projectDir, backend, projectConfig);
                if (verificationDiagnostics.Count > 0)
                {
                    diagnostics.AddRange(verificationDiagnostics);
                    diagnostics = DeduplicateAndSort(diagnostics);
                }
            }

            if (useText)
            {
                var errors = diagnostics.Count(d => d.Severity == "error");
                var warnings = diagnostics.Count(d => d.Severity == "warning");
                if (errors == 0 && warnings == 0)
                {
                    var fileCount = snapshot.SourceFiles.Count;
                    Console.Error.WriteLine($"  Checked {fileCount} file{(fileCount == 1 ? "" : "s")} — no errors. [{FormatElapsed(sw.Elapsed)}]");
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(diagnostics));
                    Console.Error.WriteLine($"  Checked in {FormatElapsed(sw.Elapsed)}");
                }
            }
            else
            {
                Console.Write(OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count));
            }

            return diagnostics.Any(d => d.Severity == "error") ? 1 : 0;
        }
        catch (Exception ex)
        {
            if (useText)
                Console.Error.WriteLine($"  Check failed in {FormatElapsed(sw.Elapsed)}");
            return EmitError(useText, $"Check failed: {ex.Message}", projectDir);
        }
    }

    /// <summary>
    /// Verifies that the configured backend can emit a valid assembly.
    /// </summary>
    private static List<DiagnosticResult> VerifyBackendOutput(string projectDir, CompilationBackend backend, ProjectConfig? config)
    {
        if (backend != CompilationBackend.Il)
        {
            throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
        }

        return VerifyIlOutput(projectDir, config);
    }

    private static List<DiagnosticResult> VerifyIlOutput(string projectDir, ProjectConfig? config)
    {
        var results = new List<DiagnosticResult>();
        config ??= ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault();
        var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-check-il-{Guid.NewGuid():N}");

        try
        {
            Directory.CreateDirectory(tempDir);
            var outputPath = Path.Combine(tempDir, $"{CompilationReferenceResolver.GetProjectAssemblyName(projectDir, config)}.dll");
            var compiler = new MultiFileCompiler(projectDir, config);
            var compileResult = compiler.CompileToIlAssembly(
                CompilationReferenceResolver.GetProjectAssemblyName(projectDir, config),
                outputPath);

            if (!compileResult.Success)
            {
                foreach (var error in compileResult.Errors.Where(e => e.Severity == ErrorSeverity.Error))
                {
                    var relativeFile = error.FileName != null
                        ? NormalizePath(Path.GetRelativePath(projectDir, error.FileName))
                        : "unknown";
                    results.Add(new DiagnosticResult(
                        error.DiagnosticId,
                        "error",
                        error.Message,
                        relativeFile,
                        error.Line,
                        error.Column,
                        error.Length,
                        error.SourceSnippet,
                        error.HumanExplanation,
                        error.Suggestion ?? FormatSuggestions(error.Suggestions),
                        error.ContextualHint,
                        error.ExpectedType,
                        error.ActualType,
                        error.DocsUrl));
                }
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { /* best effort */ }
        }

        return results;
    }

    private static string? FormatSuggestions(IReadOnlyList<string>? suggestions)
    {
        if (suggestions == null || suggestions.Count == 0) return null;
        return string.Join("; ", suggestions);
    }

    private static List<DiagnosticResult> DeduplicateAndSort(List<DiagnosticResult> diagnostics)
    {
        return diagnostics
            .GroupBy(d => (d.Code, d.File, d.Line, d.Column, d.Message))
            .Select(group => group.First())
            .OrderBy(d => d.File)
            .ThenBy(d => d.Line)
            .ThenBy(d => d.Column)
            .ToList();
    }

    private static List<DiagnosticResult> GetLintDiagnostics(string projectDir, IReadOnlyList<string> sourceFiles)
    {
        var results = new List<DiagnosticResult>();

        foreach (var filePath in sourceFiles)
        {
            string source;
            try
            {
                source = File.ReadAllText(filePath);
            }
            catch
            {
                continue;
            }

            var lexer = new Lexer(source, filePath);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, filePath, source);
            var parseResult = parser.ParseCompilationUnit();
            if (parseResult.CompilationUnit == null)
                continue;

            var fileDir = Path.GetDirectoryName(filePath) ?? projectDir;
            var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
            var diagnostics = linter.Lint(parseResult.CompilationUnit, filePath, source);

            foreach (var diagnostic in diagnostics)
            {
                results.Add(new DiagnosticResult(
                    diagnostic.Code,
                    diagnostic.Severity switch
                    {
                        DiagnosticSeverity.Error => "error",
                        DiagnosticSeverity.Warning => "warning",
                        _ => "info"
                    },
                    diagnostic.Message,
                    NormalizePath(Path.GetRelativePath(projectDir, filePath)),
                    diagnostic.Location.Line,
                    diagnostic.Location.Column,
                    1,
                    ExtractSourceLine(source, diagnostic.Location.Line),
                    null,
                    diagnostic.Suggestion,
                    null,
                    null,
                    null,
                    null));
            }
        }

        return results;
    }

    public static int ShowHelp()
    {
        Console.WriteLine(@"N# Type Check

Usage: nlc check [options] [project-dir]

Verifies your N# project compiles without errors. Runs semantic analysis,
linting, and IL backend verification.

Options:
  --backend <mode>  Compilation backend: il
  --json        Output as JSON (default)
  --text        Output as human-readable diagnostics
  --project     Project root directory (default: current directory)
  --help, -h    Show this help text

Examples:
  nlc check
  nlc check --backend il
  nlc check --text
  nlc check --project examples/16-task-cli

Exit codes:
  0  No errors found
  1  One or more errors detected");

        return 0;
    }

    private static string GetProjectDir(string[] args)
    {
        var projectOption = GetOption(args, "--project");
        if (!string.IsNullOrWhiteSpace(projectOption))
            return Path.GetFullPath(projectOption);

        var positional = GetFirstPositionalArg(args, Array.Empty<string>());
        return Path.GetFullPath(positional ?? Directory.GetCurrentDirectory());
    }

    private static CompilationBackend ResolveCompilationBackend(string[] args, ProjectConfig? config)
    {
        var backendOption = GetOption(args, "--backend");
        return !string.IsNullOrWhiteSpace(backendOption)
            ? CompilationBackendExtensions.Parse(backendOption)
            : config?.EffectiveBackend ?? CompilationBackend.Il;
    }

    private static string? GetOption(string[] args, string flag)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }

        return null;
    }

    private static string? GetFirstPositionalArg(string[] args, string[] optionsWithValues)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (optionsWithValues.Contains(args[i], StringComparer.Ordinal))
            {
                i++;
                continue;
            }

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return args[i];
        }

        return null;
    }

    private static int EmitError(bool useText, string message, string? projectRoot = null)
    {
        if (useText)
        {
            Console.Error.WriteLine(message);
        }
        else
        {
            Console.Write(OutputFormatter.ErrorToJson("check", message, projectRoot));
        }

        return 1;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed.TotalMinutes >= 1)
            return $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
        return $"{elapsed.TotalSeconds:F1}s";
    }

    private static string? ExtractSourceLine(string source, int line)
    {
        var lines = source.Split('\n');
        return line > 0 && line <= lines.Length ? lines[line - 1] : null;
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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

        try
        {
            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(projectDir);
            var diagnostics = service.GetDiagnostics(snapshot);
            diagnostics.AddRange(GetLintDiagnostics(projectDir, snapshot.SourceFiles));
            diagnostics = diagnostics
                .GroupBy(d => (d.Code, d.File, d.Line, d.Column, d.Message))
                .Select(group => group.First())
                .OrderBy(d => d.File)
                .ThenBy(d => d.Line)
                .ThenBy(d => d.Column)
                .ToList();

            if (useText)
            {
                var errors = diagnostics.Count(d => d.Severity == "error");
                var warnings = diagnostics.Count(d => d.Severity == "warning");
                if (errors == 0 && warnings == 0)
                {
                    var fileCount = snapshot.SourceFiles.Count;
                    Console.Error.WriteLine($"  Checked {fileCount} file{(fileCount == 1 ? "" : "s")} — no errors.");
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(diagnostics));
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
            return EmitError(useText, $"Check failed: {ex.Message}", projectDir);
        }
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
            var diagnostics = linter.Lint(parseResult.CompilationUnit, filePath);

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
        Console.WriteLine(@"N# Fast Type Check

Usage: nlc check [options] [project-dir]

Options:
  --json        Output as JSON (default)
  --text        Output as human-readable diagnostics
  --project     Project root directory (default: current directory)
  --help, -h    Show this help text

Examples:
  nlc check
  nlc check --text
  nlc check --project examples/15-dogfood-project");

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

    private static string? ExtractSourceLine(string source, int line)
    {
        var lines = source.Split('\n');
        return line > 0 && line <= lines.Length ? lines[line - 1] : null;
    }
}

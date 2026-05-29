using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class LintCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var useText = args.Contains("--text");
        var useJson = args.Contains("--json");
        var projectRoot = Path.GetFullPath(GetOption(args, "--project") ?? Directory.GetCurrentDirectory());

        // Filter out flags to get positional file args
        var positionalFiles = args
            .Where(a => !a.StartsWith("-", StringComparison.Ordinal) && a != "help")
            .Where(a => !IsOptionValue(args, a, "--project"))
            .ToArray();

        // Default to JSON when no explicit mode is specified (matches check/fix contract)
        if (!useText && !useJson)
            useJson = true;

        if (!Directory.Exists(projectRoot))
            return EmitError(useJson, $"Directory not found: {projectRoot}", projectRoot);

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            string[] files;
            if (positionalFiles.Length == 0)
            {
                // Use ProjectConfig to discover files, matching check/fix behavior
                // (respects exclude patterns and excludes .tests.nl)
                var config = ProjectFileParser.ParseFromDirectory(projectRoot) ?? ProjectFileParser.CreateDefault();
                files = config.GetSourceFiles(projectRoot, includeTests: false)
                    .Select(f => Path.GetFullPath(f))
                    .ToArray();
            }
            else
            {
                files = positionalFiles
                    .Select(f => Path.GetFullPath(Path.IsPathRooted(f) ? f : Path.Combine(projectRoot, f)))
                    .ToArray();
            }

            if (files.Length == 0)
            {
                if (useJson)
                {
                    Console.Write(OutputFormatter.LintToJson(new List<DiagnosticResult>(), projectRoot, 0));
                    return 0;
                }
                Console.WriteLine("No .nl files found. Ensure you are in a project directory or specify files explicitly.");
                return 0;
            }

            var allDiagnostics = new List<DiagnosticResult>();
            var lintedFileCount = 0;
            var hadErrors = false;

            foreach (var file in files)
            {
                if (!File.Exists(file))
                {
                    hadErrors = true;
                    var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
                    if (useJson)
                    {
                        // Surface as an error diagnostic so JSON consumers see it
                        allDiagnostics.Add(new DiagnosticResult(
                            "LINT", "error", $"File not found: {relativePath}",
                            relativePath, 0, 0, 0, null, null, null, null, null, null, null));
                    }
                    else
                    {
                        Console.Error.WriteLine($"File not found: {file}");
                    }
                    continue;
                }

                try
                {
                    var source = File.ReadAllText(file);
                    var lexer = new Lexer(source, file);
                    var tokens = lexer.Tokenize();
                    var parser = new Parser(tokens, file, source);
                    var parseResult = parser.ParseCompilationUnit();

                    if (parseResult.Errors.Any(e => e.Severity == ErrorSeverity.Error))
                    {
                        hadErrors = true;
                        var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
                        if (useJson)
                        {
                            foreach (var err in parseResult.Errors.Where(e => e.Severity == ErrorSeverity.Error))
                            {
                                allDiagnostics.Add(new DiagnosticResult(
                                    "PARSE", "error", err.Message,
                                    relativePath, err.Line, err.Column, Math.Max(err.Length, 1),
                                    ExtractSourceLine(source, err.Line),
                                    null, null, null, null, null, null));
                            }
                        }
                        else
                        {
                            Console.Error.WriteLine($"Parse errors in {file}: {string.Join(", ", parseResult.Errors.Select(e => e.Message))}");
                        }
                        continue;
                    }

                    var fileDir = Path.GetDirectoryName(Path.GetFullPath(file)) ?? projectRoot;
                    var linterConfig = LinterConfig.FromEditorConfig(fileDir);
                    var linter = new Linter(linterConfig);
                    var diagnostics = linter.Lint(parseResult.CompilationUnit!, file, source);

                    lintedFileCount++;

                    foreach (var diag in diagnostics)
                    {
                        allDiagnostics.Add(new DiagnosticResult(
                            diag.Code,
                            diag.Severity switch
                            {
                                DiagnosticSeverity.Error => "error",
                                DiagnosticSeverity.Warning => "warning",
                                _ => "info"
                            },
                            diag.Message,
                            NormalizePath(Path.GetRelativePath(projectRoot, file)),
                            diag.Location.Line,
                            diag.Location.Column,
                            Math.Max(diag.Length, 1),
                            ExtractSourceLine(source, diag.Location.Line),
                            null,
                            diag.Suggestion,
                            null,
                            null,
                            null,
                            null));
                    }
                }
                catch (Exception ex)
                {
                    hadErrors = true;
                    var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
                    if (useJson)
                    {
                        allDiagnostics.Add(new DiagnosticResult(
                            "LINT", "error", $"Error linting: {ex.Message}",
                            relativePath, 0, 0, 0, null, null, null, null, null, null, null));
                    }
                    else
                    {
                        Console.Error.WriteLine($"Error linting {file}: {ex.Message}");
                    }
                }
            }

            if (useJson)
            {
                Console.Write(OutputFormatter.LintToJson(allDiagnostics, projectRoot, lintedFileCount));
            }
            else
            {
                if (allDiagnostics.Count == 0)
                {
                    Console.Error.WriteLine($"  Linted {lintedFileCount} file{(lintedFileCount == 1 ? "" : "s")} — no issues. [{FormatElapsed(sw.Elapsed)}]");
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(allDiagnostics));
                    Console.Error.WriteLine($"  Linted in {FormatElapsed(sw.Elapsed)}");
                }
            }

            return (hadErrors || allDiagnostics.Any(d => d.Severity == "error")) ? 1 : 0;
        }
        catch (Exception ex)
        {
            return EmitError(useJson, $"Lint failed: {ex.Message}", projectRoot);
        }
    }

    public static int ShowHelp()
    {
        Console.WriteLine(@"N# Lint

Usage: nlc lint [options] [files...]

Run static analysis rules on N# source files. Error-severity lints are
also included in 'nlc check' and block project builds.

Options:
  --project <dir>   Project root directory (default: current directory)
  --json            Output as JSON (default)
  --text            Output as human-readable diagnostics
  --help, -h        Show this help text

Lint Rules:
  NL001  error     Unused variable
  NL002  error     Missing import
  NL003  error     Unnecessary null check on value type
  NL004  error     Async function without await
  NL006  error     Unreachable code
  NL010  error     Unused import
  NL011  error     Empty catch block
  NL012  error     Unused parameter
  NL016  error     Redundant null check
  NL020  error     Shadowed variable

Inline Suppression:
  // nlc:ignore NL001
  unusedVar := 42

Examples:
  nlc lint
  nlc lint --json
  nlc lint --text
  nlc lint Program.nl
  nlc lint --project examples/16-task-cli

Exit codes:
  0  No errors found
  1  One or more errors were reported");

        return 0;
    }

    private static int EmitError(bool useJson, string message, string? projectRoot = null)
    {
        if (!useJson)
        {
            Console.Error.WriteLine(message);
        }
        else
        {
            Console.Write(OutputFormatter.ErrorToJson("lint", message, projectRoot));
        }

        return 1;
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

    private static bool IsOptionValue(string[] args, string value, params string[] flags)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (flags.Contains(args[i]) && args[i + 1] == value)
                return true;
        }
        return false;
    }

    private static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed.TotalMinutes >= 1)
            return $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
        return $"{elapsed.TotalSeconds:F1}s";
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string? ExtractSourceLine(string source, int line)
    {
        var lines = source.Split('\n');
        return line > 0 && line <= lines.Length ? lines[line - 1] : null;
    }
}

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
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var useJson = GetEffectiveOutputMode(options) == LintOutputModeKind.Json;
        var projectRoot = Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());

        var positionalFiles = GetPositionalFiles(args);

        if (!Directory.Exists(projectRoot))
            return EmitError(useJson, LintCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot), projectRoot);

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
                Console.WriteLine(LintCommandKernels.GetNoFilesFoundMessage());
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
                            "LINT", "error", LintCommandKernels.GetFileNotFoundMessage(relativePath),
                            relativePath, 0, 0, 0, null, null, null, null, null, null, null));
                    }
                    else
                    {
                        Console.Error.WriteLine(LintCommandKernels.GetFileNotFoundMessage(file));
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
                    var parseErrors = FilterCompilerErrorsBySeverity(parseResult.Errors, ErrorSeverity.Error);

                    if (parseErrors.Count > 0)
                    {
                        hadErrors = true;
                        var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
                        if (useJson)
                        {
                            foreach (var err in parseErrors)
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
                            Console.Error.WriteLine(LintCommandKernels.GetParseErrorsMessage(
                                file,
                                string.Join(", ", parseResult.Errors.Select(e => e.Message))));
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
                            LintCommandKernels.GetSeverityText(diag.Severity),
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
                            "LINT", "error", LintCommandKernels.GetErrorLintingDiagnosticMessage(ex.Message),
                            relativePath, 0, 0, 0, null, null, null, null, null, null, null));
                    }
                    else
                    {
                        Console.Error.WriteLine(LintCommandKernels.GetErrorLintingFileMessage(file, ex.Message));
                    }
                }
            }

            var summary = OutputFormatter.SummarizeDiagnostics(allDiagnostics);
            if (useJson)
            {
                Console.Write(OutputFormatter.LintToJson(allDiagnostics, projectRoot, lintedFileCount));
            }
            else
            {
                if (allDiagnostics.Count == 0)
                {
                    Console.Error.WriteLine(LintCommandKernels.GetNoIssuesMessage(
                        lintedFileCount,
                        FormatElapsed(sw.Elapsed)));
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(allDiagnostics));
                    Console.Error.WriteLine(LintCommandKernels.GetLintedInMessage(FormatElapsed(sw.Elapsed)));
                }
            }

            return (hadErrors || summary.Errors > 0) ? 1 : 0;
        }
        catch (Exception ex)
        {
            return EmitError(useJson, LintCommandKernels.GetFailedMessage(ex.Message), projectRoot);
        }
    }

    public static int ShowHelp()
    {
        Console.WriteLine(LintCommandKernels.GetHelpText());

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

    internal static LintOptionSummary GetOptionSummary(string[] args)
    {
        if (LintCommandKernels.TryGetOptionSummary(args, out var summary))
            return summary;

        throw new InvalidOperationException("N# lint option summary kernel rejected the arguments.");
    }

    internal static LintOutputModeKind GetEffectiveOutputMode(LintOptionSummary options)
        => LintCommandKernels.GetEffectiveOutputMode(options.UseText, options.UseJson);

    private static string[] GetPositionalFiles(string[] args)
        => LintCommandKernels.TryGetFileArgs(args, out var files)
            ? files
            : throw new InvalidOperationException("N# lint file argument kernel rejected the arguments.");

    private static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed.TotalMinutes >= 1)
            return $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
        return $"{elapsed.TotalSeconds:F1}s";
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static List<CompilerError> FilterCompilerErrorsBySeverity(
        IReadOnlyList<CompilerError> errors,
        ErrorSeverity severity)
    {
        return CompilerErrorSeverityFilter.TryFilter(
            errors,
            severity,
            out var filteredErrors)
            ? filteredErrors
            : throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the diagnostics.");
    }

    private static string? ExtractSourceLine(string source, int line) =>
        CodeIntelligenceService.ExtractSourceLineForDiagnostics(source, line);
}

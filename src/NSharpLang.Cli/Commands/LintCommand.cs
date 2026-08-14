using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class LintCommand
{
    public static int Execute(string[] args)
    {
        var options = LintCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(LintCommandKernels.GetHelpText());
            return 0;
        }

        var useJson = LintCommandKernels.GetEffectiveOutputMode(options.UseText, options.UseJson) == 1;
        var projectRoot = LintCommandKernels.GetProjectRoot(options.ProjectOption, Directory.GetCurrentDirectory());

        var positionalFiles = LintCommandKernels.GetFileArgs(args);

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
                    .Select(f => LintCommandKernels.GetSourceFilePath(f))
                    .ToArray();
            }
            else
            {
                files = positionalFiles
                    .Select(f => LintCommandKernels.ResolveFilePath(projectRoot, f))
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
                    var relativePath = LintCommandKernels.GetRelativePath(projectRoot, file);
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
                    var parseResult = NSharpLang.Compiler.Columnar.ColumnarParserRecovery.ParseFileAst(source, file);
                    var parseErrors = CompilerErrorSeverityFilter.Filter(parseResult.Errors, ErrorSeverity.Error);

                    if (parseErrors.Count > 0)
                    {
                        hadErrors = true;
                        var relativePath = LintCommandKernels.GetRelativePath(projectRoot, file);
                        if (useJson)
                        {
                            foreach (var err in parseErrors)
                            {
                                allDiagnostics.Add(new DiagnosticResult(
                                    "PARSE", "error", err.Message,
                                    relativePath, err.Line, err.Column, Math.Max(err.Length, 1),
                                    CodeIntelligenceSourceDoor.SourceLine(source, err.Line),
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

                    var fileDir = LintCommandKernels.GetFileDirectory(projectRoot, file);
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
                            LintCommandKernels.GetRelativePath(projectRoot, file),
                            diag.Location.Line,
                            diag.Location.Column,
                            Math.Max(diag.Length, 1),
                            CodeIntelligenceSourceDoor.SourceLine(source, diag.Location.Line),
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
                    var relativePath = LintCommandKernels.GetRelativePath(projectRoot, file);
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
                        ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)));
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(allDiagnostics));
                    Console.Error.WriteLine(LintCommandKernels.GetLintedInMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)));
                }
            }

            return LintCommandKernels.GetExitCode(hadErrors, summary.Errors);
        }
        catch (Exception ex)
        {
            return EmitError(useJson, LintCommandKernels.GetFailedMessage(ex.Message), projectRoot);
        }
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
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class CheckCommand
{
    public static int Execute(string[] args)
    {
        var arguments = GetArgumentSummary(args);
        if (arguments.ShowHelp)
            return ShowHelp();

        var outputMode = GetEffectiveOutputMode(arguments);
        var useText = outputMode is CheckOutputModeKind.Text or CheckOutputModeKind.InvalidSystemsReportText;
        var aot = arguments.Aot;
        var projectDir = GetProjectDir(arguments);

        if (!Directory.Exists(projectDir))
        {
            return EmitError(useText, CheckCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir), projectDir);
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

            var backend = ResolveCompilationBackend(arguments.BackendOption, projectConfig);
            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(projectDir, projectConfig);
            var diagnostics = service.GetDiagnostics(snapshot);
            diagnostics = OutputFormatter.DeduplicateAndSortDiagnostics(diagnostics);
            var summary = OutputFormatter.SummarizeDiagnostics(diagnostics);

            // If analysis found no errors AND this is a proper project (has project.yml),
            // verify the IL backend can emit the assembly successfully. Non-project
            // directories (standalone .nl files) skip this because they aren't meant
            // to be compiled as a single project.
            if (summary.Errors == 0
                && snapshot.SourceFiles.Count > 0
                && File.Exists(projectYmlPath))
            {
                var verificationDiagnostics = VerifyBackendOutput(projectDir, backend, projectConfig);
                if (verificationDiagnostics.Count > 0)
                {
                    diagnostics.AddRange(verificationDiagnostics);
                    diagnostics = OutputFormatter.DeduplicateAndSortDiagnostics(diagnostics);
                    summary = OutputFormatter.SummarizeDiagnostics(diagnostics);
                }
            }

            // `--aot` promotes Native AOT blockers to errors so `nlc check --aot` mirrors
            // `nlc build --aot`. Analysis-only: no IL is emitted for this gate.
            if (aot)
            {
                var aotDiagnostics = CollectAotDiagnostics(projectDir, projectConfig);
                if (aotDiagnostics.Count > 0)
                {
                    diagnostics.AddRange(aotDiagnostics);
                    diagnostics = OutputFormatter.DeduplicateAndSortDiagnostics(diagnostics);
                    summary = OutputFormatter.SummarizeDiagnostics(diagnostics);
                }
            }

            if (outputMode == CheckOutputModeKind.InvalidSystemsReportText)
            {
                return EmitError(useText, CheckCommandKernels.GetSystemsReportTextUnavailableMessage(), projectDir);
            }

            if (useText)
            {
                if (summary.Errors == 0 && summary.Warnings == 0)
                {
                    var fileCount = snapshot.SourceFiles.Count;
                    Console.Error.WriteLine(CheckCommandKernels.GetNoErrorsMessage(
                        fileCount,
                        FormatElapsed(sw.Elapsed)));
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(diagnostics));
                    Console.Error.WriteLine(CheckCommandKernels.GetCheckedInMessage(FormatElapsed(sw.Elapsed)));
                }
            }
            else if (outputMode == CheckOutputModeKind.SystemsReportJson)
            {
                Console.Write(OutputFormatter.CheckSystemsReportToJson(
                    diagnostics,
                    snapshot.ProjectRoot,
                    snapshot.SourceFiles.Count,
                    snapshot.SystemsReport));
            }
            else
            {
                Console.Write(OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count));
            }

            return summary.Errors > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            if (useText)
                Console.Error.WriteLine(CheckCommandKernels.GetFailedElapsedMessage(FormatElapsed(sw.Elapsed)));
            return EmitError(useText, CheckCommandKernels.GetFailedMessage(ex.Message), projectDir);
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
                foreach (var error in FilterCompilerErrorsBySeverity(compileResult.Errors, ErrorSeverity.Error))
                {
                    results.Add(CodeIntelligenceService.ToDiagnosticResult(error, projectDir));
                }
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { /* best effort */ }
        }

        return results;
    }

    private static List<CompilerError> FilterCompilerErrorsBySeverity(
        IEnumerable<CompilerError> errors,
        ErrorSeverity severity)
    {
        var errorList = errors as IReadOnlyList<CompilerError> ?? errors.ToList();
        return CompilerErrorSeverityFilter.TryFilter(
            errorList,
            severity,
            out var filteredErrors)
            ? filteredErrors
            : errorList.Where(error => error.Severity == severity).ToList();
    }

    /// <summary>
    /// Runs the AOT-blocker analysis pass and returns the blockers as build-blocking
    /// diagnostics. Analysis-only — no IL is emitted.
    /// </summary>
    private static List<DiagnosticResult> CollectAotDiagnostics(string projectDir, ProjectConfig? config)
    {
        var compiler = new MultiFileCompiler(projectDir, config);
        compiler.CompileForAnalysis();
        return compiler.BuildAotDiagnostics(asError: true)
            .Select(error => CodeIntelligenceService.ToDiagnosticResult(error, projectDir))
            .ToList();
    }

    public static int ShowHelp()
    {
        Console.WriteLine(CheckCommandKernels.GetHelpText());

        return 0;
    }

    internal static CheckArgumentSummary GetArgumentSummary(string[] args)
    {
        if (CheckCommandKernels.TryGetArgumentSummary(args, out var summary))
            return summary;

        throw new InvalidOperationException("N# check argument parser kernel rejected the arguments.");
    }

    internal static CheckOutputModeKind GetEffectiveOutputMode(CheckArgumentSummary arguments)
    {
        if (CheckCommandKernels.TryGetEffectiveOutputMode(arguments.UseText, arguments.SystemsReport, out var outputMode))
            return outputMode;

        throw new InvalidOperationException("N# check output-mode kernel rejected the options.");
    }

    private static string GetProjectDir(CheckArgumentSummary arguments)
    {
        if (!string.IsNullOrWhiteSpace(arguments.ProjectOption))
            return Path.GetFullPath(arguments.ProjectOption);

        return Path.GetFullPath(arguments.PositionalProject ?? Directory.GetCurrentDirectory());
    }

    private static CompilationBackend ResolveCompilationBackend(string? backendOption, ProjectConfig? config)
    {
        return CompilationBackendSelectionKernels.Resolve(backendOption, config);
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

    private static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed.TotalMinutes >= 1)
            return $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
        return $"{elapsed.TotalSeconds:F1}s";
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Playground;

public sealed class PlaygroundCompiler
{
    public const int SchemaVersion = 2;
    public const int MaxSourceLength = 64 * 1024;
    public const int MaxProjectSourceLength = 128 * 1024;
    private const string DefaultFileName = "Program.nl";
    public PlaygroundCatalogResponse GetCatalog()
        => new(
            SchemaVersion,
            PlaygroundExamples.DefaultId,
            PlaygroundExamples.EstimatedMinutes,
            PlaygroundExamples.All,
            PlaygroundExamples.Tutorial,
            new PlaygroundCapabilities(
                RunsInBrowser: true,
                SupportsDiagnostics: true,
                SupportsFormatting: true,
                SupportsCompletions: true,
                SupportsHover: true,
                SupportsSyntaxHighlighting: true,
                SupportsExecution: true,
                SupportsTests: false,
                Limitations:
                [
                    "The hosted playground runs compiler analysis, formatting, completions, hover, syntax highlighting, and a bounded execution subset entirely in the browser.",
                    "The Run button supports tutorial-scale code: functions, print, simple control flow, records/classes, object initializers, string/numeric helpers, and selected match patterns.",
                    "Full build, test execution, NuGet restore, filesystem workflows, async, LINQ, and unrestricted .NET interop require the local nlc toolchain.",
                    "External assembly resolution is intentionally bounded for browser reliability."
                ]));

    public PlaygroundCheckResponse Check(string? source, string? fileName = null)
        => CheckProject([new PlaygroundFile(NormalizeFileName(fileName), NormalizeSource(source))], fileName);

    public PlaygroundCheckResponse CheckProject(IEnumerable<PlaygroundFile>? files, string? activeFile = null)
    {
        var normalizedFiles = NormalizeFiles(files);
        var normalizedActiveFile = NormalizeExistingFileName(activeFile, normalizedFiles);
        var analysis = AnalyzeProject(normalizedFiles);
        return BuildCheckResponse(normalizedActiveFile, analysis.Diagnostics);
    }

    public PlaygroundFormatResponse Format(string? source, string? fileName = null)
    {
        var normalizedSource = NormalizeSource(source);
        var normalizedFileName = NormalizeFileName(fileName);
        var check = Check(normalizedSource, normalizedFileName);

        if (check.Summary.Errors > 0)
        {
            return new PlaygroundFormatResponse(
                SchemaVersion,
                Ok: false,
                File: normalizedFileName,
                FormattedCode: normalizedSource,
                Diagnostics: check.Diagnostics,
                Summary: check.Summary,
                Warnings: ["Formatting is skipped while the source has compiler errors."]);
        }

        try
        {
            var lexer = new Lexer(normalizedSource, normalizedFileName);
            lexer.Tokenize();   // populates lexer.Comments for the formatter below
            var parseResult = NSharpLang.Compiler.Columnar.ColumnarParserRecovery.ParseFileAst(normalizedSource, normalizedFileName);
            if (parseResult.CompilationUnit == null)
            {
                return new PlaygroundFormatResponse(
                    SchemaVersion,
                    Ok: false,
                    File: normalizedFileName,
                    FormattedCode: normalizedSource,
                    Diagnostics: check.Diagnostics,
                    Summary: check.Summary,
                    Warnings: ["Formatting is skipped because the parser did not produce an AST."]);
            }

            var formatter = new Formatter();
            var formatResult = formatter.FormatSafe(normalizedSource, parseResult.CompilationUnit, lexer.Comments, normalizedFileName);
            return new PlaygroundFormatResponse(
                SchemaVersion,
                Ok: formatResult.Success,
                File: normalizedFileName,
                FormattedCode: formatResult.Text,
                Diagnostics: check.Diagnostics,
                Summary: check.Summary,
                Warnings: formatResult.Warnings);
        }
        catch (Exception ex)
        {
            return new PlaygroundFormatResponse(
                SchemaVersion,
                Ok: false,
                File: normalizedFileName,
                FormattedCode: normalizedSource,
                Diagnostics: check.Diagnostics,
                Summary: check.Summary,
                Warnings: [$"Formatting failed: {ex.Message}"]);
        }
    }

    public PlaygroundCompletionResponse Complete(
        IEnumerable<PlaygroundFile>? files,
        string? fileName,
        int line,
        int column)
    {
        var normalizedFiles = NormalizeFiles(files);
        var normalizedFileName = NormalizeExistingFileName(fileName, normalizedFiles);
        var analysis = AnalyzeProject(normalizedFiles);
        var items = new List<PlaygroundCompletionItem>();
        var context = CompletionContext.Unknown.ToString();
        string? receiver = null;
        string? receiverType = null;

        if (analysis.Snapshot != null)
        {
            var engine = new CompletionEngine();
            var result = engine.GetCompletions(
                analysis.Snapshot,
                normalizedFileName,
                Math.Max(line, 1),
                Math.Max(column, 0),
                includeKeywords: true);

            context = result.Context.ToString();
            receiver = result.Receiver;
            receiverType = result.ReceiverType;
            items.AddRange(FlattenCompletions(result));
        }

        var diagnostics = Deduplicate(analysis.Diagnostics);
        var summary = Summarize(diagnostics);
        return new PlaygroundCompletionResponse(
            SchemaVersion,
            Ok: summary.Errors == 0,
            File: normalizedFileName,
            Context: context,
            Receiver: receiver,
            ReceiverType: receiverType,
            Items: DeduplicateCompletions(items),
            Diagnostics: diagnostics,
            Summary: summary);
    }

    public PlaygroundHoverResponse Hover(
        IEnumerable<PlaygroundFile>? files,
        string? fileName,
        int line,
        int column)
    {
        var normalizedFiles = NormalizeFiles(files);
        var normalizedFileName = NormalizeExistingFileName(fileName, normalizedFiles);
        var analysis = AnalyzeProject(normalizedFiles);
        PlaygroundHover? hover = null;

        if (analysis.Snapshot != null)
        {
            var service = new CodeIntelligenceService();
            var result = service.GetHoverInfo(
                analysis.Snapshot,
                normalizedFileName,
                Math.Max(line, 1),
                Math.Max(column, 0));

            if (result != null)
            {
                hover = new PlaygroundHover(result.Signature, result.Documentation, result.DefinedIn, result.Kind);
            }
        }

        var diagnostics = Deduplicate(analysis.Diagnostics);
        var summary = Summarize(diagnostics);
        return new PlaygroundHoverResponse(
            SchemaVersion,
            Ok: hover != null,
            File: normalizedFileName,
            Hover: hover,
            Diagnostics: diagnostics,
            Summary: summary);
    }

    public PlaygroundRunResponse RunProject(IEnumerable<PlaygroundFile>? files, string? activeFile = null)
    {
        var normalizedFiles = NormalizeFiles(files);
        var normalizedActiveFile = NormalizeExistingFileName(activeFile, normalizedFiles);
        var analysis = AnalyzeProject(normalizedFiles);
        var diagnostics = Deduplicate(analysis.Diagnostics);
        var summary = Summarize(diagnostics);

        if (summary.Errors > 0)
        {
            return new PlaygroundRunResponse(
                SchemaVersion,
                Ok: false,
                File: normalizedActiveFile,
                ExitCode: 1,
                Stdout: string.Empty,
                Stderr: "Run skipped because the program has compiler errors.",
                UnsupportedReason: null,
                Diagnostics: diagnostics,
                Summary: summary);
        }

        if (analysis.Snapshot == null)
        {
            var failedDiagnostics = Deduplicate(diagnostics.Concat([
                new PlaygroundDiagnostic(
                    Code: "PG200",
                    Severity: "error",
                    Message: "Run skipped because the browser compiler could not build an executable snapshot.",
                    File: normalizedActiveFile,
                    Line: 1,
                    Column: 1,
                    Length: 1,
                    SourceSnippet: null,
                    Explanation: "The browser runner needs a successfully parsed and analyzed project snapshot before execution.",
                    Suggestion: "Use the local nlc toolchain for this program, or simplify it for the hosted playground.",
                    Hint: null)
            ]));
            return BuildFailedRunResponse(normalizedActiveFile, failedDiagnostics, "No executable snapshot was available.", unsupportedReason: null);
        }

        try
        {
            var orderedUnits = analysis.Snapshot.SourceFiles
                .Select(path => analysis.Snapshot.CompilationUnits.TryGetValue(path, out var unit) ? unit : null)
                .Where(unit => unit != null)
                .Cast<CompilationUnit>()
                .ToArray();
            var runner = new PlaygroundRunner(orderedUnits);
            var run = runner.Run();
            return new PlaygroundRunResponse(
                SchemaVersion,
                Ok: run.ExitCode == 0,
                File: normalizedActiveFile,
                ExitCode: run.ExitCode,
                Stdout: run.Stdout,
                Stderr: run.Stderr,
                UnsupportedReason: null,
                Diagnostics: diagnostics,
                Summary: summary);
        }
        catch (PlaygroundRunUnsupportedException ex)
        {
            var runDiagnostics = Deduplicate(diagnostics.Concat([
                new PlaygroundDiagnostic(
                    Code: ex.Code,
                    Severity: "error",
                    Message: ex.Message,
                    File: normalizedActiveFile,
                    Line: 1,
                    Column: 1,
                    Length: 1,
                    SourceSnippet: null,
                    Explanation: "The hosted playground intentionally runs a bounded browser execution subset.",
                    Suggestion: "Install nlc locally for full CLR execution, or try one of the smaller runnable samples.",
                    Hint: "Diagnostics, formatting, hover, and completions still work for this code in the browser.")
            ]));
            return BuildFailedRunResponse(normalizedActiveFile, runDiagnostics, ex.Message, unsupportedReason: ex.Message);
        }
        catch (Exception ex)
        {
            var runDiagnostics = Deduplicate(diagnostics.Concat([
                new PlaygroundDiagnostic(
                    Code: "PG299",
                    Severity: "error",
                    Message: $"Run failed: {ex.Message}",
                    File: normalizedActiveFile,
                    Line: 1,
                    Column: 1,
                    Length: 1,
                    SourceSnippet: null,
                    Explanation: "The browser runner hit an unexpected execution failure.",
                    Suggestion: "If this is reproducible, file an issue with the sample source.",
                    Hint: null)
            ]));
            return BuildFailedRunResponse(normalizedActiveFile, runDiagnostics, ex.Message, unsupportedReason: null);
        }
    }

    private static ProjectAnalysis AnalyzeProject(IReadOnlyList<PlaygroundFile> files)
    {
        var diagnostics = new List<PlaygroundDiagnostic>();
        var totalLength = files.Sum(file => file.Code.Length);
        if (totalLength > MaxProjectSourceLength)
        {
            diagnostics.Add(new PlaygroundDiagnostic(
                Code: "PG001",
                Severity: "error",
                Message: $"Playground source is too large. Maximum project size is {MaxProjectSourceLength} characters.",
                File: files[0].Name,
                Line: 1,
                Column: 1,
                Length: 1,
                SourceSnippet: null,
                Explanation: "The hosted playground keeps analysis bounded so it can run reliably in the browser.",
                Suggestion: "Reduce the sample or use the local nlc toolchain for larger programs.",
                Hint: null));

            return new ProjectAnalysis(null, diagnostics);
        }

        foreach (var file in files)
        {
            if (file.Code.Length > MaxSourceLength)
            {
                diagnostics.Add(new PlaygroundDiagnostic(
                    Code: "PG001",
                    Severity: "error",
                    Message: $"Playground file '{file.Name}' is too large. Maximum file size is {MaxSourceLength} characters.",
                    File: file.Name,
                    Line: 1,
                    Column: 1,
                    Length: 1,
                    SourceSnippet: null,
                    Explanation: "The hosted playground keeps per-file analysis bounded so it can run reliably in the browser.",
                    Suggestion: "Reduce the sample or use the local nlc toolchain for larger programs.",
                    Hint: null));
            }
        }

        if (diagnostics.Count > 0)
        {
            return new ProjectAnalysis(null, diagnostics);
        }

        var filesToAnalyze = GetAnalyzableFiles(files);

        return AnalyzeWithProjectCompiler(filesToAnalyze);
    }

    private static ProjectAnalysis AnalyzeWithProjectCompiler(IReadOnlyList<PlaygroundFile> files)
    {
        var root = GetVirtualProjectRoot();
        var paths = files
            .Select(file => Path.GetFullPath(Path.Combine(root, file.Name)))
            .ToArray();
        var sourceOverrides = files
            .Zip(paths, (file, path) => new { file, path })
            .ToDictionary(pair => pair.path, pair => pair.file.Code, StringComparer.OrdinalIgnoreCase);
        var config = ProjectFileParser.CreateDefault("NSharpPlayground");
        config.Entry = files[0].Name;
        config.Exclude = [];

        var compiler = new MultiFileCompiler(paths, root, config, sourceOverrides);
        compiler.CompileForAnalysis();

        var snapshot = new ProjectSnapshot(
            root,
            compiler.CompilationUnits,
            compiler.SemanticModels,
            compiler.AllErrors,
            compiler.SharedAnalyzer,
            compiler.SourceFiles,
            compiler.ProjectIndex,
            compiler.SourceTexts);

        var diagnostics = new CodeIntelligenceService()
            .GetDiagnostics(snapshot)
            .Select(ToPlaygroundDiagnostic)
            .ToList();

        AddLintDiagnostics(snapshot, diagnostics);
        return new ProjectAnalysis(snapshot, diagnostics);
    }

    private static void AddLintDiagnostics(ProjectSnapshot snapshot, List<PlaygroundDiagnostic> diagnostics)
    {
        var linter = new Linter();
        foreach (var (filePath, compilationUnit) in snapshot.CompilationUnits)
        {
            var source = snapshot.SourceTexts.TryGetValue(filePath, out var text) ? text : string.Empty;
            diagnostics.AddRange(linter
                .Lint(compilationUnit, Path.GetFileName(filePath), source)
                .Select(ToPlaygroundDiagnostic));
        }
    }

    private static IReadOnlyList<PlaygroundCompletionItem> FlattenCompletions(CompletionResult result)
        => result.Completions
            .SelectMany(group => group.Value)
            .Select(item => new PlaygroundCompletionItem(
                Label: item.Name,
                Kind: item.Kind,
                Detail: string.Join(" ", new[] { item.Parameters, item.Type }.Where(value => !string.IsNullOrWhiteSpace(value))),
                Documentation: item.Documentation,
                InsertText: item.Name))
            .ToArray();

    private static IReadOnlyList<PlaygroundCompletionItem> DeduplicateCompletions(IEnumerable<PlaygroundCompletionItem> items)
        => items
            .GroupBy(item => item.Label, StringComparer.Ordinal)
            .Select(group => group.First())
            .OrderBy(item => CompletionSortRank(item.Kind))
            .ThenBy(item => item.Label, StringComparer.OrdinalIgnoreCase)
            .Take(200)
            .ToArray();

    private static int CompletionSortRank(string kind)
        => kind switch
        {
            "keyword" => 0,
            "variable" or "parameter" => 1,
            "function" or "method" => 2,
            "property" or "field" => 3,
            "class" or "record" or "struct" or "interface" or "enum" or "union" or "type" => 4,
            _ => 9
        };

    private static PlaygroundCheckResponse BuildCheckResponse(
        string fileName,
        IReadOnlyList<PlaygroundDiagnostic> diagnostics)
    {
        var deduplicated = Deduplicate(diagnostics);
        var summary = Summarize(deduplicated);
        return new PlaygroundCheckResponse(
            SchemaVersion,
            Ok: summary.Errors == 0,
            File: fileName,
            Diagnostics: deduplicated,
            Summary: summary);
    }

    private static PlaygroundRunResponse BuildFailedRunResponse(
        string fileName,
        IReadOnlyList<PlaygroundDiagnostic> diagnostics,
        string stderr,
        string? unsupportedReason)
    {
        var summary = Summarize(diagnostics);
        return new PlaygroundRunResponse(
            SchemaVersion,
            Ok: false,
            File: fileName,
            ExitCode: 2,
            Stdout: string.Empty,
            Stderr: stderr,
            UnsupportedReason: unsupportedReason,
            Diagnostics: diagnostics,
            Summary: summary);
    }

    private static PlaygroundSummary Summarize(IEnumerable<PlaygroundDiagnostic> diagnostics)
    {
        var list = diagnostics.ToArray();
        return new PlaygroundSummary(
            Errors: list.Count(diagnostic => diagnostic.Severity == "error"),
            Warnings: list.Count(diagnostic => diagnostic.Severity == "warning"),
            Infos: list.Count(diagnostic => diagnostic.Severity == "info"));
    }

    private static PlaygroundDiagnostic ToPlaygroundDiagnostic(CompilerError error, string source, string fileName)
    {
        var sourceSnippet = error.SourceSnippet;
        if (string.IsNullOrWhiteSpace(sourceSnippet) && error.Line > 0)
        {
            sourceSnippet = GetSourceLine(source, error.Line);
        }

        return new PlaygroundDiagnostic(
            Code: error.DiagnosticId,
            Severity: error.Severity == ErrorSeverity.Error ? "error" : "warning",
            Message: error.Message,
            File: NormalizeFileName(error.FileName ?? fileName),
            Line: Math.Max(error.Line, 1),
            Column: Math.Max(error.Column, 1),
            Length: Math.Max(error.Length, 1),
            SourceSnippet: sourceSnippet,
            Explanation: error.HumanExplanation,
            Suggestion: error.Suggestion ?? FormatSuggestions(error.Suggestions),
            Hint: error.ContextualHint);
    }

    private static PlaygroundDiagnostic ToPlaygroundDiagnostic(DiagnosticResult diagnostic)
        => new(
            Code: diagnostic.Code,
            Severity: NormalizeSeverity(diagnostic.Severity),
            Message: diagnostic.Message,
            File: NormalizeFileName(diagnostic.File),
            Line: Math.Max(diagnostic.Line, 1),
            Column: Math.Max(diagnostic.Column, 1),
            Length: Math.Max(diagnostic.Length, 1),
            SourceSnippet: diagnostic.SourceSnippet,
            Explanation: diagnostic.Explanation,
            Suggestion: diagnostic.Suggestion,
            Hint: diagnostic.Hint);

    private static PlaygroundDiagnostic ToPlaygroundDiagnostic(Diagnostic diagnostic)
        => new(
            Code: diagnostic.Code,
            Severity: diagnostic.Severity switch
            {
                DiagnosticSeverity.Error => "error",
                DiagnosticSeverity.Warning => "warning",
                _ => "info"
            },
            Message: diagnostic.Message,
            File: NormalizeFileName(diagnostic.Location.FilePath ?? DefaultFileName),
            Line: Math.Max(diagnostic.Location.Line, 1),
            Column: Math.Max(diagnostic.Location.Column, 1),
            Length: Math.Max(diagnostic.Length, 1),
            SourceSnippet: null,
            Explanation: null,
            Suggestion: diagnostic.Suggestion,
            Hint: null);

    private static string NormalizeSeverity(string severity)
        => string.Equals(severity, "warning", StringComparison.OrdinalIgnoreCase)
            ? "warning"
            : string.Equals(severity, "info", StringComparison.OrdinalIgnoreCase)
                ? "info"
                : "error";

    private static IReadOnlyList<PlaygroundDiagnostic> Deduplicate(IEnumerable<PlaygroundDiagnostic> diagnostics)
        => diagnostics
            .GroupBy(diagnostic => new
            {
                diagnostic.Code,
                diagnostic.File,
                diagnostic.Line,
                diagnostic.Column,
                diagnostic.Message
            })
            .Select(group => group.First())
            .OrderByDescending(diagnostic => diagnostic.Severity == "error")
            .ThenByDescending(diagnostic => diagnostic.Severity == "warning")
            .ThenBy(diagnostic => diagnostic.File, StringComparer.Ordinal)
            .ThenBy(diagnostic => diagnostic.Line)
            .ThenBy(diagnostic => diagnostic.Column)
            .ToArray();

    private static IReadOnlyList<PlaygroundFile> NormalizeFiles(IEnumerable<PlaygroundFile>? files)
    {
        var normalized = (files ?? [])
            .Select(file => new PlaygroundFile(NormalizeFileName(file.Name), NormalizeSource(file.Code)))
            .GroupBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Last())
            .ToArray();

        return normalized.Length == 0
            ? [new PlaygroundFile(DefaultFileName, string.Empty)]
            : normalized;
    }

    private static IReadOnlyList<PlaygroundFile> GetAnalyzableFiles(IReadOnlyList<PlaygroundFile> files)
    {
        var sourceFiles = files
            .Where(file => !IsTestFile(file.Name))
            .ToArray();

        return sourceFiles.Length == 0 ? files : sourceFiles;
    }

    private static bool IsTestFile(string fileName)
        => fileName.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase) ||
           fileName.EndsWith(".tests.nsharp", StringComparison.OrdinalIgnoreCase);

    private static string NormalizeSource(string? source)
        => (source ?? string.Empty)
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace("\r", "\n", StringComparison.Ordinal);

    private static string NormalizeExistingFileName(string? fileName, IReadOnlyList<PlaygroundFile> files)
    {
        var normalized = NormalizeFileName(fileName);
        return files.Any(file => string.Equals(file.Name, normalized, StringComparison.OrdinalIgnoreCase))
            ? normalized
            : files[0].Name;
    }

    private static string NormalizeFileName(string? fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName))
        {
            return DefaultFileName;
        }

        var normalized = fileName.Replace('\\', '/');
        var candidate = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
        if (string.IsNullOrWhiteSpace(candidate))
        {
            return DefaultFileName;
        }

        return candidate.EndsWith(".nl", StringComparison.OrdinalIgnoreCase) ||
               candidate.EndsWith(".nsharp", StringComparison.OrdinalIgnoreCase)
            ? candidate
            : $"{candidate}.nl";
    }

    private static string? GetSourceLine(string source, int line)
    {
        var lines = source.Split('\n');
        return line > 0 && line <= lines.Length ? lines[line - 1] : null;
    }

    private static string? FormatSuggestions(IEnumerable<string>? suggestions)
        => suggestions == null ? null : string.Join(" ", suggestions.Where(suggestion => !string.IsNullOrWhiteSpace(suggestion)));

    private static string GetVirtualProjectRoot()
        => Path.Combine(Path.GetTempPath(), "nsharp-playground");

    private sealed record ProjectAnalysis(ProjectSnapshot? Snapshot, List<PlaygroundDiagnostic> Diagnostics);
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Handles the 'nlc fix' command — auto-applies compiler suggestions.
/// The N# equivalent of `cargo clippy --fix`.
///
/// Safety contract:
///   - Default (no flags):  applies only FixSafety.Safe fixes
///   - --include-review-needed: also applies FixSafety.ReviewNeeded fixes
///   - FixSafety.SuggestionOnly: never written — reported in results only
///
/// Pipeline: discover files → parse → lint → get fixes → filter by safety → apply edits → write back
/// </summary>
public static class FixCommand
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public static int Execute(string[] args)
    {
        var arguments = FixCommandArgumentKernels.GetArgumentSummary(args);
        if (arguments.ShowHelp)
        {
            Console.WriteLine(FixCommandKernels.GetHelpText());
            return 0;
        }

        var dryRun = arguments.DryRun;
        var useText = FixCommandArgumentKernels.GetEffectiveOutputMode(arguments.UseText) == FixOutputModeKind.Text;
        var includeReviewNeeded = arguments.IncludeReviewNeeded;
        var fileArg = arguments.FileOption;
        var projectDir = !string.IsNullOrWhiteSpace(arguments.ProjectOption)
            ? Path.GetFullPath(arguments.ProjectOption)
            : Path.GetFullPath(arguments.PositionalProject ?? Directory.GetCurrentDirectory());

        if (!Directory.Exists(projectDir))
        {
            return EmitError(useText, FixCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir), projectDir);
        }

        try
        {
            // Discover files
            List<string> files;
            if (fileArg != null)
            {
                var fullPath = Path.GetFullPath(Path.IsPathRooted(fileArg) ? fileArg : Path.Combine(projectDir, fileArg));
                if (!File.Exists(fullPath))
                {
                    return EmitError(useText, FixCommandKernels.GetFileNotFoundMessage(fullPath), projectDir);
                }
                files = new List<string> { fullPath };
            }
            else
            {
                var config = ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault();
                files = config.GetSourceFiles(projectDir, includeTests: false)
                    .Select(f => Path.GetFullPath(f))
                    .ToList();
            }

            if (files.Count == 0)
            {
                if (useText)
                    Console.Error.WriteLine(FixCommandKernels.GetNoFilesFoundMessage());
                else
                    Console.Write(ResultJson(projectDir, dryRun, includeReviewNeeded,
                        Array.Empty<FixEntry>(), Array.Empty<FixEntry>(), 0));
                return 0;
            }

            // Collect fixes per file, then filter by safety
            var allResults = new List<FixEntry>();    // every discovered fix
            var allApplied = new List<FixEntry>();     // only fixes that pass the safety gate
            var pendingWrites = new List<(string File, string FixedSource)>();
            var filesModified = 0;

            foreach (var file in files)
            {
                var source = File.ReadAllText(file);
                var fixes = FixApplicator.GetFixesForFile(file, source);

                if (fixes.Count == 0) continue;

                var relativeFile = NormalizePath(Path.GetRelativePath(projectDir, file));

                var safeActions = FixCommandKernels.FilterBySafety(fixes, includeReviewNeeded);

                foreach (var fix in fixes)
                {
                    var entry = ToFixEntry(relativeFile, fix);
                    allResults.Add(entry);
                }

                var fileApplied = new List<FixEntry>(safeActions.Count);
                foreach (var fix in safeActions)
                {
                    fileApplied.Add(ToFixEntry(relativeFile, fix));
                }
                allApplied.AddRange(fileApplied);

                if (fileApplied.Count > 0)
                {
                    // Collect only edits from fixes that passed the safety gate. Validate in dry-run too so
                    // the JSON never promises a write plan that would later fail or corrupt a file.
                    var allEdits = safeActions.SelectMany(f => f.Edits).ToList();
                    FixApplicator.ValidateAndSortEdits(source, allEdits);

                    if (!dryRun)
                    {
                        var fixedSource = FixApplicator.ApplyEdits(source, allEdits);

                        if (fixedSource != source)
                        {
                            pendingWrites.Add((file, fixedSource));
                            filesModified++;
                        }
                    }
                    else
                    {
                        filesModified++; // Would modify
                    }
                }
            }

            if (!dryRun)
            {
                foreach (var (file, fixedSource) in pendingWrites)
                {
                    WriteAllTextAtomic(file, fixedSource);
                }
            }

            // Output results
            if (useText)
            {
                OutputText(allResults, allApplied, filesModified, dryRun, includeReviewNeeded);
            }
            else
            {
                Console.Write(ResultJson(projectDir, dryRun, includeReviewNeeded, allResults, allApplied, filesModified));
            }

            return dryRun && filesModified > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            return EmitError(useText, FixCommandKernels.GetFailedMessage(ex.Message), projectDir);
        }
    }

    private static void OutputText(
        List<FixEntry> results,
        List<FixEntry> applied,
        int filesModified,
        bool dryRun,
        bool includeReviewNeeded)
    {
        if (results.Count == 0)
        {
            Console.Error.WriteLine(FixCommandKernels.GetNothingToFixMessage());
            return;
        }

        // Report applied fixes
        if (applied.Count > 0)
        {
            Console.Error.WriteLine(FixCommandKernels.GetAppliedHeader(applied.Count, filesModified, dryRun));

            var groupedApplied = FixCommandKernels.GroupAppliedEntriesByFile(applied);

            for (var groupIndex = 0; groupIndex < groupedApplied.GroupCount; groupIndex++)
            {
                Console.Error.WriteLine(FixCommandKernels.GetAppliedFileHeader(groupedApplied.Files[groupIndex]));
                var start = groupedApplied.Starts[groupIndex];
                var count = groupedApplied.Counts[groupIndex];
                for (var i = 0; i < count; i++)
                {
                    var sourceIndex = groupedApplied.Indices[start + i];
                    var fix = applied[sourceIndex];
                    Console.Error.WriteLine(FixCommandKernels.GetEntryLine(fix.DiagnosticCode, fix.Title));
                }
            }
        }

        // Report skipped fixes
        var skipped = FixCommandKernels.SelectSkippedEntries(results, includeReviewNeeded);

        if (skipped.Count > 0)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine(FixCommandKernels.GetSkippedHeader(skipped.Count));
            foreach (var fix in skipped)
            {
                var reason = FixCommandKernels.GetSkippedReason(fix.Safety);
                Console.Error.WriteLine(FixCommandKernels.GetSkippedLine(fix.DiagnosticCode, fix.Title, reason));
            }
        }
    }

    private static string ResultJson(
        string projectDir,
        bool dryRun,
        bool includeReviewNeeded,
        IReadOnlyCollection<FixEntry> results,
        IReadOnlyCollection<FixEntry> applied,
        int filesModified)
    {
        var normalizedProjectRoot = NormalizePath(Path.GetFullPath(projectDir));

        var envelope = new
        {
            schemaVersion = 2,
            command = "fix",
            projectRoot = normalizedProjectRoot,
            dryRun,
            includeReviewNeeded,
            ok = !dryRun || filesModified == 0,
            filesModified,
            results = results.Select(ToJsonEntry).ToList(),
            fixesApplied = applied.Select(ToJsonEntry).ToList()
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    private static object ToJsonEntry(FixEntry f)
    {
        return new
        {
            file = NormalizePath(f.File),
            diagnostic = f.DiagnosticCode,
            title = f.Title,
            safety = f.Safety,
            edits = f.Edits.Select(e => new
            {
                startLine = e.StartLine,
                startColumn = e.StartColumn,
                endLine = e.EndLine,
                endColumn = e.EndColumn,
                newText = e.NewText
            }).ToList()
        };
    }

    private static FixEntry ToFixEntry(string relativeFile, CodeAction fix)
    {
        var safetyStr = fix.Safety switch
        {
            FixSafety.Safe => "safe",
            FixSafety.ReviewNeeded => "reviewNeeded",
            FixSafety.SuggestionOnly => "suggestionOnly",
            _ => "unknown"
        };

        return new FixEntry(relativeFile, fix.DiagnosticCode, fix.Title, fix.Edits, safetyStr);
    }

    private static int EmitError(bool useText, string message, string? projectRoot = null)
    {
        if (useText)
        {
            Console.Error.WriteLine(message);
        }
        else
        {
            Console.Write(OutputFormatter.ErrorToJson("fix", message, projectRoot));
        }

        return 1;
    }

    private static void WriteAllTextAtomic(string path, string contents)
    {
        var directory = Path.GetDirectoryName(path) ?? Directory.GetCurrentDirectory();
        var tempPath = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");

        try
        {
            File.WriteAllText(tempPath, contents);
            if (!OperatingSystem.IsWindows() && File.Exists(path))
            {
                File.SetUnixFileMode(tempPath, File.GetUnixFileMode(path));
            }
            File.Move(tempPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(tempPath))
                File.Delete(tempPath);
        }
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

/// <summary>
/// Serialization-friendly representation of a fix for JSON/text output.
/// </summary>
internal record FixEntry(
    string File,
    string DiagnosticCode,
    string Title,
    List<TextEdit> Edits,
    string Safety);

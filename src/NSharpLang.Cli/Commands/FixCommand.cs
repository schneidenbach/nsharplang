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
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var dryRun = args.Contains("--dry-run");
        var useText = args.Contains("--text");
        var includeReviewNeeded = args.Contains("--include-review-needed");
        var fileArg = GetOption(args, "--file");
        var projectDir = GetProjectDir(args);

        if (!Directory.Exists(projectDir))
        {
            return EmitError(useText, $"Directory not found: {projectDir}", projectDir);
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
                    return EmitError(useText, $"File not found: {fullPath}", projectDir);
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
                    Console.Error.WriteLine("No .nl files found.");
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

                // Classify every fix
                var fileApplied = new List<FixEntry>();
                foreach (var fix in fixes)
                {
                    var entry = ToFixEntry(relativeFile, fix);
                    allResults.Add(entry);

                    if (ShouldApply(fix.Safety, includeReviewNeeded))
                    {
                        fileApplied.Add(entry);
                    }
                }

                allApplied.AddRange(fileApplied);

                if (fileApplied.Count > 0)
                {
                    // Collect only edits from fixes that passed the safety gate. Validate in dry-run too so
                    // the JSON never promises a write plan that would later fail or corrupt a file.
                    var safeActions = fixes.Where(f => ShouldApply(f.Safety, includeReviewNeeded)).ToList();
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
            return EmitError(useText, $"Fix failed: {ex.Message}", projectDir);
        }
    }

    /// <summary>
    /// Returns true when a fix at the given safety level should be written to disk.
    /// </summary>
    public static bool ShouldApply(FixSafety safety, bool includeReviewNeeded)
    {
        return safety switch
        {
            FixSafety.Safe => true,
            FixSafety.ReviewNeeded => includeReviewNeeded,
            FixSafety.SuggestionOnly => false,
            _ => false
        };
    }

    public static int ShowHelp()
    {
        Console.WriteLine(@"N# Auto-Fix

Usage: nlc fix [options] [project-dir]

Options:
  --json                    Output as JSON (default)
  --text                    Output as human-readable summary
  --project                 Project root directory (default: current directory)
  --file                    Fix a single file
  --dry-run                 Preview fixes without writing files
  --include-review-needed   Also apply fixes that may need review (e.g. unused import removal)
  --help, -h                Show this help text

Safety levels:
  Safe              Always applied by default
  ReviewNeeded      Only applied with --include-review-needed flag
  SuggestionOnly    Never applied automatically — reported in results only

Examples:
  nlc fix
  nlc fix --dry-run --text
  nlc fix --include-review-needed
  nlc fix --file Program.nl
  nlc fix --project examples/16-task-cli");

        return 0;
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
            Console.Error.WriteLine("Nothing to fix.");
            return;
        }

        // Report applied fixes
        if (applied.Count > 0)
        {
            var verb = dryRun ? "Would fix" : "Fixed";
            var fileWord = filesModified == 1 ? "file" : "files";
            Console.Error.WriteLine($"{verb} {applied.Count} issue{(applied.Count == 1 ? "" : "s")} in {filesModified} {fileWord}:");

            var byFile = applied.GroupBy(f => f.File);
            foreach (var group in byFile)
            {
                Console.Error.WriteLine($"  {group.Key}:");
                foreach (var fix in group)
                {
                    Console.Error.WriteLine($"    [{fix.DiagnosticCode}] {fix.Title}");
                }
            }
        }

        // Report skipped fixes
        var skipped = results.Where(r => !applied.Contains(r)).ToList();
        if (skipped.Count > 0)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine($"Skipped {skipped.Count} fix{(skipped.Count == 1 ? "" : "es")}:");
            foreach (var fix in skipped)
            {
                var reason = fix.Safety == "suggestionOnly"
                    ? "suggestion only — manual review required"
                    : "requires --include-review-needed flag";
                Console.Error.WriteLine($"  [{fix.DiagnosticCode}] {fix.Title} ({reason})");
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

    private static string GetProjectDir(string[] args)
    {
        var projectOption = GetOption(args, "--project");
        if (!string.IsNullOrWhiteSpace(projectOption))
            return Path.GetFullPath(projectOption);

        var positional = GetFirstPositionalArg(args, "--project", "--file");
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

    private static string? GetFirstPositionalArg(string[] args, params string[] optionsWithValues)
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

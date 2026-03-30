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
/// Pipeline: discover files → parse → lint → get fixes → apply edits → write back
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
                    Console.Write(ResultJson(projectDir, dryRun, Array.Empty<AppliedFix>(), 0));
                return 0;
            }

            // Collect and apply fixes
            var allAppliedFixes = new List<AppliedFix>();
            var filesModified = 0;

            foreach (var file in files)
            {
                var source = File.ReadAllText(file);
                var fixes = FixApplicator.GetFixesForFile(file, source);

                if (fixes.Count == 0) continue;

                var relativeFile = NormalizePath(Path.GetRelativePath(projectDir, file));
                var appliedForFile = fixes.Select(f => new AppliedFix(
                    relativeFile, f.DiagnosticCode, f.Title, f.Edits)).ToList();

                allAppliedFixes.AddRange(appliedForFile);

                if (!dryRun)
                {
                    // Collect all edits for this file and apply them
                    var allEdits = fixes.SelectMany(f => f.Edits).ToList();
                    var fixedSource = FixApplicator.ApplyEdits(source, allEdits);

                    if (fixedSource != source)
                    {
                        File.WriteAllText(file, fixedSource);
                        filesModified++;
                    }
                }
                else
                {
                    filesModified++; // Would modify
                }
            }

            // Output results
            if (useText)
            {
                OutputText(allAppliedFixes, filesModified, dryRun);
            }
            else
            {
                Console.Write(ResultJson(projectDir, dryRun, allAppliedFixes, filesModified));
            }

            return dryRun && filesModified > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            return EmitError(useText, $"Fix failed: {ex.Message}", projectDir);
        }
    }

    public static int ShowHelp()
    {
        Console.WriteLine(@"N# Auto-Fix

Usage: nlc fix [options] [project-dir]

Options:
  --json        Output as JSON (default)
  --text        Output as human-readable summary
  --project     Project root directory (default: current directory)
  --file        Fix a single file
  --dry-run     Preview fixes without writing files
  --help, -h    Show this help text

Examples:
  nlc fix
  nlc fix --dry-run --text
  nlc fix --file Program.nl
  nlc fix --project examples/16-task-cli");

        return 0;
    }

    private static void OutputText(List<AppliedFix> fixes, int filesModified, bool dryRun)
    {
        if (fixes.Count == 0)
        {
            Console.Error.WriteLine("Nothing to fix.");
            return;
        }

        var verb = dryRun ? "Would fix" : "Fixed";
        var fileWord = filesModified == 1 ? "file" : "files";
        Console.Error.WriteLine($"{verb} {fixes.Count} issue{(fixes.Count == 1 ? "" : "s")} in {filesModified} {fileWord}:");

        var byFile = fixes.GroupBy(f => f.File);
        foreach (var group in byFile)
        {
            Console.Error.WriteLine($"  {group.Key}:");
            foreach (var fix in group)
            {
                Console.Error.WriteLine($"    [{fix.DiagnosticCode}] {fix.Title}");
            }
        }
    }

    private static string ResultJson(string projectDir, bool dryRun, IReadOnlyCollection<AppliedFix> fixes, int filesModified)
    {
        var normalizedProjectRoot = NormalizePath(Path.GetFullPath(projectDir));
        var normalizedFixes = fixes.Select(f => new
        {
            file = NormalizePath(f.File),
            diagnostic = f.DiagnosticCode,
            title = f.Title,
            edits = f.Edits.Select(e => new
            {
                startLine = e.StartLine,
                startColumn = e.StartColumn,
                endLine = e.EndLine,
                endColumn = e.EndColumn,
                newText = e.NewText
            }).ToList()
        }).ToList();

        var envelope = new
        {
            schemaVersion = 1,
            command = "fix",
            projectRoot = normalizedProjectRoot,
            dryRun,
            ok = !dryRun || filesModified == 0,
            filesModified,
            results = normalizedFixes,
            fixesApplied = normalizedFixes
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
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

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

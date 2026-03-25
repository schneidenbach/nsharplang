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
        if (args.Contains("--help") || args.Contains("-h"))
        {
            ShowHelp();
            return 0;
        }

        var dryRun = args.Contains("--dry-run");
        var useText = args.Contains("--text");
        var fileArg = GetOption(args, "--file");
        var projectDir = GetOption(args, "--project") ?? Directory.GetCurrentDirectory();

        if (!Directory.Exists(projectDir))
        {
            Console.Error.WriteLine($"Directory not found: {projectDir}");
            return 1;
        }

        try
        {
            // Discover files
            List<string> files;
            if (fileArg != null)
            {
                var fullPath = Path.IsPathRooted(fileArg) ? fileArg : Path.Combine(projectDir, fileArg);
                if (!File.Exists(fullPath))
                {
                    Console.Error.WriteLine($"File not found: {fullPath}");
                    return 1;
                }
                files = new List<string> { fullPath };
            }
            else
            {
                var config = ProjectFileParser.ParseFromDirectory(projectDir);
                files = config.GetSourceFiles(projectDir, includeTests: false)
                    .Select(f => Path.GetFullPath(f))
                    .ToList();
            }

            if (files.Count == 0)
            {
                if (useText)
                    Console.Error.WriteLine("No .nl files found.");
                else
                    Console.Write(EmptyResultJson());
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

                var relativeFile = Path.GetRelativePath(projectDir, file);
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
                OutputJson(allAppliedFixes, filesModified, dryRun);
            }

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Fix failed: {ex.Message}");
            return 1;
        }
    }

    private static void OutputJson(List<AppliedFix> fixes, int filesModified, bool dryRun)
    {
        var envelope = new
        {
            schemaVersion = 1,
            command = "fix",
            dryRun,
            filesModified,
            fixesApplied = fixes.Select(f => new
            {
                file = f.File,
                diagnostic = f.DiagnosticCode,
                title = f.Title,
                edits = f.Edits.Select(e => new
                {
                    startLine = e.StartLine,
                    startColumn = e.StartColumn,
                    endLine = e.EndLine,
                    endColumn = e.EndColumn,
                    newText = e.NewText
                })
            })
        };
        Console.Write(JsonSerializer.Serialize(envelope, JsonOptions));
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

    private static string EmptyResultJson()
    {
        var envelope = new
        {
            schemaVersion = 1,
            command = "fix",
            dryRun = false,
            filesModified = 0,
            fixesApplied = Array.Empty<object>()
        };
        return JsonSerializer.Serialize(envelope, JsonOptions);
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

    private static void ShowHelp()
    {
        Console.WriteLine("Usage: nlc fix [--project <dir>] [--file <path>] [--dry-run] [--text]");
        Console.WriteLine();
        Console.WriteLine("Auto-apply fixable diagnostics for an N# project or file.");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --project <dir>   Project root directory (default: current directory)");
        Console.WriteLine("  --file <path>     Restrict fixes to a single file");
        Console.WriteLine("  --dry-run         Show proposed fixes without modifying files");
        Console.WriteLine("  --text            Human-readable output");
        Console.WriteLine("  --help, -h        Show this help");
    }
}

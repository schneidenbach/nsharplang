using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
    public static int Execute(string[] args)
    {
        var arguments = FixCommandArgumentKernels.GetArgumentSummary(args);
        if (arguments.ShowHelp)
        {
            Console.WriteLine(FixCommandKernels.GetHelpText());
            return 0;
        }

        var dryRun = arguments.DryRun;
        var useText = FixCommandArgumentKernels.GetEffectiveOutputMode(arguments.UseText) == 2;
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
                    Console.Write(FixCommandKernels.ResultJson(projectDir, dryRun, includeReviewNeeded,
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

                var relativeFile = Path.GetRelativePath(projectDir, file);

                var safeActions = FixCommandKernels.FilterBySafety(fixes, includeReviewNeeded);

                foreach (var fix in fixes)
                {
                    var entry = FixCommandKernels.ToFixEntry(relativeFile, fix);
                    allResults.Add(entry);
                }

                var fileApplied = new List<FixEntry>(safeActions.Count);
                foreach (var fix in safeActions)
                {
                    fileApplied.Add(FixCommandKernels.ToFixEntry(relativeFile, fix));
                }
                allApplied.AddRange(fileApplied);

                if (fileApplied.Count > 0)
                {
                    // Collect only edits from fixes that passed the safety gate. Validate in dry-run too so
                    // the JSON never promises a write plan that would later fail or corrupt a file.
                    var allEdits = safeActions.SelectMany(f => f.Edits).ToList();
                    FixApplicatorCore.ValidateAndSortEdits(source, allEdits);

                    if (!dryRun)
                    {
                        var fixedSource = FixApplicatorCore.ApplyEdits(source, allEdits);

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
                Console.Error.Write(FixCommandKernels.ResultText(allResults, allApplied, filesModified, dryRun, includeReviewNeeded));
            }
            else
            {
                Console.Write(FixCommandKernels.ResultJson(projectDir, dryRun, includeReviewNeeded, allResults, allApplied, filesModified));
            }

            return FixCommandKernels.GetExitCode(dryRun, filesModified);
        }
        catch (Exception ex)
        {
            return EmitError(useText, FixCommandKernels.GetFailedMessage(ex.Message), projectDir);
        }
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

}

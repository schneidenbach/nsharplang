using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// nlc tidy — Identify and optionally remove unused NuGet dependencies from project.yml.
///
/// Conservative by design: a dependency is only classified as "possibly-unused" when no
/// import statement in any .nl source file could plausibly reference its namespace.
/// When in doubt the result is "unknown" rather than "unused".
/// </summary>
public static class TidyCommand
{
    public static int Execute(string[] args)
    {
        var options = TidyCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(TidyCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = options.ProjectOption ?? Directory.GetCurrentDirectory();
        var fix = options.Fix;
        var outputMode = TidyCommandKernels.GetOutputMode(options.Json);

        var projectYml = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYml))
        {
            if (outputMode == 1)
            {
                WriteJson(new
                {
                    schemaVersion = 1,
                    command = "tidy",
                    ok = false,
                    error = new { message = TidyCommandKernels.GetMissingProjectFileJsonMessage() }
                });
            }
            else
            {
                Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(
                    TidyCommandKernels.GetMissingProjectFileTextMessage()));
            }
            return 1;
        }

        ProjectConfig config;
        try
        {
            config = ProjectFileParser.Parse(projectYml);
        }
        catch (Exception ex)
        {
            if (outputMode == 1)
            {
                WriteJson(new
                {
                    schemaVersion = 1,
                    command = "tidy",
                    ok = false,
                    error = new { message = TidyCommandKernels.GetParseFailedMessage(ex.Message) }
                });
            }
            else
            {
                Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(
                    TidyCommandKernels.GetParseFailedMessage(ex.Message)));
            }
            return 1;
        }

        // Collect all import namespaces from .nl source files
        var importedNamespaces = CollectImportedNamespaces(projectRoot);

        var results = ClassifyDependencies(config.Dependencies, importedNamespaces);

        var summary = SummarizeDependencies(results);
        var ok = summary.PossiblyUnusedCount == 0;

        if (outputMode == 1)
        {
            WriteJson(new
            {
                schemaVersion = 1,
                command = "tidy",
                ok,
                projectRoot = projectRoot.Replace('\\', '/'),
                dependencies = results.Select(r => new
                {
                    name = r.Name,
                    version = r.Version,
                    status = r.Status,
                    reason = r.Reason
                })
            });
        }
        else
        {
            PrintTable(results, projectRoot, summary);
        }

        // Apply fixes if requested
        if (fix)
        {
            var selectedIndices = TidyCommandKernels.SelectPossiblyUnusedDependencyIndices(
                results.Select(static result => result.Status).ToArray());
            var toRemove = new List<DependencyStatus>(selectedIndices.Length);
            foreach (var index in selectedIndices)
            {
                toRemove.Add(results[index]);
            }

            if (toRemove.Count == 0)
            {
                if (outputMode == 2) Console.WriteLine(TidyCommandKernels.GetNothingToRemoveMessage());
            }
            else
            {
                RemoveDependencies(projectYml, toRemove.Select(r => r.Name).ToList());
                if (outputMode == 2)
                    Console.WriteLine(TidyCommandKernels.GetRemovedDependenciesMessage(toRemove.Count));
            }
        }

        return 0;
    }

    // ── Analysis ──────────────────────────────────────────────────────────

    /// <summary>
    /// Collect all namespace fragments referenced in import statements across all .nl files.
    /// </summary>
    private static HashSet<string> CollectImportedNamespaces(string projectRoot)
    {
        var namespaces = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (!Directory.Exists(projectRoot))
            return namespaces;

        foreach (var file in Directory.GetFiles(projectRoot, "*.nl", SearchOption.AllDirectories))
        {
            try
            {
                foreach (var line in File.ReadLines(file))
                {
                    var importedNamespace = TidyCommandKernels.GetImportedNamespace(line);
                    if (importedNamespace != null)
                        namespaces.Add(importedNamespace);
                }
            }
            catch
            {
                // Ignore unreadable files
            }
        }

        return namespaces;
    }

    private static List<DependencyStatus> ClassifyDependencies(
        IReadOnlyList<Reference> dependencies,
        HashSet<string> importedNamespaces)
    {
        var nugetDependencies = new List<Reference>();
        foreach (var dep in dependencies)
        {
            if (dep.Nuget != null)
                nugetDependencies.Add(dep);
        }

        var statusRanks = TidyCommandKernels.ClassifyDependencyStatusRanks(
                nugetDependencies,
                importedNamespaces);
        var results = new List<DependencyStatus>(nugetDependencies.Count);
        for (var i = 0; i < nugetDependencies.Count; i++)
        {
            var dep = nugetDependencies[i];
            var status = CreateDependencyStatusFromRank(dep.Nuget!, dep.Version, statusRanks[i]);
            if (status == null)
                throw new InvalidOperationException("N# tidy dependency classifier kernel produced an invalid status rank.");

            results.Add(status);
        }

        return results;
    }

    private static DependencyStatus? CreateDependencyStatusFromRank(
        string packageName,
        string? version,
        int statusRank)
    {
        var firstDot = packageName.IndexOf('.');
        if (statusRank == 3 && firstDot <= 0)
        {
            return new DependencyStatus(packageName, version, "unknown",
                TidyCommandKernels.GetUnknownReasonMessage());
        }

        if (firstDot <= 0)
            return null;

        var secondDot = packageName.IndexOf('.', firstDot + 1);
        var prefix1 = packageName[..firstDot];
        var prefix2 = secondDot > firstDot
            ? packageName[..secondDot]
            : packageName;

        return statusRank switch
        {
            2 => new DependencyStatus(packageName, version, "used",
                TidyCommandKernels.GetUsedReasonMessage(prefix2)),
            1 => new DependencyStatus(packageName, version, "possibly-unused",
                TidyCommandKernels.GetPossiblyUnusedReasonMessage(prefix1, prefix2)),
            _ => null
        };
    }

    // ── Fix ───────────────────────────────────────────────────────────────

    private static void RemoveDependencies(string projectYml, List<string> packageNames)
    {
        var lines = File.ReadAllLines(projectYml);
        File.WriteAllLines(projectYml, TidyCommandKernels.FilterRemovalLines(lines, packageNames));
    }

    // ── Output ────────────────────────────────────────────────────────────

    private static TidyDependencySummary SummarizeDependencies(IReadOnlyList<DependencyStatus> results)
    {
        var summary = TidyCommandKernels.SummarizeDependencyStatuses(
            results.Select(static result => result.Status).ToArray());
        return new TidyDependencySummary(
            summary.PossiblyUnusedCount,
            summary.UnknownCount);
    }

    private static void PrintTable(
        List<DependencyStatus> results,
        string projectRoot,
        TidyDependencySummary summary)
    {
        if (results.Count == 0)
        {
            Console.WriteLine(TidyCommandKernels.GetNoNuGetDependenciesMessage(projectRoot));
            return;
        }

        var nameWidth = Math.Max(results.Max(r => r.Name.Length), 12);
        var statusWidth = 15;

        Console.WriteLine(TidyCommandKernels.GetTableHeader("Package".PadRight(nameWidth), "Status".PadRight(statusWidth)));
        Console.WriteLine(TidyCommandKernels.GetTableSeparator(new string('-', nameWidth), new string('-', statusWidth)));

        foreach (var r in results)
        {
            Console.WriteLine(TidyCommandKernels.GetTableRow(
                r.Name.PadRight(nameWidth),
                r.Status.PadRight(statusWidth),
                r.Reason));
        }

        var possiblyUnused = summary.PossiblyUnusedCount;
        var unknown = summary.UnknownCount;

        Console.WriteLine();
        if (possiblyUnused > 0)
            Console.WriteLine(TidyCommandKernels.GetPossiblyUnusedFoundMessage(possiblyUnused));
        else if (unknown > 0)
            Console.WriteLine(TidyCommandKernels.GetAllDependenciesAccountedForMessage(unknown));
        else
            Console.WriteLine(TidyCommandKernels.GetAllDependenciesInUseMessage());
    }

    private static void WriteJson(object value)
    {
        var options = new JsonSerializerOptions
        {
            WriteIndented = false,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
        Console.WriteLine(JsonSerializer.Serialize(value, options));
    }

    // ── Types ─────────────────────────────────────────────────────────────

    private sealed record DependencyStatus(string Name, string? Version, string Status, string Reason);

    private readonly record struct TidyDependencySummary(
        int PossiblyUnusedCount,
        int UnknownCount);
}

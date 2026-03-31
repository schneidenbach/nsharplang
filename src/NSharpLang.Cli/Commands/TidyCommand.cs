using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
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
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = GetOption(args, "--project") ?? Directory.GetCurrentDirectory();
        var fix = args.Contains("--fix");
        var json = args.Contains("--json");

        var projectYml = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYml))
        {
            if (json)
            {
                WriteJson(new
                {
                    schemaVersion = 1,
                    command = "tidy",
                    ok = false,
                    error = new { message = "No project.yml found in the specified directory." }
                });
            }
            else
            {
                Console.Error.WriteLine("Error: No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.");
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
            if (json)
            {
                WriteJson(new
                {
                    schemaVersion = 1,
                    command = "tidy",
                    ok = false,
                    error = new { message = $"Failed to parse project.yml: {ex.Message}" }
                });
            }
            else
            {
                Console.Error.WriteLine($"Error: Failed to parse project.yml: {ex.Message}");
            }
            return 1;
        }

        // Collect all import namespaces from .nl source files
        var importedNamespaces = CollectImportedNamespaces(projectRoot);

        // Analyse each NuGet dependency
        var results = new List<DependencyStatus>();
        foreach (var dep in config.Dependencies)
        {
            if (dep.Nuget == null)
                continue; // Only analyse NuGet packages

            var status = ClassifyDependency(dep.Nuget, dep.Version, importedNamespaces);
            results.Add(status);
        }

        var ok = results.All(r => r.Status != "possibly-unused");

        if (json)
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
            PrintTable(results, projectRoot);
        }

        // Apply fixes if requested
        if (fix)
        {
            var toRemove = results.Where(r => r.Status == "possibly-unused").ToList();
            if (toRemove.Count == 0)
            {
                if (!json) Console.WriteLine("Nothing to remove.");
            }
            else
            {
                RemoveDependencies(projectYml, toRemove.Select(r => r.Name).ToList());
                if (!json)
                    Console.WriteLine($"Removed {toRemove.Count} possibly-unused {(toRemove.Count == 1 ? "dependency" : "dependencies")}.");
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
                    var trimmed = line.TrimStart();
                    if (!trimmed.StartsWith("import ", StringComparison.Ordinal))
                        continue;

                    // import <namespace>  or  import <namespace>.<type>
                    var importValue = trimmed["import ".Length..].Trim();

                    // Remove trailing semicolons, braces etc. — keep the dotted identifier
                    var clean = new string(importValue.TakeWhile(c => char.IsLetterOrDigit(c) || c == '.' || c == '_').ToArray());
                    if (clean.Length > 0)
                        namespaces.Add(clean);
                }
            }
            catch
            {
                // Ignore unreadable files
            }
        }

        return namespaces;
    }

    /// <summary>
    /// Classify a single NuGet dependency as "used", "possibly-unused", or "unknown".
    ///
    /// Heuristic: a NuGet package named "A.B.C" typically publishes types under namespaces
    /// starting with "A" or "A.B".  We check whether any imported namespace starts with the
    /// first one or two segments of the package ID (case-insensitive).
    ///
    /// If we cannot derive a plausible namespace (e.g. single-segment package names like
    /// "Polly") we return "unknown" instead of guessing.
    /// </summary>
    private static DependencyStatus ClassifyDependency(
        string packageName,
        string? version,
        HashSet<string> importedNamespaces)
    {
        var segments = packageName.Split('.');
        if (segments.Length < 2)
        {
            // Single-segment package (e.g. "Polly") — cannot determine namespace safely
            return new DependencyStatus(packageName, version, "unknown",
                "Cannot determine namespace for single-segment package name; manual review required.");
        }

        // Candidate namespace prefixes: first segment ("Newtonsoft") and first two ("Newtonsoft.Json")
        var prefix1 = segments[0];
        var prefix2 = string.Join(".", segments.Take(2));

        var matched = importedNamespaces.Any(ns =>
            ns.StartsWith(prefix1 + ".", StringComparison.OrdinalIgnoreCase) ||
            ns.Equals(prefix1, StringComparison.OrdinalIgnoreCase) ||
            ns.StartsWith(prefix2 + ".", StringComparison.OrdinalIgnoreCase) ||
            ns.Equals(prefix2, StringComparison.OrdinalIgnoreCase));

        if (matched)
            return new DependencyStatus(packageName, version, "used",
                $"Import statement references namespace matching '{prefix2}'.");

        return new DependencyStatus(packageName, version, "possibly-unused",
            $"No import statement found referencing '{prefix1}' or '{prefix2}'.");
    }

    // ── Fix ───────────────────────────────────────────────────────────────

    private static void RemoveDependencies(string projectYml, List<string> packageNames)
    {
        var lines = new List<string>(File.ReadAllLines(projectYml));
        var toRemove = new HashSet<string>(packageNames, StringComparer.OrdinalIgnoreCase);

        var filtered = lines.Where(line =>
        {
            var trimmed = line.TrimStart();
            if (!trimmed.StartsWith("- "))
                return true;

            // Match "  - PackageName@version" or "  - nuget: PackageName"
            foreach (var pkg in toRemove)
            {
                if (trimmed.StartsWith($"- {pkg}@", StringComparison.OrdinalIgnoreCase) ||
                    trimmed.StartsWith($"- {pkg}", StringComparison.OrdinalIgnoreCase) ||
                    trimmed.Contains($"nuget: {pkg}", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }
            }

            return true;
        }).ToList();

        File.WriteAllLines(projectYml, filtered);
    }

    // ── Output ────────────────────────────────────────────────────────────

    private static void PrintTable(List<DependencyStatus> results, string projectRoot)
    {
        if (results.Count == 0)
        {
            Console.WriteLine($"No NuGet dependencies found in {projectRoot}");
            return;
        }

        var nameWidth = Math.Max(results.Max(r => r.Name.Length), 12);
        var statusWidth = 15;

        Console.WriteLine($"  {"Package".PadRight(nameWidth)}  {"Status".PadRight(statusWidth)}  Reason");
        Console.WriteLine($"  {new string('-', nameWidth)}  {new string('-', statusWidth)}  ------");

        foreach (var r in results)
        {
            Console.WriteLine($"  {r.Name.PadRight(nameWidth)}  {r.Status.PadRight(statusWidth)}  {r.Reason}");
        }

        var possiblyUnused = results.Count(r => r.Status == "possibly-unused");
        var unknown = results.Count(r => r.Status == "unknown");

        Console.WriteLine();
        if (possiblyUnused > 0)
            Console.WriteLine($"{possiblyUnused} possibly-unused {(possiblyUnused == 1 ? "dependency" : "dependencies")} found. Run 'nlc tidy --fix' to remove them.");
        else if (unknown > 0)
            Console.WriteLine($"All dependencies accounted for ({unknown} could not be determined).");
        else
            Console.WriteLine("All dependencies appear to be in use.");
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

    // ── Helpers ───────────────────────────────────────────────────────────

    private static string? GetOption(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Tidy

Usage: nlc tidy [options]

Identify and optionally remove unused NuGet dependencies from project.yml.

Each dependency is classified as:
  used            — an import statement plausibly references the package namespace
  possibly-unused — no import statement references the package namespace
  unknown         — cannot determine usage (e.g. single-segment package names)

The command is conservative: 'unknown' is reported rather than incorrectly
flagging a dependency as unused.

Options:
  --project <dir>   Project directory (default: current directory)
  --fix             Remove all possibly-unused dependencies from project.yml
  --json            Emit structured JSON output
  --help, -h        Show this help text

JSON schema (schemaVersion 1):
  { schemaVersion, command, ok, projectRoot,
    dependencies: [{ name, version, status, reason }] }

Examples:
  nlc tidy                   Report unused dependencies
  nlc tidy --fix             Remove possibly-unused dependencies
  nlc tidy --json            Machine-readable output
  nlc tidy --project ./lib   Analyse a different project

Exit codes:
  0  All dependencies in use (or tidy succeeded)
  1  Error (missing project.yml, parse failure)");

        return 0;
    }

    // ── Types ─────────────────────────────────────────────────────────────

    private sealed record DependencyStatus(string Name, string? Version, string Status, string Reason);
}

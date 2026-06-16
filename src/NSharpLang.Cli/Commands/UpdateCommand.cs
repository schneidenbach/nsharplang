using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class UpdateCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = Directory.GetCurrentDirectory();
        var projectYml = Path.Combine(projectRoot, "project.yml");
        var dryRun = args.Contains("--dry-run");

        if (!File.Exists(projectYml))
            return Error("No project.yml found.");

        var targetPackage = GetTargetPackage(args);

        try
        {
            var config = ProjectFileParser.Parse(projectYml);
            var allNuGetDeps = FilterNuGetDependencies(config.Dependencies, targetPackage: null);

            if (allNuGetDeps.Count == 0)
            {
                Console.WriteLine("No NuGet dependencies to update.");
                return 0;
            }

            var nugetDeps = allNuGetDeps;
            if (targetPackage != null)
            {
                nugetDeps = FilterNuGetDependencies(allNuGetDeps, targetPackage);
                if (nugetDeps.Count == 0)
                    return Error($"Package '{targetPackage}' not found in dependencies.");
            }

            var lines = File.ReadAllLines(projectYml);
            var updated = 0;

            foreach (var dep in nugetDeps)
            {
                var latest = AddCommand.ResolveLatestVersion(dep.Nuget!);
                if (latest == null)
                {
                    Console.Error.WriteLine($"  Could not resolve latest version for {dep.Nuget}");
                    continue;
                }

                if (dep.Version == latest)
                {
                    if (dryRun || targetPackage != null)
                        Console.WriteLine($"  {dep.Nuget}@{dep.Version} is up to date");
                    continue;
                }

                Console.WriteLine($"  {dep.Nuget}: {dep.Version ?? "unversioned"} -> {latest}");

                if (!dryRun)
                {
                    // Text-based version replacement
                    for (var i = 0; i < lines.Length; i++)
                    {
                        var trimmed = lines[i].Trim();

                        // Shorthand: "- Package@OldVersion"
                        if (trimmed.StartsWith("- ") && trimmed.Contains($"{dep.Nuget}@", StringComparison.OrdinalIgnoreCase))
                        {
                            var atIdx = lines[i].IndexOf('@');
                            if (atIdx > 0)
                                lines[i] = lines[i][..(atIdx + 1)] + latest;
                            break;
                        }

                        // Mapping: look for nuget line, then update next version line
                        if (trimmed.Contains($"nuget: {dep.Nuget}", StringComparison.OrdinalIgnoreCase))
                        {
                            for (var j = i + 1; j < lines.Length && j <= i + 3; j++)
                            {
                                if (lines[j].TrimStart().StartsWith("version:"))
                                {
                                    var indent = lines[j][..lines[j].IndexOf('v')];
                                    lines[j] = $"{indent}version: {latest}";
                                    break;
                                }
                            }
                            break;
                        }
                    }
                    updated++;
                }
            }

            if (!dryRun && updated > 0)
            {
                File.WriteAllLines(projectYml, lines);
                RestoreCommand.Restore(projectRoot, quiet: true);
                Console.WriteLine($"Updated {updated} package{(updated == 1 ? "" : "s")}.");
            }
            else if (dryRun)
            {
                Console.WriteLine("(dry run — no changes made)");
            }
            else
            {
                Console.WriteLine("All packages are up to date.");
            }

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Update failed: {ex.Message}");
        }
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Update Dependencies

Usage: nlc update [package] [options]

Update NuGet dependencies to their latest versions. If a package name is
given, only that package is updated. Otherwise all NuGet dependencies
are checked.

Options:
  --dry-run       Show what would change without modifying files
  --help, -h      Show this help text

Examples:
  nlc update
  nlc update Newtonsoft.Json
  nlc update --dry-run

Exit codes:
  0  Update completed successfully
  1  Update failed");

        return 0;
    }

    internal static string? GetTargetPackage(string[] args)
    {
        return NSharpLang.Cli.NSharpCliDogfoodAdapter.TryGetFirstPositionalArg(args, Array.Empty<string>(), out var positional)
            ? positional
            : GetTargetPackageWithCSharp(args);
    }

    private static string? GetTargetPackageWithCSharp(string[] args)
        => args.FirstOrDefault(arg => !arg.StartsWith("-"));

    internal static List<Reference> FilterNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        string? targetPackage)
    {
        if (targetPackage == null)
        {
            return UpdateDependencyFilter.TryFilterAllNuGetDependencies(
                dependencies,
                out var allNuGetDependencies)
                ? allNuGetDependencies
                : FilterNuGetDependenciesWithCSharp(dependencies, targetPackage);
        }

        return UpdateDependencyFilter.TryFilterTargetNuGetDependencies(
            dependencies,
            targetPackage,
            out var filteredDependencies)
            ? filteredDependencies
            : FilterNuGetDependenciesWithCSharp(dependencies, targetPackage);
    }

    private static List<Reference> FilterNuGetDependenciesWithCSharp(
        IEnumerable<Reference> dependencies,
        string? targetPackage)
    {
        var nugetDeps = dependencies.Where(d => d.Nuget != null).ToList();
        if (targetPackage != null)
        {
            nugetDeps = nugetDeps.Where(d =>
                string.Equals(d.Nuget, targetPackage, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        return nugetDeps;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

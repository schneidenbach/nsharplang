using System;
using System.Collections.Generic;
using System.IO;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class UpdateCommand
{
    public static int Execute(string[] args)
    {
        var arguments = GetArgumentSummary(args);
        if (arguments.ShowHelp)
            return ShowHelp();

        var projectRoot = Directory.GetCurrentDirectory();
        var projectYml = Path.Combine(projectRoot, "project.yml");
        var dryRun = arguments.DryRun;

        if (!File.Exists(projectYml))
            return Error(UpdateCommandKernels.GetMissingProjectFileMessage());

        var targetPackage = arguments.TargetPackage;

        try
        {
            var config = ProjectFileParser.Parse(projectYml);
            var allNuGetDeps = FilterNuGetDependencies(config.Dependencies, targetPackage: null);

            if (allNuGetDeps.Count == 0)
            {
                Console.WriteLine(UpdateCommandKernels.GetNoNuGetDependenciesMessage());
                return 0;
            }

            var nugetDeps = allNuGetDeps;
            if (targetPackage != null)
            {
                nugetDeps = FilterNuGetDependencies(allNuGetDeps, targetPackage);
                if (nugetDeps.Count == 0)
                    return Error(UpdateCommandKernels.GetPackageNotFoundMessage(targetPackage));
            }

            var lines = File.ReadAllLines(projectYml);
            var updated = 0;

            foreach (var dep in nugetDeps)
            {
                var latest = AddCommand.ResolveLatestVersion(dep.Nuget!);
                if (latest == null)
                {
                    Console.Error.WriteLine(UpdateCommandKernels.GetResolveLatestFailureMessage(dep.Nuget!));
                    continue;
                }

                if (dep.Version == latest)
                {
                    if (dryRun || targetPackage != null)
                    {
                        Console.WriteLine(UpdateCommandKernels.GetPackageUpToDateMessage(
                            dep.Nuget!,
                            dep.Version ?? string.Empty));
                    }
                    continue;
                }

                Console.WriteLine(UpdateCommandKernels.GetPackageUpdateMessage(
                    dep.Nuget!,
                    dep.Version ?? string.Empty,
                    latest));

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
                Console.WriteLine(UpdateCommandKernels.GetUpdatedPackagesMessage(updated));
            }
            else if (dryRun)
            {
                Console.WriteLine(UpdateCommandKernels.GetDryRunMessage());
            }
            else
            {
                Console.WriteLine(UpdateCommandKernels.GetAllPackagesUpToDateMessage());
            }

            return 0;
        }
        catch (Exception ex)
        {
            return Error(UpdateCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static int ShowHelp()
    {
        Console.WriteLine(UpdateCommandKernels.GetHelpText());
        return 0;
    }

    internal static UpdateArgumentSummary GetArgumentSummary(string[] args)
        => UpdateCommandKernels.GetArgumentSummary(args);

    internal static List<Reference> FilterNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        string? targetPackage)
    {
        if (targetPackage == null)
            return UpdateDependencyFilter.FilterAllNuGetDependencies(dependencies);

        return UpdateDependencyFilter.FilterTargetNuGetDependencies(dependencies, targetPackage);
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

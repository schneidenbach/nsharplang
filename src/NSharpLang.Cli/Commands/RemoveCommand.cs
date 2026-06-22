using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Cli.Commands;

public static class RemoveCommand
{
    public static int Execute(string[] args)
    {
        var arguments = GetArgumentSummary(args);
        if (arguments.ShowHelp)
            return ShowHelp();

        if (args.Length == 0)
            return Error(RemoveCommandKernels.GetUsageMessage());

        var packageName = arguments.PackageOperand;
        if (string.IsNullOrWhiteSpace(packageName))
            return Error(RemoveCommandKernels.GetUsageMessage());

        var projectRoot = Directory.GetCurrentDirectory();
        var projectYml = Path.Combine(projectRoot, "project.yml");

        if (!File.Exists(projectYml))
            return Error(RemoveCommandKernels.GetMissingProjectFileMessage());

        var lines = new List<string>(File.ReadAllLines(projectYml));
        var removed = false;

        // Find and remove the dependency (text-based to preserve comments)
        for (var i = 0; i < lines.Count; i++)
        {
            var action = GetDependencyLineAction(lines[i], packageName);
            if (action == RemoveDependencyLineAction.RemoveSingleLine)
            {
                lines.RemoveAt(i);
                removed = true;
                break;
            }

            if (action == RemoveDependencyLineAction.RemoveMappingBlock)
            {
                lines.RemoveAt(i);
                // Remove continuation lines (version:, etc.)
                while (i < lines.Count)
                {
                    if (ShouldStopDependencyContinuationLine(lines[i]))
                        break;
                    lines.RemoveAt(i);
                }
                removed = true;
                break;
            }
        }

        if (!removed)
            return Error(RemoveCommandKernels.GetPackageNotFoundMessage(packageName));

        File.WriteAllLines(projectYml, lines);

        // Restore
        RestoreCommand.Restore(projectRoot, quiet: true);

        Console.WriteLine(RemoveCommandKernels.GetRemovedMessage(packageName));
        return 0;
    }

    internal static string? GetPackageOperand(string[] args)
        => GetArgumentSummary(args).PackageOperand;

    internal static RemoveArgumentSummary GetArgumentSummary(string[] args)
    {
        if (RemoveCommandKernels.TryGetArgumentSummary(args, out var summary))
            return summary;

        throw new InvalidOperationException("N# remove argument summary kernel rejected the arguments.");
    }

    internal static RemoveDependencyLineAction GetDependencyLineAction(string line, string packageName)
    {
        if (RemoveCommandKernels.TryGetDependencyLineAction(line, packageName, out var action))
            return action;

        throw new InvalidOperationException("N# remove dependency-line action kernel rejected the line.");
    }

    internal static bool ShouldStopDependencyContinuationLine(string line)
    {
        if (RemoveCommandKernels.TryShouldStopDependencyContinuationLine(line, out var shouldStop))
            return shouldStop;

        throw new InvalidOperationException("N# remove dependency continuation kernel rejected the line.");
    }

    static int ShowHelp()
    {
        Console.WriteLine(RemoveCommandKernels.GetHelpText());
        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

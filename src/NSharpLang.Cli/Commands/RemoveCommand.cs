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
        => RemoveCommandKernels.TryGetArgumentSummary(args, out var summary)
            ? summary
            : GetArgumentSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product remove argument parsing routes through RemoveCommandKernels.
    private static RemoveArgumentSummary GetArgumentSummaryWithCSharp(string[] args)
        => new(
            GetPackageOperandWithCSharp(args),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    private static string? GetPackageOperandWithCSharp(string[] args)
    {
        for (var i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return args[i];
        }

        return null;
    }

    internal static RemoveDependencyLineAction GetDependencyLineAction(string line, string packageName)
        => RemoveCommandKernels.TryGetDependencyLineAction(line, packageName, out var action)
            ? action
            : GetDependencyLineActionWithCSharp(line, packageName);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product remove dependency line matching routes through RemoveCommandKernels.
    private static RemoveDependencyLineAction GetDependencyLineActionWithCSharp(string line, string packageName)
    {
        var trimmed = line.Trim();

        if (trimmed.StartsWith("- ") &&
            (trimmed.Contains(packageName + "@", StringComparison.OrdinalIgnoreCase) ||
             trimmed.Equals($"- {packageName}", StringComparison.OrdinalIgnoreCase)))
            return RemoveDependencyLineAction.RemoveSingleLine;

        if ((trimmed.StartsWith("- nuget:", StringComparison.OrdinalIgnoreCase) ||
             trimmed.StartsWith("- framework:", StringComparison.OrdinalIgnoreCase)) &&
            trimmed.Contains(packageName, StringComparison.OrdinalIgnoreCase))
            return RemoveDependencyLineAction.RemoveMappingBlock;

        return RemoveDependencyLineAction.Keep;
    }

    internal static bool ShouldStopDependencyContinuationLine(string line)
        => RemoveCommandKernels.TryShouldStopDependencyContinuationLine(line, out var shouldStop)
            ? shouldStop
            : ShouldStopDependencyContinuationLineWithCSharp(line);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product remove dependency continuation pruning routes through RemoveCommandKernels.
    private static bool ShouldStopDependencyContinuationLineWithCSharp(string line)
        => line.Length == 0 ||
           line.TrimStart().StartsWith("- ") ||
           (!line.StartsWith(" ") && !line.StartsWith("\t"));

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
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

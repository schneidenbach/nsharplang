using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace NSharpLang.Cli.Commands;

public static class RemoveCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        if (args.Length == 0)
            return Error("Usage: nlc remove <package>");

        var packageName = args[0];
        var projectRoot = Directory.GetCurrentDirectory();
        var projectYml = Path.Combine(projectRoot, "project.yml");

        if (!File.Exists(projectYml))
            return Error("No project.yml found.");

        var lines = new List<string>(File.ReadAllLines(projectYml));
        var removed = false;

        // Find and remove the dependency (text-based to preserve comments)
        for (var i = 0; i < lines.Count; i++)
        {
            var trimmed = lines[i].Trim();

            // Match shorthand: "- Package@Version" or "- Package"
            if (trimmed.StartsWith("- ") &&
                (trimmed.Contains(packageName + "@", StringComparison.OrdinalIgnoreCase) ||
                 trimmed.Equals($"- {packageName}", StringComparison.OrdinalIgnoreCase)))
            {
                lines.RemoveAt(i);
                removed = true;
                break;
            }

            // Match mapping: "- nuget: Package" or "- framework: Package"
            if ((trimmed.StartsWith("- nuget:", StringComparison.OrdinalIgnoreCase) ||
                 trimmed.StartsWith("- framework:", StringComparison.OrdinalIgnoreCase)) &&
                trimmed.Contains(packageName, StringComparison.OrdinalIgnoreCase))
            {
                lines.RemoveAt(i);
                // Remove continuation lines (version:, etc.)
                while (i < lines.Count)
                {
                    var next = lines[i];
                    if (next.Length == 0 || next.TrimStart().StartsWith("- ") ||
                        (!next.StartsWith(" ") && !next.StartsWith("\t")))
                        break;
                    lines.RemoveAt(i);
                }
                removed = true;
                break;
            }
        }

        if (!removed)
            return Error($"Package '{packageName}' not found in dependencies.");

        File.WriteAllLines(projectYml, lines);

        // Restore
        RestoreCommand.Restore(projectRoot, quiet: true);

        Console.WriteLine($"Removed {packageName} from project.yml");
        return 0;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Remove Dependency

Usage: nlc remove <package>

Remove a dependency from project.yml.

Options:
  --help, -h    Show this help text

Examples:
  nlc remove Newtonsoft.Json
  nlc remove Microsoft.AspNetCore.App

Exit codes:
  0  Dependency removed successfully
  1  Failed to remove dependency");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

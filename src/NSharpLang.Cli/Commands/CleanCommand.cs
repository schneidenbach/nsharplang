using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace NSharpLang.Cli.Commands;

public static class CleanCommand
{
    private static readonly string[] ArtifactDirectories =
    {
        "bin",
        "obj",
        "nsharp",
        ".nlc"
    };

    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = GetProjectRoot(args);
        var cleanAll = args.Contains("--all");

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}");

        try
        {
            var removed = RemoveArtifacts(projectRoot);

            if (cleanAll)
            {
                var cacheExitCode = ClearNuGetCaches();
                if (cacheExitCode != 0)
                    return cacheExitCode;
            }

            if (removed.Count == 0)
            {
                Console.WriteLine($"No build artifacts found under {projectRoot}.");
            }
            else
            {
                Console.WriteLine($"Removed {removed.Count} build artifact director{(removed.Count == 1 ? "y" : "ies")}:");
                foreach (var path in removed)
                    Console.WriteLine($"  {path}");
            }

            if (cleanAll)
                Console.WriteLine("Cleared NuGet caches.");

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Clean failed: {ex.Message}");
        }
    }

    private static List<string> RemoveArtifacts(string projectRoot)
    {
        var removed = new List<string>();
        var directories = Directory.EnumerateDirectories(projectRoot, "*", SearchOption.AllDirectories)
            .Concat(ArtifactDirectories.Select(name => Path.Combine(projectRoot, name)))
            .Where(Directory.Exists)
            .Distinct(StringComparer.Ordinal)
            .Where(dir =>
            {
                var normalized = NormalizePath(dir);
                return !normalized.Contains("/node_modules/", StringComparison.Ordinal);
            })
            .Where(dir => ArtifactDirectories.Contains(Path.GetFileName(dir), StringComparer.Ordinal))
            .OrderByDescending(dir => dir.Length)
            .ToArray();

        foreach (var dir in directories)
        {
            Directory.Delete(dir, recursive: true);
            removed.Add(NormalizePath(Path.GetRelativePath(projectRoot, dir)));
        }

        removed.Sort(StringComparer.Ordinal);
        return removed;
    }

    private static int ClearNuGetCaches()
    {
        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = "nuget locals all --clear",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        });

        process?.WaitForExit();

        if (process?.ExitCode == 0)
            return 0;

        var stderr = process?.StandardError.ReadToEnd() ?? string.Empty;
        var stdout = process?.StandardOutput.ReadToEnd() ?? string.Empty;
        return Error($"Failed to clear NuGet caches.\n{stderr}{stdout}".Trim());
    }

    private static string GetProjectRoot(string[] args)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--project")
                return Path.GetFullPath(args[i + 1]);
        }

        return Path.GetFullPath(Directory.GetCurrentDirectory());
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Clean

Usage: nlc clean [options]

Remove local build artifacts for the current project. Equivalent to `cargo clean`
or `go clean`.

Options:
  --project <dir>   Project root directory (default: current directory)
  --all             Also clear NuGet caches
  --help, -h        Show this help text

Examples:
  nlc clean
  nlc clean --all
  nlc clean --project examples/15-dogfood-project

Exit codes:
  0  Clean completed successfully
  1  Clean failed");

        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

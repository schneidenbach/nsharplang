using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace NSharpLang.Cli.Commands;

public static class CleanCommand
{
    private static readonly string[] ArtifactDirectories =
    {
        "bin",
        "obj",
        ".nlc"
    };

    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var projectRoot = GetProjectRoot(options);
        var cleanAll = options.CleanAll;

        if (!Directory.Exists(projectRoot))
            return Error(CleanCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot));

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
                Console.WriteLine(CleanCommandKernels.GetNoArtifactsFoundMessage(projectRoot));
            }
            else
            {
                Console.WriteLine(CleanCommandKernels.GetRemovedArtifactsHeader(removed.Count));
                foreach (var path in removed)
                    Console.WriteLine($"  {path}");
            }

            if (cleanAll)
                Console.WriteLine(CleanCommandKernels.GetClearedNuGetCachesMessage());

            return 0;
        }
        catch (Exception ex)
        {
            return Error(CleanCommandKernels.GetCleanFailedMessage(ex.Message));
        }
    }

    private static List<string> RemoveArtifacts(string projectRoot)
    {
        var removed = new List<string>();
        var existingDirectories = Directory.EnumerateDirectories(projectRoot, "*", SearchOption.AllDirectories)
            .Concat(ArtifactDirectories.Select(name => Path.Combine(projectRoot, name)))
            .Where(Directory.Exists)
            .ToArray();
        var directories = CleanArtifactDirectoryOrderer.TryOrder(
            existingDirectories,
            out var dogfoodDirectories)
            ? dogfoodDirectories
            : CleanArtifactDirectoryOrderer.OrderWithCSharpFallback(existingDirectories);

        foreach (var dir in directories)
        {
            Directory.Delete(dir, recursive: true);
            removed.Add(NormalizePath(Path.GetRelativePath(projectRoot, dir)));
        }

        // Remove legacy generated MSBuild wrapper files from older nlc versions.
        foreach (var csproj in Directory.GetFiles(projectRoot, "*.g.csproj"))
        {
            File.Delete(csproj);
            removed.Add(NormalizePath(Path.GetRelativePath(projectRoot, csproj)));
        }

        removed.Sort(StringComparer.Ordinal);
        return removed;
    }

    private static int ClearNuGetCaches()
    {
        var result = DotnetRunner.Run("nuget locals all --clear");

        if (result.ExitCode == 0)
            return 0;

        return Error(CleanCommandKernels.GetClearNuGetCachesFailedMessage($"{result.Stderr}{result.Stdout}".Trim()));
    }

    internal static CleanOptionSummary GetOptionSummary(string[] args)
        => CleanCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product clean option parsing routes through CleanCommandKernels.
    private static CleanOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionWithCSharp(args, "--project"),
            ContainsArgWithCSharp(args, "--all"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    private static string GetProjectRoot(CleanOptionSummary options)
        => Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());

    private static string? GetOptionWithCSharp(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(CleanCommandKernels.GetHelpText());
        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

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
        var options = CleanCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(CleanCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());
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
                    Console.WriteLine(CleanCommandKernels.GetRemovedArtifactLine(path));
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
        var directories = CleanArtifactDirectoryOrderer.Order(existingDirectories);

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
        var result = DotnetRunner.Run("nuget locals all --clear");

        if (result.ExitCode == 0)
            return 0;

        return Error(CleanCommandKernels.GetClearNuGetCachesFailedMessage($"{result.Stderr}{result.Stdout}".Trim()));
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

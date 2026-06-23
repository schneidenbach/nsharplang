using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class AddCommand
{
    public static int Execute(string[] args)
    {
        var arguments = GetArgumentSummary(args);
        if (arguments.ShowHelp)
            return ShowHelp();

        if (args.Length == 0)
            return Error(AddCommandKernels.GetUsageMessage());

        var projectRoot = Directory.GetCurrentDirectory();
        var projectYml = Path.Combine(projectRoot, "project.yml");

        if (!File.Exists(projectYml))
            return Error(AddCommandKernels.GetMissingProjectFileMessage());

        var isFramework = arguments.Framework;
        var isPrerelease = arguments.Prerelease;
        var localPath = arguments.PathOption;

        // --path: add a local project reference
        if (localPath != null)
            return AddProjectReference(projectYml, localPath);

        var raw = arguments.PackageOperand;
        if (string.IsNullOrWhiteSpace(raw))
            return Error(AddCommandKernels.GetUsageMessage());

        var packageSpec = GetPackageSpec(raw, arguments.VersionOption);
        var packageName = packageSpec.PackageName;
        var version = packageSpec.Version;

        // For NuGet packages, resolve version if not specified
        if (!isFramework && version == null)
        {
            Console.WriteLine(AddCommandKernels.GetResolvingLatestVersionMessage(packageName));
            version = ResolveLatestVersion(packageName, isPrerelease);
            if (version == null)
                return Error(AddCommandKernels.GetPackageNotFoundMessage(packageName));
        }

        // Check for duplicate
        try
        {
            var config = ProjectFileParser.Parse(projectYml);
            if (PackageOrFrameworkDependencyExists(config.Dependencies, packageName))
                return Error(AddCommandKernels.GetDuplicatePackageMessage(packageName));
        }
        catch
        {
            // If parse fails, proceed anyway — text-based edit doesn't require full parse
        }

        // Text-based insertion into project.yml
        var lineArray = File.ReadAllLines(projectYml);
        var lines = new List<string>(lineArray);
        var insertAt = GetDependencyInsertIndex(lineArray);

        string newEntry;
        if (isFramework)
            newEntry = $"  - framework: {packageName}";
        else
            newEntry = $"  - {packageName}@{version}";

        if (insertAt >= 0)
        {
            lines.Insert(insertAt, newEntry);
        }
        else
        {
            // Add dependencies section
            lines.Add("");
            lines.Add("dependencies:");
            lines.Add(newEntry);
        }

        File.WriteAllLines(projectYml, lines);

        // Restore
        RestoreCommand.Restore(projectRoot, quiet: true);

        if (isFramework)
            Console.WriteLine(AddCommandKernels.GetFrameworkAddedMessage(packageName));
        else
            Console.WriteLine(AddCommandKernels.GetPackageAddedMessage(packageName, version ?? string.Empty));

        return 0;
    }

    internal static AddArgumentSummary GetArgumentSummary(string[] args)
        => AddCommandKernels.GetArgumentSummary(args);

    internal static AddPackageSpec GetPackageSpec(string raw, string? explicitVersion)
    {
        if (AddCommandKernels.TryGetPackageSpec(raw, explicitVersion, out var spec))
            return spec;

        throw new InvalidOperationException("N# add package spec kernel rejected the package.");
    }

    internal static int GetDependencyInsertIndex(string[] lines)
    {
        if (AddCommandKernels.TryGetDependencyInsertIndex(lines, out var insertIndex))
            return insertIndex;

        throw new InvalidOperationException("N# add dependency insertion kernel rejected the project file.");
    }

    internal static bool PackageOrFrameworkDependencyExists(IReadOnlyList<Reference> dependencies, string packageName)
    {
        if (AddCommandKernels.TryPackageOrFrameworkDependencyExists(dependencies, packageName, out var exists))
            return exists;

        throw new InvalidOperationException("N# add duplicate dependency kernel rejected the dependency table.");
    }

    internal static bool ProjectDependencyExists(IReadOnlyList<Reference> dependencies, string localPath)
    {
        if (AddCommandKernels.TryProjectDependencyExists(dependencies, localPath, out var exists))
            return exists;

        throw new InvalidOperationException("N# add duplicate project dependency kernel rejected the dependency table.");
    }

    static int AddProjectReference(string projectYml, string localPath)
    {
        // Check for duplicate project reference
        try
        {
            var config = ProjectFileParser.Parse(projectYml);
            if (ProjectDependencyExists(config.Dependencies, localPath))
                return Error(AddCommandKernels.GetDuplicateProjectReferenceMessage(localPath));
        }
        catch
        {
            // If parse fails, proceed anyway — text-based edit doesn't require full parse
        }

        var lineArray = File.ReadAllLines(projectYml);
        var lines = new List<string>(lineArray);
        var insertAt = GetDependencyInsertIndex(lineArray);
        var newEntry = $"  - project: {localPath}";

        if (insertAt >= 0)
        {
            lines.Insert(insertAt, newEntry);
        }
        else
        {
            lines.Add("");
            lines.Add("dependencies:");
            lines.Add(newEntry);
        }

        File.WriteAllLines(projectYml, lines);
        Console.WriteLine(AddCommandKernels.GetProjectReferenceAddedMessage(localPath));
        return 0;
    }

    internal static string? ResolveLatestVersion(string packageName, bool includePrerelease = false)
    {
        try
        {
            var searchArgs = $"package search {packageName} --exact-match --take 1 --format json";
            if (includePrerelease) searchArgs += " --prerelease";

            var result = DotnetRunner.Run(searchArgs);

            if (result.ExitCode == 0 && result.Stdout.Length > 0)
            {
                using var doc = JsonDocument.Parse(result.Stdout);
                var results = doc.RootElement.GetProperty("searchResult");
                foreach (var source in results.EnumerateArray())
                {
                    var packages = source.GetProperty("packages");
                    foreach (var pkg in packages.EnumerateArray())
                        return pkg.GetProperty("latestVersion").GetString();
                }
            }
        }
        catch
        {
            // Fall through to return null
        }

        return null;
    }

    static int ShowHelp()
    {
        Console.WriteLine(AddCommandKernels.GetHelpText());
        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

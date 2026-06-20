using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class AddCommand
{
    private static readonly string[] PackageOptionsWithValues = { "--version", "--path" };

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

    internal static string? GetPackageOperand(string[] args)
        => GetArgumentSummary(args).PackageOperand;

    internal static AddArgumentSummary GetArgumentSummary(string[] args)
        => AddCommandKernels.TryGetArgumentSummary(args, out var summary)
            ? summary
            : GetArgumentSummaryWithCSharp(args);

    internal static AddPackageSpec GetPackageSpec(string raw, string? explicitVersion)
        => AddCommandKernels.TryGetPackageSpec(raw, explicitVersion, out var spec)
            ? spec
            : GetPackageSpecWithCSharp(raw, explicitVersion);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product add package spec shaping routes through AddCommandKernels.
    private static AddPackageSpec GetPackageSpecWithCSharp(string raw, string? explicitVersion)
    {
        var atIndex = raw.IndexOf('@');
        if (atIndex > 0)
            return new AddPackageSpec(raw[..atIndex], raw[(atIndex + 1)..]);

        return new AddPackageSpec(raw, explicitVersion);
    }

    internal static int GetDependencyInsertIndex(string[] lines)
        => AddCommandKernels.TryGetDependencyInsertIndex(lines, out var insertIndex)
            ? insertIndex
            : GetDependencyInsertIndexWithCSharp(lines);

    internal static bool PackageOrFrameworkDependencyExists(IReadOnlyList<Reference> dependencies, string packageName)
        => AddCommandKernels.TryPackageOrFrameworkDependencyExists(dependencies, packageName, out var exists)
            ? exists
            : PackageOrFrameworkDependencyExistsWithCSharp(dependencies, packageName);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product add duplicate package/framework checks route through AddCommandKernels.
    private static bool PackageOrFrameworkDependencyExistsWithCSharp(
        IReadOnlyList<Reference> dependencies,
        string packageName)
    {
        for (var i = 0; i < dependencies.Count; i++)
        {
            var dependency = dependencies[i];
            if (string.Equals(dependency.Nuget, packageName, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(dependency.Framework, packageName, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    internal static bool ProjectDependencyExists(IReadOnlyList<Reference> dependencies, string localPath)
        => AddCommandKernels.TryProjectDependencyExists(dependencies, localPath, out var exists)
            ? exists
            : ProjectDependencyExistsWithCSharp(dependencies, localPath);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product add duplicate project checks route through AddCommandKernels.
    private static bool ProjectDependencyExistsWithCSharp(
        IReadOnlyList<Reference> dependencies,
        string localPath)
    {
        for (var i = 0; i < dependencies.Count; i++)
        {
            if (string.Equals(dependencies[i].Project, localPath, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product add dependency insertion planning routes through AddCommandKernels.
    private static int GetDependencyInsertIndexWithCSharp(string[] lines)
    {
        var depIndex = Array.FindIndex(lines, l => l.TrimStart().StartsWith("dependencies:"));
        if (depIndex < 0)
            return -1;

        var insertAt = depIndex + 1;
        while (insertAt < lines.Length)
        {
            var line = lines[insertAt];
            if (line.Length == 0 || (!line.StartsWith(" ") && !line.StartsWith("\t")))
                break;
            insertAt++;
        }

        return insertAt;
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product add argument parsing routes through AddCommandKernels.
    private static AddArgumentSummary GetArgumentSummaryWithCSharp(string[] args)
        => new(
            GetOptionWithCSharp(args, "--version"),
            GetOptionWithCSharp(args, "--path"),
            GetPackageOperandWithCSharp(args),
            ContainsArgWithCSharp(args, "--framework"),
            ContainsArgWithCSharp(args, "--prerelease"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    private static string? GetPackageOperandWithCSharp(string[] args)
    {
        for (var i = 0; i < args.Length; i++)
        {
            if (PackageOptionsWithValues.Contains(args[i], StringComparer.Ordinal))
            {
                i++;
                continue;
            }

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return args[i];
        }

        return null;
    }

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
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

    static string? GetOptionWithCSharp(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
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

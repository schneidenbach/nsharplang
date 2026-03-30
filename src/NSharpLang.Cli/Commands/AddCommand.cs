using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class AddCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        if (args.Length == 0)
            return Error("Usage: nlc add <package> [--version <ver>]\n       nlc add <package>@<version>");

        var projectRoot = Directory.GetCurrentDirectory();
        var projectYml = Path.Combine(projectRoot, "project.yml");

        if (!File.Exists(projectYml))
            return Error("No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.");

        var isFramework = args.Contains("--framework");
        var isPrerelease = args.Contains("--prerelease");
        var raw = args.First(a => !a.StartsWith("-"));

        string packageName;
        string? version = null;

        // Parse Package@Version syntax
        var atIndex = raw.IndexOf('@');
        if (atIndex > 0)
        {
            packageName = raw[..atIndex];
            version = raw[(atIndex + 1)..];
        }
        else
        {
            packageName = raw;
            version = GetOption(args, "--version");
        }

        // For NuGet packages, resolve version if not specified
        if (!isFramework && version == null)
        {
            Console.WriteLine($"Resolving latest version for {packageName}...");
            version = ResolveLatestVersion(packageName, isPrerelease);
            if (version == null)
                return Error($"Could not find package '{packageName}' on NuGet. Check the package name and try again.");
        }

        // Check for duplicate
        try
        {
            var config = ProjectFileParser.Parse(projectYml);
            var existing = config.Dependencies.FirstOrDefault(d =>
                string.Equals(d.Nuget, packageName, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(d.Framework, packageName, StringComparison.OrdinalIgnoreCase));
            if (existing != null)
                return Error($"'{packageName}' is already in dependencies. Use 'nlc update' to change the version.");
        }
        catch
        {
            // If parse fails, proceed anyway — text-based edit doesn't require full parse
        }

        // Text-based insertion into project.yml
        var lines = new List<string>(File.ReadAllLines(projectYml));
        var depIndex = lines.FindIndex(l => l.TrimStart().StartsWith("dependencies:"));

        string newEntry;
        if (isFramework)
            newEntry = $"  - framework: {packageName}";
        else
            newEntry = $"  - {packageName}@{version}";

        if (depIndex >= 0)
        {
            // Find the end of the dependencies block
            var insertAt = depIndex + 1;
            while (insertAt < lines.Count)
            {
                var line = lines[insertAt];
                if (line.Length == 0 || (!line.StartsWith(" ") && !line.StartsWith("\t")))
                    break;
                insertAt++;
            }
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
            Console.WriteLine($"Added framework reference '{packageName}' to project.yml");
        else
            Console.WriteLine($"Added {packageName}@{version} to project.yml");

        return 0;
    }

    internal static string? ResolveLatestVersion(string packageName, bool includePrerelease = false)
    {
        try
        {
            var searchArgs = $"package search {packageName} --exact-match --take 1 --format json";
            if (includePrerelease) searchArgs += " --prerelease";

            var psi = new ProcessStartInfo("dotnet", searchArgs)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            var process = Process.Start(psi);
            var output = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();

            if (process?.ExitCode == 0 && output != null)
            {
                using var doc = JsonDocument.Parse(output);
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

    static string? GetOption(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Add Dependency

Usage: nlc add <package> [options]
       nlc add <package>@<version>

Add a NuGet package or framework reference to project.yml.
If no version is specified, the latest version is resolved from NuGet.

Options:
  --version <ver>   Package version (alternative to @version syntax)
  --prerelease      Allow prerelease versions when resolving latest
  --framework       Add as a framework reference instead of NuGet package
  --help, -h        Show this help text

Examples:
  nlc add Newtonsoft.Json
  nlc add Serilog@3.1.0
  nlc add Serilog --version 3.1.0
  nlc add System.Text.Json --prerelease
  nlc add Microsoft.AspNetCore.App --framework

Exit codes:
  0  Dependency added successfully
  1  Failed to add dependency");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace NSharpLang.Cli.Commands;

public static class PublishCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = GetProjectRoot(args);

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}");

        // Restore first
        var restoreResult = RestoreCommand.Restore(projectRoot, quiet: true);
        if (restoreResult != 0)
            return Error("Failed to restore project configuration. Check project.yml.");

        // Find .csproj
        var csprojFiles = Directory.GetFiles(projectRoot, "*.csproj");
        if (csprojFiles.Length == 0)
            return Error("No .csproj file found. Run 'nlc init' to create one.");
        if (csprojFiles.Length > 1)
            return Error($"Multiple .csproj files found. Specify which to publish.");

        var csproj = csprojFiles[0];

        // Build dotnet publish args, filtering out our --project flag
        var dotnetArgs = FilterArgs(args);
        var fullArgs = $"publish \"{csproj}\" {string.Join(" ", dotnetArgs)}".Trim();

        var psi = new ProcessStartInfo("dotnet", fullArgs)
        {
            WorkingDirectory = projectRoot,
            UseShellExecute = false
        };

        try
        {
            var process = Process.Start(psi);
            process?.WaitForExit();
            return process?.ExitCode ?? 1;
        }
        catch (Exception ex)
        {
            return Error($"Publish failed: {ex.Message}");
        }
    }

    static string[] FilterArgs(string[] args)
    {
        var result = new System.Collections.Generic.List<string>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--project" && i + 1 < args.Length)
            {
                i++; // skip value
                continue;
            }
            result.Add(args[i]);
        }
        return result.ToArray();
    }

    static string GetProjectRoot(string[] args)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == "--project")
                return Path.GetFullPath(args[i + 1]);
        return Path.GetFullPath(Directory.GetCurrentDirectory());
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Publish

Usage: nlc publish [options]

Publish an N# project for deployment. Runs 'nlc restore' then 'dotnet publish'.
All options are forwarded to 'dotnet publish'.

Options:
  --project <dir>       Project root directory (default: current directory)
  -c, --configuration   Build configuration (Debug/Release)
  -r, --runtime         Target runtime (e.g., linux-x64, win-x64, osx-arm64)
  -o, --output          Output directory
  --self-contained      Publish as self-contained (includes .NET runtime)
  --help, -h            Show this help text

Examples:
  nlc publish
  nlc publish -c Release
  nlc publish -c Release -r linux-x64 --self-contained
  nlc publish -o ./dist

Exit codes:
  0  Publish succeeded
  1  Publish failed");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

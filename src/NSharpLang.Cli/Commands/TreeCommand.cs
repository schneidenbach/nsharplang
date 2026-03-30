using System;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace NSharpLang.Cli.Commands;

public static class TreeCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = GetProjectRoot(args);
        var json = args.Contains("--json");
        var maxDepth = GetIntOption(args, "--depth") ?? int.MaxValue;

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}");

        // Ensure restore
        RestoreCommand.Restore(projectRoot, quiet: true);

        var csprojFiles = Directory.GetFiles(projectRoot, "*.csproj");
        if (csprojFiles.Length == 0)
            return Error("No .csproj file found. Run 'nlc init' to create one.");

        var csproj = csprojFiles[0];

        try
        {
            var result = DotnetRunner.Run(
                $"list \"{csproj}\" package --include-transitive --format json",
                workingDirectory: projectRoot);

            if (result.ExitCode != 0)
                return Error("Failed to list packages. Run 'dotnet restore' first.");

            var output = result.Stdout;

            if (json)
            {
                // Wrap in our envelope
                using var rawDoc = JsonDocument.Parse(output);
                using var stream = new MemoryStream();
                using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
                writer.WriteStartObject();
                writer.WriteNumber("schemaVersion", 1);
                writer.WriteString("command", "tree");
                writer.WriteBoolean("ok", true);
                writer.WriteString("projectRoot", projectRoot);
                writer.WritePropertyName("packages");
                rawDoc.RootElement.WriteTo(writer);
                writer.WriteEndObject();
                writer.Flush();
                Console.WriteLine(System.Text.Encoding.UTF8.GetString(stream.ToArray()));
            }
            else
            {
                RenderTree(output, Path.GetFileNameWithoutExtension(csproj), maxDepth);
            }

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Tree failed: {ex.Message}");
        }
    }

    static void RenderTree(string jsonOutput, string projectName, int maxDepth)
    {
        try
        {
            using var doc = JsonDocument.Parse(jsonOutput);
            var projects = doc.RootElement.GetProperty("projects");

            foreach (var project in projects.EnumerateArray())
            {
                var frameworks = project.GetProperty("frameworks");
                foreach (var fw in frameworks.EnumerateArray())
                {
                    var framework = fw.GetProperty("framework").GetString();
                    Console.WriteLine($"{projectName} ({framework})");

                    if (maxDepth < 1) continue;

                    var topLevel = fw.TryGetProperty("topLevelPackages", out var tlp)
                        ? tlp.EnumerateArray().ToArray()
                        : Array.Empty<JsonElement>();

                    for (var i = 0; i < topLevel.Length; i++)
                    {
                        var pkg = topLevel[i];
                        var id = pkg.GetProperty("id").GetString();
                        var version = pkg.GetProperty("resolvedVersion").GetString();
                        var isLast = i == topLevel.Length - 1;
                        var prefix = isLast ? "└── " : "├── ";
                        Console.WriteLine($"{prefix}{id}@{version}");
                    }

                    if (maxDepth < 2) continue;

                    var transitive = fw.TryGetProperty("transitivePackages", out var tp)
                        ? tp.EnumerateArray().ToArray()
                        : Array.Empty<JsonElement>();

                    if (transitive.Length > 0)
                    {
                        Console.WriteLine();
                        Console.WriteLine($"  transitive ({transitive.Length} packages):");
                        foreach (var pkg in transitive)
                        {
                            var id = pkg.GetProperty("id").GetString();
                            var version = pkg.GetProperty("resolvedVersion").GetString();
                            Console.WriteLine($"    {id}@{version}");
                        }
                    }
                }
            }
        }
        catch
        {
            Console.WriteLine("Could not parse package list.");
        }
    }

    static string GetProjectRoot(string[] args)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == "--project")
                return Path.GetFullPath(args[i + 1]);
        return Path.GetFullPath(Directory.GetCurrentDirectory());
    }

    static int? GetIntOption(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag && int.TryParse(args[i + 1], out var val))
                return val;
        return null;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Dependency Tree

Usage: nlc tree [options]

Show the project's dependency tree including transitive dependencies.

Options:
  --project <dir>   Project root directory (default: current directory)
  --depth <n>       Maximum tree depth to display
  --json            Output as JSON envelope
  --help, -h        Show this help text

Examples:
  nlc tree
  nlc tree --depth 1
  nlc tree --json

Exit codes:
  0  Tree displayed successfully
  1  Failed to display tree");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

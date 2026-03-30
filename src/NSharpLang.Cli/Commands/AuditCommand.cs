using System;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace NSharpLang.Cli.Commands;

public static class AuditCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = GetProjectRoot(args);
        var json = args.Contains("--json");

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}");

        var csprojFiles = Directory.GetFiles(projectRoot, "*.csproj");
        if (csprojFiles.Length == 0)
            return Error("No .csproj file found. Run 'nlc init' to create one.");

        var csproj = csprojFiles[0];

        try
        {
            var result = DotnetRunner.Run(
                $"list \"{csproj}\" package --vulnerable --include-transitive --format json",
                workingDirectory: projectRoot);

            if (result.ExitCode != 0)
            {
                // dotnet list --vulnerable may not be available in older SDKs
                if (result.Stderr.Contains("--vulnerable"))
                    return Error("The --vulnerable flag requires .NET SDK 8.0 or later.");
                return Error($"Audit failed: {result.Stderr}".Trim());
            }

            var output = result.Stdout;

            var vulnCount = CountVulnerabilities(output);

            if (json)
            {
                using var rawDoc = JsonDocument.Parse(output);
                using var stream = new MemoryStream();
                using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
                writer.WriteStartObject();
                writer.WriteNumber("schemaVersion", 1);
                writer.WriteString("command", "audit");
                writer.WriteBoolean("ok", vulnCount == 0);
                writer.WriteString("projectRoot", projectRoot);
                writer.WriteNumber("vulnerabilityCount", vulnCount);
                writer.WritePropertyName("details");
                rawDoc.RootElement.WriteTo(writer);
                writer.WriteEndObject();
                writer.Flush();
                Console.WriteLine(System.Text.Encoding.UTF8.GetString(stream.ToArray()));
            }
            else
            {
                RenderAudit(output, vulnCount);
            }

            return vulnCount > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            return Error($"Audit failed: {ex.Message}");
        }
    }

    static int CountVulnerabilities(string jsonOutput)
    {
        var count = 0;
        try
        {
            using var doc = JsonDocument.Parse(jsonOutput);
            var projects = doc.RootElement.GetProperty("projects");
            foreach (var project in projects.EnumerateArray())
            {
                var frameworks = project.GetProperty("frameworks");
                foreach (var fw in frameworks.EnumerateArray())
                {
                    foreach (var section in new[] { "topLevelPackages", "transitivePackages" })
                    {
                        if (!fw.TryGetProperty(section, out var packages)) continue;
                        foreach (var pkg in packages.EnumerateArray())
                        {
                            if (pkg.TryGetProperty("vulnerabilities", out var vulns))
                                count += vulns.GetArrayLength();
                        }
                    }
                }
            }
        }
        catch
        {
            // Ignore parse errors
        }
        return count;
    }

    static void RenderAudit(string jsonOutput, int vulnCount)
    {
        if (vulnCount == 0)
        {
            Console.WriteLine("No known vulnerabilities found.");
            return;
        }

        Console.WriteLine($"{vulnCount} vulnerabilit{(vulnCount == 1 ? "y" : "ies")} found:");
        Console.WriteLine();

        try
        {
            using var doc = JsonDocument.Parse(jsonOutput);
            var projects = doc.RootElement.GetProperty("projects");
            foreach (var project in projects.EnumerateArray())
            {
                var frameworks = project.GetProperty("frameworks");
                foreach (var fw in frameworks.EnumerateArray())
                {
                    foreach (var section in new[] { "topLevelPackages", "transitivePackages" })
                    {
                        if (!fw.TryGetProperty(section, out var packages)) continue;
                        foreach (var pkg in packages.EnumerateArray())
                        {
                            if (!pkg.TryGetProperty("vulnerabilities", out var vulns)) continue;
                            var id = pkg.GetProperty("id").GetString();
                            var version = pkg.GetProperty("resolvedVersion").GetString();

                            foreach (var vuln in vulns.EnumerateArray())
                            {
                                var severity = vuln.TryGetProperty("severity", out var s) ? s.GetString() : "Unknown";
                                var url = vuln.TryGetProperty("advisoryurl", out var u) ? u.GetString() : "";
                                Console.WriteLine($"  {severity}: {id}@{version}");
                                if (!string.IsNullOrEmpty(url))
                                    Console.WriteLine($"    {url}");
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            Console.WriteLine("  (could not parse vulnerability details)");
        }
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
        Console.WriteLine(@"N# Security Audit

Usage: nlc audit [options]

Check dependencies for known security vulnerabilities.

Options:
  --project <dir>   Project root directory (default: current directory)
  --json            Output as JSON envelope
  --help, -h        Show this help text

Examples:
  nlc audit
  nlc audit --json
  nlc audit --project examples/14-minimal-api

Exit codes:
  0  No vulnerabilities found
  1  Vulnerabilities found or audit failed");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

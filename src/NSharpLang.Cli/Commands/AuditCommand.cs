using System;
using System.IO;
using System.Text.Json;

namespace NSharpLang.Cli.Commands;

public static class AuditCommand
{
    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var projectRoot = GetProjectRoot(options);
        var outputMode = GetOutputMode(options.Json);

        if (!Directory.Exists(projectRoot))
            return Error(AuditCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot));

        var csprojFiles = Directory.GetFiles(projectRoot, "*.csproj");
        if (csprojFiles.Length == 0)
            return Error(AuditCommandKernels.GetNoCsprojFileMessage());

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
                    return Error(AuditCommandKernels.GetVulnerableFlagUnsupportedMessage());
                return Error(AuditCommandKernels.GetFailedMessage(result.Stderr).Trim());
            }

            var output = result.Stdout;

            var vulnCount = CountVulnerabilities(output);

            if (outputMode == AuditOutputModeKind.Json)
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
            return Error(AuditCommandKernels.GetFailedMessage(ex.Message));
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
            Console.WriteLine(AuditCommandKernels.GetNoKnownVulnerabilitiesMessage());
            return;
        }

        Console.WriteLine(AuditCommandKernels.GetVulnerabilitySummaryMessage(vulnCount));
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
                                Console.WriteLine(AuditCommandKernels.GetVulnerabilityLine(
                                    severity ?? "Unknown",
                                    id ?? string.Empty,
                                    version ?? string.Empty));
                                if (!string.IsNullOrEmpty(url))
                                    Console.WriteLine(AuditCommandKernels.GetVulnerabilityUrlLine(url));
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            Console.WriteLine(AuditCommandKernels.GetParseFailureMessage());
        }
    }

    internal static AuditOptionSummary GetOptionSummary(string[] args)
        => AuditCommandKernels.GetOptionSummary(args);

    internal static AuditOutputModeKind GetOutputMode(bool json)
        => AuditCommandKernels.GetOutputMode(json);

    private static string GetProjectRoot(AuditOptionSummary options)
        => Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());

    static int ShowHelp()
    {
        Console.WriteLine(AuditCommandKernels.GetHelpText());

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}

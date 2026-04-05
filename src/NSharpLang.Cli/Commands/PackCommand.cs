using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Generates a NuGet package from the current N# project by reading package metadata
/// from project.yml and delegating to `dotnet pack`.
/// </summary>
public static class PackCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = Path.GetFullPath(GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory());
        var outputDir = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
        var versionOverride = GetOptionValue(args, "--version");
        var configuration = GetOptionValue(args, "--configuration") ?? GetOptionValue(args, "-c") ?? "Release";
        var includeSymbols = args.Contains("--include-symbols");
        var jsonOutput = args.Contains("--json");

        // Locate project.yml
        var projectYmlPath = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYmlPath))
        {
            if (jsonOutput)
            {
                WriteErrorJson("No project.yml found. Run 'nlc new <name>' to create a project.");
            }
            else
            {
                Console.Error.WriteLine("Error: No project.yml found in current directory.");
                Console.Error.WriteLine("Run 'nlc new <name>' to create a project.");
            }
            return 1;
        }

        ProjectConfig config;
        try
        {
            config = ProjectFileParser.Parse(projectYmlPath);
        }
        catch (Exception ex)
        {
            if (jsonOutput)
                WriteErrorJson($"Failed to parse project.yml: {ex.Message}");
            else
                Console.Error.WriteLine($"Error: Failed to parse project.yml: {ex.Message}");
            return 1;
        }

        if (!jsonOutput)
        {
            Console.WriteLine($"Packing {config.EffectiveName} {config.Version ?? "(no version)"}...");
            Console.WriteLine();
        }

        try
        {
            // Generate obj/project.g.props from project.yml
            var restoreResult = RestoreCommand.Restore(projectRoot, quiet: true);
            if (restoreResult != 0)
            {
                if (jsonOutput)
                    WriteErrorJson("Failed to restore project configuration from project.yml.");
                else
                    Console.Error.WriteLine("Error: Failed to restore project configuration from project.yml.");
                return 1;
            }

            // Determine .g.csproj path (same logic as EnsureProjectFiles in Program.cs)
            var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";
            var csprojPath = EnsurePackProjectFiles(projectRoot, config, projectName);

            // Clean up stale .g.cs files from deleted .nl sources
            Program.CleanStaleGeneratedFiles(projectRoot);

            // Build 'dotnet pack' arguments
            var packArgs = new List<string> { "pack", $"\"{csprojPath}\"" };
            packArgs.Add($"--configuration {configuration}");
            packArgs.Add("-p:NSharpExcludeTests=true");

            // Inject package metadata as MSBuild properties
            var pkg = config.Package;
            if (pkg != null)
            {
                if (!string.IsNullOrWhiteSpace(pkg.Author))
                    packArgs.Add($"-p:Authors={QuoteProperty(pkg.Author)}");

                if (!string.IsNullOrWhiteSpace(pkg.Description))
                    packArgs.Add($"-p:Description={QuoteProperty(pkg.Description)}");

                if (pkg.Tags != null && pkg.Tags.Count > 0)
                    packArgs.Add($"-p:PackageTags={QuoteProperty(string.Join(" ", pkg.Tags))}");

                if (!string.IsNullOrWhiteSpace(pkg.License))
                    packArgs.Add($"-p:PackageLicenseExpression={QuoteProperty(pkg.License)}");

                if (!string.IsNullOrWhiteSpace(pkg.Repository))
                    packArgs.Add($"-p:RepositoryUrl={QuoteProperty(pkg.Repository)}");

                if (!string.IsNullOrWhiteSpace(pkg.Icon))
                    packArgs.Add($"-p:PackageIcon={QuoteProperty(pkg.Icon)}");
            }

            // Version override
            var effectiveVersion = versionOverride ?? config.Version;
            if (!string.IsNullOrWhiteSpace(effectiveVersion))
                packArgs.Add($"-p:Version={QuoteProperty(effectiveVersion)}");

            // Output directory
            if (!string.IsNullOrEmpty(outputDir))
            {
                var absOutput = Path.GetFullPath(outputDir);
                packArgs.Add($"--output \"{absOutput}\"");
            }

            if (includeSymbols)
            {
                packArgs.Add("--include-symbols");
                packArgs.Add("-p:SymbolPackageFormat=snupkg");
            }

            var psi = new ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = string.Join(" ", packArgs),
                WorkingDirectory = projectRoot,
                UseShellExecute = false,
                RedirectStandardOutput = jsonOutput,
                RedirectStandardError = jsonOutput
            };

            var process = Process.Start(psi);
            var stdout = jsonOutput ? process?.StandardOutput.ReadToEnd() ?? "" : "";
            var stderr = jsonOutput ? process?.StandardError.ReadToEnd() ?? "" : "";
            process?.WaitForExit();

            if (process?.ExitCode != 0)
            {
                var detail = jsonOutput ? $": {(stderr + stdout).Trim()}" : "";
                if (jsonOutput)
                    WriteErrorJson($"Pack failed{detail}");
                else
                    Console.Error.WriteLine("Error: Pack failed");
                return 1;
            }

            // Locate the produced .nupkg file
            var packagePath = FindProducedPackage(projectRoot, outputDir, projectName, effectiveVersion);

            if (jsonOutput)
            {
                WriteJson(writer =>
                {
                    writer.WriteNumber("schemaVersion", 1);
                    writer.WriteString("command", "pack");
                    writer.WriteBoolean("ok", true);
                    writer.WriteString("projectRoot", projectRoot);
                    writer.WriteString("name", projectName);
                    writer.WriteString("version", effectiveVersion ?? "");
                    if (packagePath != null)
                        writer.WriteString("packagePath", packagePath);
                    else
                        writer.WriteNull("packagePath");
                });
            }
            else
            {
                Console.WriteLine("Pack successful!");
                if (packagePath != null)
                    Console.WriteLine($"  Package: {packagePath}");
            }

            return 0;
        }
        catch (Exception ex)
        {
            if (jsonOutput)
                WriteErrorJson($"Pack failed: {ex.Message}");
            else
                Console.Error.WriteLine($"Error: Pack failed: {ex.Message}");
            return 1;
        }
    }

    // ── Project file generation ───────────────────────────────────────────────

    /// <summary>
    /// Ensure the project's generated MSBuild files exist and return the .g.csproj path.
    /// NOTE: obj/project.g.props is generated by RestoreCommand.Restore(), not here.
    /// Callers must call Restore() before this method to ensure props are up to date.
    /// </summary>
    static string EnsurePackProjectFiles(string projectRoot, ProjectConfig config, string projectName)
    {
        var csprojPath = Path.Combine(projectRoot, $"{projectName}.g.csproj");
        File.WriteAllText(csprojPath, "<Project Sdk=\"NSharpLang.Sdk\" />\n");

        // Ensure global.json
        var globalJsonPath = Path.Combine(projectRoot, "global.json");
        if (!File.Exists(globalJsonPath))
        {
            File.WriteAllText(globalJsonPath, @"{
  ""sdk"": {
    ""version"": ""9.0.100""
  },
  ""msbuild-sdks"": {
    ""NSharpLang.Sdk"": ""0.1.0""
  }
}
");
        }

        // Ensure NuGet.config
        var nugetConfigPath = Path.Combine(projectRoot, "NuGet.config");
        if (!File.Exists(nugetConfigPath))
        {
            File.WriteAllText(nugetConfigPath, @"<?xml version=""1.0"" encoding=""utf-8""?>
<configuration>
  <packageSources>
    <clear />
    <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" />
    <add key=""nsharp-local"" value=""%HOME%/.nuget/local-feed"" />
  </packageSources>
</configuration>
");
        }

        return csprojPath;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Attempt to find the .nupkg produced by dotnet pack.
    /// </summary>
    static string? FindProducedPackage(string projectRoot, string? outputDir, string projectName, string? version)
    {
        var searchDir = string.IsNullOrEmpty(outputDir)
            ? Path.Combine(projectRoot, "bin")
            : Path.GetFullPath(outputDir);

        if (!Directory.Exists(searchDir))
            return null;

        try
        {
            var pattern = $"{projectName}*.nupkg";
            var candidates = Directory.GetFiles(searchDir, pattern, SearchOption.AllDirectories);

            if (candidates.Length == 0)
                return null;

            // Prefer the one matching the exact version, otherwise return the newest
            if (!string.IsNullOrEmpty(version))
            {
                var exact = candidates.FirstOrDefault(f => Path.GetFileName(f).Contains(version));
                if (exact != null) return exact;
            }

            return candidates.OrderByDescending(File.GetLastWriteTimeUtc).First();
        }
        catch
        {
            return null;
        }
    }

    static string QuoteProperty(string value)
        => value.Contains(' ') ? $"\"{value}\"" : value;

    static string? GetOptionValue(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    static void WriteJson(Action<Utf8JsonWriter> write)
    {
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
        writer.WriteStartObject();
        write(writer);
        writer.WriteEndObject();
        writer.Flush();
        Console.WriteLine(System.Text.Encoding.UTF8.GetString(stream.ToArray()));
    }

    static void WriteErrorJson(string message)
    {
        WriteJson(writer =>
        {
            writer.WriteNumber("schemaVersion", 1);
            writer.WriteString("command", "pack");
            writer.WriteBoolean("ok", false);
            writer.WriteStartObject("error");
            writer.WriteString("message", message);
            writer.WriteEndObject();
        });
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Pack

Usage: nlc pack [options]

Generate a NuGet package from the current N# project.

Reads package metadata from the 'package' section of project.yml, then
delegates to `dotnet pack`. The package section is optional but recommended
for library projects intended for distribution.

project.yml example:
  name: MyLibrary
  version: 1.2.0
  outputType: library
  package:
    author: Your Name
    description: A concise description of your library
    license: MIT
    repository: https://github.com/you/MyLibrary
    tags:
      - dotnet
      - nsharp

Options:
  --output <dir>          Output directory for the .nupkg file
  --version <ver>         Override the version from project.yml
  --configuration <cfg>   Build configuration (default: Release)
  --include-symbols       Also produce a .snupkg symbols package
  --project <dir>         Project root directory (default: current directory)
  --json                  Output structured JSON (schemaVersion 1 envelope)
  --help, -h              Show this help text

Examples:
  nlc pack
  nlc pack --output ./artifacts
  nlc pack --version 2.0.0-beta.1
  nlc pack --include-symbols
  nlc pack --json

Exit codes:
  0  Pack succeeded
  1  Pack failed");

        return 0;
    }
}

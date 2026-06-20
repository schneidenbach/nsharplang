using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Generates a NuGet package from the current N# project by reading package metadata
/// from project.yml and packing the native IL build output.
/// </summary>
public static class PackCommand
{
    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var projectRoot = Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());
        var outputDir = options.OutputDir;
        var versionOverride = options.VersionOverride;
        var configuration = options.Configuration;
        var includeSymbols = options.IncludeSymbols;
        var outputMode = GetOutputMode(options.JsonOutput);

        // Locate project.yml
        var projectYmlPath = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYmlPath))
        {
            if (outputMode == PackOutputModeKind.Json)
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
            if (outputMode == PackOutputModeKind.Json)
                WriteErrorJson($"Failed to parse project.yml: {ex.Message}");
            else
                Console.Error.WriteLine($"Error: Failed to parse project.yml: {ex.Message}");
            return 1;
        }

        if (outputMode == PackOutputModeKind.Text)
        {
            Console.WriteLine($"Packing {config.EffectiveName} {config.Version ?? "(no version)"}...");
            Console.WriteLine();
        }

        try
        {
            var projectName = CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config);
            var versionSource = GetEffectiveVersionSource(versionOverride, config.Version);
            var effectiveVersion = versionSource switch
            {
                PackVersionSourceKind.Override => versionOverride,
                PackVersionSourceKind.Project => config.Version,
                _ => null
            };
            if (effectiveVersion == null)
            {
                if (outputMode == PackOutputModeKind.Json)
                    WriteErrorJson("Package version is required. Set version in project.yml or pass --version.");
                else
                    Console.Error.WriteLine("Error: Package version is required. Set version in project.yml or pass --version.");
                return 1;
            }

            var buildOutputDir = Path.Combine(projectRoot, "bin", configuration, config.TargetFramework);
            var assemblyPath = Program.BuildProjectWithIlBackendForCommand(
                projectRoot,
                config,
                configuration,
                buildOutputDir,
                includeTests: false);
            if (assemblyPath == null)
            {
                if (outputMode == PackOutputModeKind.Json)
                    WriteErrorJson("Pack build failed.");
                else
                    Console.Error.WriteLine("Error: Pack build failed.");
                return 1;
            }

            var packageOutputDir = string.IsNullOrEmpty(outputDir)
                ? Path.Combine(projectRoot, "bin", configuration)
                : Path.GetFullPath(outputDir);
            Directory.CreateDirectory(packageOutputDir);

            var packagePath = Path.Combine(packageOutputDir, $"{projectName}.{effectiveVersion}.nupkg");
            CreateNuGetPackage(projectRoot, config, projectName, effectiveVersion, assemblyPath, packagePath);

            if (includeSymbols)
            {
                var symbolsPath = Path.Combine(packageOutputDir, $"{projectName}.{effectiveVersion}.snupkg");
                CreateSymbolsPackage(projectName, effectiveVersion, assemblyPath, symbolsPath);
            }

            if (outputMode == PackOutputModeKind.Json)
            {
                WriteJson(writer =>
                {
                    writer.WriteNumber("schemaVersion", 1);
                    writer.WriteString("command", "pack");
                    writer.WriteBoolean("ok", true);
                    writer.WriteString("projectRoot", projectRoot);
                    writer.WriteString("name", projectName);
                    writer.WriteString("version", effectiveVersion);
                    writer.WriteString("packagePath", packagePath);
                });
            }
            else
            {
                Console.WriteLine("Pack successful!");
                Console.WriteLine($"  Package: {packagePath}");
            }

            return 0;
        }
        catch (Exception ex)
        {
            if (outputMode == PackOutputModeKind.Json)
                WriteErrorJson($"Pack failed: {ex.Message}");
            else
                Console.Error.WriteLine($"Error: Pack failed: {ex.Message}");
            return 1;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    static void CreateNuGetPackage(
        string projectRoot,
        ProjectConfig config,
        string projectName,
        string version,
        string assemblyPath,
        string packagePath)
    {
        if (File.Exists(packagePath))
        {
            File.Delete(packagePath);
        }

        using var archive = ZipFile.Open(packagePath, ZipArchiveMode.Create);
        AddTextEntry(archive, $"{projectName}.nuspec", GenerateNuspec(config, projectName, version));
        archive.CreateEntryFromFile(assemblyPath, $"lib/{config.TargetFramework}/{Path.GetFileName(assemblyPath)}");

        var runtimeConfigPath = Path.ChangeExtension(assemblyPath, ".runtimeconfig.json");
        if (File.Exists(runtimeConfigPath))
        {
            archive.CreateEntryFromFile(runtimeConfigPath, $"lib/{config.TargetFramework}/{Path.GetFileName(runtimeConfigPath)}");
        }

        if (!string.IsNullOrWhiteSpace(config.Package?.Icon))
        {
            var iconPath = Path.GetFullPath(Path.Combine(projectRoot, config.Package.Icon));
            if (File.Exists(iconPath))
            {
                archive.CreateEntryFromFile(iconPath, config.Package.Icon.Replace('\\', '/'));
            }
        }
    }

    static void CreateSymbolsPackage(string projectName, string version, string assemblyPath, string symbolsPath)
    {
        if (File.Exists(symbolsPath))
        {
            File.Delete(symbolsPath);
        }

        using var archive = ZipFile.Open(symbolsPath, ZipArchiveMode.Create);
        AddTextEntry(archive, $"{projectName}.nuspec", $$"""
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>{{EscapeXml(projectName)}}</id>
    <version>{{EscapeXml(version)}}</version>
    <authors>NSharp</authors>
    <description>Symbols for {{EscapeXml(projectName)}}.</description>
  </metadata>
</package>
""");

        var pdbPath = Path.ChangeExtension(assemblyPath, ".pdb");
        if (File.Exists(pdbPath))
        {
            archive.CreateEntryFromFile(pdbPath, $"lib/{Path.GetFileName(pdbPath)}");
        }
    }

    static string GenerateNuspec(ProjectConfig config, string projectName, string version)
    {
        var pkg = config.Package;
        var authors = string.IsNullOrWhiteSpace(pkg?.Author) ? "NSharp" : pkg!.Author;
        var description = string.IsNullOrWhiteSpace(pkg?.Description)
            ? $"{projectName} N# package"
            : pkg!.Description;

        var sb = new StringBuilder();
        sb.AppendLine("""<?xml version="1.0" encoding="utf-8"?>""");
        sb.AppendLine("""<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">""");
        sb.AppendLine("  <metadata>");
        sb.AppendLine($"    <id>{EscapeXml(projectName)}</id>");
        sb.AppendLine($"    <version>{EscapeXml(version)}</version>");
        sb.AppendLine($"    <authors>{EscapeXml(authors!)}</authors>");
        sb.AppendLine($"    <description>{EscapeXml(description!)}</description>");
        if (pkg?.Tags is { Count: > 0 })
            sb.AppendLine($"    <tags>{EscapeXml(string.Join(" ", pkg.Tags))}</tags>");
        if (!string.IsNullOrWhiteSpace(pkg?.License))
            sb.AppendLine($"    <license type=\"expression\">{EscapeXml(pkg.License!)}</license>");
        if (!string.IsNullOrWhiteSpace(pkg?.Repository))
            sb.AppendLine($"    <repository type=\"git\" url=\"{EscapeXml(pkg.Repository!)}\" />");
        if (!string.IsNullOrWhiteSpace(pkg?.Icon))
            sb.AppendLine($"    <icon>{EscapeXml(pkg.Icon!)}</icon>");
        sb.AppendLine("  </metadata>");
        sb.AppendLine("</package>");
        return sb.ToString();
    }

    static void AddTextEntry(ZipArchive archive, string entryName, string contents)
    {
        var entry = archive.CreateEntry(entryName);
        using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
        writer.Write(contents);
    }

    static string EscapeXml(string value)
        => value
            .Replace("&", "&amp;", StringComparison.Ordinal)
            .Replace("\"", "&quot;", StringComparison.Ordinal)
            .Replace("<", "&lt;", StringComparison.Ordinal)
            .Replace(">", "&gt;", StringComparison.Ordinal);

    internal static PackOptionSummary GetOptionSummary(string[] args)
        => PackCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    internal static PackVersionSourceKind GetEffectiveVersionSource(string? versionOverride, string? projectVersion)
        => PackCommandKernels.TryGetEffectiveVersionSource(versionOverride, projectVersion, out var versionSource)
            ? versionSource
            : GetEffectiveVersionSourceWithCSharp(versionOverride, projectVersion);

    internal static PackOutputModeKind GetOutputMode(bool json)
        => PackCommandKernels.TryGetOutputMode(json, out var outputMode)
            ? outputMode
            : GetOutputModeWithCSharp(json);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product pack option parsing routes through PackCommandKernels.
    private static PackOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionValueWithCSharp(args, "--project"),
            GetOptionValueWithCSharp(args, "--output") ?? GetOptionValueWithCSharp(args, "-o"),
            GetOptionValueWithCSharp(args, "--version"),
            GetOptionValueWithCSharp(args, "--configuration") ?? GetOptionValueWithCSharp(args, "-c") ?? "Release",
            ContainsArgWithCSharp(args, "--include-symbols"),
            ContainsArgWithCSharp(args, "--json"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    // Stage 6 C#-surface-shrink: fallback/oracle only; product pack output mode selection routes through PackCommandKernels.
    private static PackOutputModeKind GetOutputModeWithCSharp(bool json)
        => json ? PackOutputModeKind.Json : PackOutputModeKind.Text;

    // Stage 6 C#-surface-shrink: fallback/oracle only; product pack version source selection routes through PackCommandKernels.
    private static PackVersionSourceKind GetEffectiveVersionSourceWithCSharp(
        string? versionOverride,
        string? projectVersion)
    {
        if (versionOverride != null)
            return string.IsNullOrWhiteSpace(versionOverride)
                ? PackVersionSourceKind.Missing
                : PackVersionSourceKind.Override;

        return string.IsNullOrWhiteSpace(projectVersion)
            ? PackVersionSourceKind.Missing
            : PackVersionSourceKind.Project;
    }

    private static string? GetOptionValueWithCSharp(string[] args, string flag)
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

Reads package metadata from the 'package' section of project.yml and packs
the native nlc IL build output. The package section is optional but
recommended for library projects intended for distribution.

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

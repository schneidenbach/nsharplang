using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using NSharpLang.Cli;
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
        var options = PackCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(PackCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());
        var outputDir = options.OutputDir;
        var versionOverride = options.VersionOverride;
        var configuration = options.Configuration;
        var includeSymbols = options.IncludeSymbols;
        var outputMode = PackCommandKernels.GetOutputMode(options.JsonOutput);

        // Locate project.yml
        var projectYmlPath = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYmlPath))
        {
            if (outputMode == PackOutputModeKind.Json)
            {
                WriteErrorJson(PackCommandKernels.GetMissingProjectFileJsonMessage());
            }
            else
            {
                WriteTextError(PackCommandKernels.GetMissingProjectFileTextMessage());
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
                WriteErrorJson(PackCommandKernels.GetParseFailedJsonMessage(ex.Message));
            else
                WriteTextError(PackCommandKernels.GetParseFailedTextMessage(ex.Message));
            return 1;
        }

        if (outputMode == PackOutputModeKind.Text)
        {
            Console.WriteLine(PackCommandKernels.GetStartMessage(config.EffectiveName, config.Version));
            Console.WriteLine();
        }

        try
        {
            var projectName = CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config);
            var versionSource = PackCommandKernels.GetEffectiveVersionSource(versionOverride, config.Version);
            var effectiveVersion = versionSource switch
            {
                PackVersionSourceKind.Override => versionOverride,
                PackVersionSourceKind.Project => config.Version,
                _ => null
            };
            if (effectiveVersion == null)
            {
                if (outputMode == PackOutputModeKind.Json)
                    WriteErrorJson(PackCommandKernels.GetMissingVersionJsonMessage());
                else
                    WriteTextError(PackCommandKernels.GetMissingVersionTextMessage());
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
                    WriteErrorJson(PackCommandKernels.GetBuildFailedJsonMessage());
                else
                    WriteTextError(PackCommandKernels.GetBuildFailedTextMessage());
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
                Console.WriteLine(PackCommandKernels.GetSuccessMessage());
                Console.WriteLine(PackCommandKernels.GetPackagePathLine(packagePath));
            }

            return 0;
        }
        catch (Exception ex)
        {
            if (outputMode == PackOutputModeKind.Json)
                WriteErrorJson(PackCommandKernels.GetFailedJsonMessage(ex.Message));
            else
                WriteTextError(PackCommandKernels.GetFailedTextMessage(ex.Message));
            return 1;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static void WriteTextError(string message)
        => Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message));

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
        var pkg = config.Package;
        var packageTags = pkg?.Tags is { Count: > 0 } tags ? string.Join(" ", tags) : string.Empty;
        var nuspecText = PackCommandKernels.GetNuspecText(
            projectName,
            version,
            pkg?.Author ?? string.Empty,
            pkg?.Description ?? string.Empty,
            packageTags,
            pkg?.Tags?.Count ?? 0,
            pkg?.License ?? string.Empty,
            pkg?.Repository ?? string.Empty,
            pkg?.Icon ?? string.Empty);
        AddTextEntry(archive, $"{projectName}.nuspec", nuspecText);
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
        AddTextEntry(archive, $"{projectName}.nuspec", PackCommandKernels.GetSymbolsNuspecText(projectName, version));

        var pdbPath = Path.ChangeExtension(assemblyPath, ".pdb");
        if (File.Exists(pdbPath))
        {
            archive.CreateEntryFromFile(pdbPath, $"lib/{Path.GetFileName(pdbPath)}");
        }
    }

    static void AddTextEntry(ZipArchive archive, string entryName, string contents)
    {
        var entry = archive.CreateEntry(entryName);
        using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
        writer.Write(contents);
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

}

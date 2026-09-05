using System;
using System.IO;
using System.IO.Compression;
using System.Text;
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

        var projectRoot = PackCommandKernels.GetProjectRoot(options.ProjectOption, Directory.GetCurrentDirectory());
        var outputDir = options.OutputDir;
        var versionOverride = options.VersionOverride;
        var configuration = options.Configuration;
        var includeSymbols = options.IncludeSymbols;
        var outputMode = PackCommandKernels.GetOutputMode(options.JsonOutput);

        // Locate project.yml
        var projectYmlPath = PackCommandKernels.GetProjectYmlPath(projectRoot);
        if (!File.Exists(projectYmlPath))
        {
            if (outputMode == 1)
            {
                Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetMissingProjectFileJsonMessage()));
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
            if (outputMode == 1)
                Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetParseFailedJsonMessage(ex.Message)));
            else
                WriteTextError(PackCommandKernels.GetParseFailedTextMessage(ex.Message));
            return 1;
        }

        if (outputMode == 2)
        {
            Console.WriteLine(PackCommandKernels.GetStartMessage(config.EffectiveName, config.Version));
            Console.WriteLine();
        }

        try
        {
            var projectName = CompilationReferenceResolverKernels.GetProjectAssemblyName(projectRoot, config.Name);
            var effectiveVersion = PackCommandKernels.GetEffectiveVersion(versionOverride, config.Version);
            if (effectiveVersion == null)
            {
                if (outputMode == 1)
                    Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetMissingVersionJsonMessage()));
                else
                    WriteTextError(PackCommandKernels.GetMissingVersionTextMessage());
                return 1;
            }

            var buildOutputDir = PackCommandKernels.GetBuildOutputDirectory(projectRoot, configuration, config.TargetFramework);
            var assemblyPath = Program.BuildProjectWithIlBackendForCommand(
                projectRoot,
                config,
                configuration,
                buildOutputDir,
                includeTests: false);
            if (assemblyPath == null)
            {
                if (outputMode == 1)
                    Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetBuildFailedJsonMessage()));
                else
                    WriteTextError(PackCommandKernels.GetBuildFailedTextMessage());
                return 1;
            }

            var packageOutputDir = PackCommandKernels.GetPackageOutputDirectory(projectRoot, configuration, outputDir);
            Directory.CreateDirectory(packageOutputDir);

            var packagePath = PackCommandKernels.GetPackagePath(packageOutputDir, projectName, effectiveVersion);
            CreateNuGetPackage(projectRoot, config, projectName, effectiveVersion, assemblyPath, packagePath);

            if (includeSymbols)
            {
                var symbolsPath = PackCommandKernels.GetSymbolsPackagePath(packageOutputDir, projectName, effectiveVersion);
                CreateSymbolsPackage(projectName, effectiveVersion, assemblyPath, symbolsPath);
            }

            if (outputMode == 1)
            {
                Console.WriteLine(PackCommandKernels.SuccessJson(projectRoot, projectName, effectiveVersion, packagePath));
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
            if (outputMode == 1)
                Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetFailedJsonMessage(ex.Message)));
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
        var packageTags = PackCommandKernels.GetPackageTags(pkg?.Tags);
        var nuspecText = PackCommandKernels.GetNuspecText(
            projectName,
            version,
            pkg?.Author ?? string.Empty,
            pkg?.Description ?? string.Empty,
            packageTags.Text,
            packageTags.Count,
            pkg?.License ?? string.Empty,
            pkg?.Repository ?? string.Empty,
            pkg?.Icon ?? string.Empty);
        AddTextEntry(archive, PackCommandKernels.GetNuspecEntryName(projectName), nuspecText);
        archive.CreateEntryFromFile(assemblyPath, PackCommandKernels.GetPackageAssemblyEntryPath(config.TargetFramework, assemblyPath));

        var runtimeConfigPath = PackCommandKernels.GetRuntimeConfigPath(assemblyPath);
        if (File.Exists(runtimeConfigPath))
        {
            archive.CreateEntryFromFile(runtimeConfigPath!, PackCommandKernels.GetRuntimeConfigEntryPath(config.TargetFramework, runtimeConfigPath!));
        }

        if (!string.IsNullOrWhiteSpace(config.Package?.Icon))
        {
            var iconPath = PackCommandKernels.GetIconSourcePath(projectRoot, config.Package.Icon);
            if (File.Exists(iconPath))
            {
                archive.CreateEntryFromFile(iconPath, PackCommandKernels.GetIconPackageEntryName(config.Package.Icon));
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
        AddTextEntry(archive, PackCommandKernels.GetNuspecEntryName(projectName), PackCommandKernels.GetSymbolsNuspecText(projectName, version));

        var pdbPath = PackCommandKernels.GetSymbolsPdbPath(assemblyPath);
        if (File.Exists(pdbPath))
        {
            archive.CreateEntryFromFile(pdbPath!, PackCommandKernels.GetSymbolsPdbEntryPath(pdbPath!));
        }
    }

    static void AddTextEntry(ZipArchive archive, string entryName, string contents)
    {
        var entry = archive.CreateEntry(entryName);
        using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
        writer.Write(contents);
    }

}

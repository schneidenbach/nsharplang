namespace NSharpLang.Cli.Commands

import System
import System.IO
import System.IO.Compression
import System.Text
import NSharpLang.Cli
import NSharpLang.Compiler

// `nlc pack` owns the whole route from project.yml to a .nupkg on disk: read the metadata, build
// the project through the shared IL backend, then write the archive. Every name inside the archive
// — the nuspec's text, its entry name, the lib/<tfm>/ paths, the icon entry — is decided by
// PackCommandKernels, so this owner only opens streams and copies bytes. The symbols package is
// the same write with a different nuspec and one extra file.
class PackCommand {
    static func Execute(args: string[]): int {
        options := PackCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            Console.WriteLine(PackCommandKernels.GetHelpText())
            return 0
        }

        projectRoot := CommandOutputKernels.GetProjectRoot(options.ProjectOption, Directory.GetCurrentDirectory())
        outputDir := options.OutputDir
        versionOverride := options.VersionOverride
        configuration := options.Configuration
        includeSymbols := options.IncludeSymbols
        outputMode := CommandOutputKernels.GetOutputMode(options.JsonOutput)

        projectYmlPath := PackCommandKernels.GetProjectYmlPath(projectRoot)
        if !File.Exists(projectYmlPath) {
            if outputMode == 1 {
                Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetMissingProjectFileJsonMessage()))
                return 1
            }

            return CliError.Report(PackCommandKernels.GetMissingProjectFileTextMessage())
        }

        config: ProjectConfig? = null
        try {
            config = ProjectFileParser.Parse(projectYmlPath)
        } catch ex: Exception {
            if outputMode == 1 {
                Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetParseFailedJsonMessage(ex.Message)))
                return 1
            }

            return CliError.Report(PackCommandKernels.GetParseFailedTextMessage(ex.Message))
        }

        parsedConfig := must config
        if outputMode == 2 {
            Console.WriteLine(PackCommandKernels.GetStartMessage(parsedConfig.EffectiveName, parsedConfig.Version))
            Console.WriteLine()
        }

        try {
            projectName := CompilationReferenceResolverKernels.GetProjectAssemblyName(projectRoot, parsedConfig.Name)
            effectiveVersion := PackCommandKernels.GetEffectiveVersion(versionOverride, parsedConfig.Version)
            if effectiveVersion == null {
                if outputMode == 1 {
                    Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetMissingVersionJsonMessage()))
                    return 1
                }

                return CliError.Report(PackCommandKernels.GetMissingVersionTextMessage())
            }

            resolvedVersion := must effectiveVersion
            buildOutputDir := PackCommandKernels.GetBuildOutputDirectory(projectRoot, configuration, parsedConfig.TargetFramework)
            assemblyPath := CliIlBackend.BuildProjectWithIlBackendForCommand(
                projectRoot,
                parsedConfig,
                configuration,
                buildOutputDir,
                false,
                false,
                false
            )
            if assemblyPath == null {
                if outputMode == 1 {
                    Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetBuildFailedJsonMessage()))
                    return 1
                }

                return CliError.Report(PackCommandKernels.GetBuildFailedTextMessage())
            }

            resolvedAssemblyPath := must assemblyPath
            packageOutputDir := PackCommandKernels.GetPackageOutputDirectory(projectRoot, configuration, outputDir)
            Directory.CreateDirectory(packageOutputDir)

            packagePath := PackCommandKernels.GetPackagePath(packageOutputDir, projectName, resolvedVersion)
            CreateNuGetPackage(projectRoot, parsedConfig, projectName, resolvedVersion, resolvedAssemblyPath, packagePath)

            if includeSymbols {
                symbolsPath := PackCommandKernels.GetSymbolsPackagePath(packageOutputDir, projectName, resolvedVersion)
                CreateSymbolsPackage(projectName, resolvedVersion, resolvedAssemblyPath, symbolsPath)
            }

            if outputMode == 1 {
                Console.WriteLine(PackCommandKernels.SuccessJson(projectRoot, projectName, resolvedVersion, packagePath))
            } else {
                Console.WriteLine(PackCommandKernels.GetSuccessMessage())
                Console.WriteLine(PackCommandKernels.GetPackagePathLine(packagePath))
            }

            return 0
        } catch ex: Exception {
            if outputMode == 1 {
                Console.WriteLine(PackCommandKernels.ErrorJson(PackCommandKernels.GetFailedJsonMessage(ex.Message)))
                return 1
            }

            return CliError.Report(PackCommandKernels.GetFailedTextMessage(ex.Message))
        }
    }

    static func CreateNuGetPackage(
        projectRoot: string,
        config: ProjectConfig,
        projectName: string,
        version: string,
        assemblyPath: string,
        packagePath: string
    ) {
        if File.Exists(packagePath) {
            File.Delete(packagePath)
        }

        using archive := ZipFile.Open(packagePath, ZipArchiveMode.Create)
        pkg := config.Package
        packageTags := PackCommandKernels.GetPackageTags(pkg?.Tags)
        nuspecText := PackCommandKernels.GetNuspecText(
            projectName,
            version,
            pkg?.Author ?? "",
            pkg?.Description ?? "",
            packageTags.Text,
            packageTags.Count,
            pkg?.License ?? "",
            pkg?.Repository ?? "",
            pkg?.Icon ?? ""
        )
        AddTextEntry(archive, PackCommandKernels.GetNuspecEntryName(projectName), nuspecText)
        archive.CreateEntryFromFile(assemblyPath, PackCommandKernels.GetPackageAssemblyEntryPath(config.TargetFramework, assemblyPath))

        runtimeConfigPath := PackCommandKernels.GetRuntimeConfigPath(assemblyPath)
        if runtimeConfigPath != null && File.Exists(runtimeConfigPath) {
            resolvedRuntimeConfigPath := must runtimeConfigPath
            archive.CreateEntryFromFile(
                resolvedRuntimeConfigPath,
                PackCommandKernels.GetRuntimeConfigEntryPath(config.TargetFramework, resolvedRuntimeConfigPath)
            )
        }

        icon := pkg?.Icon ?? ""
        if !string.IsNullOrWhiteSpace(icon) {
            iconPath := PackCommandKernels.GetIconSourcePath(projectRoot, icon)
            if File.Exists(iconPath) {
                archive.CreateEntryFromFile(iconPath, PackCommandKernels.GetIconPackageEntryName(icon))
            }
        }
    }

    static func CreateSymbolsPackage(projectName: string, version: string, assemblyPath: string, symbolsPath: string) {
        if File.Exists(symbolsPath) {
            File.Delete(symbolsPath)
        }

        using archive := ZipFile.Open(symbolsPath, ZipArchiveMode.Create)
        AddTextEntry(archive, PackCommandKernels.GetNuspecEntryName(projectName), PackCommandKernels.GetSymbolsNuspecText(projectName, version))

        pdbPath := PackCommandKernels.GetSymbolsPdbPath(assemblyPath)
        if pdbPath != null && File.Exists(pdbPath) {
            resolvedPdbPath := must pdbPath
            archive.CreateEntryFromFile(resolvedPdbPath, PackCommandKernels.GetSymbolsPdbEntryPath(resolvedPdbPath))
        }
    }

    static func AddTextEntry(archive: ZipArchive, entryName: string, contents: string) {
        entry := archive.CreateEntry(entryName)
        using writer := new StreamWriter(entry.Open(), Encoding.UTF8)
        writer.Write(contents)
    }
}

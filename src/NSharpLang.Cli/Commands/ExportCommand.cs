using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using NSharpLang.Cli;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class ExportCommand
{
    public static int Execute(string[] args)
    {
        if (args.Length == 0 || args[0] is "--help" or "-h" or "help")
        {
            return ShowHelp();
        }

        var format = args[0].ToLowerInvariant();
        return format switch
        {
            "csharp" => ExportCSharp(args.Skip(1).ToArray()),
            _ => Error($"Unknown export target '{args[0]}'. Expected 'csharp'.")
        };
    }

    private static int ExportCSharp(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            return ShowCSharpHelp();
        }

        var outputPath = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
        var projectOption = GetOptionValue(args, "--project");

        args = StripOptionWithValue(args, "--output");
        args = StripOptionWithValue(args, "-o");
        args = StripOptionWithValue(args, "--project");

        var positional = args.Where(arg => !arg.StartsWith("-", StringComparison.Ordinal)).ToArray();
        if (!string.IsNullOrWhiteSpace(projectOption) && positional.Length > 0)
        {
            return Error("Specify either a source path or --project, not both.");
        }

        try
        {
            if (!string.IsNullOrWhiteSpace(projectOption))
            {
                return ExportProjectBundle(Path.GetFullPath(projectOption), outputPath);
            }

            if (positional.Length > 0)
            {
                var inputPath = Path.GetFullPath(positional[0]);
                if (File.Exists(inputPath))
                {
                    return ExportSingleFile(inputPath, outputPath);
                }

                if (Directory.Exists(inputPath))
                {
                    return ExportProjectBundle(inputPath, outputPath);
                }

                return Error($"Path not found: {positional[0]}");
            }

            var currentDirectory = Directory.GetCurrentDirectory();
            if (File.Exists(Path.Combine(currentDirectory, "project.yml")))
            {
                return ExportProjectBundle(currentDirectory, outputPath);
            }

            return Error("No input provided. Pass a .nl file or project directory, or run from a directory containing project.yml.");
        }
        catch (Exception ex)
        {
            return Error($"Export failed: {ex.Message}");
        }
    }

    private static int ExportSingleFile(string sourceFile, string? outputPath)
    {
        if (!sourceFile.EndsWith(".nl", StringComparison.OrdinalIgnoreCase))
        {
            return Error($"Expected an .nl file, got: {sourceFile}");
        }

        var projectRoot = FindContainingProjectRoot(sourceFile)
            ?? Path.GetDirectoryName(sourceFile)
            ?? Directory.GetCurrentDirectory();
        var projectConfig = File.Exists(Path.Combine(projectRoot, "project.yml"))
            ? ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"))
            : ProjectFileParser.CreateDefault(Path.GetFileNameWithoutExtension(sourceFile));

        var compiler = new MultiFileCompiler(new[] { sourceFile }, projectRoot, projectConfig);
        var result = compiler.ExportToCSharp();
        EmitDiagnostics(result.Errors);

        if (!result.Success)
        {
            return 1;
        }

        if (!result.ExportedFiles.TryGetValue(sourceFile, out var csharpSource))
        {
            return Error($"The export pipeline did not produce output for {sourceFile}.");
        }

        if (string.IsNullOrWhiteSpace(outputPath))
        {
            Console.Write(csharpSource);
            return 0;
        }

        var resolvedOutputPath = ResolveFileExportPath(sourceFile, outputPath);
        if (string.Equals(Path.GetFullPath(resolvedOutputPath), Path.GetFullPath(sourceFile), StringComparison.OrdinalIgnoreCase))
        {
            return Error("Refusing to overwrite the source .nl file. Choose a different output path.");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(resolvedOutputPath) ?? Directory.GetCurrentDirectory());
        File.WriteAllText(resolvedOutputPath, csharpSource);
        Console.WriteLine($"Exported {Path.GetFileName(sourceFile)} to {resolvedOutputPath}");
        return 0;
    }

    private static int ExportProjectBundle(string projectRoot, string? outputPath)
    {
        if (!File.Exists(Path.Combine(projectRoot, "project.yml")))
        {
            return Error($"No project.yml found in {projectRoot}.");
        }

        var bundleRoot = Path.GetFullPath(outputPath ?? Path.Combine(projectRoot, "csharp-export"));
        Directory.CreateDirectory(bundleRoot);
        RemoveDirectoryIfExists(Path.Combine(bundleRoot, "_nsharp_refs"));
        RemoveDirectoryIfExists(Path.Combine(bundleRoot, "_nsharp_libs"));

        var exporter = new CSharpProjectExportSession(bundleRoot);
        try
        {
            var exportedProject = exporter.ExportProject(projectRoot, isRoot: true);
            Console.WriteLine($"Exported {exportedProject.ProjectName} to {exportedProject.ProjectFilePath}");
            if (exportedProject.TestProjectFilePath != null)
            {
                Console.WriteLine($"Exported tests to {exportedProject.TestProjectFilePath}");
            }
            return 0;
        }
        catch (ProjectExportException ex)
        {
            EmitDiagnostics(ex.Errors);
            return 1;
        }
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Export

Usage: nlc export <target> [options]

Export N# sources into other representations without changing the build backend.

Targets:
  csharp              Export a single file or an entire project bundle to C#

Examples:
  nlc export csharp Program.nl
  nlc export csharp Program.nl -o Program.cs
  nlc export csharp --project .
  nlc export csharp examples/12-multi-file-projects/WeatherDemo -o ./weather-csharp

Run 'nlc export <target> --help' for target-specific options.");

        return 0;
    }

    private static int ShowCSharpHelp()
    {
        Console.WriteLine(@"N# Export C#

Usage:
  nlc export csharp <file.nl> [-o output.cs]
  nlc export csharp <project-dir> [-o bundle-dir]
  nlc export csharp --project <project-dir> [-o bundle-dir]

Exports N# sources to C# without using generated C# as a build backend.

Single-file mode:
  Writes the exported C# to stdout by default, or to the file passed with -o/--output.

Project mode:
  Writes a self-contained C# bundle containing:
  - the exported main project
  - a sibling test project when .tests.nl files exist
  - exported N# project references under _nsharp_refs

Options:
  --project <dir>    Export a project from a specific directory
  --output <path>    Output .cs file or bundle directory (-o shorthand)
  --help, -h         Show this help text

Exit codes:
  0  Export succeeded
  1  Export failed");

        return 0;
    }

    private static string? FindContainingProjectRoot(string path)
    {
        var current = Directory.Exists(path)
            ? new DirectoryInfo(Path.GetFullPath(path))
            : new DirectoryInfo(Path.GetDirectoryName(Path.GetFullPath(path)) ?? Directory.GetCurrentDirectory());

        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, "project.yml")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        return null;
    }

    private static string ResolveFileExportPath(string sourceFile, string outputPath)
    {
        var fullOutputPath = Path.GetFullPath(outputPath);
        if (Directory.Exists(fullOutputPath) || outputPath.EndsWith(Path.DirectorySeparatorChar) || outputPath.EndsWith(Path.AltDirectorySeparatorChar))
        {
            return Path.Combine(fullOutputPath, Path.ChangeExtension(Path.GetFileName(sourceFile), ".cs"));
        }

        return fullOutputPath;
    }

    private static string? GetOptionValue(string[] args, string option)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == option)
            {
                return args[i + 1];
            }
        }

        return null;
    }

    private static string[] StripOptionWithValue(string[] args, string option)
    {
        var result = new List<string>(args.Length);
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == option && i + 1 < args.Length)
            {
                i++;
                continue;
            }

            result.Add(args[i]);
        }

        return result.ToArray();
    }

    private static void EmitDiagnostics(IEnumerable<CompilerError> errors)
    {
        foreach (var error in errors)
        {
            Console.Error.WriteLine(error.Format());
        }
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }

    private static void RemoveDirectoryIfExists(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, true);
        }
    }

    private sealed class CSharpProjectExportSession(string bundleRoot)
    {
        private readonly string _bundleRoot = bundleRoot;
        private readonly Dictionary<string, ExportedProjectInfo> _exportedProjects = new(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _projectsInProgress = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, string> _copiedDllReferences = new(StringComparer.OrdinalIgnoreCase);

        public ExportedProjectInfo ExportProject(string projectRoot, bool isRoot)
        {
            projectRoot = Path.GetFullPath(projectRoot);
            if (_exportedProjects.TryGetValue(projectRoot, out var existing))
            {
                return existing;
            }

            if (!_projectsInProgress.Add(projectRoot))
            {
                throw new InvalidOperationException($"Cyclic project reference detected while exporting '{projectRoot}'.");
            }

            try
            {
                var projectFile = Path.Combine(projectRoot, "project.yml");
                var exportConfig = ProjectFileParser.Parse(projectFile);
                var compilationConfig = ProjectFileParser.Parse(projectFile);
                CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, compilationConfig);
                var directoryName = GetProjectDirectoryName(projectRoot, exportConfig.EffectiveName, isRoot);
                var projectOutputDirectory = Path.Combine(_bundleRoot, directoryName);
                var testOutputDirectory = Path.Combine(_bundleRoot, $"{directoryName}.Tests");

                if (string.Equals(projectOutputDirectory, projectRoot, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException(
                        $"Export output '{projectOutputDirectory}' would overwrite the source project. Choose a different --output path.");
                }

                RecreateDirectory(projectOutputDirectory);
                CopyPackageIconIfPresent(exportConfig, projectRoot, projectOutputDirectory);

                var sourceFiles = exportConfig.GetSourceFiles(projectRoot, includeTests: true)
                    .Select(Path.GetFullPath)
                    .ToArray();
                var compiler = new MultiFileCompiler(sourceFiles, projectRoot, compilationConfig);
                var exportResult = compiler.ExportToCSharp();
                if (!exportResult.Success)
                {
                    throw new ProjectExportException(exportResult.Errors.ToList());
                }

                EmitDiagnostics(exportResult.Errors);

                var mainProjectReferences = ResolveProjectReferences(exportConfig.Dependencies, projectRoot, projectOutputDirectory);
                var mainDllReferences = ResolveDllReferences(exportConfig.Dependencies, projectRoot, projectOutputDirectory);
                var mainPackageReferences = ResolvePackageReferences(exportConfig.Dependencies);
                var mainFrameworkReferences = ResolveFrameworkReferences(exportConfig.Dependencies);
                var hasTestFiles = exportResult.ExportedFiles.Keys.Any(sourceFile =>
                    sourceFile.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase));
                if (hasTestFiles)
                {
                    RecreateDirectory(testOutputDirectory);
                }

                foreach (var (sourceFile, csharpSource) in exportResult.ExportedFiles.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
                {
                    var relativeSourcePath = Path.GetRelativePath(projectRoot, sourceFile);
                    var relativeCSharpPath = ChangeSourceExtension(relativeSourcePath);
                    var targetDirectory = sourceFile.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase)
                        ? testOutputDirectory
                        : projectOutputDirectory;
                    var targetFilePath = Path.Combine(targetDirectory, relativeCSharpPath);

                    Directory.CreateDirectory(Path.GetDirectoryName(targetFilePath) ?? targetDirectory);
                    File.WriteAllText(targetFilePath, csharpSource);
                }

                var projectFilePath = Path.Combine(projectOutputDirectory, $"{SanitizeFileName(exportConfig.EffectiveName)}.csproj");
                File.WriteAllText(projectFilePath, GenerateMainProjectFile(
                    exportConfig,
                    mainPackageReferences,
                    mainFrameworkReferences,
                    mainProjectReferences,
                    mainDllReferences));

                string? testProjectFilePath = null;
                if (hasTestFiles)
                {
                    var testProjectReferences = ResolveProjectReferences(exportConfig.TestDependencies, projectRoot, testOutputDirectory);
                    testProjectReferences.Insert(0, NormalizePath(Path.GetRelativePath(testOutputDirectory, projectFilePath)));
                    testProjectReferences.AddRange(
                        mainProjectReferences.Select(projectReference =>
                            NormalizePath(Path.GetRelativePath(testOutputDirectory, Path.GetFullPath(Path.Combine(projectOutputDirectory, projectReference))))));
                    var testDllReferences = ResolveDllReferences(exportConfig.TestDependencies, projectRoot, testOutputDirectory);
                    testDllReferences.AddRange(ResolveDllReferences(exportConfig.Dependencies, projectRoot, testOutputDirectory));
                    var testPackageReferences = ResolvePackageReferences(exportConfig.TestDependencies);
                    testPackageReferences.AddRange(ResolvePackageReferences(exportConfig.Dependencies));
                    var testFrameworkReferences = ResolveFrameworkReferences(exportConfig.TestDependencies);
                    testFrameworkReferences.AddRange(ResolveFrameworkReferences(exportConfig.Dependencies));

                    testProjectFilePath = Path.Combine(testOutputDirectory, $"{SanitizeFileName(exportConfig.EffectiveName)}.Tests.csproj");
                    File.WriteAllText(testProjectFilePath, GenerateTestProjectFile(
                        exportConfig,
                        testPackageReferences,
                        testFrameworkReferences,
                        testProjectReferences,
                        testDllReferences));
                }

                var exportedProject = new ExportedProjectInfo(
                    projectRoot,
                    exportConfig.EffectiveName,
                    projectOutputDirectory,
                    projectFilePath,
                    testProjectFilePath);
                _exportedProjects[projectRoot] = exportedProject;
                return exportedProject;
            }
            finally
            {
                _projectsInProgress.Remove(projectRoot);
            }
        }

        private List<string> ResolveProjectReferences(IEnumerable<Reference> dependencies, string projectRoot, string outputDirectory)
        {
            var projectReferences = new List<string>();

            foreach (var dependency in dependencies.Where(reference => reference.Type == ReferenceType.Project))
            {
                var absoluteReferencePath = Path.GetFullPath(Path.IsPathRooted(dependency.Project!)
                    ? dependency.Project!
                    : Path.Combine(projectRoot, dependency.Project!));

                if (absoluteReferencePath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
                {
                    projectReferences.Add(NormalizePath(Path.GetRelativePath(outputDirectory, absoluteReferencePath)));
                    continue;
                }

                if (!absoluteReferencePath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException(
                        $"Unsupported project reference '{dependency.Project}'. Expected a .csproj or project.yml path.");
                }

                var referencedProjectRoot = Path.GetDirectoryName(absoluteReferencePath)
                    ?? throw new InvalidOperationException($"Could not determine the project root for '{dependency.Project}'.");
                var exportedReference = ExportProject(referencedProjectRoot, isRoot: false);
                projectReferences.Add(NormalizePath(Path.GetRelativePath(outputDirectory, exportedReference.ProjectFilePath)));
            }

            return projectReferences
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        private List<DllReferenceInfo> ResolveDllReferences(IEnumerable<Reference> dependencies, string projectRoot, string outputDirectory)
        {
            var dllReferences = new List<DllReferenceInfo>();

            foreach (var dependency in dependencies.Where(reference => reference.Type == ReferenceType.Dll))
            {
                var absoluteReferencePath = Path.GetFullPath(Path.IsPathRooted(dependency.Dll!)
                    ? dependency.Dll!
                    : Path.Combine(projectRoot, dependency.Dll!));
                if (!File.Exists(absoluteReferencePath))
                {
                    throw new FileNotFoundException($"Referenced DLL not found: {absoluteReferencePath}");
                }

                if (!_copiedDllReferences.TryGetValue(absoluteReferencePath, out var copiedReferencePath))
                {
                    var dllDirectory = Path.Combine(_bundleRoot, "_nsharp_libs");
                    Directory.CreateDirectory(dllDirectory);

                    var copiedFileName = $"{Path.GetFileNameWithoutExtension(absoluteReferencePath)}-{GetPathHash(absoluteReferencePath)}{Path.GetExtension(absoluteReferencePath)}";
                    copiedReferencePath = Path.Combine(dllDirectory, copiedFileName);
                    File.Copy(absoluteReferencePath, copiedReferencePath, overwrite: true);
                    _copiedDllReferences[absoluteReferencePath] = copiedReferencePath;
                }

                dllReferences.Add(new DllReferenceInfo(
                    Path.GetFileNameWithoutExtension(absoluteReferencePath),
                    NormalizePath(Path.GetRelativePath(outputDirectory, copiedReferencePath))));
            }

            return dllReferences
                .Distinct()
                .ToList();
        }

        private static List<PackageReferenceInfo> ResolvePackageReferences(IEnumerable<Reference> dependencies)
        {
            return dependencies
                .Where(reference => reference.Type == ReferenceType.NuGet)
                .Select(reference => new PackageReferenceInfo(reference.Nuget!, reference.Version))
                .Distinct()
                .ToList();
        }

        private static List<string> ResolveFrameworkReferences(IEnumerable<Reference> dependencies)
        {
            return dependencies
                .Where(reference => reference.Type == ReferenceType.Framework)
                .Select(reference => reference.Framework!)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        private static string GenerateMainProjectFile(
            ProjectConfig config,
            List<PackageReferenceInfo> packageReferences,
            List<string> frameworkReferences,
            List<string> projectReferences,
            List<DllReferenceInfo> dllReferences)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"<Project Sdk=\"{EscapeXml(config.Sdk)}\">");
            sb.AppendLine("  <PropertyGroup>");
            sb.AppendLine($"    <TargetFramework>{EscapeXml(config.TargetFramework)}</TargetFramework>");
            sb.AppendLine($"    <OutputType>{(string.Equals(config.OutputType, "library", StringComparison.OrdinalIgnoreCase) ? "Library" : "Exe")}</OutputType>");
            sb.AppendLine($"    <AssemblyName>{EscapeXml(config.EffectiveName)}</AssemblyName>");
            sb.AppendLine("    <LangVersion>latest</LangVersion>");
            sb.AppendLine("    <Nullable>enable</Nullable>");
            sb.AppendLine("    <ImplicitUsings>disable</ImplicitUsings>");
            if (!string.IsNullOrWhiteSpace(config.Version))
            {
                sb.AppendLine($"    <Version>{EscapeXml(config.Version)}</Version>");
            }

            AppendPackageMetadata(sb, config.Package);
            sb.AppendLine("  </PropertyGroup>");

            AppendReferenceItemGroups(sb, packageReferences, frameworkReferences, projectReferences, dllReferences);
            sb.AppendLine("</Project>");
            return sb.ToString();
        }

        private static string GenerateTestProjectFile(
            ProjectConfig config,
            List<PackageReferenceInfo> testPackageReferences,
            List<string> testFrameworkReferences,
            List<string> testProjectReferences,
            List<DllReferenceInfo> testDllReferences)
        {
            var sb = new StringBuilder();
            sb.AppendLine("<Project Sdk=\"Microsoft.NET.Sdk\">");
            sb.AppendLine("  <PropertyGroup>");
            sb.AppendLine($"    <TargetFramework>{EscapeXml(config.TargetFramework)}</TargetFramework>");
            sb.AppendLine("    <LangVersion>latest</LangVersion>");
            sb.AppendLine("    <Nullable>enable</Nullable>");
            sb.AppendLine("    <ImplicitUsings>disable</ImplicitUsings>");
            sb.AppendLine("    <IsPackable>false</IsPackable>");
            sb.AppendLine("    <IsTestProject>true</IsTestProject>");
            sb.AppendLine("  </PropertyGroup>");

            var frameworkPackages = GetTestFrameworkPackages(config.TestFramework);
            testPackageReferences.InsertRange(0, frameworkPackages);

            AppendReferenceItemGroups(sb, testPackageReferences, testFrameworkReferences, testProjectReferences, testDllReferences);
            sb.AppendLine("</Project>");
            return sb.ToString();
        }

        private static void AppendReferenceItemGroups(
            StringBuilder sb,
            List<PackageReferenceInfo> packageReferences,
            List<string> frameworkReferences,
            List<string> projectReferences,
            List<DllReferenceInfo> dllReferences)
        {
            if (packageReferences.Count > 0)
            {
                sb.AppendLine("  <ItemGroup>");
                foreach (var packageReference in packageReferences.Distinct())
                {
                    if (string.IsNullOrWhiteSpace(packageReference.Version))
                    {
                        sb.AppendLine($"    <PackageReference Include=\"{EscapeXml(packageReference.Name)}\" />");
                    }
                    else if (packageReference.PrivateAssetsAll)
                    {
                        sb.AppendLine($"    <PackageReference Include=\"{EscapeXml(packageReference.Name)}\" Version=\"{EscapeXml(packageReference.Version)}\">");
                        sb.AppendLine("      <PrivateAssets>all</PrivateAssets>");
                        if (!string.IsNullOrWhiteSpace(packageReference.IncludeAssets))
                        {
                            sb.AppendLine($"      <IncludeAssets>{EscapeXml(packageReference.IncludeAssets)}</IncludeAssets>");
                        }
                        sb.AppendLine("    </PackageReference>");
                    }
                    else
                    {
                        sb.AppendLine($"    <PackageReference Include=\"{EscapeXml(packageReference.Name)}\" Version=\"{EscapeXml(packageReference.Version)}\" />");
                    }
                }
                sb.AppendLine("  </ItemGroup>");
            }

            if (frameworkReferences.Count > 0)
            {
                sb.AppendLine("  <ItemGroup>");
                foreach (var frameworkReference in frameworkReferences.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    sb.AppendLine($"    <FrameworkReference Include=\"{EscapeXml(frameworkReference)}\" />");
                }
                sb.AppendLine("  </ItemGroup>");
            }

            if (projectReferences.Count > 0)
            {
                sb.AppendLine("  <ItemGroup>");
                foreach (var projectReference in projectReferences.Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    sb.AppendLine($"    <ProjectReference Include=\"{EscapeXml(projectReference)}\" />");
                }
                sb.AppendLine("  </ItemGroup>");
            }

            if (dllReferences.Count > 0)
            {
                sb.AppendLine("  <ItemGroup>");
                foreach (var dllReference in dllReferences.Distinct())
                {
                    sb.AppendLine($"    <Reference Include=\"{EscapeXml(dllReference.Name)}\">");
                    sb.AppendLine($"      <HintPath>{EscapeXml(dllReference.HintPath)}</HintPath>");
                    sb.AppendLine("    </Reference>");
                }
                sb.AppendLine("  </ItemGroup>");
            }
        }

        private static List<PackageReferenceInfo> GetTestFrameworkPackages(string testFramework)
        {
            return string.Equals(testFramework, "nunit", StringComparison.OrdinalIgnoreCase)
                ? new List<PackageReferenceInfo>
                {
                    new("NUnit", "4.3.2"),
                    new("NUnit3TestAdapter", "4.6.0", PrivateAssetsAll: true, IncludeAssets: "runtime; build; native; contentfiles; analyzers; buildtransitive"),
                    new("Microsoft.NET.Test.Sdk", "17.11.1"),
                    new("coverlet.msbuild", "6.0.2", PrivateAssetsAll: true, IncludeAssets: "runtime; build; native; contentfiles; analyzers"),
                }
                : new List<PackageReferenceInfo>
                {
                    new("xunit", "2.9.2"),
                    new("xunit.runner.visualstudio", "2.8.2", PrivateAssetsAll: true, IncludeAssets: "runtime; build; native; contentfiles; analyzers; buildtransitive"),
                    new("Microsoft.NET.Test.Sdk", "17.11.1"),
                    new("coverlet.msbuild", "6.0.2", PrivateAssetsAll: true, IncludeAssets: "runtime; build; native; contentfiles; analyzers"),
                };
        }

        private static void AppendPackageMetadata(StringBuilder sb, PackageConfig? package)
        {
            if (package == null)
            {
                return;
            }

            if (!string.IsNullOrWhiteSpace(package.Author))
            {
                sb.AppendLine($"    <Authors>{EscapeXml(package.Author)}</Authors>");
            }

            if (!string.IsNullOrWhiteSpace(package.Description))
            {
                sb.AppendLine($"    <Description>{EscapeXml(package.Description)}</Description>");
            }

            if (package.Tags is { Count: > 0 })
            {
                sb.AppendLine($"    <PackageTags>{EscapeXml(string.Join(" ", package.Tags))}</PackageTags>");
            }

            if (!string.IsNullOrWhiteSpace(package.License))
            {
                sb.AppendLine($"    <PackageLicenseExpression>{EscapeXml(package.License)}</PackageLicenseExpression>");
            }

            if (!string.IsNullOrWhiteSpace(package.Repository))
            {
                sb.AppendLine($"    <RepositoryUrl>{EscapeXml(package.Repository)}</RepositoryUrl>");
            }

            if (!string.IsNullOrWhiteSpace(package.Icon))
            {
                sb.AppendLine($"    <PackageIcon>{EscapeXml(Path.GetFileName(package.Icon))}</PackageIcon>");
            }
        }

        private static void RecreateDirectory(string path)
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, true);
            }

            Directory.CreateDirectory(path);
        }

        private static void CopyPackageIconIfPresent(ProjectConfig config, string projectRoot, string projectOutputDirectory)
        {
            if (string.IsNullOrWhiteSpace(config.Package?.Icon))
            {
                return;
            }

            var sourceIconPath = Path.IsPathRooted(config.Package.Icon)
                ? config.Package.Icon
                : Path.Combine(projectRoot, config.Package.Icon);
            if (!File.Exists(sourceIconPath))
            {
                return;
            }

            var destinationIconPath = Path.Combine(projectOutputDirectory, Path.GetFileName(sourceIconPath));
            File.Copy(sourceIconPath, destinationIconPath, overwrite: true);
        }

        private static string GetProjectDirectoryName(string projectRoot, string projectName, bool isRoot)
        {
            var sanitizedProjectName = SanitizeFileName(projectName);
            return isRoot
                ? sanitizedProjectName
                : Path.Combine("_nsharp_refs", $"{sanitizedProjectName}-{GetPathHash(projectRoot)}");
        }

        private static string GetPathHash(string path)
        {
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(path)));
            return Convert.ToHexString(bytes[..4]).ToLowerInvariant();
        }

        private static string ChangeSourceExtension(string path)
        {
            return Path.ChangeExtension(path, ".cs");
        }

        private static string SanitizeFileName(string value)
        {
            var invalidChars = Path.GetInvalidFileNameChars();
            return string.Concat(value.Select(ch => invalidChars.Contains(ch) ? '_' : ch));
        }

        private static string EscapeXml(string value)
        {
            return value
                .Replace("&", "&amp;", StringComparison.Ordinal)
                .Replace("\"", "&quot;", StringComparison.Ordinal)
                .Replace("<", "&lt;", StringComparison.Ordinal)
                .Replace(">", "&gt;", StringComparison.Ordinal);
        }

        private static string NormalizePath(string path) => path.Replace('\\', '/');
    }

    private sealed class ProjectExportException(IReadOnlyList<CompilerError> errors)
        : Exception("Project export failed.")
    {
        public IReadOnlyList<CompilerError> Errors { get; } = errors;
    }

    private sealed record ExportedProjectInfo(
        string SourceProjectRoot,
        string ProjectName,
        string ProjectDirectory,
        string ProjectFilePath,
        string? TestProjectFilePath);

    private sealed record PackageReferenceInfo(
        string Name,
        string? Version,
        bool PrivateAssetsAll = false,
        string? IncludeAssets = null);

    private sealed record DllReferenceInfo(string Name, string HintPath);
}

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
        var targetSummary = GetTargetSummary(args);
        if (targetSummary.ShowHelp)
        {
            return ShowHelp();
        }

        return targetSummary.TargetKind switch
        {
            ExportTargetKind.CSharp => ExportCSharp(args.Skip(1).ToArray()),
            _ => Error(ExportCommandKernels.GetUnknownTargetMessage(args[0]))
        };
    }

    internal static ExportTargetSummary GetTargetSummary(string[] args)
        => ExportCommandKernels.GetTargetSummary(args);

    private static int ExportCSharp(string[] args)
    {
        var options = GetExportCSharpOptionSummary(args);
        if (options.ShowHelp)
        {
            return ShowCSharpHelp();
        }

        var outputPath = options.OutputOption;
        var projectOption = options.ProjectOption;

        var firstPositional = GetExportCSharpInputOperand(args);
        if (!string.IsNullOrWhiteSpace(projectOption) && firstPositional != null)
        {
            return Error(ExportCommandKernels.GetSourceAndProjectConflictMessage());
        }

        try
        {
            if (!string.IsNullOrWhiteSpace(projectOption))
            {
                return ExportProjectBundle(Path.GetFullPath(projectOption), outputPath);
            }

            if (firstPositional != null)
            {
                var inputPath = Path.GetFullPath(firstPositional);
                if (File.Exists(inputPath))
                {
                    return ExportSingleFile(inputPath, outputPath);
                }

                if (Directory.Exists(inputPath))
                {
                    return ExportProjectBundle(inputPath, outputPath);
                }

                return Error(ExportCommandKernels.GetPathNotFoundMessage(firstPositional));
            }

            var currentDirectory = Directory.GetCurrentDirectory();
            if (File.Exists(Path.Combine(currentDirectory, "project.yml")))
            {
                return ExportProjectBundle(currentDirectory, outputPath);
            }

            return Error(ExportCommandKernels.GetNoInputMessage());
        }
        catch (Exception ex)
        {
            return Error(ExportCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    private static int ExportSingleFile(string sourceFile, string? outputPath)
    {
        if (!sourceFile.EndsWith(".nl", StringComparison.OrdinalIgnoreCase))
        {
            return Error(ExportCommandKernels.GetExpectedNlFileMessage(sourceFile));
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
            return Error(ExportCommandKernels.GetMissingOutputMessage(sourceFile));
        }

        if (string.IsNullOrWhiteSpace(outputPath))
        {
            Console.Write(csharpSource);
            return 0;
        }

        var resolvedOutputPath = ResolveFileExportPath(sourceFile, outputPath);
        if (string.Equals(Path.GetFullPath(resolvedOutputPath), Path.GetFullPath(sourceFile), StringComparison.OrdinalIgnoreCase))
        {
            return Error(ExportCommandKernels.GetRefuseOverwriteMessage());
        }

        Directory.CreateDirectory(Path.GetDirectoryName(resolvedOutputPath) ?? Directory.GetCurrentDirectory());
        File.WriteAllText(resolvedOutputPath, csharpSource);
        Console.WriteLine(ExportCommandKernels.GetSingleFileSuccessMessage(Path.GetFileName(sourceFile), resolvedOutputPath));
        return 0;
    }

    private static int ExportProjectBundle(string projectRoot, string? outputPath)
    {
        if (!File.Exists(Path.Combine(projectRoot, "project.yml")))
        {
            return Error(ExportCommandKernels.GetNoProjectFileMessage(projectRoot));
        }

        var bundleRoot = Path.GetFullPath(outputPath ?? Path.Combine(projectRoot, "csharp-export"));
        Directory.CreateDirectory(bundleRoot);
        RemoveDirectoryIfExists(Path.Combine(bundleRoot, "_nsharp_refs"));
        RemoveDirectoryIfExists(Path.Combine(bundleRoot, "_nsharp_libs"));

        var exporter = new CSharpProjectExportSession(bundleRoot);
        try
        {
            var exportedProject = exporter.ExportProject(projectRoot, isRoot: true);
            Console.WriteLine(ExportCommandKernels.GetProjectSuccessMessage(exportedProject.ProjectName, exportedProject.ProjectFilePath));
            if (exportedProject.TestProjectFilePath != null)
            {
                Console.WriteLine(ExportCommandKernels.GetTestsSuccessMessage(exportedProject.TestProjectFilePath));
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
        Console.WriteLine(ExportCommandKernels.GetHelpText());

        return 0;
    }

    private static int ShowCSharpHelp()
    {
        Console.WriteLine(ExportCommandKernels.GetCSharpHelpText());

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

    internal static ExportCSharpOptionSummary GetExportCSharpOptionSummary(string[] args)
        => ExportCommandKernels.GetCSharpOptionSummary(args);

    private static string? GetExportCSharpInputOperand(string[] args)
        => ExportCommandKernels.GetCSharpInputOperand(args);

    internal static bool IsTestSourceFile(string sourceFile)
        => ExportCommandKernels.IsTestSourceFile(sourceFile);

    private static void EmitDiagnostics(IEnumerable<CompilerError> errors)
    {
        foreach (var error in errors)
        {
            Console.Error.WriteLine(error.Format());
        }
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message));
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
                var hasTestFiles = exportResult.ExportedFiles.Keys.Any(IsTestSourceFile);
                if (hasTestFiles)
                {
                    RecreateDirectory(testOutputDirectory);
                }

                foreach (var (sourceFile, csharpSource) in exportResult.ExportedFiles.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
                {
                    var relativeSourcePath = Path.GetRelativePath(projectRoot, sourceFile);
                    var relativeCSharpPath = ChangeSourceExtension(relativeSourcePath);
                    var targetDirectory = IsTestSourceFile(sourceFile)
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

            foreach (var dependency in FilterExportReferencesByType(dependencies, ReferenceType.Project))
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

            return DeduplicateExportReferences(projectReferences, StringComparer.OrdinalIgnoreCase);
        }

        private List<DllReferenceInfo> ResolveDllReferences(IEnumerable<Reference> dependencies, string projectRoot, string outputDirectory)
        {
            var dllReferences = new List<DllReferenceInfo>();

            foreach (var dependency in FilterExportReferencesByType(dependencies, ReferenceType.Dll))
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

            return DeduplicateExportReferences(dllReferences);
        }

        private static List<PackageReferenceInfo> ResolvePackageReferences(IEnumerable<Reference> dependencies)
        {
            var packageReferences = FilterExportReferencesByType(dependencies, ReferenceType.NuGet)
                .Select(reference => new PackageReferenceInfo(reference.Nuget!, reference.Version))
                .ToList();

            return DeduplicateExportReferences(packageReferences);
        }

        private static List<string> ResolveFrameworkReferences(IEnumerable<Reference> dependencies)
        {
            var frameworkReferences = FilterExportReferencesByType(dependencies, ReferenceType.Framework)
                .Select(reference => reference.Framework!)
                .ToList();

            return DeduplicateExportReferences(frameworkReferences, StringComparer.OrdinalIgnoreCase);
        }

        private static List<Reference> FilterExportReferencesByType(
            IEnumerable<Reference> dependencies,
            ReferenceType referenceType)
        {
            var dependencyList = dependencies as IReadOnlyList<Reference> ?? dependencies.ToArray();
            return ExportCommandKernels.FilterReferencesByType(dependencyList, referenceType);
        }

        private static string GenerateMainProjectFile(
            ProjectConfig config,
            List<PackageReferenceInfo> packageReferences,
            List<string> frameworkReferences,
            List<string> projectReferences,
            List<DllReferenceInfo> dllReferences)
        {
            var distinctPackageReferences = DeduplicateExportReferences(packageReferences);
            var distinctFrameworkReferences = DeduplicateExportReferences(frameworkReferences, StringComparer.OrdinalIgnoreCase);
            var distinctProjectReferences = DeduplicateExportReferences(projectReferences, StringComparer.OrdinalIgnoreCase);
            var distinctDllReferences = DeduplicateExportReferences(dllReferences);
            var package = config.Package;
            var packageTags = package?.Tags is { Count: > 0 } tags ? string.Join(" ", tags) : string.Empty;
            var packageIcon = package?.Icon;

            return ExportCommandKernels.GetCSharpMainProjectFileText(
                config.Sdk,
                config.TargetFramework,
                string.Equals(config.OutputType, "library", StringComparison.OrdinalIgnoreCase) ? "Library" : "Exe",
                config.EffectiveName,
                config.Version ?? string.Empty,
                package?.Author ?? string.Empty,
                package?.Description ?? string.Empty,
                packageTags,
                package?.Tags?.Count ?? 0,
                package?.License ?? string.Empty,
                package?.Repository ?? string.Empty,
                packageIcon == null ? string.Empty : Path.GetFileName(packageIcon),
                string.IsNullOrWhiteSpace(packageIcon) ? 0 : 1,
                distinctPackageReferences.Select(reference => reference.Name).ToArray(),
                distinctPackageReferences.Select(reference => reference.Version ?? string.Empty).ToArray(),
                distinctPackageReferences.Select(reference => reference.PrivateAssetsAll ? 1 : 0).ToArray(),
                distinctPackageReferences.Select(reference => reference.IncludeAssets ?? string.Empty).ToArray(),
                distinctFrameworkReferences.ToArray(),
                distinctProjectReferences.ToArray(),
                distinctDllReferences.Select(reference => reference.Name).ToArray(),
                distinctDllReferences.Select(reference => reference.HintPath).ToArray());
        }

        private static string GenerateTestProjectFile(
            ProjectConfig config,
            List<PackageReferenceInfo> testPackageReferences,
            List<string> testFrameworkReferences,
            List<string> testProjectReferences,
            List<DllReferenceInfo> testDllReferences)
        {
            var frameworkPackages = GetTestFrameworkPackages(config.TestFramework);
            testPackageReferences.InsertRange(0, frameworkPackages);

            var distinctPackageReferences = DeduplicateExportReferences(testPackageReferences);
            var distinctFrameworkReferences = DeduplicateExportReferences(testFrameworkReferences, StringComparer.OrdinalIgnoreCase);
            var distinctProjectReferences = DeduplicateExportReferences(testProjectReferences, StringComparer.OrdinalIgnoreCase);
            var distinctDllReferences = DeduplicateExportReferences(testDllReferences);

            return ExportCommandKernels.GetCSharpTestProjectFileText(
                config.TargetFramework,
                distinctPackageReferences.Select(reference => reference.Name).ToArray(),
                distinctPackageReferences.Select(reference => reference.Version ?? string.Empty).ToArray(),
                distinctPackageReferences.Select(reference => reference.PrivateAssetsAll ? 1 : 0).ToArray(),
                distinctPackageReferences.Select(reference => reference.IncludeAssets ?? string.Empty).ToArray(),
                distinctFrameworkReferences.ToArray(),
                distinctProjectReferences.ToArray(),
                distinctDllReferences.Select(reference => reference.Name).ToArray(),
                distinctDllReferences.Select(reference => reference.HintPath).ToArray());
        }

        private static List<T> DeduplicateExportReferences<T>(
            IReadOnlyList<T> references,
            IEqualityComparer<T>? comparer = null)
            where T : notnull
            => ExportCommandKernels.DeduplicateReferences(references, comparer);

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

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Serialization;
using System.Text.Json;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class TreeCommand
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static int Execute(string[] args)
    {
        var options = TreeCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var projectRoot = GetProjectRoot(options);
        var outputMode = TreeCommandKernels.GetOutputMode(options.Json);
        var maxDepth = TreeCommandKernels.GetMaxDepth(args, int.MaxValue);

        if (!Directory.Exists(projectRoot))
            return Error(TreeCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot), outputMode, projectRoot);

        try
        {
            var report = BuildReport(projectRoot, maxDepth);

            if (outputMode == TreeOutputModeKind.Json)
            {
                Console.WriteLine(JsonSerializer.Serialize(report, JsonOptions));
            }
            else
            {
                RenderTree(report);
            }

            return 0;
        }
        catch (Exception ex)
        {
            return Error(TreeCommandKernels.GetTreeFailedMessage(ex.Message), outputMode, projectRoot);
        }
    }

    static TreeReport BuildReport(string projectRoot, int maxDepth)
    {
        projectRoot = Path.GetFullPath(projectRoot);
        var projectYml = Path.Combine(projectRoot, "project.yml");
        var csproj = Directory.GetFiles(projectRoot, "*.csproj", SearchOption.TopDirectoryOnly)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();

        if (csproj != null)
        {
            if (File.Exists(projectYml))
                RestoreCommand.Restore(projectRoot, quiet: true);

            return BuildFromMsbuild(projectRoot, csproj, File.Exists(projectYml) ? projectYml : null, maxDepth);
        }

        if (File.Exists(projectYml))
            return BuildFromProjectYml(projectRoot, projectYml, maxDepth);

        throw new InvalidOperationException(
            TreeCommandKernels.GetNoProjectFileMessage());
    }

    static TreeReport BuildFromProjectYml(string projectRoot, string projectYml, int maxDepth, string? extraLimitation = null)
    {
        var config = ProjectFileParser.Parse(projectYml);
        var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";
        var allDirect = Deduplicate(config.Dependencies.Select(ToProjectYmlDependency));

        var direct = maxDepth >= 1 ? allDirect : Array.Empty<TreeDependency>();
        var limitations = new List<string>
        {
            TreeCommandKernels.GetProjectYmlLimitationMessage()
        };
        if (!string.IsNullOrWhiteSpace(extraLimitation))
            limitations.Add(extraLimitation);

        return new TreeReport(
            SchemaVersion: 2,
            Command: "tree",
            Ok: true,
            ProjectRoot: NormalizePath(projectRoot),
            Project: new TreeProject(projectName, config.TargetFramework, "project.yml"),
            MaxDepth: maxDepth,
            Capabilities: new TreeCapabilities(DirectDependencies: true, TransitiveNuGetDependencies: false),
            Dependencies: direct,
            TransitiveDependencies: Array.Empty<TreeDependency>(),
            Summary: new TreeSummary(Direct: direct.Length, Transitive: 0, Total: direct.Length),
            Limitations: limitations);
    }

    static TreeReport BuildFromMsbuild(string projectRoot, string csproj, string? projectYml, int maxDepth)
    {
        ProjectConfig? config = null;
        if (projectYml != null)
            config = ProjectFileParser.Parse(projectYml);

        var result = DotnetRunner.Run(
            $"list \"{csproj}\" package --include-transitive --format json",
            workingDirectory: projectRoot);

        if (result.ExitCode != 0)
        {
            var detail = GetDotnetListFailureDetail(result);
            if (config != null && projectYml != null)
            {
                return BuildFromProjectYml(
                    projectRoot,
                    projectYml,
                    maxDepth,
                    TreeCommandKernels.GetTransitiveResolutionFailedLimitation(detail));
            }

            throw new InvalidOperationException(TreeCommandKernels.GetDotnetRestoreRetryMessage(detail));
        }

        using var doc = JsonDocument.Parse(result.Stdout);
        var projectName = config?.Name ?? Path.GetFileNameWithoutExtension(csproj);
        var targetFrameworks = new List<string>();
        var direct = config?.Dependencies.Select(ToProjectYmlDependency).ToList() ?? new List<TreeDependency>();
        var transitive = new List<TreeDependency>();

        if (doc.RootElement.TryGetProperty("projects", out var projects))
        {
            foreach (var project in projects.EnumerateArray())
            {
                if (!project.TryGetProperty("frameworks", out var frameworks))
                    continue;

                foreach (var framework in frameworks.EnumerateArray())
                {
                    var targetFramework = framework.TryGetProperty("framework", out var frameworkElement)
                        ? frameworkElement.GetString()
                        : null;
                    if (!string.IsNullOrWhiteSpace(targetFramework))
                        targetFrameworks.Add(targetFramework!);

                    direct.AddRange(ReadPackageSection(framework, "topLevelPackages", transitive: false));
                    transitive.AddRange(ReadPackageSection(framework, "transitivePackages", transitive: true));
                }
            }
        }

        var visibleDirect = maxDepth >= 1 ? Deduplicate(direct) : Array.Empty<TreeDependency>();
        var visibleTransitive = maxDepth >= 2 ? Deduplicate(transitive) : Array.Empty<TreeDependency>();
        var frameworkName = FormatTargetFrameworks(targetFrameworks);

        return new TreeReport(
            SchemaVersion: 2,
            Command: "tree",
            Ok: true,
            ProjectRoot: NormalizePath(projectRoot),
            Project: new TreeProject(projectName, frameworkName, config != null ? "project.yml+msbuild" : "msbuild"),
            MaxDepth: maxDepth,
            Capabilities: new TreeCapabilities(DirectDependencies: true, TransitiveNuGetDependencies: true),
            Dependencies: visibleDirect,
            TransitiveDependencies: visibleTransitive,
            Summary: new TreeSummary(
                Direct: visibleDirect.Length,
                Transitive: visibleTransitive.Length,
                Total: visibleDirect.Length + visibleTransitive.Length),
            Limitations: Array.Empty<string>());
    }

    static TreeDependency ToProjectYmlDependency(Reference reference)
    {
        var kind = reference.Type switch
        {
            ReferenceType.NuGet => "nuget",
            ReferenceType.Framework => "framework",
            ReferenceType.Project => "project",
            ReferenceType.Dll => "dll",
            _ => "unknown"
        };

        var version = reference.Type == ReferenceType.NuGet ? reference.Version : null;
        return new TreeDependency(
            Name: NormalizePath(reference.Value),
            Kind: kind,
            Version: version,
            Scope: "runtime",
            Transitive: false,
            Dependencies: Array.Empty<TreeDependency>());
    }

    static TreeDependency[] ReadPackageSection(JsonElement framework, string propertyName, bool transitive)
    {
        if (!framework.TryGetProperty(propertyName, out var packages))
            return Array.Empty<TreeDependency>();

        return packages.EnumerateArray()
            .Select(package => new TreeDependency(
                Name: package.GetProperty("id").GetString() ?? "",
                Kind: "nuget",
                Version: GetPackageVersion(package),
                Scope: "runtime",
                Transitive: transitive,
                Dependencies: Array.Empty<TreeDependency>()))
            .Where(dependency => dependency.Name.Length > 0)
            .ToArray();
    }

    internal static TreeDependency[] Deduplicate(IEnumerable<TreeDependency> dependencies)
    {
        var dependencyArray = dependencies as TreeDependency[] ?? dependencies.ToArray();
        return TreeDependencyDeduplicator.Deduplicate(dependencyArray);
    }

    internal static string FormatTargetFrameworks(IReadOnlyList<string> targetFrameworks)
    {
        if (targetFrameworks.Count == 0)
            return "unknown";

        var distinctFrameworks = TreeDependencyDeduplicator.DeduplicateTargetFrameworks(targetFrameworks);
        return string.Join(",", distinctFrameworks);
    }

    static string? GetPackageVersion(JsonElement package)
    {
        foreach (var property in new[] { "resolvedVersion", "requestedVersion", "version" })
        {
            if (package.TryGetProperty(property, out var version) && version.ValueKind == JsonValueKind.String)
                return version.GetString();
        }

        return null;
    }

    static string GetDotnetListFailureDetail(DotnetRunner.RunResult result)
    {
        if (!string.IsNullOrWhiteSpace(result.Stderr))
            return result.Stderr.Trim();

        if (!string.IsNullOrWhiteSpace(result.Stdout))
            return result.Stdout.Trim();

        return TreeCommandKernels.GetDotnetListFailedMessage();
    }

    static void RenderTree(TreeReport report)
    {
        Console.WriteLine(TreeCommandKernels.GetProjectHeader(report.Project.Name, report.Project.TargetFramework));

        if (report.Dependencies.Count == 0 && report.TransitiveDependencies.Count == 0)
        {
            Console.WriteLine(TreeCommandKernels.GetNoDependenciesLine());
        }

        for (var i = 0; i < report.Dependencies.Count; i++)
        {
            var isLast = i == report.Dependencies.Count - 1;
            Console.WriteLine(TreeCommandKernels.GetDependencyLine(isLast, FormatDependency(report.Dependencies[i])));
        }

        if (report.TransitiveDependencies.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine(TreeCommandKernels.GetTransitiveHeader(report.TransitiveDependencies.Count));
            foreach (var dependency in report.TransitiveDependencies)
                Console.WriteLine(TreeCommandKernels.GetTransitiveDependencyLine(FormatDependency(dependency)));
        }

        if (report.Limitations.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine(TreeCommandKernels.GetLimitationsHeader());
            foreach (var limitation in report.Limitations)
                Console.WriteLine(TreeCommandKernels.GetLimitationLine(limitation));
        }
    }

    static string FormatDependency(TreeDependency dependency)
        => TreeCommandKernels.GetDependencyText(dependency.Name, dependency.Version, dependency.Kind);

    private static string GetProjectRoot(TreeOptionSummary options)
        => Path.GetFullPath(options.ProjectOption ?? Directory.GetCurrentDirectory());

    static int ShowHelp()
    {
        Console.WriteLine(TreeCommandKernels.GetHelpText());
        return 0;
    }

    static int Error(string message, TreeOutputModeKind outputMode = TreeOutputModeKind.Text, string? projectRoot = null)
    {
        if (outputMode == TreeOutputModeKind.Json)
        {
            Console.Write(OutputFormatter.ErrorToJson("tree", message, projectRoot));
        }
        else
        {
            Console.Error.WriteLine(message);
        }

        return 1;
    }

    static string NormalizePath(string path) => path.Replace('\\', '/');

    private sealed record TreeReport(
        int SchemaVersion,
        string Command,
        bool Ok,
        string ProjectRoot,
        TreeProject Project,
        int MaxDepth,
        TreeCapabilities Capabilities,
        IReadOnlyList<TreeDependency> Dependencies,
        IReadOnlyList<TreeDependency> TransitiveDependencies,
        TreeSummary Summary,
        IReadOnlyList<string> Limitations);

    private sealed record TreeProject(string Name, string TargetFramework, string Source);

    private sealed record TreeCapabilities(bool DirectDependencies, bool TransitiveNuGetDependencies);

    internal sealed record TreeDependency(
        string Name,
        string Kind,
        string? Version,
        string Scope,
        bool Transitive,
        IReadOnlyList<TreeDependency> Dependencies);

    private sealed record TreeSummary(int Direct, int Transitive, int Total);

}

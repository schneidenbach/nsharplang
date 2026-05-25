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
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = GetProjectRoot(args);
        var json = args.Contains("--json");
        var maxDepth = GetIntOption(args, "--depth") ?? int.MaxValue;

        if (!Directory.Exists(projectRoot))
            return Error($"Project directory not found: {projectRoot}", json, projectRoot);

        try
        {
            var report = BuildReport(projectRoot, maxDepth);

            if (json)
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
            return Error($"Tree failed: {ex.Message}", json, projectRoot);
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
            "No project.yml or .csproj found. nlc tree reads direct dependencies from project.yml; transitive NuGet dependency output requires an MSBuild project file.");
    }

    static TreeReport BuildFromProjectYml(string projectRoot, string projectYml, int maxDepth, string? extraLimitation = null)
    {
        var config = ProjectFileParser.Parse(projectYml);
        var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";
        var allDirect = config.Dependencies
            .Select(ToProjectYmlDependency)
            .OrderBy(dependency => dependency.Kind, StringComparer.Ordinal)
            .ThenBy(dependency => dependency.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var direct = maxDepth >= 1 ? allDirect : Array.Empty<TreeDependency>();
        var limitations = new List<string>
        {
            "project.yml output lists direct runtime dependencies only. Transitive NuGet dependencies require an MSBuild project file so dotnet can resolve the package graph."
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
                    $"Transitive NuGet dependency resolution through MSBuild failed: {detail}");
            }

            throw new InvalidOperationException($"{detail} Run 'dotnet restore' and retry.");
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
        var frameworkName = targetFrameworks.Count == 0
            ? "unknown"
            : string.Join(",", targetFrameworks.Distinct(StringComparer.OrdinalIgnoreCase));

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

    static TreeDependency[] Deduplicate(IEnumerable<TreeDependency> dependencies)
    {
        return dependencies
            .GroupBy(dependency => (dependency.Kind, dependency.Name), dependency => dependency, new TreeDependencyKeyComparer())
            .Select(group => group.First())
            .OrderBy(dependency => dependency.Kind, StringComparer.Ordinal)
            .ThenBy(dependency => dependency.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
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

        return "dotnet list package failed.";
    }

    static void RenderTree(TreeReport report)
    {
        Console.WriteLine($"{report.Project.Name} ({report.Project.TargetFramework})");

        if (report.Dependencies.Count == 0 && report.TransitiveDependencies.Count == 0)
        {
            Console.WriteLine("  (no dependencies)");
        }

        for (var i = 0; i < report.Dependencies.Count; i++)
        {
            var isLast = i == report.Dependencies.Count - 1;
            var prefix = isLast ? "└── " : "├── ";
            Console.WriteLine($"{prefix}{FormatDependency(report.Dependencies[i])}");
        }

        if (report.TransitiveDependencies.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine($"  transitive ({report.TransitiveDependencies.Count} packages):");
            foreach (var dependency in report.TransitiveDependencies)
                Console.WriteLine($"    {FormatDependency(dependency)}");
        }

        if (report.Limitations.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine("Limitations:");
            foreach (var limitation in report.Limitations)
                Console.WriteLine($"  - {limitation}");
        }
    }

    static string FormatDependency(TreeDependency dependency)
    {
        var version = string.IsNullOrWhiteSpace(dependency.Version) ? "" : $"@{dependency.Version}";
        return $"{dependency.Name}{version} [{dependency.Kind}]";
    }

    static string GetProjectRoot(string[] args)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == "--project")
                return Path.GetFullPath(args[i + 1]);
        return Path.GetFullPath(Directory.GetCurrentDirectory());
    }

    static int? GetIntOption(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag && int.TryParse(args[i + 1], out var val))
                return val;
        return null;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Dependency Tree

Usage: nlc tree [options]

Show the project's dependencies and transitive NuGet packages when available.

Options:
  --project <dir>   Project root directory (default: current directory)
  --depth <n>       Maximum tree depth to display
  --json            Output as JSON envelope
  --help, -h        Show this help text

Examples:
  nlc tree
  nlc tree --depth 1
  nlc tree --json

Behavior:
  project.yml projects list direct runtime dependencies without requiring .csproj files.
  Transitive NuGet dependencies are included when an MSBuild project file is present.

Exit codes:
  0  Tree displayed successfully
  1  Failed to display tree");

        return 0;
    }

    static int Error(string message, bool json = false, string? projectRoot = null)
    {
        if (json)
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

    private sealed record TreeDependency(
        string Name,
        string Kind,
        string? Version,
        string Scope,
        bool Transitive,
        IReadOnlyList<TreeDependency> Dependencies);

    private sealed record TreeSummary(int Direct, int Transitive, int Total);

    private sealed class TreeDependencyKeyComparer : IEqualityComparer<(string Kind, string Name)>
    {
        public bool Equals((string Kind, string Name) x, (string Kind, string Name) y)
        {
            return string.Equals(x.Kind, y.Kind, StringComparison.Ordinal)
                && string.Equals(x.Name, y.Name, StringComparison.OrdinalIgnoreCase);
        }

        public int GetHashCode((string Kind, string Name) obj)
        {
            return HashCode.Combine(
                StringComparer.Ordinal.GetHashCode(obj.Kind),
                StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Name));
        }
    }
}

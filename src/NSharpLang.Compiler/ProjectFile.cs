using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using YamlDotNet.Core;
using YamlDotNet.Core.Events;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace NSharpLang.Compiler;

/// <summary>
/// Represents the project.yml configuration file
/// </summary>
public class ProjectConfig
{
    /// <summary>
    /// Project name (optional, defaults to directory name)
    /// </summary>
    public string? Name { get; set; }

    /// <summary>
    /// Project version (e.g., "1.0.0")
    /// </summary>
    public string? Version { get; set; }

    /// <summary>
    /// Entry point file for executables (e.g., "Program.nl")
    /// </summary>
    public string? Entry { get; set; }

    /// <summary>
    /// Compilation backend: "il" (default and only supported executable backend).
    /// </summary>
    public string Backend { get; set; } = CompilationBackend.Il.ToConfigValue();

    /// <summary>
    /// Output type: "exe" or "library"
    /// </summary>
    public string OutputType { get; set; } = "exe";

    /// <summary>
    /// Target framework (e.g., "net8.0", "net10.0")
    /// </summary>
    public string TargetFramework { get; set; } = "net10.0";

    /// <summary>
    /// SDK type: "Microsoft.NET.Sdk" or "Microsoft.NET.Sdk.Web"
    /// </summary>
    public string Sdk { get; set; } = "Microsoft.NET.Sdk";

    /// <summary>
    /// References (NuGet packages, DLLs, projects, frameworks)
    /// </summary>
    /// <summary>
    /// Runtime dependencies (NuGet packages, framework references, DLL files)
    /// </summary>
    public List<Reference> Dependencies { get; set; } = new();

    /// <summary>
    /// Test-specific dependencies (only included when running tests)
    /// </summary>
    public List<Reference> TestDependencies { get; set; } = new();

    /// <summary>
    /// Files to exclude from compilation
    /// Supports glob patterns (e.g., "*.tests.nl", "temp/**/*.nl")
    /// By default, all .nl files are included except those matching exclude patterns
    /// </summary>
    public List<string> Exclude { get; set; } = new();

    /// <summary>
    /// Test framework to use: "xunit" (default) or "nunit"
    /// </summary>
    public string TestFramework { get; set; } = "xunit";

    /// <summary>
    /// Conditional-compilation symbols defined for the whole project. These drive
    /// <c>#if</c>/<c>#elif</c> evaluation in source. The build also defines
    /// <c>DEBUG</c> for debug builds and any symbols passed via <c>nlc --define</c>.
    /// </summary>
    public List<string> Defines { get; set; } = new();

    /// <summary>
    /// Language-specific configuration
    /// </summary>
    public LanguageConfig Language { get; set; } = new();

    /// <summary>
    /// NuGet package metadata (required for 'nlc pack')
    /// </summary>
    public PackageConfig? Package { get; set; }

    /// <summary>
    /// Gets the effective project name (uses Name or defaults to directory name)
    /// </summary>
    [YamlIgnore]
    public string EffectiveName => Name ?? Path.GetFileName(Environment.CurrentDirectory) ?? "Project";

    [YamlIgnore]
    public CompilationBackend EffectiveBackend => CompilationBackendExtensions.Parse(Backend);

    /// <summary>
    /// Source generator assemblies discovered from package, framework, and project references.
    /// This is compiler-internal state: project.yml remains the source of user-authored
    /// references, while resolver stages populate concrete generator assembly paths.
    /// </summary>
    [YamlIgnore]
    public List<SourceGeneratorReference> SourceGenerators { get; set; } = new();

    /// <summary>
    /// Gets all .nl files in the project directory, excluding test files and files matching exclude patterns
    /// </summary>
    /// <param name="projectRoot">Root directory of the project</param>
    /// <param name="includeTests">Whether to include .tests.nl files (default: false)</param>
    /// <returns>Array of file paths</returns>
    public string[] GetSourceFiles(string projectRoot, bool includeTests = false)
    {
        // Get all .nl files recursively, skipping build/tooling directories and
        // local agent worktrees that can mirror the repo and explode the project size.
        var allFiles = EnumerateSourceFiles(projectRoot).ToArray();

        return ProjectSourceFileFilter.Filter(
            allFiles,
            projectRoot,
            Exclude.ToArray(),
            includeTests);
    }

    private static readonly HashSet<string> DefaultSkippedSourceDirectories = new(StringComparer.OrdinalIgnoreCase)
    {
        ".context", ".git", ".github", ".hermes", ".vscode", ".vscode-test", ".worktrees",
        "bin", "node_modules", "nsharp", "obj", "out"
    };

    public static IEnumerable<string> EnumerateSourceFiles(string projectRoot)
    {
        if (!Directory.Exists(projectRoot))
        {
            return Array.Empty<string>();
        }

        return EnumerateSourceFilesRecursive(Path.GetFullPath(projectRoot));
    }

    private static IEnumerable<string> EnumerateSourceFilesRecursive(string directory)
    {
        string[] files;
        try
        {
            files = Directory.GetFiles(directory, "*.nl", SearchOption.TopDirectoryOnly);
        }
        catch
        {
            yield break;
        }

        foreach (var file in files)
        {
            yield return file;
        }

        string[] subdirectories;
        try
        {
            subdirectories = Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly);
        }
        catch
        {
            yield break;
        }

        foreach (var subdirectory in subdirectories)
        {
            if (DefaultSkippedSourceDirectories.Contains(Path.GetFileName(subdirectory)))
            {
                continue;
            }

            foreach (var file in EnumerateSourceFilesRecursive(subdirectory))
            {
                yield return file;
            }
        }
    }

}

public enum SourceGeneratorReferenceKind
{
    Package,
    Project,
    Framework,
    Direct
}

public sealed record SourceGeneratorReference(
    string Path,
    SourceGeneratorReferenceKind Kind,
    string Origin,
    bool IsImplicitFramework = false);

/// <summary>
/// Reference to an external dependency
/// </summary>
public class Reference
{
    /// <summary>
    /// NuGet package name (e.g., "Microsoft.EntityFrameworkCore")
    /// </summary>
    public string? Nuget { get; set; }

    /// <summary>
    /// Version for NuGet package (optional, defaults to latest)
    /// </summary>
    public string? Version { get; set; }

    /// <summary>
    /// Path to local DLL file (e.g., "libs/MyLibrary.dll")
    /// </summary>
    public string? Dll { get; set; }

    /// <summary>
    /// Path to local project file (e.g., "../Shared/Shared.csproj" or "../Models/project.yml")
    /// </summary>
    public string? Project { get; set; }

    /// <summary>
    /// Framework reference (e.g., "Microsoft.AspNetCore.App")
    /// </summary>
    public string? Framework { get; set; }

    /// <summary>
    /// Get the reference type
    /// </summary>
    [YamlIgnore]
    public ReferenceType Type
    {
        get
        {
            if (Nuget != null) return ReferenceType.NuGet;
            if (Dll != null) return ReferenceType.Dll;
            if (Project != null) return ReferenceType.Project;
            if (Framework != null) return ReferenceType.Framework;
            throw new InvalidOperationException("Reference must specify one of: nuget, dll, project, or framework");
        }
    }

    /// <summary>
    /// Get the reference value (package name, path, etc.)
    /// </summary>
    [YamlIgnore]
    public string Value => Nuget ?? Dll ?? Project ?? Framework
        ?? throw new InvalidOperationException("Invalid reference");

    [YamlIgnore]
    public bool HasValue =>
        !string.IsNullOrWhiteSpace(Nuget) ||
        !string.IsNullOrWhiteSpace(Dll) ||
        !string.IsNullOrWhiteSpace(Project) ||
        !string.IsNullOrWhiteSpace(Framework);

    /// <summary>
    /// Validate this reference
    /// </summary>
    public void Validate(string projectDirectory)
    {
        switch (Type)
        {
            case ReferenceType.NuGet:
                if (string.IsNullOrWhiteSpace(Nuget))
                    throw new InvalidOperationException("NuGet reference must have a package name");
                break;

            case ReferenceType.Dll:
                if (string.IsNullOrWhiteSpace(Dll))
                    throw new InvalidOperationException("DLL reference must have a path");

                var dllPath = Path.IsPathRooted(Dll)
                    ? Dll
                    : Path.Combine(projectDirectory, Dll);

                if (!File.Exists(dllPath))
                    throw new FileNotFoundException($"DLL not found: {Dll} (resolved to {dllPath})");
                break;

            case ReferenceType.Project:
                if (string.IsNullOrWhiteSpace(Project))
                    throw new InvalidOperationException("Project reference must have a path");

                var projectPath = Path.IsPathRooted(Project)
                    ? Project
                    : Path.Combine(projectDirectory, Project);

                if (!File.Exists(projectPath))
                    throw new FileNotFoundException($"Project file not found: {Project} (resolved to {projectPath})");
                break;

            case ReferenceType.Framework:
                if (string.IsNullOrWhiteSpace(Framework))
                    throw new InvalidOperationException("Framework reference must have a name");
                break;
        }
    }
}

/// <summary>
/// Type of reference
/// </summary>
public enum ReferenceType
{
    NuGet,
    Dll,
    Project,
    Framework
}

/// <summary>
/// NuGet package metadata for 'nlc pack'
/// </summary>
public class PackageConfig
{
    /// <summary>
    /// Package author (mapped to MSBuild Authors property)
    /// </summary>
    public string? Author { get; set; }

    /// <summary>
    /// Short description of the package
    /// </summary>
    public string? Description { get; set; }

    /// <summary>
    /// Space-separated list of package tags/keywords
    /// </summary>
    public List<string>? Tags { get; set; }

    /// <summary>
    /// SPDX license expression (e.g., "MIT", "Apache-2.0")
    /// </summary>
    public string? License { get; set; }

    /// <summary>
    /// Source repository URL
    /// </summary>
    public string? Repository { get; set; }

    /// <summary>
    /// Path to icon file (relative to project root)
    /// </summary>
    public string? Icon { get; set; }
}

/// <summary>
/// Language-specific configuration options
/// </summary>
public class LanguageConfig
{
    /// <summary>
    /// Optional language profile. "default" keeps ordinary N# policy; "systems"
    /// enables whole-project systems diagnostics.
    /// </summary>
    public string Profile { get; set; } = "default";

    /// <summary>
    /// Default async return type wrapper: "Task" or "ValueTask"
    /// </summary>
    public string AsyncDefaultType { get; set; } = "ValueTask";

    /// <summary>
    /// Opt in to pooled async value-task builders
    /// (<c>PoolingAsyncValueTaskMethodBuilder</c>) for ValueTask-returning async methods.
    ///
    /// This selects the builder at codegen time but only takes effect once real async state
    /// machines are emitted for the IL backend to drive; until then it is inert plumbing. See
    /// docs/design/performance-compiler-refactor.md (Async &amp; Iterators).
    /// </summary>
    public bool PooledAsync { get; set; }

    /// <summary>
    /// Systems-profile policy. Used when <see cref="Profile"/> is "systems";
    /// local [hot] checks are still enforced in default projects.
    /// </summary>
    public SystemsConfig Systems { get; set; } = new();
}

public class SystemsConfig
{
    /// <summary>
    /// Systems policy mode: "audit" reports facts without failing builds; "strict"
    /// promotes policy violations to errors.
    /// </summary>
    public string Mode { get; set; } = "strict";

    /// <summary>
    /// Unknown external call policy outside [hot]: "allow", "warn", or "error".
    /// [hot] always fails closed for unknown external calls.
    /// </summary>
    public string UnknownExternalCalls { get; set; } = "warn";

    /// <summary>
    /// Target used for target-qualified AOT/trimming facts.
    /// </summary>
    public string AotTarget { get; set; } = "nativeaot";

    /// <summary>
    /// User-authored warmup functions that make hot paths warm-ready.
    /// </summary>
    public List<string> Warmup { get; set; } = new();

    /// <summary>
    /// Maximum stackalloc reservation accepted by systems analysis without a
    /// stronger proof. Defaults to 4096 bytes.
    /// </summary>
    public int StackBudgetBytes { get; set; } = 4096;

    /// <summary>
    /// Explicit HotSummary sidecar files, relative to project.yml unless
    /// absolute. Sidecars are accepted for ordinary systems analysis.
    /// </summary>
    public List<string> HotSummaryFiles { get; set; } = new();

    /// <summary>
    /// Whether sidecar HotSummary entries may satisfy [hot] calls. The default
    /// is fail-closed; the compiler-owned BCL pack and source inference remain
    /// hot-callable.
    /// </summary>
    public bool AllowHotSidecars { get; set; }
}

/// <summary>
/// YAML type converter for Reference to support shorthand syntax (Package@Version)
/// </summary>
public class ReferenceConverter : IYamlTypeConverter
{
    public bool Accepts(Type type) => type == typeof(Reference);

    public object ReadYaml(IParser parser, Type type, ObjectDeserializer rootDeserializer)
    {
        // Check if it's a scalar (string) value
        if (parser.Current is Scalar scalar)
        {
            parser.MoveNext();
            var value = scalar.Value;

            // Handle shorthand: "Package@Version"
            if (value.Contains('@'))
            {
                var parts = value.Split('@', 2);
                return new Reference
                {
                    Nuget = parts[0].Trim(),
                    Version = parts[1].Trim()
                };
            }

            // If no @, treat as NuGet package without version
            return new Reference { Nuget = value.Trim() };
        }

        // Otherwise parse as mapping (object)
        if (parser.Current is MappingStart)
        {
            parser.MoveNext();
            var reference = new Reference();

            while (parser.Current is not MappingEnd)
            {
                if (parser.Current is Scalar key)
                {
                    var keyValue = key.Value.ToLowerInvariant();
                    parser.MoveNext();

                    if (parser.Current is Scalar valueScalar)
                    {
                        var value = valueScalar.Value;
                        parser.MoveNext();

                        switch (keyValue)
                        {
                            case "nuget":
                                // Handle shorthand syntax: "Package@Version"
                                if (value.Contains('@'))
                                {
                                    var parts = value.Split('@', 2);
                                    reference.Nuget = parts[0].Trim();
                                    reference.Version = parts[1].Trim();
                                }
                                else
                                {
                                    reference.Nuget = value;
                                }
                                break;
                            case "version":
                                reference.Version = value;
                                break;
                            case "dll":
                                reference.Dll = value;
                                break;
                            case "project":
                                reference.Project = value;
                                break;
                            case "framework":
                                reference.Framework = value;
                                break;
                        }
                    }
                }
            }

            parser.MoveNext(); // Skip MappingEnd
            return reference;
        }

        throw new YamlException("Invalid reference format");
    }

    public void WriteYaml(IEmitter emitter, object? value, Type type, ObjectSerializer serializer)
    {
        if (value is not Reference reference)
        {
            throw new InvalidOperationException("Expected Reference object");
        }

        // Write as shorthand if NuGet with version
        if (reference.Type == ReferenceType.NuGet && !string.IsNullOrEmpty(reference.Version))
        {
            emitter.Emit(new Scalar(null, null, $"{reference.Nuget}@{reference.Version}", ScalarStyle.Plain, true, false));
        }
        else
        {
            // Write as mapping
            emitter.Emit(new MappingStart(null, null, false, MappingStyle.Block));

            switch (reference.Type)
            {
                case ReferenceType.NuGet:
                    emitter.Emit(new Scalar("nuget"));
                    emitter.Emit(new Scalar(reference.Nuget!)); // Non-null when Type is NuGet
                    break;
                case ReferenceType.Dll:
                    emitter.Emit(new Scalar("dll"));
                    emitter.Emit(new Scalar(reference.Dll!)); // Non-null when Type is Dll
                    break;
                case ReferenceType.Project:
                    emitter.Emit(new Scalar("project"));
                    emitter.Emit(new Scalar(reference.Project!)); // Non-null when Type is Project
                    break;
                case ReferenceType.Framework:
                    emitter.Emit(new Scalar("framework"));
                    emitter.Emit(new Scalar(reference.Framework!)); // Non-null when Type is Framework
                    break;
            }

            emitter.Emit(new MappingEnd());
        }
    }
}

/// <summary>
/// Parser for project.yml configuration files
/// </summary>
public class ProjectFileParser
{
    /// <summary>
    /// Parse a project.yml file from the given path
    /// </summary>
    public static ProjectConfig Parse(string yamlPath)
    {
        if (!File.Exists(yamlPath))
        {
            throw new FileNotFoundException($"Project file not found: {yamlPath}");
        }

        var yaml = File.ReadAllText(yamlPath);
        var deserializer = new DeserializerBuilder()
            .WithNamingConvention(CamelCaseNamingConvention.Instance)
            .WithTypeConverter(new ReferenceConverter())
            .IgnoreUnmatchedProperties()
            .Build();

        var config = deserializer.Deserialize<ProjectConfig>(yaml);

        // Validate the configuration
        ValidateConfig(config, Path.GetDirectoryName(yamlPath) ?? Environment.CurrentDirectory);

        return config;
    }

    /// <summary>
    /// Look for and parse project.yml in the given directory
    /// Returns null if no project.yml found
    /// </summary>
    public static ProjectConfig? ParseFromDirectory(string directory)
    {
        var projectPath = Path.Combine(directory, "project.yml");

        if (!File.Exists(projectPath))
        {
            return null;
        }

        return Parse(projectPath);
    }

    /// <summary>
    /// Create a default project configuration (used when no project.yml exists)
    /// </summary>
    public static ProjectConfig CreateDefault(string? projectName = null)
    {
        return new ProjectConfig
        {
            Name = projectName,
            Backend = CompilationBackend.Il.ToConfigValue(),
            OutputType = "exe",
            TargetFramework = "net10.0",
            Language = new LanguageConfig()
        };
    }


    /// <summary>
    /// Validate project configuration
    /// </summary>
    private static void ValidateConfig(ProjectConfig config, string projectDirectory)
    {
        _ = config.EffectiveBackend;

        // Validate outputType
        if (config.OutputType != "exe" && config.OutputType != "library")
        {
            throw new InvalidOperationException(
                $"Invalid outputType: '{config.OutputType}'. Must be 'exe' or 'library'.");
        }

        // Validate testFramework
        if (config.TestFramework != "xunit" && config.TestFramework != "nunit")
        {
            throw new InvalidOperationException(
                $"Invalid testFramework: '{config.TestFramework}'. Must be 'xunit' or 'nunit'.");
        }

        // Validate asyncDefaultType
        if (config.Language.AsyncDefaultType != "Task" && config.Language.AsyncDefaultType != "ValueTask")
        {
            throw new InvalidOperationException(
                $"Invalid language.asyncDefaultType: '{config.Language.AsyncDefaultType}'. Must be 'Task' or 'ValueTask'.");
        }

        if (config.Language.Profile != "default" && config.Language.Profile != "systems")
        {
            throw new InvalidOperationException(
                $"Invalid language.profile: '{config.Language.Profile}'. Must be 'default' or 'systems'.");
        }

        if (config.Language.Systems.Mode != "audit" && config.Language.Systems.Mode != "strict")
        {
            throw new InvalidOperationException(
                $"Invalid language.systems.mode: '{config.Language.Systems.Mode}'. Must be 'audit' or 'strict'.");
        }

        if (config.Language.Systems.UnknownExternalCalls is not ("allow" or "warn" or "error"))
        {
            throw new InvalidOperationException(
                $"Invalid language.systems.unknownExternalCalls: '{config.Language.Systems.UnknownExternalCalls}'. Must be 'allow', 'warn', or 'error'.");
        }

        if (config.Language.Systems.AotTarget is not ("nativeaot" or "coreclr" or "mono-wasm"))
        {
            throw new InvalidOperationException(
                $"Invalid language.systems.aotTarget: '{config.Language.Systems.AotTarget}'. Must be 'nativeaot', 'coreclr', or 'mono-wasm'.");
        }

        if (config.Language.Systems.StackBudgetBytes <= 0)
        {
            throw new InvalidOperationException(
                $"Invalid language.systems.stackBudgetBytes: '{config.Language.Systems.StackBudgetBytes}'. Must be greater than zero.");
        }

        // Validate entry file exists (if specified and outputType is exe)
        if (!string.IsNullOrEmpty(config.Entry))
        {
            var entryPath = Path.Combine(projectDirectory, config.Entry);
            if (!File.Exists(entryPath))
            {
                throw new FileNotFoundException(
                    $"Entry file not found: {config.Entry} (resolved to {entryPath})");
            }
        }
        // Validate targetFramework format (basic check)
        if (!config.TargetFramework.StartsWith("net"))
        {
            Console.Error.WriteLine($"Warning: Target framework '{config.TargetFramework}' may not be valid. Expected format: netX.Y");
        }

        // Validate dependencies (skip file validation for NuGet and Framework references)
        config.Dependencies = config.Dependencies
            .Where(reference => reference != null && reference.HasValue)
            .ToList();

        config.TestDependencies = config.TestDependencies
            .Where(reference => reference != null && reference.HasValue)
            .ToList();

        foreach (var reference in config.Dependencies)
        {
            try
            {
                // Only validate Dll and Project references (which check file existence)
                if (reference.Type == ReferenceType.Dll || reference.Type == ReferenceType.Project)
                {
                    reference.Validate(projectDirectory);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Warning: Dependency validation failed: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Generate a template project.yml file content
    /// </summary>
    public static string GenerateTemplate(string projectName)
    {
return $@"name: {projectName}
version: 1.0.0
entry: Program.nl
backend: il
outputType: exe
targetFramework: net10.0

# Test framework: xunit (default) or nunit
# testFramework: xunit

# Add your dependencies here
# dependencies:
#   - nuget: Newtonsoft.Json
#     version: 13.0.3

language:
  profile: default
  asyncDefaultType: ValueTask

# package:
#   author: Your Name
#   description: A short description
#   license: MIT
";
    }
}

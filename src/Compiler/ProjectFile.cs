using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using YamlDotNet.Core;
using YamlDotNet.Core.Events;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace NewCLILang.Compiler;

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
    /// Output type: "exe" or "library"
    /// </summary>
    public string OutputType { get; set; } = "exe";

    /// <summary>
    /// Target framework (e.g., "net8.0", "net9.0")
    /// </summary>
    public string TargetFramework { get; set; } = "net9.0";

    /// <summary>
    /// SDK type: "Microsoft.NET.Sdk" or "Microsoft.NET.Sdk.Web"
    /// </summary>
    public string Sdk { get; set; } = "Microsoft.NET.Sdk";

    /// <summary>
    /// References (NuGet packages, DLLs, projects, frameworks)
    /// </summary>
    public List<Reference> References { get; set; } = new();

    /// <summary>
    /// DEPRECATED: Use References instead with nuget type
    /// NuGet package dependencies (package name -> version)
    /// Kept for backwards compatibility
    /// </summary>
    [Obsolete("Use References instead with nuget type")]
    public Dictionary<string, string> Dependencies { get; set; } = new();

    /// <summary>
    /// Test-specific NuGet package dependencies (package name -> version)
    /// These are only included when running tests, not in the main project build
    /// </summary>
    public Dictionary<string, string> TestDependencies { get; set; } = new();

    /// <summary>
    /// DEPRECATED: Use References instead with appropriate types
    /// Assembly references (for external type resolution)
    /// Kept for backwards compatibility
    /// </summary>
    [Obsolete("Use References instead with appropriate types")]
    public List<string> LegacyReferences { get; set; } = new();

    /// <summary>
    /// DEPRECATED: Use References instead with project type
    /// Project references (for test projects referencing other projects)
    /// Kept for backwards compatibility
    /// </summary>
    [Obsolete("Use References instead with project type")]
    public List<string> ProjectReferences { get; set; } = new();

    /// <summary>
    /// Files to exclude from compilation
    /// Supports glob patterns (e.g., "*.tests.nl", "temp/**/*.nl")
    /// By default, all .nl files are included except those matching exclude patterns
    /// </summary>
    public List<string> Exclude { get; set; } = new();

    /// <summary>
    /// Language-specific configuration
    /// </summary>
    public LanguageConfig Language { get; set; } = new();

    /// <summary>
    /// Gets the effective project name (uses Name or defaults to directory name)
    /// </summary>
    [YamlIgnore]
    public string EffectiveName => Name ?? Path.GetFileName(Environment.CurrentDirectory) ?? "Project";

    /// <summary>
    /// Gets all .nl files in the project directory, excluding test files and files matching exclude patterns
    /// </summary>
    /// <param name="projectRoot">Root directory of the project</param>
    /// <param name="includeTests">Whether to include .tests.nl files (default: false)</param>
    /// <returns>Array of file paths</returns>
    public string[] GetSourceFiles(string projectRoot, bool includeTests = false)
    {
        // Get all .nl files recursively
        var allFiles = Directory.GetFiles(projectRoot, "*.nl", SearchOption.AllDirectories);

        // Filter out test files if not including them
        var files = includeTests
            ? allFiles
            : allFiles.Where(f => !f.EndsWith(".tests.nl")).ToArray();

        // Apply exclude patterns
        if (Exclude.Count > 0)
        {
            files = files.Where(file =>
            {
                var relativePath = Path.GetRelativePath(projectRoot, file);
                return !Exclude.Any(pattern => MatchesPattern(relativePath, pattern));
            }).ToArray();
        }

        return files;
    }

    /// <summary>
    /// Simple glob pattern matching (supports * and **)
    /// </summary>
    private static bool MatchesPattern(string path, string pattern)
    {
        // Normalize path separators
        path = path.Replace('\\', '/');
        pattern = pattern.Replace('\\', '/');

        // Convert glob pattern to regex
        var regexPattern = "^" + System.Text.RegularExpressions.Regex.Escape(pattern)
            .Replace("\\*\\*/", ".*?/")  // **/ matches any number of directories
            .Replace("\\*\\*", ".*")      // ** matches anything
            .Replace("\\*", "[^/]*")      // * matches anything except /
            .Replace("\\?", ".")          // ? matches single character
            + "$";

        return System.Text.RegularExpressions.Regex.IsMatch(path, regexPattern);
    }
}

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
/// Language-specific configuration options
/// </summary>
public class LanguageConfig
{
    /// <summary>
    /// Default async return type wrapper: "Task" or "ValueTask"
    /// </summary>
    public string AsyncDefaultType { get; set; } = "ValueTask";
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
                    emitter.Emit(new Scalar(reference.Nuget));
                    break;
                case ReferenceType.Dll:
                    emitter.Emit(new Scalar("dll"));
                    emitter.Emit(new Scalar(reference.Dll));
                    break;
                case ReferenceType.Project:
                    emitter.Emit(new Scalar("project"));
                    emitter.Emit(new Scalar(reference.Project));
                    break;
                case ReferenceType.Framework:
                    emitter.Emit(new Scalar("framework"));
                    emitter.Emit(new Scalar(reference.Framework));
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

        // Migrate legacy fields
        MigrateLegacyFields(config);

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
            OutputType = "exe",
            TargetFramework = "net9.0",
            Language = new LanguageConfig()
        };
    }

    /// <summary>
    /// Migrate legacy fields to new References system for backwards compatibility
    /// </summary>
    private static void MigrateLegacyFields(ProjectConfig config)
    {
        var migrated = false;

        // Migrate old Dependencies field
        #pragma warning disable CS0618 // Type or member is obsolete
        if (config.Dependencies.Count > 0)
        {
            Console.WriteLine("Warning: 'dependencies' field is deprecated. Use 'references' instead.");

            foreach (var (package, version) in config.Dependencies)
            {
                config.References.Add(new Reference
                {
                    Nuget = package,
                    Version = version
                });
            }

            config.Dependencies.Clear();
            migrated = true;
        }

        // Migrate old LegacyReferences field (assembly names)
        if (config.LegacyReferences.Count > 0)
        {
            Console.WriteLine("Warning: String-based 'references' field is deprecated. Use structured references instead.");

            foreach (var reference in config.LegacyReferences)
            {
                // Try to determine if it's a NuGet package or assembly name
                // If it looks like a file path, treat as DLL, otherwise as NuGet
                if (reference.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) ||
                    reference.Contains('/') || reference.Contains('\\'))
                {
                    config.References.Add(new Reference { Dll = reference });
                }
                else
                {
                    config.References.Add(new Reference { Nuget = reference });
                }
            }

            config.LegacyReferences.Clear();
            migrated = true;
        }

        // Migrate old ProjectReferences field
        if (config.ProjectReferences.Count > 0)
        {
            Console.WriteLine("Warning: 'projectReferences' field is deprecated. Use 'references' with 'project' type instead.");

            foreach (var projectRef in config.ProjectReferences)
            {
                config.References.Add(new Reference { Project = projectRef });
            }

            config.ProjectReferences.Clear();
            migrated = true;
        }
        #pragma warning restore CS0618 // Type or member is obsolete

        if (migrated)
        {
            Console.WriteLine("Legacy fields have been automatically migrated to the new 'references' format.");
        }
    }

    /// <summary>
    /// Validate project configuration
    /// </summary>
    private static void ValidateConfig(ProjectConfig config, string projectDirectory)
    {
        // Validate outputType
        if (config.OutputType != "exe" && config.OutputType != "library")
        {
            throw new InvalidOperationException(
                $"Invalid outputType: '{config.OutputType}'. Must be 'exe' or 'library'.");
        }

        // Validate asyncDefaultType
        if (config.Language.AsyncDefaultType != "Task" && config.Language.AsyncDefaultType != "ValueTask")
        {
            throw new InvalidOperationException(
                $"Invalid language.asyncDefaultType: '{config.Language.AsyncDefaultType}'. Must be 'Task' or 'ValueTask'.");
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
        else if (config.OutputType == "exe")
        {
            // Warn if exe but no entry specified (will look for Program.nl or Main())
            Console.WriteLine("Warning: No entry file specified in project.yml. Will look for Program.nl or Main() method.");
        }

        // Validate targetFramework format (basic check)
        if (!config.TargetFramework.StartsWith("net"))
        {
            Console.WriteLine($"Warning: Target framework '{config.TargetFramework}' may not be valid. Expected format: netX.Y");
        }

        // Validate references (skip file validation for NuGet and Framework references)
        foreach (var reference in config.References)
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
                Console.WriteLine($"Warning: Reference validation failed: {ex.Message}");
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
outputType: exe
targetFramework: net9.0

# References - all external dependencies go here
references:
  # NuGet packages (with version)
  # - nuget: Microsoft.EntityFrameworkCore
  #   version: 9.0.0

  # NuGet packages (shorthand with version)
  # - nuget: Newtonsoft.Json@13.0.3

  # NuGet packages (latest version)
  # - nuget: Dapper

  # Local DLL files
  # - dll: libs/MyCustomLibrary.dll
  # - dll: ../shared/Utils.dll

  # Local project references (.csproj or project.yml)
  # - project: ../SharedModels/SharedModels.csproj
  # - project: ../CoreLibrary/project.yml

  # Framework references
  # - framework: Microsoft.AspNetCore.App

language:
  asyncDefaultType: ValueTask
";
    }
}

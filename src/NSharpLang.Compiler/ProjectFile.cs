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
            OutputType = "exe",
            TargetFramework = "net9.0",
            Language = new LanguageConfig()
        };
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
outputType: exe
targetFramework: net9.0

# Test framework: xunit (default) or nunit
# testFramework: xunit

# Add your dependencies here
# dependencies:
#   - nuget: Newtonsoft.Json
#     version: 13.0.3

language:
  asyncDefaultType: ValueTask

# package:
#   author: Your Name
#   description: A short description
#   license: MIT
";
    }
}

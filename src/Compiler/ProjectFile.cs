using System;
using System.Collections.Generic;
using System.IO;
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
    /// NuGet package dependencies (package name -> version)
    /// </summary>
    public Dictionary<string, string> Dependencies { get; set; } = new();

    /// <summary>
    /// Assembly references (for external type resolution)
    /// Can be assembly names (e.g., "Microsoft.AspNetCore") or file paths
    /// </summary>
    public List<string> References { get; set; } = new();

    /// <summary>
    /// Language-specific configuration
    /// </summary>
    public LanguageConfig Language { get; set; } = new();

    /// <summary>
    /// Gets the effective project name (uses Name or defaults to directory name)
    /// </summary>
    [YamlIgnore]
    public string EffectiveName => Name ?? Path.GetFileName(Environment.CurrentDirectory) ?? "Project";
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

# Add NuGet package dependencies here:
# dependencies:
#   Newtonsoft.Json: 13.0.3

# Add assembly references for type resolution:
# references:
#   - Microsoft.AspNetCore
#   - Microsoft.EntityFrameworkCore

language:
  asyncDefaultType: ValueTask
";
    }
}

using System;
using System.IO;
using System.Linq;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace NSharpLang.Compiler;

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
            Backend = "il",
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
            // Only validate Dll and Project references (which check file existence)
            if (reference.Type == ReferenceType.Dll || reference.Type == ReferenceType.Project)
            {
                reference.Validate(projectDirectory);
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

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Text
import YamlDotNet.Serialization
import YamlDotNet.Serialization.NamingConventions

public class ProjectFileParser {
    public static func Parse(yamlPath: string): ProjectConfig {
        if !File.Exists(yamlPath) {
            throw new FileNotFoundException("Project file not found: " + yamlPath)
        }

        yaml := File.ReadAllText(yamlPath)
        deserializer := new DeserializerBuilder()
            .WithNamingConvention(CamelCaseNamingConvention.Instance)
            .WithTypeConverter((IYamlTypeConverter)new ReferenceConverter())
            .IgnoreUnmatchedProperties()
            .Build()

        configObject := deserializer.Deserialize(yaml, typeof(ProjectConfig))
        config := (ProjectConfig)configObject
        ValidateConfig(config, Path.GetDirectoryName(yamlPath) ?? Environment.CurrentDirectory)
        return config
    }

    public static func ParseFromDirectory(directory: string): ProjectConfig? {
        projectPath := Path.Combine(directory, "project.yml")
        if !File.Exists(projectPath) {
            return null
        }

        return Parse(projectPath)
    }

    public static func CreateDefault(projectName: string? = null): ProjectConfig {
        config := new ProjectConfig()
        config.Name = projectName
        config.Backend = "il"
        config.OutputType = "exe"
        config.TargetFramework = "net10.0"
        config.Language = new LanguageConfig()
        return config
    }

    static func ValidateConfig(config: ProjectConfig, projectDirectory: string) {
        if config.OutputType != "exe" && config.OutputType != "library" {
            throw new InvalidOperationException("Invalid outputType: '" + config.OutputType + "'. Must be 'exe' or 'library'.")
        }

        if config.TestFramework != "xunit" && config.TestFramework != "nunit" {
            throw new InvalidOperationException("Invalid testFramework: '" + config.TestFramework + "'. Must be 'xunit' or 'nunit'.")
        }

        if config.Language.AsyncDefaultType != "Task" && config.Language.AsyncDefaultType != "ValueTask" {
            throw new InvalidOperationException("Invalid language.asyncDefaultType: '" + config.Language.AsyncDefaultType + "'. Must be 'Task' or 'ValueTask'.")
        }

        if config.Language.Profile != "default" && config.Language.Profile != "systems" {
            throw new InvalidOperationException("Invalid language.profile: '" + config.Language.Profile + "'. Must be 'default' or 'systems'.")
        }

        if config.Language.Systems.Mode != "audit" && config.Language.Systems.Mode != "strict" {
            throw new InvalidOperationException("Invalid language.systems.mode: '" + config.Language.Systems.Mode + "'. Must be 'audit' or 'strict'.")
        }

        unknownExternalCalls := config.Language.Systems.UnknownExternalCalls
        if unknownExternalCalls != "allow" && unknownExternalCalls != "warn" && unknownExternalCalls != "error" {
            throw new InvalidOperationException("Invalid language.systems.unknownExternalCalls: '" + unknownExternalCalls + "'. Must be 'allow', 'warn', or 'error'.")
        }

        aotTarget := config.Language.Systems.AotTarget
        if aotTarget != "nativeaot" && aotTarget != "coreclr" && aotTarget != "mono-wasm" {
            throw new InvalidOperationException("Invalid language.systems.aotTarget: '" + aotTarget + "'. Must be 'nativeaot', 'coreclr', or 'mono-wasm'.")
        }

        if config.Language.Systems.StackBudgetBytes <= 0 {
            throw new InvalidOperationException("Invalid language.systems.stackBudgetBytes: '" + config.Language.Systems.StackBudgetBytes.ToString() + "'. Must be greater than zero.")
        }

        if !string.IsNullOrEmpty(config.Entry ?? "") {
            entryValue := config.Entry ?? ""
            entryPath := Path.Combine(projectDirectory, entryValue)
            if !File.Exists(entryPath) {
                throw new FileNotFoundException("Entry file not found: " + entryValue + " (resolved to " + entryPath + ")")
            }
        }

        if !config.TargetFramework.StartsWith("net") {
            Console.Error.WriteLine("Warning: Target framework '" + config.TargetFramework + "' may not be valid. Expected format: netX.Y")
        }

        config.Dependencies = FilterReferences(config.Dependencies)
        config.TestDependencies = FilterReferences(config.TestDependencies)

        i := 0
        while i < config.Dependencies.Count {
            reference := config.Dependencies[i]
            referenceType := reference.Type
            if referenceType == ReferenceType.Dll || referenceType == ReferenceType.Project {
                reference.Validate(projectDirectory)
            }

            i = i + 1
        }
    }

    static func FilterReferences(references: List<Reference>): List<Reference> {
        filtered := new List<Reference>()
        i := 0
        while i < references.Count {
            reference := references[i]
            if reference != null {
                if reference.HasValue {
                    filtered.Add(reference)
                }
            }

            i = i + 1
        }

        return filtered
    }

    public static func GenerateTemplate(projectName: string): string {
        builder := new StringBuilder()
        builder.Append("name: ")
        builder.Append(projectName)
        builder.AppendLine()
        builder.AppendLine("version: 1.0.0")
        builder.AppendLine("entry: Program.nl")
        builder.AppendLine("backend: il")
        builder.AppendLine("outputType: exe")
        builder.AppendLine("targetFramework: net10.0")
        builder.AppendLine()
        builder.AppendLine("# Test framework: xunit (default) or nunit")
        builder.AppendLine("# testFramework: xunit")
        builder.AppendLine()
        builder.AppendLine("# Add your dependencies here")
        builder.AppendLine("# dependencies:")
        builder.AppendLine("#   - nuget: Newtonsoft.Json")
        builder.AppendLine("#     version: 13.0.3")
        builder.AppendLine()
        builder.AppendLine("language:")
        builder.AppendLine("  profile: default")
        builder.AppendLine("  asyncDefaultType: ValueTask")
        builder.AppendLine()
        builder.AppendLine("# package:")
        builder.AppendLine("#   author: Your Name")
        builder.AppendLine("#   description: A short description")
        builder.AppendLine("#   license: MIT")
        return builder.ToString()
    }
}

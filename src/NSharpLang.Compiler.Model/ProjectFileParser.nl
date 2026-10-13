namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Text
import YamlDotNet.Core
import YamlDotNet.RepresentationModel

class ProjectFileParser {
    static func Parse(yamlPath: string): ProjectConfig {
        if !File.Exists(yamlPath) {
            throw new FileNotFoundException("Project file not found: " + yamlPath)
        }

        yaml := File.ReadAllText(yamlPath)
        config := ProjectConfigYamlMapping.Read(yaml)
        ValidateConfig(config, Path.GetDirectoryName(yamlPath) ?? Environment.CurrentDirectory)
        return config
    }

    static func ParseFromDirectory(directory: string): ProjectConfig? {
        projectPath := Path.Combine(directory, "project.yml")
        if !File.Exists(projectPath) {
            return null
        }

        return Parse(projectPath)
    }

    static func ParseFromDirectoryOrDefault(directory: string): ProjectConfig {
        config := ParseFromDirectory(directory)
        if config != null {
            return config
        }

        projectName := Path.GetFileName(Path.GetFullPath(directory))
        return CreateDefault(projectName)
    }

    static func CreateDefault(projectName: string? = null): ProjectConfig {
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

        if config.Backend != "il" {
            throw new InvalidOperationException("Invalid backend: '" + config.Backend + "'. Must be 'il'.")
        }

        if config.TestFramework != "xunit" && config.TestFramework != "nunit" {
            throw new InvalidOperationException("Invalid testFramework: '" + config.TestFramework + "'. Must be 'xunit' or 'nunit'.")
        }

        if config.DebugType != "none" && config.DebugType != "portable" && config.DebugType != "embedded" && config.DebugType != "full" && config.DebugType != "pdbonly" {
            throw new InvalidOperationException("Invalid debugType: '" + config.DebugType + "'. Must be 'none', 'portable', 'embedded', 'full', or 'pdbonly'.")
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

        // A FRIEND DECLARATION THAT NAMES NOTHING IS A CONFIGURATION MISTAKE, not a silent no-op.
        // An entry with no simple name in front of its comma would emit a metadata row no reader
        // can ever match, so the project file is refused with the entry's own spelling quoted.
        for declaredGrant in config.InternalsVisibleTo {
            if !InternalsVisibleToGrants.IsUsableDeclaredName(declaredGrant) {
                throw new InvalidOperationException("Invalid internalsVisibleTo entry: '" + (declaredGrant ?? "") + "'. Each entry must be an assembly name.")
            }
        }

        config.Dependencies = FilterReferences(config.Dependencies)
        config.TestDependencies = FilterReferences(config.TestDependencies)

        for reference in config.Dependencies {
            referenceType := reference.Type
            if referenceType == ReferenceType.Dll || referenceType == ReferenceType.Project {
                reference.Validate(projectDirectory)
            }
        }
    }

    static func FilterReferences(references: List<Reference>): List<Reference> {
        filtered := new List<Reference>()
        for reference in references {
            if reference != null {
                if reference.HasValue {
                    filtered.Add(reference)
                }
            }
        }

        return filtered
    }

    static func GenerateTemplate(projectName: string): string {
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

// `YamlDotNet`'s high-level DeserializerBuilder discovers object members and constructs values by
// reflection. That path requires runtime code generation and fails in a NativeAOT host. Keep
// YamlDotNet as the YAML grammar/parser owner, then map the known project.yml schema into its N#
// model with ordinary typed code. Unknown keys retain the existing refusal behavior.
static class ProjectConfigYamlMapping {
    static func Read(yaml: string): ProjectConfig {
        stream := new YamlStream()
        stream.Load(new StringReader(yaml))
        if stream.Documents.Count != 1 {
            throw new YamlException("Project file must contain exactly one YAML document.")
        }

        root := stream.Documents[0].RootNode as YamlMappingNode
        if root == null {
            throw new YamlException("Project file root must be a mapping.")
        }

        EnsureKnownProperties(root, "ProjectConfig", ["name", "version", "entry", "backend", "outputType", "targetFramework", "excludeTests", "debugType", "sdk", "dependencies", "testDependencies", "exclude", "testFramework", "defines", "internalsVisibleTo", "language", "package"])
        config := new ProjectConfig()

        value := Scalar(root, "name", "ProjectConfig")
        if value != null {
            config.Name = value
        }
        value = Scalar(root, "version", "ProjectConfig")
        if value != null {
            config.Version = value
        }
        value = Scalar(root, "entry", "ProjectConfig")
        if value != null {
            config.Entry = value
        }
        value = Scalar(root, "backend", "ProjectConfig")
        if value != null {
            config.Backend = value
        }
        value = Scalar(root, "outputType", "ProjectConfig")
        if value != null {
            config.OutputType = value
        }
        value = Scalar(root, "targetFramework", "ProjectConfig")
        if value != null {
            config.TargetFramework = value
        }
        value = Scalar(root, "debugType", "ProjectConfig")
        if value != null {
            config.DebugType = value
        }
        value = Scalar(root, "sdk", "ProjectConfig")
        if value != null {
            config.Sdk = value
        }
        value = Scalar(root, "testFramework", "ProjectConfig")
        if value != null {
            config.TestFramework = value
        }

        if HasNode(root, "excludeTests") {
            config.ExcludeTests = Convert.ToBoolean(Scalar(root, "excludeTests", "ProjectConfig") ?? "false")
        }

        values := StringList(root, "exclude", "ProjectConfig")
        if values != null {
            config.Exclude = values
        }
        values = StringList(root, "defines", "ProjectConfig")
        if values != null {
            config.Defines = values
        }
        values = StringList(root, "internalsVisibleTo", "ProjectConfig")
        if values != null {
            config.InternalsVisibleTo = values
        }

        references := ReferenceList(root, "dependencies", "ProjectConfig")
        if references != null {
            config.Dependencies = references
        }
        references = ReferenceList(root, "testDependencies", "ProjectConfig")
        if references != null {
            config.TestDependencies = references
        }

        languageMap := Mapping(root, "language", "ProjectConfig")
        if languageMap != null {
            EnsureKnownProperties(languageMap, "LanguageConfig", ["profile", "asyncDefaultType", "pooledAsync", "systems"])
            language := config.Language
            value = Scalar(languageMap, "profile", "LanguageConfig")
            if value != null {
                language.Profile = value
            }
            value = Scalar(languageMap, "asyncDefaultType", "LanguageConfig")
            if value != null {
                language.AsyncDefaultType = value
            }
            if HasNode(languageMap, "pooledAsync") {
                language.PooledAsync = Convert.ToBoolean(Scalar(languageMap, "pooledAsync", "LanguageConfig") ?? "false")
            }

            systemsMap := Mapping(languageMap, "systems", "LanguageConfig")
            if systemsMap != null {
                EnsureKnownProperties(systemsMap, "SystemsConfig", ["mode", "unknownExternalCalls", "aotTarget", "warmup", "stackBudgetBytes", "hotSummaryFiles", "allowHotSidecars"])
                systems := language.Systems
                value = Scalar(systemsMap, "mode", "SystemsConfig")
                if value != null {
                    systems.Mode = value
                }
                value = Scalar(systemsMap, "unknownExternalCalls", "SystemsConfig")
                if value != null {
                    systems.UnknownExternalCalls = value
                }
                value = Scalar(systemsMap, "aotTarget", "SystemsConfig")
                if value != null {
                    systems.AotTarget = value
                }

                values = StringList(systemsMap, "warmup", "SystemsConfig")
                if values != null {
                    systems.Warmup = values
                }
                values = StringList(systemsMap, "hotSummaryFiles", "SystemsConfig")
                if values != null {
                    systems.HotSummaryFiles = values
                }
                if HasNode(systemsMap, "stackBudgetBytes") {
                    value = Scalar(systemsMap, "stackBudgetBytes", "SystemsConfig")
                    systems.StackBudgetBytes = Convert.ToInt32(value ?? "0")
                }
                if HasNode(systemsMap, "allowHotSidecars") {
                    systems.AllowHotSidecars = Convert.ToBoolean(Scalar(systemsMap, "allowHotSidecars", "SystemsConfig") ?? "false")
                }
            }
        }

        packageMap := Mapping(root, "package", "ProjectConfig")
        if packageMap != null {
            EnsureKnownProperties(packageMap, "PackageConfig", ["id", "author", "description", "tags", "license", "repository", "icon", "readme"])
            packageConfig := new PackageConfig()
            packageConfig.Id = Scalar(packageMap, "id", "PackageConfig")
            packageConfig.Author = Scalar(packageMap, "author", "PackageConfig")
            packageConfig.Description = Scalar(packageMap, "description", "PackageConfig")
            packageConfig.Tags = StringList(packageMap, "tags", "PackageConfig")
            packageConfig.License = Scalar(packageMap, "license", "PackageConfig")
            packageConfig.Repository = Scalar(packageMap, "repository", "PackageConfig")
            packageConfig.Icon = Scalar(packageMap, "icon", "PackageConfig")
            packageConfig.Readme = Scalar(packageMap, "readme", "PackageConfig")
            config.Package = packageConfig
        }

        return config
    }

    static func HasNode(mapping: YamlMappingNode, key: string): bool {
        return FindNode(mapping, key) != null
    }

    static func FindNode(mapping: YamlMappingNode, key: string): YamlNode? {
        for entry in mapping.Children {
            keyNode := entry.Key as YamlScalarNode
            if keyNode != null && keyNode.Value == key {
                return entry.Value
            }
        }

        return null
    }

    static func Scalar(mapping: YamlMappingNode, key: string, owner: string): string? {
        node := FindNode(mapping, key)
        if node == null {
            return null
        }

        scalar := node as YamlScalarNode
        if scalar == null {
            throw new YamlException("Property '" + key + "' on type '" + owner + "' must be a scalar.")
        }

        if IsNullScalar(scalar) {
            return null
        }

        return scalar.Value
    }

    static func Mapping(mapping: YamlMappingNode, key: string, owner: string): YamlMappingNode? {
        node := FindNode(mapping, key)
        if node == null {
            return null
        }

        scalar := node as YamlScalarNode
        if scalar != null && IsNullScalar(scalar) {
            return null
        }

        nested := node as YamlMappingNode
        if nested == null {
            throw new YamlException("Property '" + key + "' on type '" + owner + "' must be a mapping.")
        }

        return nested
    }

    static func StringList(mapping: YamlMappingNode, key: string, owner: string): List<string>? {
        node := FindNode(mapping, key)
        if node == null {
            return null
        }

        scalar := node as YamlScalarNode
        if scalar != null && IsNullScalar(scalar) {
            return null
        }

        sequence := node as YamlSequenceNode
        if sequence == null {
            throw new YamlException("Property '" + key + "' on type '" + owner + "' must be a sequence.")
        }

        values := new List<string>()
        for item in sequence.Children {
            itemScalar := item as YamlScalarNode
            if itemScalar == null {
                throw new YamlException("Items in property '" + key + "' on type '" + owner + "' must be scalars.")
            }

            values.Add(itemScalar.Value ?? "")
        }

        return values
    }

    static func ReferenceList(mapping: YamlMappingNode, key: string, owner: string): List<Reference>? {
        node := FindNode(mapping, key)
        if node == null {
            return null
        }

        scalar := node as YamlScalarNode
        if scalar != null && IsNullScalar(scalar) {
            return null
        }

        sequence := node as YamlSequenceNode
        if sequence == null {
            throw new YamlException("Property '" + key + "' on type '" + owner + "' must be a sequence.")
        }

        references := new List<Reference>()
        for item in sequence.Children {
            references.Add(ReadReference(item, key))
        }

        return references
    }

    static func ReadReference(node: YamlNode, property: string): Reference {
        scalar := node as YamlScalarNode
        if scalar != null {
            value := scalar.Value ?? ""
            atIndex := value.IndexOf('@')
            if atIndex >= 0 {
                return new Reference {
                    Nuget: value.Substring(0, atIndex).Trim(),
                    Version: value.Substring(atIndex + 1).Trim()
                }
            }

            return new Reference { Nuget: value.Trim() }
        }

        mapping := node as YamlMappingNode
        if mapping == null {
            throw new YamlException("Items in property '" + property + "' must be reference scalars or mappings.")
        }

        reference := new Reference()
        for entry in mapping.Children {
            keyNode := entry.Key as YamlScalarNode
            valueNode := entry.Value as YamlScalarNode
            if keyNode == null || valueNode == null || IsNullScalar(valueNode) {
                continue
            }

            ApplyReferenceValue(reference, (keyNode.Value ?? "").ToLowerInvariant(), valueNode.Value ?? "")
        }

        return reference
    }

    static func ApplyReferenceValue(reference: Reference, key: string, value: string): void {
        if key == "nuget" {
            atIndex := value.IndexOf('@')
            if atIndex >= 0 {
                reference.Nuget = value.Substring(0, atIndex).Trim()
                reference.Version = value.Substring(atIndex + 1).Trim()
            } else {
                reference.Nuget = value
            }
            return
        }

        if key == "version" {
            reference.Version = value
            return
        }
        if key == "dll" {
            reference.Dll = value
            return
        }
        if key == "project" {
            reference.Project = value
            return
        }
        if key == "framework" {
            reference.Framework = value
        }
    }

    static func IsNullScalar(scalar: YamlScalarNode): bool {
        if scalar.Value == null {
            return true
        }
        if scalar.Style.ToString() != "Plain" {
            return false
        }

        value := scalar.Value.Trim()
        return value.Length == 0 || value == "~" || string.Equals(value, "null", StringComparison.OrdinalIgnoreCase)
    }

    static func EnsureKnownProperties(mapping: YamlMappingNode, owner: string, known: string[]): void {
        for entry in mapping.Children {
            keyNode := entry.Key as YamlScalarNode
            if keyNode == null {
                continue
            }

            key := keyNode.Value ?? ""
            found := false
            for knownName in known {
                if key == knownName {
                    found = true
                    break
                }
            }

            if !found {
                throw new YamlException("Property '" + key + "' not found on type '" + owner + "'.")
            }
        }
    }
}

namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json
import NSharpLang.Cli
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

class TreeReport {
    SchemaVersion: int
    Command: string
    Ok: bool
    ProjectRoot: string
    Project: TreeProject
    MaxDepth: int
    Capabilities: TreeCapabilities
    Dependencies: TreeDependency[]
    TransitiveDependencies: TreeDependency[]
    Summary: TreeSummary
    Limitations: string[]

    constructor(schemaVersion: int, command: string, ok: bool, projectRoot: string, project: TreeProject, maxDepth: int, capabilities: TreeCapabilities, dependencies: TreeDependency[], transitiveDependencies: TreeDependency[], summary: TreeSummary, limitations: string[]) {
        SchemaVersion = schemaVersion
        Command = command
        Ok = ok
        ProjectRoot = projectRoot
        Project = project
        MaxDepth = maxDepth
        Capabilities = capabilities
        Dependencies = dependencies
        TransitiveDependencies = transitiveDependencies
        Summary = summary
        Limitations = limitations
    }
}

class TreeProject {
    Name: string
    TargetFramework: string
    Source: string

    constructor(name: string, targetFramework: string, source: string) {
        Name = name
        TargetFramework = targetFramework
        Source = source
    }
}

class TreeCapabilities {
    DirectDependencies: bool
    TransitiveNuGetDependencies: bool

    constructor(directDependencies: bool, transitiveNuGetDependencies: bool) {
        DirectDependencies = directDependencies
        TransitiveNuGetDependencies = transitiveNuGetDependencies
    }
}

class TreeSummary {
    Direct: int
    Transitive: int
    Total: int

    constructor(direct: int, transitive: int, total: int) {
        Direct = direct
        Transitive = transitive
        Total = total
    }
}

class TreeCommand {
    static func Execute(args: string[]): int {
        options := TreeCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print TreeCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := Path.GetFullPath(options.ProjectOption ?? Environment.CurrentDirectory)
        outputMode := TreeCommandKernels.GetOutputMode(options.Json)
        maxDepth := TreeCommandKernels.GetMaxDepth(args, 2147483647)

        if !Directory.Exists(projectRoot) {
            return Error(TreeCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot), outputMode, projectRoot)
        }

        try {
            report := BuildReport(projectRoot, maxDepth)

            if outputMode == 1 {
                print BuildJsonReport(report)
            } else {
                RenderTree(report)
            }

            return 0
        } catch ex: Exception {
            return Error(TreeCommandKernels.GetTreeFailedMessage(ex.Message), outputMode, projectRoot)
        }
    }

    static func BuildReport(projectRoot: string, maxDepth: int): TreeReport {
        root := Path.GetFullPath(projectRoot)
        projectYml := Path.Combine(root, "project.yml")
        csproj := SelectFirstCsproj(root)

        if csproj != null {
            if File.Exists(projectYml) {
                RestoreCommand.Restore(root, true)
            }

            projectYmlPath: string? = null
            if File.Exists(projectYml) {
                projectYmlPath = projectYml
            }

            return BuildFromMsbuild(root, csproj ?? "", projectYmlPath, maxDepth)
        }

        if File.Exists(projectYml) {
            return BuildFromProjectYml(root, projectYml, maxDepth, null)
        }

        throw new InvalidOperationException(TreeCommandKernels.GetNoProjectFileMessage())
    }

    static func BuildFromProjectYml(projectRoot: string, projectYml: string, maxDepth: int, extraLimitation: string?): TreeReport {
        config := ProjectFileParser.Parse(projectYml)
        projectName := config.Name ?? Path.GetFileName(projectRoot) ?? "Project"
        allDirect := TreeCommandKernels.DeduplicateDependencies(ProjectYmlDependenciesToArray(config.Dependencies))

        direct := EmptyDependencyArray()
        if maxDepth >= 1 {
            direct = allDirect
        }

        limitationList := new List<string>()
        limitationList.Add(TreeCommandKernels.GetProjectYmlLimitationMessage())
        if !string.IsNullOrWhiteSpace(extraLimitation) {
            limitationList.Add(extraLimitation ?? "")
        }

        return new TreeReport(2, "tree", true, NormalizePath(projectRoot), new TreeProject(projectName, config.TargetFramework, "project.yml"), maxDepth, new TreeCapabilities(true, false), direct, EmptyDependencyArray(), new TreeSummary(direct.Length, 0, direct.Length), limitationList.ToArray())
    }

    static func BuildFromMsbuild(projectRoot: string, csproj: string, projectYml: string?, maxDepth: int): TreeReport {
        hasConfig := false
        config := new ProjectConfig()
        if projectYml != null {
            config = ProjectFileParser.Parse(projectYml ?? "")
            hasConfig = true
        }

        result := DotnetRunner.Run("list \"" + csproj + "\" package --include-transitive --format json", projectRoot, true, null)

        if result.ExitCode != 0 {
            detail := GetDotnetListFailureDetail(result)
            if hasConfig && projectYml != null {
                return BuildFromProjectYml(projectRoot, projectYml ?? "", maxDepth, TreeCommandKernels.GetTransitiveResolutionFailedLimitation(detail))
            }

            throw new InvalidOperationException(TreeCommandKernels.GetDotnetRestoreRetryMessage(detail))
        }

        document := JsonDocument.Parse(result.Stdout)
        projectName := FileNameWithoutExtension(csproj)
        direct := new List<TreeDependency>()
        if hasConfig {
            AddProjectYmlDependencies(config.Dependencies, direct)
            if config.Name != null {
                projectName = config.Name ?? projectName
            }
        }

        transitive := new List<TreeDependency>()
        targetFrameworks := new List<string>()
        ReadMsbuildDependencyGraph(document.RootElement, direct, transitive, targetFrameworks)
        document.Dispose()

        directArray := direct.ToArray()
        transitiveArray := transitive.ToArray()

        visibleDirect := EmptyDependencyArray()
        if maxDepth >= 1 {
            visibleDirect = TreeCommandKernels.DeduplicateDependencies(directArray)
        }

        visibleTransitive := EmptyDependencyArray()
        if maxDepth >= 2 {
            visibleTransitive = TreeCommandKernels.DeduplicateDependencies(transitiveArray)
        }

        frameworkName := "unknown"
        if targetFrameworks.Count > 0 {
            frameworkName = JoinStrings(TreeCommandKernels.DeduplicateTargetFrameworks(targetFrameworks), ",")
        }

        source := "msbuild"
        if hasConfig {
            source = "project.yml+msbuild"
        }

        return new TreeReport(2, "tree", true, NormalizePath(projectRoot), new TreeProject(projectName, frameworkName, source), maxDepth, new TreeCapabilities(true, true), visibleDirect, visibleTransitive, new TreeSummary(visibleDirect.Length, visibleTransitive.Length, visibleDirect.Length + visibleTransitive.Length), new string[](0))
    }

    static func ReadMsbuildDependencyGraph(root: JsonElement, direct: List<TreeDependency>, transitive: List<TreeDependency>, targetFrameworks: List<string>) {
        projects := new JsonElement()
        if !root.TryGetProperty("projects", out projects) {
            return
        }

        if projects.ValueKind != JsonValueKind.Array {
            return
        }

        projectEnumerator := projects.EnumerateArray()
        while projectEnumerator.MoveNext() {
            project := projectEnumerator.Current
            frameworks := new JsonElement()
            if !project.TryGetProperty("frameworks", out frameworks) {
                continue
            }

            ReadFrameworks(frameworks, direct, transitive, targetFrameworks)
        }
    }

    static func ReadFrameworks(frameworks: JsonElement, direct: List<TreeDependency>, transitive: List<TreeDependency>, targetFrameworks: List<string>) {
        if frameworks.ValueKind != JsonValueKind.Array {
            return
        }

        frameworkEnumerator := frameworks.EnumerateArray()
        while frameworkEnumerator.MoveNext() {
            framework := frameworkEnumerator.Current
            targetFramework := ReadStringProperty(framework, "framework", "")
            if !string.IsNullOrWhiteSpace(targetFramework) {
                targetFrameworks.Add(targetFramework)
            }

            AddPackageSection(framework, "topLevelPackages", false, direct)
            AddPackageSection(framework, "transitivePackages", true, transitive)
        }
    }

    static func AddPackageSection(framework: JsonElement, propertyName: string, transitive: bool, output: List<TreeDependency>) {
        packages := new JsonElement()
        if !framework.TryGetProperty(propertyName, out packages) {
            return
        }

        if packages.ValueKind != JsonValueKind.Array {
            return
        }

        packageEnumerator := packages.EnumerateArray()
        while packageEnumerator.MoveNext() {
            packageElement := packageEnumerator.Current
            name := ReadStringProperty(packageElement, "id", "")
            if name.Length == 0 {
                continue
            }

            output.Add(new TreeDependency(name, "nuget", GetPackageVersion(packageElement), "runtime", transitive, EmptyDependencyArray()))
        }
    }

    static func GetPackageVersion(packageElement: JsonElement): string? {
        value := ReadNullableStringProperty(packageElement, "resolvedVersion")
        if value != null {
            return value
        }

        value = ReadNullableStringProperty(packageElement, "requestedVersion")
        if value != null {
            return value
        }

        return ReadNullableStringProperty(packageElement, "version")
    }

    static func ReadStringProperty(element: JsonElement, name: string, fallback: string): string {
        value := ReadNullableStringProperty(element, name)
        return value ?? fallback
    }

    static func ReadNullableStringProperty(element: JsonElement, name: string): string? {
        property := new JsonElement()
        if !element.TryGetProperty(name, out property) {
            return null
        }

        if property.ValueKind != JsonValueKind.String {
            return null
        }

        return property.GetString()
    }

    static func ProjectYmlDependenciesToArray(references: List<Reference>): TreeDependency[] {
        result := new List<TreeDependency>()
        AddProjectYmlDependencies(references, result)
        return result.ToArray()
    }

    static func AddProjectYmlDependencies(references: List<Reference>, result: List<TreeDependency>) {
        i := 0
        while i < references.Count {
            result.Add(ToProjectYmlDependency(references[i]))
            i = i + 1
        }
    }

    static func ToProjectYmlDependency(reference: Reference): TreeDependency {
        kind := "unknown"
        if reference.Type == ReferenceType.NuGet {
            kind = "nuget"
        } else if reference.Type == ReferenceType.Framework {
            kind = "framework"
        } else if reference.Type == ReferenceType.Project {
            kind = "project"
        } else if reference.Type == ReferenceType.Dll {
            kind = "dll"
        }

        version: string? = null
        if reference.Type == ReferenceType.NuGet {
            version = reference.Version
        }

        return new TreeDependency(NormalizePath(reference.Value), kind, version, "runtime", false, EmptyDependencyArray())
    }

    static func SelectFirstCsproj(projectRoot: string): string? {
        files := Directory.GetFiles(projectRoot, "*.csproj", SearchOption.TopDirectoryOnly)
        if files.Length == 0 {
            return null
        }

        best := files[0]
        i := 1
        while i < files.Length {
            if String.Compare(files[i], best, StringComparison.OrdinalIgnoreCase) < 0 {
                best = files[i]
            }

            i = i + 1
        }

        return best
    }

    static func GetDotnetListFailureDetail(result: DotnetRunResult): string {
        if !string.IsNullOrWhiteSpace(result.Stderr) {
            return result.Stderr.Trim()
        }

        if !string.IsNullOrWhiteSpace(result.Stdout) {
            return result.Stdout.Trim()
        }

        return TreeCommandKernels.GetDotnetListFailedMessage()
    }

    static func RenderTree(report: TreeReport) {
        print TreeCommandKernels.GetProjectHeader(report.Project.Name, report.Project.TargetFramework)

        if report.Dependencies.Length == 0 && report.TransitiveDependencies.Length == 0 {
            print TreeCommandKernels.GetNoDependenciesLine()
        }

        i := 0
        while i < report.Dependencies.Length {
            isLast := i == report.Dependencies.Length - 1
            print TreeCommandKernels.GetDependencyLine(isLast, FormatDependency(report.Dependencies[i]))
            i = i + 1
        }

        if report.TransitiveDependencies.Length > 0 {
            print ""
            print TreeCommandKernels.GetTransitiveHeader(report.TransitiveDependencies.Length)

            transitiveIndex := 0
            while transitiveIndex < report.TransitiveDependencies.Length {
                print TreeCommandKernels.GetTransitiveDependencyLine(FormatDependency(report.TransitiveDependencies[transitiveIndex]))
                transitiveIndex = transitiveIndex + 1
            }
        }

        if report.Limitations.Length > 0 {
            print ""
            print TreeCommandKernels.GetLimitationsHeader()

            limitationIndex := 0
            while limitationIndex < report.Limitations.Length {
                print TreeCommandKernels.GetLimitationLine(report.Limitations[limitationIndex])
                limitationIndex = limitationIndex + 1
            }
        }
    }

    static func FormatDependency(dependency: TreeDependency): string {
        return TreeCommandKernels.GetDependencyText(dependency.Name, dependency.Version, dependency.Kind)
    }

    static func Error(message: string, outputMode: int = 2, projectRoot: string? = null): int {
        if outputMode == 1 {
            print BuildErrorJson(message, projectRoot)
        } else {
            Console.Error.WriteLine(message)
        }

        return 1
    }

    static func BuildJsonReport(report: TreeReport): string {
        builder := new StringBuilder()
        builder.AppendLine("{")
        builder.AppendLine("  \"schemaVersion\": " + report.SchemaVersion.ToString() + ",")
        builder.AppendLine("  \"command\": \"tree\",")
        builder.AppendLine("  \"ok\": true,")
        builder.Append("  \"projectRoot\": ")
        AppendJsonString(builder, report.ProjectRoot)
        builder.AppendLine(",")
        builder.AppendLine("  \"project\": {")
        AppendJsonStringProperty(builder, "    ", "name", report.Project.Name, true)
        AppendJsonStringProperty(builder, "    ", "targetFramework", report.Project.TargetFramework, true)
        AppendJsonStringProperty(builder, "    ", "source", report.Project.Source, false)
        builder.AppendLine("  },")
        builder.AppendLine("  \"maxDepth\": " + report.MaxDepth.ToString() + ",")
        builder.AppendLine("  \"capabilities\": {")
        AppendJsonBoolProperty(builder, "    ", "directDependencies", report.Capabilities.DirectDependencies, true)
        AppendJsonBoolProperty(builder, "    ", "transitiveNuGetDependencies", report.Capabilities.TransitiveNuGetDependencies, false)
        builder.AppendLine("  },")
        AppendDependencyArrayProperty(builder, "dependencies", report.Dependencies, true)
        AppendDependencyArrayProperty(builder, "transitiveDependencies", report.TransitiveDependencies, true)
        builder.AppendLine("  \"summary\": {")
        builder.AppendLine("    \"direct\": " + report.Summary.Direct.ToString() + ",")
        builder.AppendLine("    \"transitive\": " + report.Summary.Transitive.ToString() + ",")
        builder.AppendLine("    \"total\": " + report.Summary.Total.ToString())
        builder.AppendLine("  },")
        AppendStringArrayProperty(builder, "limitations", report.Limitations, false)
        builder.AppendLine("}")
        return builder.ToString()
    }

    static func BuildErrorJson(message: string, projectRoot: string?): string {
        builder := new StringBuilder()
        builder.AppendLine("{")
        builder.AppendLine("  \"schemaVersion\": 1,")
        builder.AppendLine("  \"command\": \"tree\",")
        builder.AppendLine("  \"ok\": false,")
        builder.Append("  \"projectRoot\": ")
        AppendJsonString(builder, NormalizePath(projectRoot ?? ""))
        builder.AppendLine(",")
        builder.AppendLine("  \"error\": {")
        AppendJsonStringProperty(builder, "    ", "message", message, false)
        builder.AppendLine("  }")
        builder.AppendLine("}")
        return builder.ToString()
    }

    static func AppendDependencyArrayProperty(builder: StringBuilder, name: string, dependencies: TreeDependency[], trailingComma: bool) {
        builder.Append("  ")
        AppendJsonString(builder, name)
        builder.Append(": ")
        if dependencies.Length == 0 {
            builder.Append("[]")
            if trailingComma {
                builder.Append(",")
            }

            builder.AppendLine()
            return
        }

        builder.AppendLine("[")
        i := 0
        while i < dependencies.Length {
            AppendDependencyObject(builder, dependencies[i], "    ")
            if i + 1 < dependencies.Length {
                builder.Append(",")
            }

            builder.AppendLine()
            i = i + 1
        }

        builder.Append("  ]")
        if trailingComma {
            builder.Append(",")
        }

        builder.AppendLine()
    }

    static func AppendDependencyObject(builder: StringBuilder, dependency: TreeDependency, indent: string) {
        builder.Append(indent)
        builder.AppendLine("{")
        AppendJsonStringProperty(builder, indent + "  ", "name", dependency.Name, true)
        AppendJsonStringProperty(builder, indent + "  ", "kind", dependency.Kind, true)
        if dependency.Version != null {
            AppendJsonStringProperty(builder, indent + "  ", "version", dependency.Version ?? "", true)
        }

        AppendJsonStringProperty(builder, indent + "  ", "scope", dependency.Scope, true)
        AppendJsonBoolProperty(builder, indent + "  ", "transitive", dependency.Transitive, true)
        builder.Append(indent + "  ")
        builder.AppendLine("\"dependencies\": []")
        builder.Append(indent)
        builder.Append("}")
    }

    static func AppendStringArrayProperty(builder: StringBuilder, name: string, values: string[], trailingComma: bool) {
        builder.Append("  ")
        AppendJsonString(builder, name)
        builder.Append(": ")
        if values.Length == 0 {
            builder.Append("[]")
            if trailingComma {
                builder.Append(",")
            }

            builder.AppendLine()
            return
        }

        builder.AppendLine("[")
        i := 0
        while i < values.Length {
            builder.Append("    ")
            AppendJsonString(builder, values[i])
            if i + 1 < values.Length {
                builder.Append(",")
            }

            builder.AppendLine()
            i = i + 1
        }

        builder.Append("  ]")
        if trailingComma {
            builder.Append(",")
        }

        builder.AppendLine()
    }

    static func AppendJsonStringProperty(builder: StringBuilder, indent: string, name: string, value: string, trailingComma: bool) {
        builder.Append(indent)
        AppendJsonString(builder, name)
        builder.Append(": ")
        AppendJsonString(builder, value)
        if trailingComma {
            builder.Append(",")
        }

        builder.AppendLine()
    }

    static func AppendJsonBoolProperty(builder: StringBuilder, indent: string, name: string, value: bool, trailingComma: bool) {
        builder.Append(indent)
        AppendJsonString(builder, name)
        builder.Append(": ")
        if value {
            builder.Append("true")
        } else {
            builder.Append("false")
        }

        if trailingComma {
            builder.Append(",")
        }

        builder.AppendLine()
    }

    static func AppendJsonString(builder: StringBuilder, value: string) {
        builder.Append('"')
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '"' {
                builder.Append("\\\"")
            } else if ch == '\\' {
                builder.Append("\\\\")
            } else if ch == '\n' {
                builder.Append("\\n")
            } else if ch == '\r' {
                builder.Append("\\r")
            } else if ch == '\t' {
                builder.Append("\\t")
            } else {
                builder.Append(value.Substring(index, 1))
            }

            index = index + 1
        }

        builder.Append('"')
    }

    static func NormalizePath(path: string): string {
        normalized := OutputFormatterNormalizationKernels.NormalizePath(path)
        if normalized == null {
            return path
        }

        return normalized
    }

    static func EmptyDependencyArray(): TreeDependency[] {
        return new TreeDependency[](0)
    }

    static func JoinStrings(values: string[], separator: string): string {
        if values.Length == 0 {
            return ""
        }

        builder := new StringBuilder()
        i := 0
        while i < values.Length {
            if i > 0 {
                builder.Append(separator)
            }

            builder.Append(values[i])
            i = i + 1
        }

        return builder.ToString()
    }

    static func FileNameWithoutExtension(path: string): string {
        fileName := Path.GetFileName(path) ?? path
        dot := fileName.Length - 1
        while dot >= 0 {
            if fileName[dot] == '.' {
                return fileName.Substring(0, dot)
            }

            dot = dot - 1
        }

        return fileName
    }
}

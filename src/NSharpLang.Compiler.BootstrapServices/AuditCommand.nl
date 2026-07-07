namespace NSharpLang.Cli.Commands

import NSharpLang.Cli
import System
import System.IO
import System.Text
import System.Text.Json

public class AuditCommand {
    public static func Execute(args: string[]): int {
        options := AuditCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print AuditCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := Path.GetFullPath(options.ProjectOption ?? Environment.CurrentDirectory)
        outputMode := AuditCommandKernels.GetOutputMode(options.Json)

        if !Directory.Exists(projectRoot) {
            return Error(AuditCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot))
        }

        csprojFiles := Directory.GetFiles(projectRoot, "*.csproj", SearchOption.TopDirectoryOnly)
        if csprojFiles.Length == 0 {
            return Error(AuditCommandKernels.GetNoCsprojFileMessage())
        }

        csproj := csprojFiles[0]

        try {
            result := DotnetRunner.Run(
                "list \"" + csproj + "\" package --vulnerable --include-transitive --format json",
                projectRoot,
                true,
                null)

            if result.ExitCode != 0 {
                if result.Stderr.IndexOf("--vulnerable", StringComparison.Ordinal) >= 0 {
                    return Error(AuditCommandKernels.GetVulnerableFlagUnsupportedMessage())
                }

                failedMessage := AuditCommandKernels.GetFailedMessage(result.Stderr).Trim()
                return Error(failedMessage)
            }

            output := result.Stdout
            vulnerabilityCount := CountVulnerabilities(output)

            if outputMode == 1 {
                print BuildJsonEnvelope(projectRoot, vulnerabilityCount, output)
            } else {
                RenderAudit(output, vulnerabilityCount)
            }

            if vulnerabilityCount > 0 {
                return 1
            }

            return 0
        } catch ex: Exception {
            return Error(AuditCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func CountVulnerabilities(jsonOutput: string): int {
        count := 0
        try {
            document := JsonDocument.Parse(jsonOutput)
            projects := new JsonElement()
            if document.RootElement.TryGetProperty("projects", out projects) {
                if projects.ValueKind == JsonValueKind.Array {
                    projectEnumerator := projects.EnumerateArray()
                    while projectEnumerator.MoveNext() {
                        project := projectEnumerator.Current
                        count = count + CountProjectVulnerabilities(project)
                    }
                }
            }

            document.Dispose()
        } catch {
        }

        return count
    }

    static func CountProjectVulnerabilities(project: JsonElement): int {
        count := 0
        frameworks := new JsonElement()
        if !project.TryGetProperty("frameworks", out frameworks) {
            return 0
        }

        if frameworks.ValueKind != JsonValueKind.Array {
            return 0
        }

        frameworkEnumerator := frameworks.EnumerateArray()
        while frameworkEnumerator.MoveNext() {
            framework := frameworkEnumerator.Current
            count = count + CountPackageSectionVulnerabilities(framework, "topLevelPackages")
            count = count + CountPackageSectionVulnerabilities(framework, "transitivePackages")
        }

        return count
    }

    static func CountPackageSectionVulnerabilities(framework: JsonElement, section: string): int {
        packages := new JsonElement()
        if !framework.TryGetProperty(section, out packages) {
            return 0
        }

        if packages.ValueKind != JsonValueKind.Array {
            return 0
        }

        count := 0
        packageEnumerator := packages.EnumerateArray()
        while packageEnumerator.MoveNext() {
            packageElement := packageEnumerator.Current
            vulnerabilities := new JsonElement()
            if packageElement.TryGetProperty("vulnerabilities", out vulnerabilities) {
                if vulnerabilities.ValueKind == JsonValueKind.Array {
                    vulnerabilityEnumerator := vulnerabilities.EnumerateArray()
                    while vulnerabilityEnumerator.MoveNext() {
                        count = count + 1
                    }
                }
            }
        }

        return count
    }

    static func RenderAudit(jsonOutput: string, vulnerabilityCount: int) {
        if vulnerabilityCount == 0 {
            print AuditCommandKernels.GetNoKnownVulnerabilitiesMessage()
            return
        }

        print AuditCommandKernels.GetVulnerabilitySummaryMessage(vulnerabilityCount)
        print ""

        try {
            document := JsonDocument.Parse(jsonOutput)
            projects := new JsonElement()
            if document.RootElement.TryGetProperty("projects", out projects) {
                RenderProjects(projects)
            }

            document.Dispose()
        } catch {
            print AuditCommandKernels.GetParseFailureMessage()
        }
    }

    static func RenderProjects(projects: JsonElement) {
        if projects.ValueKind != JsonValueKind.Array {
            return
        }

        projectEnumerator := projects.EnumerateArray()
        while projectEnumerator.MoveNext() {
            project := projectEnumerator.Current
            frameworks := new JsonElement()
            if project.TryGetProperty("frameworks", out frameworks) {
                RenderFrameworks(frameworks)
            }
        }
    }

    static func RenderFrameworks(frameworks: JsonElement) {
        if frameworks.ValueKind != JsonValueKind.Array {
            return
        }

        frameworkEnumerator := frameworks.EnumerateArray()
        while frameworkEnumerator.MoveNext() {
            framework := frameworkEnumerator.Current
            RenderPackageSection(framework, "topLevelPackages")
            RenderPackageSection(framework, "transitivePackages")
        }
    }

    static func RenderPackageSection(framework: JsonElement, section: string) {
        packages := new JsonElement()
        if !framework.TryGetProperty(section, out packages) {
            return
        }

        if packages.ValueKind != JsonValueKind.Array {
            return
        }

        packageEnumerator := packages.EnumerateArray()
        while packageEnumerator.MoveNext() {
            packageElement := packageEnumerator.Current
            vulnerabilities := new JsonElement()
            if !packageElement.TryGetProperty("vulnerabilities", out vulnerabilities) {
                continue
            }

            id := ReadStringProperty(packageElement, "id", "")
            version := ReadStringProperty(packageElement, "resolvedVersion", "")
            RenderVulnerabilities(vulnerabilities, id, version)
        }
    }

    static func RenderVulnerabilities(vulnerabilities: JsonElement, packageId: string, version: string) {
        if vulnerabilities.ValueKind != JsonValueKind.Array {
            return
        }

        vulnerabilityEnumerator := vulnerabilities.EnumerateArray()
        while vulnerabilityEnumerator.MoveNext() {
            vulnerability := vulnerabilityEnumerator.Current
            severity := ReadStringProperty(vulnerability, "severity", "Unknown")
            url := ReadStringProperty(vulnerability, "advisoryurl", "")
            print AuditCommandKernels.GetVulnerabilityLine(severity, packageId, version)
            if !string.IsNullOrEmpty(url) {
                print AuditCommandKernels.GetVulnerabilityUrlLine(url)
            }
        }
    }

    static func ReadStringProperty(element: JsonElement, name: string, fallback: string): string {
        property := new JsonElement()
        if !element.TryGetProperty(name, out property) {
            return fallback
        }

        if property.ValueKind != JsonValueKind.String {
            return fallback
        }

        return property.GetString() ?? fallback
    }

    static func BuildJsonEnvelope(projectRoot: string, vulnerabilityCount: int, detailsJson: string): string {
        builder := new StringBuilder()
        builder.AppendLine("{")
        builder.AppendLine("  \"schemaVersion\": 1,")
        builder.AppendLine("  \"command\": \"audit\",")
        if vulnerabilityCount == 0 {
            builder.AppendLine("  \"ok\": true,")
        } else {
            builder.AppendLine("  \"ok\": false,")
        }

        builder.Append("  \"projectRoot\": ")
        AppendJsonString(builder, projectRoot)
        builder.AppendLine(",")
        builder.Append("  \"vulnerabilityCount\": ")
        builder.Append(vulnerabilityCount.ToString())
        builder.AppendLine(",")
        builder.AppendLine("  \"details\": " + detailsJson)
        builder.AppendLine("}")
        return builder.ToString()
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

    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }
}

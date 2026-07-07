namespace NSharpLang.Cli.Commands

import NSharpLang.Cli
import NSharpLang.Compiler
import System
import System.Collections.Generic
import System.IO
import System.Text

public class TidyDependencyStatus {
    Name: string
    Version: string?
    Status: string
    Reason: string

    constructor(name: string, version: string?, status: string, reason: string) {
        Name = name
        Version = version
        Status = status
        Reason = reason
    }
}

public class TidyCommandSummary {
    PossiblyUnusedCount: int
    UnknownCount: int

    constructor(possiblyUnusedCount: int, unknownCount: int) {
        PossiblyUnusedCount = possiblyUnusedCount
        UnknownCount = unknownCount
    }
}

public class TidyCommand {
    public static func Execute(args: string[]): int {
        options := TidyCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print TidyCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := options.ProjectOption ?? Environment.CurrentDirectory
        fix := options.Fix
        outputMode := TidyCommandKernels.GetOutputMode(options.Json)

        projectYml := Path.Combine(projectRoot, "project.yml")
        if !File.Exists(projectYml) {
            if outputMode == 1 {
                print BuildErrorJson(TidyCommandKernels.GetMissingProjectFileJsonMessage())
            } else {
                Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(
                    TidyCommandKernels.GetMissingProjectFileTextMessage()))
            }

            return 1
        }

        config := new ProjectConfig()
        try {
            config = ProjectFileParser.Parse(projectYml)
        } catch ex: Exception {
            message := TidyCommandKernels.GetParseFailedMessage(ex.Message)
            if outputMode == 1 {
                print BuildErrorJson(message)
            } else {
                Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message))
            }

            return 1
        }

        importedNamespaces := CollectImportedNamespaces(projectRoot)
        results := ClassifyDependencies(config.Dependencies, importedNamespaces)
        summary := SummarizeDependencies(results)
        ok := summary.PossiblyUnusedCount == 0

        if outputMode == 1 {
            print BuildSuccessJson(ok, projectRoot, results)
        } else {
            PrintTable(results, projectRoot, summary)
        }

        if fix {
            selectedIndices := TidyCommandKernels.SelectPossiblyUnusedDependencyIndices(StatusesToArray(results))
            toRemove := new List<TidyDependencyStatus>()
            index := 0
            while index < selectedIndices.Length {
                toRemove.Add(results[selectedIndices[index]])
                index = index + 1
            }

            if toRemove.Count == 0 {
                if outputMode == 2 {
                    print TidyCommandKernels.GetNothingToRemoveMessage()
                }
            } else {
                RemoveDependencies(projectYml, NamesToList(toRemove))
                if outputMode == 2 {
                    print TidyCommandKernels.GetRemovedDependenciesMessage(toRemove.Count)
                }
            }
        }

        return 0
    }

    static func CollectImportedNamespaces(projectRoot: string): List<string> {
        namespaces := new List<string>()
        if !Directory.Exists(projectRoot) {
            return namespaces
        }

        sourceConfig := new ProjectConfig()
        files := sourceConfig.GetSourceFiles(projectRoot, true)
        fileIndex := 0
        while fileIndex < files.Length {
            lines := File.ReadAllLines(files[fileIndex])
            lineIndex := 0
            while lineIndex < lines.Length {
                importedNamespace := TidyCommandKernels.GetImportedNamespace(lines[lineIndex])
                if importedNamespace != null {
                    namespaces.Add(importedNamespace ?? "")
                }

                lineIndex = lineIndex + 1
            }

            fileIndex = fileIndex + 1
        }

        return namespaces
    }

    static func ClassifyDependencies(
        dependencies: List<Reference>,
        importedNamespaces: List<string>): List<TidyDependencyStatus> {
        nugetDependencies := new List<Reference>()
        i := 0
        while i < dependencies.Count {
            dep := dependencies[i]
            if dep.Nuget != null {
                nugetDependencies.Add(dep)
            }

            i = i + 1
        }

        statusRanks := TidyCommandKernels.ClassifyDependencyStatusRanks(nugetDependencies, importedNamespaces)
        results := new List<TidyDependencyStatus>()
        i = 0
        while i < nugetDependencies.Count {
            dep := nugetDependencies[i]
            status := CreateDependencyStatusFromRank(dep.Nuget ?? "", dep.Version, statusRanks[i])
            if status == null {
                throw new InvalidOperationException("N# tidy dependency classifier kernel produced an invalid status rank.")
            }

            results.Add(status ?? new TidyDependencyStatus("", null, "", ""))
            i = i + 1
        }

        return results
    }

    static func CreateDependencyStatusFromRank(
        packageName: string,
        version: string?,
        statusRank: int): TidyDependencyStatus? {
        firstDot := packageName.IndexOf('.')
        if statusRank == 3 && firstDot <= 0 {
            return new TidyDependencyStatus(
                packageName,
                version,
                "unknown",
                TidyCommandKernels.GetUnknownReasonMessage())
        }

        if firstDot <= 0 {
            return null
        }

        secondDot := packageName.IndexOf('.', firstDot + 1)
        prefix1 := packageName.Substring(0, firstDot)
        prefix2 := packageName
        if secondDot > firstDot {
            prefix2 = packageName.Substring(0, secondDot)
        }

        if statusRank == 2 {
            return new TidyDependencyStatus(
                packageName,
                version,
                "used",
                TidyCommandKernels.GetUsedReasonMessage(prefix2))
        }

        if statusRank == 1 {
            return new TidyDependencyStatus(
                packageName,
                version,
                "possibly-unused",
                TidyCommandKernels.GetPossiblyUnusedReasonMessage(prefix1, prefix2))
        }

        return null
    }

    static func RemoveDependencies(projectYml: string, dependencies: List<string>) {
        lines := File.ReadAllLines(projectYml)
        filtered := TidyCommandKernels.FilterRemovalLines(lines, dependencies)
        builder := new StringBuilder()

        i := 0
        while i < filtered.Length {
            builder.AppendLine(filtered[i])
            i = i + 1
        }

        File.WriteAllText(projectYml, builder.ToString())
    }

    static func SummarizeDependencies(results: List<TidyDependencyStatus>): TidyCommandSummary {
        summary := TidyCommandKernels.SummarizeDependencyStatuses(StatusesToArray(results))
        return new TidyCommandSummary(summary.PossiblyUnusedCount, summary.UnknownCount)
    }

    static func PrintTable(
        results: List<TidyDependencyStatus>,
        projectRoot: string,
        summary: TidyCommandSummary) {
        if results.Count == 0 {
            print TidyCommandKernels.GetNoNuGetDependenciesMessage(projectRoot)
            return
        }

        nameWidth := 12
        i := 0
        while i < results.Count {
            if results[i].Name.Length > nameWidth {
                nameWidth = results[i].Name.Length
            }

            i = i + 1
        }

        statusWidth := 15

        print TidyCommandKernels.GetTableHeader(PadRight("Package", nameWidth), PadRight("Status", statusWidth))
        print TidyCommandKernels.GetTableSeparator(new string('-', nameWidth), new string('-', statusWidth))

        i = 0
        while i < results.Count {
            result := results[i]
            print TidyCommandKernels.GetTableRow(
                PadRight(result.Name, nameWidth),
                PadRight(result.Status, statusWidth),
                result.Reason)
            i = i + 1
        }

        possiblyUnused := summary.PossiblyUnusedCount
        unknown := summary.UnknownCount

        print ""
        if possiblyUnused > 0 {
            print TidyCommandKernels.GetPossiblyUnusedFoundMessage(possiblyUnused)
        } else if unknown > 0 {
            print TidyCommandKernels.GetAllDependenciesAccountedForMessage(unknown)
        } else {
            print TidyCommandKernels.GetAllDependenciesInUseMessage()
        }
    }

    static func BuildErrorJson(message: string): string {
        builder := new StringBuilder()
        builder.Append("{\"schemaVersion\":1,\"command\":\"tidy\",\"ok\":false,\"error\":{\"message\":")
        AppendJsonString(builder, message)
        builder.Append("}}")
        return builder.ToString()
    }

    static func BuildSuccessJson(ok: bool, projectRoot: string, dependencies: List<TidyDependencyStatus>): string {
        builder := new StringBuilder()
        builder.Append("{\"schemaVersion\":1,\"command\":\"tidy\",\"ok\":")
        if ok {
            builder.Append("true")
        } else {
            builder.Append("false")
        }

        builder.Append(",\"projectRoot\":")
        AppendJsonString(builder, NormalizeRoot(projectRoot))
        builder.Append(",\"dependencies\":[")

        i := 0
        while i < dependencies.Count {
            dependency := dependencies[i]
            if i > 0 {
                builder.Append(",")
            }

            builder.Append("{\"name\":")
            AppendJsonString(builder, dependency.Name)
            builder.Append(",\"version\":")
            AppendJsonNullableString(builder, dependency.Version)
            builder.Append(",\"status\":")
            AppendJsonString(builder, dependency.Status)
            builder.Append(",\"reason\":")
            AppendJsonString(builder, dependency.Reason)
            builder.Append("}")
            i = i + 1
        }

        builder.Append("]}")
        return builder.ToString()
    }

    static func StatusesToArray(results: List<TidyDependencyStatus>): string[] {
        statuses := new string[](results.Count)
        i := 0
        while i < results.Count {
            statuses[i] = results[i].Status
            i = i + 1
        }

        return statuses
    }

    static func NamesToList(results: List<TidyDependencyStatus>): List<string> {
        names := new List<string>()
        i := 0
        while i < results.Count {
            names.Add(results[i].Name)
            i = i + 1
        }

        return names
    }

    static func PadRight(value: string, width: int): string {
        if value.Length >= width {
            return value
        }

        return value + new string(' ', width - value.Length)
    }

    static func NormalizeRoot(projectRoot: string): string {
        return projectRoot.Replace('\\', '/')
    }

    static func AppendJsonNullableString(builder: StringBuilder, value: string?) {
        if value == null {
            builder.Append("null")
            return
        }

        AppendJsonString(builder, value ?? "")
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
}

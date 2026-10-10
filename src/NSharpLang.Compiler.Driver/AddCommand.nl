namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json
import NSharpLang.Cli
import NSharpLang.Compiler

class AddCommand {
    static func Execute(args: string[]): int {
        arguments := AddCommandKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            print AddCommandKernels.GetHelpText()
            return 0
        }

        if args.Length == 0 {
            return CommandOutputKernels.Error(AddCommandKernels.GetUsageMessage())
        }

        projectRoot := Environment.CurrentDirectory
        projectYml := Path.Combine(projectRoot, "project.yml")

        if !File.Exists(projectYml) {
            return CommandOutputKernels.Error(AddCommandKernels.GetMissingProjectFileMessage())
        }

        isFramework := arguments.Framework
        isPrerelease := arguments.Prerelease
        localPath := arguments.PathOption

        if localPath != null {
            return AddProjectReference(projectYml, localPath ?? "")
        }

        raw := arguments.PackageOperand
        if string.IsNullOrWhiteSpace(raw) {
            return CommandOutputKernels.Error(AddCommandKernels.GetUsageMessage())
        }

        packageSpec := AddCommandKernels.GetPackageSpec(raw ?? "", arguments.VersionOption)
        packageName := packageSpec.PackageName
        version := packageSpec.Version

        if !isFramework && version == null {
            print AddCommandKernels.GetResolvingLatestVersionMessage(packageName)
            version = ResolveLatestVersion(packageName, isPrerelease)
            if version == null {
                return CommandOutputKernels.Error(AddCommandKernels.GetPackageNotFoundMessage(packageName))
            }
        }

        if DeclaresPackageOrFramework(projectYml, packageName) {
            return CommandOutputKernels.Error(AddCommandKernels.GetDuplicatePackageMessage(packageName))
        }

        lineArray := File.ReadAllLines(projectYml)
        lines := ToLineList(lineArray)
        insertAt := AddCommandKernels.GetDependencyInsertIndex(lineArray)

        versionValue := version ?? ""
        newEntry := "  - " + packageName + "@" + versionValue
        if isFramework {
            newEntry = "  - framework: " + packageName
        }

        InsertDependencyEntry(lines, insertAt, newEntry)
        WriteProjectLines(projectYml, lines)

        RestoreCommand.Restore(projectRoot, true)

        if isFramework {
            print AddCommandKernels.GetFrameworkAddedMessage(packageName)
        } else {
            print AddCommandKernels.GetPackageAddedMessage(packageName, versionValue)
        }

        return 0
    }

    // A project.yml the parser cannot read declares no dependency to duplicate: the duplicate check
    // answers "no" for it, and the line-based edit that follows still applies.
    static func DeclaresPackageOrFramework(projectYml: string, packageName: string): bool {
        try {
            config := ProjectFileParser.Parse(projectYml)
            return AddCommandKernels.PackageOrFrameworkDependencyExists(config.Dependencies, packageName)
        } catch {
            return false
        }
    }

    static func DeclaresProjectReference(projectYml: string, localPath: string): bool {
        try {
            config := ProjectFileParser.Parse(projectYml)
            return AddCommandKernels.ProjectDependencyExists(config.Dependencies, localPath)
        } catch {
            return false
        }
    }

    static func AddProjectReference(projectYml: string, localPath: string): int {
        if DeclaresProjectReference(projectYml, localPath) {
            return CommandOutputKernels.Error(AddCommandKernels.GetDuplicateProjectReferenceMessage(localPath))
        }

        lineArray := File.ReadAllLines(projectYml)
        lines := ToLineList(lineArray)
        insertAt := AddCommandKernels.GetDependencyInsertIndex(lineArray)
        newEntry := "  - project: " + localPath

        InsertDependencyEntry(lines, insertAt, newEntry)
        WriteProjectLines(projectYml, lines)

        print AddCommandKernels.GetProjectReferenceAddedMessage(localPath)
        return 0
    }

    static func ResolveLatestVersion(packageName: string, includePrerelease: bool = false): string? {
        try {
            searchArgs := "package search " + packageName + " --exact-match --take 1 --format json"
            if includePrerelease {
                searchArgs = searchArgs + " --prerelease"
            }

            result := DotnetRunner.Run(searchArgs, null, true, null)

            if result.ExitCode == 0 && result.Stdout.Length > 0 {
                document := JsonDocument.Parse(result.Stdout)
                version := ReadLatestVersion(document.RootElement)
                document.Dispose()
                return version
            }
        } catch {
            // An unreachable feed or an unreadable answer resolves no version; the caller reports
            // the package as not found.
            return null
        }

        return null
    }

    static func ReadLatestVersion(root: JsonElement): string? {
        searchResult := new JsonElement()
        if !root.TryGetProperty("searchResult", out searchResult) {
            return null
        }

        if searchResult.ValueKind != JsonValueKind.Array {
            return null
        }

        sourceEnumerator := searchResult.EnumerateArray()
        while sourceEnumerator.MoveNext() {
            source := sourceEnumerator.Current
            packages := new JsonElement()
            if !source.TryGetProperty("packages", out packages) {
                continue
            }

            if packages.ValueKind != JsonValueKind.Array {
                continue
            }

            packageEnumerator := packages.EnumerateArray()
            while packageEnumerator.MoveNext() {
                packageElement := packageEnumerator.Current
                latestVersion := new JsonElement()
                if packageElement.TryGetProperty("latestVersion", out latestVersion) {
                    if latestVersion.ValueKind == JsonValueKind.String {
                        return latestVersion.GetString()
                    }
                }
            }
        }

        return null
    }

    static func ToLineList(lineArray: string[]): List<string> {
        lines := new List<string>()

        for lineArrayItem in lineArray {
            lines.Add(lineArrayItem)
        }

        return lines
    }

    static func InsertDependencyEntry(lines: List<string>, insertAt: int, newEntry: string) {
        if insertAt >= 0 {
            lines.Insert(insertAt, newEntry)
            return
        }

        lines.Add("")
        lines.Add("dependencies:")
        lines.Add(newEntry)
    }

    static func WriteProjectLines(projectYml: string, lines: List<string>) {
        builder := new StringBuilder()

        for line in lines {
            builder.AppendLine(line)
        }

        File.WriteAllText(projectYml, builder.ToString())
    }
}

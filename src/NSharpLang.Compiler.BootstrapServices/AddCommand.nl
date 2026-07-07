namespace NSharpLang.Cli.Commands

import NSharpLang.Cli
import NSharpLang.Compiler
import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json

public class AddCommand {
    public static func Execute(args: string[]): int {
        arguments := AddCommandKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            print AddCommandKernels.GetHelpText()
            return 0
        }

        if args.Length == 0 {
            return Error(AddCommandKernels.GetUsageMessage())
        }

        projectRoot := Environment.CurrentDirectory
        projectYml := Path.Combine(projectRoot, "project.yml")

        if !File.Exists(projectYml) {
            return Error(AddCommandKernels.GetMissingProjectFileMessage())
        }

        isFramework := arguments.Framework
        isPrerelease := arguments.Prerelease
        localPath := arguments.PathOption

        if localPath != null {
            return AddProjectReference(projectYml, localPath ?? "")
        }

        raw := arguments.PackageOperand
        if string.IsNullOrWhiteSpace(raw) {
            return Error(AddCommandKernels.GetUsageMessage())
        }

        packageSpec := AddCommandKernels.GetPackageSpec(raw ?? "", arguments.VersionOption)
        packageName := packageSpec.PackageName
        version := packageSpec.Version

        if !isFramework && version == null {
            print AddCommandKernels.GetResolvingLatestVersionMessage(packageName)
            version = ResolveLatestVersion(packageName, isPrerelease)
            if version == null {
                return Error(AddCommandKernels.GetPackageNotFoundMessage(packageName))
            }
        }

        try {
            config := ProjectFileParser.Parse(projectYml)
            if AddCommandKernels.PackageOrFrameworkDependencyExists(config.Dependencies, packageName) {
                return Error(AddCommandKernels.GetDuplicatePackageMessage(packageName))
            }
        } catch {
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

    static func AddProjectReference(projectYml: string, localPath: string): int {
        try {
            config := ProjectFileParser.Parse(projectYml)
            if AddCommandKernels.ProjectDependencyExists(config.Dependencies, localPath) {
                return Error(AddCommandKernels.GetDuplicateProjectReferenceMessage(localPath))
            }
        } catch {
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

    public static func ResolveLatestVersion(packageName: string, includePrerelease: bool = false): string? {
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

        i := 0
        while i < lineArray.Length {
            lines.Add(lineArray[i])
            i = i + 1
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

        i := 0
        while i < lines.Count {
            builder.AppendLine(lines[i])
            i = i + 1
        }

        File.WriteAllText(projectYml, builder.ToString())
    }

    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }
}

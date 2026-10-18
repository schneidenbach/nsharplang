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

    static func DeclaresProjectReference(projectYml: string, projectRoot: string, targetFullPath: string): bool {
        try {
            config := ProjectFileParser.Parse(projectYml)
            existing := new List<string>()
            for path in AddCommandKernels.GetProjectDependencyPaths(config.Dependencies, projectRoot) {
                existing.Add(PhysicalPath(path))
            }

            return AddCommandKernels.ContainsPath(existing, PhysicalPath(targetFullPath))
        } catch {
            return false
        }
    }

    // THE PATH WITH EVERY SYMBOLIC LINK ON IT RESOLVED, so `/var/x` and `/private/var/x` on macOS --
    // or a symlinked checkout and its real directory -- compare as the one file they are. Each
    // segment is resolved in turn; a segment that does not exist (yet) is kept as written.
    static func PhysicalPath(path: string): string {
        full := Path.GetFullPath(path)
        current := Path.GetPathRoot(full) ?? ""
        segments := full.Substring(current.Length).Split(Path.DirectorySeparatorChar)
        for segment in segments {
            if segment.Length == 0 {
                continue
            }

            next := Path.Combine(current, segment)
            try {
                let target: FileSystemInfo? = null
                if Directory.Exists(next) {
                    target = Directory.ResolveLinkTarget(next, true)
                } else if File.Exists(next) {
                    target = File.ResolveLinkTarget(next, true)
                }

                if target != null {
                    next = target.FullName
                }
            } catch {
                // An unreadable link keeps its own spelling; the comparison is then by that spelling.
                next = Path.Combine(current, segment)
            }

            current = next
        }

        return current
    }

    // `--path` NAMES AN N# PROJECT: a `project.yml`, or a directory holding one, which is written as
    // `<dir>/project.yml`. A `.csproj` or any other file is refused, because `nlc build` cannot build
    // it. The duplicate check compares the FULL PATHS the entries resolve to, so `../Lib`,
    // `../Lib/./project.yml` and an absolute spelling of the same file are one reference. The entry
    // is written with `/` separators, since project.yml is shared across platforms.
    static func AddProjectReference(projectYml: string, writtenPath: string): int {
        projectRoot := Path.GetDirectoryName(Path.GetFullPath(projectYml)) ?? Environment.CurrentDirectory
        localPath := writtenPath
        resolvedPath := Path.GetFullPath(CompilationReferenceResolverKernels.ResolveProjectReferencePath(projectRoot, writtenPath))
        targetPath := resolvedPath
        isDirectory := Directory.Exists(resolvedPath)
        if isDirectory {
            targetPath = Path.Combine(resolvedPath, "project.yml")
            if !File.Exists(targetPath) {
                return CommandOutputKernels.Error(AddCommandKernels.GetProjectDirectoryWithoutProjectFileMessage(writtenPath))
            }

            localPath = AddCommandKernels.GetProjectFileReferencePath(writtenPath)
        }

        localPath = AddCommandKernels.GetWrittenProjectReferencePath(localPath)
        if DeclaresProjectReference(projectYml, projectRoot, targetPath) {
            return CommandOutputKernels.Error(AddCommandKernels.GetDuplicateProjectReferenceMessage(localPath))
        }

        if !isDirectory && !File.Exists(resolvedPath) {
            return CommandOutputKernels.Error(AddCommandKernels.GetProjectReferenceNotFoundMessage(writtenPath, resolvedPath))
        }

        if !AddCommandKernels.IsProjectFileName(Path.GetFileName(targetPath)) {
            return CommandOutputKernels.Error(AddCommandKernels.GetNotAProjectFileMessage(writtenPath))
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

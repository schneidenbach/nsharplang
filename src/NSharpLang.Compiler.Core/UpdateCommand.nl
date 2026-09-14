namespace NSharpLang.Cli.Commands

import System
import System.IO
import System.Text
import NSharpLang.Compiler

class UpdateCommand {
    static func Execute(args: string[]): int {
        arguments := UpdateCommandKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            print UpdateCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := Environment.CurrentDirectory
        projectYml := Path.Combine(projectRoot, "project.yml")
        dryRun := arguments.DryRun

        if !File.Exists(projectYml) {
            return Error(UpdateCommandKernels.GetMissingProjectFileMessage())
        }

        targetPackage := arguments.TargetPackage

        try {
            config := ProjectFileParser.Parse(projectYml)
            allNuGetDeps := UpdateDependencyFilter.FilterAllNuGetDependencies(config.Dependencies)

            if allNuGetDeps.Count == 0 {
                print UpdateCommandKernels.GetNoNuGetDependenciesMessage()
                return 0
            }

            nugetDeps := allNuGetDeps
            if targetPackage != null {
                targetValue := targetPackage ?? ""
                nugetDeps = UpdateDependencyFilter.FilterTargetNuGetDependencies(allNuGetDeps, targetValue)
                if nugetDeps.Count == 0 {
                    return Error(UpdateCommandKernels.GetPackageNotFoundMessage(targetValue))
                }
            }

            lines := File.ReadAllLines(projectYml)
            updated := 0

            depIndex := 0
            while depIndex < nugetDeps.Count {
                dep := nugetDeps[depIndex]
                packageName := dep.Nuget ?? ""
                latest := AddCommand.ResolveLatestVersion(packageName, false)
                if latest == null {
                    Console.Error.WriteLine(UpdateCommandKernels.GetResolveLatestFailureMessage(packageName))
                    depIndex = depIndex + 1
                    continue
                }

                latestValue := latest ?? ""
                currentVersion := dep.Version ?? ""
                if currentVersion == latestValue {
                    if dryRun || targetPackage != null {
                        print UpdateCommandKernels.GetPackageUpToDateMessage(packageName, currentVersion)
                    }

                    depIndex = depIndex + 1
                    continue
                }

                print UpdateCommandKernels.GetPackageUpdateMessage(packageName, currentVersion, latestValue)

                if !dryRun {
                    ApplyPackageUpdate(lines, packageName, latestValue)
                    updated = updated + 1
                }

                depIndex = depIndex + 1
            }

            if !dryRun && updated > 0 {
                WriteProjectLines(projectYml, lines)
                RestoreCommand.Restore(projectRoot, true)
                print UpdateCommandKernels.GetUpdatedPackagesMessage(updated)
            } else if dryRun {
                print UpdateCommandKernels.GetDryRunMessage()
            } else {
                print UpdateCommandKernels.GetAllPackagesUpToDateMessage()
            }

            return 0
        } catch ex: Exception {
            return Error(UpdateCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func ApplyPackageUpdate(lines: string[], packageName: string, latest: string) {
        i := 0
        while i < lines.Length {
            trimmed := lines[i].Trim()
            shorthandNeedle := packageName + "@"

            if trimmed.StartsWith("- ", StringComparison.Ordinal) && ContainsIgnoreCase(trimmed, shorthandNeedle) {
                atIndex := lines[i].IndexOf('@')
                if atIndex > 0 {
                    lines[i] = lines[i].Substring(0, atIndex + 1) + latest
                }

                return
            }

            mappingNeedle := "nuget: " + packageName
            if ContainsIgnoreCase(trimmed, mappingNeedle) {
                j := i + 1
                limit := i + 3
                while j < lines.Length && j <= limit {
                    versionIndex := FirstNonWhitespaceIndex(lines[j])
                    if StartsWithAt(lines[j], versionIndex, "version:") {
                        indent := ""
                        if versionIndex > 0 {
                            indent = lines[j].Substring(0, versionIndex)
                        }

                        lines[j] = indent + "version: " + latest
                        return
                    }

                    j = j + 1
                }

                return
            }

            i = i + 1
        }
    }

    static func ContainsIgnoreCase(text: string, value: string): bool {
        if value.Length == 0 {
            return true
        }

        limit := text.Length - value.Length
        index := 0
        while index <= limit {
            if String.Compare(text, index, value, 0, value.Length, StringComparison.OrdinalIgnoreCase) == 0 {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func FirstNonWhitespaceIndex(text: string): int {
        index := 0
        while index < text.Length && char.IsWhiteSpace(text[index]) {
            index = index + 1
        }

        return index
    }

    static func StartsWithAt(text: string, start: int, value: string): bool {
        if start < 0 || start + value.Length > text.Length {
            return false
        }

        index := 0
        while index < value.Length {
            if text[start + index] != value[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func WriteProjectLines(projectYml: string, lines: string[]) {
        builder := new StringBuilder()

        i := 0
        while i < lines.Length {
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

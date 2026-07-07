namespace NSharpLang.Cli.Commands

import NSharpLang.Cli
import NSharpLang.Compiler.CodeIntelligence
import System
import System.Collections.Generic
import System.IO
import System.Text

public class CleanCommand {
    public static func Execute(args: string[]): int {
        options := CleanCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print CleanCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := Path.GetFullPath(options.ProjectOption ?? Environment.CurrentDirectory)
        cleanAll := options.CleanAll

        if !Directory.Exists(projectRoot) {
            return Error(CleanCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot))
        }

        try {
            removed := RemoveArtifacts(projectRoot)

            if cleanAll {
                cacheExitCode := ClearNuGetCaches()
                if cacheExitCode != 0 {
                    return cacheExitCode
                }
            }

            if removed.Count == 0 {
                print CleanCommandKernels.GetNoArtifactsFoundMessage(projectRoot)
            } else {
                print CleanCommandKernels.GetRemovedArtifactsHeader(removed.Count)
                i := 0
                while i < removed.Count {
                    print CleanCommandKernels.GetRemovedArtifactLine(removed[i])
                    i = i + 1
                }
            }

            if cleanAll {
                print CleanCommandKernels.GetClearedNuGetCachesMessage()
            }

            return 0
        } catch ex: Exception {
            return Error(CleanCommandKernels.GetCleanFailedMessage(ex.Message))
        }
    }

    static func RemoveArtifacts(projectRoot: string): List<string> {
        candidates := new List<string>()
        AddArtifactCandidates(projectRoot, candidates)
        ordered := CleanArtifactDirectoryOrderer.Order(candidates)

        removed := new List<string>()
        i := 0
        while i < ordered.Length {
            dir := ordered[i]
            if Directory.Exists(dir) {
                DeleteDirectoryTree(dir)
                removed.Add(NormalizePath(Path.GetRelativePath(projectRoot, dir)))
            }

            i = i + 1
        }

        array := removed.ToArray()
        Array.Sort(array, 0, array.Length, StringComparer.Ordinal)

        sorted := new List<string>()
        j := 0
        while j < array.Length {
            sorted.Add(array[j])
            j = j + 1
        }

        return sorted
    }

    static func AddArtifactCandidates(projectRoot: string, candidates: List<string>) {
        AddIfExists(candidates, Path.Combine(projectRoot, "bin"))
        AddIfExists(candidates, Path.Combine(projectRoot, "obj"))
        AddIfExists(candidates, Path.Combine(projectRoot, ".nlc"))
        AddArtifactCandidatesRecursive(projectRoot, candidates)
    }

    static func AddArtifactCandidatesRecursive(directory: string, candidates: List<string>) {
        subdirectories := new string[](0)
        try {
            subdirectories = Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
        } catch {
            return
        }

        i := 0
        while i < subdirectories.Length {
            subdirectory := subdirectories[i]
            AddIfExists(candidates, subdirectory)

            directoryName := Path.GetFileName(subdirectory) ?? ""
            if String.Compare(directoryName, "node_modules", StringComparison.OrdinalIgnoreCase) != 0 {
                AddArtifactCandidatesRecursive(subdirectory, candidates)
            }

            i = i + 1
        }
    }

    static func AddIfExists(candidates: List<string>, directory: string) {
        if Directory.Exists(directory) {
            candidates.Add(directory)
        }
    }

    static func DeleteDirectoryTree(directory: string) {
        result := new DotnetRunResult(1, "", "")
        if IsWindows() {
            result = DotnetRunner.RunProcess("cmd", "/c rmdir /s /q " + QuoteProcessArgument(directory), null, null)
        } else {
            result = DotnetRunner.RunProcess("rm", "-rf " + QuoteProcessArgument(directory), null, null)
        }

        if result.ExitCode != 0 {
            detail := (result.Stderr + result.Stdout).Trim()
            if detail.Length == 0 {
                detail = "directory removal process exited with code " + result.ExitCode.ToString()
            }

            throw new InvalidOperationException(detail)
        }
    }

    static func ClearNuGetCaches(): int {
        result := DotnetRunner.Run("nuget locals all --clear", null, true, null)

        if result.ExitCode == 0 {
            return 0
        }

        return Error(CleanCommandKernels.GetClearNuGetCachesFailedMessage((result.Stderr + result.Stdout).Trim()))
    }

    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }

    static func IsWindows(): bool {
        osMarker := Environment.GetEnvironmentVariable("OS") ?? ""
        return String.Compare(osMarker, "Windows_NT", StringComparison.OrdinalIgnoreCase) == 0
    }

    static func QuoteProcessArgument(value: string): string {
        builder := new StringBuilder()
        builder.Append('"')

        i := 0
        while i < value.Length {
            ch := value[i]
            if ch == '\\' || ch == '"' {
                builder.Append('\\')
            }

            builder.Append(ch)
            i = i + 1
        }

        builder.Append('"')
        return builder.ToString()
    }

    static func NormalizePath(path: string): string {
        return OutputFormatterNormalizationKernels.NormalizePath(path) ?? path
    }
}

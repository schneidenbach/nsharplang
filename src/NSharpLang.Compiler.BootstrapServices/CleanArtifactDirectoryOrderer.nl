namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class CleanArtifactDirectoryOrderer {
    public static func Order(directories: IReadOnlyList<string>): string[] {
        selected := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)

        foreach directory in directories {
            if GetArtifactDirectoryKindRank(directory) > 0
                && !IsUnderNodeModulesDirectory(directory)
                && !seen.Contains(directory) {
                seen.Add(directory)
                selected.Add(directory)
            }
        }

        result := new string[](selected.Count)
        used := new bool[](selected.Count)
        outputIndex := 0
        while outputIndex < selected.Count {
            bestIndex := -1
            bestLength := -1

            i := 0
            while i < selected.Count {
                if !used[i] {
                    length := selected[i].Length
                    if length > bestLength {
                        bestLength = length
                        bestIndex = i
                    }
                }

                i = i + 1
            }

            result[outputIndex] = selected[bestIndex]
            used[bestIndex] = true
            outputIndex = outputIndex + 1
        }

        return result
    }

    static func GetArtifactDirectoryKindRank(path: string): int {
        fileNameStart := CleanFileNameStart(path)
        if CleanPathSegmentEquals(path, fileNameStart, path.Length, "bin") {
            return 1
        }

        if CleanPathSegmentEquals(path, fileNameStart, path.Length, "obj") {
            return 2
        }

        if CleanPathSegmentEquals(path, fileNameStart, path.Length, ".nlc") {
            return 3
        }

        return 0
    }

    static func IsUnderNodeModulesDirectory(path: string): bool {
        pattern := "/node_modules/"
        if path.Length < pattern.Length {
            return false
        }

        start := 0
        maxStart := path.Length - pattern.Length
        while start <= maxStart {
            if CleanPathSegmentEquals(path, start, start + pattern.Length, pattern) {
                return true
            }

            start = start + 1
        }

        return false
    }

    static func CleanFileNameStart(path: string): int {
        index := path.Length - 1
        while index >= 0 {
            ch := path[index]
            if ch == '/' || ch == '\\' {
                return index + 1
            }

            index = index - 1
        }

        return 0
    }

    static func CleanPathSegmentEquals(path: string, start: int, end: int, value: string): bool {
        length := end - start
        if length != value.Length {
            return false
        }

        index := 0
        while index < value.Length {
            if CleanNormalizedPathChar(path[start + index]) != value[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func CleanNormalizedPathChar(ch: char): char {
        if ch == '\\' {
            return '/'
        }

        return ch
    }
}

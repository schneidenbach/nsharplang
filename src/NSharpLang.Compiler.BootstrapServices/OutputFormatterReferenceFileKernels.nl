namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class OutputFormatterReferenceFileKernels {
    public static func BuildInspectSummaryReferenceFiles(references: IReadOnlyList<object>): string[] {
        return BuildReferenceFiles(references, true, false)
    }

    public static func BuildDiagnosticClusterFiles(diagnostics: IReadOnlyList<object>): string[] {
        return BuildReferenceFiles(diagnostics, false, true)
    }

    static func BuildReferenceFiles(items: IReadOnlyList<object>, normalizePath: bool, ignoreCase: bool): string[] {
        uniqueFiles := new List<string>()
        i := 0
        while i < items.Count {
            pathText := ReferenceFileValue(items[i])
            if normalizePath {
                pathText = NormalizeReferencePath(pathText)
            }

            if !ContainsReferenceFile(uniqueFiles, pathText, ignoreCase) {
                uniqueFiles.Add(pathText)
            }

            i = i + 1
        }

        SortReferenceFiles(uniqueFiles, ignoreCase)
        result := new string[](uniqueFiles.Count)
        i = 0
        while i < uniqueFiles.Count {
            result[i] = uniqueFiles[i]
            i = i + 1
        }

        return result
    }

    static func ReferenceFileValue(value: object): string {
        if value == null {
            return ""
        }

        property := value.GetType().GetProperty("File")
        if property != null {
            return ReferenceFileRawValue(property.GetValue(value))
        }

        field := value.GetType().GetField("File")
        if field == null {
            return ""
        }

        return ReferenceFileRawValue(field.GetValue(value))
    }

    static func ReferenceFileRawValue(rawValue: object): string {
        if rawValue == null {
            return ""
        }

        text := rawValue as string
        if text == null {
            return ""
        }

        return text
    }

    static func NormalizeReferencePath(path: string): string {
        return path.Replace('\\', '/')
    }

    static func ContainsReferenceFile(files: List<string>, pathText: string, ignoreCase: bool): bool {
        i := 0
        while i < files.Count {
            if CompareReferenceFiles(files[i], pathText, ignoreCase) == 0 {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func SortReferenceFiles(files: List<string>, ignoreCase: bool) {
        i := 1
        while i < files.Count {
            current := files[i]
            j := i
            while j > 0 {
                previous := files[j - 1]
                if CompareReferenceFiles(previous, current, ignoreCase) <= 0 {
                    break
                }

                files[j] = previous
                j = j - 1
            }

            files[j] = current
            i = i + 1
        }
    }

    static func CompareReferenceFiles(left: string, right: string, ignoreCase: bool): int {
        if ignoreCase {
            return String.Compare(left, right, StringComparison.OrdinalIgnoreCase)
        }

        return String.Compare(left, right, StringComparison.Ordinal)
    }
}

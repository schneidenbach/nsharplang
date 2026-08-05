namespace NSharpLang.Cli.Commands

import System

class RemoveArgumentSummary {
    packageOperandValue: string?
    showHelpValue: bool

    PackageOperand: string? => packageOperandValue
    ShowHelp: bool => showHelpValue

    constructor(packageOperand: string?, showHelp: bool) {
        packageOperandValue = packageOperand
        showHelpValue = showHelp
    }
}

enum RemoveDependencyLineAction {
    Keep = 0,
    RemoveSingleLine = 1,
    RemoveMappingBlock = 2
}

class RemoveCommandKernels {
    static func GetArgumentSummary(args: string[]): RemoveArgumentSummary {
        resultIndices := new int[](2)
        code := RemoveArgumentSummaryInto(args, resultIndices)
        if code != 0 {
            throw new InvalidOperationException("N# remove argument summary kernel rejected the arguments.")
        }

        packageOperand: string? = null
        if resultIndices[0] != -1 {
            packageOperand = args[resultIndices[0]]
        }

        return new RemoveArgumentSummary(packageOperand, resultIndices[1] != 0)
    }

    static func GetDependencyLineAction(line: string, packageName: string): RemoveDependencyLineAction {
        result := RemoveDependencyLineActionCode(line, packageName)
        if result < 0 || result > 2 {
            throw new InvalidOperationException("N# remove dependency-line action kernel rejected the line.")
        }

        return (RemoveDependencyLineAction)result
    }

    static func ShouldStopDependencyContinuationLine(line: string): bool {
        result := RemoveShouldStopDependencyContinuationLine(line)
        if result != 0 && result != 1 {
            throw new InvalidOperationException("N# remove dependency continuation kernel rejected the line.")
        }

        return result == 1
    }

    static func GetHelpText(): string {
        return "N# Remove Dependency\n" + "\n" + "Usage: nlc remove <package>\n" + "\n" + "Remove a dependency from project.yml.\n" + "\n" + "Options:\n" + "  --help, -h    Show this help text\n" + "\n" + "Examples:\n" + "  nlc remove Newtonsoft.Json\n" + "  nlc remove Microsoft.AspNetCore.App\n" + "\n" + "Exit codes:\n" + "  0  Dependency removed successfully\n" + "  1  Failed to remove dependency"
    }

    static func GetUsageMessage(): string {
        return "Usage: nlc remove <package>"
    }

    static func GetMissingProjectFileMessage(): string {
        return "No project.yml found."
    }

    static func GetPackageNotFoundMessage(packageName: string): string {
        return "Package '" + packageName + "' not found in dependencies."
    }

    static func GetRemovedMessage(packageName: string): string {
        return "Removed " + packageName + " from project.yml"
    }

    static func RemoveArgumentSummaryInto(args: string[], resultIndices: int[]): int {
        if resultIndices.Length < 2 {
            return -1
        }

        resultIndices[0] = -1
        resultIndices[1] = 0

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                resultIndices[1] = 1
            }

            if arg == "--help" || arg == "-h" {
                resultIndices[1] = 1
            }

            if resultIndices[0] < 0 {
                if arg.Length == 0 || arg[0] != '-' {
                    resultIndices[0] = i
                }
            }

            i = i + 1
        }

        return 0
    }

    static func RemoveDependencyLineActionCode(line: string, packageName: string): int {
        start := RemoveTrimStartIndex(line)
        end := RemoveTrimEndIndex(line, start)

        if RemoveSubstringStartsWithAsciiIgnoreCase(line, start, end, "- ") {
            if RemoveTrimmedEqualsPackageLine(line, start, end, packageName) {
                return 1
            }

            if RemoveContainsPackageVersion(line, start, end, packageName) {
                return 1
            }
        }

        if RemoveSubstringStartsWithAsciiIgnoreCase(line, start, end, "- nuget:") || RemoveSubstringStartsWithAsciiIgnoreCase(line, start, end, "- framework:") {
            if RemoveContainsAsciiIgnoreCase(line, start, end, packageName) {
                return 2
            }
        }

        return 0
    }

    static func RemoveShouldStopDependencyContinuationLine(line: string): int {
        if line.Length == 0 {
            return 1
        }

        start := RemoveTrimStartIndex(line)
        if RemoveSubstringStartsWithAsciiIgnoreCase(line, start, line.Length, "- ") {
            return 1
        }

        if line[0] != ' ' && line[0] != '\t' {
            return 1
        }

        return 0
    }

    static func RemoveTrimStartIndex(text: string): int {
        index := 0
        while index < text.Length && char.IsWhiteSpace(text[index]) {
            index = index + 1
        }

        return index
    }

    static func RemoveTrimEndIndex(text: string, start: int): int {
        end := text.Length
        while end > start && char.IsWhiteSpace(text[end - 1]) {
            end = end - 1
        }

        return end
    }

    static func RemoveSubstringStartsWithAsciiIgnoreCase(text: string, start: int, end: int, prefix: string): bool {
        if end - start < prefix.Length {
            return false
        }

        return RemoveRangeEqualsAsciiIgnoreCase(text, start, prefix)
    }

    static func RemoveTrimmedEqualsPackageLine(text: string, start: int, end: int, packageName: string): bool {
        prefixLength := 2
        if end - start != prefixLength + packageName.Length {
            return false
        }

        if text[start] != '-' || text[start + 1] != ' ' {
            return false
        }

        return RemoveRangeEqualsAsciiIgnoreCase(text, start + prefixLength, packageName)
    }

    static func RemoveContainsPackageVersion(text: string, start: int, end: int, packageName: string): bool {
        if packageName.Length == 0 {
            index := start
            while index < end {
                if text[index] == '@' {
                    return true
                }

                index = index + 1
            }

            return false
        }

        limit := end - packageName.Length
        index := start
        while index < limit {
            if text[index + packageName.Length] == '@' && RemoveRangeEqualsAsciiIgnoreCase(text, index, packageName) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func RemoveContainsAsciiIgnoreCase(text: string, start: int, end: int, value: string): bool {
        if value.Length == 0 {
            return true
        }

        limit := end - value.Length
        index := start
        while index <= limit {
            if RemoveRangeEqualsAsciiIgnoreCase(text, index, value) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func RemoveRangeEqualsAsciiIgnoreCase(text: string, start: int, value: string): bool {
        if start < 0 || start + value.Length > text.Length {
            return false
        }

        index := 0
        while index < value.Length {
            if !RemoveCharsEqualAsciiIgnoreCase(text[start + index], value[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func RemoveCharsEqualAsciiIgnoreCase(left: char, right: char): bool {
        leftCode := (int)left
        rightCode := (int)right

        if left >= 'A' && left <= 'Z' {
            leftCode = leftCode + 32
        }

        if right >= 'A' && right <= 'Z' {
            rightCode = rightCode + 32
        }

        return leftCode == rightCode
    }
}

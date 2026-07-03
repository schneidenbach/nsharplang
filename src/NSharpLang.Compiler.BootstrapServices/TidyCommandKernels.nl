namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler
import System
import System.Collections.Generic

public class TidyOptionSummary {
    ProjectOption: string?
    Fix: bool
    Json: bool
    ShowHelp: bool

    constructor(projectOption: string?, fix: bool, json: bool, showHelp: bool) {
        ProjectOption = projectOption
        Fix = fix
        Json = json
        ShowHelp = showHelp
    }
}

public class TidyDependencyStatusSummary {
    PossiblyUnusedCount: int
    UnknownCount: int

    constructor(possiblyUnusedCount: int, unknownCount: int) {
        PossiblyUnusedCount = possiblyUnusedCount
        UnknownCount = unknownCount
    }
}

public class TidyCommandKernels {
    public static func GetOptionSummary(args: string[]): TidyOptionSummary {
        projectOption: string? = null
        fix := false
        json := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            kind := OptionSummaryKind(arg)
            if kind == 1 {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            } else if kind == 2 {
                fix = true
            } else if kind == 3 {
                json = true
            } else if kind == 4 {
                showHelp = true
            }

            i = i + 1
        }

        return new TidyOptionSummary(projectOption, fix, json, showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetImportedNamespace(line: string): string? {
        start := 0
        while start < line.Length && char.IsWhiteSpace(line[start]) {
            start = start + 1
        }

        if !SubstringStartsWith(line, start, line.Length, "import ") {
            return null
        }

        namespaceStart := start + 7
        while namespaceStart < line.Length && char.IsWhiteSpace(line[namespaceStart]) {
            namespaceStart = namespaceStart + 1
        }

        namespaceEnd := namespaceStart
        while namespaceEnd < line.Length && IsImportNamespaceChar(line[namespaceEnd]) {
            namespaceEnd = namespaceEnd + 1
        }

        if namespaceEnd == namespaceStart {
            return null
        }

        return line.Substring(namespaceStart, namespaceEnd - namespaceStart)
    }

    public static func SelectPossiblyUnusedDependencyIndices(statuses: IReadOnlyList<string>): int[] {
        count := 0
        i := 0
        while i < statuses.Count {
            if StatusRank(statuses[i]) == 1 {
                count = count + 1
            }

            i = i + 1
        }

        indices := new int[](count)
        resultIndex := 0
        i = 0
        while i < statuses.Count {
            if StatusRank(statuses[i]) == 1 {
                indices[resultIndex] = i
                resultIndex = resultIndex + 1
            }

            i = i + 1
        }

        return indices
    }

    public static func SummarizeDependencyStatuses(statuses: IReadOnlyList<string>): TidyDependencyStatusSummary {
        possiblyUnusedCount := 0
        unknownCount := 0

        i := 0
        while i < statuses.Count {
            rank := StatusRank(statuses[i])
            if rank == 1 {
                possiblyUnusedCount = possiblyUnusedCount + 1
            } else if rank == 3 {
                unknownCount = unknownCount + 1
            }

            i = i + 1
        }

        return new TidyDependencyStatusSummary(possiblyUnusedCount, unknownCount)
    }

    public static func ClassifyDependencyStatusRanks(
        dependencies: IReadOnlyList<Reference>,
        importedNamespaces: IReadOnlyCollection<string>): int[] {
        statusRanks := new int[](dependencies.Count)
        importArray := new string[](importedNamespaces.Count)

        importIndex := 0
        foreach importedNamespace in importedNamespaces {
            importArray[importIndex] = importedNamespace
            importIndex = importIndex + 1
        }

        i := 0
        while i < dependencies.Count {
            packageName := dependencies[i].Nuget
            if packageName == null {
                throw new InvalidOperationException("N# tidy dependency classifier kernel received a non-NuGet dependency.")
            }

            statusRanks[i] = DependencyStatusRank(packageName, importArray)
            i = i + 1
        }

        return statusRanks
    }

    public static func FilterRemovalLines(
        lines: IReadOnlyList<string>,
        packageNames: IReadOnlyList<string>): string[] {
        keptCount := 0
        i := 0
        while i < lines.Count {
            lineValue := lines[i]
            if lineValue == null {
                throw new InvalidOperationException("N# tidy dependency removal kernel received a null line.")
            }

            if RemovalLineKeepFlag(lineValue, packageNames) == 1 {
                keptCount = keptCount + 1
            }

            i = i + 1
        }

        result := new string[](keptCount)
        resultIndex := 0
        i = 0
        while i < lines.Count {
            lineValue := lines[i]
            if RemovalLineKeepFlag(lineValue, packageNames) == 1 {
                result[resultIndex] = lineValue
                resultIndex = resultIndex + 1
            }

            i = i + 1
        }

        return result
    }

    public static func GetHelpText(): string {
        return "N# Tidy\n"
            + "\n"
            + "Usage: nlc tidy [options]\n"
            + "\n"
            + "Identify and optionally remove unused NuGet dependencies from project.yml.\n"
            + "\n"
            + "Each dependency is classified as:\n"
            + "  used            — an import statement plausibly references the package namespace\n"
            + "  possibly-unused — no import statement references the package namespace\n"
            + "  unknown         — cannot determine usage (e.g. single-segment package names)\n"
            + "\n"
            + "The command is conservative: 'unknown' is reported rather than incorrectly\n"
            + "flagging a dependency as unused.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project directory (default: current directory)\n"
            + "  --fix             Remove all possibly-unused dependencies from project.yml\n"
            + "  --json            Emit structured JSON output\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "JSON schema (schemaVersion 1):\n"
            + "  { schemaVersion, command, ok, projectRoot,\n"
            + "    dependencies: [{ name, version, status, reason }] }\n"
            + "\n"
            + "Examples:\n"
            + "  nlc tidy                   Report unused dependencies\n"
            + "  nlc tidy --fix             Remove possibly-unused dependencies\n"
            + "  nlc tidy --json            Machine-readable output\n"
            + "  nlc tidy --project ./lib   Analyse a different project\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  All dependencies in use (or tidy succeeded)\n"
            + "  1  Error (missing project.yml, parse failure)"
    }

    public static func GetMissingProjectFileJsonMessage(): string {
        return "No project.yml found in the specified directory."
    }

    public static func GetMissingProjectFileTextMessage(): string {
        return "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project."
    }

    public static func GetParseFailedMessage(message: string): string {
        return "Failed to parse project.yml: " + message
    }

    public static func GetNothingToRemoveMessage(): string {
        return "Nothing to remove."
    }

    public static func GetRemovedDependenciesMessage(count: int): string {
        dependencyWord := "dependencies"
        if count == 1 {
            dependencyWord = "dependency"
        }

        return "Removed " + count.ToString() + " possibly-unused " + dependencyWord + "."
    }

    public static func GetNoNuGetDependenciesMessage(projectRoot: string): string {
        return "No NuGet dependencies found in " + projectRoot
    }

    public static func GetTableHeader(packageLabel: string, statusLabel: string): string {
        return "  " + packageLabel + "  " + statusLabel + "  Reason"
    }

    public static func GetTableSeparator(packageSeparator: string, statusSeparator: string): string {
        return "  " + packageSeparator + "  " + statusSeparator + "  ------"
    }

    public static func GetTableRow(packageLabel: string, statusLabel: string, reason: string): string {
        return "  " + packageLabel + "  " + statusLabel + "  " + reason
    }

    public static func GetPossiblyUnusedFoundMessage(count: int): string {
        dependencyWord := "dependencies"
        if count == 1 {
            dependencyWord = "dependency"
        }

        return count.ToString() + " possibly-unused " + dependencyWord + " found. Run 'nlc tidy --fix' to remove them."
    }

    public static func GetAllDependenciesAccountedForMessage(unknownCount: int): string {
        return "All dependencies accounted for (" + unknownCount.ToString() + " could not be determined)."
    }

    public static func GetAllDependenciesInUseMessage(): string {
        return "All dependencies appear to be in use."
    }

    public static func GetUnknownReasonMessage(): string {
        return "Cannot determine namespace for single-segment package name; manual review required."
    }

    public static func GetUsedReasonMessage(namespacePrefix: string): string {
        return "Import statement references namespace matching '" + namespacePrefix + "'."
    }

    public static func GetPossiblyUnusedReasonMessage(prefix1: string, prefix2: string): string {
        return "No import statement found referencing '" + prefix1 + "' or '" + prefix2 + "'."
    }

    static func OptionSummaryKind(arg: string): int {
        if arg == "--project" {
            return 1
        }

        if arg == "--fix" {
            return 2
        }

        if arg == "--json" {
            return 3
        }

        if arg == "--help" || arg == "-h" {
            return 4
        }

        return 0
    }

    static func StatusRank(status: string): int {
        if status == "possibly-unused" {
            return 1
        }

        if status == "used" {
            return 2
        }

        if status == "unknown" {
            return 3
        }

        return 0
    }

    static func DependencyStatusRank(packageName: string, importNamespaces: string[]): int {
        firstDot := packageName.IndexOf('.')
        if firstDot < 0 {
            return 3
        }

        i := 0
        while i < importNamespaces.Length {
            namespaceName := importNamespaces[i]
            if NamespaceMatchesPrefix(namespaceName, packageName, firstDot) {
                return 2
            }

            i = i + 1
        }

        return 1
    }

    static func NamespaceMatchesPrefix(namespaceName: string, packageName: string, prefixLength: int): bool {
        if prefixLength <= 0 || namespaceName.Length < prefixLength || packageName.Length < prefixLength {
            return false
        }

        if namespaceName.Length > prefixLength && namespaceName[prefixLength] != '.' {
            return false
        }

        return TextSegmentEqualsIgnoreCase(namespaceName, 0, packageName, 0, prefixLength)
    }

    static func RemovalLineKeepFlag(lineValue: string, packageNames: IReadOnlyList<string>): int {
        start := 0
        while start < lineValue.Length && char.IsWhiteSpace(lineValue[start]) {
            start = start + 1
        }

        if start + 2 > lineValue.Length || lineValue[start] != '-' || lineValue[start + 1] != ' ' {
            return 1
        }

        if RemovalLineStartsWithAnyPackage(lineValue, start + 2, packageNames) {
            return 0
        }

        markerLimit := lineValue.Length - 7
        markerStart := start
        while markerStart <= markerLimit {
            if RemovalLineHasNugetMarkerAt(lineValue, markerStart)
                && RemovalLineStartsWithAnyPackage(lineValue, markerStart + 7, packageNames) {
                return 0
            }

            markerStart = markerStart + 1
        }

        return 1
    }

    static func RemovalLineStartsWithAnyPackage(
        lineValue: string,
        packageStart: int,
        packageNames: IReadOnlyList<string>): bool {
        i := 0
        while i < packageNames.Count {
            packageName := packageNames[i]
            if packageName == null {
                throw new InvalidOperationException("N# tidy dependency removal kernel received a null package name.")
            }

            if RemovalLineStartsWithPackage(lineValue, packageStart, packageName) {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func RemovalLineStartsWithPackage(lineValue: string, packageStart: int, packageName: string): bool {
        if packageStart + packageName.Length > lineValue.Length {
            return false
        }

        return TextSegmentEqualsIgnoreCase(lineValue, packageStart, packageName, 0, packageName.Length)
    }

    static func RemovalLineHasNugetMarkerAt(lineValue: string, start: int): bool {
        return TextSegmentEqualsIgnoreCase(lineValue, start, "nuget: ", 0, 7)
    }

    static func IsImportNamespaceChar(value: char): bool {
        return char.IsLetterOrDigit(value) || value == '.' || value == '_'
    }

    static func SubstringStartsWith(text: string, start: int, end: int, prefix: string): bool {
        if start < 0 || end > text.Length || end - start < prefix.Length {
            return false
        }

        index := 0
        while index < prefix.Length {
            if text[start + index] != prefix[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func TextSegmentEqualsIgnoreCase(
        left: string,
        leftStart: int,
        right: string,
        rightStart: int,
        length: int): bool {
        if leftStart < 0 || rightStart < 0 || length < 0 {
            return false
        }

        if leftStart + length > left.Length || rightStart + length > right.Length {
            return false
        }

        return String.Compare(left, leftStart, right, rightStart, length, StringComparison.OrdinalIgnoreCase) == 0
    }
}

namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

class TreeDependency {
    nameValue: string
    kindValue: string
    versionValue: string?
    scopeValue: string
    transitiveValue: bool
    dependenciesValue: IReadOnlyList<TreeDependency>

    Name: string => nameValue
    Kind: string => kindValue
    Version: string? => versionValue
    Scope: string => scopeValue
    Transitive: bool => transitiveValue
    Dependencies: IReadOnlyList<TreeDependency> => dependenciesValue

    constructor(Name: string, Kind: string, Version: string?, Scope: string, Transitive: bool, Dependencies: IReadOnlyList<TreeDependency>) {
        nameValue = Name
        kindValue = Kind
        versionValue = Version
        scopeValue = Scope
        transitiveValue = Transitive
        dependenciesValue = Dependencies
    }
}

class TreeOptionSummary {
    ProjectOption: string?
    DepthOption: string?
    Json: bool
    ShowHelp: bool

    constructor(projectOption: string?, depthOption: string?, json: bool, showHelp: bool) {
        ProjectOption = projectOption
        DepthOption = depthOption
        Json = json
        ShowHelp = showHelp
    }
}

class TreeCommandKernels {
    static func DeduplicateDependencies(dependencies: IReadOnlyList<TreeDependency>): TreeDependency[] {
        selected := new List<TreeDependency>()

        for dependency in dependencies {
            if !ContainsDependency(selected, dependency) {
                InsertDependencySorted(selected, dependency)
            }
        }

        return selected.ToArray()
    }

    static func DeduplicateTargetFrameworks(targetFrameworks: IReadOnlyList<string>): string[] {
        selected := new List<string>()

        for targetFramework in targetFrameworks {
            if !ContainsTargetFramework(selected, targetFramework) {
                selected.Add(targetFramework)
            }
        }

        return selected.ToArray()
    }

    static func GetOptionSummary(args: string[]): TreeOptionSummary {
        projectOption: string? = null
        depthOption: string? = null
        json := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            valueIndex := i + 1
            hasValue := valueIndex < args.Length

            if arg == "--project" {
                if projectOption == null && hasValue {
                    projectOption = args[valueIndex]
                }
            } else if arg == "--depth" {
                if depthOption == null && hasValue {
                    depthOption = args[valueIndex]
                }
            } else if arg == "--json" {
                json = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new TreeOptionSummary(projectOption, depthOption, json, showHelp)
    }

    static func GetMaxDepth(args: string[], defaultDepth: int): int {
        i := 0
        while i < args.Length - 1 {
            if args[i] == "--depth" {
                parsed := 0
                if TryParseInt32(args[i + 1], out parsed) {
                    return parsed
                }
            }

            i = i + 1
        }

        return defaultDepth
    }

    static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    static func GetHelpText(): string {
        return "N# Dependency Tree\n" + "\n" + "Usage: nlc tree [options]\n" + "\n" + "Show the project's dependencies and transitive NuGet packages when available.\n" + "\n" + "Options:\n" + "  --project <dir>   Project root directory (default: current directory)\n" + "  --depth <n>       Maximum tree depth to display\n" + "  --json            Output as JSON envelope\n" + "  --help, -h        Show this help text\n" + "\n" + "Examples:\n" + "  nlc tree\n" + "  nlc tree --depth 1\n" + "  nlc tree --json\n" + "\n" + "Behavior:\n" + "  project.yml projects list direct runtime dependencies without requiring .csproj files.\n" + "  Transitive NuGet dependencies are included when an MSBuild project file is present.\n" + "\n" + "Exit codes:\n" + "  0  Tree displayed successfully\n" + "  1  Failed to display tree"
    }

    static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    static func GetTreeFailedMessage(message: string): string {
        return "Tree failed: " + message
    }

    static func GetNoProjectFileMessage(): string {
        return "No project.yml or .csproj found. nlc tree reads direct dependencies from project.yml; transitive NuGet dependency output requires an MSBuild project file."
    }

    static func GetProjectYmlLimitationMessage(): string {
        return "project.yml output lists direct runtime dependencies only. Transitive NuGet dependencies require an MSBuild project file so dotnet can resolve the package graph."
    }

    static func GetTransitiveResolutionFailedLimitation(detail: string): string {
        return "Transitive NuGet dependency resolution through MSBuild failed: " + detail
    }

    static func GetDotnetRestoreRetryMessage(detail: string): string {
        return detail + " Run 'dotnet restore' and retry."
    }

    static func GetDotnetListFailedMessage(): string {
        return "dotnet list package failed."
    }

    static func GetProjectHeader(name: string, targetFramework: string): string {
        return name + " (" + targetFramework + ")"
    }

    static func GetNoDependenciesLine(): string {
        return "  (no dependencies)"
    }

    static func GetDependencyText(name: string, version: string?, kind: string): string {
        versionText := version ?? ""
        if versionText.Length == 0 {
            return name + " [" + kind + "]"
        }

        return name + "@" + versionText + " [" + kind + "]"
    }

    static func GetDependencyLine(isLast: bool, dependencyText: string): string {
        if isLast {
            return "└── " + dependencyText
        }

        return "├── " + dependencyText
    }

    static func GetTransitiveHeader(count: int): string {
        return "  transitive (" + count.ToString() + " packages):"
    }

    static func GetTransitiveDependencyLine(dependencyText: string): string {
        return "    " + dependencyText
    }

    static func GetLimitationsHeader(): string {
        return "Limitations:"
    }

    static func GetLimitationLine(limitation: string): string {
        return "  - " + limitation
    }

    static func TryParseInt32(text: string, out result: int): bool {
        start := 0
        end := text.Length
        while start < end && char.IsWhiteSpace(text[start]) {
            start = start + 1
        }

        while end > start && char.IsWhiteSpace(text[end - 1]) {
            end = end - 1
        }

        if start >= end {
            result = 0
            return false
        }

        negative := false
        if text[start] == '+' || text[start] == '-' {
            negative = text[start] == '-'
            start = start + 1
            if start >= end {
                result = 0
                return false
            }
        }

        value := 0
        index := start
        while index < end {
            ch := text[index]
            if ch < '0' || ch > '9' {
                result = 0
                return false
            }

            digit := ch - '0'
            if value > 214748364 {
                result = 0
                return false
            }

            if value == 214748364 {
                if negative {
                    if digit == 8 && index == end - 1 {
                        result = 0 - 2147483647 - 1
                        return true
                    }

                    result = 0
                    return false
                }

                if digit > 7 {
                    result = 0
                    return false
                }
            }

            value = value * 10 + digit
            index = index + 1
        }

        if negative {
            result = 0 - value
        } else {
            result = value
        }

        return true
    }

    static func ContainsDependency(dependencies: List<TreeDependency>, dependency: TreeDependency): bool {
        i := 0
        while i < dependencies.Count {
            current := dependencies[i]
            if String.Compare(current.Kind, dependency.Kind, StringComparison.Ordinal) == 0 && String.Compare(current.Name, dependency.Name, StringComparison.OrdinalIgnoreCase) == 0 {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func InsertDependencySorted(dependencies: List<TreeDependency>, dependency: TreeDependency) {
        index := 0
        while index < dependencies.Count && CompareDependencies(dependencies[index], dependency) <= 0 {
            index = index + 1
        }

        dependencies.Insert(index, dependency)
    }

    static func CompareDependencies(left: TreeDependency, right: TreeDependency): int {
        kindCompare := String.Compare(left.Kind, right.Kind, StringComparison.Ordinal)
        if kindCompare != 0 {
            return kindCompare
        }

        return String.Compare(left.Name, right.Name, StringComparison.OrdinalIgnoreCase)
    }

    static func ContainsTargetFramework(targetFrameworks: List<string>, targetFramework: string): bool {
        i := 0
        while i < targetFrameworks.Count {
            if String.Compare(targetFrameworks[i], targetFramework, StringComparison.OrdinalIgnoreCase) == 0 {
                return true
            }

            i = i + 1
        }

        return false
    }
}

namespace NSharpLang.Cli.Commands

public class TreeOptionSummary {
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

public class TreeCommandKernels {
    public static func GetOptionSummary(args: string[]): TreeOptionSummary {
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

    public static func GetMaxDepth(args: string[], defaultDepth: int): int {
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

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetHelpText(): string {
        return "N# Dependency Tree\n"
            + "\n"
            + "Usage: nlc tree [options]\n"
            + "\n"
            + "Show the project's dependencies and transitive NuGet packages when available.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project root directory (default: current directory)\n"
            + "  --depth <n>       Maximum tree depth to display\n"
            + "  --json            Output as JSON envelope\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc tree\n"
            + "  nlc tree --depth 1\n"
            + "  nlc tree --json\n"
            + "\n"
            + "Behavior:\n"
            + "  project.yml projects list direct runtime dependencies without requiring .csproj files.\n"
            + "  Transitive NuGet dependencies are included when an MSBuild project file is present.\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Tree displayed successfully\n"
            + "  1  Failed to display tree"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    public static func GetTreeFailedMessage(message: string): string {
        return "Tree failed: " + message
    }

    public static func GetNoProjectFileMessage(): string {
        return "No project.yml or .csproj found. nlc tree reads direct dependencies from project.yml; transitive NuGet dependency output requires an MSBuild project file."
    }

    public static func GetProjectYmlLimitationMessage(): string {
        return "project.yml output lists direct runtime dependencies only. Transitive NuGet dependencies require an MSBuild project file so dotnet can resolve the package graph."
    }

    public static func GetTransitiveResolutionFailedLimitation(detail: string): string {
        return "Transitive NuGet dependency resolution through MSBuild failed: " + detail
    }

    public static func GetDotnetRestoreRetryMessage(detail: string): string {
        return detail + " Run 'dotnet restore' and retry."
    }

    public static func GetDotnetListFailedMessage(): string {
        return "dotnet list package failed."
    }

    public static func GetProjectHeader(name: string, targetFramework: string): string {
        return name + " (" + targetFramework + ")"
    }

    public static func GetNoDependenciesLine(): string {
        return "  (no dependencies)"
    }

    public static func GetDependencyText(name: string, version: string?, kind: string): string {
        versionText := version ?? ""
        if versionText.Length == 0 {
            return name + " [" + kind + "]"
        }

        return name + "@" + versionText + " [" + kind + "]"
    }

    public static func GetDependencyLine(isLast: bool, dependencyText: string): string {
        if isLast {
            return "└── " + dependencyText
        }

        return "├── " + dependencyText
    }

    public static func GetTransitiveHeader(count: int): string {
        return "  transitive (" + count.ToString() + " packages):"
    }

    public static func GetTransitiveDependencyLine(dependencyText: string): string {
        return "    " + dependencyText
    }

    public static func GetLimitationsHeader(): string {
        return "Limitations:"
    }

    public static func GetLimitationLine(limitation: string): string {
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
}

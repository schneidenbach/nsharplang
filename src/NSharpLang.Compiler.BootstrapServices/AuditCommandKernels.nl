namespace NSharpLang.Cli.Commands

public class AuditOptionSummary {
    ProjectOption: string?
    Json: bool
    ShowHelp: bool

    constructor(projectOption: string?, json: bool, showHelp: bool) {
        ProjectOption = projectOption
        Json = json
        ShowHelp = showHelp
    }
}

public class AuditCommandKernels {
    public static func GetOptionSummary(args: string[]): AuditOptionSummary {
        projectOption: string? = null
        json := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--project" {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            } else if arg == "--json" {
                json = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new AuditOptionSummary(projectOption, json, showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetHelpText(): string {
        return "N# Security Audit\n"
            + "\n"
            + "Usage: nlc audit [options]\n"
            + "\n"
            + "Check dependencies for known security vulnerabilities.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project root directory (default: current directory)\n"
            + "  --json            Output as JSON envelope\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc audit\n"
            + "  nlc audit --json\n"
            + "  nlc audit --project examples/14-minimal-api\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  No vulnerabilities found\n"
            + "  1  Vulnerabilities found or audit failed"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    public static func GetNoCsprojFileMessage(): string {
        return "No .csproj file found. Run 'nlc init' to create one."
    }

    public static func GetVulnerableFlagUnsupportedMessage(): string {
        return "The --vulnerable flag requires .NET SDK 8.0 or later."
    }

    public static func GetFailedMessage(message: string): string {
        return "Audit failed: " + message
    }

    public static func GetNoKnownVulnerabilitiesMessage(): string {
        return "No known vulnerabilities found."
    }

    public static func GetVulnerabilitySummaryMessage(vulnerabilityCount: int): string {
        suffix := "ies"
        if vulnerabilityCount == 1 {
            suffix = "y"
        }

        return vulnerabilityCount.ToString() + " vulnerabilit" + suffix + " found:"
    }

    public static func GetVulnerabilityLine(severity: string, packageId: string, version: string): string {
        return "  " + severity + ": " + packageId + "@" + version
    }

    public static func GetVulnerabilityUrlLine(url: string): string {
        return "    " + url
    }

    public static func GetParseFailureMessage(): string {
        return "  (could not parse vulnerability details)"
    }
}

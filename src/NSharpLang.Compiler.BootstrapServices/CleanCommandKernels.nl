namespace NSharpLang.Cli.Commands

public class CleanOptionSummary {
    ProjectOption: string?
    CleanAll: bool
    ShowHelp: bool

    constructor(projectOption: string?, cleanAll: bool, showHelp: bool) {
        ProjectOption = projectOption
        CleanAll = cleanAll
        ShowHelp = showHelp
    }
}

public class CleanCommandKernels {
    public static func GetOptionSummary(args: string[]): CleanOptionSummary {
        projectOption: string? = null
        cleanAll := false
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
            } else if arg == "--all" {
                cleanAll = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new CleanOptionSummary(projectOption, cleanAll, showHelp)
    }

    public static func GetHelpText(): string {
        return "N# Clean\n"
            + "\n"
            + "Usage: nlc clean [options]\n"
            + "\n"
            + "Remove local build artifacts for the current project. Equivalent to `cargo clean`\n"
            + "or `go clean`.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project root directory (default: current directory)\n"
            + "  --all             Also clear NuGet caches\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc clean\n"
            + "  nlc clean --all\n"
            + "  nlc clean --project examples/16-task-cli\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Clean completed successfully\n"
            + "  1  Clean failed"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    public static func GetNoArtifactsFoundMessage(projectRoot: string): string {
        return "No build artifacts found under " + projectRoot + "."
    }

    public static func GetRemovedArtifactsHeader(count: int): string {
        if count == 1 {
            return "Removed 1 build artifact directory:"
        }

        return "Removed " + count.ToString() + " build artifact directories:"
    }

    public static func GetRemovedArtifactLine(path: string): string {
        return "  " + path
    }

    public static func GetClearedNuGetCachesMessage(): string {
        return "Cleared NuGet caches."
    }

    public static func GetClearNuGetCachesFailedMessage(detail: string): string {
        if detail.Length == 0 {
            return "Failed to clear NuGet caches."
        }

        return "Failed to clear NuGet caches.\n" + detail
    }

    public static func GetCleanFailedMessage(message: string): string {
        return "Clean failed: " + message
    }
}

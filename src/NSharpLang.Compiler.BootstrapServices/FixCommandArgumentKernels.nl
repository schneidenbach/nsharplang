namespace NSharpLang.Cli.Commands

import System.IO

public class FixArgumentSummary {
    ProjectOption: string?
    FileOption: string?
    PositionalProject: string?
    DryRun: bool
    UseText: bool
    IncludeReviewNeeded: bool
    ShowHelp: bool

    constructor(
        projectOption: string?,
        fileOption: string?,
        positionalProject: string?,
        dryRun: bool,
        useText: bool,
        includeReviewNeeded: bool,
        showHelp: bool) {
        ProjectOption = projectOption
        FileOption = fileOption
        PositionalProject = positionalProject
        DryRun = dryRun
        UseText = useText
        IncludeReviewNeeded = includeReviewNeeded
        ShowHelp = showHelp
    }
}

public class FixCommandArgumentKernels {
    public static func GetArgumentSummary(args: string[]): FixArgumentSummary {
        projectOption: string? = null
        fileOption: string? = null
        positionalProject: string? = null
        dryRun := false
        useText := false
        includeReviewNeeded := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            kind := GetArgumentKind(arg)

            if i == 0 && arg == "help" {
                showHelp = true
            }

            if kind == 1 {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            } else if kind == 2 {
                if fileOption == null && i + 1 < args.Length {
                    fileOption = args[i + 1]
                }
            } else if kind == 3 {
                dryRun = true
            } else if kind == 4 {
                useText = true
            } else if kind == 5 {
                includeReviewNeeded = true
            } else if kind == 6 {
                showHelp = true
            }

            i = i + 1
        }

        i = 0
        while i < args.Length {
            arg := args[i]
            kind := GetArgumentKind(arg)
            if kind == 1 || kind == 2 {
                if i + 1 < args.Length {
                    i = i + 2
                } else {
                    i = i + 1
                }

                continue
            }

            if arg.Length == 0 || arg[0] != '-' {
                positionalProject = arg
                break
            }

            i = i + 1
        }

        return new FixArgumentSummary(
            projectOption,
            fileOption,
            positionalProject,
            dryRun,
            useText,
            includeReviewNeeded,
            showHelp)
    }

    public static func GetEffectiveOutputMode(useText: bool): int {
        if useText {
            return 2
        }

        return 1
    }

    static func GetArgumentKind(arg: string): int {
        if arg == "--project" {
            return 1
        }

        if arg == "--file" {
            return 2
        }

        if arg == "--dry-run" {
            return 3
        }

        if arg == "--text" {
            return 4
        }

        if arg == "--include-review-needed" {
            return 5
        }

        if arg == "--help" || arg == "-h" {
            return 6
        }

        return 0
    }
}

public class CheckArgumentSummary {
    ProjectOption: string?
    BackendOption: string?
    PositionalProject: string?
    UseText: bool
    Aot: bool
    SystemsReport: bool
    ShowHelp: bool

    constructor(
        projectOption: string?,
        backendOption: string?,
        positionalProject: string?,
        useText: bool,
        aot: bool,
        systemsReport: bool,
        showHelp: bool) {
        ProjectOption = projectOption
        BackendOption = backendOption
        PositionalProject = positionalProject
        UseText = useText
        Aot = aot
        SystemsReport = systemsReport
        ShowHelp = showHelp
    }
}

public class CheckCommandKernels {
    public static func GetArgumentSummary(args: string[]): CheckArgumentSummary {
        projectOption: string? = null
        backendOption: string? = null
        positionalProject: string? = null
        useText := false
        aot := false
        systemsReport := false
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
            } else if arg == "--backend" {
                if backendOption == null && i + 1 < args.Length {
                    backendOption = args[i + 1]
                }
            } else if arg == "--text" {
                useText = true
            } else if arg == "--aot" {
                aot = true
            } else if arg == "--systems-report" {
                systemsReport = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        i = 0
        while i < args.Length {
            arg := args[i]
            if arg == "--project" || arg == "--backend" {
                if i + 1 < args.Length {
                    i = i + 2
                    continue
                }
            }

            if arg.Length == 0 || arg[0] != '-' {
                positionalProject = arg
                break
            }

            i = i + 1
        }

        return new CheckArgumentSummary(
            projectOption,
            backendOption,
            positionalProject,
            useText,
            aot,
            systemsReport,
            showHelp)
    }

    public static func GetEffectiveOutputMode(useText: bool, systemsReport: bool): int {
        if useText {
            if systemsReport {
                return -1
            }

            return 2
        }

        if systemsReport {
            return 3
        }

        return 1
    }

    public static func GetProjectDirectory(projectOption: string?, positionalProject: string?, currentDirectory: string): string {
        if !string.IsNullOrWhiteSpace(projectOption ?? "") {
            return Path.GetFullPath(projectOption ?? "")
        }

        return Path.GetFullPath(positionalProject ?? currentDirectory)
    }

    public static func GetProjectYmlPath(projectDir: string): string {
        return Path.Combine(projectDir, "project.yml")
    }

    public static func ShouldVerifyIlOutput(errorCount: int, sourceFileCount: int, hasProjectFile: bool): bool {
        return errorCount == 0 && sourceFileCount > 0 && hasProjectFile
    }

    public static func GetVerificationOutputPath(tempDir: string, assemblyName: string): string {
        return Path.Combine(tempDir, assemblyName + ".dll")
    }

    public static func GetVerificationTempDirectory(tempRoot: string, uniqueName: string): string {
        return Path.Combine(tempRoot, "nlc-check-il-" + uniqueName)
    }

    public static func GetExitCode(errorCount: int): int {
        if errorCount > 0 {
            return 1
        }

        return 0
    }

    public static func GetHelpText(): string {
        return "N# Type Check\n"
            + "\n"
            + "Usage: nlc check [options] [project-dir]\n"
            + "\n"
            + "Verifies your N# project compiles without errors. Runs semantic analysis,\n"
            + "linting, and IL backend verification.\n"
            + "\n"
            + "Options:\n"
            + "  --backend <mode>  Compilation backend: il\n"
            + "  --json        Output as JSON (default)\n"
            + "  --text        Output as human-readable diagnostics\n"
            + "  --aot         Report Native AOT blockers as errors\n"
            + "  --systems-report\n"
            + "                Output the versioned Systems N# effect/policy report as JSON\n"
            + "  --project     Project root directory (default: current directory)\n"
            + "  --help, -h    Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc check\n"
            + "  nlc check --backend il\n"
            + "  nlc check --text\n"
            + "  nlc check --aot\n"
            + "  nlc check --project examples/16-task-cli\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  No errors found\n"
            + "  1  One or more errors detected"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectDir: string): string {
        return "Directory not found: " + projectDir
    }

    public static func GetSystemsReportTextUnavailableMessage(): string {
        return "--systems-report is only available as JSON output."
    }

    public static func GetNoErrorsMessage(fileCount: int, elapsedText: string): string {
        suffix := "s"
        if fileCount == 1 {
            suffix = ""
        }

        return "  Checked " + fileCount.ToString() + " file" + suffix + " — no errors. [" + elapsedText + "]"
    }

    public static func GetCheckedInMessage(elapsedText: string): string {
        return "  Checked in " + elapsedText
    }

    public static func GetFailedElapsedMessage(elapsedText: string): string {
        return "  Check failed in " + elapsedText
    }

    public static func GetFailedMessage(message: string): string {
        return "Check failed: " + message
    }
}

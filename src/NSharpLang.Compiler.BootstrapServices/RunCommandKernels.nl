namespace NSharpLang.Cli

import System.IO

public class RunOptionSummary {
    BackendOption: string?
    ShowHelp: bool

    constructor(backendOption: string?, showHelp: bool) {
        BackendOption = backendOption
        ShowHelp = showHelp
    }
}

public class RunCommandKernels {
    public static func GetOptionSummary(args: string[]): RunOptionSummary {
        backendOption: string? = null
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            if arg == "--backend" {
                if backendOption == null && i + 1 < args.Length {
                    backendOption = args[i + 1]
                }
            }

            i = i + 1
        }

        return new RunOptionSummary(backendOption, showHelp)
    }

    public static func GetSourceOperand(args: string[]): string? {
        i := 0
        while i < args.Length {
            if args[i] == "--backend" && i + 1 < args.Length {
                i = i + 2
                continue
            }

            return args[i]
        }

        return null
    }

    public static func GetHelpText(): string {
        return "N# Run\n"
            + "\n"
            + "Usage: nlc run [file.nl]\n"
            + "\n"
            + "Build and run either the current project or a single N# source file.\n"
            + "\n"
            + "Options:\n"
            + "  --backend <mode>   Compilation backend: il\n"
            + "  --define <symbol>  Define a conditional-compilation symbol for #if (-d shorthand);\n"
            + "                     repeatable, and accepts comma-separated lists\n"
            + "  --help, -h         Show this help text\n"
            + "\n"
            + "Conditional compilation:\n"
            + "  DEBUG is defined automatically when running (a debug build).\n"
            + "  Project-wide symbols can also be set via 'defines:' in project.yml.\n"
            + "\n"
            + "Examples:\n"
            + "  nlc run\n"
            + "  nlc run --backend il\n"
            + "  nlc run Program.nl\n"
            + "  nlc run --define FEATURE_X\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Program ran successfully\n"
            + "  1  Build or execution failed"
    }

    public static func GetFileNotFoundMessage(sourceFile: string): string {
        return "File not found: " + sourceFile
    }

    public static func GetSourceStartingMessage(sourceFile: string): string {
        return "Running " + sourceFile + "..."
    }

    public static func GetProjectRoot(currentDirectory: string): string {
        return currentDirectory
    }

    public static func GetSourceDirectory(sourceFile: string, currentDirectory: string): string {
        return Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? currentDirectory
    }

    public static func GetMissingProjectFileMessage(): string {
        return "No project.yml found in current directory. Run 'nlc new <name>' to create a project."
    }

    public static func GetLibraryProjectMessage(): string {
        return "Cannot run a library project."
    }

    public static func GetProjectStartingMessage(): string {
        return "Running..."
    }

    public static func GetSingleFileBackendStartMessage(sourceFile: string): string {
        return "Running " + sourceFile + " with the IL backend..."
    }

    public static func GetLibrarySourceFileMessage(): string {
        return "Cannot run a library source file."
    }

    public static func GetFailedMessage(message: string): string {
        return "Run failed: " + message
    }
}

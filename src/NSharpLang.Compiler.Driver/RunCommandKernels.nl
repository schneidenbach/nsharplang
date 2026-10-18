namespace NSharpLang.Cli

import System
import System.IO
import NSharpLang.Compiler

class RunOptionSummary {
    BackendOption: string?
    ShowHelp: bool

    constructor(backendOption: string?, showHelp: bool) {
        BackendOption = backendOption
        ShowHelp = showHelp
    }
}

class RunCommandKernels {
    static func GetOptionSummary(args: string[]): RunOptionSummary {
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

    // The `--` separator ends nlc's own arguments, exactly as it does for `--no-daemon`: everything
    // after it belongs to the program being run, so a program flag such as `--help` or `--project`
    // is never read as an nlc option.
    static func GetSeparatorIndex(args: string[]): int {
        i := 0
        while i < args.Length {
            if args[i] == "--" {
                return i
            }

            i = i + 1
        }

        return -1
    }

    static func GetLauncherArguments(args: string[]): string[] {
        separator := GetSeparatorIndex(args)
        if separator < 0 {
            return args
        }

        launcher := new string[](separator)
        Array.Copy(args, launcher, separator)
        return launcher
    }

    static func GetProgramArguments(args: string[]): string[] {
        separator := GetSeparatorIndex(args)
        if separator < 0 {
            return new string[](0)
        }

        program := new string[](args.Length - separator - 1)
        Array.Copy(args, separator + 1, program, 0, program.Length)
        return program
    }

    static func GetProjectOption(args: string[]): string? {
        i := 0
        while i < args.Length {
            if args[i] == "--project" && i + 1 < args.Length && !args[i + 1].StartsWith("--") {
                return args[i + 1]
            }

            i = i + 1
        }

        return null
    }

    // `--project` is the last argument, so there is no directory to resolve.
    static func IsProjectOptionMissingValue(args: string[]): bool {
        i := 0
        while i < args.Length {
            if args[i] == "--project" {
                return i + 1 >= args.Length || args[i + 1].StartsWith("--")
            }

            i = i + 1
        }

        return false
    }

    static func GetSourceOperand(args: string[]): string? {
        i := 0
        while i < args.Length {
            if args[i] == "--backend" && i + 1 < args.Length {
                i = i + 2
                continue
            }

            if args[i] == "--project" {
                i = i + 2
                continue
            }

            // A colour flag is an option, not the file to run.
            if DiagnosticColorPolicy.IsColorOption(args[i]) {
                i = i + 1
                continue
            }

            return args[i]
        }

        return null
    }

    static func GetHelpText(): string {
        return "N# Run\n" + "\n" + "Usage: nlc run [file.nl | --project <dir>] [options] [-- <program arguments>]\n" + "\n" + "Build and run a project (the current directory, or --project) or a single N# source file.\n" + "Everything after -- is passed to the program unchanged.\n" + "\n" + "Options:\n" + "  --backend <mode>   Compilation backend: il\n" + "  --project <dir>    Project root directory (default: current directory); the program\n" + "                     runs with that directory as its working directory\n" + "  --define <symbol>  Define a conditional-compilation symbol for #if (-d shorthand);\n" + "                     repeatable, and accepts comma-separated lists\n" + "  --color=<when>     Colour diagnostics: auto (default), always, never\n" + "  --help, -h         Show this help text\n" + "\n" + "Conditional compilation:\n" + "  DEBUG is defined automatically when running (a debug build).\n" + "  Project-wide symbols can also be set via 'defines:' in project.yml.\n" + "\n" + "Examples:\n" + "  nlc run\n" + "  nlc run --backend il\n" + "  nlc run --project src/App\n" + "  nlc run Program.nl\n" + "  nlc run --project src/App -- --port 8080\n" + "  nlc run --define FEATURE_X\n" + "\n" + "Exit codes:\n" + "  0  Program ran successfully\n" + "  1  Build or execution failed"
    }

    static func GetSourceStartingMessage(sourceFile: string): string {
        return "Running " + sourceFile + "..."
    }

    static func GetProjectRoot(currentDirectory: string): string {
        return currentDirectory
    }

    static func GetSourceDirectory(sourceFile: string, currentDirectory: string): string {
        return Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? currentDirectory
    }

    static func GetProjectAndFileConflictMessage(): string {
        return "Cannot combine --project with a source file. Use 'nlc run --project <dir>' or 'nlc run <file.nl>'."
    }

    static func GetMissingProjectFileAtMessage(projectRoot: string): string {
        return "No project.yml found in " + projectRoot + ". Run 'nlc new <name>' to create a project."
    }

    static func GetProjectOptionMissingValueMessage(): string {
        return "--project requires a directory."
    }

    // The `dotnet` argument vector that starts the built assembly with the program's own arguments.
    static func GetLaunchArguments(assemblyPath: string, programArguments: string[]): string[] {
        launch := new string[](programArguments.Length + 1)
        launch[0] = assemblyPath
        Array.Copy(programArguments, 0, launch, 1, programArguments.Length)
        return launch
    }

    static func GetMissingProjectFileMessage(): string {
        return "No project.yml found in current directory. Run 'nlc new <name>' to create a project."
    }

    static func GetLibraryProjectMessage(): string {
        return "Cannot run a library project."
    }

    static func GetProjectStartingMessage(): string {
        return "Running..."
    }

    static func GetSingleFileBackendStartMessage(sourceFile: string): string {
        return "Running " + sourceFile + " with the IL backend..."
    }

    static func GetLibrarySourceFileMessage(): string {
        return "Cannot run a library source file."
    }

    static func GetFailedMessage(message: string): string {
        return "Run failed: " + message
    }
}

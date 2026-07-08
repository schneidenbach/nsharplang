namespace NSharpLang.Cli.Commands

import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

public class LintOptionSummary {
    ProjectOption: string?
    UseText: bool
    UseJson: bool
    ShowHelp: bool

    constructor(projectOption: string?, useText: bool, useJson: bool, showHelp: bool) {
        ProjectOption = projectOption
        UseText = useText
        UseJson = useJson
        ShowHelp = showHelp
    }
}

public class LintCommandKernels {
    public static func GetOptionSummary(args: string[]): LintOptionSummary {
        projectOption: string? = null
        useText := false
        useJson := false
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
            } else if arg == "--text" {
                useText = true
            } else if arg == "--json" {
                useJson = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new LintOptionSummary(projectOption, useText, useJson, showHelp)
    }

    public static func GetFileArgs(args: string[]): string[] {
        projectValueCount := CountProjectOptionValues(args)
        projectValues := new string[](projectValueCount)

        projectValueIndex := 0
        i := 0
        while i < args.Length - 1 {
            if args[i] == "--project" {
                projectValues[projectValueIndex] = args[i + 1]
                projectValueIndex = projectValueIndex + 1
                i = i + 2
                continue
            }

            i = i + 1
        }

        count := CountFileArgs(args, projectValues)
        files := new string[](count)

        resultIndex := 0
        i = 0
        while i < args.Length {
            arg := args[i]
            if IsLintFileArg(arg, projectValues) {
                files[resultIndex] = arg
                resultIndex = resultIndex + 1
            }

            i = i + 1
        }

        return files
    }

    public static func GetEffectiveOutputMode(useText: bool, useJson: bool): int {
        if useJson {
            return 1
        }

        if useText {
            return 2
        }

        return 1
    }

    public static func GetProjectRoot(projectOption: string?, currentDirectory: string): string {
        return Path.GetFullPath(projectOption ?? currentDirectory)
    }

    public static func GetSourceFilePath(sourceFile: string): string {
        return Path.GetFullPath(sourceFile)
    }

    public static func ResolveFilePath(projectRoot: string, filePath: string): string {
        if Path.IsPathRooted(filePath) {
            return Path.GetFullPath(filePath)
        }

        return Path.GetFullPath(Path.Combine(projectRoot, filePath))
    }

    public static func GetRelativePath(projectRoot: string, filePath: string): string {
        relativePath := Path.GetRelativePath(projectRoot, filePath)
        return OutputFormatterNormalizationKernels.NormalizePath(relativePath) ?? relativePath
    }

    public static func GetFileDirectory(projectRoot: string, filePath: string): string {
        return Path.GetDirectoryName(Path.GetFullPath(filePath)) ?? projectRoot
    }

    public static func GetExitCode(hadErrors: bool, diagnosticErrorCount: int): int {
        if hadErrors || diagnosticErrorCount > 0 {
            return 1
        }

        return 0
    }

    public static func GetHelpText(): string {
        return "N# Lint\n"
            + "\n"
            + "Usage: nlc lint [options] [files...]\n"
            + "\n"
            + "Run static analysis rules on N# source files. Error-severity lints are\n"
            + "also included in 'nlc check' and block project builds.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project root directory (default: current directory)\n"
            + "  --json            Output as JSON (default)\n"
            + "  --text            Output as human-readable diagnostics\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Lint Rules:\n"
            + "  NL001  error     Unused variable\n"
            + "  NL002  error     Missing import\n"
            + "  NL003  error     Unnecessary null check on value type\n"
            + "  NL004  error     Async function without await\n"
            + "  NL006  error     Unreachable code\n"
            + "  NL010  error     Unused import\n"
            + "  NL011  error     Empty catch block\n"
            + "  NL012  error     Unused parameter\n"
            + "  NL016  error     Redundant null check\n"
            + "  NL020  error     Shadowed variable\n"
            + "\n"
            + "Inline Suppression:\n"
            + "  // nlc:ignore NL001\n"
            + "  unusedVar := 42\n"
            + "\n"
            + "Examples:\n"
            + "  nlc lint\n"
            + "  nlc lint --json\n"
            + "  nlc lint --text\n"
            + "  nlc lint Program.nl\n"
            + "  nlc lint --project examples/16-task-cli\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  No errors found\n"
            + "  1  One or more errors were reported"
    }

    public static func GetSeverityText(severity: DiagnosticSeverity): string {
        if severity == DiagnosticSeverity.Error {
            return "error"
        }

        if severity == DiagnosticSeverity.Warning {
            return "warning"
        }

        return "info"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Directory not found: " + projectRoot
    }

    public static func GetNoFilesFoundMessage(): string {
        return "No .nl files found. Ensure you are in a project directory or specify files explicitly."
    }

    public static func GetFileNotFoundMessage(sourceFile: string): string {
        return "File not found: " + sourceFile
    }

    public static func GetParseErrorsMessage(sourceFile: string, messages: string): string {
        return "Parse errors in " + sourceFile + ": " + messages
    }

    public static func GetErrorLintingDiagnosticMessage(exceptionMessage: string): string {
        return "Error linting: " + exceptionMessage
    }

    public static func GetErrorLintingFileMessage(sourceFile: string, exceptionMessage: string): string {
        return "Error linting " + sourceFile + ": " + exceptionMessage
    }

    public static func GetNoIssuesMessage(fileCount: int, elapsedText: string): string {
        suffix := "s"
        if fileCount == 1 {
            suffix = ""
        }

        return "  Linted " + fileCount.ToString() + " file" + suffix + " — no issues. [" + elapsedText + "]"
    }

    public static func GetLintedInMessage(elapsedText: string): string {
        return "  Linted in " + elapsedText
    }

    public static func GetFailedMessage(exceptionMessage: string): string {
        return "Lint failed: " + exceptionMessage
    }

    static func CountProjectOptionValues(args: string[]): int {
        count := 0
        i := 0
        while i < args.Length - 1 {
            if args[i] == "--project" {
                count = count + 1
                i = i + 2
                continue
            }

            i = i + 1
        }

        return count
    }

    static func CountFileArgs(args: string[], projectValues: string[]): int {
        count := 0
        i := 0
        while i < args.Length {
            if IsLintFileArg(args[i], projectValues) {
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    static func IsLintFileArg(arg: string, projectValues: string[]): bool {
        if arg == "help" {
            return false
        }

        if arg.Length > 0 && arg[0] == '-' {
            return false
        }

        i := 0
        while i < projectValues.Length {
            if projectValues[i] == arg {
                return false
            }

            i = i + 1
        }

        return true
    }
}

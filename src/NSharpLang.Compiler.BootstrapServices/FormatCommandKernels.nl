namespace NSharpLang.Cli

import System
import System.Text

public class FormatOptionSummary {
    projectOptionValue: string?
    verifyOnlyValue: bool
    diffOnlyValue: bool
    stdinModeValue: bool
    showHelpValue: bool

    ProjectOption: string? => projectOptionValue
    VerifyOnly: bool => verifyOnlyValue
    DiffOnly: bool => diffOnlyValue
    StdinMode: bool => stdinModeValue
    ShowHelp: bool => showHelpValue

    constructor(
        projectOption: string?,
        verifyOnly: bool,
        diffOnly: bool,
        stdinMode: bool,
        showHelp: bool) {
        projectOptionValue = projectOption
        verifyOnlyValue = verifyOnly
        diffOnlyValue = diffOnly
        stdinModeValue = stdinMode
        showHelpValue = showHelp
    }
}

public class FormatCommandKernels {
    public static func GetOptionSummary(args: string[]): FormatOptionSummary {
        projectOption: string? = null
        verifyOnly := false
        diffOnly := false
        stdinMode := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--help" {
                showHelp = true
            } else if arg == "-h" {
                showHelp = true
            }

            if arg == "--project" {
                if projectOption == null {
                    next := i + 1
                    if next < args.Length {
                        projectOption = args[next]
                    }
                }
            }

            if arg == "--check" {
                verifyOnly = true
            } else if arg == "--verify-no-changes" {
                verifyOnly = true
            }

            if arg == "--diff" {
                diffOnly = true
            }

            if arg == "--stdin" {
                stdinMode = true
            }

            i = i + 1
        }

        return new FormatOptionSummary(projectOption, verifyOnly, diffOnly, stdinMode, showHelp)
    }

    public static func GetHelpText(): string {
        builder := new StringBuilder()
        AppendLine(builder, "N# Format")
        AppendLine(builder, "")
        AppendLine(builder, "Usage: nlc format [options] [files...]")
        AppendLine(builder, "")
        AppendLine(builder, "Format N# source files with the canonical formatter.")
        AppendLine(builder, "")
        AppendLine(builder, "Options:")
        AppendLine(builder, "  --project <dir>         Project root directory (default: current directory)")
        AppendLine(builder, "  --check                 Exit with code 1 if any file needs formatting")
        AppendLine(builder, "  --verify-no-changes     Back-compat alias for --check")
        AppendLine(builder, "  --diff                  Print unified diffs instead of writing files")
        AppendLine(builder, "  --stdin                 Read source from stdin and write the formatted result to stdout")
        AppendLine(builder, "  --help, -h              Show this help text")
        AppendLine(builder, "")
        AppendLine(builder, "Examples:")
        AppendLine(builder, "  nlc format")
        AppendLine(builder, "  nlc format --check")
        AppendLine(builder, "  nlc format --diff Program.nl")
        AppendLine(builder, "  nlc format --stdin < Program.nl")
        AppendLine(builder, "")
        AppendLine(builder, "Exit codes:")
        AppendLine(builder, "  0  Formatting succeeded")
        builder.Append("  1  Formatting failed or --check found unformatted files")
        return builder.ToString()
    }

    public static func GetStdinWithFilesMessage(): string {
        return "Cannot combine --stdin with file arguments."
    }

    public static func GetNoFilesFoundMessage(): string {
        return "No .nl files found to format."
    }

    public static func GetFileNotFoundMessage(sourceFile: string): string {
        return "File not found: " + sourceFile
    }

    public static func GetErrorFormattingMessage(sourceFile: string, exceptionMessage: string): string {
        return "Error formatting " + sourceFile + ": " + exceptionMessage
    }

    public static func GetWarningLine(relativePath: string, warning: string): string {
        return "Warning [" + relativePath + "]: " + warning
    }

    public static func GetSafetyCheckFailedMessage(warnings: string): string {
        return "Formatter safety check failed: " + warnings
    }

    public static func GetCheckFailedHeader(count: int): string {
        return "Formatting check failed for " + count.ToString() + " file(s):"
    }

    public static func GetCheckFailedPathLine(sourceFile: string): string {
        return "  " + sourceFile
    }

    public static func GetAllFilesFormattedMessage(): string {
        return "All files are properly formatted."
    }

    public static func GetFormattedCountMessage(count: int): string {
        return "Formatted " + count.ToString() + " file(s)."
    }

    public static func GetFailedMessage(exceptionMessage: string): string {
        return "Format failed: " + exceptionMessage
    }

    public static func GetParseErrorsMessage(relativePath: string, messages: string): string {
        return "Parse errors in " + relativePath + ": " + messages
    }

    public static func ShouldFormatDiscoveredPath(relativePath: string): bool {
        if PathEndsWithTestsNl(relativePath) {
            return false
        }

        previousWasTestRoot := false
        segmentStart := 0
        i := 0

        while i <= relativePath.Length {
            atEnd := i == relativePath.Length
            isSeparator := false
            if !atEnd {
                ch := relativePath[i]
                if ch == '/' {
                    isSeparator = true
                } else if ch == '\\' {
                    isSeparator = true
                }
            }

            if atEnd || isSeparator {
                if i > segmentStart {
                    if FormatPathSegmentIsExcluded(relativePath, segmentStart, i) {
                        return false
                    }

                    if previousWasTestRoot && FormatPathSegmentEquals(relativePath, segmentStart, i, "fixtures") {
                        return false
                    }

                    previousWasTestRoot = false
                    if FormatPathSegmentEquals(relativePath, segmentStart, i, "test") {
                        previousWasTestRoot = true
                    } else if FormatPathSegmentEquals(relativePath, segmentStart, i, "tests") {
                        previousWasTestRoot = true
                    }
                }

                segmentStart = i + 1
            }

            i = i + 1
        }

        return true
    }

    public static func ShouldSkipDiscoveredDirectoryName(directoryName: string): bool {
        return FormatPathSegmentIsExcluded(directoryName, 0, directoryName.Length)
    }

    static func FormatPathSegmentIsExcluded(text: string, start: int, end: int): bool {
        length := end - start
        if length == 3 {
            if FormatPathSegmentEquals(text, start, end, ".hg") {
                return true
            }

            if FormatPathSegmentEquals(text, start, end, "bin") {
                return true
            }

            return FormatPathSegmentEquals(text, start, end, "obj")
        }

        if length == 4 {
            if FormatPathSegmentEquals(text, start, end, ".git") {
                return true
            }

            if FormatPathSegmentEquals(text, start, end, ".svn") {
                return true
            }

            return FormatPathSegmentEquals(text, start, end, ".nlc")
        }

        if length == 7 {
            return FormatPathSegmentEquals(text, start, end, ".hermes")
        }

        if length == 10 {
            return FormatPathSegmentEquals(text, start, end, ".worktrees")
        }

        if length == 12 {
            return FormatPathSegmentEquals(text, start, end, "node_modules")
        }

        return false
    }

    static func PathEndsWithTestsNl(text: string): bool {
        return PathEndsWithAsciiIgnoreCase(text, ".tests.nl")
    }

    static func PathEndsWithAsciiIgnoreCase(text: string, suffix: string): bool {
        if text.Length < suffix.Length {
            return false
        }

        start := text.Length - suffix.Length
        return PathSubstringEqualsAsciiIgnoreCase(text, start, text.Length, suffix)
    }

    static func FormatPathSegmentEquals(text: string, start: int, end: int, value: string): bool {
        return PathSubstringEqualsAsciiIgnoreCase(text, start, end, value)
    }

    static func PathSubstringEqualsAsciiIgnoreCase(text: string, start: int, end: int, value: string): bool {
        length := end - start
        if length != value.Length {
            return false
        }

        i := 0
        while i < value.Length {
            if !PathCharsEqualAsciiIgnoreCase(text[start + i], value[i]) {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func PathCharsEqualAsciiIgnoreCase(left: char, right: char): bool {
        leftCode := (int)left
        rightCode := (int)right

        if left >= 'A' {
            if left <= 'Z' {
                leftCode = leftCode + 32
            }
        }

        if right >= 'A' {
            if right <= 'Z' {
                rightCode = rightCode + 32
            }
        }

        return leftCode == rightCode
    }

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }
}

namespace NSharpLang.Cli.Commands

import System

public class WatchOptionSummary {
    ProjectOption: string?
    DebounceMsOption: string?
    MaxRunsOption: string?
    ShowHelp: bool

    constructor(projectOption: string?, debounceMsOption: string?, maxRunsOption: string?, showHelp: bool) {
        ProjectOption = projectOption
        DebounceMsOption = debounceMsOption
        MaxRunsOption = maxRunsOption
        ShowHelp = showHelp
    }
}

public class WatchTargetSummary {
    TargetKind: int

    constructor(targetKind: int) {
        TargetKind = targetKind
    }
}

public class WatchPositiveIntOption {
    IsValid: bool
    HasValue: bool
    Value: int

    constructor(isValid: bool, hasValue: bool, value: int) {
        IsValid = isValid
        HasValue = hasValue
        Value = value
    }
}

public class WatchCommandKernels {
    public static func GetTargetSummary(args: string[]): WatchTargetSummary {
        targetKind := 0
        if args.Length == 0 {
            return new WatchTargetSummary(targetKind)
        }

        firstArg := args[0]
        if String.Compare(firstArg, "check", StringComparison.OrdinalIgnoreCase) == 0 {
            targetKind = 1
        } else if String.Compare(firstArg, "build", StringComparison.OrdinalIgnoreCase) == 0 {
            targetKind = 2
        } else if String.Compare(firstArg, "test", StringComparison.OrdinalIgnoreCase) == 0 {
            targetKind = 3
        } else if String.Compare(firstArg, "lint", StringComparison.OrdinalIgnoreCase) == 0 {
            targetKind = 4
        } else if String.Compare(firstArg, "format", StringComparison.OrdinalIgnoreCase) == 0 {
            targetKind = 5
        }

        return new WatchTargetSummary(targetKind)
    }

    public static func GetOptionSummary(args: string[]): WatchOptionSummary {
        projectOption: string? = null
        debounceMsOption: string? = null
        maxRunsOption: string? = null
        showHelp := false

        if args.Length == 0 {
            showHelp = true
        }

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            if arg == "--project" {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            }

            if arg == "--debounce-ms" {
                if debounceMsOption == null && i + 1 < args.Length {
                    debounceMsOption = args[i + 1]
                }
            }

            if arg == "--max-runs" {
                if maxRunsOption == null && i + 1 < args.Length {
                    maxRunsOption = args[i + 1]
                }
            }

            i = i + 1
        }

        return new WatchOptionSummary(projectOption, debounceMsOption, maxRunsOption, showHelp)
    }

    public static func GetForwardedArgs(args: string[]): string[] {
        count := 0
        i := 1
        while i < args.Length {
            arg := args[i]
            if WatchArgumentIsOptionWithValue(arg) {
                i = i + 2
                continue
            }

            if arg == "--help" || arg == "-h" {
                i = i + 1
                continue
            }

            count = count + 1
            i = i + 1
        }

        forwardedArgs := new string[](count)
        resultIndex := 0
        i = 1
        while i < args.Length {
            arg := args[i]
            if WatchArgumentIsOptionWithValue(arg) {
                i = i + 2
                continue
            }

            if arg == "--help" || arg == "-h" {
                i = i + 1
                continue
            }

            forwardedArgs[resultIndex] = arg
            resultIndex = resultIndex + 1
            i = i + 1
        }

        return forwardedArgs
    }

    public static func ParsePositiveInt(value: string): int {
        parsed := ParseInt32OrZero(value)
        if parsed <= 0 {
            return 0
        }

        return parsed
    }

    public static func ParsePositiveIntOption(value: string?, hasDefault: bool, defaultValue: int): WatchPositiveIntOption {
        if value == null || (value ?? "").Trim().Length == 0 {
            if hasDefault {
                return new WatchPositiveIntOption(true, true, defaultValue)
            }

            return new WatchPositiveIntOption(true, false, 0)
        }

        parsed := ParsePositiveInt(value ?? "")
        if parsed > 0 {
            return new WatchPositiveIntOption(true, true, parsed)
        }

        return new WatchPositiveIntOption(false, false, 0)
    }

    public static func GetTargetCommandName(targetKind: int): string {
        if targetKind == 1 {
            return "check"
        }

        if targetKind == 2 {
            return "build"
        }

        if targetKind == 3 {
            return "test"
        }

        if targetKind == 4 {
            return "lint"
        }

        if targetKind == 5 {
            return "format"
        }

        return ""
    }

    public static func GetHelpText(): string {
        return "N# Watch\n"
            + "\n"
            + "Usage: nlc watch <check|build|test|lint|format> [command-options]\n"
            + "\n"
            + "Re-run an N# command when `.nl`, `project.yml`, or `.editorconfig` files change.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>      Project root directory to watch (default: current directory)\n"
            + "  --debounce-ms <ms>   Debounce window before rerunning (default: 250)\n"
            + "  --max-runs <count>   Exit after N command executions (useful for scripts and tests)\n"
            + "  --help, -h           Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc watch check\n"
            + "  nlc watch build\n"
            + "  nlc watch test --filter AddPerson\n"
            + "  nlc watch lint\n"
            + "  nlc watch format --check\n"
            + "  nlc watch check --project examples/16-task-cli --max-runs 2\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Watch finished and the last run succeeded\n"
            + "  1  Invalid usage or the last watched run failed"
    }

    public static func GetUnsupportedTargetMessage(target: string): string {
        return "Unsupported watch target '" + target + "'. Expected check, build, test, lint, or format."
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    public static func GetPositiveIntExpectedMessage(flag: string): string {
        return flag + " expects a positive integer."
    }

    public static func GetStartedMessage(projectRoot: string): string {
        return "Watching " + projectRoot + " for N# changes. Press Ctrl+C to stop."
    }

    public static func GetChangeDetectedMessage(timeText: string, watchedCommand: string): string {
        return "Change detected at " + timeText + ". Re-running `nlc " + watchedCommand + "`."
    }

    public static func ShouldTriggerForChangedPath(path: string): bool {
        fileNameStart := WatchFileNameStart(path)

        if PathSubstringEqualsIgnoreCase(path, fileNameStart, path.Length, "project.yml")
            || PathSubstringEqualsIgnoreCase(path, fileNameStart, path.Length, ".editorconfig") {
            return true
        }

        extensionStart := WatchExtensionStart(path, fileNameStart)
        if extensionStart >= 0
            && PathSubstringEqualsIgnoreCase(path, extensionStart, path.Length, ".nl") {
            return true
        }

        return false
    }

    static func WatchArgumentIsOptionWithValue(arg: string): bool {
        return arg == "--project" || arg == "--debounce-ms" || arg == "--max-runs"
    }

    static func WatchFileNameStart(path: string): int {
        index := path.Length - 1
        while index >= 0 {
            ch := path[index]
            if ch == '/' || ch == '\\' {
                return index + 1
            }

            index = index - 1
        }

        return 0
    }

    static func WatchExtensionStart(path: string, fileNameStart: int): int {
        index := path.Length - 1
        while index >= fileNameStart {
            if path[index] == '.' {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func PathSubstringEqualsIgnoreCase(text: string, start: int, end: int, value: string): bool {
        if start < 0 || end < start || end > text.Length {
            return false
        }

        if end - start != value.Length {
            return false
        }

        return String.Compare(text, start, value, 0, value.Length, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func ParseInt32OrZero(text: string): int {
        start := 0
        end := text.Length
        while start < end && char.IsWhiteSpace(text[start]) {
            start = start + 1
        }

        while end > start && char.IsWhiteSpace(text[end - 1]) {
            end = end - 1
        }

        if start >= end {
            return 0
        }

        negative := false
        if text[start] == '+' || text[start] == '-' {
            negative = text[start] == '-'
            start = start + 1
            if start >= end {
                return 0
            }
        }

        parsed := 0
        index := start
        while index < end {
            ch := text[index]
            if ch < '0' || ch > '9' {
                return 0
            }

            digit := ch - '0'
            if parsed > 214748364 {
                return 0
            }

            if parsed == 214748364 {
                if negative {
                    if digit == 8 && index == end - 1 {
                        return 0 - 2147483647 - 1
                    }

                    return 0
                }

                if digit > 7 {
                    return 0
                }
            }

            parsed = parsed * 10 + digit
            index = index + 1
        }

        if negative {
            return 0 - parsed
        }

        return parsed
    }
}

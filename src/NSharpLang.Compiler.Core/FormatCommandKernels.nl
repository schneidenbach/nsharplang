namespace NSharpLang.Cli

import System
import System.IO
import System.Text

class FormatOptionSummary {
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

    constructor(projectOption: string?, verifyOnly: bool, diffOnly: bool, stdinMode: bool, showHelp: bool) {
        projectOptionValue = projectOption
        verifyOnlyValue = verifyOnly
        diffOnlyValue = diffOnly
        stdinModeValue = stdinMode
        showHelpValue = showHelp
    }
}

class FormatCommandKernels {
    static func GetOptionSummary(args: string[]): FormatOptionSummary {
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

    static func GetHelpText(): string {
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

    static func GetStdinWithFilesMessage(): string {
        return "Cannot combine --stdin with file arguments."
    }

    static func GetNoFilesFoundMessage(): string {
        return "No .nl files found to format."
    }

    static func GetFileNotFoundMessage(sourceFile: string): string {
        return "File not found: " + sourceFile
    }

    static func GetErrorFormattingMessage(sourceFile: string, exceptionMessage: string): string {
        return "Error formatting " + sourceFile + ": " + exceptionMessage
    }

    static func GetWarningLine(relativePath: string, warning: string): string {
        return "Warning [" + relativePath + "]: " + warning
    }

    static func GetSafetyCheckFailedMessage(warnings: string): string {
        return "Formatter safety check failed: " + warnings
    }

    static func GetCheckFailedHeader(count: int): string {
        return "Formatting check failed for " + count.ToString() + " file(s):"
    }

    static func GetCheckFailedPathLine(sourceFile: string): string {
        return "  " + sourceFile
    }

    static func GetAllFilesFormattedMessage(): string {
        return "All files are properly formatted."
    }

    static func GetFormattedCountMessage(count: int): string {
        return "Formatted " + count.ToString() + " file(s)."
    }

    static func GetFailedMessage(exceptionMessage: string): string {
        return "Format failed: " + exceptionMessage
    }

    static func GetParseErrorsMessage(relativePath: string, messages: string): string {
        return "Parse errors in " + relativePath + ": " + messages
    }

    static func GetStdinExitCode(verifyOnly: bool, source: string, formatted: string): int {
        if verifyOnly && !string.Equals(source, formatted, StringComparison.Ordinal) {
            return 1
        }

        return 0
    }

    // A DECLINE MUST NOT SUPPRESS THE `--check` REPORT, WHICH IS WHY THE VERIFY ARM IS ASKED FIRST.
    //
    // Kind 1 and kind 2 both exit 1, so the order does not change the exit code — it changes whether
    // the user is TOLD WHICH FILES need formatting. With `failed` tested first, one unformattable file
    // anywhere in the tree turned `nlc format --check --project .` into a bare exit 1 with an empty
    // stdout: the warnings named the file that declined and nothing named the twenty that were merely
    // out of date. That is the least useful moment to go quiet, because a decline is exactly when a
    // user wants to know what else is outstanding. A run with declines AND nothing to reformat still
    // falls through to kind 1, so an empty list is never printed as if it were news.
    static func GetCompletionKind(failed: bool, verifyOnly: bool, diffOnly: bool, filesNeedingFormatting: int): int {
        if verifyOnly && filesNeedingFormatting > 0 {
            return 2
        }

        if failed {
            return 1
        }

        if diffOnly {
            if filesNeedingFormatting == 0 {
                return 3
            }

            return 4
        }

        if verifyOnly {
            return 5
        }

        return 6
    }

    static func ResolveFilePath(projectRoot: string, filePath: string): string {
        if Path.IsPathRooted(filePath) {
            return Path.GetFullPath(filePath)
        }

        return Path.GetFullPath(Path.Combine(projectRoot, filePath))
    }

    static func GetProjectRoot(projectOption: string?, currentDirectory: string): string {
        return Path.GetFullPath(projectOption ?? currentDirectory)
    }

    static func GetRelativePath(projectRoot: string, filePath: string): string {
        return NormalizePath(Path.GetRelativePath(projectRoot, filePath))
    }

    static func GetFileDirectory(projectRoot: string, filePath: string): string {
        return Path.GetDirectoryName(Path.GetFullPath(filePath)) ?? projectRoot
    }

    static func GetDiscoveredDirectoryName(directoryPath: string): string {
        end := directoryPath.Length
        while end > 0 {
            ch := directoryPath[end - 1]
            if ch == '/' || ch == '\\' {
                end = end - 1
            } else {
                break
            }
        }

        start := end - 1
        while start >= 0 {
            ch := directoryPath[start]
            if ch == '/' || ch == '\\' {
                break
            }

            start = start - 1
        }

        length := end - start - 1
        if length <= 0 {
            return ""
        }

        return directoryPath.Substring(start + 1, length)
    }

    static func ShouldEmitFormattedFile(source: string, formatted: string): bool {
        return !string.Equals(source, formatted, StringComparison.Ordinal)
    }

    // A `.tests.nl` FILE IS N# SOURCE AND IS DISCOVERED LIKE ANY OTHER. Discovery used to refuse
    // the suffix outright, which made `nlc format --project X` and `nlc format <file>` answer
    // DIFFERENT questions about the same file and put the whole contract estate — 294 files under
    // the paths the product gate walks — outside canonical formatting with nothing saying so. The
    // fixtures rule below still stands: `tests/fixtures/**` holds deliberately malformed sources.
    static func ShouldFormatDiscoveredPath(relativePath: string): bool {
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

    static func ShouldSkipDiscoveredDirectoryName(directoryName: string): bool {
        return FormatPathSegmentIsExcluded(directoryName, 0, directoryName.Length)
    }

    static func NormalizePath(path: string): string {
        return path.Replace('\\', '/')
    }

    // A HIDDEN SEGMENT IS SKIPPED, AND THE NAMED EXCLUSIONS ARE THE THREE THAT ARE NOT HIDDEN.
    //
    // THIS USED TO BE A LIST OF EXACT NAMES, AND `.worktrees` IS THE PROOF THAT A LIST IS THE WRONG
    // SHAPE: it was added to keep the walk out of nested checkouts, and the layout that actually
    // exists is `.claude/worktrees` — `.claude` was not in the list and `worktrees` carries no dot,
    // so neither segment matched. At the repository root the walk descended into three other
    // sessions' full checkouts and `nlc format --check --project .` reported 2,712 foreign sources.
    // A name list has to predict every tool's directory in advance; this one predicted a layout
    // nobody uses.
    //
    // THE RULE IS GOFMT'S DOT HALF, AND ONLY THE DOT HALF. gofmt skips a directory whose name begins
    // with `.` or `_`, plus `testdata`. The dot half is adopted: it covers `.git`, `.svn`, `.hg`,
    // `.nlc`, `.hermes`, `.claude`, `.vs`, `.idea` and every future tool directory in one line, and
    // it is measured to cost nothing here — the files under `.claude/` are the ONLY `.nl` files under
    // any dot-directory in the checkout. The underscore half is REFUSED on evidence:
    // `editors/vscode/test/fixtures/simple/_rename_var.nl` and two siblings are legitimate
    // `_`-prefixed N# sources, and gofmt skips `_` only because the GO TOOLCHAIN ignores those
    // directories — a rule N# does not have. `testdata` is refused for the same reason: it is a Go
    // convention, and N#'s equivalent (`tests/**/fixtures`) already has its own two-segment rule.
    //
    // `bin`, `obj` and `node_modules` STAY NAMED because they are not hidden and nothing else would
    // catch them. The six dot-named entries that used to be listed here are gone: every one of them
    // is covered by the rule above, and keeping both would leave two places to update.
    //
    // AN EXPLICIT HIDDEN ROOT IS STILL HONOURED, and that falls out of the structure rather than
    // needing a case here: `EnumerateFormatFiles` pushes the project root WITHOUT testing it and
    // filters only the child directories it discovers, and the paths reaching this predicate are
    // RELATIVE to that root — so `nlc format --project .claude/worktrees/x` sees `src/Program.nl`
    // and formats it.
    static func FormatPathSegmentIsExcluded(text: string, start: int, end: int): bool {
        length := end - start
        if length == 0 {
            return false
        }

        if text[start] == '.' {
            return true
        }

        if length == 3 {
            if FormatPathSegmentEquals(text, start, end, "bin") {
                return true
            }

            return FormatPathSegmentEquals(text, start, end, "obj")
        }

        if length == 12 {
            return FormatPathSegmentEquals(text, start, end, "node_modules")
        }

        return false
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

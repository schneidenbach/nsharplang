namespace NSharpLang.Cli

import System
import System.IO
import System.Text
import System.Text.Json
import NSharpLang.Compiler.CodeIntelligence

// THE SHAPES EVERY `nlc` COMMAND WRITES ITS ANSWER IN, OWNED ONCE.
//
// A command's own file owns what that command MEANS. It does not own how a JSON string is escaped,
// which integer `--json` selects, what "project directory not found" reads like, or how an argument
// segment parses as an int — and yet twenty-odd command files each carried their own copy of those,
// byte for byte: five identical `AppendJsonString`, eight identical `GetOutputMode`, seven identical
// `AppendLine`, six identical `Error`. A copy is a place a fix can miss, and a JSON escaper that is
// fixed in four of five commands is worse than one that is wrong in all five.
//
// Every function here is the EXACT behaviour its copies had, so the bytes a command writes are the
// bytes it wrote before. The loops are spelled `for … in` and the character tables as `match`, which
// is the same answer in fewer lines, not a different one.
//
// This class lives in `NSharpLang.Cli`, the namespace enclosing `NSharpLang.Cli.Commands` and
// `NSharpLang.Cli.Daemon`, so every command file sees it without an import. Shapes that belong to
// code intelligence rather than to a command — the symbol-kind spellings — are owned by
// `SymbolDisplayFacts` instead, because `NSharpLang.Compiler.CodeIntelligence` must not import the CLI.
static class CommandOutputKernels {

    // ── JSON ──────────────────────────────────────────────────────────────────
    //
    // The five copies escaped exactly these five characters and passed everything else through
    // verbatim, including control characters, which this one does too: it is the escaper the CLI's
    // committed output was produced by, not a more correct one.
    static func AppendJsonString(builder: StringBuilder, value: string) {
        builder.Append('"')
        for character in value {
            builder.Append(match character {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\n' => "\\n",
                '\r' => "\\r",
                '\t' => "\\t",
                _ => character.ToString()
            })
        }

        builder.Append('"')
    }

    static func AppendJsonNullableString(builder: StringBuilder, value: string?) {
        if value == null {
            builder.Append("null")
            return
        }

        AppendJsonString(builder, value ?? "")
    }

    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    // ── TEXT ──────────────────────────────────────────────────────────────────
    //
    // `(char)10` and not `Environment.NewLine`: the committed text output is LF on every platform.
    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }

    // ── XML ───────────────────────────────────────────────────────────────────
    //
    // The five-entry table two owners spelled identically under two names (`PackCommandKernels`'
    // `XmlEscape` and `RestoreCommandKernels`' `XmlAttributeEscape`). `NewCommandKernels` keeps its
    // OWN `XmlAttributeEscape`, which escapes a different set and is not this function.
    static func XmlEscape(value: string): string {
        result := ""
        for character in value {
            result = result + match character {
                '&' => "&amp;",
                '"' => "&quot;",
                '<' => "&lt;",
                '>' => "&gt;",
                _ => character.ToString()
            }
        }

        return result
    }

    // ── OUTPUT MODE AND EXIT ──────────────────────────────────────────────────
    //
    // 1 is JSON and 2 is text. The numbers are the ones every command already answered.
    static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }

    // ── PATHS AND THEIR MESSAGES ──────────────────────────────────────────────
    static func GetProjectRoot(projectOption: string?, currentDirectory: string): string {
        return Path.GetFullPath(projectOption ?? currentDirectory)
    }

    // `OutputFormatterNormalizationKernels` owns what normalization IS; a command needs the total
    // function, which answers the path it was given when normalization declines.
    static func NormalizePath(path: string): string {
        return OutputFormatterNormalizationKernels.NormalizePath(path) ?? path
    }

    static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    static func GetFileNotFoundMessage(sourceFile: string): string {
        return "File not found: " + sourceFile
    }

    // ── ARGUMENT SEGMENTS ─────────────────────────────────────────────────────
    //
    // A `line:column` argument is parsed WITHOUT allocating a substring, and without `int.Parse`'s
    // culture or its exception. The overflow arm is the reason this is not two lines: `int.MinValue`
    // has no positive spelling, so the last digit of the most negative value is admitted only when it
    // ends the segment. `DaemonServerKernels` and `QueryCommandKernels` each carried this; the one
    // difference was a local `IsWhiteSpace` that fell through to `char.IsWhiteSpace` after testing
    // four characters it also answers, so the two agreed on every input.
    static func TryParseIntSegment(text: string, start: int, end: int, out result: int): bool {
        result = 0

        while start < end && char.IsWhiteSpace(text[start]) {
            start = start + 1
        }

        while end > start && char.IsWhiteSpace(text[end - 1]) {
            end = end - 1
        }

        if start >= end {
            return false
        }

        negative := false
        if text[start] == '+' || text[start] == '-' {
            negative = text[start] == '-'
            start = start + 1
            if start >= end {
                return false
            }
        }

        parsedValue := 0
        index := start
        while index < end {
            ch := text[index]
            if ch < '0' || ch > '9' {
                return false
            }

            digit := ch - '0'
            if parsedValue > 214748364 {
                return false
            }

            if parsedValue == 214748364 {
                if negative {
                    if digit == 8 && index == end - 1 {
                        result = 0 - 2147483647 - 1
                        return true
                    }

                    return false
                }

                if digit > 7 {
                    return false
                }
            }

            parsedValue = parsedValue * 10 + digit
            index = index + 1
        }

        if negative {
            result = 0 - parsedValue
        } else {
            result = parsedValue
        }

        return true
    }
}

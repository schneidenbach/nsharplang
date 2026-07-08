namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler.CodeIntelligence
import System

public class QueryDaemonParameterSummary {
    File: string?
    Pos: string?
    Name: string?
    Kind: string?
    Severity: string?
    IncludeKeywords: bool
    Clusters: bool

    constructor(
        filePath: string?,
        pos: string?,
        name: string?,
        kind: string?,
        severity: string?,
        includeKeywords: bool,
        clusters: bool) {
        File = filePath
        Pos = pos
        Name = name
        Kind = kind
        Severity = severity
        IncludeKeywords = includeKeywords
        Clusters = clusters
    }
}

public class QueryCommandOptionSummary {
    Filter: string?
    Function: string?
    Limit: string?
    Requests: string?
    LeadingOperand: string?

    constructor(filter: string?, functionName: string?, limit: string?, requests: string?, leadingOperand: string?) {
        Filter = filter
        Function = functionName
        Limit = limit
        Requests = requests
        LeadingOperand = leadingOperand
    }
}

public class QueryTopLevelOptionSummary {
    Subcommand: string?
    ProjectDir: string?
    File: string?
    Pos: string?
    UseText: bool
    NoDaemon: bool
    InspectCompact: bool
    RemainingArgs: string[]

    constructor(
        subcommand: string?,
        projectDir: string?,
        filePath: string?,
        pos: string?,
        useText: bool,
        noDaemon: bool,
        inspectCompact: bool,
        remainingArgs: string[]) {
        Subcommand = subcommand
        ProjectDir = projectDir
        File = filePath
        Pos = pos
        UseText = useText
        NoDaemon = noDaemon
        InspectCompact = inspectCompact
        RemainingArgs = remainingArgs
    }
}

public class QueryOptions {
    ProjectDir: string?
    File: string?
    Pos: string?
    UseText: bool
    NoDaemon: bool
    InspectCompact: bool

    constructor(
        projectDir: string?,
        filePath: string?,
        pos: string?,
        useText: bool,
        noDaemon: bool,
        inspectCompact: bool) {
        ProjectDir = projectDir
        File = filePath
        Pos = pos
        UseText = useText
        NoDaemon = noDaemon
        InspectCompact = inspectCompact
    }
}

public class QuerySymbolKindParseResult {
    HasValue: bool
    value: int

    constructor(hasValue: bool, kindValue: int) {
        HasValue = hasValue
        value = kindValue
    }

    public func GetValueOrDefault(): SymbolKind {
        return (SymbolKind)value
    }
}

public class QueryCommandKernels {
    public static func GetDaemonParameterSummary(args: string[]): QueryDaemonParameterSummary {
        filePath: string? = null
        pos: string? = null
        name: string? = null
        kind: string? = null
        severity: string? = null
        includeKeywords := false
        clusters := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--file" {
                if filePath == null && i + 1 < args.Length {
                    filePath = args[i + 1]
                }
            } else if arg == "--pos" {
                if pos == null && i + 1 < args.Length {
                    pos = args[i + 1]
                }
            } else if arg == "--name" {
                if name == null && i + 1 < args.Length {
                    name = args[i + 1]
                }
            } else if arg == "--kind" {
                if kind == null && i + 1 < args.Length {
                    kind = args[i + 1]
                }
            } else if arg == "--severity" {
                if severity == null && i + 1 < args.Length {
                    severity = args[i + 1]
                }
            } else if arg == "--include-keywords" {
                includeKeywords = true
            } else if arg == "--clusters" {
                clusters = true
            }

            i = i + 1
        }

        return new QueryDaemonParameterSummary(filePath, pos, name, kind, severity, includeKeywords, clusters)
    }

    public static func GetCommandOptionSummary(args: string[]): QueryCommandOptionSummary {
        filter: string? = null
        functionName: string? = null
        limit: string? = null
        requests: string? = null
        leadingOperand: string? = null

        if args.Length > 0 && !IsLongOption(args[0]) {
            leadingOperand = args[0]
        }

        i := 0
        while i < args.Length {
            arg := args[i]
            if arg == "--filter" {
                if filter == null && i + 1 < args.Length {
                    filter = args[i + 1]
                }
            } else if arg == "--function" {
                if functionName == null && i + 1 < args.Length {
                    functionName = args[i + 1]
                }
            } else if arg == "--limit" {
                if limit == null && i + 1 < args.Length {
                    limit = args[i + 1]
                }
            } else if arg == "--requests" {
                if requests == null && i + 1 < args.Length {
                    requests = args[i + 1]
                }
            }

            i = i + 1
        }

        return new QueryCommandOptionSummary(filter, functionName, limit, requests, leadingOperand)
    }

    public static func GetTopLevelOptionSummary(args: string[]): QueryTopLevelOptionSummary {
        subcommand: string? = null
        projectDir: string? = null
        filePath: string? = null
        pos: string? = null
        useText := false
        noDaemon := false
        inspectCompact := false

        if args.Length > 0 {
            subcommand = args[0]
        }

        remainingCount := CountTopLevelRemainingArgs(args)
        remainingArgs := new string[](remainingCount)
        remainingIndex := 0

        i := 1
        while i < args.Length {
            arg := args[i]
            if arg == "--project" && i + 1 < args.Length {
                projectDir = args[i + 1]
                i = i + 2
                continue
            }

            if arg == "--file" && i + 1 < args.Length {
                filePath = args[i + 1]
                i = i + 2
                continue
            }

            if arg == "--pos" && i + 1 < args.Length {
                pos = args[i + 1]
                i = i + 2
                continue
            }

            if arg == "--text" {
                useText = true
            } else if arg == "--json" {
                useText = false
            } else if arg == "--no-daemon" {
                noDaemon = true
            } else if arg == "--summary" || arg == "--compact" {
                inspectCompact = true
            } else {
                remainingArgs[remainingIndex] = arg
                remainingIndex = remainingIndex + 1
            }

            i = i + 1
        }

        return new QueryTopLevelOptionSummary(subcommand, projectDir, filePath, pos, useText, noDaemon, inspectCompact, remainingArgs)
    }

    public static func ParsePosition(position: string, out line: int, out column: int): bool {
        line = 0
        column = 0

        fastParsed := TryParseSimplePositivePosition(position, out line, out column)
        if fastParsed >= 0 {
            return fastParsed == 1
        }

        colon := -1
        i := 0
        while i < position.Length {
            if position[i] == ':' {
                if colon >= 0 {
                    return false
                }

                colon = i
            }

            i = i + 1
        }

        if colon < 0 {
            return false
        }

        if !TryParseIntSegment(position, 0, colon, out line) {
            line = 0
            column = 0
            return false
        }

        if !TryParseIntSegment(position, colon + 1, position.Length, out column) {
            column = 0
            return false
        }

        return true
    }

    public static func ParsePositiveInt(valueText: string, out result: int): bool {
        result = 0
        if !TryParseIntSegment(valueText, 0, valueText.Length, out result) {
            result = 0
            return false
        }

        if result <= 0 {
            result = 0
            return false
        }

        return true
    }

    public static func GetInspectOutputMode(useText: bool, inspectCompact: bool): int {
        if useText && inspectCompact {
            return -1
        }

        if inspectCompact {
            return 2
        }

        if useText {
            return 3
        }

        return 1
    }

    public static func ShouldUseDaemon(useText: bool, noDaemon: bool): bool {
        return !useText && !noDaemon
    }

    public static func GetDiagnosticsOutputMode(useText: bool, clusters: bool): int {
        if clusters {
            return 3
        }

        if useText {
            return 2
        }

        return 1
    }

    public static func GetJsonOnlyOutputMode(useText: bool): int {
        if useText {
            return -1
        }

        return 1
    }

    public static func GetTextJsonOutputMode(useText: bool): int {
        if useText {
            return 2
        }

        return 1
    }

    public static func GetResultPresenceExitCode(resultCount: int): int {
        if resultCount > 0 {
            return 0
        }

        return 1
    }

    public static func GetBooleanSuccessExitCode(ok: bool): int {
        if ok {
            return 0
        }

        return 1
    }

    public static func GetDiagnosticSummaryExitCode(errorCount: int): int {
        if errorCount > 0 {
            return 1
        }

        return 0
    }

    public static func IsInterfaceKind(kind: string?): bool {
        return String.Compare(kind ?? "", "interface", StringComparison.OrdinalIgnoreCase) == 0
    }

    public static func ParseSymbolKind(valueText: string): QuerySymbolKindParseResult {
        kindValue := 0
        if !TryParseSymbolKind(valueText, out kindValue) {
            return new QuerySymbolKindParseResult(false, 0)
        }

        return new QuerySymbolKindParseResult(true, kindValue)
    }

    public static func GetHelpText(commandLines: string): string {
        return "N# Code Intelligence CLI\n"
            + "\n"
            + "Usage: nlc query <command> [options]\n"
            + "\n"
            + "Commands:\n"
            + commandLines + "\n"
            + "\n"
            + "Global Options:\n"
            + "  --json        Output as JSON (default)\n"
            + "  --text        Output as human-readable text (Elm-style)\n"
            + "  --no-daemon   Force in-process analysis even if a daemon is running\n"
            + "  --project     Project root directory (default: current directory)\n"
            + "  --file        Target file for file-scoped operations\n"
            + "  --pos         Position as line:col (e.g. 5:12)\n"
            + "  --compact     For inspect, emit the compact token-efficient envelope (alias: --summary)\n"
            + "  --clusters    For diagnostics, emit the stable diagnostic-cluster JSON envelope\n"
            + "\n"
            + "Examples:\n"
            + "  nlc query symbols                              # All symbols in project\n"
            + "  nlc query symbols --filter '*Person*'          # Symbols matching glob\n"
            + "  nlc query symbols --filter Person              # Symbols matching substring\n"
            + "  nlc query batch --requests requests.json       # Mixed semantic queries in one call\n"
            + "  nlc query symbols --file Program.nl            # Symbols in one file\n"
            + "  nlc query symbols --kind function              # Only functions\n"
            + "  nlc query outline Program.nl                   # File structure\n"
            + "  nlc query diagnostics                          # All errors/warnings\n"
            + "  nlc query diagnostics --clusters               # Diagnostic clusters\n"
            + "  nlc query diagnostics --text                   # Elm-style error output\n"
            + "  nlc query type --file Program.nl --pos 5:4     # Type at position\n"
            + "  nlc query inspect --file Program.nl --pos 5:4\n"
            + "  nlc query inspect --file Program.nl --pos 5:4 --compact\n"
            + "  nlc query def --file Program.nl --pos 5:4      # Definition at position\n"
            + "  nlc query refs --file Program.nl --pos 5:4     # All references\n"
            + "  nlc query hover --file Program.nl --pos 5:4    # Signature + docs at position\n"
            + "  nlc query call-graph --function Main           # Callers/callees of Main\n"
            + "  nlc query call-graph --function Main --limit 50\n"
            + "  nlc query implementors --name IShape           # Types implementing IShape\n"
            + "  nlc query implementors --file Program.nl --pos 10:11\n"
            + "  nlc query perf --file Program.nl --pos 5:4     # Allocation/dispatch/ABI facts\n"
            + "  nlc query trusted                              # Governed [trusted] wrappers\n"
            + "  nlc query doc Console                          # Type documentation\n"
            + "  nlc query doc Console.WriteLine                # Method documentation\n"
            + "  nlc query doc List                             # Generic type docs\n"
            + "\n"
            + "JSON queries reuse `nlc daemon` automatically when a daemon is already running.\n"
            + "Use `--no-daemon` to bypass the daemon for debugging."
    }

    public static func GetDescriptionWithAliases(description: string, aliasesText: string): string {
        if aliasesText.Length == 0 {
            return description
        }

        return description + " (aliases: " + aliasesText + ")"
    }

    public static func GetUnknownSubcommandMessage(subcommand: string): string {
        return "Unknown query subcommand: " + subcommand + ". Run 'nlc query help' for usage."
    }

    public static func GetNoCompilationUnitForFileMessage(fileFilter: string): string {
        return "No compilation unit found for --file " + fileFilter
    }

    public static func GetNoCompilationUnitsMessage(): string {
        return "No compilation units in project."
    }

    public static func GetPositionUsageMessage(subcommand: string): string {
        return "Usage: nlc query " + subcommand + " --file <path> --pos <line>:<col>"
    }

    public static func GetInvalidPositionMessage(position: string): string {
        return "Invalid position format: " + position + ". Expected <line>:<col> (e.g. 5:12)"
    }

    public static func GetNoSymbolAtPositionMessage(filePath: string, line: int, column: int): string {
        return "No symbol found at " + filePath + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetNoTypeInformationAtPositionMessage(filePath: string, line: int, column: int): string {
        return "No type information found at " + filePath + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetNoDefinitionAtPositionMessage(filePath: string, line: int, column: int): string {
        return "No definition found at " + filePath + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetNoInterfaceAtPositionMessage(filePath: string, line: int, column: int): string {
        return "No interface found at " + filePath + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetPerformanceJsonOnlyMessage(): string {
        return "Performance facts are only available as JSON output."
    }

    public static func GetTrustedJsonOnlyMessage(): string {
        return "Trusted-site reports are only available as JSON output."
    }

    public static func GetImplementorsUsageMessage(): string {
        return "Usage: nlc query implementors --name <interface>\n       nlc query implementors --file <path> --pos <line>:<col>"
    }

    public static func GetBatchJsonOnlyMessage(): string {
        return "Batch queries only support JSON output."
    }

    public static func GetBatchUsageMessage(): string {
        return "Usage: nlc query batch --requests <path-to-json>"
    }

    public static func GetEmptyBatchMessage(): string {
        return "Batch request file did not contain any requests."
    }

    public static func GetOutlineUsageMessage(): string {
        return "Usage: nlc query outline <file>"
    }

    public static func GetFileNotFoundMessage(filePath: string): string {
        return "File not found: " + filePath
    }

    public static func GetDefinitionUsageMessage(): string {
        return "Usage: nlc query definition --file <path> --pos <line>:<col>"
    }

    public static func GetInspectCompactTextUnsupportedMessage(): string {
        return "--compact/--summary is only supported with JSON output."
    }

    public static func GetReferencesUsageMessage(): string {
        return "Usage: nlc query references --file <path> --pos <line>:<col>\n\nThis is a semantic operation. Position-based only — no name-based shortcut."
    }

    public static func GetSemanticReferencesUnavailableMessage(): string {
        return "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. "
            + "No name-based or text-based fallback was used."
    }

    public static func GetDocUsageMessage(): string {
        return "Usage: nlc query doc <type-or-member>\n"
            + "\n"
            + "Examples:\n"
            + "  nlc query doc Console\n"
            + "  nlc query doc Console.WriteLine\n"
            + "  nlc query doc List\n"
            + "  nlc query doc System.IO.File"
    }

    public static func GetNoDocumentationMessage(query: string): string {
        return "No documentation found for '" + query + "'."
    }

    public static func GetProjectDirectoryNotFoundMessage(projectDir: string): string {
        return "Project directory not found: " + projectDir
    }

    public static func GetFailedAnalyzeProjectMessage(message: string): string {
        return "Failed to analyze project: " + message
    }

    static func CountTopLevelRemainingArgs(args: string[]): int {
        count := 0
        i := 1
        while i < args.Length {
            arg := args[i]
            if HasTopLevelValue(arg) && i + 1 < args.Length {
                i = i + 2
                continue
            }

            if !IsTopLevelFlag(arg) {
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    static func HasTopLevelValue(arg: string): bool {
        return arg == "--project" || arg == "--file" || arg == "--pos"
    }

    static func IsTopLevelFlag(arg: string): bool {
        return arg == "--text"
            || arg == "--json"
            || arg == "--no-daemon"
            || arg == "--summary"
            || arg == "--compact"
    }

    static func IsLongOption(arg: string): bool {
        return arg.Length >= 2 && arg[0] == '-' && arg[1] == '-'
    }

    static func TryParseSymbolKind(kind: string, out result: int): bool {
        result = 0

        start := 0
        end := kind.Length
        while start < end && IsWhiteSpace(kind[start]) {
            start = start + 1
        }

        while end > start && IsWhiteSpace(kind[end - 1]) {
            end = end - 1
        }

        if start >= end {
            return false
        }

        hasComma := false
        commaScan := start
        while commaScan < end {
            if kind[commaScan] == ',' {
                hasComma = true
            }

            commaScan = commaScan + 1
        }

        if hasComma {
            combined := 0
            segmentStart := start
            while segmentStart < end {
                segmentEnd := segmentStart
                while segmentEnd < end && kind[segmentEnd] != ',' {
                    segmentEnd = segmentEnd + 1
                }

                segmentValue := 0
                if !TryParseSymbolKindSegment(kind, segmentStart, segmentEnd, out segmentValue) {
                    result = 0
                    return false
                }

                combined = BitwiseOrInt(combined, segmentValue)
                segmentStart = segmentEnd + 1
            }

            result = combined
            return true
        }

        return TryParseSymbolKindSegment(kind, start, end, out result)
    }

    static func TryParseSymbolKindSegment(kind: string, start: int, end: int, out result: int): bool {
        result = 0

        while start < end && IsWhiteSpace(kind[start]) {
            start = start + 1
        }

        while end > start && IsWhiteSpace(kind[end - 1]) {
            end = end - 1
        }

        if start >= end {
            return false
        }

        if TryParseIntSegment(kind, start, end, out result) {
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Function") {
            result = 0
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Class") {
            result = 1
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Struct") {
            result = 2
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Record") {
            result = 3
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Interface") {
            result = 4
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Enum") {
            result = 5
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Union") {
            result = 6
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Property") {
            result = 7
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Field") {
            result = 8
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Method") {
            result = 9
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Variable") {
            result = 10
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Parameter") {
            result = 11
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Constructor") {
            result = 12
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "EnumMember") {
            result = 13
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "TypeAlias") {
            result = 14
            return true
        }

        if TextSegmentEqualsIgnoreCase(kind, start, end, "Test") {
            result = 15
            return true
        }

        return false
    }

    static func TextSegmentEqualsIgnoreCase(text: string, start: int, end: int, expected: string): bool {
        if end - start != expected.Length {
            return false
        }

        return String.Compare(text, start, expected, 0, expected.Length, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func BitwiseOrInt(left: int, right: int): int {
        return left + right - (left & right)
    }

    static func TryParseSimplePositivePosition(position: string, out line: int, out column: int): int {
        line = 0
        column = 0

        if position.Length < 3 {
            return -1
        }

        sawColon := false
        lineDigits := 0
        columnDigits := 0
        localLine := 0
        localColumn := 0

        i := 0
        while i < position.Length {
            ch := position[i]
            if ch == ':' {
                if sawColon || lineDigits == 0 {
                    return -1
                }

                sawColon = true
            } else if ch >= '0' && ch <= '9' {
                digit := ch - '0'
                if sawColon {
                    if localColumn > 214748364 {
                        return -1
                    }

                    if localColumn == 214748364 && digit > 7 {
                        return -1
                    }

                    localColumn = localColumn * 10 + digit
                    columnDigits = columnDigits + 1
                } else {
                    if localLine > 214748364 {
                        return -1
                    }

                    if localLine == 214748364 && digit > 7 {
                        return -1
                    }

                    localLine = localLine * 10 + digit
                    lineDigits = lineDigits + 1
                }
            } else {
                return -1
            }

            i = i + 1
        }

        if !sawColon || columnDigits == 0 {
            return -1
        }

        line = localLine
        column = localColumn
        return 1
    }

    static func TryParseIntSegment(text: string, start: int, end: int, out result: int): bool {
        result = 0

        while start < end && IsWhiteSpace(text[start]) {
            start = start + 1
        }

        while end > start && IsWhiteSpace(text[end - 1]) {
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

    static func IsWhiteSpace(ch: char): bool {
        if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
            return true
        }

        return char.IsWhiteSpace(ch)
    }
}

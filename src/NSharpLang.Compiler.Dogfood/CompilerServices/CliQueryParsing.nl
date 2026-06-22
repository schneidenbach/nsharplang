import System.Numerics

struct CliBatchDuplicateIdRankTable {
    IdRanks: int[]
    UniqueIdCount: int
}

struct CliBatchDuplicateScratchTable {
    CountsByRank: int[]
    ResultRanks: int[]
}

struct CliBatchResultWordTable {
    OkWords: ulong[]
    ItemCount: int
}

struct CliQueryPositionResultTable {
    Lines: int[]
    Columns: int[]
}

struct CliQueryIntResultTable {
    Values: int[]
}

func CliBatchDuplicateIdRanksInto(
    idRanks: int[],
    uniqueIdCount: int,
    countsByRank: int[],
    resultRanks: int[]): int {
    ranks := new CliBatchDuplicateIdRankTable { IdRanks: idRanks, UniqueIdCount: uniqueIdCount }
    scratch := new CliBatchDuplicateScratchTable { CountsByRank: countsByRank, ResultRanks: resultRanks }
    return CliBatchDuplicateIdRanksCore(ref ranks, ref scratch)
}

func CliBatchDuplicateIdRanksCore(ranks: &CliBatchDuplicateIdRankTable, scratch: &CliBatchDuplicateScratchTable): int {
    clearCount := ranks.UniqueIdCount + 1
    if clearCount > scratch.CountsByRank.Length {
        clearCount = scratch.CountsByRank.Length
    }

    i := 0
    while i < clearCount {
        scratch.CountsByRank[i] = 0
        i = i + 1
    }

    i = 0
    while i < ranks.IdRanks.Length {
        rank := ranks.IdRanks[i]
        if rank > 0 && rank <= ranks.UniqueIdCount && rank < scratch.CountsByRank.Length {
            scratch.CountsByRank[rank] = scratch.CountsByRank[rank] + 1
        }

        i = i + 1
    }

    duplicateCount := 0
    rank := 1
    while rank <= ranks.UniqueIdCount && rank < scratch.CountsByRank.Length {
        if scratch.CountsByRank[rank] > 1 {
            if duplicateCount < scratch.ResultRanks.Length {
                scratch.ResultRanks[duplicateCount] = rank
            }

            duplicateCount = duplicateCount + 1
        }

        rank = rank + 1
    }

    return duplicateCount
}

func CliBatchResultPackedSuccessCount(okWords: ulong[], itemCount: int): int {
    results := new CliBatchResultWordTable { OkWords: okWords, ItemCount: itemCount }
    return CliBatchResultPackedSuccessCountCore(ref results)
}

func CliBatchResultPackedSuccessCountCore(results: &CliBatchResultWordTable): int {
    if results.ItemCount <= 0 {
        return 0
    }

    fullWordCount := results.ItemCount >> 6
    if fullWordCount > results.OkWords.Length {
        fullWordCount = results.OkWords.Length
    }

    successCount := 0
    i := 0
    while i < fullWordCount {
        successCount = successCount + CliBatchResultPopCount64(results.OkWords[i])
        i = i + 1
    }

    lastBits := results.ItemCount & 63
    if lastBits != 0 && fullWordCount < results.OkWords.Length {
        shift := 64 - lastBits
        lastWord := (results.OkWords[fullWordCount] << shift) >> shift
        successCount = successCount + CliBatchResultPopCount64(lastWord)
    }

    return successCount
}

func CliBatchResultPopCount64(value: ulong): int {
    return BitOperations.PopCount(value)
}

func CliBatchRequestsFileNotFoundMessage(path: string): string {
    return "Requests file not found: " + path
}

func CliBatchPayloadShapeMessage(): string {
    return "Batch requests must be a JSON array or an object with a 'requests' array."
}

func CliBatchRequestObjectRequiredMessage(): string {
    return "Each batch request must be a JSON object."
}

func CliBatchRequestDeserializeFailedMessage(): string {
    return "Failed to deserialize a batch request."
}

func CliBatchDuplicateRequestIdsMessage(duplicateIdsText: string): string {
    return "Duplicate batch request ids are not allowed: " + duplicateIdsText
}

func CliBatchUnsupportedCommandMessage(command: string): string {
    return "Unsupported batch query command '" + command + "'."
}

func CliBatchOutlineFileRequiredMessage(): string {
    return "file is required for outline requests."
}

func CliBatchDocQueryRequiredMessage(): string {
    return "query is required for doc requests."
}

func CliBatchFileAndPosRequiredMessage(): string {
    return "file and pos are required."
}

func CliBatchInvalidPositionMessage(position: string): string {
    return "Invalid position format '" + position + "'. Expected <line>:<col>."
}

func CliQueryDaemonParameterSummaryInto(args: string[], resultIndices: int[]): int {
    if resultIndices.Length < 7 {
        return -1
    }

    resultIndices[0] = -1
    resultIndices[1] = -1
    resultIndices[2] = -1
    resultIndices[3] = -1
    resultIndices[4] = -1
    resultIndices[5] = 0
    resultIndices[6] = 0

    i := 0
    while i < args.Length {
        arg := args[i]
        if arg == "--file" {
            if resultIndices[0] < 0 && i + 1 < args.Length {
                resultIndices[0] = i + 1
            }
        } else if arg == "--pos" {
            if resultIndices[1] < 0 && i + 1 < args.Length {
                resultIndices[1] = i + 1
            }
        } else if arg == "--name" {
            if resultIndices[2] < 0 && i + 1 < args.Length {
                resultIndices[2] = i + 1
            }
        } else if arg == "--kind" {
            if resultIndices[3] < 0 && i + 1 < args.Length {
                resultIndices[3] = i + 1
            }
        } else if arg == "--severity" {
            if resultIndices[4] < 0 && i + 1 < args.Length {
                resultIndices[4] = i + 1
            }
        } else if arg == "--include-keywords" {
            resultIndices[5] = 1
        } else if arg == "--clusters" {
            resultIndices[6] = 1
        }

        i = i + 1
    }

    return 0
}

func CliQueryCommandOptionSummaryInto(args: string[], resultIndices: int[]): int {
    if resultIndices.Length < 5 {
        return -1
    }

    resultIndices[0] = -1
    resultIndices[1] = -1
    resultIndices[2] = -1
    resultIndices[3] = -1
    resultIndices[4] = -1

    if args.Length > 0 && !CliQueryIsLongOption(args[0]) {
        resultIndices[4] = 0
    }

    i := 0
    while i < args.Length {
        arg := args[i]
        if arg == "--filter" {
            if resultIndices[0] < 0 && i + 1 < args.Length {
                resultIndices[0] = i + 1
            }
        } else if arg == "--function" {
            if resultIndices[1] < 0 && i + 1 < args.Length {
                resultIndices[1] = i + 1
            }
        } else if arg == "--limit" {
            if resultIndices[2] < 0 && i + 1 < args.Length {
                resultIndices[2] = i + 1
            }
        } else if arg == "--requests" {
            if resultIndices[3] < 0 && i + 1 < args.Length {
                resultIndices[3] = i + 1
            }
        }

        i = i + 1
    }

    return 0
}

func CliQueryTopLevelOptionSummaryInto(args: string[], resultIndices: int[], remainingIndices: int[]): int {
    if resultIndices.Length < 7 {
        return -1
    }

    resultIndices[0] = -1
    resultIndices[1] = -1
    resultIndices[2] = -1
    resultIndices[3] = -1
    resultIndices[4] = 0
    resultIndices[5] = 0
    resultIndices[6] = 0

    if args.Length > 0 {
        resultIndices[0] = 0
    }

    resultCount := 0
    i := 1
    while i < args.Length {
        arg := args[i]
        if arg == "--project" && i + 1 < args.Length {
            resultIndices[1] = i + 1
            i = i + 2
            continue
        }

        if arg == "--file" && i + 1 < args.Length {
            resultIndices[2] = i + 1
            i = i + 2
            continue
        }

        if arg == "--pos" && i + 1 < args.Length {
            resultIndices[3] = i + 1
            i = i + 2
            continue
        }

        if arg == "--text" {
            resultIndices[4] = 1
        } else if arg == "--json" {
            resultIndices[4] = 0
        } else if arg == "--no-daemon" {
            resultIndices[5] = 1
        } else if arg == "--summary" || arg == "--compact" {
            resultIndices[6] = 1
        } else {
            if resultCount < remainingIndices.Length {
                remainingIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliQueryInspectOutputMode(useText: int, inspectCompact: int): int {
    if useText != 0 && inspectCompact != 0 {
        return -1
    }

    if inspectCompact != 0 {
        return 2
    }

    if useText != 0 {
        return 3
    }

    return 1
}

func CliQueryDiagnosticsOutputMode(useText: int, clusters: int): int {
    if clusters != 0 {
        return 3
    }

    if useText != 0 {
        return 2
    }

    return 1
}

func CliQueryJsonOnlyOutputMode(useText: int): int {
    if useText != 0 {
        return -1
    }

    return 1
}

func CliQueryTextJsonOutputMode(useText: int): int {
    if useText != 0 {
        return 2
    }

    return 1
}

func CliQueryShouldUseDaemon(useText: int, noDaemon: int): int {
    if useText != 0 || noDaemon != 0 {
        return 0
    }

    return 1
}

func CliQueryHelpText(commandLines: string): string {
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
        + "  nlc query def --name Person                    # Search by name\n"
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

func CliQueryDescriptionWithAliases(description: string, aliasesText: string): string {
    if aliasesText.Length == 0 {
        return description
    }

    return description + " (aliases: " + aliasesText + ")"
}

func CliQueryUnknownSubcommandMessage(subcommand: string): string {
    return "Unknown query subcommand: " + subcommand + ". Run 'nlc query help' for usage."
}

func CliQueryNoCompilationUnitForFileMessage(fileFilter: string): string {
    return "No compilation unit found for --file " + fileFilter
}

func CliQueryNoCompilationUnitsMessage(): string {
    return "No compilation units in project."
}

func CliQueryPositionUsageMessage(subcommand: string): string {
    return "Usage: nlc query " + subcommand + " --file <path> --pos <line>:<col>"
}

func CliQueryInvalidPositionMessage(position: string): string {
    return "Invalid position format: " + position + ". Expected <line>:<col> (e.g. 5:12)"
}

func CliQueryNoSymbolAtPositionMessage(filePath: string, lineText: string, columnText: string): string {
    return "No symbol found at " + filePath + ":" + lineText + ":" + columnText
}

func CliQueryNoTypeInformationAtPositionMessage(filePath: string, lineText: string, columnText: string): string {
    return "No type information found at " + filePath + ":" + lineText + ":" + columnText
}

func CliQueryNoDefinitionAtPositionMessage(filePath: string, lineText: string, columnText: string): string {
    return "No definition found at " + filePath + ":" + lineText + ":" + columnText
}

func CliQueryNoInterfaceAtPositionMessage(filePath: string, lineText: string, columnText: string): string {
    return "No interface found at " + filePath + ":" + lineText + ":" + columnText
}

func CliQueryPerformanceJsonOnlyMessage(): string {
    return "Performance facts are only available as JSON output."
}

func CliQueryTrustedJsonOnlyMessage(): string {
    return "Trusted-site reports are only available as JSON output."
}

func CliQueryImplementorsUsageMessage(): string {
    return "Usage: nlc query implementors --name <interface>\n       nlc query implementors --file <path> --pos <line>:<col>"
}

func CliQueryBatchJsonOnlyMessage(): string {
    return "Batch queries only support JSON output."
}

func CliQueryBatchUsageMessage(): string {
    return "Usage: nlc query batch --requests <path-to-json>"
}

func CliQueryEmptyBatchMessage(): string {
    return "Batch request file did not contain any requests."
}

func CliQueryOutlineUsageMessage(): string {
    return "Usage: nlc query outline <file>"
}

func CliQueryFileNotFoundMessage(filePath: string): string {
    return "File not found: " + filePath
}

func CliQueryDefinitionUsageMessage(): string {
    return "Usage: nlc query definition --file <path> --pos <line>:<col>\n       nlc query definition --name <name>"
}

func CliQueryInspectCompactTextUnsupportedMessage(): string {
    return "--compact/--summary is only supported with JSON output."
}

func CliQueryReferencesUsageMessage(): string {
    return "Usage: nlc query references --file <path> --pos <line>:<col>\n\nThis is a semantic operation. Position-based only — no name-based shortcut."
}

func CliQuerySemanticReferencesUnavailableMessage(): string {
    return "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. "
        + "No name-based or text-based fallback was used."
}

func CliQueryDocUsageMessage(): string {
    return "Usage: nlc query doc <type-or-member>\n"
        + "\n"
        + "Examples:\n"
        + "  nlc query doc Console\n"
        + "  nlc query doc Console.WriteLine\n"
        + "  nlc query doc List\n"
        + "  nlc query doc System.IO.File"
}

func CliQueryNoDocumentationMessage(query: string): string {
    return "No documentation found for '" + query + "'."
}

func CliQueryProjectDirectoryNotFoundMessage(projectDir: string): string {
    return "Project directory not found: " + projectDir
}

func CliQueryFailedAnalyzeProjectMessage(message: string): string {
    return "Failed to analyze project: " + message
}

func CliDaemonUnknownMethodMessage(method: string): string {
    return "Unknown method: " + method
}

func CliDaemonFailedLoadProjectMessage(): string {
    return "Failed to load project"
}

func CliDaemonEmptyBatchPayloadMessage(): string {
    return "Batch request payload did not contain any requests."
}

func CliDaemonFileParameterRequiredMessage(): string {
    return "file parameter required"
}

func CliDaemonFileAndPosParametersRequiredMessage(): string {
    return "file and pos parameters required"
}

func CliDaemonDefinitionTargetRequiredMessage(): string {
    return "file+pos or name required"
}

func CliDaemonFileAndPosRequiredMessage(): string {
    return "file and pos required"
}

func CliDaemonNoSymbolAtPositionMessage(filePath: string, lineText: string, columnText: string): string {
    return CliQueryNoSymbolAtPositionMessage(filePath, lineText, columnText)
}

func CliDaemonSemanticReferencesUnavailableMessage(): string {
    return CliQuerySemanticReferencesUnavailableMessage()
}

func CliDaemonListeningMessage(socketPath: string, processIdText: string): string {
    return "[daemon] Listening on " + socketPath + " (PID " + processIdText + ")"
}

func CliDaemonProjectMessage(projectRoot: string): string {
    return "[daemon] Project: " + projectRoot
}

func CliDaemonIdleTimeoutMessage(durationText: string): string {
    return "[daemon] Idle timeout: " + durationText
}

func CliDaemonIdleTimeoutShutdownMessage(durationText: string): string {
    return "[daemon] Idle timeout (" + durationText + "). Shutting down."
}

func CliDaemonServerErrorMessage(messageText: string): string {
    return "[daemon] Error: " + messageText
}

func CliDaemonClientErrorMessage(messageText: string): string {
    return "[daemon] Client error: " + messageText
}

func CliDaemonLoadingProjectMessage(): string {
    return "[daemon] Loading project..."
}

func CliDaemonProjectLoadedMessage(elapsedMillisecondsText: string, fileCountText: string): string {
    return "[daemon] Project loaded in " + elapsedMillisecondsText + "ms (" + fileCountText + " files)"
}

func CliDaemonProjectLoadFailedTraceMessage(messageText: string): string {
    return "[daemon] Failed to load project: " + messageText
}

func CliDaemonFileWatcherStartedMessage(): string {
    return "[daemon] File watcher started for *.nl, project.yml, .editorconfig"
}

func CliDaemonFileWatcherFailedMessage(messageText: string): string {
    return "[daemon] File watcher failed: " + messageText
}

func CliDaemonFileChangedMessage(fileName: string): string {
    return "[daemon] File changed: " + fileName + " — cache invalidated"
}

func CliDaemonShutdownCompleteMessage(): string {
    return "[daemon] Shutdown complete."
}

func CliDaemonMalformedRequestParamMessage(key: string, typeName: string, messageText: string): string {
    return "[daemon] Ignoring malformed request param '" + key + "' (expected " + typeName + "): " + messageText
}

func CliQueryIsLongOption(arg: string): bool {
    return arg.Length >= 2 && arg[0] == '-' && arg[1] == '-'
}

func CliTryParsePositionInto(position: string, result: int[]): int {
    if result.Length < 2 {
        return 0
    }

    results := new CliQueryPositionResultTable { Lines: result, Columns: result }
    return CliTryParsePositionPartsCore(position, ref results, 0, 1)
}

func CliTryParsePositiveIntInto(value: string, result: int[]): int {
    if result.Length < 1 {
        return -1
    }

    result[0] = 0
    values := new CliQueryIntResultTable { Values: result }
    if !CliTryParseIntSegmentCore(value, 0, value.Length, ref values, 0) {
        return 0
    }

    if result[0] <= 0 {
        result[0] = 0
        return 0
    }

    return 1
}

func CliQuerySymbolKindInto(kind: string, result: int[]): int {
    if result.Length < 1 {
        return -1
    }

    result[0] = 0

    start := 0
    end := kind.Length
    while start < end && CliQueryIsWhiteSpace(kind[start]) {
        start = start + 1
    }

    while end > start && CliQueryIsWhiteSpace(kind[end - 1]) {
        end = end - 1
    }

    if start >= end {
        return 0
    }

    values := new CliQueryIntResultTable { Values: result }
    if CliTryParseIntSegmentCore(kind, start, end, ref values, 0) {
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Function") {
        result[0] = 0
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Class") {
        result[0] = 1
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Struct") {
        result[0] = 2
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Record") {
        result[0] = 3
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Interface") {
        result[0] = 4
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Enum") {
        result[0] = 5
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Union") {
        result[0] = 6
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Property") {
        result[0] = 7
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Field") {
        result[0] = 8
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Method") {
        result[0] = 9
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Variable") {
        result[0] = 10
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Parameter") {
        result[0] = 11
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Constructor") {
        result[0] = 12
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "EnumMember") {
        result[0] = 13
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "TypeAlias") {
        result[0] = 14
        return 1
    }

    if CliQueryTextSegmentEqualsIgnoreCase(kind, start, end, "Test") {
        result[0] = 15
        return 1
    }

    return 0
}

func CliQueryTextSegmentEqualsIgnoreCase(text: string, start: int, end: int, expected: string): bool {
    if end - start != expected.Length {
        return false
    }

    return String.Compare(text, start, expected, 0, expected.Length, StringComparison.OrdinalIgnoreCase) == 0
}

func CliDaemonPositionInto(position: string, result: int[]): int {
    if result.Length < 2 {
        return -1
    }

    result[0] = 0
    result[1] = 0

    colon := -1
    i := 0
    while i < position.Length {
        if position[i] == ':' {
            if colon >= 0 {
                return 0
            }

            colon = i
        }

        i = i + 1
    }

    if colon < 0 {
        return 0
    }

    lineResult := new CliQueryIntResultTable { Values: result }
    if !CliTryParseIntSegmentCore(position, 0, colon, ref lineResult, 0) {
        result[0] = 0
    }

    result[1] = 0
    columnResult := new CliQueryIntResultTable { Values: result }
    if !CliTryParseIntSegmentCore(position, colon + 1, position.Length, ref columnResult, 1) {
        result[1] = 0
    }

    return 0
}

func CliTryParsePositionPartsCore(
    position: string,
    results: &CliQueryPositionResultTable,
    lineIndex: int,
    columnIndex: int): int {
    results.Lines[lineIndex] = 0
    results.Columns[columnIndex] = 0

    fastParsed := CliTryParseSimplePositivePositionCore(position, ref results, lineIndex, columnIndex)
    if fastParsed >= 0 {
        return fastParsed
    }

    colon := -1
    i := 0
    while i < position.Length {
        if position[i] == ':' {
            if colon >= 0 {
                return 0
            }

            colon = i
        }

        i = i + 1
    }

    if colon < 0 {
        return 0
    }

    lineResult := new CliQueryIntResultTable { Values: results.Lines }
    if !CliTryParseIntSegmentCore(position, 0, colon, ref lineResult, lineIndex) {
        results.Lines[lineIndex] = 0
        results.Columns[columnIndex] = 0
        return 0
    }

    columnResult := new CliQueryIntResultTable { Values: results.Columns }
    if !CliTryParseIntSegmentCore(position, colon + 1, position.Length, ref columnResult, columnIndex) {
        results.Columns[columnIndex] = 0
        return 0
    }

    return 1
}

func CliTryParseSimplePositivePositionCore(
    position: string,
    results: &CliQueryPositionResultTable,
    lineIndex: int,
    columnIndex: int): int {
    if position.Length < 3 {
        return -1
    }

    line := 0
    column := 0
    sawColon := false
    lineDigits := 0
    columnDigits := 0

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
                if column > 214748364 {
                    return -1
                }

                if column == 214748364 && digit > 7 {
                    return -1
                }

                column = column * 10 + digit
                columnDigits = columnDigits + 1
            } else {
                if line > 214748364 {
                    return -1
                }

                if line == 214748364 && digit > 7 {
                    return -1
                }

                line = line * 10 + digit
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

    results.Lines[lineIndex] = line
    results.Columns[columnIndex] = column
    return 1
}

func CliTryParseIntSegmentCore(
    text: string,
    start: int,
    end: int,
    result: &CliQueryIntResultTable,
    resultIndex: int): bool {
    while start < end && CliQueryIsWhiteSpace(text[start]) {
        start = start + 1
    }

    while end > start && CliQueryIsWhiteSpace(text[end - 1]) {
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

    value := 0
    index := start
    while index < end {
        ch := text[index]
        if ch < '0' || ch > '9' {
            return false
        }

        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 {
            if negative {
                if digit == 8 && index == end - 1 {
                    result.Values[resultIndex] = 0 - 2147483647 - 1
                    return true
                }

                return false
            }

            if digit > 7 {
                return false
            }
        }

        value = value * 10 + digit
        index = index + 1
    }

    if negative {
        result.Values[resultIndex] = 0 - value
    } else {
        result.Values[resultIndex] = value
    }

    return true
}

func CliQueryIsWhiteSpace(ch: char): bool {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
        return true
    }

    return char.IsWhiteSpace(ch)
}

namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Linq
import NSharpLang.Cli
import NSharpLang.Cli.Daemon
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Performance

// ─── THE THREE PERF FACTS, AS TYPES ───────────────────────────────────────────────────────────
//
// `nlc query perf` answers a list of facts drawn from three different places, and the C# built
// each one as an ANONYMOUS TYPE. `OutputFormatterJsonKernels.BuildPerfFact` reads whichever object
// it is handed BY MEMBER NAME through reflection, so the names below are the contract and the
// member order is the JSON order.
//
// The path member is `filePath`, not `file`: `file` is a hard keyword in N# with no escape, which
// is the single reason this whole owner was still C#. The kernel was changed to read `filePath`
// and still WRITE the key `file`, so the envelope is unchanged — see
// census-briefs/CLI2-COMPILER-BLOCKERS.md, entry 16, and the estate rows beside the kernel.
//
// They are written as properties with backing fields because `JsonSerializer` and
// `Type.GetProperty` both read PROPERTIES, and N#'s bare `Name: T` member is a FIELD.
class QueryPerformanceFactRow {
    filePathValue: string
    lineValue: int
    columnValue: int
    allocationValue: string
    captureValue: string
    dispatchValue: string
    escapeValue: string
    valueLayoutValue: string
    aotSafetyValue: string

    constructor(
        filePath: string,
        line: int,
        column: int,
        allocation: string,
        capture: string,
        dispatch: string,
        escape: string,
        valueLayout: string,
        aotSafety: string
    ) {
        filePathValue = filePath
        lineValue = line
        columnValue = column
        allocationValue = allocation
        captureValue = capture
        dispatchValue = dispatch
        escapeValue = escape
        valueLayoutValue = valueLayout
        aotSafetyValue = aotSafety
    }

    source: string {
        get {
            return "performanceFacts"
        }
    }

    filePath: string {
        get {
            return filePathValue
        }
    }

    line: int {
        get {
            return lineValue
        }
    }

    column: int {
        get {
            return columnValue
        }
    }

    allocation: string {
        get {
            return allocationValue
        }
    }

    capture: string {
        get {
            return captureValue
        }
    }

    dispatch: string {
        get {
            return dispatchValue
        }
    }

    escape: string {
        get {
            return escapeValue
        }
    }

    valueLayout: string {
        get {
            return valueLayoutValue
        }
    }

    aotSafety: string {
        get {
            return aotSafetyValue
        }
    }
}

// A systems finding at the queried position. The C# anonymous type used member shorthand
// (`finding.Code`), so the member names are the finding's own; they are kept exactly.
class QuerySystemsFactRow {
    codeValue: string
    severityValue: string
    effectValue: string
    messageValue: string
    functionValue: string?
    policyValue: string?
    suggestionValue: string?

    constructor(
        code: string,
        severity: string,
        effect: string,
        message: string,
        functionName: string?,
        policy: string?,
        suggestion: string?
    ) {
        codeValue = code
        severityValue = severity
        effectValue = effect
        messageValue = message
        functionValue = functionName
        policyValue = policy
        suggestionValue = suggestion
    }

    source: string {
        get {
            return "systems"
        }
    }

    Code: string {
        get {
            return codeValue
        }
    }

    Severity: string {
        get {
            return severityValue
        }
    }

    Effect: string {
        get {
            return effectValue
        }
    }

    Message: string {
        get {
            return messageValue
        }
    }

    Function: string? {
        get {
            return functionValue
        }
    }

    Policy: string? {
        get {
            return policyValue
        }
    }

    Suggestion: string? {
        get {
            return suggestionValue
        }
    }
}

// A systems function summary at the queried line. `Effects` is handed over as the record it is —
// the kernel walks its members itself — and `Calls` as the list it is.
class QuerySystemsFunctionFactRow {
    nameValue: string
    isHotValue: bool
    isBoundaryValue: bool
    allocNoneValue: bool
    summarySourceValue: string
    effectsValue: SystemsEffectFacts
    callsValue: IReadOnlyList<string>

    constructor(
        name: string,
        isHot: bool,
        isBoundary: bool,
        allocNone: bool,
        summarySource: string,
        effects: SystemsEffectFacts,
        calls: IReadOnlyList<string>
    ) {
        nameValue = name
        isHotValue = isHot
        isBoundaryValue = isBoundary
        allocNoneValue = allocNone
        summarySourceValue = summarySource
        effectsValue = effects
        callsValue = calls
    }

    source: string {
        get {
            return "systemsFunction"
        }
    }

    Name: string {
        get {
            return nameValue
        }
    }

    IsHot: bool {
        get {
            return isHotValue
        }
    }

    IsBoundary: bool {
        get {
            return isBoundaryValue
        }
    }

    AllocNone: bool {
        get {
            return allocNoneValue
        }
    }

    SummarySource: string {
        get {
            return summarySourceValue
        }
    }

    Effects: SystemsEffectFacts {
        get {
            return effectsValue
        }
    }

    Calls: IReadOnlyList<string> {
        get {
            return callsValue
        }
    }
}

// `nlc query batch` loads the project AT MOST ONCE and only if some request in the batch actually
// needs it — the C# was `() => snapshot ??= LoadProjectOrThrow(options)` over a local. This holds
// the same one-slot cache so the thunk handed to the runner keeps that exact meaning.
class QuerySnapshotCache {
    options: QueryOptions
    snapshot: ProjectSnapshot?

    constructor(queryOptions: QueryOptions) {
        options = queryOptions
        snapshot = null
    }

    func Get(): ProjectSnapshot {
        loaded := snapshot
        if loaded == null {
            loaded = QueryCommand.LoadProjectOrThrow(options)
            snapshot = loaded
        }

        return loaded
    }
}

// Handles all 'nlc query' subcommands.
// JSON output goes to stdout. Logs/errors go to stderr.
static class QueryCommand {
    static Service: CodeIntelligenceService = new CodeIntelligenceService()

    static docQuery: Lazy<DocQuery> = new Lazy<DocQuery>(() => {
        query := new DocQuery()
        query.LoadSystemAssemblies()
        return query
    })

    static func Execute(args: string[]): int {
        if args.Length == 0 {
            return ShowQueryHelp()
        }

        // Parse global options
        summary := QueryCommandKernels.GetTopLevelOptionSummary(args)
        subcommand := summary.Subcommand ?? ""
        positionalArgs := summary.RemainingArgs
        options := new QueryOptions(
            summary.ProjectDir,
            summary.File,
            summary.Pos,
            summary.UseText,
            summary.NoDaemon,
            summary.InspectCompact
        )

        subcommandKind := QueryCommandDogfoodKernels.GetSubcommandKind(subcommand)

        if subcommandKind == QuerySubcommandKind.Batch {
            return BatchCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Symbols {
            return SymbolsCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Outline {
            return OutlineCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Ast {
            return AstCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Diagnostics {
            return DiagnosticsCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Type {
            return TypeCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Inspect {
            return InspectCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Definition {
            return DefinitionCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.References {
            return ReferencesCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Completions {
            return CompletionsCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Doc {
            return DocCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Hover {
            return HoverCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.CallGraph {
            return CallGraphCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Performance {
            return PerformanceCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Trusted {
            return TrustedCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Implementors {
            return ImplementorsCommand(positionalArgs, options)
        }

        if subcommandKind == QuerySubcommandKind.Help {
            return ShowQueryHelp()
        }

        return QueryError(QueryCommandKernels.GetUnknownSubcommandMessage(subcommand))
    }

    // ── Subcommands ─────────────────────────────────────────────────────

    static func SymbolsCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodSymbols, MaterializeDaemonParameters(args, options), out daemonExitCode) {
            return daemonExitCode
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        commandSummary := QueryCommandKernels.GetCommandOptionSummary(args)
        kindFilter: SymbolKind? = null
        kindArg := summary.Kind
        if kindArg != null {
            parsedKind := QueryCommandKernels.ParseSymbolKind(kindArg)
            if parsedKind.HasValue {
                kindFilter = parsedKind.GetValueOrDefault()
            }
        }

        fileFilter := summary.File ?? options.File
        filterPattern := commandSummary.Filter

        results := Service.GetSymbols(snapshot, fileFilter, kindFilter)

        // Apply fuzzy/glob filter: * = wildcard, bare string = substring match
        if !string.IsNullOrWhiteSpace(filterPattern) {
            pattern := filterPattern ?? ""
            results = QuerySymbolNameFilter.Filter(results, pattern, 200)
        }

        if outputMode == 2 {
            Console.Write(OutputFormatter.SymbolsToText(results))
        } else {
            Console.Write(OutputFormatter.SymbolsToJson(results, snapshot.ProjectRoot))
        }

        return 0
    }

    static func AstCommand(args: string[], options: QueryOptions): int {
        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        fileFilter := summary.File ?? options.File

        units := new List<AstJsonUnit>()
        // The C# ordered the compilation units by ordinal key before rendering; the same ordinal
        // ordering is produced here from the keys themselves, so the AST envelope's unit order does
        // not depend on the dictionary's.
        orderedKeys := new List<string>()
        for pair in snapshot.CompilationUnits {
            orderedKeys.Add(pair.Key)
        }

        orderedKeys.Sort(StringComparer.Ordinal)

        for key in orderedKeys {
            if fileFilter != null {
                if !QueryCommandDogfoodKernels.MatchesCompilationUnitFile(key, fileFilter) {
                    continue
                }
            }

            units.Add(new AstJsonUnit(key, snapshot.CompilationUnits[key]))
        }

        if units.Count == 0 {
            if fileFilter != null {
                return QueryError(QueryCommandKernels.GetNoCompilationUnitForFileMessage(fileFilter))
            }

            return QueryError(QueryCommandKernels.GetNoCompilationUnitsMessage())
        }

        // The AST is structured data; `ast` always emits the stable JSON envelope (LLM-first).
        Console.Write(OutputFormatterAstJsonKernels.AstToJson(units))
        return 0
    }

    static func HoverCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos

        if filePath == null || posStr == null {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("hover"))
        }

        line := 0
        col := 0
        if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        result := Service.GetHoverInfo(snapshot, filePath, line, col)
        if result == null {
            if outputMode == 2 {
                Console.Error.WriteLine(QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col))
            } else {
                Console.Write(OutputFormatter.ErrorToJson(
                    "hover",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    QueryErrorDetailKernels.Position(filePath, line, col)
                ))
            }

            return 1
        }

        if outputMode == 2 {
            Console.Write(OutputFormatter.HoverToText(result, filePath, line, col))
        } else {
            Console.Write(OutputFormatter.HoverToJson(result, filePath, line, col))
        }

        return 0
    }

    static func CallGraphCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        commandSummary := QueryCommandKernels.GetCommandOptionSummary(args)
        functionName := commandSummary.Function
        limit := QueryCommandDogfoodKernels.GetCallGraphLimit(commandSummary.Limit)

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        result := Service.GetCallGraph(snapshot, functionName, limit)

        if outputMode == 2 {
            Console.Write(OutputFormatter.CallGraphToText(result))
        } else {
            Console.Write(OutputFormatter.CallGraphToJson(result))
        }

        return 0
    }

    static func PerformanceCommand(args: string[], options: QueryOptions): int {
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos

        if filePath == null || posStr == null {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("perf"))
        }

        line := 0
        col := 0
        if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
        }

        if QueryCommandKernels.GetJsonOnlyOutputMode(options.UseText) == -1 {
            return QueryError(QueryCommandKernels.GetPerformanceJsonOnlyMessage())
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        facts := new List<object>()
        performanceFacts := snapshot.PerformanceFacts
        if performanceFacts != null {
            for entry in performanceFacts.All {
                key := entry.Key
                value := entry.Value
                // The named tuple's element names (`File`, `Line`, `Column`) do not survive into
                // the referenced assembly's metadata, so the key reads positionally here. Same
                // three values, same order.
                keyFile := key.Item1
                keyLine := key.Item2
                keyColumn := key.Item3
                if QueryCommandDogfoodKernels.MatchesFile(keyFile, filePath) && keyLine == line && keyColumn == col {
                    facts.Add(new QueryPerformanceFactRow(
                        NormalizePath(keyFile ?? filePath),
                        keyLine,
                        keyColumn,
                        value.Allocation.ToString(),
                        value.Capture.ToString(),
                        value.Dispatch.ToString(),
                        value.Escape.ToString(),
                        value.ValueLayout.ToString(),
                        value.AotSafety.ToString()
                    ))
                }
            }
        }

        for finding in snapshot.SystemsReport.Findings {
            if QueryCommandDogfoodKernels.MatchesFile(finding.File, filePath) && finding.Line == line {
                facts.Add(new QuerySystemsFactRow(
                    finding.Code,
                    finding.Severity,
                    finding.Effect,
                    finding.Message,
                    finding.Function,
                    finding.Policy,
                    finding.Suggestion
                ))
            }
        }

        for function in snapshot.SystemsReport.Functions {
            if QueryCommandDogfoodKernels.MatchesFile(function.File, filePath) && function.Line == line {
                facts.Add(new QuerySystemsFunctionFactRow(
                    function.Name,
                    function.IsHot,
                    function.IsBoundary,
                    function.AllocNone,
                    function.SummarySource,
                    function.Effects,
                    function.Calls
                ))
            }
        }

        Console.Write(OutputFormatter.PerfToJson(filePath, line, col, snapshot.ProjectRoot, facts))
        return 0
    }

    static func TrustedCommand(args: string[], options: QueryOptions): int {
        if QueryCommandKernels.GetJsonOnlyOutputMode(options.UseText) == -1 {
            return QueryError(QueryCommandKernels.GetTrustedJsonOnlyMessage())
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        Console.Write(OutputFormatter.TrustedToJson(snapshot.SystemsReport, snapshot.ProjectRoot))
        return 0
    }

    static func ImplementorsCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        name := summary.Name
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos

        // Name-based lookup (primary)
        if name != null {
            snapshot := LoadProjectOrFail(options)
            if snapshot == null {
                return 1
            }

            result := Service.GetImplementors(snapshot, name)

            if outputMode == 2 {
                Console.Write(OutputFormatter.ImplementorsToText(result))
            } else {
                Console.Write(OutputFormatter.ImplementorsToJson(result))
            }

            return QueryCommandKernels.GetResultPresenceExitCode(result.Results.Count)
        }

        // Position-based: resolve the interface name at position, then find implementors
        if filePath != null && posStr != null {
            line := 0
            col := 0
            if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
                return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
            }

            snapshot := LoadProjectOrFail(options)
            if snapshot == null {
                return 1
            }

            definition := Service.FindDefinition(snapshot, filePath, line, col)
            if definition == null || !QueryCommandKernels.IsInterfaceKind(definition.Kind) {
                if outputMode == 2 {
                    Console.Error.WriteLine(QueryCommandKernels.GetNoInterfaceAtPositionMessage(filePath, line, col))
                } else {
                    Console.Write(OutputFormatter.ErrorToJson(
                        "implementors",
                        QueryCommandKernels.GetNoInterfaceAtPositionMessage(filePath, line, col),
                        GetProjectRoot(options),
                        "noInterface",
                        QueryErrorDetailKernels.Position(filePath, line, col)
                    ))
                }

                return 1
            }

            result := Service.GetImplementors(snapshot, definition.Name)

            if outputMode == 2 {
                Console.Write(OutputFormatter.ImplementorsToText(result))
            } else {
                Console.Write(OutputFormatter.ImplementorsToJson(result))
            }

            return QueryCommandKernels.GetResultPresenceExitCode(result.Results.Count)
        }

        return QueryError(QueryCommandKernels.GetImplementorsUsageMessage())
    }

    static func BatchCommand(args: string[], options: QueryOptions): int {
        if QueryCommandKernels.GetJsonOnlyOutputMode(options.UseText) == -1 {
            return QueryError(QueryCommandKernels.GetBatchJsonOnlyMessage())
        }

        commandSummary := QueryCommandKernels.GetCommandOptionSummary(args)
        requestsPath := commandSummary.Requests ?? commandSummary.LeadingOperand

        if string.IsNullOrWhiteSpace(requestsPath) {
            return QueryError(QueryCommandKernels.GetBatchUsageMessage())
        }

        path := requestsPath ?? ""
        requests: List<BatchQueryRequest> = new List<BatchQueryRequest>()
        try {
            requests = BatchQueryRunner.LoadRequests(path)
        } catch ex: Exception {
            Console.Write(OutputFormatter.ErrorToJson(
                "batch",
                ex.Message,
                GetProjectRoot(options),
                "invalidRequestsFile",
                QueryErrorDetailKernels.Requests(path)
            ))
            return 1
        }

        if requests.Count == 0 {
            Console.Write(OutputFormatter.ErrorToJson(
                "batch",
                QueryCommandKernels.GetEmptyBatchMessage(),
                GetProjectRoot(options),
                "emptyBatch",
                QueryErrorDetailKernels.Requests(path)
            ))
            return 1
        }

        daemonParameters := new Dictionary<string, object?>()
        daemonParameters["requests"] = requests
        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodBatch, daemonParameters, out daemonExitCode) {
            return daemonExitCode
        }

        cache := new QuerySnapshotCache(options)
        execution := BatchQueryRunner.Execute(
            requests,
            GetProjectRoot(options),
            () => cache.Get(),
            Service,
            new CompletionEngine()
        )

        Console.Write(execution.Json)
        return QueryCommandKernels.GetBooleanSuccessExitCode(execution.Ok)
    }

    static func OutlineCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        // Outline can work on a single file without full project analysis
        commandSummary := QueryCommandKernels.GetCommandOptionSummary(args)
        filePath := commandSummary.LeadingOperand ?? options.File

        if filePath == null {
            return QueryError(QueryCommandKernels.GetOutlineUsageMessage())
        }

        projectRoot := QueryCommandDogfoodKernels.GetProjectRoot(options.ProjectDir, Directory.GetCurrentDirectory())
        resolvedPath := QueryCommandDogfoodKernels.ResolveProjectFilePath(projectRoot, filePath)

        if !File.Exists(resolvedPath) {
            return QueryError(QueryCommandKernels.GetFileNotFoundMessage(resolvedPath))
        }

        // Use single-file fast path
        result := Service.GetOutlineSingleFile(resolvedPath)

        // Make the file path relative to project root for output
        relativePath := QueryCommandDogfoodKernels.GetRelativePath(projectRoot, resolvedPath)
        result = QueryCommandDogfoodKernels.WithOutlineFile(result, relativePath)

        if outputMode == 2 {
            Console.Write(OutputFormatter.OutlineToText(result))
        } else {
            Console.Write(OutputFormatter.OutlineToJson(result))
        }

        return 0
    }

    static func DiagnosticsCommand(args: string[], options: QueryOptions): int {
        parameterSummary := QueryCommandKernels.GetDaemonParameterSummary(args)
        wantsClusters := parameterSummary.Clusters
        outputMode := QueryCommandKernels.GetDiagnosticsOutputMode(options.UseText, wantsClusters)
        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodDiagnostics, MaterializeDaemonParameters(args, options), out daemonExitCode) {
            return daemonExitCode
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        fileFilter := parameterSummary.File ?? options.File
        results: List<DiagnosticResult> = Service.GetDiagnostics(snapshot, fileFilter)

        // Filter by severity if requested
        severityFilter := parameterSummary.Severity
        if severityFilter != null {
            results = OutputFormatter.FilterDiagnosticsBySeverity(results, severityFilter)
        }

        summary := OutputFormatter.SummarizeDiagnostics(results)
        if outputMode == 3 {
            Console.Write(OutputFormatter.DiagnosticClustersToJson(results, snapshot.ProjectRoot))
        } else if outputMode == 2 {
            Console.Write(OutputFormatter.DiagnosticsToText(results))
        } else {
            Console.Write(OutputFormatter.DiagnosticsToJson(results, snapshot.ProjectRoot))
        }

        return QueryCommandKernels.GetDiagnosticSummaryExitCode(summary.Errors)
    }

    static func TypeCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos

        if filePath == null || posStr == null {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("type"))
        }

        line := 0
        col := 0
        if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
        }

        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodType, MaterializeDaemonParameters(args, options), out daemonExitCode) {
            return daemonExitCode
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        result := Service.GetTypeAtPosition(snapshot, filePath, line, col)
        if result == null {
            if outputMode == 2 {
                Console.Error.WriteLine(QueryCommandKernels.GetNoTypeInformationAtPositionMessage(filePath, line, col))
            } else {
                Console.Write(OutputFormatter.ErrorToJson(
                    "type",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    QueryErrorDetailKernels.Position(filePath, line, col)
                ))
            }

            return 1
        }

        if outputMode == 2 {
            Console.Write(OutputFormatter.TypeToText(result, filePath, line, col))
        } else {
            Console.Write(OutputFormatter.TypeToJson(result, filePath, line, col))
        }

        return 0
    }

    static func DefinitionCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos
        name := summary.Name

        if name != null {
            snapshot := LoadProjectOrFail(options)
            if snapshot == null {
                return 1
            }

            // All three arguments are written out: omitting a defaulted parameter at a
            // same-compilation call site declines on the bootstrap SDK that builds this project
            // (census-briefs/CLI2-COMPILER-BLOCKERS.md, entry 18).
            symbols := Service.GetSymbols(snapshot, null, null)
            results := DefinitionSearchKernels.FindDefinitions(symbols, name, 200)
            if outputMode == 2 {
                Console.Write(OutputFormatter.DefinitionSearchToText(name, results))
            } else {
                Console.Write(OutputFormatter.DefinitionSearchToJson(name, results))
            }

            return QueryCommandKernels.GetResultPresenceExitCode(results.Count)
        }

        // Position-based (primary, semantic)
        if filePath != null && posStr != null {
            line := 0
            col := 0
            if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
                return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
            }

            daemonExitCode := 0
            if TryExecuteViaDaemon(options, DaemonConstants.MethodDefinition, MaterializeDaemonParameters(args, options), out daemonExitCode) {
                return daemonExitCode
            }

            snapshot := LoadProjectOrFail(options)
            if snapshot == null {
                return 1
            }

            result := Service.FindDefinition(snapshot, filePath, line, col)
            if result == null {
                if outputMode == 2 {
                    Console.Error.WriteLine(QueryCommandKernels.GetNoDefinitionAtPositionMessage(filePath, line, col))
                } else {
                    Console.Write(OutputFormatter.ErrorToJson(
                        "definition",
                        QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                        GetProjectRoot(options),
                        "noSymbol",
                        QueryErrorDetailKernels.Position(filePath, line, col)
                    ))
                }

                return 1
            }

            if outputMode == 2 {
                Console.Write(OutputFormatter.DefinitionToText(result))
            } else {
                Console.Write(OutputFormatter.DefinitionToJson(result))
            }

            return 0
        }

        return QueryError(QueryCommandKernels.GetDefinitionUsageMessage())
    }

    static func InspectCommand(args: string[], options: QueryOptions): int {
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos
        outputMode := QueryCommandKernels.GetInspectOutputMode(options.UseText, options.InspectCompact)
        compactMode := outputMode == 2

        if filePath == null || posStr == null {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("inspect"))
        }

        if outputMode == -1 {
            return QueryError(QueryCommandKernels.GetInspectCompactTextUnsupportedMessage())
        }

        line := 0
        col := 0
        if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
        }

        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodInspect, MaterializeDaemonParameters(args, options), out daemonExitCode) {
            return daemonExitCode
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        typeResult := Service.GetTypeAtPosition(snapshot, filePath, line, col)
        definition := Service.FindDefinition(snapshot, filePath, line, col)
        references := Service.FindReferences(snapshot, filePath, line, col)

        includeKeywords := summary.IncludeKeywords
        engine := new CompletionEngine()
        completions := engine.GetCompletions(snapshot, filePath, line, col, includeKeywords)

        symbol: InspectSymbolResult? = null
        if definition != null {
            symbol = new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column)
            )
        } else if typeResult != null {
            symbol = new InspectSymbolResult(typeResult.Name, typeResult.Kind, typeResult.Definition)
        }

        definitionCount := references.Count(reference => reference.IsDefinition)
        inspect := new InspectResult(
            symbol,
            typeResult,
            definition,
            new InspectReferencesResult(
                references.Count,
                definitionCount,
                references.ToArray()
            ),
            completions
        )

        if typeResult == null && definition == null && references.Count == 0 {
            if outputMode == 3 {
                Console.Error.WriteLine(QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col))
            } else {
                Console.Write(OutputFormatter.ErrorToJson(
                    "inspect",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    QueryErrorDetailKernels.Position(filePath, line, col)
                ))
            }

            return 1
        }

        if outputMode == 3 {
            Console.Write(OutputFormatter.InspectToText(inspect, filePath, line, col))
        } else if compactMode {
            Console.Write(OutputFormatter.InspectSummaryToJson(inspect, filePath, line, col))
        } else {
            Console.Write(OutputFormatter.InspectToJson(inspect, filePath, line, col))
        }

        return 0
    }

    static func ReferencesCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos

        if filePath == null || posStr == null {
            return QueryError(QueryCommandKernels.GetReferencesUsageMessage())
        }

        line := 0
        col := 0
        if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
        }

        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodReferences, MaterializeDaemonParameters(args, options), out daemonExitCode) {
            return daemonExitCode
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        // First resolve what symbol is at this position
        definition := Service.FindDefinition(snapshot, filePath, line, col)
        if definition == null {
            if outputMode == 2 {
                Console.Error.WriteLine(QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col))
            } else {
                Console.Write(OutputFormatter.ErrorToJson(
                    "references",
                    QueryCommandKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                    GetProjectRoot(options),
                    "noSymbol",
                    QueryErrorDetailKernels.Position(filePath, line, col)
                ))
            }

            return 1
        }

        symbolName := definition.Name
        symbolKind := definition.Kind
        definedAt := new LocationResult(definition.File, definition.Line, definition.Column)

        results := Service.FindReferences(snapshot, filePath, line, col)
        if results.Count == 0 {
            message := QueryCommandKernels.GetSemanticReferencesUnavailableMessage()

            if outputMode == 2 {
                Console.Error.WriteLine(message)
            } else {
                Console.Write(OutputFormatter.ErrorToJson(
                    "references",
                    message,
                    GetProjectRoot(options),
                    "semanticReferencesUnavailable",
                    QueryErrorDetailKernels.SemanticReferencesUnavailable(
                        filePath,
                        line,
                        col,
                        symbolName,
                        symbolKind,
                        definedAt
                    )
                ))
            }

            return 1
        }

        if outputMode == 2 {
            Console.Write(OutputFormatter.ReferencesToText(symbolName, results))
        } else {
            Console.Write(OutputFormatter.ReferencesToJson(symbolName, symbolKind, definedAt, results))
        }

        return 0
    }

    static func CompletionsCommand(args: string[], options: QueryOptions): int {
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)
        summary := QueryCommandKernels.GetDaemonParameterSummary(args)
        filePath := summary.File ?? options.File
        posStr := summary.Pos ?? options.Pos

        if filePath == null || posStr == null {
            return QueryError(QueryCommandKernels.GetPositionUsageMessage("completions"))
        }

        line := 0
        col := 0
        if !QueryCommandKernels.ParsePosition(posStr, out line, out col) {
            return QueryError(QueryCommandKernels.GetInvalidPositionMessage(posStr))
        }

        daemonExitCode := 0
        if TryExecuteViaDaemon(options, DaemonConstants.MethodCompletions, MaterializeDaemonParameters(args, options), out daemonExitCode) {
            return daemonExitCode
        }

        snapshot := LoadProjectOrFail(options)
        if snapshot == null {
            return 1
        }

        includeKeywords := summary.IncludeKeywords
        engine := new CompletionEngine()
        result := engine.GetCompletions(snapshot, filePath, line, col, includeKeywords)

        if outputMode == 2 {
            Console.Write(OutputFormatter.CompletionsToText(result, filePath, line, col))
        } else {
            Console.Write(OutputFormatter.CompletionsToJson(result, filePath, line, col))
        }

        return 0
    }

    static func DocCommand(args: string[], options: QueryOptions): int {
        commandSummary := QueryCommandKernels.GetCommandOptionSummary(args)
        query := commandSummary.LeadingOperand
        outputMode := QueryCommandKernels.GetTextJsonOutputMode(options.UseText)

        if query == null {
            return QueryError(QueryCommandKernels.GetDocUsageMessage())
        }

        lookup := docQuery.Value
        result := lookup.Lookup(query)
        if result == null {
            miss := lookup.DescribeLookupMiss(query)
            message := QueryCommandKernels.GetNoDocumentationMessage(query, miss)
            if outputMode == 2 {
                Console.Error.WriteLine(message)
            } else {
                Console.Write(OutputFormatter.ErrorToJson("doc", message, null, null, null))
            }

            return 1
        }

        if outputMode == 2 {
            Console.Write(OutputFormatter.DocToText(result))
        } else {
            Console.Write(OutputFormatter.DocToJson(result, query))
        }

        return 0
    }

    // ── Option Parsing ──────────────────────────────────────────────────

    static func LoadProjectOrFail(options: QueryOptions): ProjectSnapshot? {
        projectDir := GetProjectRoot(options)

        if !Directory.Exists(projectDir) {
            Console.Error.WriteLine(QueryCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir))
            return null
        }

        try {
            config := ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault(QueryCommandDogfoodKernels.GetDefaultProjectName(projectDir))
            // `nlc query` is a read-only/LLM-first inspection path: it must never spawn `dotnet build`
            // for project references (multi-second stalls + the build-pipe deadlock) (H4). Resolve
            // package/already-resolved references only; cross-project resolution requires `nlc build`.
            CompilationReferenceResolver.AddResolvedDllReferences(
                projectDir,
                config,
                QuietResolutionOptions()
            )
            return Service.LoadProject(projectDir, config, null)
        } catch ex: Exception {
            Console.Error.WriteLine(QueryCommandKernels.GetFailedAnalyzeProjectMessage(ex.Message))
            return null
        }
    }

    static func LoadProjectOrThrow(options: QueryOptions): ProjectSnapshot {
        projectDir := GetProjectRoot(options)

        if !Directory.Exists(projectDir) {
            throw new DirectoryNotFoundException(QueryCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir))
        }

        config := ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault(QueryCommandDogfoodKernels.GetDefaultProjectName(projectDir))
        // Read-only query path: never spawn `dotnet build` for project references (H4).
        CompilationReferenceResolver.AddResolvedDllReferences(
            projectDir,
            config,
            QuietResolutionOptions()
        )
        return Service.LoadProject(projectDir, config, null)
    }

    static func QuietResolutionOptions(): ReferenceResolutionOptions {
        resolutionOptions := new ReferenceResolutionOptions()
        resolutionOptions.Quiet = true
        resolutionOptions.BuildProjectReferences = false
        return resolutionOptions
    }

    static func NormalizePath(path: string): string {
        return OutputFormatterNormalizationKernels.NormalizePath(path) ?? path
    }

    static func GetProjectRoot(options: QueryOptions): string {
        return QueryCommandDogfoodKernels.GetProjectRoot(options.ProjectDir, Directory.GetCurrentDirectory())
    }

    static func MaterializeDaemonParameters(args: string[], options: QueryOptions): Dictionary<string, object?> {
        plan := QueryCommandDogfoodKernels.GetDaemonParameterPlan(args, options)
        parameters := new Dictionary<string, object?>()
        if plan.File != null {
            parameters["file"] = plan.File
        }

        if plan.Pos != null {
            parameters["pos"] = plan.Pos
        }

        if plan.Name != null {
            parameters["name"] = plan.Name
        }

        if plan.Kind != null {
            parameters["kind"] = plan.Kind
        }

        if plan.Severity != null {
            parameters["severity"] = plan.Severity
        }

        if plan.IncludeKeywords {
            parameters["includeKeywords"] = true
        }

        if plan.Summary {
            parameters["summary"] = true
        }

        if plan.Clusters {
            parameters["clusters"] = true
        }

        return parameters
    }

    static func TryExecuteViaDaemon(
        options: QueryOptions,
        method: string,
        parameters: Dictionary<string, object?>,
        out exitCode: int
    ): bool {
        exitCode = 0
        methodKind := DaemonProtocolKernels.GetMethodKind(method)
        if !QueryCommandDogfoodKernels.ShouldUseDaemon(options.UseText, options.NoDaemon, methodKind) {
            return false
        }

        projectRoot := GetProjectRoot(options)
        if !Directory.Exists(projectRoot) {
            return false
        }

        if !DaemonClient.IsRunning(projectRoot) {
            return false
        }

        response := DaemonClient.QueryResponse(projectRoot, method, parameters)
        if response == null {
            return false
        }

        error := response.Error
        if error != null {
            Console.Error.WriteLine(DaemonProtocolKernels.ErrorResponseJson(response.Id, error.Code, error.Message))
            exitCode = 1
            return true
        }

        result := response.Result
        if string.IsNullOrWhiteSpace(result) {
            return false
        }

        resultJson := result ?? ""
        Console.Write(resultJson)
        exitCode = GetJsonExitCode(resultJson)
        return true
    }

    static func GetJsonExitCode(json: string): int {
        return QueryCommandDogfoodKernels.GetDaemonJsonExitCodeFromJson(json)
    }

    static func QueryError(message: string): int {
        Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message))
        return 1
    }

    static func FormatQueryDescription(command: CliCommandSpec): string {
        aliases := new List<string>()
        for candidate in CommandRegistry.QueryCommands {
            if QueryCommandDogfoodKernels.IsAliasOf(candidate.AliasOf, command.Name) {
                aliases.Add(candidate.Name)
            }
        }

        return QueryCommandKernels.GetDescriptionWithAliases(
            command.Description,
            string.Join(", ", aliases)
        )
    }

    static func ShowQueryHelp(): int {
        lines := new List<string>()
        for command in CommandRegistry.QueryCommands {
            if !command.IsAlias {
                // `$"  {command.Name,-13} {description}"` — the C# spelling — is left-alignment in
                // an interpolation hole; `PadRight(13)` is the same string.
                lines.Add("  " + command.Name.PadRight(13) + " " + FormatQueryDescription(command))
            }
        }

        commandLines := string.Join(Environment.NewLine, lines)
        Console.WriteLine(QueryCommandKernels.GetHelpText(commandLines))

        return 0
    }
}

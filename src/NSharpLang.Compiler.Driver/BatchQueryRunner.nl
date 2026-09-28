namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Linq
import System.Text.Json
import System.Text.Json.Serialization
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// One batch request as it arrives, either from a --requests file or from the daemon's `query/batch`
// params. The member names and their order are the wire: the CLI serializes this list straight into
// the daemon's params, and the daemon deserializes it back, so the four flags keep
// `WhenWritingDefault` and nothing is renamed. Everything the request MEANS — what "symbols" is,
// which fields each command requires, what a duplicate id is — belongs to the batch kernels.
class BatchQueryRequest {
    commandValue: string
    idValue: string?
    fileValue: string?
    posValue: string?
    nameValue: string?
    queryValue: string?
    kindValue: string?
    severityValue: string?
    includeKeywordsValue: bool
    summaryValue: bool
    compactValue: bool
    clustersValue: bool

    constructor() {
        commandValue = ""
        idValue = null
        fileValue = null
        posValue = null
        nameValue = null
        queryValue = null
        kindValue = null
        severityValue = null
        includeKeywordsValue = false
        summaryValue = false
        compactValue = false
        clustersValue = false
    }

    Command: string {
        get {
            return commandValue
        }
        set {
            commandValue = value
        }
    }

    Id: string? {
        get {
            return idValue
        }
        set {
            idValue = value
        }
    }

    File: string? {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Pos: string? {
        get {
            return posValue
        }
        set {
            posValue = value
        }
    }

    Name: string? {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    Query: string? {
        get {
            return queryValue
        }
        set {
            queryValue = value
        }
    }

    Kind: string? {
        get {
            return kindValue
        }
        set {
            kindValue = value
        }
    }

    Severity: string? {
        get {
            return severityValue
        }
        set {
            severityValue = value
        }
    }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    IncludeKeywords: bool {
        get {
            return includeKeywordsValue
        }
        set {
            includeKeywordsValue = value
        }
    }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    Summary: bool {
        get {
            return summaryValue
        }
        set {
            summaryValue = value
        }
    }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    Compact: bool {
        get {
            return compactValue
        }
        set {
            compactValue = value
        }
    }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    Clusters: bool {
        get {
            return clustersValue
        }
        set {
            clustersValue = value
        }
    }
}

// The one place a list of batch requests turns into a list of answers, whoever asked. `nlc query
// batch` calls it in-process and the daemon calls it with its warm snapshot, and because they call
// the SAME runner the two routes cannot answer differently — which is the whole point of the type.
//
// The snapshot arrives as a `Func<ProjectSnapshot>` rather than a snapshot because a batch whose
// every command is `doc` must never load a project; the thunk is what makes "load only if some
// command needs it" a property of the code.
class BatchQueryRunner {
    static requestJsonOptions: JsonSerializerOptions = CreateRequestJsonOptions()

    static docQuery: Lazy<DocQuery> = new Lazy<DocQuery>(() => {
        query := new DocQuery()
        query.LoadSystemAssemblies()
        return query
    })

    static func CreateRequestJsonOptions(): JsonSerializerOptions {
        options := new JsonSerializerOptions()
        options.PropertyNameCaseInsensitive = true
        return options
    }

    static func LoadRequests(path: string): List<BatchQueryRequest> {
        if !File.Exists(path) {
            throw new FileNotFoundException(BatchQueryKernels.GetRequestsFileNotFoundMessage(path))
        }

        text := File.ReadAllText(path)
        using document := JsonDocument.Parse(text)

        rootElement := document.RootElement
        nestedRequests: JsonElement = default
        hasNestedRequests := rootElement.ValueKind == JsonValueKind.Object && rootElement.TryGetProperty("requests", out nestedRequests)
        rootIsArray := rootElement.ValueKind == JsonValueKind.Array
        rootIsObject := rootElement.ValueKind == JsonValueKind.Object
        nestedRequestsIsArray := hasNestedRequests && nestedRequests.ValueKind == JsonValueKind.Array
        payloadShape := BatchQueryValidationKernels.GetPayloadShapeKind(rootIsArray, rootIsObject, hasNestedRequests, nestedRequestsIsArray)

        requestsElement: JsonElement = default
        if payloadShape == BatchQueryPayloadShapeKind.RootArray {
            requestsElement = rootElement
        } else if payloadShape == BatchQueryPayloadShapeKind.NestedRequestsArray {
            requestsElement = nestedRequests
        } else {
            throw new InvalidDataException(BatchQueryKernels.GetPayloadShapeMessage())
        }

        requests := new List<BatchQueryRequest>()
        for item in requestsElement.EnumerateArray() {
            if !BatchQueryValidationKernels.IsRequestItemObject(item.ValueKind == JsonValueKind.Object) {
                throw new InvalidDataException(BatchQueryKernels.GetRequestObjectRequiredMessage())
            }

            // `item.Deserialize<T>(options)` — the JsonElement extension — declines at
            // emit.call.generic-unresolved; reading the element's own raw text through the
            // serializer is the same deserialization of the same bytes with the same options.
            itemJson := item.GetRawText()
            request := JsonSerializer.Deserialize<BatchQueryRequest>(itemJson, requestJsonOptions)
            if request == null {
                throw new InvalidDataException(BatchQueryKernels.GetRequestDeserializeFailedMessage())
            }

            // The C# record made a copy with the normalized command; the copy was added and the
            // original dropped, so normalizing in place is the same list.
            request.Command = BatchQueryKernels.NormalizeCommand(request.Command)
            requests.Add(request)
        }

        // The kernel reads ids off `IReadOnlyList<object>`. The covariant widening
        // `List<BatchQueryRequest>` -> `IReadOnlyList<object>` declines at
        // emit.typed-local.type-mismatch, so the same elements are handed over in an object list.
        requestObjects := new List<object>(requests.Count)
        for request in requests {
            requestObjects.Add(request)
        }

        duplicateIds := BatchQueryKernels.FindDuplicateRequestIds(requestObjects)
        if duplicateIds.Length > 0 {
            throw new InvalidDataException(BatchQueryKernels.GetDuplicateRequestIdsMessage(string.Join(", ", duplicateIds)))
        }

        return requests
    }

    static func Execute(
        requests: IReadOnlyList<BatchQueryRequest>,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService,
        completionEngine: CompletionEngine
    ): BatchQueryExecutionResult {
        items := new List<BatchQueryOutputItem>(requests.Count)
        okWords := new ulong[]((requests.Count + 63) >> 6)

        i := 0
        while i < requests.Count {
            request := requests[i]
            responseJson := ExecuteSingle(request, projectRoot, getSnapshot, service, completionEngine)
            using responseDocument := JsonDocument.Parse(responseJson)
            response := responseDocument.RootElement.Clone()
            okElement: JsonElement = default
            ok := response.TryGetProperty("ok", out okElement) && okElement.ValueKind == JsonValueKind.True
            if ok {
                bit: ulong = 1
                okWords[i >> 6] = okWords[i >> 6] | (bit << (i & 63))
            }

            items.Add(new BatchQueryOutputItem(i, request.Id, NormalizeForOutput(request), ok, response))
            i = i + 1
        }

        summary := BatchQueryKernels.SummarizeExecutionResults(okWords, items.Count)

        return new BatchQueryExecutionResult(
            BatchQueryOutputKernels.BuildExecutionResultJson(projectRoot, items, summary.SuccessCount, summary.FailureCount),
            summary.Ok,
            items.Count,
            summary.SuccessCount,
            summary.FailureCount
        )
    }

    static func ExecuteSingle(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService,
        completionEngine: CompletionEngine
    ): string {
        normalizedCommand := BatchQueryKernels.NormalizeCommand(request.Command)
        commandKind := BatchQueryKernels.GetCommandKind(normalizedCommand)
        try {
            if commandKind == BatchQueryCommandKind.Symbols {
                return ExecuteSymbols(request, getSnapshot, service)
            }

            if commandKind == BatchQueryCommandKind.Outline {
                return ExecuteOutline(request, projectRoot, getSnapshot, service)
            }

            if commandKind == BatchQueryCommandKind.Diagnostics {
                return ExecuteDiagnostics(request, getSnapshot, service)
            }

            if commandKind == BatchQueryCommandKind.Type {
                return ExecuteType(request, projectRoot, getSnapshot, service)
            }

            if commandKind == BatchQueryCommandKind.Inspect {
                return ExecuteInspect(request, projectRoot, getSnapshot, service, completionEngine)
            }

            if commandKind == BatchQueryCommandKind.Definition {
                return ExecuteDefinition(request, projectRoot, getSnapshot, service)
            }

            if commandKind == BatchQueryCommandKind.References {
                return ExecuteReferences(request, projectRoot, getSnapshot, service)
            }

            if commandKind == BatchQueryCommandKind.Completions {
                return ExecuteCompletions(request, projectRoot, getSnapshot, completionEngine)
            }

            if commandKind == BatchQueryCommandKind.Doc {
                return ExecuteDoc(request)
            }

            return OutputFormatter.ErrorToJson(
                normalizedCommand,
                BatchQueryKernels.GetUnsupportedCommandMessage(normalizedCommand),
                projectRoot,
                "unsupportedCommand",
                null
            )
        } catch ex: Exception {
            return OutputFormatter.ErrorToJson(normalizedCommand, ex.Message, projectRoot, "executionFailed", null)
        }
    }

    static func ExecuteSymbols(request: BatchQueryRequest, getSnapshot: Func<ProjectSnapshot>, service: CodeIntelligenceService): string {
        kindFilter: SymbolKind? = null
        if !string.IsNullOrWhiteSpace(request.Kind) {
            parsedKind := QueryCommandKernels.ParseSymbolKind(request.Kind)
            if parsedKind.HasValue {
                kindFilter = parsedKind.GetValueOrDefault()
            }
        }

        snapshot := getSnapshot()
        results := service.GetSymbols(snapshot, request.File, kindFilter)
        return OutputFormatter.SymbolsToJson(results, snapshot.ProjectRoot)
    }

    static func ExecuteOutline(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService
    ): string {
        if !BatchQueryValidationKernels.HasRequiredInput(BatchQueryCommandKind.Outline, request.File, request.Pos, request.Query) {
            return InvalidMissingRequiredInput(BatchQueryCommandKind.Outline, projectRoot, request)
        }

        snapshot := getSnapshot()
        requestFile := request.File ?? ""
        result := service.GetOutline(snapshot, requestFile)
        return OutputFormatter.OutlineToJson(result)
    }

    static func ExecuteDiagnostics(request: BatchQueryRequest, getSnapshot: Func<ProjectSnapshot>, service: CodeIntelligenceService): string {
        snapshot := getSnapshot()
        results: List<DiagnosticResult> = service.GetDiagnostics(snapshot, request.File)
        if !string.IsNullOrWhiteSpace(request.Severity) {
            severity := request.Severity ?? ""
            results = OutputFormatter.FilterDiagnosticsBySeverity(results, severity)
        }

        if request.Clusters {
            return OutputFormatter.DiagnosticClustersToJson(results, snapshot.ProjectRoot)
        }

        return OutputFormatter.DiagnosticsToJson(results, snapshot.ProjectRoot)
    }

    static func ExecuteType(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService
    ): string {
        position := ResolveFileAndPosition(request, projectRoot, BatchQueryCommandKind.Type)
        if !position.IsValid {
            return position.Invalid
        }

        resolvedFile := position.File
        line := position.Line
        column := position.Column
        snapshot := getSnapshot()
        result := service.GetTypeAtPosition(snapshot, resolvedFile, line, column)
        if result == null {
            return OutputFormatter.ErrorToJson(
                "type",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                QueryErrorDetailKernels.Position(resolvedFile, line, column)
            )
        }

        return OutputFormatter.TypeToJson(result, resolvedFile, line, column)
    }

    static func ExecuteInspect(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService,
        completionEngine: CompletionEngine
    ): string {
        position := ResolveFileAndPosition(request, projectRoot, BatchQueryCommandKind.Inspect)
        if !position.IsValid {
            return position.Invalid
        }

        resolvedFile := position.File
        line := position.Line
        column := position.Column
        snapshot := getSnapshot()
        typeResult := service.GetTypeAtPosition(snapshot, resolvedFile, line, column)
        definition := service.FindDefinition(snapshot, resolvedFile, line, column)
        references: List<ReferenceResult> = new List<ReferenceResult>()
        if definition != null {
            references = service.FindReferences(snapshot, resolvedFile, line, column)
        }

        completions := completionEngine.GetCompletions(snapshot, resolvedFile, line, column, request.IncludeKeywords)

        if typeResult == null && definition == null && references.Count == 0 {
            return OutputFormatter.ErrorToJson(
                "inspect",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                QueryErrorDetailKernels.Position(resolvedFile, line, column)
            )
        }

        inspect := BuildInspectResult(SymbolOf(definition, typeResult), typeResult, definition, references, completions)

        if request.Summary || request.Compact {
            return OutputFormatter.InspectSummaryToJson(inspect, resolvedFile, line, column)
        }

        return OutputFormatter.InspectToJson(inspect, resolvedFile, line, column)
    }

    static func ExecuteDefinition(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService
    ): string {
        // The C# asked for the snapshot before validating, so a `definition` request with no file
        // still loaded the project. Keeping that order keeps the timing and the failure the same.
        snapshot := getSnapshot()

        position := ResolveFileAndPosition(request, projectRoot, BatchQueryCommandKind.Definition)
        if !position.IsValid {
            return position.Invalid
        }

        resolvedFile := position.File
        line := position.Line
        column := position.Column
        result := service.FindDefinition(snapshot, resolvedFile, line, column)
        if result == null {
            return OutputFormatter.ErrorToJson(
                "definition",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                QueryErrorDetailKernels.Position(resolvedFile, line, column)
            )
        }

        return OutputFormatter.DefinitionToJson(result)
    }

    static func ExecuteReferences(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        service: CodeIntelligenceService
    ): string {
        position := ResolveFileAndPosition(request, projectRoot, BatchQueryCommandKind.References)
        if !position.IsValid {
            return position.Invalid
        }

        resolvedFile := position.File
        line := position.Line
        column := position.Column
        snapshot := getSnapshot()
        definition := service.FindDefinition(snapshot, resolvedFile, line, column)
        if definition == null {
            return OutputFormatter.ErrorToJson(
                "references",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                QueryErrorDetailKernels.Position(resolvedFile, line, column)
            )
        }

        definedAt := new LocationResult(definition.File, definition.Line, definition.Column)
        results := service.FindReferences(snapshot, resolvedFile, line, column)
        if results.Count == 0 {
            return OutputFormatter.ErrorToJson(
                "references",
                QueryCommandKernels.GetSemanticReferencesUnavailableMessage(),
                snapshot.ProjectRoot,
                "semanticReferencesUnavailable",
                QueryErrorDetailKernels.SemanticReferencesUnavailable(
                    resolvedFile,
                    line,
                    column,
                    definition.Name,
                    definition.Kind,
                    definedAt
                )
            )
        }

        return OutputFormatter.ReferencesToJson(definition.Name, definition.Kind, definedAt, results)
    }

    static func ExecuteCompletions(
        request: BatchQueryRequest,
        projectRoot: string?,
        getSnapshot: Func<ProjectSnapshot>,
        completionEngine: CompletionEngine
    ): string {
        position := ResolveFileAndPosition(request, projectRoot, BatchQueryCommandKind.Completions)
        if !position.IsValid {
            return position.Invalid
        }

        resolvedFile := position.File
        line := position.Line
        column := position.Column
        snapshot := getSnapshot()
        result := completionEngine.GetCompletions(snapshot, resolvedFile, line, column, request.IncludeKeywords)
        return OutputFormatter.CompletionsToJson(result, resolvedFile, line, column)
    }

    static func ExecuteDoc(request: BatchQueryRequest): string {
        if !BatchQueryValidationKernels.HasRequiredInput(BatchQueryCommandKind.Doc, request.File, request.Pos, request.Query) {
            return InvalidMissingRequiredInput(BatchQueryCommandKind.Doc, null, request)
        }

        query := request.Query ?? ""
        lookup := docQuery.Value
        result := lookup.Lookup(query)
        if result == null {
            miss := lookup.DescribeLookupMiss(query)
            return OutputFormatter.ErrorToJson("doc", QueryCommandKernels.GetNoDocumentationMessage(query, miss), null, null, null)
        }

        return OutputFormatter.DocToJson(result, query)
    }

    // The C# `TryGetFileAndPosition` answered through four `out` parameters; one carrier says the
    // same thing and keeps every caller's shape identical.
    static func ResolveFileAndPosition(
        request: BatchQueryRequest,
        projectRoot: string?,
        commandKind: BatchQueryCommandKind
    ): BatchQueryPositionResolution {
        requestFile := request.File
        if !BatchQueryValidationKernels.HasRequiredInput(commandKind, requestFile, request.Pos, request.Query) {
            return BatchQueryPositionResolution.Rejected(InvalidMissingRequiredInput(commandKind, projectRoot, request))
        }

        line := 0
        column := 0
        position := request.Pos ?? ""
        if !QueryCommandKernels.ParsePosition(position, out line, out column) {
            rejection := InvalidRequest(
                BatchQueryValidationKernels.GetCommandName(commandKind),
                BatchQueryKernels.GetInvalidPositionMessage(position),
                projectRoot,
                request
            )
            return BatchQueryPositionResolution.Rejected(rejection)
        }

        return BatchQueryPositionResolution.Accepted(requestFile ?? "", line, column)
    }

    static func InvalidRequest(command: string, message: string, projectRoot: string?, request: BatchQueryRequest): string {
        return OutputFormatter.ErrorToJson(command, message, projectRoot, "invalidRequest", NormalizeForErrorDetails(request))
    }

    static func InvalidMissingRequiredInput(commandKind: BatchQueryCommandKind, projectRoot: string?, request: BatchQueryRequest): string {
        return InvalidRequest(
            BatchQueryValidationKernels.GetCommandName(commandKind),
            BatchQueryValidationKernels.GetRequiredInputMessage(commandKind),
            projectRoot,
            request
        )
    }

    static func NormalizeForErrorDetails(request: BatchQueryRequest): object {
        return BatchQueryOutputKernels.NormalizeForErrorDetails(
            request.Command,
            request.Id,
            request.File,
            request.Pos,
            request.Name,
            request.Query,
            request.Kind,
            request.Severity,
            request.IncludeKeywords,
            request.Summary,
            request.Compact,
            request.Clusters
        )
    }

    static func NormalizeForOutput(request: BatchQueryRequest): BatchQueryOutputRequest {
        return BatchQueryOutputKernels.NormalizeForOutput(
            request.Command,
            request.File,
            request.Pos,
            request.Name,
            request.Query,
            request.Kind,
            request.Severity,
            request.IncludeKeywords,
            request.Summary,
            request.Compact,
            request.Clusters
        )
    }

    static func SymbolOf(definition: DefinitionResult?, typeResult: TypeResult?): InspectSymbolResult? {
        if definition != null {
            return new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column)
            )
        }

        if typeResult != null {
            return new InspectSymbolResult(typeResult.Name, typeResult.Kind, typeResult.Definition)
        }

        return null
    }

    static func BuildInspectResult(
        symbol: InspectSymbolResult?,
        typeResult: TypeResult?,
        definition: DefinitionResult?,
        references: List<ReferenceResult>,
        completions: CompletionResult
    ): InspectResult {
        definitionCount := references.Count(reference => reference.IsDefinition)
        return new InspectResult(
            symbol,
            typeResult,
            definition,
            new InspectReferencesResult(references.Count, definitionCount, references.ToArray()),
            completions
        )
    }
}

// What `ResolveFileAndPosition` answers: either a file and a position, or the JSON the caller must
// return instead.
class BatchQueryPositionResolution {
    IsValid: bool
    File: string
    Line: int
    Column: int
    Invalid: string

    constructor(isValid: bool, filePath: string, line: int, column: int, invalid: string) {
        IsValid = isValid
        File = filePath
        Line = line
        Column = column
        Invalid = invalid
    }

    static func Accepted(filePath: string, line: int, column: int): BatchQueryPositionResolution {
        return new BatchQueryPositionResolution(true, filePath, line, column, "")
    }

    static func Rejected(invalid: string): BatchQueryPositionResolution {
        return new BatchQueryPositionResolution(false, "", 0, 0, invalid)
    }
}

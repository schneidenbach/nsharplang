using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli;

internal sealed record BatchQueryRequest(
    string Command,
    string? Id = null,
    string? File = null,
    string? Pos = null,
    string? Name = null,
    string? Query = null,
    string? Kind = null,
    string? Severity = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    bool IncludeKeywords = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    bool Summary = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    bool Compact = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    bool Clusters = false);

internal sealed record BatchQueryItemResult(
    int Index,
    BatchQueryRequest Request,
    bool Ok,
    JsonElement Response);

internal static class BatchQueryRunner
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private static readonly JsonSerializerOptions RequestJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly Lazy<DocQuery> DocQuery = new(() =>
    {
        var query = new DocQuery();
        query.LoadSystemAssemblies();
        return query;
    });

    public static List<BatchQueryRequest> LoadRequests(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException(BatchQueryKernels.GetRequestsFileNotFoundMessage(path));
        }

        using var document = JsonDocument.Parse(File.ReadAllText(path));

        var rootElement = document.RootElement;
        JsonElement nestedRequests = default;
        var hasNestedRequests = rootElement.ValueKind == JsonValueKind.Object &&
                                rootElement.TryGetProperty("requests", out nestedRequests);
        var payloadShape = BatchQueryValidationKernels.GetPayloadShapeKind(
            rootElement.ValueKind == JsonValueKind.Array,
            rootElement.ValueKind == JsonValueKind.Object,
            hasNestedRequests,
            hasNestedRequests && nestedRequests.ValueKind == JsonValueKind.Array);

        JsonElement requestsElement;
        if (payloadShape == BatchQueryPayloadShapeKind.RootArray)
        {
            requestsElement = rootElement;
        }
        else if (payloadShape == BatchQueryPayloadShapeKind.NestedRequestsArray)
        {
            requestsElement = nestedRequests;
        }
        else
        {
            throw new InvalidDataException(BatchQueryKernels.GetPayloadShapeMessage());
        }

        var requests = new List<BatchQueryRequest>();
        foreach (var item in requestsElement.EnumerateArray())
        {
            if (!BatchQueryValidationKernels.IsRequestItemObject(item.ValueKind == JsonValueKind.Object))
            {
                throw new InvalidDataException(BatchQueryKernels.GetRequestObjectRequiredMessage());
            }

            var request = item.Deserialize<BatchQueryRequest>(RequestJsonOptions);
            if (request == null)
            {
                throw new InvalidDataException(BatchQueryKernels.GetRequestDeserializeFailedMessage());
            }

            requests.Add(request with
            {
                Command = BatchQueryKernels.NormalizeCommand(request.Command)
            });
        }

        var duplicateIds = BatchQueryKernels.FindDuplicateRequestIds(requests);

        if (duplicateIds.Length > 0)
        {
            throw new InvalidDataException(BatchQueryKernels.GetDuplicateRequestIdsMessage(string.Join(", ", duplicateIds)));
        }

        return requests;
    }

    public static BatchQueryExecutionResult Execute(
        IReadOnlyList<BatchQueryRequest> requests,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service,
        CompletionEngine completionEngine)
    {
        var items = new List<BatchQueryItemResult>(requests.Count);
        var okWords = new ulong[(requests.Count + 63) >> 6];

        for (int i = 0; i < requests.Count; i++)
        {
            var request = requests[i];
            var responseJson = ExecuteSingle(request, projectRoot, getSnapshot, service, completionEngine);
            using var responseDocument = JsonDocument.Parse(responseJson);
            var response = responseDocument.RootElement.Clone();
            var ok = response.TryGetProperty("ok", out var okElement) &&
                     okElement.ValueKind == JsonValueKind.True;
            if (ok)
                okWords[i >> 6] |= 1UL << (i & 63);

            items.Add(new BatchQueryItemResult(i, request, ok, response));
        }

        var successCount = BatchQueryKernels.CountResultSuccesses(okWords, items.Count);
        var failureCount = items.Count - successCount;
        var envelope = new
        {
            schemaVersion = 1,
            command = "batch",
            ok = failureCount == 0,
            projectRoot = NormalizePath(projectRoot),
            requestCount = items.Count,
            successCount,
            failureCount,
            results = items.Select(item => new
            {
                index = item.Index,
                id = item.Request.Id,
                request = NormalizeForOutput(item.Request),
                ok = item.Ok,
                response = item.Response
            }).ToArray()
        };

        return new BatchQueryExecutionResult(
            JsonSerializer.Serialize(envelope, JsonOptions),
            failureCount == 0,
            items.Count,
            successCount,
            failureCount);
    }

    private static string ExecuteSingle(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service,
        CompletionEngine completionEngine)
    {
        var normalizedCommand = BatchQueryKernels.NormalizeCommand(request.Command);
        var commandKind = BatchQueryKernels.GetCommandKind(normalizedCommand);
        try
        {
            return commandKind switch
            {
                BatchQueryCommandKind.Symbols => ExecuteSymbols(request, projectRoot, getSnapshot, service),
                BatchQueryCommandKind.Outline => ExecuteOutline(request, projectRoot, getSnapshot, service),
                BatchQueryCommandKind.Diagnostics => ExecuteDiagnostics(request, projectRoot, getSnapshot, service),
                BatchQueryCommandKind.Type => ExecuteType(request, projectRoot, getSnapshot, service),
                BatchQueryCommandKind.Inspect => ExecuteInspect(request, projectRoot, getSnapshot, service, completionEngine),
                BatchQueryCommandKind.Definition => ExecuteDefinition(request, projectRoot, getSnapshot, service),
                BatchQueryCommandKind.References => ExecuteReferences(request, projectRoot, getSnapshot, service),
                BatchQueryCommandKind.Completions => ExecuteCompletions(request, projectRoot, getSnapshot, completionEngine),
                BatchQueryCommandKind.Doc => ExecuteDoc(request),
                _ => OutputFormatter.ErrorToJson(
                    normalizedCommand,
                    BatchQueryKernels.GetUnsupportedCommandMessage(normalizedCommand),
                    projectRoot,
                    "unsupportedCommand")
            };
        }
        catch (Exception ex)
        {
            return OutputFormatter.ErrorToJson(
                normalizedCommand,
                ex.Message,
                projectRoot,
                "executionFailed");
        }
    }

    private static string ExecuteSymbols(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service)
    {
        SymbolKind? kindFilter = null;
        if (!string.IsNullOrWhiteSpace(request.Kind))
        {
            var parsedKind = QueryCommandKernels.ParseSymbolKind(request.Kind);
            if (parsedKind.HasValue)
                kindFilter = parsedKind.GetValueOrDefault();
        }

        var snapshot = getSnapshot();
        var results = service.GetSymbols(snapshot, request.File, kindFilter);
        return OutputFormatter.SymbolsToJson(results, snapshot.ProjectRoot);
    }

    private static string ExecuteOutline(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service)
    {
        if (!BatchQueryValidationKernels.HasRequiredInput(
                BatchQueryCommandKind.Outline,
                request.File,
                request.Pos,
                request.Query))
        {
            return InvalidMissingRequiredInput(BatchQueryCommandKind.Outline, projectRoot, request);
        }

        var snapshot = getSnapshot();
        var result = service.GetOutline(snapshot, request.File!);
        return OutputFormatter.OutlineToJson(result);
    }

    private static string ExecuteDiagnostics(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service)
    {
        var snapshot = getSnapshot();
        var results = service.GetDiagnostics(snapshot, request.File);
        if (!string.IsNullOrWhiteSpace(request.Severity))
        {
            results = OutputFormatter.FilterDiagnosticsBySeverity(results, request.Severity);
        }

        return request.Clusters
            ? OutputFormatter.DiagnosticClustersToJson(results, snapshot.ProjectRoot)
            : OutputFormatter.DiagnosticsToJson(results, snapshot.ProjectRoot);
    }

    private static string ExecuteType(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service)
    {
        if (!TryGetFileAndPosition(request, projectRoot, BatchQueryCommandKind.Type, out var file, out var line, out var column, out var invalid))
        {
            return invalid;
        }

        var resolvedFile = file!;
        var snapshot = getSnapshot();
        var result = service.GetTypeAtPosition(snapshot, resolvedFile, line, column);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson(
                "type",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                new
                {
                    file = NormalizePath(resolvedFile),
                    position = new { line, column }
                });
        }

        return OutputFormatter.TypeToJson(result, resolvedFile, line, column);
    }

    private static string ExecuteInspect(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service,
        CompletionEngine completionEngine)
    {
        if (!TryGetFileAndPosition(request, projectRoot, BatchQueryCommandKind.Inspect, out var file, out var line, out var column, out var invalid))
        {
            return invalid;
        }

        var resolvedFile = file!;
        var snapshot = getSnapshot();
        var type = service.GetTypeAtPosition(snapshot, resolvedFile, line, column);
        var definition = service.FindDefinition(snapshot, resolvedFile, line, column);
        var references = definition != null
            ? service.FindReferences(snapshot, resolvedFile, line, column)
            : new List<ReferenceResult>();
        var completions = completionEngine.GetCompletions(snapshot, resolvedFile, line, column, request.IncludeKeywords);

        if (type == null && definition == null && references.Count == 0)
        {
            return OutputFormatter.ErrorToJson(
                "inspect",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                new
                {
                    file = NormalizePath(resolvedFile),
                    position = new { line, column }
                });
        }

        InspectSymbolResult? symbol = null;
        if (definition != null)
        {
            symbol = new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column));
        }
        else if (type != null)
        {
            symbol = new InspectSymbolResult(type.Name, type.Kind, type.Definition);
        }

        var inspect = new InspectResult(
            symbol,
            type,
            definition,
            new InspectReferencesResult(
                references.Count,
                references.Count(reference => reference.IsDefinition),
                references.ToArray()),
            completions);

        return request.Summary || request.Compact
            ? OutputFormatter.InspectSummaryToJson(inspect, resolvedFile, line, column)
            : OutputFormatter.InspectToJson(inspect, resolvedFile, line, column);
    }

    private static string ExecuteDefinition(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service)
    {
        var snapshot = getSnapshot();

        if (!TryGetFileAndPosition(request, projectRoot, BatchQueryCommandKind.Definition, out var file, out var line, out var column, out var invalid))
        {
            return invalid;
        }

        var resolvedFile = file!;
        var result = service.FindDefinition(snapshot, resolvedFile, line, column);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson(
                "definition",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                new
                {
                    file = NormalizePath(resolvedFile),
                    position = new { line, column }
                });
        }

        return OutputFormatter.DefinitionToJson(result);
    }

    private static string ExecuteReferences(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CodeIntelligenceService service)
    {
        if (!TryGetFileAndPosition(request, projectRoot, BatchQueryCommandKind.References, out var file, out var line, out var column, out var invalid))
        {
            return invalid;
        }

        var resolvedFile = file!;
        var snapshot = getSnapshot();
        var definition = service.FindDefinition(snapshot, resolvedFile, line, column);
        if (definition == null)
        {
            return OutputFormatter.ErrorToJson(
                "references",
                QueryCommandKernels.GetNoSymbolAtPositionMessage(resolvedFile, line, column),
                snapshot.ProjectRoot,
                "noSymbol",
                new
                {
                    file = NormalizePath(resolvedFile),
                    position = new { line, column }
                });
        }

        var definedAt = new LocationResult(definition.File, definition.Line, definition.Column);
        var results = service.FindReferences(snapshot, resolvedFile, line, column);
        if (results.Count == 0)
        {
            return OutputFormatter.ErrorToJson(
                "references",
                QueryCommandKernels.GetSemanticReferencesUnavailableMessage(),
                snapshot.ProjectRoot,
                "semanticReferencesUnavailable",
                new
                {
                    file = NormalizePath(resolvedFile),
                    position = new { line, column },
                    symbol = new { name = definition.Name, kind = definition.Kind, definedAt }
                });
        }

        return OutputFormatter.ReferencesToJson(definition.Name, definition.Kind, definedAt, results);
    }

    private static string ExecuteCompletions(
        BatchQueryRequest request,
        string? projectRoot,
        Func<ProjectSnapshot> getSnapshot,
        CompletionEngine completionEngine)
    {
        if (!TryGetFileAndPosition(request, projectRoot, BatchQueryCommandKind.Completions, out var file, out var line, out var column, out var invalid))
        {
            return invalid;
        }

        var resolvedFile = file!;
        var snapshot = getSnapshot();
        var result = completionEngine.GetCompletions(snapshot, resolvedFile, line, column, request.IncludeKeywords);
        return OutputFormatter.CompletionsToJson(result, resolvedFile, line, column);
    }

    private static string ExecuteDoc(BatchQueryRequest request)
    {
        if (!BatchQueryValidationKernels.HasRequiredInput(
                BatchQueryCommandKind.Doc,
                request.File,
                request.Pos,
                request.Query))
        {
            return InvalidMissingRequiredInput(BatchQueryCommandKind.Doc, null, request);
        }

        var query = request.Query!;
        var result = DocQuery.Value.Lookup(query);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson("doc", QueryCommandKernels.GetNoDocumentationMessage(query));
        }

        return OutputFormatter.DocToJson(result, query);
    }

    private static bool TryGetFileAndPosition(
        BatchQueryRequest request,
        string? projectRoot,
        BatchQueryCommandKind commandKind,
        out string? file,
        out int line,
        out int column,
        out string invalid)
    {
        file = request.File;
        line = 0;
        column = 0;
        invalid = string.Empty;

        if (!BatchQueryValidationKernels.HasRequiredInput(commandKind, file, request.Pos, request.Query))
        {
            invalid = InvalidMissingRequiredInput(commandKind, projectRoot, request);
            return false;
        }

        if (!QueryCommandKernels.ParsePosition(request.Pos, out line, out column))
        {
            invalid = InvalidRequest(
                BatchQueryValidationKernels.GetCommandName(commandKind),
                BatchQueryKernels.GetInvalidPositionMessage(request.Pos),
                projectRoot,
                request);
            return false;
        }

        return true;
    }

    private static string InvalidRequest(string command, string message, string? projectRoot, BatchQueryRequest request)
        => OutputFormatter.ErrorToJson(command, message, projectRoot, "invalidRequest", Normalize(request));

    private static string InvalidMissingRequiredInput(BatchQueryCommandKind commandKind, string? projectRoot, BatchQueryRequest request)
        => InvalidRequest(
            BatchQueryValidationKernels.GetCommandName(commandKind),
            BatchQueryValidationKernels.GetRequiredInputMessage(commandKind),
            projectRoot,
            request);

    private static BatchQueryRequest Normalize(BatchQueryRequest request) => request with
    {
        Command = BatchQueryKernels.NormalizeCommand(request.Command),
        File = NormalizePath(request.File)
    };

    private static object NormalizeForOutput(BatchQueryRequest request)
    {
        var normalized = Normalize(request);
        return new
        {
            command = normalized.Command,
            file = normalized.File,
            pos = normalized.Pos,
            name = normalized.Name,
            query = normalized.Query,
            kind = normalized.Kind,
            severity = normalized.Severity,
            includeKeywords = normalized.IncludeKeywords ? true : (bool?)null,
            summary = normalized.Summary ? true : (bool?)null,
            compact = normalized.Compact ? true : (bool?)null,
            clusters = normalized.Clusters ? true : (bool?)null
        };
    }

    private static string? NormalizePath(string? path)
        => OutputFormatterNormalizationKernels.NormalizePath(path);
}

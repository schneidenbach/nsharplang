using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
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

internal sealed record BatchQueryExecutionResult(
    string Json,
    bool Ok,
    int RequestCount,
    int SuccessCount,
    int FailureCount);

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
            throw new FileNotFoundException($"Requests file not found: {path}");
        }

        using var document = JsonDocument.Parse(File.ReadAllText(path));

        JsonElement requestsElement;
        if (document.RootElement.ValueKind == JsonValueKind.Array)
        {
            requestsElement = document.RootElement;
        }
        else if (document.RootElement.ValueKind == JsonValueKind.Object &&
                 document.RootElement.TryGetProperty("requests", out var nestedRequests) &&
                 nestedRequests.ValueKind == JsonValueKind.Array)
        {
            requestsElement = nestedRequests;
        }
        else
        {
            throw new InvalidDataException("Batch requests must be a JSON array or an object with a 'requests' array.");
        }

        var requests = new List<BatchQueryRequest>();
        foreach (var item in requestsElement.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidDataException("Each batch request must be a JSON object.");
            }

            var request = item.Deserialize<BatchQueryRequest>(RequestJsonOptions);
            if (request == null)
            {
                throw new InvalidDataException("Failed to deserialize a batch request.");
            }

            requests.Add(request with
            {
                Command = NormalizeCommand(request.Command)
            });
        }

        var duplicateIds = requests
            .Where(request => !string.IsNullOrWhiteSpace(request.Id))
            .GroupBy(request => request.Id, StringComparer.Ordinal)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .OrderBy(id => id, StringComparer.Ordinal)
            .ToArray();

        if (duplicateIds.Length > 0)
        {
            throw new InvalidDataException($"Duplicate batch request ids are not allowed: {string.Join(", ", duplicateIds)}");
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

        for (int i = 0; i < requests.Count; i++)
        {
            var request = requests[i];
            var responseJson = ExecuteSingle(request, projectRoot, getSnapshot, service, completionEngine);
            using var responseDocument = JsonDocument.Parse(responseJson);
            var response = responseDocument.RootElement.Clone();
            var ok = response.TryGetProperty("ok", out var okElement) &&
                     okElement.ValueKind == JsonValueKind.True;

            items.Add(new BatchQueryItemResult(i, request, ok, response));
        }

        var successCount = items.Count(item => item.Ok);
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
        try
        {
            return request.Command switch
            {
                "symbols" => ExecuteSymbols(request, projectRoot, getSnapshot, service),
                "outline" => ExecuteOutline(request, projectRoot, getSnapshot, service),
                "diagnostics" => ExecuteDiagnostics(request, projectRoot, getSnapshot, service),
                "type" => ExecuteType(request, projectRoot, getSnapshot, service),
                "inspect" => ExecuteInspect(request, projectRoot, getSnapshot, service, completionEngine),
                "definition" => ExecuteDefinition(request, projectRoot, getSnapshot, service),
                "references" => ExecuteReferences(request, projectRoot, getSnapshot, service),
                "completions" => ExecuteCompletions(request, projectRoot, getSnapshot, completionEngine),
                "doc" => ExecuteDoc(request),
                _ => OutputFormatter.ErrorToJson(
                    request.Command,
                    $"Unsupported batch query command '{request.Command}'.",
                    projectRoot,
                    "unsupportedCommand")
            };
        }
        catch (Exception ex)
        {
            return OutputFormatter.ErrorToJson(
                request.Command,
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
        if (!string.IsNullOrWhiteSpace(request.Kind) &&
            Enum.TryParse<SymbolKind>(request.Kind, ignoreCase: true, out var parsedKind))
        {
            kindFilter = parsedKind;
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
        if (string.IsNullOrWhiteSpace(request.File))
        {
            return InvalidRequest("outline", "file is required for outline requests.", projectRoot, request);
        }

        var snapshot = getSnapshot();
        var result = service.GetOutline(snapshot, request.File);
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
            results = results
                .Where(diagnostic => diagnostic.Severity.Equals(request.Severity, StringComparison.OrdinalIgnoreCase))
                .ToList();
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
        if (!TryGetFileAndPosition(request, projectRoot, "type", out var file, out var line, out var column, out var invalid))
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
                $"No symbol found at {resolvedFile}:{line}:{column}",
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
        if (!TryGetFileAndPosition(request, projectRoot, "inspect", out var file, out var line, out var column, out var invalid))
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
                $"No symbol found at {resolvedFile}:{line}:{column}",
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
        if (!string.IsNullOrWhiteSpace(request.Name))
        {
            var results = service.FindDefinitionByName(snapshot, request.Name);
            return OutputFormatter.DefinitionSearchToJson(request.Name, results);
        }

        if (!TryGetFileAndPosition(request, projectRoot, "definition", out var file, out var line, out var column, out var invalid))
        {
            return invalid;
        }

        var resolvedFile = file!;
        var result = service.FindDefinition(snapshot, resolvedFile, line, column);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson(
                "definition",
                $"No symbol found at {resolvedFile}:{line}:{column}",
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
        if (!TryGetFileAndPosition(request, projectRoot, "references", out var file, out var line, out var column, out var invalid))
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
                $"No symbol found at {resolvedFile}:{line}:{column}",
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
                "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. No name-based or text-based fallback was used.",
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
        if (!TryGetFileAndPosition(request, projectRoot, "completions", out var file, out var line, out var column, out var invalid))
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
        if (string.IsNullOrWhiteSpace(request.Query))
        {
            return InvalidRequest("doc", "query is required for doc requests.", null, request);
        }

        var result = DocQuery.Value.Lookup(request.Query);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson("doc", $"No documentation found for '{request.Query}'.");
        }

        return OutputFormatter.DocToJson(result, request.Query);
    }

    private static bool TryGetFileAndPosition(
        BatchQueryRequest request,
        string? projectRoot,
        string command,
        out string? file,
        out int line,
        out int column,
        out string invalid)
    {
        file = request.File;
        line = 0;
        column = 0;
        invalid = string.Empty;

        if (string.IsNullOrWhiteSpace(file) || string.IsNullOrWhiteSpace(request.Pos))
        {
            invalid = InvalidRequest(command, "file and pos are required.", projectRoot, request);
            return false;
        }

        var parts = request.Pos.Split(':');
        if (parts.Length != 2 ||
            !int.TryParse(parts[0], out line) ||
            !int.TryParse(parts[1], out column))
        {
            invalid = InvalidRequest(
                command,
                $"Invalid position format '{request.Pos}'. Expected <line>:<col>.",
                projectRoot,
                request);
            return false;
        }

        return true;
    }

    private static string InvalidRequest(string command, string message, string? projectRoot, BatchQueryRequest request)
        => OutputFormatter.ErrorToJson(command, message, projectRoot, "invalidRequest", Normalize(request));

    private static BatchQueryRequest Normalize(BatchQueryRequest request) => request with
    {
        Command = NormalizeCommand(request.Command),
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

    private static string NormalizeCommand(string? command) => command?.Trim().ToLowerInvariant() switch
    {
        "def" => "definition",
        "refs" => "references",
        "" or null => "",
        var normalized => normalized
    };

    private static string? NormalizePath(string? path) => path?.Replace('\\', '/');
}

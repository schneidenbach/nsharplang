namespace NSharpLang.Cli

import System.Collections.Generic
import System.Text.Json

public class BatchQueryOutputRequest {
    commandValue: string
    fileValue: string?
    posValue: string?
    nameValue: string?
    queryValue: string?
    kindValue: string?
    severityValue: string?
    includeKeywordsValue: bool?
    summaryValue: bool?
    compactValue: bool?
    clustersValue: bool?

    Command: string => commandValue
    File: string? => fileValue
    Pos: string? => posValue
    Name: string? => nameValue
    Query: string? => queryValue
    Kind: string? => kindValue
    Severity: string? => severityValue
    IncludeKeywords: bool? => includeKeywordsValue
    Summary: bool? => summaryValue
    Compact: bool? => compactValue
    Clusters: bool? => clustersValue

    constructor(
        command: string,
        filePath: string?,
        pos: string?,
        name: string?,
        query: string?,
        kind: string?,
        severity: string?,
        includeKeywords: bool?,
        summary: bool?,
        compact: bool?,
        clusters: bool?) {
        commandValue = command
        fileValue = filePath
        posValue = pos
        nameValue = name
        queryValue = query
        kindValue = kind
        severityValue = severity
        includeKeywordsValue = includeKeywords
        summaryValue = summary
        compactValue = compact
        clustersValue = clusters
    }
}

public class BatchQueryNormalizedRequest {
    commandValue: string
    idValue: string?
    fileValue: string?
    posValue: string?
    nameValue: string?
    queryValue: string?
    kindValue: string?
    severityValue: string?
    includeKeywordsValue: bool?
    summaryValue: bool?
    compactValue: bool?
    clustersValue: bool?

    Command: string => commandValue
    Id: string? => idValue
    File: string? => fileValue
    Pos: string? => posValue
    Name: string? => nameValue
    Query: string? => queryValue
    Kind: string? => kindValue
    Severity: string? => severityValue
    IncludeKeywords: bool? => includeKeywordsValue
    Summary: bool? => summaryValue
    Compact: bool? => compactValue
    Clusters: bool? => clustersValue

    constructor(
        command: string,
        id: string?,
        filePath: string?,
        pos: string?,
        name: string?,
        query: string?,
        kind: string?,
        severity: string?,
        includeKeywords: bool?,
        summary: bool?,
        compact: bool?,
        clusters: bool?) {
        commandValue = command
        idValue = id
        fileValue = filePath
        posValue = pos
        nameValue = name
        queryValue = query
        kindValue = kind
        severityValue = severity
        includeKeywordsValue = includeKeywords
        summaryValue = summary
        compactValue = compact
        clustersValue = clusters
    }
}

public class BatchQueryOutputItem {
    indexValue: int
    idValue: string?
    requestValue: BatchQueryOutputRequest
    okValue: bool
    responseValue: JsonElement

    Index: int => indexValue
    Id: string? => idValue
    Request: BatchQueryOutputRequest => requestValue
    Ok: bool => okValue
    Response: JsonElement => responseValue

    constructor(
        index: int,
        id: string?,
        request: BatchQueryOutputRequest,
        ok: bool,
        response: JsonElement) {
        indexValue = index
        idValue = id
        requestValue = request
        okValue = ok
        responseValue = response
    }
}

public class BatchQueryOutputKernels {
    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    public static func BuildExecutionResultJson(
        projectRoot: string?,
        items: IReadOnlyList<BatchQueryOutputItem>,
        successCount: int,
        failureCount: int): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "batch"
        envelope["ok"] = failureCount == 0

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["requestCount"] = items.Count
        envelope["successCount"] = successCount
        envelope["failureCount"] = failureCount
        envelope["results"] = BuildResultItems(items)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    public static func NormalizeForOutput(
        command: string?,
        filePath: string?,
        pos: string?,
        name: string?,
        query: string?,
        kind: string?,
        severity: string?,
        includeKeywords: bool,
        summary: bool,
        compact: bool,
        clusters: bool): BatchQueryOutputRequest {
        return new BatchQueryOutputRequest(
            BatchQueryKernels.NormalizeCommand(command),
            OutputFormatterNormalizationKernels.NormalizePath(filePath),
            pos,
            name,
            query,
            kind,
            severity,
            OptionalBool(includeKeywords),
            OptionalBool(summary),
            OptionalBool(compact),
            OptionalBool(clusters))
    }

    public static func NormalizeForErrorDetails(
        command: string?,
        id: string?,
        filePath: string?,
        pos: string?,
        name: string?,
        query: string?,
        kind: string?,
        severity: string?,
        includeKeywords: bool,
        summary: bool,
        compact: bool,
        clusters: bool): BatchQueryNormalizedRequest {
        return new BatchQueryNormalizedRequest(
            BatchQueryKernels.NormalizeCommand(command),
            id,
            OutputFormatterNormalizationKernels.NormalizePath(filePath),
            pos,
            name,
            query,
            kind,
            severity,
            OptionalBool(includeKeywords),
            OptionalBool(summary),
            OptionalBool(compact),
            OptionalBool(clusters))
    }

    static func OptionalBool(value: bool): bool? {
        if value {
            return true
        }

        return null
    }

    static func BuildResultItems(items: IReadOnlyList<BatchQueryOutputItem>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        i := 0
        while i < items.Count {
            payload.Add(BuildResultItem(items[i]))
            i = i + 1
        }

        return payload
    }

    static func BuildResultItem(item: BatchQueryOutputItem): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["index"] = item.Index
        if item.Id != null {
            payload["id"] = item.Id ?? ""
        }

        payload["request"] = BuildOutputRequest(item.Request)
        payload["ok"] = item.Ok
        payload["response"] = item.Response
        return payload
    }

    static func BuildOutputRequest(request: BatchQueryOutputRequest): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["command"] = request.Command

        if request.File != null {
            payload["file"] = request.File ?? ""
        }

        if request.Pos != null {
            payload["pos"] = request.Pos ?? ""
        }

        if request.Name != null {
            payload["name"] = request.Name ?? ""
        }

        if request.Query != null {
            payload["query"] = request.Query ?? ""
        }

        if request.Kind != null {
            payload["kind"] = request.Kind ?? ""
        }

        if request.Severity != null {
            payload["severity"] = request.Severity ?? ""
        }

        if request.IncludeKeywords != null {
            payload["includeKeywords"] = true
        }

        if request.Summary != null {
            payload["summary"] = true
        }

        if request.Compact != null {
            payload["compact"] = true
        }

        if request.Clusters != null {
            payload["clusters"] = true
        }

        return payload
    }
}

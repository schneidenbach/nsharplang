namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Numerics

enum BatchQueryCommandKind {
    Unknown = 0,
    Symbols = 1,
    Outline = 2,
    Diagnostics = 3,
    Type = 4,
    Inspect = 5,
    Definition = 6,
    References = 7,
    Completions = 8,
    Doc = 9
}

class BatchQueryExecutionResult {
    Json: string
    Ok: bool
    RequestCount: int
    SuccessCount: int
    FailureCount: int

    constructor(json: string, ok: bool, requestCount: int, successCount: int, failureCount: int) {
        Json = json
        Ok = ok
        RequestCount = requestCount
        SuccessCount = successCount
        FailureCount = failureCount
    }
}

class BatchQueryExecutionSummary {
    Ok: bool
    SuccessCount: int
    FailureCount: int

    constructor(ok: bool, successCount: int, failureCount: int) {
        Ok = ok
        SuccessCount = successCount
        FailureCount = failureCount
    }
}

class BatchQueryKernels {
    static func NormalizeCommand(command: string?): string {
        if command == null {
            return ""
        }

        normalized := command.Trim().ToLowerInvariant()
        if normalized == "def" {
            return "definition"
        }

        if normalized == "refs" {
            return "references"
        }

        return normalized
    }

    static func GetCommandKind(command: string?): BatchQueryCommandKind {
        normalized := NormalizeCommand(command)
        if normalized == "symbols" {
            return BatchQueryCommandKind.Symbols
        }

        if normalized == "outline" {
            return BatchQueryCommandKind.Outline
        }

        if normalized == "diagnostics" {
            return BatchQueryCommandKind.Diagnostics
        }

        if normalized == "type" {
            return BatchQueryCommandKind.Type
        }

        if normalized == "inspect" {
            return BatchQueryCommandKind.Inspect
        }

        if normalized == "definition" {
            return BatchQueryCommandKind.Definition
        }

        if normalized == "references" {
            return BatchQueryCommandKind.References
        }

        if normalized == "completions" {
            return BatchQueryCommandKind.Completions
        }

        if normalized == "doc" {
            return BatchQueryCommandKind.Doc
        }

        return BatchQueryCommandKind.Unknown
    }

    static func FindDuplicateRequestIds(requests: IReadOnlyList<object>): string[] {
        countsById := new Dictionary<string, int>(StringComparer.Ordinal)
        uniqueIds := new List<string>()

        i := 0
        while i < requests.Count {
            id := GetRequestId(requests[i])
            if !string.IsNullOrWhiteSpace(id ?? "") {
                if countsById.ContainsKey(id) {
                    countsById[id] = countsById[id] + 1
                } else {
                    countsById[id] = 1
                    uniqueIds.Add(id)
                }
            }

            i = i + 1
        }

        orderedIds := uniqueIds.ToArray()
        Array.Sort(orderedIds, 0, orderedIds.Length, StringComparer.Ordinal)

        duplicates := new List<string>()
        i = 0
        while i < orderedIds.Length {
            id := orderedIds[i]
            if countsById[id] > 1 {
                duplicates.Add(id)
            }

            i = i + 1
        }

        return duplicates.ToArray()
    }

    static func CountResultSuccesses(okWords: ulong[], itemCount: int): int {
        if itemCount < 0 {
            throw new InvalidOperationException("N# batch success-count kernel received a negative item count.")
        }

        if itemCount > okWords.Length * 64 {
            throw new InvalidOperationException("N# batch success-count kernel received too few packed words.")
        }

        if itemCount == 0 {
            return 0
        }

        fullWordCount := itemCount >> 6
        successCount := 0
        i := 0
        while i < fullWordCount {
            successCount = successCount + BitOperations.PopCount(okWords[i])
            i = i + 1
        }

        lastBits := itemCount & 63
        if lastBits != 0 {
            shift := 64 - lastBits
            lastWord := (okWords[fullWordCount] << shift) >> shift
            successCount = successCount + BitOperations.PopCount(lastWord)
        }

        if successCount < 0 || successCount > itemCount {
            throw new InvalidOperationException("N# batch success-count kernel rejected the results.")
        }

        return successCount
    }

    static func SummarizeExecutionResults(okWords: ulong[], itemCount: int): BatchQueryExecutionSummary {
        successCount := CountResultSuccesses(okWords, itemCount)
        failureCount := itemCount - successCount

        if failureCount < 0 || failureCount > itemCount {
            throw new InvalidOperationException("N# batch execution-summary kernel rejected the results.")
        }

        return new BatchQueryExecutionSummary(failureCount == 0, successCount, failureCount)
    }

    static func GetRequestsFileNotFoundMessage(path: string): string {
        return "Requests file not found: " + path
    }

    static func GetPayloadShapeMessage(): string {
        return "Batch requests must be a JSON array or an object with a 'requests' array."
    }

    static func GetRequestObjectRequiredMessage(): string {
        return "Each batch request must be a JSON object."
    }

    static func GetRequestDeserializeFailedMessage(): string {
        return "Failed to deserialize a batch request."
    }

    static func GetDuplicateRequestIdsMessage(duplicateIdsText: string): string {
        return "Duplicate batch request ids are not allowed: " + duplicateIdsText
    }

    static func GetUnsupportedCommandMessage(command: string): string {
        return "Unsupported batch query command '" + command + "'."
    }

    static func GetOutlineFileRequiredMessage(): string {
        return "file is required for outline requests."
    }

    static func GetDocQueryRequiredMessage(): string {
        return "query is required for doc requests."
    }

    static func GetFileAndPosRequiredMessage(): string {
        return "file and pos are required."
    }

    static func GetInvalidPositionMessage(position: string): string {
        return "Invalid position format '" + position + "'. Expected <line>:<col>."
    }

    static func GetRequestId(request: object): string? {
        property := request.GetType().GetProperty("Id")
        if property != null {
            return property.GetValue(request) as string
        }

        field := request.GetType().GetField("Id")
        if field != null {
            return field.GetValue(request) as string
        }

        return null
    }
}

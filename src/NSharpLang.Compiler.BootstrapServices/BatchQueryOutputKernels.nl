namespace NSharpLang.Cli

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

public class BatchQueryOutputKernels {
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
}

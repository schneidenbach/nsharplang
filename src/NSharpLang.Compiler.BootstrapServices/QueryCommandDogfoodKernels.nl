namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler.CodeIntelligence
import System
import System.IO

public enum QuerySubcommandKind {
    Unknown = 0,
    Batch = 1,
    Symbols = 2,
    Outline = 3,
    Ast = 4,
    Diagnostics = 5,
    Type = 6,
    Inspect = 7,
    Definition = 8,
    References = 9,
    Completions = 10,
    Doc = 11,
    Hover = 12,
    CallGraph = 13,
    Performance = 14,
    Trusted = 15,
    Implementors = 16,
    Help = 17
}

public class QueryDaemonParameterPlan {
    File: string?
    Pos: string?
    Name: string?
    Kind: string?
    Severity: string?
    IncludeKeywords: bool
    Summary: bool
    Clusters: bool

    constructor(
        filePath: string?,
        pos: string?,
        name: string?,
        kind: string?,
        severity: string?,
        includeKeywords: bool,
        summary: bool,
        clusters: bool) {
        File = filePath
        Pos = pos
        Name = name
        Kind = kind
        Severity = severity
        IncludeKeywords = includeKeywords
        Summary = summary
        Clusters = clusters
    }
}

public class QueryCommandDogfoodKernels {
    public static func GetDaemonParameterPlan(args: string[], options: QueryOptions): QueryDaemonParameterPlan {
        parameterSummary := QueryCommandKernels.GetDaemonParameterSummary(args)

        return new QueryDaemonParameterPlan(
            SelectDaemonString(parameterSummary.File, options.File),
            SelectDaemonString(parameterSummary.Pos, options.Pos),
            SelectDaemonString(parameterSummary.Name, null),
            SelectDaemonString(parameterSummary.Kind, null),
            SelectDaemonString(parameterSummary.Severity, null),
            parameterSummary.IncludeKeywords,
            options.InspectCompact,
            parameterSummary.Clusters)
    }

    public static func GetCallGraphLimit(limitText: string?): int {
        defaultLimit := 100
        if limitText != null {
            parsedLimit := 0
            if QueryCommandKernels.ParsePositiveInt(limitText, out parsedLimit) {
                return parsedLimit
            }
        }

        return defaultLimit
    }

    public static func GetSubcommandKind(subcommand: string): QuerySubcommandKind {
        if subcommand == "batch" {
            return QuerySubcommandKind.Batch
        }

        if subcommand == "symbols" {
            return QuerySubcommandKind.Symbols
        }

        if subcommand == "outline" {
            return QuerySubcommandKind.Outline
        }

        if subcommand == "ast" {
            return QuerySubcommandKind.Ast
        }

        if subcommand == "diagnostics" {
            return QuerySubcommandKind.Diagnostics
        }

        if subcommand == "type" {
            return QuerySubcommandKind.Type
        }

        if subcommand == "inspect" {
            return QuerySubcommandKind.Inspect
        }

        if subcommand == "definition" || subcommand == "def" {
            return QuerySubcommandKind.Definition
        }

        if subcommand == "references" || subcommand == "refs" {
            return QuerySubcommandKind.References
        }

        if subcommand == "completions" {
            return QuerySubcommandKind.Completions
        }

        if subcommand == "doc" {
            return QuerySubcommandKind.Doc
        }

        if subcommand == "hover" {
            return QuerySubcommandKind.Hover
        }

        if subcommand == "call-graph" {
            return QuerySubcommandKind.CallGraph
        }

        if subcommand == "perf" {
            return QuerySubcommandKind.Performance
        }

        if subcommand == "trusted" {
            return QuerySubcommandKind.Trusted
        }

        if subcommand == "implementors" {
            return QuerySubcommandKind.Implementors
        }

        if subcommand == "help" || subcommand == "--help" || subcommand == "-h" {
            return QuerySubcommandKind.Help
        }

        return QuerySubcommandKind.Unknown
    }

    public static func MatchesFile(candidate: string?, query: string): bool {
        if string.IsNullOrWhiteSpace(candidate ?? "") {
            return false
        }

        normalizedCandidate := NormalizePath(candidate ?? "")
        normalizedQuery := NormalizePath(query)
        return string.Equals(normalizedCandidate, normalizedQuery, StringComparison.OrdinalIgnoreCase)
            || normalizedCandidate.EndsWith("/" + normalizedQuery, StringComparison.OrdinalIgnoreCase)
            || normalizedCandidate.EndsWith(normalizedQuery, StringComparison.OrdinalIgnoreCase)
    }

    public static func GetRelativePath(basePath: string, filePath: string): string {
        return Path.GetRelativePath(basePath, filePath)
    }

    public static func WithOutlineFile(result: OutlineResult, outputFile: string): OutlineResult {
        return new OutlineResult(outputFile, result.Imports, result.Outline)
    }

    static func NormalizePath(path: string): string {
        return OutputFormatterNormalizationKernels.NormalizePath(path) ?? path
    }

    static func SelectDaemonString(primary: string?, fallback: string?): string? {
        if !string.IsNullOrWhiteSpace(primary ?? "") {
            return primary
        }

        if !string.IsNullOrWhiteSpace(fallback ?? "") {
            return fallback
        }

        return null
    }
}

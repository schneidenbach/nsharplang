namespace NSharpLang.Cli.Commands

import NSharpLang.Cli.Daemon
import NSharpLang.Compiler.CodeIntelligence
import System
import System.IO
import System.Text.Json

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
    public static func ShouldUseDaemon(useText: bool, noDaemon: bool, methodKind: DaemonMethodKind): bool {
        return QueryCommandKernels.ShouldUseDaemon(useText, noDaemon)
            && DaemonProtocolKernels.IsQueryMethod(methodKind)
    }

    public static func GetDaemonJsonExitCode(hasOk: bool, ok: bool): int {
        if !hasOk {
            return 0
        }

        if ok {
            return 0
        }

        return 1
    }

    public static func GetDaemonJsonExitCodeFromJson(json: string): int {
        try {
            document := JsonDocument.Parse(json)
            okElement := new JsonElement()
            if document.RootElement.TryGetProperty("ok", out okElement) {
                ok := okElement.ValueKind == JsonValueKind.True
                document.Dispose()
                return GetDaemonJsonExitCode(true, ok)
            }

            document.Dispose()
        } catch {
        }

        return GetDaemonJsonExitCode(false, false)
    }

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

    public static func MatchesCompilationUnitFile(candidate: string, query: string): bool {
        normalizedCandidate := NormalizePath(candidate)
        normalizedQuery := NormalizePath(query)
        return string.Equals(normalizedCandidate, normalizedQuery, StringComparison.OrdinalIgnoreCase)
            || normalizedCandidate.EndsWith("/" + normalizedQuery, StringComparison.OrdinalIgnoreCase)
            || string.Equals(Path.GetFileName(normalizedCandidate), Path.GetFileName(normalizedQuery), StringComparison.OrdinalIgnoreCase)
    }

    public static func GetRelativePath(basePath: string, filePath: string): string {
        return Path.GetRelativePath(basePath, filePath)
    }

    public static func GetProjectRoot(projectDir: string?, currentDirectory: string): string {
        return Path.GetFullPath(projectDir ?? currentDirectory)
    }

    public static func ResolveProjectFilePath(projectRoot: string, filePath: string): string {
        if Path.IsPathRooted(filePath) {
            return filePath
        }

        return Path.Combine(projectRoot, filePath)
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

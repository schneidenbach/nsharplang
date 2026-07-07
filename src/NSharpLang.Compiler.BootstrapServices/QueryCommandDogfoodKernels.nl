namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler.CodeIntelligence

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

public class QueryCommandDogfoodKernels {
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

    public static func WithOutlineFile(result: OutlineResult, outputFile: string): OutlineResult {
        return new OutlineResult(outputFile, result.Imports, result.Outline)
    }
}

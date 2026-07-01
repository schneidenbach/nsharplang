namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.CodeIntelligence

public class DocOptionSummary {
    ProjectOption: string?
    OutputOption: string?
    Json: bool
    Open: bool
    ShowHelp: bool

    constructor(projectOption: string?, outputOption: string?, json: bool, open: bool, showHelp: bool) {
        ProjectOption = projectOption
        OutputOption = outputOption
        Json = json
        Open = open
        ShowHelp = showHelp
    }
}

public class DocCommandKernels {
    public static func GetOptionSummary(args: string[]): DocOptionSummary {
        projectOption: string? = null
        outputOption: string? = null
        json := false
        open := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            valueIndex := i + 1
            hasValue := valueIndex < args.Length

            if arg == "--project" {
                if projectOption == null && hasValue {
                    projectOption = args[valueIndex]
                }
            } else if arg == "--output" {
                if outputOption == null && hasValue {
                    outputOption = args[valueIndex]
                }
            } else if arg == "--json" {
                json = true
            } else if arg == "--open" {
                open = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new DocOptionSummary(projectOption, outputOption, json, open, showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func OrderSymbolsForGeneration(symbols: IReadOnlyList<SymbolResult>): List<SymbolResult> {
        return OrderEntriesForGeneration(symbols, false)
    }

    public static func OrderMembersForGeneration(members: IReadOnlyList<SymbolResult>): List<SymbolResult> {
        return OrderEntriesForGeneration(members, true)
    }

    public static func CreateSlugs(rawSlugs: string[]): string[] {
        result := new string[](rawSlugs.Length)
        i := 0
        while i < rawSlugs.Length {
            result[i] = CreateSlug(rawSlugs[i])
            i = i + 1
        }

        return result
    }

    public static func GetHelpText(): string {
        return "N# API Documentation\n"
            + "\n"
            + "Usage: nlc doc [options]\n"
            + "\n"
            + "Generate HTML API documentation for the current project. Similar to `cargo doc`.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project root directory (default: current directory)\n"
            + "  --output <dir>    Output directory (default: ./nsharp/docs)\n"
            + "  --json            Emit a structured JSON result envelope\n"
            + "  --open            Open the generated index in the default browser\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc doc\n"
            + "  nlc doc --open\n"
            + "  nlc doc --json\n"
            + "  nlc doc --project examples/16-task-cli --output /tmp/nsharp-docs\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Documentation generated successfully\n"
            + "  1  Documentation generation failed"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    public static func GetGeneratedSummaryMessage(pageCount: int): string {
        return "Generated API docs for " + pageCount.ToString() + " symbols."
    }

    public static func GetOutputPathMessage(outputDir: string): string {
        return "Output: " + outputDir
    }

    public static func GetIndexPathMessage(indexPath: string): string {
        return "Index: " + indexPath
    }

    public static func GetOpenedMessage(): string {
        return "Opened generated documentation in the default browser."
    }

    public static func GetGenerationFailedMessage(exceptionMessage: string): string {
        return "Doc generation failed: " + exceptionMessage
    }

    public static func GetOpenFailedMessage(indexPath: string): string {
        return "Generated docs, but failed to open " + indexPath + "."
    }

    public static func GetOpenFailedWithDetailMessage(indexPath: string, exceptionMessage: string): string {
        return "Generated docs, but failed to open " + indexPath + ": " + exceptionMessage
    }

    public static func GetLocationText(relativePath: string, line: int, column: int): string {
        return relativePath + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetParameterText(name: string, typeName: string, hasDefault: bool, defaultValue: string): string {
        if hasDefault {
            return name + ": " + typeName + " = " + defaultValue
        }

        return name + ": " + typeName
    }

    public static func GetSignatureText(
        kind: SymbolKind,
        name: string,
        hasParameterList: bool,
        parametersText: string,
        typeName: string): string {
        prefix := SignaturePrefix(kind)
        result := prefix + name
        if hasParameterList {
            result = result + "(" + parametersText + ")"
        }

        if typeName != "" {
            result = result + ": " + typeName
        }

        return result
    }

    static func OrderEntriesForGeneration(symbols: IReadOnlyList<SymbolResult>, includeAllKinds: bool): List<SymbolResult> {
        ordered := new List<SymbolResult>()
        index := 0
        while index < symbols.Count {
            symbol := symbols[index]
            if includeAllKinds || IsDocumentedSymbolKind(symbol.Kind) {
                InsertOrdered(ordered, symbol)
            }

            index = index + 1
        }

        return ordered
    }

    static func InsertOrdered(ordered: List<SymbolResult>, symbol: SymbolResult) {
        insertIndex := ordered.Count
        index := 0
        while index < ordered.Count {
            if CompareSymbols(symbol, ordered[index]) < 0 {
                insertIndex = index
                index = ordered.Count
            } else {
                index = index + 1
            }
        }

        ordered.Insert(insertIndex, symbol)
    }

    static func CompareSymbols(left: SymbolResult, right: SymbolResult): int {
        kindCompare := SymbolKindOrderRank(left.Kind) - SymbolKindOrderRank(right.Kind)
        if kindCompare != 0 {
            return kindCompare
        }

        return String.Compare(left.Name, right.Name, StringComparison.Ordinal)
    }

    static func IsDocumentedSymbolKind(kind: SymbolKind): bool {
        return kind != SymbolKind.Variable && kind != SymbolKind.Parameter
    }

    static func SymbolKindOrderRank(kind: SymbolKind): int {
        if kind == SymbolKind.Class {
            return 1
        }

        if kind == SymbolKind.Constructor {
            return 2
        }

        if kind == SymbolKind.Enum {
            return 3
        }

        if kind == SymbolKind.EnumMember {
            return 4
        }

        if kind == SymbolKind.Field {
            return 5
        }

        if kind == SymbolKind.Function {
            return 6
        }

        if kind == SymbolKind.Interface {
            return 7
        }

        if kind == SymbolKind.Method {
            return 8
        }

        if kind == SymbolKind.Parameter {
            return 9
        }

        if kind == SymbolKind.Property {
            return 10
        }

        if kind == SymbolKind.Record {
            return 11
        }

        if kind == SymbolKind.Struct {
            return 12
        }

        if kind == SymbolKind.Test {
            return 13
        }

        if kind == SymbolKind.TypeAlias {
            return 14
        }

        if kind == SymbolKind.Union {
            return 15
        }

        if kind == SymbolKind.Variable {
            return 16
        }

        return 0
    }

    static func CreateSlug(raw: string): string {
        builder := new StringBuilder(raw.Length)
        i := 0
        while i < raw.Length {
            ch := raw[i]
            if Char.IsLetterOrDigit(ch) {
                builder.Append(Char.ToLowerInvariant(ch))
            }

            i = i + 1
        }

        return builder.ToString()
    }

    static func SignaturePrefix(kind: SymbolKind): string {
        if kind == SymbolKind.Function || kind == SymbolKind.Method {
            return "func "
        }

        if kind == SymbolKind.Constructor {
            return "ctor "
        }

        if kind == SymbolKind.Class {
            return "class "
        }

        if kind == SymbolKind.Struct {
            return "struct "
        }

        if kind == SymbolKind.Record {
            return "record "
        }

        if kind == SymbolKind.Interface {
            return "interface "
        }

        if kind == SymbolKind.Enum {
            return "enum "
        }

        if kind == SymbolKind.Union {
            return "union "
        }

        if kind == SymbolKind.Property {
            return "prop "
        }

        if kind == SymbolKind.Field {
            return "field "
        }

        if kind == SymbolKind.TypeAlias {
            return "type "
        }

        if kind == SymbolKind.Test {
            return "test "
        }

        return ""
    }
}

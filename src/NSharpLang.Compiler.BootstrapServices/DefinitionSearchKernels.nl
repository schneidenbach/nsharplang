namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class DefinitionSearchKernels {
    public static func FindDefinitions(
        symbols: IReadOnlyList<SymbolResult>,
        query: string,
        limit: int): List<DefinitionResult> {
        results := new List<DefinitionResult>()
        if limit <= 0 {
            return results
        }

        index := 0
        while index < symbols.Count && results.Count < limit {
            AddMatchingDefinitions(symbols[index], query, results, limit)
            index = index + 1
        }

        return results
    }

    public static func GetDefinitionSearchHeader(query: string, count: int): string {
        if count == 1 {
            return "Definition of '" + query + "':"
        }

        return "Definitions of '" + query + "':"
    }

    public static func GetDefinitionSearchNote(count: int): string {
        if count == 0 {
            return "No public definition matched the requested name."
        }

        return "Name-based definition search matches public symbols by exact name."
    }

    static func AddMatchingDefinitions(
        symbol: SymbolResult,
        query: string,
        results: List<DefinitionResult>,
        limit: int) {
        if results.Count >= limit {
            return
        }

        if symbol.Name == query {
            results.Add(new DefinitionResult(
                symbol.Name,
                SymbolKindText(symbol.Kind),
                symbol.File,
                symbol.Line,
                symbol.Column,
                symbol.Name.Length))
        }

        members := symbol.Members
        if members == null {
            return
        }

        memberArray := members ?? new SymbolResult[](0)
        index := 0
        while index < memberArray.Length && results.Count < limit {
            AddMatchingDefinitions(memberArray[index], query, results, limit)
            index = index + 1
        }
    }

    static func SymbolKindText(kind: SymbolKind): string {
        if kind == SymbolKind.Function { return "function" }
        if kind == SymbolKind.Class { return "class" }
        if kind == SymbolKind.Struct { return "struct" }
        if kind == SymbolKind.Record { return "record" }
        if kind == SymbolKind.Interface { return "interface" }
        if kind == SymbolKind.Enum { return "enum" }
        if kind == SymbolKind.Union { return "union" }
        if kind == SymbolKind.Property { return "property" }
        if kind == SymbolKind.Field { return "field" }
        if kind == SymbolKind.Method { return "method" }
        if kind == SymbolKind.Variable { return "variable" }
        if kind == SymbolKind.Parameter { return "parameter" }
        if kind == SymbolKind.Constructor { return "constructor" }
        if kind == SymbolKind.EnumMember { return "enumMember" }
        if kind == SymbolKind.TypeAlias { return "typeAlias" }
        if kind == SymbolKind.Test { return "test" }
        return "unknown"
    }
}

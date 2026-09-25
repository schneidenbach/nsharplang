namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class DefinitionSearchKernels {
    static func FindDefinitions(symbols: IReadOnlyList<SymbolResult>, query: string, limit: int): List<DefinitionResult> {
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

    static func GetDefinitionSearchHeader(query: string, count: int): string {
        if count == 1 {
            return "Definition of '" + query + "':"
        }

        return "Definitions of '" + query + "':"
    }

    static func GetDefinitionSearchNote(count: int): string {
        if count == 0 {
            return "No public definition matched the requested name."
        }

        return "Name-based definition search matches public symbols by exact name."
    }

    static func AddMatchingDefinitions(symbol: SymbolResult, query: string, results: List<DefinitionResult>, limit: int) {
        if results.Count >= limit {
            return
        }

        if symbol.Name == query {
            results.Add(new DefinitionResult(symbol.Name, SymbolDisplayFacts.SymbolKindJsonText(symbol.Kind), symbol.File, symbol.Line, symbol.Column, symbol.Name.Length))
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
}

namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

public class CodeIntelligenceSymbolKernels {
    public static func FilterSymbolsByKind(symbols: List<SymbolResult>, targetKind: SymbolKind): List<SymbolResult> {
        results := new List<SymbolResult>()

        i := 0
        while i < symbols.Count {
            symbol := symbols[i]
            if symbol.Kind == targetKind {
                results.Add(symbol)
            }

            i = i + 1
        }

        return results
    }
}

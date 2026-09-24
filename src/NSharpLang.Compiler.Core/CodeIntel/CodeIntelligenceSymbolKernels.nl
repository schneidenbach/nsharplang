namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class CodeIntelligenceSymbolKernels {
    static func FilterSymbolsByKind(symbols: List<SymbolResult>, targetKind: SymbolKind): List<SymbolResult> {
        results := new List<SymbolResult>()

        for symbol in symbols {
            if symbol.Kind == targetKind {
                results.Add(symbol)
            }
        }

        return results
    }
}

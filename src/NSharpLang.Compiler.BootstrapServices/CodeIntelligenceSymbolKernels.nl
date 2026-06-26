namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class CodeIntelligenceSymbolKernels {
    public static func FilterSymbolsByKind<T>(symbols: IReadOnlyList<T>, targetKind: object): List<T> {
        results := new List<T>()
        targetKindId := Convert.ToInt32(targetKind)

        i := 0
        while i < symbols.Count {
            symbol := symbols[i]
            if CodeIntelligenceSymbolKindId(symbol) == targetKindId {
                results.Add(symbol)
            }

            i = i + 1
        }

        return results
    }

    static func CodeIntelligenceSymbolKindId(symbol: object): int {
        property := symbol.GetType().GetProperty("Kind")
        if property != null {
            return CodeIntelligenceSymbolKindValue(property.GetValue(symbol))
        }

        field := symbol.GetType().GetField("Kind")
        if field == null {
            return -1
        }

        return CodeIntelligenceSymbolKindValue(field.GetValue(symbol))
    }

    static func CodeIntelligenceSymbolKindValue(rawKind: object): int {
        if rawKind == null {
            return -1
        }

        return Convert.ToInt32(rawKind)
    }
}

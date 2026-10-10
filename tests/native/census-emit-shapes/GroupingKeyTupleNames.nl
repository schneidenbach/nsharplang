namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic
import System.Linq


// TUPLE ELEMENT NAMES SURVIVE AN `IGrouping.Key` HOP WHEN SOMETHING WRITTEN NAMED THEM.
//
// A loop variable's element names are the ones the collection's own written type gave that position,
// and `rows.GroupBy(r => r)` over a `List<(Code: string, Amount: int)>` yields an `IGrouping<…>` —
// a type no written spelling in the chain names. So the element search answered nothing, the loop
// variable remembered nothing, and `group.Key.Code` declined while `group.Key.Item1` emitted.
//
// The KEY is the very tuple the collection's written type named. The loop variable now remembers
// WHERE ITS VALUE CAME FROM when nothing names the element itself — the same fallback a `:=` local
// already keeps — so the ordinary member walk searches that spelling and finds the element.
class GroupingKeyNames {

    // The key IS the tuple, reached through the grouping.
    static func KeyCodes(rows: List<(Code: string, Amount: int)>): string {
        codes := ""
        for group in rows.GroupBy(r => r) {
            codes = codes + group.Key.Code
        }
        return codes
    }

    // The positional spelling of the same element, which emitted before and must still agree.
    static func KeyCodesPositional(rows: List<(Code: string, Amount: int)>): string {
        codes := ""
        for group in rows.GroupBy(r => r) {
            codes = codes + group.Key.Item1
        }
        return codes
    }

    // The second element, so the walk is pinned to the right POSITION and not to "the first string".
    static func KeyAmounts(rows: List<(Code: string, Amount: int)>): int {
        total := 0
        for group in rows.GroupBy(r => r) {
            total = total + group.Key.Amount
        }
        return total
    }
}

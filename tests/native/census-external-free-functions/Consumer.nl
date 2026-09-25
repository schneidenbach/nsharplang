namespace Census.FreeFunctions.Consumer

import System
import System.Linq
import Census.FreeFunctions.Imported
import Census.FreeFunctions.Yielding

// EVERY SHAPE A BARE CALL TAKES INTO A REFERENCED ASSEMBLY'S FREE FUNCTIONS. The library is
// `tests/fixtures/census-external-free-functions-library`, referenced as a built assembly: a global
// function and a global table it fills, an enclosing namespace's functions reached with no import (a
// defaulted parameter omitted and named, an `out` parameter), an imported namespace's function, a
// namespace whose holder yielded its name to a user `Program`, and two referenced functions named as
// method groups -- a delegate-typed local and a LINQ selector.
class FreeFunctionUses {
    static func Digest(): string {
        parsed := 0
        parsedOk := TryParseCount("41", out parsed)
        tally := new GlobalTally()
        filled := GlobalFill(tally, 5)
        filled = filled + GlobalFill(tally, 1)
        doubler: Func<int, int> = Twice
        values: int[] = [1, 2, 3]
        grouped := doubler(5).ToString() + "|" + values.Select(GlobalScale).Sum().ToString()
        return GlobalScale(Twice(2)).ToString() + "|" + Describe(3) + "|" + Describe(4, suffix: "items") + "|" + parsedOk.ToString() + parsed.ToString() + "|" + ImportedOnly() + "|" + Yielded() + "|" + Nearest() + "|" + filled.ToString() + "/" + tally.Count.ToString() + "|" + grouped
    }
}

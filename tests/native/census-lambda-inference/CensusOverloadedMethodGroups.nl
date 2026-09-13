namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic
import System.Linq


// AN OVERLOADED METHOD GROUP AT A POSITION WHOSE OUTPUT TYPE PARAMETER IS STILL BEING INFERRED.
//
// A name with several overloads carries no single signature, so the inference's phase one cannot
// fold it — and the walk used to mark the position SETTLED anyway, which left the delegate's return
// position open forever and declined the whole call at emit. One overload of the same name emitted;
// two declined.
//
// C# makes an OUTPUT type inference FROM a method group at exactly the moment the delegate's INPUT
// types are fixed (ECMA-334 §12.6.3.6): the group's candidates are filtered by those inputs alone,
// and the unique survivor's RETURN type is what the type parameter takes. That is now phase two's
// first arm, beside the lambda's.
class Widen {
    static func Of(value: int): long {
        return value * 10
    }

    static func Of(value: string): long {
        return value.Length
    }

    // A third overload that the inputs do NOT select, so the filtering is visible rather than
    // vacuous: `bool` is not `int`, and the group still converts.
    static func Of(value: bool): long {
        if value {
            return 1
        }

        return 0
    }

    static func Longs(values: int[]): long[] {
        return values.Select(Of).ToArray()
    }

    static func Lengths(words: List<string>): List<long> {
        return words.Select(Of).ToList()
    }
}

class Filters {
    static func Keep(value: int): bool {
        return value > 1
    }

    static func Keep(value: string): bool {
        return value.Length > 1
    }

    static func Longer(values: int[]): int[] {
        return values.Where(Keep).ToArray()
    }

    static func LongerWords(words: List<string>): List<string> {
        return words.Where(Keep).ToList()
    }

    // The overload that is NOT selected is still callable by its own name, so the group was filtered
    // rather than narrowed permanently.
    static func KeptDirectly(word: string): bool {
        return Keep(word)
    }
}

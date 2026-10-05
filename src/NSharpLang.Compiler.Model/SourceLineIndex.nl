namespace NSharpLang.Compiler

import System.Runtime.CompilerServices


// THE START OF EVERY LINE OF A SOURCE TEXT, computed once per string.
//
// Lines split at '\n' only, so line `k` (1-based) starts just after the `(k-1)`th '\n' -- the first
// at 0 -- and a text with `n` newlines has `n + 1` lines, the last empty when the text ends with one.
// That is exactly the walk `CodeIntelligenceTextUtilities.TryGetSourceLineRange` makes, answered by
// an array read.
//
// THREADING: a `ConditionalWeakTable` keyed by the string's identity, safe under parallel analysis
// and holding no text alive; two threads that miss the same string at once compute equal arrays.
class SourceLineStarts {
    Starts: int[]

    constructor(starts: int[]) {
        Starts = starts
    }
}

class SourceLineIndex {
    private static readonly startsBySource: ConditionalWeakTable<string, SourceLineStarts> = new ConditionalWeakTable<string, SourceLineStarts>()

    static func LineStartsOf(source: string): int[] {
        cached: SourceLineStarts? = null
        if SourceLineIndex.startsBySource.TryGetValue(source, out cached) && cached != null {
            return cached.Starts
        }

        newlines := 0
        position := 0
        while position < source.Length {
            if source[position] == '\n' {
                newlines = newlines + 1
            }
            position = position + 1
        }

        starts := new int[](newlines + 1)
        starts[0] = 0
        next := 1
        position = 0
        while position < source.Length {
            if source[position] == '\n' {
                starts[next] = position + 1
                next = next + 1
            }
            position = position + 1
        }

        SourceLineIndex.startsBySource.AddOrUpdate(source, new SourceLineStarts(starts))
        return starts
    }
}

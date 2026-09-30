namespace NSharpLang.CensusFlowRules.Tests

import System


// CENSUS §FLOW2 — THREE RULES ABOUT WHERE A METHOD BODY ENDS AND WHAT A FIELD OWES ITS CONSTRUCTOR.
//
// THE END POINT OF A `while true` IS UNREACHABLE. C# §13.2 says a `while` whose condition is the
// constant `true` and whose body contains no reachable `break` targeting it never falls out of its
// own end, so the function does not need a return after it. N# demanded one, which made the retry
// loop below — the shape the converted CLI's file-acquire path is written in — impossible to spell.
// A `for` whose condition is the constant `true` is the same statement with a different spelling.
//
// A CONSTRUCTOR ACCEPTS A BARE `return`. It runs like a `void` function: the field initializers and
// the base call have already happened, so `return` ends the body and nothing else.
//
// A VALUE-TYPED FIELD OWES ITS CONSTRUCTOR NOTHING. `default` is a valid value of every value type,
// so only a non-nullable REFERENCE-typed field has to be assigned — the CLR has already zeroed the
// rest. The types below are the whole set a census project uses: a primitive, an enum, a struct, a
// nullable and an unconstrained type parameter.
func AttemptsUntilThreshold(threshold: int): int {
    attempt := 0
    while true {
        attempt = attempt + 1
        if attempt >= threshold {
            return attempt
        }
    }
}

func ForeverLoopUntilThreshold(threshold: int): int {
    for attempt := 1; true; attempt = attempt + 1 {
        if attempt >= threshold {
            return attempt
        }
    }
}

func ThrowsFromForeverLoop(): int {
    while true {
        throw new InvalidOperationException("no way out")
    }
}

// A `break` DOES restore the end point, so this one still needs the return after the loop — and the
// value it returns proves the loop really exited rather than the last `return` winning.
func FirstMultipleOrZero(limit: int, factor: int): int {
    found := 0
    value := 1
    while true {
        if value > limit {
            break
        }

        if value % factor == 0 {
            found = value
            break
        }

        value = value + 1
    }

    return found
}

// A `break` bound to a NESTED loop leaves that loop, not this one, so the end point of the outer
// `while` is still unreachable and no trailing return is owed.
func ClassifyUntilExhausted(values: int[]): int {
    index := 0
    total := 0
    while true {
        if index >= values.Length {
            return total
        }

        repeats := 0
        while true {
            repeats = repeats + 1
            if repeats >= values[index] {
                break
            }
        }

        total = total + repeats
        index = index + 1
    }
}

enum Channel {
    Primary,
    Secondary
}

struct Extent {
    Width: int
    Height: int
}

class Daemon {
    private running: bool
    private count: int
    private channel: Channel
    private extent: Extent
    private debounce: int?
    private readonly root: string

    constructor(root: string): this(root, false) {
    }

    constructor(root: string, forced: bool) {
        this.root = root
        if forced {
            this.running = true
            return
        }

        this.count = 1
    }

    Root: string => root
    Running: bool => running
    Count: int => count
    Kind: Channel => channel
    Width: int => extent.Width
    Debounce: int? => debounce
}

class Box<T> {
    private item: T
    private label: string

    constructor(label: string) {
        this.label = label
    }

    Label: string => label
    Item: T => item
}

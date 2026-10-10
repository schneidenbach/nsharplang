namespace NSharpLang.PatternForeach.Tests

import System
import System.Collections
import System.Collections.Generic


// A MUTABLE CURSOR A STRUCT ENUMERATOR CAN STEP. The enumerator below is a struct, and a struct's
// own fields are not assignable from its methods in N# yet, so the position it steps lives here.
class CountdownCursor {
    Remaining: int
    Disposals: int

    constructor(start: int) {
        Remaining = start + 1
        Disposals = 0
    }

    func Step(): bool {
        Remaining = Remaining - 1
        return Remaining > 0
    }

    func RecordDisposal() {
        Disposals = Disposals + 1
    }
}

// A USER COLLECTION THAT IMPLEMENTS NOTHING. It carries the pattern and only the pattern, which is
// the shape C# iterates and the shape N# used to reject outright.
class Countdown {
    Cursor: CountdownCursor

    constructor(cursor: CountdownCursor) {
        Cursor = cursor
    }

    func GetEnumerator(): CountdownEnumerator {
        return new CountdownEnumerator(Cursor)
    }
}

// A STRUCT enumerator that is also disposable: the loop disposes it through a `constrained.` call on
// its own storage, never on a boxed copy.
struct CountdownEnumerator: IDisposable {
    cursor: CountdownCursor

    constructor(cursor: CountdownCursor) {
        this.cursor = cursor
    }

    Current: int => cursor.Remaining

    func MoveNext(): bool {
        return cursor.Step()
    }

    func Dispose() {
        cursor.RecordDisposal()
    }
}

// A REFERENCE enumerator, disposed through a null check and an interface call.
class WordBag {
    Words: string[]
    Log: CountdownCursor

    constructor(words: string[], log: CountdownCursor) {
        Words = words
        Log = log
    }

    func GetEnumerator(): WordBagEnumerator {
        return new WordBagEnumerator(Words, Log)
    }
}

class WordBagEnumerator: IDisposable {
    words: string[]
    log: CountdownCursor
    position: int

    constructor(words: string[], log: CountdownCursor) {
        this.words = words
        this.log = log
        position = -1
    }

    Current: string => words[position]

    func MoveNext(): bool {
        position = position + 1
        return position < words.Length
    }

    func Dispose() {
        log.RecordDisposal()
    }
}

// A USER COLLECTION WHOSE `GetEnumerator` HANDS BACK AN INTERFACE rather than a struct: the loop's
// hidden local is `IEnumerator<int>`, it is disposed through the null-checked interface call, and
// the pattern that found it is the same one a struct enumerator goes through.
class NumberBag {
    Values: List<int>

    constructor(values: List<int>) {
        Values = values
    }

    func GetEnumerator(): IEnumerator<int> {
        sequence: IEnumerable<int> = Values
        return sequence.GetEnumerator()
    }
}

class UserShapes {
    func SumCountdown(countdown: Countdown): int {
        total := 0
        guard := 0
        for value in countdown {
            total = total + value
            guard = guard + 1
            if guard > 16 {
                break
            }
        }

        return total
    }

    func CountCountdownSteps(countdown: Countdown): int {
        steps := 0
        for value in countdown {
            steps = steps + 1
            if steps > 16 {
                break
            }
        }

        return steps
    }

    func FirstWordOrEmpty(bag: WordBag): string {
        for word in bag {
            if word.Length > 0 {
                return word
            }
        }

        return ""
    }

    func JoinWords(bag: WordBag): string {
        joined := ""
        for word in bag {
            joined = joined + word
        }

        return joined
    }

    func JoinWordsUntil(bag: WordBag, stop: string): string {
        joined := ""
        for word in bag {
            if word == stop {
                break
            }

            joined = joined + word
        }

        return joined
    }

    func ThrowOnWord(bag: WordBag, trigger: string) {
        for word in bag {
            if word == trigger {
                throw new InvalidOperationException("stopped at " + word)
            }
        }
    }

    func SumNumberBag(bag: NumberBag): int {
        total := 0
        for value in bag {
            total = total + value
        }

        return total
    }

    // A nested loop proves the enumerator locals do not collide and that the inner protected region
    // nests inside the outer one.
    func CountPairs(outer: NumberBag, inner: NumberBag): int {
        pairs := 0
        for left in outer {
            for right in inner {
                if left != right {
                    continue
                }

                pairs = pairs + 1
            }
        }

        return pairs
    }
}

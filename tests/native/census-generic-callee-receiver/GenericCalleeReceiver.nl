namespace NSharpLang.CensusGenericCalleeReceiver.Tests

import System.Collections.Generic


// THE RECEIVER OF AN EXPLICIT GENERIC CALL IS AN EXPRESSION, NOT A SPELLING.
//
// The parser's generic-callee node used to keep only the callee's dotted TEXT, so every consumer
// re-read the receiver from that text and refused any spelling carrying `(`, `)`, `[` or `]` —
// because the receiver was not in the tree and re-resolving it name by name would have evaluated a
// call twice. The node now carries the callee expression as its first child, so these fixtures
// exercise receivers that have no name at all.
class Node {
    Name: string
    Weight: int

    constructor(name: string, weight: int) {
        Name = name
        Weight = weight
    }

    func Describe(): string {
        return Name + ":" + Weight.ToString()
    }
}

// A SOURCE type with a generic instance method that returns itself, so the chained spelling
// `registry.Add<A>().Add<B>()` is a source-owned call on a call.
class Registry {
    Entries: List<string>

    constructor() {
        Entries = new List<string>()
    }

    func Add<T>(): Registry {
        Entries.Add(typeof(T).Name)
        return this
    }

    func Count(): int {
        return Entries.Count
    }
}

// THE RECEIVER MUST RUN EXACTLY ONCE. The counter is what proves it: the old text reading resolved
// the receiver chain twice (once for its type, once for its value), which is precisely why a chain
// carrying a call was refused rather than emitted.
class Source {
    static Calls: int

    static func Reset() {
        Calls = 0
    }

    static func Mixed(): List<object> {
        Calls = Calls + 1
        values := new List<object>()
        values.Add("alpha")
        values.Add(3)
        values.Add("gamma")
        values.Add(new Node("delta", 4))
        return values
    }
}

func MakeRegistry(): Registry {
    return new Registry()
}

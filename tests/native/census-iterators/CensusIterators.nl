namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Text


// AN ITERATOR BODY IS AN ORDINARY FUNCTION BODY.
//
// Every generator below writes something a plain `func` writes — a call, a `new`, an array or
// collection literal, an indexer, a member access, a conversion at a `yield` — and the state machine
// does nothing to it but move its locals onto its own fields. These definitions exist to be EXECUTED:
// the tests beside them enumerate each one and assert the sequence, the laziness, and the exceptions.

// A side-effect recorder, so laziness is observable rather than asserted by inspection.
class CensusTrace {
    Entries: List<string>

    constructor() {
        Entries = new List<string>()
    }

    func Add(entry: string) {
        Entries.Add(entry)
    }

    func Joined(): string {
        return String.Join(",", Entries)
    }

    func Count(): int {
        return Entries.Count
    }
}


// A collection built and read INSIDE the machine: `new`, an instance call, an indexer and a classic
// `for` with a compound-assignment increment.
func* DoubledThrough(count: int): IEnumerable<int> {
    values := new List<int>()
    for i := 0; i < count; i += 1 {
        values.Add(i * 2)
        yield values[i]
    }
}

// The xUnit `MemberData` row shape: an `object[]` whose elements only agree because the POSITION says
// `object` — a string, a boxed int, and a nested `string[]`.
func* MemberRows(): IEnumerable<object[]> {
    yield ["symbols", 1, ["symbols", "--project", "examples"]]
    yield ["outline", 2, ["outline", "Program.nl"]]
}

// A static BCL call as the `for..in` source, and an instance call on the loop element.
func* TrimmedParts(text: string): IEnumerable<string> {
    for part in text.Split(',') {
        if part.Length > 0 {
            yield part.Trim()
        }
    }
}

// A generator consumed by another generator: `for..in` over a call to a sibling `func*`.
func* DoubledRows(count: int): IEnumerable<int> {
    for value in DoubledThrough(count) {
        yield value + 1
    }
}

// A `yield` whose value needs a CONVERSION: an int boxed to the `object` element type.
func* BoxedValues(count: int): IEnumerable<object> {
    i := 0
    while i < count {
        yield i
        i = i + 1
    }
}

// A `yield` whose value needs a REFERENCE conversion: a `StringBuilder` widened to `object`.
func* BuilderThenText(): IEnumerable<object> {
    builder := new StringBuilder()
    builder.Append("ab")
    yield builder
    yield builder.ToString()
}

// Laziness and ordering: each step records a side effect the consumer can observe only by enumerating.
func* Recorded(trace: CensusTrace, count: int): IEnumerable<int> {
    trace.Add("start")
    i := 0
    while i < count {
        trace.Add("before" + i.ToString())
        yield i
        trace.Add("after" + i.ToString())
        i = i + 1
    }
    trace.Add("end")
}

// An exception raised from inside a body surfaces at the `MoveNext` that reaches it, not at the call
// that created the sequence — and the thrown value is an ordinary expression with real arguments.
func* FailsAfterFirst(message: string): IEnumerable<int> {
    yield 1
    throw new InvalidOperationException("stopped: " + message)
}

// A generic generator whose body calls a BCL generic method and yields through a hoisted list.
func* RepeatedPairs<T>(value: T, times: int): IEnumerable<T> {
    i := 0
    while i < times {
        yield value
        i = i + 1
    }
}

// A dictionary built inside the machine, read through its indexer, and enumerated by key.
func* LookupValues(keys: string[]): IEnumerable<int> {
    table := new Dictionary<string, int>()
    table["a"] = 1
    table["b"] = 2
    for key in keys {
        if table.ContainsKey(key) {
            yield table[key]
        }
    }
}

// A `for..in` over a LIST the body built, proving the hoisted-enumerator loop runs over an ordinary
// value rather than a specially admitted source spelling.
func* ListElements(count: int): IEnumerable<string> {
    items := new List<string>()
    i := 0
    while i < count {
        items.Add("item" + i.ToString())
        i = i + 1
    }
    for item in items {
        yield item.ToUpper()
    }
}

// A static sibling call inside the body, in an argument position and as a condition.
func* AboveThreshold(values: int[], threshold: int): IEnumerable<int> {
    for value in values {
        if Scale(value) > threshold {
            yield Scale(value)
        }
    }
}

func Scale(value: int): int {
    return value * 3
}

// An `async func*` over the same ordinary-expression surface: a `new`, an instance call and an
// indexer inside the asynchronous machine.
async func* AsyncDoubled(count: int): IAsyncEnumerable<int> {
    values := new List<int>()
    for i := 0; i < count; i += 1 {
        values.Add(i * 2)
        yield values[i]
    }
}

// An async generator whose yielded value needs a conversion.
async func* AsyncBoxed(count: int): IAsyncEnumerable<object> {
    i := 0
    while i < count {
        yield i
        i = i + 1
    }
}

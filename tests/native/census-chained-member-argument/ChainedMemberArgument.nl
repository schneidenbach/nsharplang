namespace NSharpLang.CensusChainedMemberArgument.Tests

import System
import System.Collections.Generic
import System.Text

// A MEMBER READ WHOSE RECEIVER IS ITSELF A MEMBER READ, IN ARGUMENT POSITION.
//
// A call's arguments are TYPED BY PLANNING THEM, so an argument the planner cannot type leaves the
// call with no argument types and the call is then declined as "not modeled". The receiver of a
// member read had owners for four shapes only — a static member read, a scalar literal, `nameof`
// and `typeof` — so a chain stopped being plannable at its SECOND hop and every call taking one
// declined. These subjects are the chain shapes an ordinary author writes: property over property,
// field over field, a call result, an element, and the mixtures of them, over BOTH this
// compilation's own types and referenced ones.
class Leaf {
    Tag: string = ""
    Size: int = 0

    constructor(tag: string, size: int) {
        Tag = tag
        Size = size
    }

    func Describe(): string {
        return Tag + ":" + Size.ToString()
    }
}

class Mid {
    Leaf: Leaf
    Items: List<Leaf> = new List<Leaf>()
    Map: Dictionary<string, Leaf> = new Dictionary<string, Leaf>()
    Moment: DateTime = new DateTime(2026, 9, 21)

    constructor(leaf: Leaf) {
        Leaf = leaf
        Items.Add(leaf)
        Map["k"] = leaf
    }
}

class Root {
    Mid: Mid

    constructor(mid: Mid) {
        Mid = mid
    }
}

func NewRoot(tag: string, size: int): Root {
    return new Root(new Mid(new Leaf(tag, size)))
}

// Two hops over SOURCE types, in the argument of a generic external instance method whose type
// argument is inferred from that argument alone.
func HashTwoHops(r: Root): int {
    hash := new HashCode()
    hash.Add(r.Mid.Leaf.Tag)
    return hash.ToHashCode()
}

func HashOneHop(m: Mid): int {
    hash := new HashCode()
    hash.Add(m.Leaf.Tag)
    return hash.ToHashCode()
}

// Three hops, the last of them an `int` field.
func ThreeHopValue(r: Root): string {
    builder := new StringBuilder()
    builder.Append(r.Mid.Leaf.Size)
    return builder.ToString()
}

// A chain whose intermediate hop is an ELEMENT, and one whose intermediate hop is a DICTIONARY
// lookup. Both compose with the member read that follows them.
func ElementHopTag(r: Root): string {
    builder := new StringBuilder()
    builder.Append(r.Mid.Items[0].Tag)
    return builder.ToString()
}

func MapHopTag(r: Root): string {
    builder := new StringBuilder()
    builder.Append(r.Mid.Map["k"].Tag)
    return builder.ToString()
}

// A chain whose intermediate hop is a CALL, and a chain that ENDS in a call over two hops.
func CallHopLength(r: Root): int {
    hash := new HashCode()
    hash.Add(r.Mid.Leaf.Describe().Length)
    return hash.ToHashCode()
}

func CallOverTwoHops(r: Root): string {
    builder := new StringBuilder()
    builder.Append(r.Mid.Leaf.Describe())
    return builder.ToString()
}

// A VALUE-TYPE hop in the middle: the receiver of `Year` is a `DateTime` produced by a property
// read, which needs an address rather than a reference.
func ValueTypeHopYear(r: Root): string {
    builder := new StringBuilder()
    builder.Append(r.Mid.Moment.Year)
    return builder.ToString()
}

// The same shapes over REFERENCED types only: `Uri` -> `Uri` -> `string`, and a two-hop read whose
// last hop is an `int`.
func ExternalTwoHops(u: Uri): string {
    builder := new StringBuilder()
    builder.Append(new Uri(u, "child").Host)
    return builder.ToString()
}

func ExternalChainHost(pair: KeyValuePair<string, Uri>): string {
    builder := new StringBuilder()
    builder.Append(pair.Value.Host)
    return builder.ToString()
}

func ExternalChainSegmentCount(pair: KeyValuePair<string, Uri>): string {
    builder := new StringBuilder()
    builder.Append(pair.Value.Segments.Length)
    return builder.ToString()
}

// EVALUATION ORDER. Each hop records the order it ran in, so the recorded sequence states that a
// chained argument is evaluated left to right and exactly once per hop, and that the argument as a
// whole is evaluated AFTER the receiver of the call it is an argument to.
class OrderLog {
    Steps: List<string> = new List<string>()

    func Note(step: string): OrderLog {
        Steps.Add(step)
        return this
    }
}

class Counter {
    Log: OrderLog
    Reads: int = 0

    constructor(log: OrderLog) {
        Log = log
    }

    Inner: Counter2 {
        get {
            Reads = Reads + 1
            Log.Note("outer")
            return new Counter2(Log)
        }
    }
}

class Counter2 {
    Log: OrderLog

    constructor(log: OrderLog) {
        Log = log
    }

    Value: string {
        get {
            Log.Note("inner")
            return "v"
        }
    }
}

func RecordedOrder(): List<string> {
    log := new OrderLog()
    counter := new Counter(log)
    builder := new StringBuilder()
    log.Note("receiver")
    builder.Append(counter.Inner.Value)
    return log.Steps
}

func OuterHopReadCount(): int {
    log := new OrderLog()
    counter := new Counter(log)
    builder := new StringBuilder()
    builder.Append(counter.Inner.Value)
    return counter.Reads
}

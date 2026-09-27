namespace NSharpLang.CensusChainedMemberArgument.Tests

import System
import System.Collections.Generic
import System.Linq
import System.Numerics
import System.Text
import System.Text.RegularExpressions

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

// A HOP THROUGH AN INDEXER A REFERENCED TYPE DECLARES. `match.Groups["id"]` is `GroupCollection`'s
// own `get_Item(string)`, not one of the collections the element hop above reads by name, and it
// EMITTED as a local's initializer while it could not be TYPED before emission: the call taking it
// as an argument then had nothing to choose an overload with and declined as "not modeled". Both
// selectors the type declares (a name and a group number), a chain of two indexers, an overload set
// chosen by the indexed member's `bool`, and a VALUE-TYPE receiver (`Vector<int>`, whose instance
// member takes an address) are the shapes an author writes.
func PairPattern(): string {
    return "(?<key>\\w+)=(?<value>[^;]*)"
}

func NamedGroupWordCount(input: string): int {
    found := Regex.Match(input, PairPattern())
    return Regex.Matches(found.Groups["value"].Value, "\\w+").Count
}

func NumberedGroupWordCount(input: string): int {
    found := Regex.Match(input, PairPattern())
    return Regex.Matches(found.Groups[2].Value, "\\w+").Count
}

func SecondPairKey(input: string): string {
    pairs := Regex.Matches(input, PairPattern())
    return string.Concat(pairs[1].Groups["key"].Value, "!")
}

func GroupMatched(input: string, name: string): string {
    builder := new StringBuilder()
    builder.Append(Regex.Match(input, PairPattern()).Groups[name].Success)
    return builder.ToString()
}

func LaneOrFloor(values: int[], lane: int, floor: int): int {
    return Math.Max(new Vector<int>(values)[lane], floor)
}

// The receiver of the indexer is evaluated before its selector, and both before the call they are
// an argument to, for a REFERENCE receiver and for a VALUE one alike.
func IndexerOrder(log: OrderLog, input: string): List<string> {
    Regex.Matches(LoggedGroups(log, input)[LoggedGroupName(log)].Value, "\\w+")
    Math.Max(LoggedVector(log)[LoggedLane(log)], 0)
    return log.Steps
}

func LoggedGroups(log: OrderLog, input: string): GroupCollection {
    log.Note("groups")
    return Regex.Match(input, PairPattern()).Groups
}

func LoggedGroupName(log: OrderLog): string {
    log.Note("name")
    return "value"
}

func LoggedVector(log: OrderLog): Vector<int> {
    log.Note("vector")
    return new Vector<int>(3)
}

func LoggedLane(log: OrderLog): int {
    log.Note("lane")
    return 0
}

// THE SAME HOPS WHERE THERE IS NO RESIDUAL EMITTER ARM TO FALL BACK TO. A generator's body and a
// source constructor's arguments are planned whole, so an indexer hop the planner cannot read stops
// the function: `yield found.Groups["key"].Value` declined the generator at
// `emit.iterator.unsupported-shape` while `yield found.Value` emitted.
func* PairKeys(input: string): IEnumerable<string> {
    for pair in Regex.Matches(input, PairPattern()) {
        yield pair.Groups["key"].Value
    }
}

func* LanesThenOrder(log: OrderLog, values: int[]): IEnumerable<int> {
    yield new Vector<int>(values)[1]
    yield LoggedVector(log)[LoggedLane(log)]
}

func LeafFromPair(input: string): Leaf {
    found := Regex.Match(input, PairPattern())
    return new Leaf(found.Groups["key"].Value, found.Groups["value"].Length)
}

// A LAMBDA WHOSE BODY IS THE INDEXER READ. Its delegate's return type is inferred by typing the body
// before it is emitted, so `Select(name => found.Groups[name])` declined at the `Select` call while a
// body ending in `.Value` — a different root — did not.
func GroupsNamed(input: string, names: List<string>): List<Group> {
    found := Regex.Match(input, PairPattern())
    return names.Select(name => found.Groups[name]).ToList()
}

// AN INDEXER THE RECEIVER INHERITS. `Tags` declares no `get_Item`; it IS a `List<string>`, so `tags[0]`
// reads the base's indexer with the derived receiver, in a generator's body as anywhere else.
class Tags: List<string> {
}

func* TagsThenLast(tags: Tags): IEnumerable<string> {
    yield tags[0]
    yield string.Concat(tags[tags.Count - 1], "!")
}

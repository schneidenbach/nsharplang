namespace NSharpLang.ConstructedGenericInterop.Tests

import System
import System.Collections.Generic

// THE EXECUTABLE HALF OF ".NET GENERIC INTEROP OVER YOUR OWN TYPE PARAMETERS".
//
// Everything below is written inside a generic declaration and mentions that declaration's own type
// parameters in a place the CLR calls an EXTERNAL generic: a static receiver (`EqualityComparer<TOk>`),
// a base list (`IEquatable<Outcome<TOk, TErr>>`), a field (`List<T>`, `Dictionary<string, T>`), and a
// parameter and return (`IEnumerable<T>`, `KeyValuePair<string, T>`). None of these shapes can be
// stated by a table of admitted BCL heads, because the table cannot know the type argument; each one
// resolves through ordinary scoped type resolution and closes with `MakeGenericType`, and each member
// on it is rebound onto the instantiation with `TypeBuilder.GetMethod`/`GetField`.
//
// THE EQUALITY IS DELIBERATELY NOT FIELD-WISE. `Outcome<TOk, TErr>.Equals` compares only the `ok`
// arm. A value type's DEFAULT equality compares every field, so `EqualityComparer<Outcome<int,
// string>>.Default.Equals(ok1x, ok1y)` answers `true` only if the BCL picked the `IEquatable<T>`
// comparer — that is, only if the constructed interface really landed in this type's metadata and its
// MethodImpl really points at the method below. A test that compared two equal values could not tell
// the two apart.
struct Outcome<TOk, TErr>: IEquatable<Outcome<TOk, TErr>> {
    ok: TOk
    err: TErr
    state: int

    constructor(ok: TOk, err: TErr, state: int) {
        this.ok = ok
        this.err = err
        this.state = state
    }

    IsOk: bool => state == 1

    OkValue: TOk => ok

    ErrValue: TErr => err

    // The static receiver under test: an external generic closed over this declaration's own `TOk`,
    // whose `Default` property and `Equals`/`GetHashCode` members are all builder-bound.
    func Equals(other: Outcome<TOk, TErr>): bool {
        if state != other.state {
            return false
        }
        if state == 1 {
            return EqualityComparer<TOk>.Default.Equals(ok, other.ok)
        }
        if state == 2 {
            return EqualityComparer<TErr>.Default.Equals(err, other.err)
        }
        return true
    }

    func GetHashCode(): int {
        if state == 1 {
            return HashCode.Combine(state, ok)
        }
        if state == 2 {
            return HashCode.Combine(state, err)
        }
        return 0
    }
}

// `IComparable<Node<T>>` is the base-list shape whose type argument is this declaration's own
// constructed self. `Comparer<Node<string>>.Default` refuses to order a type that does not implement
// it, so the ordering below is proof that the constructed interface is really in the metadata.
class Node<T>: IComparable<Node<T>> {
    payload: T
    rank: int

    constructor(payload: T, rank: int) {
        this.payload = payload
        this.rank = rank
    }

    Payload: T => payload

    Rank: int => rank

    func CompareTo(other: Node<T>): int {
        return Comparer<int>.Default.Compare(rank, other.rank)
    }
}

// Fields, parameters and returns typed by external generics over the class's own parameter.
class Bag<T> {
    items: List<T>
    index: Dictionary<string, T>

    constructor() {
        items = new List<T>()
        index = new Dictionary<string, T>()
    }

    Count: int => items.Count

    func Add(key: string, value: T) {
        items.Add(value)
        index[key] = value
    }

    func AddAll(values: IEnumerable<T>) {
        for value in values {
            items.Add(value)
        }
    }

    func Lookup(key: string): T {
        return index[key]
    }

    func Has(key: string): bool {
        return index.ContainsKey(key)
    }

    func At(position: int): T {
        return items[position]
    }

    func Entry(key: string): KeyValuePair<string, T> {
        value := index[key]
        return new KeyValuePair<string, T>(key, value)
    }

    func Snapshot(): T[] {
        return items.ToArray()
    }

    func Largest(a: T, b: T): T {
        if Comparer<T>.Default.Compare(a, b) >= 0 {
            return a
        }
        return b
    }
}

test "EqualityComparer over the enclosing type's own parameter drives the Ok arm" {
    first := new Outcome<int, string>(7, "", 1)
    second := new Outcome<int, string>(7, "", 1)
    third := new Outcome<int, string>(8, "", 1)

    assert first.IsOk
    assert first.OkValue == 7
    assert first.Equals(second)
    assert !first.Equals(third)
    assert first.GetHashCode() == second.GetHashCode()
}

test "EqualityComparer over the enclosing type's own parameter drives the Err arm" {
    first := new Outcome<int, string>(0, "boom", 2)
    second := new Outcome<int, string>(0, "boom", 2)
    third := new Outcome<int, string>(0, "other", 2)

    assert !first.IsOk
    assert first.ErrValue == "boom"
    assert first.Equals(second)
    assert !first.Equals(third)
    assert !first.Equals(new Outcome<int, string>(0, "", 1))
}

test "the constructed interface base is in the emitted metadata" {
    outcomeType := typeof(Outcome<int, string>)
    equatable := typeof(IEquatable<Outcome<int, string>>)
    found := false
    for candidate in outcomeType.GetInterfaces() {
        if candidate == equatable {
            found = true
        }
    }
    assert found

    nodeType := typeof(Node<string>)
    comparable := typeof(IComparable<Node<string>>)
    nodeFound := false
    for candidate in nodeType.GetInterfaces() {
        if candidate == comparable {
            nodeFound = true
        }
    }
    assert nodeFound

    // The interface is CONSTRUCTED, not the open definition, and it is not the same interface for a
    // different instantiation of the same source type.
    arguments := equatable.GetGenericArguments()
    assert arguments.Length == 1
    assert arguments[0] == outcomeType
    otherEquatable := typeof(IEquatable<Outcome<string, int>>)
    assert otherEquatable != equatable
}

test "the BCL dispatches through the constructed interface" {
    okOne := new Outcome<int, string>(1, "", 1)
    // Same Ok arm, DIFFERENT err field: field-wise value equality says false, and only a real
    // IEquatable<Outcome<int, string>> dispatch says true.
    okOneOther := new Outcome<int, string>(1, "residue", 1)

    assert EqualityComparer<Outcome<int, string>>.Default.Equals(okOne, okOneOther)
    assert !EqualityComparer<Outcome<int, string>>.Default.Equals(okOne, new Outcome<int, string>(2, "", 1))

    low := new Node<string>("low", 1)
    high := new Node<string>("high", 9)
    // Comparer<T>.Default throws for a T that does not implement IComparable<T>.
    assert Comparer<Node<string>>.Default.Compare(low, high) < 0
    assert Comparer<Node<string>>.Default.Compare(high, low) > 0
    assert Comparer<Node<string>>.Default.Compare(low, low) == 0
}

test "Comparer over a class type parameter orders both reference and value arguments" {
    numbers := new Bag<int>()
    assert numbers.Largest(3, 9) == 9
    assert numbers.Largest(9, 3) == 9
    assert numbers.Largest(4, 4) == 4

    words := new Bag<string>()
    assert words.Largest("alpha", "beta") == "beta"
    assert words.Largest("beta", "alpha") == "beta"
}

test "collection fields typed over the class's own parameter round trip" {
    bag := new Bag<string>()
    bag.Add("first", "alpha")
    bag.Add("second", "beta")

    assert bag.Count == 2
    assert bag.Lookup("first") == "alpha"
    assert bag.Lookup("second") == "beta"
    assert bag.Has("second")
    assert !bag.Has("third")
    assert bag.At(0) == "alpha"

    entry := bag.Entry("second")
    assert entry.Key == "second"
    assert entry.Value == "beta"

    extra: string[] = ["gamma", "delta"]
    bag.AddAll(extra)
    assert bag.Count == 4
    assert bag.At(3) == "delta"

    snapshot := bag.Snapshot()
    assert snapshot.Length == 4
    assert snapshot[0] == "alpha"
}

test "the same collection fields carry a value-type argument" {
    bag := new Bag<int>()
    bag.Add("one", 1)
    bag.Add("two", 2)

    assert bag.Count == 2
    assert bag.Lookup("one") == 1
    assert bag.Lookup("two") == 2
    assert bag.At(1) == 2

    entry := bag.Entry("two")
    assert entry.Key == "two"
    assert entry.Value == 2

    more: int[] = [3, 4]
    bag.AddAll(more)
    assert bag.Count == 4

    snapshot := bag.Snapshot()
    assert snapshot.Length == 4
    assert snapshot[3] == 4

    // Two instantiations of the same source declaration are two distinct constructed types, and each
    // one carries its own closed field types.
    assert typeof(Bag<int>) != typeof(Bag<string>)
    assert typeof(Bag<int>).GetGenericArguments()[0] == typeof(int)
    assert typeof(Bag<string>).GetGenericArguments()[0] == typeof(string)
}

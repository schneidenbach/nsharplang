namespace NSharpLang.CompleteSourceGenericArgs.Tests

import System
import System.Collections.Generic

// THE EXECUTABLE HALF OF ".NET GENERIC INTEROP OVER YOUR OWN COMPLETE TYPES".
//
// Its sibling `tests/native/constructed-generic-interop` covers external generics closed over a
// declaration's own TYPE PARAMETERS. Everything below closes one over a COMPLETE type of this
// compilation instead — a struct, a class, a record, a nested type, a closed instantiation of a
// source generic, and an array of them — at every site a type can appear: a base list, a field, a
// local, a parameter, a return, a collection element and a static receiver.
//
// The compiler cannot state these shapes with a table of admitted BCL heads, because the table
// cannot know the type argument. Each one resolves the open definition through ordinary scoped
// resolution at the written arity and closes it with `MakeGenericType`, and each source type that
// implements one converts into it by the ordinary reference/boxing rule.
//
// THE EQUALITY AND ORDERING ARE DELIBERATELY NOT THE DEFAULT ONES. `Plain.Equals` compares only
// `value` and ignores `tag`; a value type's default equality compares every field. So
// `EqualityComparer<Plain>.Default.Equals` on two values that differ in `tag` answers `true` only if
// the BCL picked the `IEquatable<Plain>` comparer — that is, only if the constructed interface
// really landed in this struct's metadata and its MethodImpl really points at the method below.
// `Item.CompareTo` orders DESCENDING for the same reason: an ascending result would also be what a
// missing implementation produced.
struct Plain: IEquatable<Plain> {
    value: int
    tag: string

    constructor(value: int, tag: string) {
        this.value = value
        this.tag = tag
    }

    Value: int => value

    Tag: string => tag

    func Equals(other: Plain): bool {
        return value == other.value
    }

    func GetHashCode(): int {
        return value
    }
}

// A REFERENCE implementer, so the conversion into its constructed interface emits no instruction at
// all where the struct above emits a `box`.
class Item: IComparable<Item> {
    rank: int
    name: string

    constructor(rank: int, name: string) {
        this.rank = rank
        this.name = name
    }

    Rank: int => rank

    Name: string => name

    // DESCENDING, so `List<Item>.Sort()` producing ranks 3, 2, 1 is proof that the BCL called this
    // method through `IComparable<Item>` rather than falling back on anything else.
    func CompareTo(other: Item): int {
        return other.rank - rank
    }
}

record Reading {
    Sensor: string
    Celsius: int
}

// A generic source type whose base list closes an external generic over its OWN constructed self,
// so `Outcome<int, string>` is a complete source type that a use site outside the declaration can
// name inside another external generic (`IEquatable<Outcome<int, string>>`).
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

    // Only the OK arm participates, exactly as in the sibling project, so a default field-wise
    // comparison and this one disagree.
    func Equals(other: Outcome<TOk, TErr>): bool {
        if state != other.state {
            return false
        }
        if state == 1 {
            return EqualityComparer<TOk>.Default.Equals(ok, other.ok)
        }
        return true
    }

    func GetHashCode(): int {
        return state
    }
}

class Outer {
    class Nested: IEquatable<Nested> {
        id: int

        constructor(id: int) {
            this.id = id
        }

        Id: int => id

        func Equals(other: Nested): bool {
            return other != null && id == other.id
        }

        func GetHashCode(): int {
            return id
        }
    }
}

// Fields, parameters and returns typed by external generics over COMPLETE source types.
class Ledger {
    equatable: IEquatable<Plain>
    rows: List<Plain>
    byName: Dictionary<string, Plain>

    constructor(seed: Plain) {
        equatable = seed
        rows = new List<Plain>()
        byName = new Dictionary<string, Plain>()
    }

    Seed: IEquatable<Plain> => equatable

    Count: int => rows.Count

    func Add(key: string, row: Plain) {
        rows.Add(row)
        byName[key] = row
    }

    func Entry(key: string): KeyValuePair<string, Plain> {
        // THE NESTED INDEXER READ IS THE POINT: the value argument is an indexer read written
        // directly inside the construction, not lifted into a local first.
        return new KeyValuePair<string, Plain>(key, byName[key])
    }

    func Sequence(): IEnumerable<Plain> {
        return rows
    }

    func SameAsSeed(candidate: IEquatable<Plain>): bool {
        return candidate.Equals(rows[0])
    }
}

func PlainArrayComparer(): IEqualityComparer<Plain> {
    return EqualityComparer<Plain>.Default
}

// A delegate closed over a COMPLETE source type, built as a local and returned. (A lambda assigned
// to a FIELD inside a constructor is a separate unsupported shape — it declines for `Func<int, bool>`
// too — so the delegate is exercised where the language supports it today.)
func PositivePlain(): Func<Plain, bool> {
    matcher: Func<Plain, bool> = p => p.Value > 0
    return matcher
}

test "a non-generic source struct carries a constructed external interface over itself" {
    plainType := typeof(Plain)
    equatable := typeof(IEquatable<Plain>)
    found := false
    for candidate in plainType.GetInterfaces() {
        if candidate == equatable {
            found = true
        }
    }
    assert found

    arguments := equatable.GetGenericArguments()
    assert arguments.Length == 1
    assert arguments[0] == plainType
    assert equatable != typeof(IEquatable<Item>)
}

test "the BCL dispatches through the constructed interface of a complete source struct" {
    left := new Plain(4, "left")
    // Same `value`, DIFFERENT `tag`: field-wise value equality says false, and only a real
    // IEquatable<Plain> dispatch says true.
    right := new Plain(4, "right")
    other := new Plain(5, "left")

    assert EqualityComparer<Plain>.Default.Equals(left, right)
    assert !EqualityComparer<Plain>.Default.Equals(left, other)
    assert EqualityComparer<Plain>.Default.GetHashCode(left) == EqualityComparer<Plain>.Default.GetHashCode(right)
    assert !left.Tag.Equals(right.Tag, StringComparison.Ordinal)
}

test "a complete source struct converts into its constructed interface at a local, a field, a parameter and a return" {
    seed := new Plain(9, "seed")
    local: IEquatable<Plain> = seed
    assert local.Equals(new Plain(9, "elsewhere"))
    assert !local.Equals(new Plain(10, "seed"))

    ledger := new Ledger(seed)
    ledger.Add("a", new Plain(9, "a"))
    ledger.Add("b", new Plain(1, "b"))
    assert ledger.Count == 2
    assert ledger.Seed.Equals(new Plain(9, "anything"))
    assert ledger.SameAsSeed(local)
    assert !ledger.SameAsSeed(new Plain(1, "b"))
}

test "a complete source class converts into its constructed interface and the BCL orders by it" {
    items := new List<Item>()
    items.Add(new Item(1, "one"))
    items.Add(new Item(3, "three"))
    items.Add(new Item(2, "two"))
    // DESCENDING is what this type's own CompareTo says, so this ordering is proof the BCL called it.
    items.Sort()
    assert items[0].Rank == 3
    assert items[1].Rank == 2
    assert items[2].Rank == 1

    comparable: IComparable<Item> = items[0]
    assert comparable.CompareTo(items[2]) < 0
    assert Comparer<Item>.Default.Compare(items[0], items[2]) < 0
    assert Comparer<Item>.Default.Compare(items[2], items[0]) > 0
}

test "a closed instantiation of a source generic is a complete argument at a use site outside its declaration" {
    ok := new Outcome<int, string>(3, "", 1)
    okOther := new Outcome<int, string>(3, "residue", 1)
    different := new Outcome<int, string>(4, "", 1)

    equatable: IEquatable<Outcome<int, string>> = ok
    assert equatable.Equals(okOther)
    assert !equatable.Equals(different)

    // Only an IEquatable<Outcome<int, string>> dispatch answers true for two values whose `err`
    // fields differ.
    assert EqualityComparer<Outcome<int, string>>.Default.Equals(ok, okOther)
    assert !EqualityComparer<Outcome<int, string>>.Default.Equals(ok, different)
    assert typeof(IEquatable<Outcome<int, string>>) != typeof(IEquatable<Outcome<string, int>>)
}

test "a nested source class is a complete argument at every one of the same sites" {
    first := new Outer.Nested(11)
    second := new Outer.Nested(11)
    third := new Outer.Nested(12)

    equatable: IEquatable<Outer.Nested> = first
    assert equatable.Equals(second)
    assert !equatable.Equals(third)
    assert EqualityComparer<Outer.Nested>.Default.Equals(first, second)
    assert !EqualityComparer<Outer.Nested>.Default.Equals(first, third)

    nestedType := typeof(Outer.Nested)
    assert nestedType.get_DeclaringType() == typeof(Outer)
    assert typeof(IEquatable<Outer.Nested>).GetGenericArguments()[0] == nestedType
}

test "external generics over a complete source type store as fields, locals, collection elements and delegates" {
    seed := new Plain(2, "seed")
    ledger := new Ledger(seed)
    ledger.Add("a", new Plain(2, "a"))
    ledger.Add("b", new Plain(0, "b"))

    entry := ledger.Entry("a")
    assert entry.Key == "a"
    assert entry.Value.Value == 2

    matcher := PositivePlain()
    assert matcher(new Plain(1, "x"))
    assert !matcher(new Plain(0, "x"))

    sequence := ledger.Sequence()
    total := 0
    for row in sequence {
        total = total + row.Value
    }
    assert total == 2

    pairs := new List<KeyValuePair<string, Plain>>()
    pairs.Add(entry)
    assert pairs.Count == 1
    assert pairs[0].Value.Value == 2

    comparers := new List<IEquatable<Plain>>()
    comparers.Add(seed)
    assert comparers[0].Equals(new Plain(2, "elsewhere"))
}

test "external generics over a complete source RECORD reach the same sites" {
    first := new Reading { Sensor: "s1", Celsius: 20 }
    second := new Reading { Sensor: "s1", Celsius: 20 }

    readings: List<Reading> = new List<Reading>()
    readings.Add(first)
    byName: Dictionary<string, Reading> = new Dictionary<string, Reading>()
    byName[first.Sensor] = first
    assert readings[0].Celsius == 20
    assert byName["s1"].Celsius == 20
    assert second.Sensor == "s1"

    // A record's generated equality is what makes it a legal dictionary KEY, and a record value is
    // also an ordinary argument to an external generic constructed over it.
    keyed: Dictionary<Reading, int> = new Dictionary<Reading, int>()
    keyed[first] = 1
    assert keyed[second] == 1
    assert keyed.Count == 1
}

// AN ARRAY OF A COMPLETE SOURCE TYPE AS A GENERIC ARGUMENT. The general arm asks the ordinary
// storability question of the argument, and `Plain[]` is a single-dimension array of a storable
// element. (A COLLECTION whose element is such an array — `List<Plain[]>` — is a different question
// with a different owner: `IsAdmissibleCollectionElement` still refuses a builder-bound element, and
// `website/docs/types.md` records that limit.)
test "an array of a complete source type is a complete generic argument" {
    rows := new Plain[](2)
    rows[0] = new Plain(1, "a")
    rows[1] = new Plain(2, "b")

    batch: Func<Plain[], bool> = candidate => candidate.Length > 0 && candidate[0].Value > 0
    assert batch(rows)
    assert rows[1].Value == 2

    empty := new Plain[](0)
    assert !batch(empty)
}

test "a static receiver typed by an external generic over a complete source type is a value" {
    comparer := PlainArrayComparer()
    assert comparer.Equals(new Plain(6, "one"), new Plain(6, "two"))
    assert !comparer.Equals(new Plain(6, "one"), new Plain(7, "one"))

    ordering: IComparer<Item> = Comparer<Item>.Default
    assert ordering.Compare(new Item(2, "hi"), new Item(1, "lo")) < 0

    // The static receiver's own type is the constructed external generic, not the definition.
    assert comparer != null
    assert typeof(IEqualityComparer<Plain>).GetGenericArguments()[0] == typeof(Plain)
}

test "a nested indexer read is an ordinary constructor argument" {
    byName := new Dictionary<string, int>()
    byName["a"] = 5
    byName["b"] = 6

    direct := new KeyValuePair<string, int>("a", byName["a"])
    lifted := byName["a"]
    viaLocal := new KeyValuePair<string, int>("a", lifted)
    assert direct.Key == viaLocal.Key
    assert direct.Value == viaLocal.Value
    assert direct.Value == 5

    // The same read as an array-literal element, where the plan-side value walk is the only owner.
    values := [byName["a"], byName["b"]]
    assert values.Length == 2
    assert values[0] == 5
    assert values[1] == 6
}

test "a missing dictionary key still throws where a nested read is the constructor argument" {
    byName := new Dictionary<string, int>()
    byName["present"] = 1

    threw := false
    try {
        absent := new KeyValuePair<string, int>("absent", byName["absent"])
        threw = absent.Value < 0
    } catch ex: Exception {
        // `KeyNotFoundException` is not one of the catch-type spellings the backend resolves yet, so
        // the guard is the base type; what this pins is that a missing key still THROWS where the
        // read is nested directly inside the construction, exactly as it does on its own line.
        threw = true
    }
    assert threw
}

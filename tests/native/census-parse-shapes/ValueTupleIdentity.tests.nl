namespace NSharpLang.CensusParseShapes.Tests

import System
import System.Collections.Generic
import System.Linq
import System.Reflection
import System.Runtime.CompilerServices


// `System.ValueTuple`N` IS THE TUPLE TYPE `(T1, ..., TN)`, AND ITS ELEMENT NAMES SURVIVE EVERY
// POSITION THEY ARE WRITTEN IN.
//
// Four census defects meet here, and they are one fact seen from four sides: element names have no
// CLR identity at all. `(Item: string, Count: int)` IS `ValueTuple<string, int>` in every signature,
// and the names live in a `TupleElementNamesAttribute` on the POSITION that declared them.
//
//   1. The analyzer had TWO TypeInfos for that one CLR type -- one for the `ValueTuple<...>` spelling
//      and one for the tuple spelling -- so `g: ValueTuple<string, List<int>> = (x, l)` reported
//      NL202 with the two halves of one type printed as if they disagreed.
//   2. A NARROWED `(Uri: string, Line: int)?` could not answer `.Value`, because the narrowed-origin
//      rule admitted only primitive-like receivers.
//   3. The names a tuple carries inside a GENERIC ARGUMENT resolved in the analyzer but not at the
//      emit boundary, so `rows[0].Item` reported NL103 and `ItemN` was the only spelling that
//      compiled. A tuple could not be a FIELD's or a PROPERTY's type at all.
//   4. `(a, b) := e` -- the spelling the language tour documents -- reached no columnar kernel, and
//      `(a, b) = e` was read as a second declaration of names that already existed.
//
// Every row below executes real emitted IL, and the metadata rows read back the attribute the
// compiler actually wrote.

// ---------------------------------------------------------------- 1. one type, two spellings

// The `ValueTuple<...>` spelling in an annotation, taking a tuple literal.
func WrittenValueTuple(x: string, l: List<int>): int {
    pair: ValueTuple<string, List<int>> = (x, l)
    return pair.Item2.Count
}

// The tuple spelling in an annotation, taking a `ValueTuple.Create`.
func WrittenTuple(x: string, l: List<int>): int {
    let pair: (string, List<int>) = ValueTuple.Create(x, l)
    return pair.Item2.Count
}

// A hand-written `ValueTuple<...>` RETURN is the tuple it spells, names and all.
func ValueTupleReturn(): ValueTuple<int, int> {
    return (3, 9)
}

func TupleReturn(): (int, int) {
    return (3, 9)
}

// ---------------------------------------------------------------- 2. a narrowed nullable tuple

func FindRow(name: string): (Uri: string, Line: int)? {
    if name.Length == 0 {
        return null
    }

    return (name, name.Length)
}

// `.Value` on a value NARROWED out of `T?` -- the type reaching member resolution is the inner tuple.
func LineThroughValue(name: string): int {
    found := FindRow(name)
    if found == null {
        return -1
    }

    return found.Value.Line
}

// The same unwrap written as `must`, which is N#'s own spelling for it.
func LineThroughMust(name: string): int {
    found := FindRow(name)
    return (must found).Line
}

// ---------------------------------------------------------------- 3. names through receivers

// An element read straight out of an INDEXER, which is where the names sit one level inside the
// receiver's own written type.
func FirstItemOfList(rows: List<(Item: string, Count: int)>): string {
    return rows[0].Item
}

func RangeCountOfDictionary(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    return groups["k"].Ranges.Count
}

// The same names reached through a chain that declares nothing of its own.
func RangeCountThroughValues(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    return groups.Values.First().Ranges.Count
}

// And through a foreach over the same collection.
func TotalRangesThroughForeach(groups: Dictionary<string, (Item: string, Ranges: List<int>)>): int {
    total := 0
    for group in groups.Values {
        total = total + group.Ranges.Count
    }

    return total
}

// A tuple-typed FIELD and a tuple-typed PROPERTY -- two declared positions that used to decline the
// whole enclosing type at `parse.struct`.
class RowHolder {
    Pair: (Item: string, Count: int) = ("", 0)
    Bounds: (Min: int, Max: int) => (3, 9)

    constructor(item: string, count: int) {
        Pair = (item, count)
    }
}

func ItemOfField(holder: RowHolder): string {
    return holder.Pair.Item
}

func MaxOfProperty(holder: RowHolder): int {
    return holder.Bounds.Max
}

// ---------------------------------------------------------------- 4. deconstruction

func MakeRow(): (Item: string, Count: int) {
    return ("row", 4)
}

// The parenthesised spelling the language tour documents.
func DeconstructParenthesised(): int {
    (item, count) := MakeRow()
    return count + item.Length
}

// The bare spelling, which is the same statement.
func DeconstructBare(): int {
    item, count := MakeRow()
    return count + item.Length
}

// `=` WRITES TARGETS THAT ALREADY EXIST.
func DeconstructAssign(): int {
    item := ""
    count := 0
    (item, count) = MakeRow()
    return count + item.Length
}

// A discard binds nothing.
func DeconstructDiscard(): int {
    (_, count) := MakeRow()
    return count
}

// A type with its own `Deconstruct(out ...)` -- `KeyValuePair<K, V>` is the one every dictionary walk
// produces, and it is not a tuple.
func DeconstructKeyValuePairs(pairs: Dictionary<string, int>): int {
    total := 0
    for pair in pairs {
        (key, value) := pair
        total = total + value + key.Length
    }

    return total
}

// A type of THIS compilation's own that declares the same method. The rule is the type's own
// declaration, not where it was compiled.
class Measurement {
    Label: string = ""
    Amount: int = 0

    constructor(label: string, amount: int) {
        Label = label
        Amount = amount
    }

    func Deconstruct(out label: string, out amount: int) {
        label = Label
        amount = Amount
    }
}

func DeconstructSourceType(): int {
    measurement := new Measurement("mm", 12)
    (label, amount) := measurement
    return amount + label.Length
}

// ---------------------------------------------------------------- reading the metadata back

class IdentityShapes {
    static func ValueTupleSpelling(): ValueTuple<int, int> {
        return (3, 9)
    }

    static func TupleSpelling(): (int, int) {
        return (3, 9)
    }

    static func NamedField(): int {
        return 0
    }
}

class AttributeShapes {
    Pair: (Item: string, Count: int) = ("", 0)
    Unnamed: (string, int) = ("", 0)
    Bounds: (Min: int, Max: int) => (3, 9)
}

// One element of a `TupleElementNamesAttribute`, `-` for the null slot a positional element occupies,
// `<end>` past the array. The arity is MEASURED because `IList<T>.Count` does not emit here.
func IdentityNameAt(declared: TupleElementNamesAttribute, index: int): string {
    transformed := declared.get_TransformNames()
    try {
        value := transformed[index]
        if value == null {
            return "-"
        }

        return value
    } catch e: ArgumentOutOfRangeException {
        return "<end>"
    }
}

func IdentityNameRowOf(attributes: object[]): string {
    if attributes.Length != 1 {
        return "<none>"
    }

    declared := attributes[0] as TupleElementNamesAttribute
    if declared == null {
        return "<none>"
    }

    row := ""
    index := 0
    while index < 32 {
        element := IdentityNameAt(declared, index)
        if element == "<end>" {
            return row
        }

        if index > 0 {
            row = row + "/"
        }

        row = row + element
        index = index + 1
    }

    return row
}

func IdentityReturnType(name: string): Type {
    found := typeof(IdentityShapes).GetMethod(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return found.ReturnType
}

func ShapeFieldType(name: string): Type {
    found := typeof(AttributeShapes).GetField(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return found.FieldType
}

func FieldNameRow(name: string): string {
    found := typeof(AttributeShapes).GetField(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return IdentityNameRowOf(found.GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

func PropertyNameRow(name: string): string {
    found := typeof(AttributeShapes).GetProperty(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return IdentityNameRowOf(found.GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

// ---------------------------------------------------------------- the contracts

test "a ValueTuple spelling and a tuple spelling are one type" {
    numbers := new List<int>()
    numbers.Add(1)
    assert WrittenValueTuple("a", numbers) == 1
    assert WrittenTuple("a", numbers) == 1

    // The CLR agrees, which is the whole reason the analyzer must: both spellings answer the same
    // constructed `System.ValueTuple`2`.
    valueTupleSpelled := IdentityReturnType("ValueTupleSpelling")
    tupleSpelled := IdentityReturnType("TupleSpelling")
    assert valueTupleSpelled == tupleSpelled
    assert valueTupleSpelled == typeof(ValueTuple<int, int>)

    written := ValueTupleReturn()
    plain := TupleReturn()
    assert written.Item1 == plain.Item1
    assert written.Item2 == plain.Item2
}

test "a narrowed nullable tuple answers Value and must" {
    assert LineThroughValue("abcd") == 4
    assert LineThroughValue("") == -1
    assert LineThroughMust("abcde") == 5
}

test "an element name survives an indexer, a chain and a foreach" {
    rows := new List<(Item: string, Count: int)>()
    rows.Add(("first", 1))
    assert FirstItemOfList(rows) == "first"

    groups := new Dictionary<string, (Item: string, Ranges: List<int>)>()
    ranges := new List<int>()
    ranges.Add(7)
    ranges.Add(9)
    groups["k"] = ("value", ranges)
    assert RangeCountOfDictionary(groups) == 2
    assert RangeCountThroughValues(groups) == 2
    assert TotalRangesThroughForeach(groups) == 2
}

test "a field and a property may be declared with a tuple type" {
    holder := new RowHolder("held", 11)
    assert ItemOfField(holder) == "held"
    assert holder.Pair.Count == 11
    assert MaxOfProperty(holder) == 9
    assert holder.Bounds.Min == 3
}

test "a field's and a property's element names are written to metadata" {
    assert FieldNameRow("Pair") == "Item/Count"
    assert FieldNameRow("Unnamed") == "<none>"
    assert PropertyNameRow("Bounds") == "Min/Max"

    // And the field's CLR type is the bare ValueTuple, which is why the attribute is needed at all.
    assert ShapeFieldType("Pair") == typeof(ValueTuple<string, int>)
}

test "a deconstruction declares with := and assigns with =" {
    assert DeconstructParenthesised() == 7
    assert DeconstructBare() == 7
    assert DeconstructAssign() == 7
    assert DeconstructDiscard() == 4
}

test "a type with a Deconstruct method deconstructs like a tuple" {
    pairs := new Dictionary<string, int>()
    pairs["ab"] = 5
    assert DeconstructKeyValuePairs(pairs) == 7

    // And a type declared here, whose `Deconstruct` lives on its own declaration rather than in
    // metadata.
    assert DeconstructSourceType() == 14
}

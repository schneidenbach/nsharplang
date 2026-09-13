namespace NSharpLang.CensusParseShapes.Tests

import System
import System.Collections.Generic
import System.Reflection
import System.Runtime.CompilerServices


// TUPLE ELEMENT NAMING IS DECIDED PER ELEMENT.
//
// Both tuple parsers used to run in one of two modes chosen by the FIRST element -- all named or all
// positional -- so C#'s ordinary mixed spelling was a syntax error in a literal
// (`(null, last, IsConstructor: true)` reported NL101 "Unexpected token ':' in expression", then
// NL301 "Variable 'IsConstructor' not found" and a delimiter cascade) and, in a tuple TYPE, declined
// the whole enclosing declaration at `parse.function`.
//
// These rows execute the mixed spellings in both positions, at run time and against the CLR metadata
// the compiler actually wrote. The metadata half matters because element names have no CLR identity
// at all: `(string, string, IsConstructor: bool)` IS `ValueTuple<string, string, bool>`, and the
// names live in a `TupleElementNamesAttribute` on the declaring POSITION, with a NULL slot for every
// element the source left positional. A mixed tuple is the only shape that can prove the null slots
// are written in the right places.

// ---------------------------------------------------------------- the declared shapes

// The census probe's own signature, element for element.
func ParsePart(parts: string[]): (string?, string, IsConstructor: bool) {
    last := parts[parts.Length - 1]
    if parts.Length >= 2 {
        return (null, last, IsConstructor: true)
    }

    return (null, last, IsConstructor: false)
}

// The name on the FIRST element and nothing after it -- the other half of the mixed rule.
func LeadingNameOnly(): (Head: int, int, int) {
    return (Head: 1, 2, 3)
}

// A positional element between two named ones.
func NameGap(): (First: int, int, Last: int) {
    return (First: 1, 2, Last: 3)
}

// Names on the literal that the declared type does not have: they are labels on a value, and the
// value's type is the declared one.
func UnnamedTargetNamedLiteral(): (int, int) {
    return (Left: 1, Right: 2)
}

// A mixed tuple nested inside a named one: the attribute's array is a PRE-ORDER walk, so the outer
// tuple's own slots -- including its nulls -- come before the inner tuple's.
func NestedMixed(): (A: int, (B: int, int)) {
    return (A: 1, (B: 2, 3))
}

// A tuple type as a generic ARGUMENT carries its names through the instantiation.
func NamedTupleRows(): List<(Item: string, Ranges: List<int>)> {
    return new List<(Item: string, Ranges: List<int>)>()
}

// ---------------------------------------------------------------- reading the metadata back

func ShapeMethod(name: string): MethodInfo {
    found := typeof(TupleNamingShapes).GetMethod(name)
    if found == null {
        throw new InvalidOperationException("'" + name + "' was not found.")
    }

    return found
}

// One element of the attribute's array: the declared name, `-` for a slot the source left positional
// (which metadata spells as a null string), and `<end>` once the array is exhausted. The arity is
// therefore MEASURED rather than assumed -- `IList<T>.Count` is not modeled by the columnar backend,
// so the read runs until the indexer throws.
func NameAt(declared: TupleElementNamesAttribute, index: int): string {
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

// The whole attribute as one readable row, or `<none>` when the position carries no attribute at all.
func NameRowOf(attributes: object[]): string {
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
        element := NameAt(declared, index)
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

func ReturnNameRow(name: string): string {
    return NameRowOf(ShapeMethod(name).ReturnParameter.GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

func ParameterNameRow(name: string): string {
    return NameRowOf(ShapeMethod(name).GetParameters()[0].GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

class TupleNamingShapes {
    static func Mixed(): (string, string, IsConstructor: bool) {
        return ("a", "b", IsConstructor: true)
    }

    static func LeadingName(): (Head: int, int, int) {
        return (Head: 1, 2, 3)
    }

    static func Gap(): (First: int, int, Last: int) {
        return (First: 1, 2, Last: 3)
    }

    static func Nested(): (A: int, (B: int, int)) {
        return (A: 1, (B: 2, 3))
    }

    static func Unnamed(): (int, int) {
        return (1, 2)
    }

    static func InGenericArgument(): List<(Item: string, Count: int)> {
        return new List<(Item: string, Count: int)>()
    }

    static func MixedParameter(row: (string, Count: int)): int {
        return row.Count
    }
}

// ---------------------------------------------------------------- the contracts

test "a tuple literal mixes named and positional elements" {
    two := new string[](2)
    two[0] = "System"
    two[1] = "Ctor"
    mixed := ParsePart(two)
    assert mixed.Item1 == null
    assert mixed.Item2 == "Ctor"
    assert mixed.IsConstructor

    one := new string[](1)
    one[0] = "Only"
    single := ParsePart(one)
    assert single.Item1 == null
    assert single.Item2 == "Only"
    assert !single.IsConstructor

    // The name reaches the element wherever it sits in the literal.
    leading := LeadingNameOnly()
    assert leading.Head == 1
    assert leading.Item2 == 2
    assert leading.Item3 == 3

    gap := NameGap()
    assert gap.First == 1
    assert gap.Item2 == 2
    assert gap.Last == 3

    // A literal's own names are labels; the value's TYPE is the declared one, and the declared one
    // here names nothing.
    labelled := UnnamedTargetNamedLiteral()
    assert labelled.Item1 == 1
    assert labelled.Item2 == 2

    // A nested tuple's own names are metadata on the same declaring position (asserted below); the
    // values read positionally through the outer element.
    nested := NestedMixed()
    assert nested.A == 1
    assert nested.Item2.Item1 == 2
    assert nested.Item2.Item2 == 3
}

test "a null element takes the declared element type, and emits as it" {
    empty := new string[](1)
    empty[0] = "x"
    row := ParsePart(empty)
    assert row.Item1 == null

    // The same target typing in a typed local, which is its own emission path.
    let pair: (string?, string) = (null, "x")
    assert pair.Item1 == null
    assert pair.Item2 == "x"

    // And through a nullable annotation the declared type carries but the literal does not.
    let widened: (string?, string, IsConstructor: bool) = ("a", "b", IsConstructor: false)
    assert widened.Item1 == "a"
    assert !widened.IsConstructor
}

test "a tuple type may be written wherever a type may be written" {
    // A bare typed local -- the one declared position that used to admit only a type starting with
    // an identifier, so `pair: (Item: string, ...) = ...` was read as an expression statement.
    let pair: (Item: string, Ranges: List<int>) = ("a", new List<int>())
    pair.Ranges.Add(7)
    assert pair.Item == "a"
    assert pair.Ranges.Count == 1

    // The `let` spelling of the same thing.
    let counted: (Item: string, Count: int) = ("b", 2)
    assert counted.Item == "b"
    assert counted.Count == 2

    // A generic ARGUMENT, at every position a type may be written. The names ride on the declaring
    // member as metadata (asserted below), and BOTH spellings of the element read emit: the positional
    // `ItemN` and the name the type argument declared. (The name half used to decline with NL103 at
    // the emit boundary even though the analyser had resolved it; `ValueTupleIdentity.tests.nl` is the
    // file that owns the whole receiver surface.)
    rows: List<(Item: string, Count: int)> = new List<(Item: string, Count: int)>()
    rows.Add(("c", 3))
    assert rows[0].Item1 == "c"
    assert rows[0].Item2 == 3
    assert rows[0].Item == "c"
    assert rows[0].Count == 3

    // A dictionary VALUE, read back through the indexer -- the census probe's own shape, where the
    // names are written once in the type argument.
    groups := new Dictionary<string, (Item: string, Ranges: List<int>)>()
    groups["k"] = ("d", new List<int>())
    assert groups["k"].Item1 == "d"
    assert groups["k"].Item == "d"
}

test "TupleElementNamesAttribute spells a positional element as a null slot" {
    // Mixed: two nulls and then the name. Without the per-element rule this signature did not
    // compile at all.
    assert ReturnNameRow("Mixed") == "-/-/IsConstructor"
    assert ReturnNameRow("LeadingName") == "Head/-/-"
    assert ReturnNameRow("Gap") == "First/-/Last"

    // The pre-order walk: the OUTER tuple's own two slots first -- the second of which is the
    // unnamed nested tuple -- and only then the nested tuple's own two.
    assert ReturnNameRow("Nested") == "A/-/B/-"

    // Nothing named anywhere means no attribute at all, which is what C# writes too.
    assert ReturnNameRow("Unnamed") == "<none>"

    // A generic argument's names ride on the declaring position exactly like a bare tuple's.
    assert ReturnNameRow("InGenericArgument") == "Item/Count"

    // A parameter position carries its own attribute.
    assert ParameterNameRow("MixedParameter") == "-/Count"
    assert TupleNamingShapes.MixedParameter(("a", 3)) == 3
}

test "a mixed tuple IS its ValueTuple, names and all" {
    assert ShapeMethod("Mixed").ReturnType == typeof(ValueTuple<string, string, bool>)
    assert ShapeMethod("Gap").ReturnType == typeof(ValueTuple<int, int, int>)
    assert ShapeMethod("InGenericArgument").ReturnType == typeof(List<ValueTuple<string, int>>)
}

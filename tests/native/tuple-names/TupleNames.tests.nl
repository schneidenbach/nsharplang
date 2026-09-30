namespace NSharpLang.TupleNames.Tests

import System
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.Runtime


// NAMED TUPLE ELEMENT NAMES ACROSS THE ASSEMBLY BOUNDARY, IN BOTH DIRECTIONS.
//
// A named tuple has no CLR identity of its own. `(int Min, int Max)` IS `System.ValueTuple<int, int>`
// in every signature, and the element names live in a
// `System.Runtime.CompilerServices.TupleElementNamesAttribute(string[])` attached to the POSITION --
// the return parameter, a parameter, a field, a property. That attribute is the entire cross-language
// contract: without WRITING it, a C# consumer of an N# library sees a bare `ValueTuple` with only
// `Item1`/`Item2`; without READING it, an N# consumer of a C# library sees the same.
//
// This file executes both halves against real metadata:
//
//   * WRITING -- every row below reads the attribute the compiler actually emitted for a shape
//     declared in `TupleNames.nl`, out of this assembly's own metadata, and compares it to what the
//     C# compiler writes for the same written type. The expected rows were measured by compiling the
//     same shapes with `csc` and reading `MethodInfo.ReturnParameter.GetCustomAttributesData()`.
//
//   * READING -- the rows at the bottom call the REAL `NSharpLang.Runtime.SimdReductions`, a C#
//     assembly this project references, and use its declared element names (`.Min`, `.Max`,
//     `.Count`, `.LastPrevious`). Before this contract those spellings were
//     `NL303 Member 'Min' not found on type 'ValueTuple<int, int>'`.
//
// THE ATTRIBUTE'S ARRAY IS NOT ONE NAME PER ELEMENT. It is a pre-order walk of the WRITTEN type with
// each tuple's own names first, so `(int A, (int B, int C) D)` is `A, D, B, C` -- not `A, B, C, D` --
// and an unnamed nested tuple still occupies its elements' slots as nulls. Every nested row here
// exists to hold that order.
//
// THE ARITY IS MEASURED, NOT ASSUMED. `TupleElementNamesAttribute.TransformNames` is an `IList<T>`,
// whose `Count` the columnar backend does not model today, so `NameAt` reads until the indexer
// throws. That makes the row LENGTH part of every assertion rather than something the reader has to
// take on trust: a row of "Min/Max" proves the attribute carries exactly two strings.

// ---------------------------------------------------------------------- reading one attribute
func TupleNamesMethodOf(owner: Type, name: string): MethodInfo {
    found := owner.GetMethod(name)
    if found == null {
        throw new InvalidOperationException("'" + owner.FullName + "." + name + "' was not found.")
    }

    return found
}

// One element of the attribute's array: the declared name, `-` for a slot the source left unnamed,
// and `<end>` once the array is exhausted.
func TupleNameAt(declared: TupleElementNamesAttribute, index: int): string {
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

// The whole attribute as one readable row, or `<none>` when the position carries no attribute at all
// -- which is what C# emits, and what N# must emit, for a tuple with nothing named.
func TupleNameRowOf(attributes: object[]): string {
    if attributes.Length != 1 {
        return "<none>"
    }

    declared := attributes[0] as TupleElementNamesAttribute
    if declared == null {
        return "<none>"
    }

    row := ""
    index := 0
    while index < 64 {
        element := TupleNameAt(declared, index)
        if element == "<end>" {
            return row
        }

        if index > 0 {
            row = row + "/"
        }

        row = row + element
        index += 1
    }

    return row
}

func ReturnTupleNames(owner: Type, name: string): string {
    return TupleNameRowOf(TupleNamesMethodOf(owner, name).get_ReturnParameter().GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

func ParameterTupleNames(owner: Type, name: string, ordinal: int): string {
    return TupleNameRowOf(TupleNamesMethodOf(owner, name).GetParameters()[ordinal].GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

func ConstructorParameterTupleNames(owner: Type, ordinal: int): string {
    constructors := owner.GetConstructors()
    if constructors.Length != 1 {
        throw new InvalidOperationException("'" + owner.FullName + "' does not declare exactly one constructor.")
    }

    return TupleNameRowOf(constructors[0].GetParameters()[ordinal].GetCustomAttributes(typeof(TupleElementNamesAttribute), false))
}

// The type the compiler puts a file's free functions on.
func FreeFunctionOwner(): Type {
    for candidate in typeof(TupleShapes).get_Assembly().GetTypes() {
        if candidate.GetMethod("FreeSimple") != null {
            return candidate
        }
    }

    throw new InvalidOperationException("The free-function owner type was not found in this assembly.")
}

// ---------------------------------------------------------------------- WRITING: emitted metadata

test "a named tuple return carries its element names, and an unnamed one carries no attribute" {
    shapes := typeof(TupleShapes)
    assert ReturnTupleNames(shapes, "Simple") == "Min/Max"
    assert ReturnTupleNames(shapes, "Unnamed") == "<none>"
    assert TupleNamesMethodOf(shapes, "Simple").get_ReturnType() == typeof(ValueTuple<int, int>)
    assert TupleNamesMethodOf(shapes, "Unnamed").get_ReturnType() == typeof(ValueTuple<int, int>)
}

test "a nested tuple's names follow the outer tuple's, in the flattened order C# writes" {
    shapes := typeof(TupleShapes)
    assert ReturnTupleNames(shapes, "Nested") == "A/D/B/C"
    assert ReturnTupleNames(shapes, "NestedFirst") == "D/A/B/C"
}

test "an unnamed nested tuple still occupies one slot per element" {
    assert ReturnTupleNames(typeof(TupleShapes), "InnerUnnamed") == "X/Y/-/-"
}

test "a tuple inside a generic argument carries its names too" {
    shapes := typeof(TupleShapes)
    assert ReturnTupleNames(shapes, "Generic") == "Min/Max"
    assert ReturnTupleNames(shapes, "GenericInsideTuple") == "M/N/L1/L2"
}

test "a parameter of named tuple type carries the attribute on the parameter, not the return" {
    shapes := typeof(TupleShapes)
    assert ParameterTupleNames(shapes, "Parameterised", 0) == "P/Q"
    assert ReturnTupleNames(shapes, "Parameterised") == "<none>"
    assert ParameterTupleNames(shapes, "InstanceParameterised", 0) == "P/Q"
}

test "an instance method's named tuple return carries its names" {
    assert ReturnTupleNames(typeof(TupleShapes), "Instance") == "Left/Right"
}

test "a constructor parameter is a signature position like any other" {
    assert ConstructorParameterTupleNames(typeof(PairHolder), 0) == "P/Q"
    assert new PairHolder((4, 5)).Sum == 9
}

test "a free function's return and parameters carry their names" {
    free := FreeFunctionOwner()
    assert ReturnTupleNames(free, "FreeSimple") == "Min/Max"
    assert ReturnTupleNames(free, "FreeUnnamed") == "<none>"
    assert ParameterTupleNames(free, "FreeParameterised", 0) == "P/Q"
}

// THE ROW THAT MAKES THIS A CROSS-LANGUAGE CLAIM. Everything above states that N# emits SOME
// attribute; this states that it emits the SAME attribute a C# compiler emits for the same written
// type, read off a real C# assembly rather than off a written-down expectation. If the emitted blob
// ever drifts -- a different name order, an extra slot, a missing null -- these two rows stop being
// equal even though each side is read the same way.
test "an N# named tuple return presents exactly what the C# original presents" {
    original := typeof(SimdReductions)
    assert ReturnTupleNames(original, "MinMaxInt32") == "Min/Max"
    assert ReturnTupleNames(original, "CountTransitionsInt32") == "Count/LastPrevious"

    // `TupleShapes.Simple` is declared `(Min: int, Max: int)` -- the same written type as the C#
    // original's return -- so the two positions must present the same names AND the same CLR type.
    assert ReturnTupleNames(typeof(TupleShapes), "Simple") == ReturnTupleNames(original, "MinMaxInt32")
    assert TupleNamesMethodOf(typeof(TupleShapes), "Simple").get_ReturnType() == TupleNamesMethodOf(original, "MinMaxInt32").get_ReturnType()
    assert typeof(TupleShapes).get_Assembly() != original.get_Assembly()
}

// ---------------------------------------------------------------------- READING: a C# assembly

test "a C# assembly's declared element names resolve on the N# side" {
    values: int[] = [5, -3, 9, 2]
    r := SimdReductions.MinMaxInt32(values, 0, values.Length, 2147483647, -2147483648)
    assert r.Min == -3
    assert r.Max == 9

    t := SimdReductions.CountTransitionsInt32(values, 0, values.Length, 5)
    assert t.Count == 3
    assert t.LastPrevious == 2
}

test "the declared names read the same slots the positional members read" {
    values: int[] = [5, -3, 9, 2]
    r := SimdReductions.MinMaxInt32(values, 0, values.Length, 2147483647, -2147483648)
    assert r.Min == r.Item1
    assert r.Max == r.Item2

    t := SimdReductions.CountTransitionsInt32(values, 0, values.Length, 5)
    assert t.Count == t.Item1
    assert t.LastPrevious == t.Item2
}

test "deconstruction of a C# named tuple return still works" {
    values: int[] = [5, -3, 9, 2]
    low, high := SimdReductions.MinMaxInt32(values, 0, values.Length, 2147483647, -2147483648)
    assert low == -3
    assert high == 9
}

// Names are METADATA, not identity: C# lets a named tuple flow into a positional one and vice versa,
// and treats a name mismatch as at most a warning. N# keeps that rule -- these assignments are legal
// and the values survive them unchanged.
test "element names are not part of tuple identity" {
    values: int[] = [5, -3, 9, 2]
    r := SimdReductions.MinMaxInt32(values, 0, values.Length, 2147483647, -2147483648)

    let positional: (int, int) = r
    assert positional.Item1 == -3
    assert positional.Item2 == 9

    let renamed: (Low: int, High: int) = r
    assert renamed.Low == -3
    assert renamed.High == 9
}

// ---------------------------------------------------------------------- READING: an N# assembly's own names

// A named tuple RETURNED BY A METHOD ON A TYPE and one returned by a FREE FUNCTION must behave the
// same at the call site; both were emit-time declines at different points in this arc.
test "a named tuple returned by an N# method or free function carries its names to the call site" {
    fromMethod := TupleShapes.Simple()
    assert fromMethod.Min == 3
    assert fromMethod.Max == 9
    assert fromMethod.Min == fromMethod.Item1

    fromFree := FreeSimple()
    assert fromFree.Min == 3
    assert fromFree.Max == 9

    assert TupleShapes.Parameterised((4, 5)) == 9
    assert FreeParameterised((9, 4)) == 5
}

test "a nested named tuple's outer names resolve at the call site" {
    nested := TupleShapes.Nested()
    assert nested.A == 1
    assert nested.D.Item1 == 2
    assert nested.D.Item2 == 3
}

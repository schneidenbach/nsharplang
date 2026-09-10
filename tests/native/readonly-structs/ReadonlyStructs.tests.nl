namespace NSharpLang.ReadonlyStructs.Tests

import System
import System.Collections.Generic
import System.Reflection

// READONLY STRUCTS, PROVED OVER REAL EMITTED IL.
//
// `readonly struct S` is a promise about METADATA as much as about source: the emitted type carries
// `System.Runtime.CompilerServices.IsReadOnlyAttribute`, and every consumer that reads it — N#, C#,
// F#, and the CLR's own rules for `in` parameters — stops making the defensive copies that would
// otherwise absorb a write. These tests therefore assert BOTH halves: that the values behave, and
// that the metadata says what the behaviour depends on.
class ReadonlyStructFacts {

    // `IsReadOnlyAttribute` lives in the compiler-services namespace of the referenced runtime, so it
    // is identified by NAME rather than by a `typeof` the test project would have to reference.
    static func CarriesIsReadOnly(candidate: Type): bool {
        for attribute in candidate.GetCustomAttributes(false) {
            if attribute.GetType().Name == "IsReadOnlyAttribute" {
                return true
            }
        }

        return false
    }

    static func InstanceFieldsAreInitOnly(candidate: Type): bool {
        for field in candidate.GetRuntimeFields() {
            if !field.get_IsStatic() && !field.get_IsInitOnly() {
                return false
            }
        }

        return true
    }
}

// --- The baseline probe: the shape that did not parse before this arc ------------------------------

test "the baseline readonly struct constructs and reads its field" {
    point := new Point(42)
    assert point.X == 42
}

test "a generic readonly struct round-trips a value type and a reference type" {
    assert new ReadonlyBox<int>(7).Value == 7
    assert new ReadonlyBox<string>("x").Value == "x"
}

// --- Metadata: IsReadOnlyAttribute is placed on the type, and only on readonly ones ----------------

test "a readonly struct carries IsReadOnlyAttribute" {
    assert ReadonlyStructFacts.CarriesIsReadOnly(typeof(Point)), "Point is declared 'readonly struct'"
    assert ReadonlyStructFacts.CarriesIsReadOnly(typeof(Vector)), "Vector is declared 'readonly struct'"
    assert ReadonlyStructFacts.CarriesIsReadOnly(typeof(Captured)), "Captured is declared 'readonly struct'"
    assert ReadonlyStructFacts.CarriesIsReadOnly(typeof(WithStatic)), "WithStatic is declared 'readonly struct'"
}

test "a plain struct with a readonly field does NOT carry IsReadOnlyAttribute" {
    // `struct Mutable { readonly X: int; Y: int }` is a MUTABLE struct that happens to hold one
    // immutable field. Marking it readonly would promise callers a copy elision that is not sound.
    assert !ReadonlyStructFacts.CarriesIsReadOnly(typeof(Mutable))
}

test "the other two readonly spellings carry the attribute too" {
    assert ReadonlyStructFacts.CarriesIsReadOnly(typeof(Window)), "'readonly ref struct'"
    assert ReadonlyStructFacts.CarriesIsReadOnly(typeof(Pair)), "'readonly record struct'"
}

test "a readonly ref struct is still byref-like" {
    assert typeof(Window).get_IsByRefLike()
}

// --- Metadata: every instance field is initonly, and layout is unchanged ---------------------------

test "the declared field of a readonly struct is emitted initonly" {
    field := typeof(Point).GetField("X")
    assert field != null, "Point.X must be present"
    if field != null {
        assert field.get_IsInitOnly()
    }
}

test "a mutable struct's fields keep their own attributes" {
    readonlyField := typeof(Mutable).GetField("X")
    mutableField := typeof(Mutable).GetField("Y")
    assert readonlyField != null, "Mutable.X must be present"
    assert mutableField != null, "Mutable.Y must be present"
    if readonlyField != null {
        assert readonlyField.get_IsInitOnly(), "a readonly field is initonly even in a mutable struct"
    }
    if mutableField != null {
        assert !mutableField.get_IsInitOnly(), "a mutable field is not initonly"
    }
}

test "a primary constructor's captured parameters are initonly in a readonly struct" {
    // The source never wrote `readonly` on these: the compiler synthesized the fields from the
    // header. The promise covers them, exactly as it does in C#.
    assert ReadonlyStructFacts.InstanceFieldsAreInitOnly(typeof(Captured))
    assert new Captured(2, 3).Total() == 5
}

test "a static field in a readonly struct is not constrained by the rule" {
    staticField := typeof(WithStatic).GetField("Counter")
    assert staticField != null, "WithStatic.Counter must be present"
    if staticField != null {
        assert staticField.get_IsStatic()
        assert !staticField.get_IsInitOnly(), "a mutable static field stays mutable"
    }

    assert new WithStatic(4).Tag == 4
}

// --- Metadata: the generic definition keeps its parameters, and T stays the field's type -----------

test "a generic readonly struct keeps its generic definition and its type-parameter field" {
    closed := typeof(ReadonlyBox<int>)
    definition := closed.GetGenericTypeDefinition()
    assert definition.get_IsGenericTypeDefinition()
    assert ReadonlyStructFacts.CarriesIsReadOnly(closed), "the closed type carries the attribute"
    assert ReadonlyStructFacts.CarriesIsReadOnly(definition), "so does the open definition"

    openField := definition.GetField("Value")
    assert openField != null, "ReadonlyBox<>.Value must be present"
    if openField != null {
        assert openField.get_FieldType().get_IsGenericParameter(), "the open field's type IS the parameter"
        assert openField.get_IsInitOnly()
    }

    closedField := typeof(ReadonlyBox<int>).GetField("Value")
    assert closedField != null, "ReadonlyBox<int>.Value must be present"
    if closedField != null {
        assert closedField.get_IsInitOnly()
    }
}

// --- Behaviour: instance methods, interfaces, equality, and use as a component --------------------

test "an instance method on a readonly struct computes over its own fields" {
    v := new Vector(3, 4)
    assert v.Magnitude() == 25
    assert v.Scaled(2).Magnitude() == 100
}

test "a readonly struct reached through an interface reference dispatches to its own method" {
    // Boxing is the one place a value type's method reaches it through a reference; the readonly
    // promise must not change which method runs.
    shape: HasMagnitude = new Vector(1, 2)
    assert shape.Magnitude() == 5
}

test "a readonly struct's Equals and GetHashCode answer over its fields" {
    a := new Vector(3, 4)
    b := new Vector(3, 4)
    c := new Vector(4, 3)
    assert a.Equals(b)
    assert !a.Equals(c)
    assert a.GetHashCode() == b.GetHashCode()
    assert a.ToString() == "(3,4)"
}

test "a readonly struct works as an array element, a generic argument and a dictionary value" {
    vectors := new Vector[3]
    vectors[0] = new Vector(1, 0)
    vectors[1] = new Vector(0, 2)
    vectors[2] = new Vector(3, 4)
    assert vectors[2].Magnitude() == 25

    boxed := new ReadonlyBox<Vector>(new Vector(3, 4))
    assert boxed.Value.Magnitude() == 25

    list := new List<Vector>()
    list.Add(new Vector(5, 0))
    assert list[0].Magnitude() == 25

    map := new Dictionary<string, Vector>()
    map["a"] = new Vector(0, 6)
    assert map["a"].Magnitude() == 36
}

test "a nested readonly struct is declared, emitted and executed like a top-level one" {
    assert Container.MakeInner(9) == 9
    inner := typeof(Container).GetNestedType("Inner")
    assert inner != null, "Container.Inner must be present"
    if inner != null {
        assert ReadonlyStructFacts.CarriesIsReadOnly(inner)
    }
}

test "a readonly ref struct executes its instance method" {
    window := new Window(4, 6)
    assert window.End() == 10
}

test "a readonly record struct holds and reads its fields" {
    pair := new Pair(2, 5)
    assert pair.Left == 2
    assert pair.Right == 5
}

// --- The acceptance shape: the Result payload, as a generic readonly struct ------------------------

test "the Result payload shape reports its state through instance predicates" {
    ok := new ResultShape<int, string>(11, "", 1)
    err := new ResultShape<int, string>(0, "boom", 2)
    assert ok.IsOk
    assert !ok.IsError
    assert err.IsError
    assert !err.IsOk
}

test "the Result payload shape answers its Try-shaped out accessors" {
    ok := new ResultShape<int, string>(11, "", 1)
    err := new ResultShape<int, string>(0, "boom", 2)

    value := 0
    assert ok.TryGetValue(out value)
    assert value == 11

    failed := 0
    assert !err.TryGetValue(out failed)

    reason := ""
    assert err.TryGetError(out reason)
    assert reason == "boom"
}

test "the Result payload shape is a readonly struct with initonly fields" {
    closed := typeof(ResultShape<int, string>)
    assert ReadonlyStructFacts.CarriesIsReadOnly(closed)
    assert ReadonlyStructFacts.InstanceFieldsAreInitOnly(closed)
    assert closed.GetGenericTypeDefinition().get_IsGenericTypeDefinition()

    a := new ResultShape<int, string>(1, "", 1)
    b := new ResultShape<int, string>(2, "", 1)
    assert a.Equals(b)
    assert a.GetHashCode() == b.GetHashCode()
}

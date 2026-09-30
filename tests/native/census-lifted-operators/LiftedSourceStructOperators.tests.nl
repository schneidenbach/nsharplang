namespace NSharpLang.CensusLiftedOperators.Tests

import System
import System.Reflection

func CentsOf(value: int): Cents {
    return new Cents { Value: value }
}

func LiftedSourceStructMethod(name: string): MethodInfo {
    method := typeof(LiftedSourceStructSignatures).GetMethod(name)
    if method == null {
        throw new InvalidOperationException(name + " was not found on the signature carrier.")
    }

    return method
}

func LiftedSourceStructElement(lifted: Type): Type {
    element := Nullable.GetUnderlyingType(lifted)
    if element == null {
        throw new InvalidOperationException(lifted.Name + " is not a Nullable<T>.")
    }

    return element
}

test "a source struct's own arithmetic operators lift, absent when either side is" {
    sum := AddCents(CentsOf(2), CentsOf(5))
    assert sum != null
    assert sum.Value.Value == 7
    assert AddCents(CentsOf(2), null) == null
    assert AddCents(null, CentsOf(5)) == null
    assert AddCents(null, null) == null

    difference := SubtractCents(CentsOf(9), CentsOf(4))
    assert difference != null
    assert difference.Value.Value == 5
    assert SubtractCents(null, CentsOf(4)) == null

    // A PLAIN operand joins the lifted form, exactly as it does for `int?` and `decimal?`.
    withValue := AddCentsValue(CentsOf(2), CentsOf(3))
    assert withValue != null
    assert withValue.Value.Value == 5
    assert AddCentsValue(null, CentsOf(3)) == null
}

test "a source struct's unary operator lifts: absent in, absent out" {
    negated := NegateCents(CentsOf(4))
    assert negated != null
    assert negated.Value.Value == -4
    assert NegateCents(null) == null
}

test "an ordering comparison over a lifted source struct is a plain bool, false when either side is absent" {
    assert CentsAreLess(CentsOf(1), CentsOf(2))
    assert !CentsAreLess(CentsOf(2), CentsOf(1))

    // BOTH directions are false for an absent operand, which is what makes the answer NOT the
    // negation of the other comparison.
    assert !CentsAreLess(null, CentsOf(2))
    assert !CentsAreLess(CentsOf(1), null)
    assert !CentsAreLess(null, null)
    assert !CentsAreMore(null, CentsOf(2))
    assert !CentsAreMore(CentsOf(2), null)
}

test "equality over a lifted source struct keeps the two-absent-values-are-equal rule" {
    assert CentsAreEqual(CentsOf(3), CentsOf(3))
    assert !CentsAreEqual(CentsOf(3), CentsOf(4))
    assert CentsAreEqual(null, null)
    assert !CentsAreEqual(null, CentsOf(3))
    assert !CentsAreEqual(CentsOf(3), null)

    assert CentsDiffer(CentsOf(3), CentsOf(4))
    assert !CentsDiffer(null, null)
    assert CentsDiffer(null, CentsOf(3))
}

test "the emitted signature of a lifted source-struct operator is the lifted struct on every position" {
    sum := LiftedSourceStructMethod("Sum")
    assert LiftedSourceStructElement(sum.ReturnType).Name == "Cents"
    assert LiftedSourceStructElement(sum.GetParameters()[0].ParameterType).Name == "Cents"
    assert LiftedSourceStructElement(sum.GetParameters()[1].ParameterType).Name == "Cents"

    // An ordering comparison is NOT lifted — its result is a plain `bool`.
    compare := LiftedSourceStructMethod("Compare")
    assert compare.ReturnType == typeof(bool)
}

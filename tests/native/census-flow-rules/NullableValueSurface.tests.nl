namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Reflection

func NullableSurfaceMoney(amount: int): Money {
    return new Money { Amount: amount }
}

// `Nullable.GetUnderlyingType` answers `Type?`, so every read of the element is guarded once here
// rather than at each of the dozen call sites below.
func NullableSurfaceElement(lifted: Type): Type {
    element := Nullable.GetUnderlyingType(lifted)
    if element == null {
        throw new InvalidOperationException(lifted.Name + " is not a Nullable<T>.")
    }

    return element
}

func NullableSurfaceMethod(name: string): MethodInfo {
    owner := typeof(NullableSurfaceSignatures)
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException(name + " was not found on the signature carrier.")
    }

    return method
}

test "`Nullable<T>`'s own surface answers for a struct THIS COMPILATION declares" {
    // Every one of these reported NL303 "Member 'GetValueOrDefault' not found on type 'Money'"
    // before the surface was read off the `Nullable<>` DEFINITION rather than off a closed
    // construction the CLR does not have for a type still being emitted.
    assert MoneyPresence(NullableSurfaceMoney(4))
    assert !MoneyPresence(null)

    assert MoneyAmountOrZero(NullableSurfaceMoney(4)) == 4
    assert MoneyAmountOrZero(null) == 0

    assert MoneyAmountOrFallback(NullableSurfaceMoney(4), NullableSurfaceMoney(9)) == 4
    assert MoneyAmountOrFallback(null, NullableSurfaceMoney(9)) == 9

    assert MoneyAmountThroughValue(NullableSurfaceMoney(7)) == 7
    assert MoneyAmountThroughValue(null) == -1
}

test "`Nullable<T>`'s own surface answers for an enum THIS COMPILATION declares" {
    assert GradePresence(Grade.High)
    assert !GradePresence(null)

    assert GradeOrDefault(Grade.High) == Grade.High

    // An absent enum answers the enum's DEFAULT, which is the zero value — and `Grade` declares no
    // zero member, so it is a `Grade` that is neither `Low` nor `High`.
    assert GradeOrDefault(null) != Grade.Low
    assert GradeOrDefault(null) != Grade.High

    assert GradeOrFallback(Grade.Low, Grade.High) == Grade.Low
    assert GradeOrFallback(null, Grade.High) == Grade.High
}

test "the surface answers for an external struct the old liftable list did not carry" {
    // `DateTime?` and `Guid?` declined at every declared position with NL103 while `TimeSpan?`
    // beside them emitted.
    assert MomentYearOrZero(new DateTime(2031, 2, 3)) == 2031
    assert MomentYearOrZero(null) == 1
    assert MomentPresence(new DateTime(2031, 2, 3))
    assert !MomentPresence(null)

    assert IdIsEmpty(null)
    assert !IdIsEmpty(Guid.NewGuid())
}

test "a `?`-lifted source struct holds every declared position" {
    assert WrapMoney(NullableSurfaceMoney(3)) != null

    held := new Wallet(NullableSurfaceMoney(11))
    assert held.HeldAmount() == 11
    assert new Wallet(null).HeldAmount() == 0

    assert UnwrapLocal(6) == 6
    assert AbsentLocal() == 0
    assert MomentLocalYear() == 2031
}

test "the emitted metadata carries a real `Nullable<T>` for every element" {
    wrapStruct := NullableSurfaceMethod("WrapStruct")
    assert NullableSurfaceElement(wrapStruct.ReturnType).Name == "Money"
    assert wrapStruct.GetParameters()[0].ParameterType.Name == "Money"

    assert NullableSurfaceElement(NullableSurfaceMethod("WrapMoment").ReturnType) == typeof(DateTime)
    assert NullableSurfaceElement(NullableSurfaceMethod("WrapId").ReturnType) == typeof(Guid)

    grade := NullableSurfaceElement(NullableSurfaceMethod("WrapGrade").ReturnType)
    assert grade.Name == "Grade"
    assert grade.IsEnum

    // The lifted operator's own signature: both parameters and the result are the lifted struct.
    sumMoney := NullableSurfaceMethod("SumMoney")
    assert NullableSurfaceElement(sumMoney.ReturnType).Name == "Money"
    assert NullableSurfaceElement(sumMoney.GetParameters()[0].ParameterType).Name == "Money"
    assert NullableSurfaceElement(sumMoney.GetParameters()[1].ParameterType).Name == "Money"

    // A `?`-lifted source struct reaches a FIELD too.
    heldField := typeof(Wallet).GetField("Held", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    if heldField == null {
        throw new InvalidOperationException("Wallet.Held was not found.")
    }

    assert NullableSurfaceElement(heldField.FieldType).Name == "Money"
}

// ── which of the two types a name binds on, when both declare it ────────────────────────────────

test "a name `Nullable<T>` declares binds on the NULLABLE, and is null-safe there" {
    // `Nullable<T>.ToString()` answers "" for an absent value and never throws — which is exactly
    // why binding `int.ToString` here and reporting NL905 was wrong.
    assert TextOfAbsentNumber(12) == "12"
    assert TextOfAbsentNumber(null) == ""

    assert TextOfNarrowedNumber(12) == "12"
    assert TextOfNarrowedNumber(null) == "<absent>"

    // The same surface over a struct THIS COMPILATION declares.
    assert TextOfAbsentMoney(null) == ""
}

test "`GetHashCode` and `Equals` are the nullable's too, and answer for the absent value" {
    assert SameHash(4, 4)
    assert !SameHash(4, 5)

    // `Nullable<T>.GetHashCode()` is 0 for an absent value rather than a throw — which is also
    // `(0).GetHashCode()`, so the absent hash collides with zero's exactly as it does in C#.
    assert SameHash(null, null)
    assert SameHash(null, 0)

    // `Nullable<T>.Equals(object)` boxes: an absent nullable equals null and nothing else.
    boxed: object = 4
    assert MatchesBoxed(4, boxed)
    assert !MatchesBoxed(5, boxed)
    assert !MatchesBoxed(null, boxed)
}

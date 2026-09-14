namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Collections.Generic

func LiftedNumbers(): List<int> {
    numbers := new List<int>()
    numbers.Add(4)
    numbers.Add(9)
    return numbers
}

func LiftedWeights(): List<Weight> {
    weights := new List<Weight>()
    weights.Add(new Weight { Grams: 120 })
    weights.Add(new Weight { Grams: 340 })
    return weights
}

test "a `where T : struct` generic declares its `T?` return as a real Nullable<T>" {
    // The metadata half: an erased `T` would answer `!!T` here, and `Nullable.GetUnderlyingType`
    // would have nothing to find.
    declaration := typeof(LiftedGenerics).GetMethod("FirstOrNone")
    assert declaration != null

    returnType := (must declaration).ReturnType
    assert returnType.IsGenericType
    assert returnType.GetGenericTypeDefinition() == typeof(Nullable<int>).GetGenericTypeDefinition()

    // The argument is the method's OWN type parameter, still open in the definition.
    element := returnType.GetGenericArguments()[0]
    assert element.IsGenericParameter
    assert element.Name == "T"
}

test "an inferred local takes the lifted result of a generic call" {
    assert FirstNumberOrMinusOne(LiftedNumbers()) == 4
    assert FirstNumberOrMinusOne(new List<int>()) == -1
}

test "a generic call reading a lifted result is a legal condition operand on its own" {
    assert HasFirstNumber(LiftedNumbers())
    assert !HasFirstNumber(new List<int>())
}

test "the lifted result flows out of a lifted return position unchanged" {
    present := FirstNumberLifted(LiftedNumbers())
    assert present != null
    assert present.Value == 4

    assert FirstNumberLifted(new List<int>()) == null
}

test "Nullable<T>'s own surface answers on the inferred local" {
    assert FirstNumberOrDefault(LiftedNumbers()) == 4

    // The absent case is the one an erased `T` could not express: it is `default(int)` either way,
    // so the PRESENT case above is what proves the lift, and this proves the absent one is reached.
    assert FirstNumberOrDefault(new List<int>()) == 0
}

test "the same lift closes over a struct this compilation declares" {
    assert FirstWeightGrams(LiftedWeights()) == 120
    assert FirstWeightGrams(new List<Weight>()) == -1

    assert PairedWeightGrams(LiftedWeights(), 2) == 120
    assert PairedWeightGrams(LiftedWeights(), 5) == -1
}

test "an external generic's lambda-taking instance member binds over a source element" {
    weights := LiftedWeights()

    assert HeaviestUnder(weights, 200) == 120
    assert CountOver(weights, 200) == 1
    assert IndexOfFirstOver(weights, 200) == 1
    assert IndexOfFirstOver(weights, 900) == -1
    assert AnyOver(weights, 200)
    assert !AnyOver(weights, 900)
}

test "`Nullable<T>`'s own surface answers inside the declaration that spells `T?`" {
    present: int? = 5
    absent: int? = null

    assert PresenceOf(present)
    assert !PresenceOf(absent)

    assert ValueOrDefaultOf(present) == 5
    assert ValueOrDefaultOf(absent) == 0

    assert ValueOrFallbackOf(present, 9) == 5
    assert ValueOrFallbackOf(absent, 9) == 9

    assert GuardedValueOf(present, 9) == 5
    assert GuardedValueOf(absent, 9) == 9

    // The same over a struct THIS COMPILATION declares, so the rule is about the `where` clause and
    // not about `int`.
    heavy: Weight? = new Weight { Grams: 51 }
    none: Weight? = null
    assert PresenceOf(heavy)
    assert !PresenceOf(none)
    assert ValueOrDefaultOf(heavy).Grams == 51
    assert ValueOrDefaultOf(none).Grams == 0
}

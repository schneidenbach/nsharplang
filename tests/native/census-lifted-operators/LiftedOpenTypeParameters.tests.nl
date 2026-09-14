namespace NSharpLang.CensusLiftedOperators.Tests

import System
import System.Reflection

test "lifted equality over an open struct parameter decides every presence pair" {
    one: int? = 1
    two: int? = 2
    absent: int? = null
    assert Same(one, one)
    assert !Same(one, two)
    assert Same(absent, absent)
    assert !Same(one, absent)
    assert !Same(absent, one)
    assert Different(one, two)
    assert Different(one, absent)
    assert !Different(absent, absent)
}

test "the same lifted rule answers for a wider element" {
    one: long? = 1
    other: long? = 2
    absent: long? = null
    assert Same(one, one)
    assert !Same(one, other)
    assert Same(absent, absent)
    assert !Same(other, absent)
}

test "unlifted equality over an open parameter is value equality" {
    assert SameValue(3, 3)
    assert !SameValue(3, 4)
    assert DifferentValue(3, 4)
    assert !DifferentValue(3, 3)
}

test "one lifted side compares against the present value" {
    five: int? = 5
    absent: int? = null
    assert SameLiftedLeft(five, 5)
    assert !SameLiftedLeft(five, 6)
    assert !SameLiftedLeft(absent, 5)
    assert SameLiftedRight(5, five)
    assert !SameLiftedRight(5, absent)
}

test "an unconstrained parameter compares the same way, reference instantiation included" {
    assert SameAny("a", "a")
    assert !SameAny("a", "b")
    assert SameAnnotated("a", "a")
    assert !SameAnnotated("a", "b")
    assert SameAny(7, 7)
    assert !SameAny(7, 8)
}

test "an enclosing type's own parameter reads the same rule" {
    box := MakeBox(4)
    assert box.Holds(4)
    assert !box.Holds(5)
}

test "the comparison DISPATCHES to the instantiation's own equality rather than comparing bits" {
    // `Sloppy` calls two values equal whenever their `X` matches. A bitwise comparison would call
    // these two DIFFERENT, so the answer proves `EqualityComparer<T>.Default` was consulted.
    left := MakeSloppy(1, 2)
    right := MakeSloppy(1, 99)
    other := MakeSloppy(3, 2)
    assert SameValue(left, right)
    assert !SameValue(left, other)
    assert Same(LiftSloppy(left), LiftSloppy(right))
    assert !Same(LiftSloppy(left), LiftSloppy(other))
    assert !Same(LiftSloppy(left), AbsentSloppy())
    assert Same(AbsentSloppy(), AbsentSloppy())
}

test "a struct-constrained parameter's optional argument really is Nullable<T> in the metadata" {
    // The lifted arm depends on the CLR shape, not on the annotation: the `?` of a `struct`
    // parameter is a construction the emitter can read `HasValue` from.
    parameterType := FindOpenParameterType("Same")
    assert parameterType != null
    assert parameterType.IsGenericType
    assert parameterType.GetGenericTypeDefinition() == typeof(Nullable<int>).GetGenericTypeDefinition()
}

// The first parameter of the free function named `name`, found through the assembly this test file
// is emitted into — a free function is a static method of whichever type the emitter placed it on,
// so the search is by NAME across the assembly's own static methods.
func FindOpenParameterType(name: string): Type? {
    types := typeof(Sloppy).Assembly.GetTypes()
    for candidate in types {
        methods := candidate.GetMethods(BindingFlags.Public | BindingFlags.Static)
        for method in methods {
            if method.Name == name {
                return method.GetParameters()[0].ParameterType
            }
        }
    }

    return null
}

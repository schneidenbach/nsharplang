namespace NSharpLang.ColumnarEmitFacts.Tests

import System

// These generic owners make constraint lookup observable at the actual constrained-call site.  The
// first owner asks for `Select` after a constraint that does not declare it, then reaches the second
// constraint; the ordered twin starts with the declaring interface.  Both shapes must retain their
// metadata order and dispatch the exact second-interface slot.
interface ConstraintLookupFirst {
    func FirstOnly(): int
}

interface ConstraintLookupSecond {
    func Select(): int
}

struct ConstraintLookupValue: ConstraintLookupFirst, ConstraintLookupSecond {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func FirstOnly(): int {
        return Value + 1
    }

    func Select(): int {
        return Value + 200
    }
}

class ConstraintLookupSecondAfterFirst<T> where T: ConstraintLookupFirst, ConstraintLookupSecond {
    func Invoke(value: T): int {
        return value.Select()
    }
}

class ConstraintLookupSecondBeforeFirst<T> where T: ConstraintLookupSecond, ConstraintLookupFirst {
    func Invoke(value: T): int {
        return value.Select()
    }
}

func ConstraintLookupSingleTypeParameter(open: Type): Type {
    parameters := open.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("Expected exactly one generic constraint parameter.")
    }
    return parameters[0]
}

func ConstraintLookupAssertConstraintOrder(open: Type, first: Type, second: Type) {
    parameter := ConstraintLookupSingleTypeParameter(open)
    assert parameter.get_IsGenericParameter()
    assert parameter.get_IsGenericTypeParameter()
    assert !parameter.get_IsGenericMethodParameter()
    assert parameter.get_GenericParameterPosition() == 0
    assert parameter.get_DeclaringType() == open
    constraints := parameter.GetGenericParameterConstraints()
    assert constraints.Length == 2
    assert constraints[0] == first
    assert constraints[1] == second
}

test "a constrained source call continues past a nonmatching first interface to the second" {
    value := new ConstraintLookupValue(11)
    owner := new ConstraintLookupSecondAfterFirst<ConstraintLookupValue>()
    assert owner.Invoke(value) == 211

    closed := typeof(ConstraintLookupSecondAfterFirst<ConstraintLookupValue>)
    open := closed.GetGenericTypeDefinition()
    ConstraintLookupAssertConstraintOrder(open, typeof(ConstraintLookupFirst), typeof(ConstraintLookupSecond))
}

test "the ordered constraint twin preserves its declared first interface and the same second slot" {
    value := new ConstraintLookupValue(12)
    owner := new ConstraintLookupSecondBeforeFirst<ConstraintLookupValue>()
    assert owner.Invoke(value) == 212

    closed := typeof(ConstraintLookupSecondBeforeFirst<ConstraintLookupValue>)
    open := closed.GetGenericTypeDefinition()
    ConstraintLookupAssertConstraintOrder(open, typeof(ConstraintLookupSecond), typeof(ConstraintLookupFirst))
}

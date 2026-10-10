namespace NSharpLang.CensusLiftedOperators.Tests


// A LIFTED ORDERING COMPARISON IS NOT LIFTED. C# §12.4.8 lifts `<`, `>`, `<=` and `>=` to a plain
// `bool`, not to a `bool?`: an absent operand makes the answer FALSE rather than absent, which is
// why `!(a < b)` is NOT `a >= b` once either side can be absent.
func LessThan(a: int?, b: int?): bool => a < b

func LessOrEqual(a: int?, b: int?): bool => a <= b

func GreaterThan(a: int?, b: int?): bool => a > b

func GreaterOrEqual(a: int?, b: int?): bool => a >= b

func LessThanValue(a: int?, b: int): bool => a < b

func ValueLessThan(a: int, b: int?): bool => a < b

func GreaterThanDoubles(a: double?, b: double?): bool => a > b

func LessThanLongs(a: long?, b: long?): bool => a < b

// BOTH DIRECTIONS OF A LIFTED ORDERING ARE FALSE AT ONCE when an operand is absent, which is the
// fact a caller has to be able to observe for itself.
func NeitherOrder(a: int?, b: int?): bool => !(a < b) && !(a >= b)

// THE LIFTED UNARY OPERATORS: absent in, absent out.
func Negate(a: int?): int? => -a

func NegateLong(a: long?): long? => -a

func NegateDouble(a: double?): double? => -a

func Complement(a: int?): int? => ~a

func NotBoolean(a: bool?): bool? => !a

func CheckedNegate(a: int?): int? => checked(-a)

func UncheckedNegate(a: int?): int? => unchecked(-a)

// `++`, `--` AND THE COMPOUND FORMS, which read and write back the same `T?` storage.
func StepUp(a: int?): int? {
    value := a
    value++
    return value
}

func StepDown(a: int?): int? {
    value := a
    value--
    return value
}

func StepUpKeepingOldValue(a: int?): int? {
    value := a
    previous := value++
    return previous
}

func CompoundAddValue(a: int?, b: int): int? {
    total := a
    total += b
    return total
}

func CompoundAddNullable(a: int?, b: int?): int? {
    total := a
    total += b
    return total
}

func CompoundMultiply(a: int?, b: int?): int? {
    total := a
    total *= b
    return total
}

// NARROWING MUST NOT DOUBLE-UNWRAP. Inside `if a != null { … }` the read of `a` is already the
// element, so `a + 1` is an ordinary `int + int` and the lifted lowering must stay out of it.
func NarrowedSum(a: int?): int {
    if a != null {
        return a + 1
    }
    return 0
}

func NarrowedComparison(a: int?, b: int?): bool {
    if a != null && b != null {
        return a < b
    }
    return false
}

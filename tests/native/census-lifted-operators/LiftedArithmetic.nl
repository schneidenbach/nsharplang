namespace NSharpLang.CensusLiftedOperators.Tests

import System.Collections.Generic


// EVERY ARITHMETIC, BITWISE AND SHIFT SHAPE THE LIFTED RULE ADMITS, written once so the runtime
// contracts beside this file can state what each of them computes when an operand is absent.
//
// Each function is deliberately a one-liner over PARAMETERS rather than over constants: a constant
// operand would let a later constant-folding rule answer without the lowering ever running, and
// the whole point of these contracts is that the lowering runs.
func AddNullables(a: int?, b: int?): int? => a + b

func AddNullableAndValue(a: int?, b: int): int? => a + b

func AddValueAndNullable(a: int, b: int?): int? => a + b

func SubtractNullables(a: int?, b: int?): int? => a - b

func MultiplyNullables(a: int?, b: int?): int? => a * b

func DivideNullables(a: int?, b: int?): int? => a / b

func RemainderNullables(a: int?, b: int?): int? => a % b

// MIXED WIDTHS LIFT THE NARROWER SIDE EXACTLY AS THE UNLIFTED RULE WIDENS IT.
func AddLongAndInt(a: long?, b: int?): long? => a + b

func MultiplyDoubleAndInt(a: double?, b: int?): double? => a * b

func AddBytes(a: byte?, b: byte?): int? => a + b

func AddFloats(a: float?, b: float?): float? => a + b

// BITWISE OVER THE INTEGRAL DOMAIN.
func AndNullables(a: int?, b: int?): int? => a & b

func OrNullables(a: int?, b: int?): int? => a | b

func XorNullables(a: int?, b: int?): int? => a ^ b

func ShiftLeftNullables(a: int?, b: int?): int? => a << b

func ShiftRightNullables(a: int?, b: int?): int? => a >> b

func ShiftRightUnsignedNullables(a: uint?, b: int?): uint? => a >> b

// OVERFLOW IS THE UNLIFTED OPERATOR'S OVERFLOW. Only the PRESENCE test is lifted, so a `checked`
// body still throws on a present pair and still produces nothing at all for an absent one.
func CheckedAdd(a: int?, b: int?): int? => checked(a + b)

func UncheckedAdd(a: int?, b: int?): int? => unchecked(a + b)

func CheckedMultiply(a: int?, b: int?): int? => checked(a * b)

// THE EVALUATION-ORDER WITNESS. A lifted operator does NOT short-circuit: both operands are
// evaluated, left before right, whether or not the left one turned out to be absent.
class OperandLog {
    Entries: List<string>

    constructor() {
        Entries = new List<string>()
    }

    func Record(name: string, value: int?): int? {
        Entries.Add(name)
        return value
    }

    func Trace(): string {
        return string.Join(",", Entries)
    }
}

func LoggedSum(log: OperandLog, a: int?, b: int?): int? => log.Record("left", a) + log.Record("right", b)

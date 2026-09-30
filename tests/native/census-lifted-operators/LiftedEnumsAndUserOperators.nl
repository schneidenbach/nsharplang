namespace NSharpLang.CensusLiftedOperators.Tests

import System


// AN ENUM LIFTS THROUGH ITS UNDERLYING TYPE. The CLR carries an enum as its backing integral value,
// so a lifted `|` over `Access?` is the integral instruction under a presence test and the RESULT
// is still an `Access?` — not an `int?`.
enum Access {
    None = 0,
    Read = 1,
    Write = 2,
    Delete = 4
}

func CombineAccess(a: Access?, b: Access?): Access? => a | b

func MaskAccess(a: Access?, b: Access?): Access? => a & b

func ToggleAccess(a: Access?, b: Access?): Access? => a ^ b

func InvertAccess(a: Access?): Access? => ~a

func CombineAccessWithValue(a: Access?, b: Access): Access? => a | b

// A USER-DEFINED OPERATOR IS LIFTED THE SAME WAY. `decimal` and `TimeSpan` carry their arithmetic
// as `op_*` methods rather than as instructions, and the lifted lowering selects them through the
// same operator resolution the unlifted arm uses — there is no table of lifted operators anywhere.
func AddDecimals(a: decimal?, b: decimal?): decimal? => a + b

func SubtractDecimals(a: decimal?, b: decimal?): decimal? => a - b

func MultiplyDecimals(a: decimal?, b: decimal?): decimal? => a * b

func NegateDecimal(a: decimal?): decimal? => -a

func AddSpans(a: TimeSpan?, b: TimeSpan?): TimeSpan? => a + b

func SubtractSpans(a: TimeSpan?, b: TimeSpan?): TimeSpan? => a - b

func NegateSpan(a: TimeSpan?): TimeSpan? => -a

func SpanIsShorter(a: TimeSpan?, b: TimeSpan?): bool => a < b

func DecimalIsSmaller(a: decimal?, b: decimal?): bool => a < b

// THE SHAPE THE EMITTED METADATA HAS TO CARRY, held on a declared type so reflection can read it
// back by name.
class LiftedSignatures {
    func Sum(a: int?, b: int?): int? => a + b

    func Compare(a: int?, b: int?): bool => a < b

    func Combine(a: Access?, b: Access?): Access? => a | b
}

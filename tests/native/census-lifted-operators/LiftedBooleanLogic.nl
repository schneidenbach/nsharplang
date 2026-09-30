namespace NSharpLang.CensusLiftedOperators.Tests


// C# §12.14's THREE-VALUED `&` AND `|` OVER `bool?`, which are the one pair of lifted operators
// whose answer is NOT absent whenever an operand is: `false & null` is FALSE and `true | null` is
// TRUE, because one operand already decides the result on its own.
//
// `^` has no such shortcut — an exclusive-or needs both values — so it is the ORDINARY lift.
func AndBooleans(a: bool?, b: bool?): bool? => a & b

func OrBooleans(a: bool?, b: bool?): bool? => a | b

func XorBooleans(a: bool?, b: bool?): bool? => a ^ b

func AndBooleanAndValue(a: bool?, b: bool): bool? => a & b

func OrValueAndBoolean(a: bool, b: bool?): bool? => a | b

// THE THREE-VALUED TABLE, RENDERED. `-1` is absent, `0` is false and `1` is true, so a single
// contract can read a whole row of the table off one call.
func AndCode(a: bool?, b: bool?): int => BooleanCode(a & b)

func OrCode(a: bool?, b: bool?): int => BooleanCode(a | b)

func XorCode(a: bool?, b: bool?): int => BooleanCode(a ^ b)

func BooleanCode(value: bool?): int {
    if value == null {
        return -1
    }
    if value == true {
        return 1
    }
    return 0
}

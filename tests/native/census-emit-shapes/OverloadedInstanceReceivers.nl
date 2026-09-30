namespace NSharpLang.CensusEmitShapes.Tests


// AN OVERLOADED INSTANCE MEMBER ON A RECEIVER THE DIRECT-CALL PLANNER DOES NOT CLAIM.
//
// The emitter's residual instance-call ladder resolved a member that is UNIQUE at its arity, because
// it asked before any argument had a type. `Int32.CompareTo` declares two — `CompareTo(int)` and
// `CompareTo(object)` — so the two receiver shapes the planner leaves behind reached the bottom of
// that ladder and declined as `emit.call.instance-member-unmodeled`:
//
//   * a NARROWED nullable (`if count == null { ... }` then `count.CompareTo(other)`), the census row;
//   * a parenthesised expression (`(x + 1).CompareTo(other)`).
//
// The fix is not an arm for `CompareTo`. It is to ask the ARGUMENTS what they are — through the same
// preflight every other operand question uses — and then run the SAME scoped CLR overload resolution
// the planned door runs. So these sources are about the general shape, and `CompareTo` is only the
// member the census happened to land on.
func CompareNarrowed(count: int?, other: int): int {
    if count == null {
        return -2
    }

    return count.CompareTo(other)
}

func CompareParenthesised(value: int, other: int): int => (value + 1).CompareTo(other)

func CompareIndexed(values: int[], other: int): int => values[0].CompareTo(other)

func CompareLong(value: long, other: long): int => value.CompareTo(other)

// A receiver whose member takes no argument at all still goes through the unique-at-arity tier, and
// has to keep working. (`count.ToString()` on a NARROWED `int?` is `Nullable<int>`'s own override and
// is `string?` — one of the four names the nullable keeps for itself — so the unwrap is written out.)
func DescribeNarrowed(count: int?): string {
    if count == null {
        return "none"
    }

    return (count ?? 0).ToString()
}

// THE SAME LADDER FOR A REFERENCE RECEIVER WITH OVERLOADS: `string.IndexOf` declares several, and a
// parenthesised receiver is not a shape the planner claims either.
func IndexOfChar(text: string, suffix: string): int => (text + suffix).IndexOf('b')

func IndexOfString(text: string, suffix: string): int => (text + suffix).IndexOf("bc")

namespace NSharpLang.CensusFlowRules.Tests

test "a maybe-null class value compares by identity against a plain one, on either side and on both" {
    entry := new EqualityEntry("k")
    assert MaybeEqualsPlain(entry, entry)
    assert !MaybeEqualsPlain(new EqualityEntry("k"), entry)
    assert !MaybeEqualsPlain(null, entry)
    assert !PlainDiffersMaybe(entry, entry)
    assert PlainDiffersMaybe(entry, null)
    assert MaybeEqualsMaybe(null, null)
    assert MaybeEqualsMaybe(entry, entry)
    assert !MaybeEqualsMaybe(entry, null)
}

test "a maybe-null base compares with a derived value, and object? with a class" {
    special := new EqualitySpecialEntry("s")
    assert MaybeEqualsDerived(special, special)
    assert !MaybeEqualsDerived(new EqualityEntry("s"), special)
    assert !MaybeEqualsDerived(null, special)
    assert MaybeObjectEqualsPlain(special, special)
    assert !MaybeObjectEqualsPlain(null, special)
}

test "a declared operator == decides for a maybe-null operand, never identity" {
    // Two DISTINCT instances with one count: identity would answer false.
    assert TallyMaybeEqualsPlain(new EqualityTally(2), new EqualityTally(2))
    assert !TallyMaybeEqualsPlain(new EqualityTally(2), new EqualityTally(3))
    assert !TallyMaybeEqualsPlain(null, new EqualityTally(2))
    assert !TallyMaybeDiffersMaybe(new EqualityTally(4), new EqualityTally(4))
    assert TallyMaybeDiffersMaybe(new EqualityTally(4), null)
    assert !TallyMaybeDiffersMaybe(null, null)
    // An operator declared over NOT-null operands is still the one chosen.
    assert MeasureMaybeEqualsPlain(new EqualityMeasure(5), new EqualityMeasure(5))
    assert !MeasureMaybeEqualsPlain(new EqualityMeasure(5), new EqualityMeasure(6))
}

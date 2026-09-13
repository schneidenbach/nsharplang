namespace NSharpLang.CensusFlowRules.Tests


// RUNTIME contracts for an `assert` narrowing the flow that survives it.
//
// Every function in `AssertNarrowing.nl` reported NL905 on the line after its assert before this
// rule, so the file COMPILING is half the contract; these assertions are the other half — the
// narrowing must not change what the code computes, only what the analyzer will let it say.
test "an asserted null check narrows the value for everything after it" {
    assert AssertedLength(MaybeText(true)) == 4
}

test "an asserted `&&` chain proves both of its halves" {
    assert AssertedPairLength(MaybeText(true), MaybeText(true)) == 8
}

test "an asserted type pattern binds its name and narrows it" {
    assert AssertedPatternLength(MaybeObject(true)) == 5
}

test "an asserted call carries its own postcondition into the surviving flow" {
    // `TryGetValue` is `[MaybeNullWhen(false)] out TValue`: asserting the call proves the `out`
    // variable present, which is the same fact `if map.TryGetValue(…) { … }` installs in its
    // then-branch.
    map := AssertEntries()

    assert AssertedLookupLabel(map, "alpha") == "first"
    assert AssertedLookupLabel(map, "beta") == "second"
}

test "an ordinary guard still narrows — the assert rule is not the only way in" {
    assert LengthWithoutAssert(MaybeText(true)) == 4
    assert LengthWithoutAssert(MaybeText(false)) == 0
}

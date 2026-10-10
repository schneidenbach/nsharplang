namespace NSharpLang.CensusInParameters.Tests

test "an in parameter is read through, with the word and without it" {
    assert InParameters.CallOmitted() == 10
    assert InParameters.CallWritten() == 10
}

test "an in parameter ALIASES the caller's storage — the row the feature exists for" {
    // By value this would be "1,1". By reference it is "1,100": the callee's second read sees a write
    // that happened after the call began, because the parameter is the caller's storage and not a copy.
    assert InParameters.AliasSeesTheWrite() == "1,100"
}

test "the by-value control does NOT see the write, so the row above measures the reference" {
    assert InParameters.ByValueDoesNotSeeTheWrite() == "1,1"
}

test "an in parameter is readable everywhere a value is, and copies out freely" {
    local := new Big { A: 4, B: 1, C: 1, D: 1 }
    assert InParameters.ReadEverywhere(local) == "5,True,7"
}

test "in works beside other parameters and in any position" {
    assert InParameters.CallMixed() == 17
}

test "an in parameter of a primitive type works too" {
    assert InParameters.CallDoubled() == 42
}

test "an in parameter forwards to another in parameter" {
    assert InParameters.CallForwarded() == 14
}

test "an instance method takes in, and a by-value constructor beside it still builds" {
    assert HolderDriver.Drive() == 60
    assert HolderDriver.Seeded() == 15
}

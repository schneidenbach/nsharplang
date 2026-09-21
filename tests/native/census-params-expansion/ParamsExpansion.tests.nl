namespace NSharpLang.CensusParamsExpansion.Tests

test "a params constructor packs its written arguments in order" {
    assert ThreePacked() == "[.][:][ ]"
    assert OnePacked() == "[only]"
    assert NonePacked() == ""
}

test "an argument that already is the declared array passes through unpacked" {
    assert ArrayPassedThrough() == "[a][b]"
    assert SequencePassedThrough() == "[p][q]"
}

test "an external extension with a params tail binds at every packed arity" {
    assert LogThroughNullLogger() == 4
}

test "an external extension with a params tail binds through a source-typed receiver" {
    assert !HandleThroughNullLogger()
}

test "an already-built array reaches an extension's params slot unpacked" {
    assert LogWithBuiltArrayThroughNullLogger() == 1
}

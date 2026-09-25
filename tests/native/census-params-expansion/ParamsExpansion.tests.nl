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

test "an ordinary STATIC call packs a params tail at every arity" {
    assert JoinFourStrings() == "x,y,z"
    assert JoinOneString() == "only"
    // Zero packed arguments is still a packed call: the callee receives an empty array.
    assert AppendFormatNoHoles() == "plain"
}

test "the ordinary door reaches a params overload past the fixed arities beside it" {
    // `Path.Combine` declares fixed 2-, 3- and 4-argument overloads and a `params` one; five
    // arguments can only be the params overload, and it used to be invisible.
    assert CombineFivePathSegments().EndsWith("e")
    assert CombineFivePathSegments().Contains("a")
    assert FormatFourHoles() == "1-2-3-4"
}

test "normal form still beats expanded at the ordinary door" {
    assert JoinWithBuiltArray() == "m+n"
}

test "a packed call evaluates its arguments in the written order" {
    // The separator is written first and runs first; the packed elements then run left to right,
    // between the `newarr` and the call. Nothing is hoisted and nothing is reordered.
    assert PackedArgumentsRunInWrittenOrder() == "sabc=a" + "s" + "b" + "s" + "c"
}

test "an ordinary INSTANCE call packs a params tail too" {
    assert AppendFormatThreeHoles() == "7/8/9"
}

namespace NSharpLang.CensusEmitShapes.Tests

test "a static member receiver picks the overload the argument's own type names" {
    // "banana": the first 'n' is at 2, the first "na" is at 2, and from index 3 the next "na" is 4.
    assert StaticReceiverOverloads.CharIndex() == 2
    assert StaticReceiverOverloads.StringIndex() == 2

    // The second argument is a START INDEX. Read as a StringComparison it would have been
    // Ordinal-from-zero and answered 2.
    assert StaticReceiverOverloads.StringIndexFrom() == 4
}

test "a static property receiver resolves a tied external overload by argument type" {
    bytes := new byte[](2)
    bytes[0] = 72
    bytes[1] = 105
    assert StaticReceiverOverloads.DecodedFromArray(bytes) == "Hi"
    assert StaticReceiverOverloads.Encoded().Length == 2
    assert StaticReceiverOverloads.Encoded()[0] == 72
}

test "an argument containing a coalesce is typed, so the overload is still chosen by its arguments" {
    assert StaticReceiverOverloads.OrdinalIndexOf("banana", null) == 2
    assert StaticReceiverOverloads.OrdinalIndexOf("banana", "na") == 2
    assert StaticReceiverOverloads.OrdinalIndexOf("banana", "zz") == -1
}

test "a collection expression at a tied external overload selects the candidate that accepts it" {
    assert StaticReceiverOverloads.DecodedFromLiteral() == "Hi"
}

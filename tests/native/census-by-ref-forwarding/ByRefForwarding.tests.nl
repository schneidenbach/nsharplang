namespace NSharpLang.CensusByRefForwarding.Tests

test "a &T struct parameter passes its reference on, and the caller sees the write" {
    counter := new Counter { Value: 1 }
    ForwardStruct(ref counter)
    assert counter.Value == 2
}

test "a chain of two &T hops still reaches the caller's storage" {
    counter := new Counter { Value: 0 }
    ForwardStructTwice(ref counter)
    assert counter.Value == 2
}

test "the two spellings of a by-reference parameter forward to each other" {
    counter := new Counter { Value: 0 }
    AmpersandToRef(ref counter)
    assert counter.Value == 10
    RefToAmpersand(ref counter)
    assert counter.Value == 110
}

test "a &int parameter forwards to a &int parameter" {
    slot := 0
    ForwardInt(ref slot, 7)
    assert slot == 7
}

test "a field reached through a &T struct is passed by reference" {
    counter := new Counter { Value: 0 }
    FieldThroughAmpersand(ref counter, 9)
    assert counter.Value == 9
}

test "a reflected ref int parameter takes a &int parameter passed on, one hop and two" {
    slot := 5
    assert IncrementThroughAmpersand(ref slot) == 6
    assert IncrementTwoHops(ref slot) == 7
    assert slot == 7
}

test "a class REFERENCE is rebound through the chain, not merely mutated through it" {
    named := new Named("a")
    original := named
    RenameTwoHops(ref named, "!")
    assert named.Name == "a!"
    assert original.Name == "a"
}

test "an out argument may name a &int parameter" {
    slot := 0
    ProduceThroughAmpersand(ref slot)
    assert slot == 42
}

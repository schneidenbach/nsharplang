namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "argument loads retain dedicated zero-to-three and byte-to-int boundary encodings" {
    zero := ArgumentInstructionEmitFacts.ObserveLoad(0)
    one := ArgumentInstructionEmitFacts.ObserveLoad(1)
    two := ArgumentInstructionEmitFacts.ObserveLoad(2)
    three := ArgumentInstructionEmitFacts.ObserveLoad(3)
    four := ArgumentInstructionEmitFacts.ObserveLoad(4)
    byteLimit := ArgumentInstructionEmitFacts.ObserveLoad(255)
    longStart := ArgumentInstructionEmitFacts.ObserveLoad(256)

    assert ArgumentInstructionEmitFacts.FormatIl(zero.Il) == "2|42"
    assert ArgumentInstructionEmitFacts.FormatIl(one.Il) == "3|42"
    assert ArgumentInstructionEmitFacts.FormatIl(two.Il) == "4|42"
    assert ArgumentInstructionEmitFacts.FormatIl(three.Il) == "5|42"
    assert ArgumentInstructionEmitFacts.FormatIl(four.Il) == "14|4|42"
    assert ArgumentInstructionEmitFacts.FormatIl(byteLimit.Il) == "14|255|42"
    assert ArgumentInstructionEmitFacts.FormatIl(longStart.Il) == "254|9|0|1|42"

    assert zero.Result == 3
    assert one.Result == 10
    assert two.Result == 17
    assert three.Result == 24
    assert four.Result == 31
    assert byteLimit.Result == 1788
    assert longStart.Result == 1795
}

test "argument stores retain short byte and long int boundary encodings" {
    zero := ArgumentInstructionEmitFacts.ObserveStore(0)
    one := ArgumentInstructionEmitFacts.ObserveStore(1)
    two := ArgumentInstructionEmitFacts.ObserveStore(2)
    three := ArgumentInstructionEmitFacts.ObserveStore(3)
    four := ArgumentInstructionEmitFacts.ObserveStore(4)
    byteLimit := ArgumentInstructionEmitFacts.ObserveStore(255)
    longStart := ArgumentInstructionEmitFacts.ObserveStore(256)

    assert ArgumentInstructionEmitFacts.FormatIl(zero.Il) == "32|57|48|0|0|16|0|2|42"
    assert ArgumentInstructionEmitFacts.FormatIl(one.Il) == "32|57|48|0|0|16|1|3|42"
    assert ArgumentInstructionEmitFacts.FormatIl(two.Il) == "32|57|48|0|0|16|2|4|42"
    assert ArgumentInstructionEmitFacts.FormatIl(three.Il) == "32|57|48|0|0|16|3|5|42"
    assert ArgumentInstructionEmitFacts.FormatIl(four.Il) == "32|57|48|0|0|16|4|14|4|42"
    assert ArgumentInstructionEmitFacts.FormatIl(byteLimit.Il) == "32|57|48|0|0|16|255|14|255|42"
    assert ArgumentInstructionEmitFacts.FormatIl(longStart.Il) == "32|57|48|0|0|254|11|0|1|254|9|0|1|42"

    assert zero.Result == 12345
    assert one.Result == 12345
    assert two.Result == 12345
    assert three.Result == 12345
    assert four.Result == 12345
    assert byteLimit.Result == 12345
    assert longStart.Result == 12345
}

test "argument addresses retain short byte and long int boundary encodings" {
    zero := ArgumentInstructionEmitFacts.ObserveLoadAddress(0)
    one := ArgumentInstructionEmitFacts.ObserveLoadAddress(1)
    two := ArgumentInstructionEmitFacts.ObserveLoadAddress(2)
    three := ArgumentInstructionEmitFacts.ObserveLoadAddress(3)
    four := ArgumentInstructionEmitFacts.ObserveLoadAddress(4)
    byteLimit := ArgumentInstructionEmitFacts.ObserveLoadAddress(255)
    longStart := ArgumentInstructionEmitFacts.ObserveLoadAddress(256)

    assert ArgumentInstructionEmitFacts.FormatIl(zero.Il) == "15|0|74|42"
    assert ArgumentInstructionEmitFacts.FormatIl(one.Il) == "15|1|74|42"
    assert ArgumentInstructionEmitFacts.FormatIl(two.Il) == "15|2|74|42"
    assert ArgumentInstructionEmitFacts.FormatIl(three.Il) == "15|3|74|42"
    assert ArgumentInstructionEmitFacts.FormatIl(four.Il) == "15|4|74|42"
    assert ArgumentInstructionEmitFacts.FormatIl(byteLimit.Il) == "15|255|74|42"
    assert ArgumentInstructionEmitFacts.FormatIl(longStart.Il) == "254|10|0|1|74|42"

    assert zero.Result == 3
    assert one.Result == 10
    assert two.Result == 17
    assert three.Result == 24
    assert four.Result == 31
    assert byteLimit.Result == 1788
    assert longStart.Result == 1795
}

test "negative argument ordinals preserve the original unchecked byte conversion" {
    load := ArgumentInstructionEmitFacts.ObserveLoad(-1)
    store := ArgumentInstructionEmitFacts.ObserveStore(-1)
    address := ArgumentInstructionEmitFacts.ObserveLoadAddress(-1)

    assert ArgumentInstructionEmitFacts.FormatIl(load.Il) == "14|255|42"
    assert ArgumentInstructionEmitFacts.FormatIl(store.Il) == "32|57|48|0|0|16|255|14|255|42"
    assert ArgumentInstructionEmitFacts.FormatIl(address.Il) == "15|255|74|42"
    assert load.Result == 1788
    assert store.Result == 12345
    assert address.Result == 1788
}

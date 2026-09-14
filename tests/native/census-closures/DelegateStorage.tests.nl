namespace NSharpLang.CensusClosures.Tests

test "a delegate is invoked the same way wherever it is stored" {
    loader := new Loader(() => "read", value => value + "-t", "L")

    assert loader.ReadThroughField() == "read"
    assert loader.TransformThroughField("x") == "x-t"
    assert loader.ReadThroughProperty() == "read"

    assert ReadFrom(loader) == "read"
    assert TransformWith(loader, "y") == "y-t"
    assert ReadFromProperty(loader) == "read"

    assert ReadThroughLocal("seed") == "seed!"
    assert ReadThroughParameter(() => "param") == "param"
}

test "a written loop binding is captured per iteration by an async lambda" {
    adders := BuildAsyncAdders(3)
    assert adders.Count == 3

    first := adders[0]
    second := adders[1]
    third := adders[2]

    firstValue := await first()
    secondValue := await second()
    thirdValue := await third()

    assert firstValue == 10
    assert secondValue == 20
    assert thirdValue == 30

    // Calling one again still answers from its own binding.
    firstAgain := await first()
    assert firstAgain == 10
}

test "a delegate produced by a call is invoked by the argument list after it" {
    assert ChainedThroughALocal() == 6
    assert ChainedFromACallResult() == 6
    assert ChainedThroughAParameter(Curry()) == 15
    assert ChainedOverACapture(2) == 7
}

namespace NSharpLang.CensusEmitShapes.Tests

test "a lifted source struct is a typed local, present and absent" {
    assert LiftedArea(true) == 6
    assert LiftedArea(false) == 0
    assert LiftedHasValue(true)
    assert !LiftedHasValue(false)
}

test "the same lift reads through a parameter" {
    assert WidthOf(new Extent { Width: 9, Height: 1 }) == 9
    assert WidthOf(Square(9)) == 9
    assert WidthOf(null) == -1
}

test "a lifted source struct round-trips through a return type" {
    assert RoundTripHeight(3) == 3
    assert RoundTripHeight(0) == 0
}

test "the lifted struct has the CLR identity Nullable<Extent>" {
    lifted := Square(2)
    assert lifted != null
    assert lifted.Value.Width == 2
    assert lifted.Value.Height == 2
}

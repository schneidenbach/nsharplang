namespace NSharpLang.CensusEmitShapes.Tests

test "casts on both operands of a bitwise expression" {
    a := new byte[](2)
    b := new byte[](2)
    assert ByteDifference(a, b) == 0
    b[1] = 5
    assert ByteDifference(a, b) == 5
}

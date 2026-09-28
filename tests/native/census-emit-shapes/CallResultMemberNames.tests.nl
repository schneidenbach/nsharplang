namespace NSharpLang.CensusEmitShapes

import System

test "a reference tuple's element read off a call compares to null" {
    assert HasNoInner(null)
    assert !HasNoInner(new InvalidOperationException("inner"))
    assert HasInner(new InvalidOperationException("inner"))
    assert !HasInner(null)
}

test "a reference tuple's element read off a call is the element" {
    inner := new InvalidOperationException("inner")
    assert Object.ReferenceEquals(InnerOf(inner), inner)
    assert InnerOf(null) == null
    assert InnerMessage(inner) == "inner"
}

test "a reference tuple's element read off a call is an if condition" {
    assert DescribeInner(null) == "none"
    assert DescribeInner(new InvalidOperationException("inner")) == "some"
}

test "a value tuple's element read off a call still compares to null" {
    assert ValueHasNoInner(null)
    assert !ValueHasNoInner(new InvalidOperationException("inner"))
}

test "a source class's Item1 and Length properties read off a call" {
    assert ItemMissing(null)
    assert !ItemMissing("present")
    assert LengthMissing(null)
    assert !LengthMissing("present")
}

test "an array's and a string's length read off a call" {
    assert WordCount() == 3
    assert GreetingLength() == 5
}

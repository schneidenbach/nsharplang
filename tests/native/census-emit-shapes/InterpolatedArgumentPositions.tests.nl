namespace NSharpLang.CensusEmitShapes.Tests

import System

test "an interpolated string is the first argument of a runtime exception constructor" {
    inner := new Exception("root")
    assert ExceptionFirstOneHole("alpha", inner).Message == "alpha"
    assert InnerMessage(ExceptionFirstOneHole("alpha", inner).InnerException) == "root"
    assert ExceptionFirstTwoHoles("alpha", "beta", inner).Message == "alpha beta"
    assert ExceptionFirstTwoHoles("alpha", "beta", null).InnerException == null
    assert ExceptionFirstThreeHoles("alpha", "beta", 3, inner).Message == "alpha beta after 3"
    assert InnerMessage(ExceptionFirstThreeHoles("alpha", "beta", 3, inner).InnerException) == "root"
}

test "an interpolated string is the middle argument of a runtime exception constructor" {
    inner := new Exception("root")
    assert ExceptionMiddleOneHole("bad", "p", inner).ParamName == "p"
    assert InnerMessage(ExceptionMiddleOneHole("bad", "p", inner).InnerException) == "root"
    assert ExceptionMiddleTwoHoles("bad", "p", "q", inner).ParamName == "pq"
    assert ExceptionMiddleThreeHoles("bad", "p", "q", "r", inner).ParamName == "p_q_r"
    assert ExceptionMiddleThreeHoles("bad", "p", "q", "r", inner).Message.StartsWith("bad")
}

test "an interpolated string is the last argument of a runtime exception constructor" {
    assert ExceptionLastOneHole("n", "x", "too big").ParamName == "n"
    assert ExceptionLastOneHole("n", "x", "too big").Message.StartsWith("too big")
    assert ExceptionLastTwoHoles("n", "x", "item", 4).Message.StartsWith("item of 4")
    assert ExceptionLastThreeHoles("n", "x", "item", 1, 9).Message.StartsWith("item of 1..9")
    assert ExceptionLastThreeHoles("n", "x", "item", 1, 9).ActualValue?.ToString() == "x"
}

test "an interpolated string is an argument of a source constructor at every position" {
    inner := new Exception("root")
    first := SourceFirst("a", "b", "c", 7, inner)
    assert first.Text == "a-b-c"
    assert first.Count == 7
    assert InnerMessage(first.Inner) == "root"
    middle := SourceMiddle("a", "b", 8, null)
    assert middle.Text == "a-b"
    assert middle.Count == 8
    assert middle.Inner == null
    last := SourceLast("a", 9, inner)
    assert last.Text == "<a>"
    assert last.Count == 9
    assert InnerMessage(last.Inner) == "root"
}

test "an interpolated string is an argument of a referenced generic constructor at every position" {
    inner := new Exception("root")
    assert TupleFirst("a", 1, inner).Item1 == "a!"
    assert InnerMessage(TupleFirst("a", 1, inner).Item3) == "root"
    assert TupleMiddle("a", "b", 2, inner).Item2 == "a+b"
    assert TupleMiddle("a", "b", 2, inner).Item1 == 2
    last := TupleLast("a", "b", "c", 3, null)
    assert last.Item3 == "abc"
    assert last.Item2 == null
}

test "an interpolated string is an argument of a method call at every position" {
    inner := new Exception("root")
    assert CallFirst("a", 1, inner) == "[a]|1|root"
    assert CallMiddle("a", "b", 2, null) == "2|[a/b]|none"
    assert CallLast("a", "b", "c", 3, inner) == "3|root|[a/b/c]"
    assert InstanceFirst(new Framed("x", 5, null), "a", "b", 6) == "a.b#6@5"
    assert ReferencedStaticFirst("a", "b", "c", inner) == "a b c root"
    assert ReferencedInstanceLast("x", "y", 1) == "a(xy)b"
    assert ReferencedStaticMiddle("-", ["p", "q"]) == "p<->q"
}

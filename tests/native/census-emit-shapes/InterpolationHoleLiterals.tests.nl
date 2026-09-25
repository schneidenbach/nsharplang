namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic

func InterpolationHoleParts(): List<string> {
    parts := new List<string>()
    parts.Add("a")
    parts.Add("b")
    return parts
}

test "a string literal is an operand inside an interpolation hole" {
    assert Replaced("world") == "hello w0rld"
    assert Joined(InterpolationHoleParts()) == "joined a, b"
    assert BraceInLiteral(InterpolationHoleParts()) == "x a}b y"
}

test "a colon inside a hole literal is content and a trailing format specifier still applies" {
    assert JoinedWithColon(InterpolationHoleParts()) == "colon a: b done"
    assert FormattedAfterLiteral(InterpolationHoleParts(), 255) == "a-b then 00FF"
}

test "an escaped quote inside a hole literal does not end it" {
    assert Unquoted("say \"hi\"") == "nested say 'hi'"
    assert Unquoted("plain") == "nested plain"
}

test "a hole that is nothing but a literal emits" {
    assert BareLiteral() == "bare literal"
    assert ContainsText("world") == "contains True and False"
}

namespace NSharpLang.Compiler


// THE INTERPOLATION HOLE BOUNDARY, AS ONE RULE.
//
// `ParserLiteralFacts` decides where an interpolation hole ends and where its format specifier
// begins, and both the parser (`ParseInterpolatedString`) and the emitter's splitter
// (`ColumnarInterpolationSplitter`) ask it. The contracts below pin the rule C# applies: braces nest,
// and a string or character literal inside the hole is opaque, so its braces, colons and quotes are
// content. Each source is the text AFTER the hole's opening brace, so index 0 is the first character
// of the hole.
test "a hole ends at its own matching brace, past every nested brace group" {
    assert ParserLiteralFacts.FindInterpolationHoleClose("name} tail", 0, 10) == 4
    nested := "new { A: 1 }} tail"
    assert ParserLiteralFacts.FindInterpolationHoleClose(nested, 0, nested.Length) == 12
    deeper := "new { Inner: new { X: 1 } }.Inner.X}"
    assert ParserLiteralFacts.FindInterpolationHoleClose(deeper, 0, deeper.Length) == deeper.Length - 1
}

test "a brace or a quote inside a string or character literal does not move the hole's end" {
    inString := "Wrap(\"}\")}"
    assert ParserLiteralFacts.FindInterpolationHoleClose(inString, 0, inString.Length) == inString.Length - 1
    inChar := "c == '}'}"
    assert ParserLiteralFacts.FindInterpolationHoleClose(inChar, 0, inChar.Length) == inChar.Length - 1
    quoteChar := "c == '\"'}"
    assert ParserLiteralFacts.FindInterpolationHoleClose(quoteChar, 0, quoteChar.Length) == quoteChar.Length - 1
    escapedChar := "c == '\\''}"
    assert ParserLiteralFacts.FindInterpolationHoleClose(escapedChar, 0, escapedChar.Length) == escapedChar.Length - 1
}

test "an unclosed hole, an unclosed group and an unterminated literal leave the hole open" {
    assert ParserLiteralFacts.FindInterpolationHoleClose("name", 0, 4) == -1
    group := "new { A: 1 }"
    assert ParserLiteralFacts.FindInterpolationHoleClose(group, 0, group.Length) == -1
    literal := "Quote(\"x)}"
    assert ParserLiteralFacts.FindInterpolationHoleClose(literal, 0, literal.Length) == -1
}

test "an apostrophe that begins a lifetime is not a character literal" {
    lifetime := "Size<'a>()}"
    assert !ParserLiteralFacts.OpensInterpolationHoleLiteral(lifetime, 5, lifetime.Length)
    assert ParserLiteralFacts.FindInterpolationHoleClose(lifetime, 0, lifetime.Length) == lifetime.Length - 1

    assert ParserLiteralFacts.OpensInterpolationHoleLiteral("'a'", 0, 3)
    assert ParserLiteralFacts.OpensInterpolationHoleLiteral("'\\n'", 0, 4)
    assert ParserLiteralFacts.OpensInterpolationHoleLiteral("'}'", 0, 3)
    assert ParserLiteralFacts.OpensInterpolationHoleLiteral("\"", 0, 1)
    assert !ParserLiteralFacts.OpensInterpolationHoleLiteral("a", 0, 1)
}

test "the format colon is the first one outside every literal, group and conditional" {
    assert ParserLiteralFacts.FindFormatSpecifierColon("value:F2") == 5
    assert ParserLiteralFacts.FindFormatSpecifierColon("new { A: 1 }") == -1
    assert ParserLiteralFacts.FindFormatSpecifierColon("new { V: n }.V:F2") == 14
    assert ParserLiteralFacts.FindFormatSpecifierColon("c == ':'") == -1
    assert ParserLiteralFacts.FindFormatSpecifierColon("Join(\": \", parts):X") == 17
    assert ParserLiteralFacts.FindFormatSpecifierColon("flag ? a : b") == -1
}

namespace NSharpLang.ParserLiteralFacts.Tests

import NSharpLang.Compiler


// THE CANONICAL CONTRACTS FOR `ParserLiteralFacts`, IN N#.
//
// These replace `tests/ParserLiteralFactsTests.cs`, which was the last canonical C# assertion layer
// over a surface that is already entirely N# — `ParserLiteralFacts.nl` in BootstrapServices, whose
// three entry points decide, for the recovery parser, whether a string literal is terminated,
// whether a char literal is terminated, and where an interpolation's `:format` specifier begins.
//
// Three declarations report TWENTY-TWO cases, because all three are TABLE-DRIVEN: one row per case,
// and one INDEPENDENT reported test per row. That is the whole reason this is a table and not a
// loop — the C# `[Theory]` reported all seven string rows under ONE method name, so a single bad
// row named the method rather than the input. Here each row is its own `[Fact]`, its own trait, its
// own method name and its own JSON result, in `nlc test` AND in `dotnet test`.
//
// The production owner is called DIRECTLY rather than by reflection: `ParserLiteralFacts` is an N#
// class in the `NSharpLang.Compiler` namespace, this project takes the BootstrapServices assembly
// as a `dll:` dependency, and every entry point takes a `string` and answers a `bool` or an `int` —
// so there is no assembly-identity hazard for a reflection harness to route around.

// Successor to ParserLiteralFacts_ClassifiesCompleteStringLiterals — all seven [InlineData] rows.
// A plain literal is complete when it closes on an UNESCAPED quote, which is why the two backslash
// rows sit next to each other: `"Ada\"` is still open (the quote is escaped) and `"Ada\\"` is
// closed (the backslash is), and only counting the run of trailing backslashes tells them apart.
// The `$"` rows say the interpolated form is measured from the SECOND character, and the bare
// `identifier` row says a value that never opened a quote is not an unterminated one.
test "parser literal facts classify complete string literals" with (value: string, expected: bool) [
    ("\"Ada\"", true),
    ("\"Ada", false),
    ("\"Ada\\\"", false),
    ("\"Ada\\\\\"", true),
    ("$\"{name}\"", true),
    ("$\"{name}", false),
    ("identifier", true)
] {
    assert ParserLiteralFacts.IsCompleteStringLiteral(value) == expected, value
}

// Successor to ParserLiteralFacts_ClassifiesCompleteCharLiterals — all six [InlineData] rows.
// A char literal is complete only when it is quoted at BOTH ends and holds exactly one character,
// or exactly two of which the first is a backslash: `''` is empty, `'ab'` is too long, and the two
// half-quoted rows are open at one end each.
test "parser literal facts classify complete char literals" with (value: string, expected: bool) [
    ("'a'", true),
    ("'\\n'", true),
    ("''", false),
    ("'ab'", false),
    ("'a", false),
    ("a'", false)
] {
    assert ParserLiteralFacts.IsCompleteCharLiteral(value) == expected, value
}

// Successor to ParserLiteralFacts_FindsOnlyTopLevelFormatSpecifierColon — all nine [InlineData]
// rows. The answer is the index of the format-specifier colon, or -1 when there is none, and every
// row is a colon the scan must NOT mistake for one: the `??` row proves a null-coalescing `?` does
// not open a ternary, the two `? :` rows prove a real ternary consumes its colon, and the
// `(`/`[`/`{` rows prove a colon nested in any bracket depth is invisible. The quoted row proves a
// colon inside a string literal is skipped, and the `?.` row proves a null-conditional access is
// not a ternary either.
test "parser literal facts find only the top-level format-specifier colon" with (expression: string, expected: int) [
    ("value:N2", 5),
    ("value ?? fallback:N2", 17),
    ("ok ? yes : no", -1),
    ("ok ? yes : no:N2", 13),
    ("Format(value: 1):N2", 16),
    ("items[0:1]:N2", 10),
    ("new { A: 1 }:N2", 12),
    ("\"{not:format}\":N2", 14),
    ("value?.Name:N2", 11)
] {
    assert ParserLiteralFacts.FindFormatSpecifierColon(expression) == expected, expression
}

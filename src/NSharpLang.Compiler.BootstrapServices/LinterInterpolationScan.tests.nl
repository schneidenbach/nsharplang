namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// CONTRACTS FOR WHICH VARIABLES AN INTERPOLATED STRING USES (task 019 slice 9). These came out of
// `Linter.cs` with `HandleStringInterpolation` and `ExtractIdentifiersFromExpression` — a
// brace-depth scan and a separator scan that between them decided whether a variable used only
// inside a `$"…"` was reported as never read.
//
// THE RULE HAD NO SEMANTIC TESTS AT ALL AND ITS FAILURE MODE IS THE WORST KIND. A missed hole does
// not produce a missing diagnostic; it produces a WRONG one — NL001 telling a developer that a
// variable they can see being used is never read. So the assertions below are written from the
// direction of the harm: every shape that must credit a name, and every shape that must credit
// nothing at all.
//
// THE INPUT IS RAW SOURCE TEXT, quotes included, because that is what a `StringLiteralExpression`
// carries. A test that passed decoded content would be testing a function nobody calls.

func LisNames(value: string): string[] {
    return LinterInterpolationScan.UsedIdentifiers(value).ToArray()
}

func LisCount(value: string): int {
    return LinterInterpolationScan.UsedIdentifiers(value).Count
}

func LisFirst(value: string): string? {
    names := LinterInterpolationScan.UsedIdentifiers(value)
    if names.Count == 0 {
        return null
    }

    return names[0]
}

func LisJoin(value: string): string {
    names := LinterInterpolationScan.UsedIdentifiers(value)
    result := ""
    index := 0
    while index < names.Count {
        if index > 0 {
            result = result + ","
        }

        result = result + names[index]
        index = index + 1
    }

    return result
}

func LisHoles(value: string): string {
    holes := LinterInterpolationScan.HoleTexts(value)
    result := ""
    index := 0
    while index < holes.Count {
        if index > 0 {
            result = result + "|"
        }

        result = result + holes[index]
        index = index + 1
    }

    return result
}


// ── which literals are scanned at all ────────────────────────────────────────────────────────

test "a literal without the dollar is not scanned, however many braces it holds" {
    assert LisCount("\"plain\"") == 0
    assert LisCount("\"{name}\"") == 0
    assert LisCount("\"\"\"{name}\"\"\"") == 0
    assert LisCount("") == 0
}

test "both interpolated forms are scanned, and their content starts after their own opener" {
    assert LisJoin("$\"{name}\"") == "name"
    assert LisJoin("$\"\"\"{name}\"\"\"") == "name"
}

test "the raw form's opener is consumed WHOLE, so a hole cannot start inside it" {
    // `$"""` is four characters and the scan starts at index 4. If it started at 2 the two
    // remaining quotes would still be scanned as content — harmless here, but the contract is that
    // the opener is not content.
    assert LisHoles("$\"\"\"a{x}b\"\"\"") == "x"
}

test "a dollar that does not open an interpolated literal is scanned as nothing" {
    // The rule tests for `$"""` then `$"` and otherwise gives up. `$x` reaches the scan and leaves.
    assert LisCount("$x{name}") == 0
    assert LisCount("$") == 0
    assert LisCount("$'{name}'") == 0
}


// ── what a hole credits ──────────────────────────────────────────────────────────────────────

test "a bare name is credited" {
    assert LisJoin("$\"{name}\"") == "name"
    assert LisJoin("$\"hello {name}!\"") == "name"
    assert LisJoin("$\"{ name }\"") == "name"
}

test "the LEADING identifier is credited and the rest of the expression is not" {
    assert LisJoin("$\"{obj.Property}\"") == "obj"
    assert LisJoin("$\"{obj?.Property}\"") == "obj"
    assert LisJoin("$\"{list[0]}\"") == "list"
    assert LisJoin("$\"{obj.Method()}\"") == "obj"
    assert LisJoin("$\"{first + second}\"") == "first"
    assert LisJoin("$\"{a,b}\"") == "a"
    assert LisJoin("$\"{value:F2}\"") == "value"
    assert LisJoin("$\"{flag ? x : y}\"") == "flag"
}

test "every separator character cuts, and cutting at position zero credits nothing" {
    // The separator set is the contract. Each of these holes begins with its separator, so the
    // leading run is empty and the hole credits nothing at all.
    //
    // THE SPACE IS DELIBERATELY NOT IN THIS LIST, and the reason is the ORDER of the two steps: the
    // hole text is TRIMMED before the separator scan sees it, so a LEADING space is gone by then
    // and cannot cut anything. It still cuts in the middle — which the second loop asserts. The
    // next test states the leading-space case on its own so the asymmetry is recorded rather than
    // hidden by an omission.
    starts := [".", "?", "[", "(", "+", "-", "*", "/", "%", "&", "|", "^", "!", "=", "<", ">", ":", ","]
    index := 0
    while index < starts.Length {
        assert LisCount("$\"{" + starts[index] + "name}\"") == 0
        index = index + 1
    }

    // And each of them cuts when it follows a name. The space is included here, where it does cut.
    cutting := [".", "?", "[", "(", " ", "+", "-", "*", "/", "%", "&", "|", "^", "!", "=", "<", ">", ":", ","]
    cutIndex := 0
    while cutIndex < cutting.Length {
        assert LisJoin("$\"{name" + cutting[cutIndex] + "rest}\"") == "name"
        cutIndex = cutIndex + 1
    }
}

test "a LEADING space does not cut, because the trim happens before the scan" {
    assert LisJoin("$\"{ name}\"") == "name"
    assert LisJoin("$\"{  name  }\"") == "name"
    assert LisJoin("$\"{\tname}\"") == "name"
}

test "a hole that is not an identifier credits nothing" {
    assert LisCount("$\"{1}\"") == 0
    assert LisCount("$\"{123abc}\"") == 0
    assert LisCount("$\"{}\"") == 0
    assert LisCount("$\"{   }\"") == 0
    assert LisCount("$\"{\\\"literal\\\"}\"") == 0
}

test "several holes credit several names, in source order, duplicates kept" {
    assert LisJoin("$\"{a} {b} {c}\"") == "a,b,c"
    assert LisJoin("$\"{a}{a}\"") == "a,a"
    assert LisJoin("$\"{a} and {a.b} and {a[0]}\"") == "a,a,a"
}

test "a name is credited by its position in the literal, not by where the text is" {
    assert LisFirst("$\"prefix {alpha} middle {beta} suffix\"") == "alpha"
    assert LisJoin("$\"prefix {alpha} middle {beta} suffix\"") == "alpha,beta"
}


// ── brace depth ──────────────────────────────────────────────────────────────────────────────

test "a hole ends at its MATCHING brace, so a nested brace does not close it early" {
    assert LisHoles("$\"{new Point { X = 1 }}\"") == "new Point { X = 1 }"
    assert LisJoin("$\"{new Point { X = 1 }}\"") == "new"

    // The braces are NOT separators, so the hole text `a{b}c` is taken whole and then refused as a
    // non-identifier — the depth counting decided where the hole ENDS, and the separator scan
    // independently decided it named nothing.
    assert LisHoles("$\"{a{b}c}\"") == "a{b}c"
    assert LisCount("$\"{a{b}c}\"") == 0
}

test "an UNTERMINATED hole yields nothing rather than swallowing the rest of the literal" {
    // This is the shape a half-typed line in the editor produces, and crediting a name here would
    // mean crediting something the developer has not finished writing.
    assert LisCount("$\"{name") == 0
    assert LisCount("$\"{a{b}") == 0
    assert LisHoles("$\"{name") == ""

    // A closed hole BEFORE the unterminated one still counts — the scan is not all-or-nothing.
    assert LisJoin("$\"{good} {bad") == "good"
}

test "a stray closing brace is content, not a hole" {
    assert LisCount("$\"}\"") == 0
    assert LisCount("$\"a}b\"") == 0
    assert LisJoin("$\"}{name}\"") == "name"
}

// THE DELIBERATE CHANGE THE OLD CONTRACT ASKED FOR. This test used to record that `{{` was NOT
// understood: the scan counted depth instead of recognising the escape, so `$"{{name}}"` read as
// ONE hole of depth two whose text was `{name}`, and credited nothing only because `{name}` is not
// an identifier. It is understood now — the scan that answers WHERE each hole is had to know the
// escape to place a token correctly, and the linter reads the same scan — so a literal brace pair
// opens no hole at all. The credited-identifier answer is unchanged; what changed is that it is now
// right for the right reason.
test "the escaped-brace pair opens no hole" {
    assert LisHoles("$\"{{name}}\"") == ""
    assert LisCount("$\"{{name}}\"") == 0

    // And a real hole between two escaped pairs is still found.
    assert LisJoin("$\"{{a}} {b} {{c}}\"") == "b"
}


// ── the parts, asked directly ────────────────────────────────────────────────────────────────

test "hole texts are trimmed, and the trim is what makes the separator scan see a bare name" {
    assert LisHoles("$\"{  spaced  }\"") == "spaced"
    assert LisJoin("$\"{  spaced  }\"") == "spaced"
}

test "the leading-identifier rule refuses what is not an identifier and accepts what is" {
    assert LinterInterpolationScan.LeadingIdentifier("name") == "name"
    assert LinterInterpolationScan.LeadingIdentifier("obj.Property") == "obj"
    assert LinterInterpolationScan.LeadingIdentifier("_private") == "_private"
    assert LinterInterpolationScan.LeadingIdentifier("") == null
    assert LinterInterpolationScan.LeadingIdentifier("   ") == null
    assert LinterInterpolationScan.LeadingIdentifier("1name") == null
    assert LinterInterpolationScan.LeadingIdentifier(".name") == null
    assert LinterInterpolationScan.LeadingIdentifier(null) == null
}

test "the separator index is the LOWEST one, not the first separator that happens to occur" {
    // Written as a scan over a fixed separator list, so a hole whose LAST separator appears first
    // in that list is the case that catches a wrong-minimum edit: `,` is last in the list and `.`
    // is first, and `a,b.c` must cut at 1 and not at 3.
    assert LinterInterpolationScan.FirstSeparatorIndex("a,b.c") == 1
    assert LinterInterpolationScan.FirstSeparatorIndex("a.b,c") == 1
    assert LinterInterpolationScan.FirstSeparatorIndex("abc") == 3
    assert LinterInterpolationScan.FirstSeparatorIndex("") == 0
}


// ── what the caller does with the answer ─────────────────────────────────────────────────────

test "the answer is a list and not a set, because the caller marks each name used" {
    // Marking twice is not different from marking once, so de-duplicating here would buy nothing
    // and would lose the source order the assertions above rely on.
    assert LisCount("$\"{a}{a}{a}\"") == 3
    assert LisJoin("$\"{a}{a}{a}\"") == "a,a,a"
}


// ── the scan's positions, which the semantic-token layer places tokens with ────────────────────
//
// `HoleTexts` above is a VIEW of `HoleSpans`, so every assertion above is already an assertion
// about this scanner. What is new here is the half the linter never needed: WHERE each hole is.

func LisSpanJoin(value: string, line: int, column: int): string {
    spans := LinterInterpolationScan.HoleSpans(value, line, column)
    text := ""
    index := 0
    while index < spans.Count {
        if index > 0 {
            text = text + ";"
        }

        text = text + spans[index].Text + "@" + spans[index].Line.ToString() + ":" + spans[index].Column.ToString()
        index = index + 1
    }

    return text
}

test "a hole reports the position of its first content character" {
    // `$"{a}"` at line 3, column 10: the `$` is column 10, `"` is 11, `{` is 12, so `a` is 13.
    assert LisSpanJoin("$\"{a}\"", 3, 10) == "a@3:13"
}

test "each hole reports its own position, and the text between them is counted" {
    // `$"{a} and {b}"` — `a` at column 4 (1 + 2 for `$"` + 1 for `{`), `b` six characters later.
    assert LisSpanJoin("$\"{a} and {b}\"", 1, 1) == "a@1:4;b@1:12"
}

test "the span text is untrimmed so a re-lex of it lands on the right column" {
    // `HoleTexts` trims; `HoleSpans` must not, or every token inside a padded hole would be
    // reported one column early for each space the trim removed.
    assert LisSpanJoin("$\"{ a }\"", 1, 1) == " a @1:4"
    assert LinterInterpolationScan.HoleTexts("$\"{ a }\"")[0] == "a"
}

test "a newline inside a raw literal resets the column, as the source does" {
    assert LisSpanJoin("$\"\"\"x\n{a}\"\"\"", 5, 20) == "a@6:2"
}

test "a literal brace opens no hole" {
    assert LisSpanJoin("$\"{{a}}\"", 1, 1) == ""
    assert LisSpanJoin("$\"{{{a}}}\"", 1, 1) == "a@1:6"
}

test "an escaped brace opens no hole in a non-raw literal" {
    // `\{` consumes both characters, so what follows is literal text rather than an interpolation.
    assert LisSpanJoin("$\"\\{a}\"", 1, 1) == ""
    // But an escaped BACKSLASH consumes only itself and its partner, so the hole after it is real.
    assert LisSpanJoin("$\"\\\\{a}\"", 1, 1) == "a@1:6"
}

test "a brace inside a nested string is not counted as nesting" {
    assert LisSpanJoin("$\"{d[\"}\"]}\"", 1, 1) == "d[\"}\"]@1:4"
}

test "a nested braced construct ends at its own matching brace" {
    assert LisSpanJoin("$\"{new Point { X = 1 }}\"", 1, 1) == "new Point { X = 1 }@1:4"
}

test "an unterminated hole yields nothing at all" {
    assert LisSpanJoin("$\"{name", 1, 1) == ""
    assert LinterInterpolationScan.HoleTexts("$\"{name").Count == 0
}

test "a raw literal brace that is a format specifier or spans lines is text, not a hole" {
    assert LisSpanJoin("$\"\"\"{a:{b}}\"\"\"", 1, 1) == "a:{b}@1:6"
    assert LisSpanJoin("$\"\"\"{a\nb}\"\"\"", 1, 1) == ""
}

test "a literal that is not interpolated has no holes" {
    assert LisSpanJoin("\"{a}\"", 1, 1) == ""
    assert LisSpanJoin("$notastring", 1, 1) == ""
}

// THE POSITIONS ARE PINNED AGAINST THE REAL LEXER, NOT AGAINST ARITHMETIC RESTATED IN THE TEST.
// The editor hands this owner a lexed token's own line and column; if the two disagree about where
// a literal starts, every hole token lands in the wrong place. So the pin runs the real `Lexer`
// over a real source line and checks that the hole's reported column is the column at which the
// identifier actually appears in that line.
test "the scan agrees with the lexer about where a hole sits in a real source line" {
    source := "let greeting = $\"hi {name}\"\n"
    lexer := new Lexer(source, null)
    tokens := lexer.Tokenize()

    literalValue := ""
    literalLine := 0
    literalColumn := 0
    index := 0
    while index < tokens.Count {
        token := tokens[index]
        if token.Type == TokenType.StringLiteral && token.Value.StartsWith("$", StringComparison.Ordinal) {
            literalValue = token.Value
            literalLine = token.Line
            literalColumn = token.Column
        }

        index = index + 1
    }

    // The lexer carries the literal's RAW text, which is what this owner scans.
    assert literalValue == "$\"hi {name}\""
    assert literalLine == 1

    spans := LinterInterpolationScan.HoleSpans(literalValue, literalLine, literalColumn)
    assert spans.Count == 1
    assert spans[0].Text == "name"
    assert spans[0].Line == 1

    // `let greeting = ` is fifteen characters, so `$` is column 16 and `name` starts at column 22.
    assert literalColumn == 16
    assert spans[0].Column == 22
}

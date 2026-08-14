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

test "the escaped-brace pair is NOT understood, and that is recorded rather than claimed otherwise" {
    // `{{` is how a literal brace is written in an interpolated string. The scan counts depth
    // instead of recognising the escape, so `$"{{name}}"` reads ONE hole of depth two whose text is
    // `{name}` — and credits nothing, because `{name}` is not an identifier. The outcome is
    // harmless (a false negative in a rule whose false negatives are silence), but it is the
    // pre-existing behaviour and it is stated so a future change to it is a deliberate one.
    assert LisHoles("$\"{{name}}\"") == "{name}"
    assert LisCount("$\"{{name}}\"") == 0
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

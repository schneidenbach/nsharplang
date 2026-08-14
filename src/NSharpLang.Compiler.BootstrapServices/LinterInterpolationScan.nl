namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// WHICH VARIABLES AN INTERPOLATED STRING USES.
//
// NL001 ("declared but never read") and NL012 ("unused parameter") both need this: a name that only
// ever appears inside `$"…{name}…"` IS read, and a linter that could not see into the literal would
// squiggle it. The linter reaches this owner from a `StringLiteralExpression`, whose `Value` is the
// literal's RAW SOURCE TEXT — quotes, dollar and all — not its decoded content, so the scan starts
// by deciding what kind of literal it is looking at.
//
// THIS IS A LEXICAL SCAN, NOT A PARSE, AND THAT IS DELIBERATE. The answer feeds a "was it used"
// question, where a false NEGATIVE is a visible wrong squiggle and a false POSITIVE is silence. So
// the scan is generous: it takes the LEADING identifier of every brace-delimited hole and stops at
// the first separator, which means `{obj.Property}` credits `obj`, `{list[0]}` credits `list`,
// `{a + b}` credits `a` and not `b`, and a format specifier (`{value:F2}`) credits `value`. What it
// never does is credit something that is not an identifier at all: `{1 + 2}` and `{"literal"}`
// credit nothing, because `IdentifierText.IsValid` refuses the segment.
//
// NESTING IS COUNTED RATHER THAN ASSUMED. The hole scan tracks brace DEPTH, so an interpolation
// holding another braced construct — `{dict["{"]}`, `{new Point { X = 1 }}` — ends at its own
// matching brace and not at the first `}` in the text. An UNTERMINATED hole (`$"{name`) yields
// nothing rather than yielding the rest of the literal, which is what keeps a half-typed line in
// the editor from crediting a name the developer has not finished writing.
class LinterInterpolationScan {

    // The whole contract. Given a string literal's raw source text, the identifiers its
    // interpolation holes read — in source order, with duplicates preserved, because the caller
    // marks each one used and marking twice is not different from marking once.
    static func UsedIdentifiers(value: string): List<string> {
        result := new List<string>()
        holes := HoleTexts(value)
        index := 0
        while index < holes.Count {
            name := LeadingIdentifier(holes[index])
            if name != null {
                result.Add(name)
            }

            index = index + 1
        }

        return result
    }

    // The trimmed text of every balanced `{…}` hole in an interpolated literal, in source order.
    // A literal that is not interpolated has none — including a plain `"…"`, which may well contain
    // braces that mean nothing.
    static func HoleTexts(value: string): List<string> {
        result := new List<string>()
        if value == null {
            return result
        }

        if !value.StartsWith("$", StringComparison.Ordinal) {
            return result
        }

        // The raw literal's opening delimiter decides where the content starts. A raw interpolated
        // string opens with `$"""`; a normal one with `$"`. Anything else beginning with `$` is not
        // an interpolated string literal at all.
        index := 0
        if value.StartsWith("$\"\"\"", StringComparison.Ordinal) {
            index = 4
        } else if value.StartsWith("$\"", StringComparison.Ordinal) {
            index = 2
        } else {
            return result
        }

        while index < value.Length {
            if value[index] == '{' {
                depth := 1
                index = index + 1
                start := index
                while index < value.Length && depth > 0 {
                    if value[index] == '{' {
                        depth = depth + 1
                    } else if value[index] == '}' {
                        depth = depth - 1
                    }

                    index = index + 1
                }

                // Only a hole that CLOSED contributes. An unterminated one leaves depth above zero
                // and is dropped whole.
                if depth == 0 {
                    result.Add(value.Substring(start, index - start - 1).Trim())
                }
            } else {
                index = index + 1
            }
        }

        return result
    }

    // The identifier a hole reads, or nothing. The leading run up to the first separator, trimmed;
    // null when that run is empty or is not an identifier.
    static func LeadingIdentifier(holeText: string): string? {
        if holeText == null {
            return null
        }

        cut := FirstSeparatorIndex(holeText)
        leading := holeText.Substring(0, cut).Trim()
        if leading.Length == 0 {
            return null
        }

        if !IdentifierText.IsValid(leading) {
            return null
        }

        return leading
    }

    // Where the leading identifier ends: the lowest index at which any separator occurs, or the
    // whole length when none does. The set is the one the rule has always used — member access,
    // null-conditional, indexing, invocation, every binary operator character, and the two
    // characters that open a format specifier or separate arguments.
    static func FirstSeparatorIndex(holeText: string): int {
        separators := ['.', '?', '[', '(', ' ', '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', ':', ',']
        first := holeText.Length
        position := 0
        while position < separators.Length {
            index := holeText.IndexOf(separators[position])
            if index >= 0 && index < first {
                first = index
            }

            position = position + 1
        }

        return first
    }
}

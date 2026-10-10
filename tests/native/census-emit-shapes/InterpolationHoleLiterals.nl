namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic

// A STRING LITERAL WRITTEN INSIDE AN INTERPOLATION HOLE.
//
// The hole grammar is a set of text scans, and a quoted region is opaque to all of them: the `}`
// that ends a hole, the `:` that starts its format specifier and the `,` that divides its
// arguments are structure only OUTSIDE quotes. Reading them inside a literal ended the hole at the
// wrong brace, so every shape below declined the WHOLE literal at `emit.interpolation.split`.
func Replaced(name: string): string {
    return $"hello {name.Replace("o", "0")}"
}

func Joined(parts: List<string>): string {
    return $"joined {string.Join(", ", parts)}"
}

// A colon inside the separator is CONTENT; the hole here has no format specifier at all.
func JoinedWithColon(parts: List<string>): string {
    return $"colon {string.Join(": ", parts)} done"
}

// ...and a format specifier written AFTER a literal operand is still read as the format.
func FormattedAfterLiteral(parts: List<string>, value: int): string {
    return $"{string.Join("-", parts)} then {value:X4}"
}

// A brace inside the literal must not close the hole.
func BraceInLiteral(parts: List<string>): string {
    return $"x {string.Join("}", parts)} y"
}

// An ESCAPED quote inside the hole literal does not end it.
func Unquoted(name: string): string {
    return $"nested {name.Replace("\"", "'")}"
}

// A hole that is nothing but a literal.
//
// The escaped-brace pairing (`$"{{not a hole}} {"literal"}"`) is pinned at the splitter instead of
// here: `nlc format` cannot round-trip ANY literal containing `{{`, with or without a hole beside
// it -- it re-emits the escaped pair as a hole and the safety reparse rejects it. That defect is
// older than this family and belongs to the formatter, and a source file that `format --check`
// refuses does not belong in the estate.
func BareLiteral(): string {
    return $"bare {"literal"}"
}

// A chained call whose receiver holds a string literal. The no-argument-call arm of the simple
// hole grammar cannot name it, and before this family that arm REFUSED the hole outright instead
// of offering it to the arms that can.
func ContainsText(name: string): string {
    return $"contains {name.Contains("or").ToString()} and {name.Contains("zz").ToString()}"
}

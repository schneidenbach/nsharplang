namespace NSharpLang.Compiler

import NSharpLang.Compiler.Columnar


// THE FORMATTER'S ROUND TRIP OVER THE `<` DISAMBIGUATION AND PER-ELEMENT TUPLE NAMING (census wave 3,
// PARSE2). The parser half -- which reading each ambiguous source gets -- is
// `ColumnarParserTypeArgumentScan.tests.nl` in Compiler.Syntax; what the formatter owes those shapes
// is here, beside the formatter, because a shape the parser accepts that the formatter cannot write
// back is a shape that silently rewrites a user's file.

// One statement wrapped in a function, the shape every source below parses.
func FormatterScanSource(statement: string): string {
    return "func Test() {\n    result := " + statement + "\n}\n"
}

// The formatter's round trip: parse, format, and show the ONE statement line with newlines visible.
func ScanFormatted(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit == null {
        return "<no-unit>"
    }

    formatter := new Formatter(new FormatterConfig())
    // The defaulted `comments` parameter is written out: a same-project declaration does not yet
    // offer its defaults to a call in that project.
    formatted := formatter.Format(unit, null)
    return formatted.Replace("\r\n", "\n").Trim()
}

test "census PARSE2 formatter: every new spelling round-trips" {
    assert ScanFormatted(FormatterScanSource("Task.FromResult<List<int>?>(null)")) == "func Test() {\n    result := Task.FromResult<List<int>?>(null)\n}"
    assert ScanFormatted(FormatterScanSource("Method<(Item: int, Label: string)>(value)")) == "func Test() {\n    result := Method<(Item: int, Label: string)>(value)\n}"
    assert ScanFormatted(FormatterScanSource("(null, last, IsConstructor: true)")) == "func Test() {\n    result := (null, last, IsConstructor: true)\n}"
    assert ScanFormatted(FormatterScanSource("(First: 1, 2, Last: 3)")) == "func Test() {\n    result := (First: 1, 2, Last: 3)\n}"
    assert ScanFormatted(FormatterScanSource("a < b && c > d")) == "func Test() {\n    result := a < b && c > d\n}"

    returnType := "func Test(): (string?, string, IsConstructor: bool) {\n    return (null, last, IsConstructor: true)\n}\n"
    assert ScanFormatted(returnType) == "func Test(): (string?, string, IsConstructor: bool) {\n    return (null, last, IsConstructor: true)\n}"

    // The formatter writes a typed declaration with its `let` keyword, which is the canonical
    // spelling of both forms; the tuple ANNOTATION is what this row is about and it round-trips
    // character for character.
    local := "func Test() {\n    pair: (Item: string, Count: int) = value\n}\n"
    assert ScanFormatted(local) == "func Test() {\n    let pair: (Item: string, Count: int) = value\n}"
}

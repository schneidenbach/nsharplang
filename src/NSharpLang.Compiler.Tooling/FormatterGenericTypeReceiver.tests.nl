namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler


// THE FORMATTER'S ROUND TRIP OVER THE CONSTRUCTED-GENERIC-TYPE RECEIVER -- `Vector<int>.Count`,
// `Box<int>.Create(42)`. The parser's contracts for the receiver are
// `ColumnarParserGenericTypeReceiver.tests.nl` in Compiler.Syntax; this is the formatter's half,
// beside the formatter.
//
// A NODE THE FORMATTER CANNOT SPELL IS A FILE THAT WILL NOT RE-PARSE, and `FormatterWalk`'s unhandled
// arm THROWS rather than emitting something plausible — so a missing arm here is a crash, not a
// silent corruption. These pin the text as well as the survival: the nested form must come back with
// its `>>` unspaced, because that is what the developer wrote and what the split-`>>` reader accepts.
func GtrFormat(source: string): string {
    formatted := ""
    ast := ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit
    if ast != null {
        formatter := new Formatter(new FormatterConfig())
        formatted = formatter.Format(ast, null)
    }

    return formatted
}

test "generic type receiver: the formatter round-trips every receiver shape byte-exactly" {
    source := "func Lanes(): int {\n    return Vector<int>.Count\n}\n\nfunc Make(): int {\n    return Box<int>.Create(42)\n}\n\nfunc Pair(): int {\n    return Dictionary<string, List<int>>.Count\n}\n\nfunc Between(value: int, lower: int, upper: int): bool {\n    return lower < value && value > upper\n}\n"
    assert GtrFormat(source) == source
}

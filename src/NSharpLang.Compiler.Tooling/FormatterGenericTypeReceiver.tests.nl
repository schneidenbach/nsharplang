namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler


// The formatter's constructed-generic receiver cases. These use the same parser plus both of
// FormatSafe's safety gates that `nlc format` uses, so a parser decline cannot be hidden by directly
// formatting a recovered or incomplete AST.
func GtrFormatSafe(source: string): FormatResult {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    for error in parsed.Errors {
        if error.Severity == ErrorSeverity.Error {
            throw new InvalidOperationException(error.Message)
        }
    }

    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("The parser returned no compilation unit.")
    }

    lexer := new Lexer(source, "test.nl")
    lexer.Tokenize()
    formatter := new Formatter(new FormatterConfig())
    return formatter.FormatSafe(source, unit, lexer.Comments, "test.nl")
}

test "generic type receiver: a constructed generic type's static member access survives FormatSafe" {
    source := "func Instance() {\n    value := NullLogger<DocumentManager>.Instance\n}\n"
    result := GtrFormatSafe(source)

    assert result.Success
    assert result.Warnings.Count == 0
    assert result.Text == source
}

test "generic type receiver: nested generic arguments retain their split `>>` through FormatSafe" {
    source := "func Count(): int {\n    return Dictionary<string, List<int>>.Count\n}\n"
    result := GtrFormatSafe(source)

    assert result.Success
    assert result.Warnings.Count == 0
    assert result.Text == source
}

test "generic method call: explicit nested type arguments can be followed by member access" {
    source := "func Count(items: List<int>): int {\n    return Identity<List<int>>(items).Count\n}\n"
    result := GtrFormatSafe(source)

    assert result.Success
    assert result.Warnings.Count == 0
    assert result.Text == source
}

test "generic type receiver: generic member calls and ordinary comparisons survive FormatSafe" {
    source := "func Make(): int {\n    return Box<int>.Create(42)\n}\n\nfunc Between(value: int, lower: int, upper: int): bool {\n    return lower < value && value > upper\n}\n"
    result := GtrFormatSafe(source)

    assert result.Success
    assert result.Warnings.Count == 0
    assert result.Text == source
}

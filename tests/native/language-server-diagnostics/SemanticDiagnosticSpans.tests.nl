namespace NSharpLang.LanguageServerDiagnostics.Tests

test "DocumentManager unexpected EOF points at the last visible owner" {
    errors := LsdCompilerDiagnostics("file:///unexpected-eof.nl", "class Foo")
    diagnostic := LsdSingle(errors, "UnexpectedEndOfFile", null)
    LsdAssertSpan(diagnostic, 1, 7, "Foo".Length)
    LsdAssertLspRange(diagnostic, 0, 6, 9)
    message := LsdFieldText(diagnostic, "Message")
    assert !message.Contains("''")
    assert message.Contains("end of the file")
}

test "DocumentManager NL301 underlines the undefined variable name" {
    source := LsdDecodedSource(
        """
func main() {
    print totla
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl301-undefined-variable.nl", source),
        "UndefinedVariable",
        "totla"
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL301"
    LsdAssertSpan(diagnostic, 2, 11, "totla".Length)
    LsdAssertLspRange(diagnostic, 1, 10, 15)
}

test "DocumentManager NL303 underlines the undefined member name" {
    source := LsdDecodedSource(
        """
func main() {
    name := "ada"
    print name.Lenght
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl303-undefined-member.nl", source),
        "UndefinedMember",
        "Lenght"
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL303"
    LsdAssertSpan(diagnostic, 3, 16, "Lenght".Length)
    LsdAssertLspRange(diagnostic, 2, 15, 21)
}

test "DocumentManager NL304 underlines the constructor keyword" {
    source := LsdDecodedSource(
        """
class Box {
    Value: string

    constructor(v: int) {
        print v
    }
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl304-definite-assignment.nl", source),
        "DefiniteAssignmentError",
        "Value"
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL304"
    LsdAssertSpan(diagnostic, 4, 5, "constructor".Length)
    LsdAssertLspRange(diagnostic, 3, 4, 15)
}

test "DocumentManager NL305 underlines the full function head" {
    source := LsdDecodedSource(
        """
func score(ok: bool): int {
    if ok {
        return 1
    }
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl305-missing-return.nl", source),
        "MissingReturn",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL305"
    LsdAssertSpan(diagnostic, 1, 1, "func score".Length)
    LsdAssertLspRange(diagnostic, 0, 0, "func score".Length)
}

test "DocumentManager NL306 underlines the duplicate declaration name" {
    source := LsdDecodedSource(
        """
func dup() {
    x := 1
    x := 2
    print x
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl306-duplicate-declaration.nl", source),
        "DuplicateDeclaration",
        "'x'"
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL306"
    LsdAssertSpan(diagnostic, 3, 5, "x".Length)
    LsdAssertLspRange(diagnostic, 2, 4, 5)
}

test "DocumentManager NL309 underlines the readonly field name" {
    source := LsdDecodedSource(
        """
class Box {
    readonly Value: int

    constructor() {
        Value = 1
    }

    func change() {
        Value = 5
    }
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl309-readonly-assignment.nl", source),
        "ReadonlyAssignment",
        "Value"
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL309"
    LsdAssertSpan(diagnostic, 9, 9, "Value".Length)
    LsdAssertLspRange(diagnostic, 8, 8, 13)
}

test "DocumentManager NL312 underlines the unreachable statement keyword" {
    source := LsdDecodedSource(
        """
func score(): int {
    return 1
    print "unreachable"
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl312-unreachable-statement.nl", source),
        "UnreachableStatement",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL312"
    LsdAssertSpan(diagnostic, 3, 5, "print".Length)
    LsdAssertLspRange(diagnostic, 2, 4, 9)
}

test "DocumentManager NL313 underlines the invalid expression" {
    source := LsdDecodedSource(
        """
func main() {
    42
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nl313-invalid-expression-statement.nl", source),
        "InvalidExpressionStatement",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL313"
    LsdAssertSpan(diagnostic, 2, 5, "42".Length)
    LsdAssertLspRange(diagnostic, 1, 4, 6)
}

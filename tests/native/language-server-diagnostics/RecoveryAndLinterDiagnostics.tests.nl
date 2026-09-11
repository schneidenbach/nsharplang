namespace NSharpLang.LanguageServerDiagnostics.Tests

import System

func LsdAssertRecoveryCase(
    source: string,
    codeName: string,
    message: string,
    line: int,
    column: int,
    highlightedText: string
) {
    diagnostics := LsdCompilerDiagnostics("file:///recovery-span.nl", source)
    diagnostic := LsdSingle(diagnostics, codeName, message)
    LsdAssertSpan(diagnostic, line, column, highlightedText.Length)
    LsdAssertLspRange(diagnostic, line - 1, column - 1, column - 1 + highlightedText.Length)
    assert !LsdContains(diagnostics, "UnexpectedToken", null)
    assert !LsdContains(diagnostics, "InvalidExpressionStatement", null)
}

test "DocumentManager unused shorthand linter diagnostic uses variable name span" {
    source := LsdDecodedSource(
        """
func main() {
    asdf := "meow"
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///unused-shorthand-variable.nl", source)
    diagnostic := LsdSingleLinter(diagnostics, "NL001", "asdf")
    LsdAssertLinterSpan(diagnostic, 2, 5, "asdf".Length)
    LsdAssertLinterLspRange(diagnostic, 1, 4, 8)
}

test "DocumentManager missing initializer points at variable name" {
    source := LsdDecodedSource(
        """
func main() {
    name :=
        greeting := "hi"
    print greeting
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///missing-initializer.nl", source)
    diagnostic := LsdSingle(
        diagnostics,
        "ExpectedToken",
        "Expected an initializer expression after ':='"
    )
    LsdAssertSpan(diagnostic, 2, 5, "name".Length)
    assert !LsdContains(diagnostics, "UnexpectedToken", null)
    assert !LsdContains(diagnostics, "UndefinedVariable", "greeting")
    assert !LsdContains(diagnostics, "DefiniteAssignmentError", "name")
    LsdAssertLspRange(diagnostic, 1, 4, 8)
}

test "DocumentManager missing assignment value points at assignment target" {
    source := LsdDecodedSource(
        """
func main() {
    value := 1
    value =
    print value
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///missing-assignment-value.nl", source)
    diagnostic := LsdSingle(diagnostics, "ExpectedToken", "Expected expression after '='")
    LsdAssertSpan(diagnostic, 3, 5, "value".Length)
    assert !LsdContains(diagnostics, "UnexpectedToken", null)
    LsdAssertLspRange(diagnostic, 2, 4, 9)
}

test "DocumentManager missing keyword expressions use visible keyword spans" {
    source := LsdDecodedSource(
        """
func main() {
    foreach item items {
        print item
    }

    if {
        print "missing condition"
    }

    while {
        print "missing condition"
    }

    print
        value := 1
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///missing-keyword-spans.nl", source)

    missingIn := LsdSingle(
        diagnostics,
        "ExpectedToken",
        "Expected 'in' between the loop variable and collection"
    )
    LsdAssertSpan(missingIn, 2, 5, "foreach".Length)
    LsdAssertLspRange(missingIn, 1, 4, 11)

    missingIfCondition := LsdSingle(
        diagnostics,
        "ExpectedToken",
        "Expected a condition expression after 'if'"
    )
    LsdAssertSpan(missingIfCondition, 6, 5, "if".Length)
    LsdAssertLspRange(missingIfCondition, 5, 4, 6)

    missingWhileCondition := LsdSingle(
        diagnostics,
        "ExpectedToken",
        "Expected a condition expression after 'while'"
    )
    LsdAssertSpan(missingWhileCondition, 10, 5, "while".Length)
    LsdAssertLspRange(missingWhileCondition, 9, 4, 9)

    missingPrintExpression := LsdSingle(
        diagnostics,
        "ExpectedToken",
        "Expected an expression to print after 'print'"
    )
    LsdAssertSpan(missingPrintExpression, 14, 5, "print".Length)
    LsdAssertLspRange(missingPrintExpression, 13, 4, 9)
    assert !LsdContains(diagnostics, "TypeMismatch", "condition in a 'while' loop")
}

test "DocumentManager recovery spans avoid punctuation only markers" {
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    + 1
}
"""
        ),
        "InvalidSyntax",
        "Prefix '+'",
        2,
        5,
        "+ 1"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    .Name
}
"""
        ),
        "ExpectedToken",
        "Expected expression before '.'",
        2,
        5,
        ".Name"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    if true
}
"""
        ),
        "ExpectedToken",
        "Expected statement body",
        2,
        5,
        "if"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    for item in items
}
"""
        ),
        "ExpectedToken",
        "Expected statement body",
        2,
        5,
        "for"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    value := await
}
"""
        ),
        "ExpectedToken",
        "Expected an expression to await after 'await'",
        2,
        14,
        "await"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    value := must
}
"""
        ),
        "ExpectedToken",
        "Expected a nullable expression to unwrap after 'must'",
        2,
        14,
        "must"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    f := x =>
}
"""
        ),
        "ExpectedToken",
        "Expected a lambda body expression after '=>'",
        2,
        10,
        "x =>"
    )
    LsdAssertRecoveryCase(
        LsdDecodedSource(
            """
func main() {
    result := condition ? 1 :
}
"""
        ),
        "ExpectedToken",
        "Expected an else expression after ':'",
        2,
        15,
        "condition ? 1 :"
    )
}

test "DocumentManager using tuple deconstruction uses tuple pattern span" {
    source := LsdDecodedSource(
        """
func getPair(): (int, int) {
    return (1, 2)
}

func main() {
    using let (left, right) := getPair() {
        print "ok"
    }
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///using-tuple-deconstruction.nl", source)
    diagnostic := LsdSingle(
        diagnostics,
        "InvalidSyntax",
        "Using statement requires a variable declaration"
    )
    LsdAssertSpan(diagnostic, 6, 15, "(left, right)".Length)
    LsdAssertLspRange(diagnostic, 5, 14, 27)
    assert !LsdContainsMessage(diagnostics, "<error>")
    index := 0
    while index < diagnostics.Count {
        assert !LsdFieldText(diagnostics[index], "Message").Contains(
            "can't determine the type",
            StringComparison.OrdinalIgnoreCase
        )
        index = index + 1
    }
}

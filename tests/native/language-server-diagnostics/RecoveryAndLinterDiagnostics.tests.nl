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

// ── the census of the converted language server, run back through the editor path ────────────────
//
// Four NL0xx reports measured by `nlc check --text` over `nsharp-cs2nl/out/languageserver`, the N#
// conversion of this repository's own C# language server. Two were the linter's fault and are fixed;
// two were correct and are pinned here so a later change cannot quietly turn them into false
// negatives. They run through `DocumentManager` rather than the CLI because that is the surface the
// editor shows, and a rule that is right in `nlc check` and wrong in the editor is still wrong.

test "an ALIASED import used only by the namespace's own bare name is not reported unused" {
    // `Handlers/CompletionHandler.nl:15`. `import X as Y` in N# binds `Y` AND supplies X's names
    // unqualified — unlike C#'s `using Y = X;` — so the bare `new StringBuilder()` below is what keeps
    // this import alive. NL010 is an ERROR and its `nlc fix` deletes the line, so reporting it here
    // broke a build that was green.
    source := LsdDecodedSource(
        """
import System.Text as Txt

class Report {
    builder: System.Text.StringBuilder = new StringBuilder()

    func Size(): int {
        return builder.Length
    }
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///aliased-import-bare-use.nl", source)
    assert !LsdLinterContains(diagnostics, "NL010")
    assert LsdLinterCensus(diagnostics) == ""
}

test "an aliased import nothing uses is still reported, at the namespace's span" {
    source := LsdDecodedSource(
        """
import System.Text as Txt

class Report {
    count: int = 1

    func Size(): int {
        return count
    }
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///aliased-import-unused.nl", source)
    diagnostic := LsdSingleLinter(diagnostics, "NL010", "import System.Text")
    LsdAssertLinterSpan(diagnostic, 1, 8, "System.Text".Length)
}

test "an import used only through fully qualified spellings is reported unused" {
    // The C# rule, and safe here for the same reason: a fully qualified name resolves with no import
    // at all, so deleting the line leaves the file compiling.
    source := LsdDecodedSource(
        """
import System.Text

class Report {
    builder: System.Text.StringBuilder = new System.Text.StringBuilder()

    func Size(): int {
        return builder.Length
    }
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///import-only-qualified.nl", source)
    diagnostic := LsdSingleLinter(diagnostics, "NL010", "import System.Text")
    LsdAssertLinterSpan(diagnostic, 1, 8, "System.Text".Length)
}

test "a lambda parameter inside a declaration's own initializer shadows nothing" {
    // `Program.nl:41`. The C# it was converted from writes
    // `var server = await LanguageServer.From(… .OnInitialize((server, request, ct) => …))`, and N#'s
    // own scope rule agrees that the outer `server` does not exist yet: `x := x + 1` is NL301.
    source := LsdDecodedSource(
        """
func Start(): int {
    server := Build(server => server + 1)
    return server
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///lambda-parameter-own-initializer.nl", source)
    assert !LsdLinterContains(diagnostics, "NL020")
    assert LsdLinterCensus(diagnostics) == ""
}

test "a lambda parameter that shadows a local already in scope is still reported" {
    // N# does not take C# 8.0's relaxation of CS0136: crossing into a lambda does not license reuse
    // of a name that is genuinely in scope.
    source := LsdDecodedSource(
        """
func Start(): int {
    server := 1
    total := Build(server => server + 1)
    return total + server
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///lambda-parameter-real-shadow.nl", source)
    diagnostic := LsdSingleLinter(diagnostics, "NL020", "'server' shadows another 'server'")
    LsdAssertLinterSpan(diagnostic, 3, 20, "server".Length)
}

test "a tuple deconstruction's names are not in scope inside the initializer producing them" {
    source := LsdDecodedSource(
        """
func Start(): int {
    total, rest := Split(total => total + 1)
    return total + rest
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///deconstruction-own-initializer.nl", source)
    assert LsdLinterCensus(diagnostics) == ""
}

test "a parameter read only from inside a lambda is NOT an unused parameter" {
    // `Services/DocumentManager.nl:538` reported NL012 on a parameter whose body the converter could
    // not map, so the report was correct — but only if a read through a CAPTURE still counts. This is
    // the half that had to be true for that verdict to mean anything.
    source := LsdDecodedSource(
        """
func Scale(values: int[], factor: int): int {
    total := 0
    Each(values, value => total = total + value * factor)
    return total
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///parameter-read-in-lambda.nl", source)
    assert !LsdLinterContains(diagnostics, "NL012")
}

test "a parameter no body reads at all is reported, which is what the converted body produced" {
    source := LsdDecodedSource(
        """
func Deduplicate(diagnostics: int[]): int {
    return 0
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///parameter-never-read.nl", source)
    diagnostic := LsdSingleLinter(diagnostics, "NL012", "'diagnostics' in 'Deduplicate' is never read")
    LsdAssertLinterSpan(diagnostic, 1, 18, "diagnostics".Length)
}

test "a generic type argument written inside a lambda still needs the import that supplies it" {
    // `Handlers/TextDocumentHandler.nl:93` reported NL002 for `List` in a file with no
    // `import System.Collections.Generic` — the C# it came from got that name from an IMPLICIT using,
    // which the conversion does not materialise. The report is correct: the name needs the import.
    source := LsdDecodedSource(
        """
func Collect(): int {
    items := new List<int>()
    Each(items, value => items.Add(value))
    return items.Count
}
"""
    )
    diagnostics := LsdLinterDiagnostics("file:///missing-generic-import.nl", source)
    diagnostic := LsdSingleLinter(diagnostics, "NL002", "'List' is used without the import")
    LsdAssertLinterSpan(diagnostic, 2, 18, "List".Length)

    withImport := LsdDecodedSource(
        """
import System.Collections.Generic

func Collect(): int {
    items := new List<int>()
    Each(items, value => items.Add(value))
    return items.Count
}
"""
    )
    assert LsdLinterCensus(LsdLinterDiagnostics("file:///present-generic-import.nl", withImport)) == ""
}

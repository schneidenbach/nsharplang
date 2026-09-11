namespace NSharpLang.LanguageServerDiagnostics.Tests

func LsdAssertDiagnosticCase(
    uri: string,
    source: string,
    codeName: string,
    message: string,
    line: int,
    column: int,
    highlightedText: string
) {
    diagnostic := LsdSingle(LsdCompilerDiagnostics(uri, source), codeName, message)
    LsdAssertSpan(diagnostic, line, column, highlightedText.Length)
    LsdAssertLspRange(diagnostic, line - 1, column - 1, column - 1 + highlightedText.Length)
}

func LsdAssertMissingDeclarationCase(declarationSource: string, message: string, keyword: string) {
    LsdAssertDiagnosticCase(
        "file:///missing-" + keyword + "-name.nl",
        "package Playground\n\n" + declarationSource,
        "ExpectedToken",
        message,
        3,
        1,
        keyword
    )
}

func LsdAssertMalformedParameterCase(
    declarationSource: string,
    message: string,
    column: int,
    highlightedText: string
) {
    LsdAssertDiagnosticCase(
        "file:///malformed-parameters.nl",
        "package Playground\n\n" + declarationSource,
        "ExpectedToken",
        message,
        3,
        column,
        highlightedText
    )
}

func LsdAssertAdditionalMalformedCase(
    sourceBody: string,
    message: string,
    line: int,
    column: int,
    highlightedText: string
) {
    LsdAssertDiagnosticCase(
        "file:///additional-malformed-spans.nl",
        "package Playground\n\n" + sourceBody,
        "ExpectedToken",
        message,
        line,
        column,
        highlightedText
    )
}

test "DocumentManager publishes every invalid member call and return diagnostic" {
    source := LsdDecodedSource(
        """
package HelloWorld

func Hi() {
    "asdf".toUp()
    asdf := "asdf"
    asdf.sdd()
    return 42
}
"""
    )
    diagnostics := LsdPublishedCompilerDiagnostics("file:///invalid-member-calls.nl", source)
    assert LsdContainsAt(diagnostics, "UndefinedMember", "toUp", 4, 12, "toUp".Length)
    assert LsdContainsAt(diagnostics, "UndefinedMember", "sdd", 6, 10, "sdd".Length)
    assert LsdContainsAt(
        diagnostics,
        "TypeMismatch",
        "returns int but has no return type",
        3,
        6,
        "Hi".Length
    )
}

test "DocumentManager malformed editing buffer publishes bounded high signal diagnostics" {
    source := LsdDecodedSource(
        """
class User {
    Name: string
}

func main() {
    first := 1 +
    Console.WriteLine(undefinedFromLsp)
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///malformed.nl", source)
    assert LsdContainsAt(
        diagnostics,
        "ExpectedToken",
        "Expected expression after '+'",
        6,
        14,
        "1 +".Length
    )
    assert LsdContains(diagnostics, "UndefinedVariable", "undefinedFromLsp")
    assert !LsdContainsMessage(diagnostics, "<error>")
    assert diagnostics.Count <= 6
}

test "DocumentManager object initializer missing value uses property name span" {
    source := LsdDecodedSource(
        """
class User {
    Name: string
}

func main() {
    user := new User { Name: }
}
"""
    )
    LsdAssertDiagnosticCase(
        "file:///object-initializer-missing-value.nl",
        source,
        "ExpectedToken",
        "Expected a value for object initializer member 'Name'",
        6,
        24,
        "Name"
    )
}

test "DocumentManager missing declaration names use declaration keyword spans" {
    LsdAssertMissingDeclarationCase("func () {\n}", "Expected function name", "func")
    LsdAssertMissingDeclarationCase("class {\n}", "Expected class name", "class")
    LsdAssertMissingDeclarationCase("struct {\n}", "Expected struct name", "struct")
    LsdAssertMissingDeclarationCase("record {\n}", "Expected record name", "record")
    LsdAssertMissingDeclarationCase("interface {\n}", "Expected interface name", "interface")
    LsdAssertMissingDeclarationCase("union {\n}", "Expected union name", "union")
    LsdAssertMissingDeclarationCase("enum {\n}", "Expected enum name", "enum")
    LsdAssertMissingDeclarationCase("type = int", "Expected type alias name", "type")
}

test "DocumentManager malformed parameter lists use visible token spans" {
    LsdAssertMalformedParameterCase("func main(: string) {\n}", "Expected parameter name", 13, "string")
    LsdAssertMalformedParameterCase("func main(name:) {\n}", "Expected type name", 11, "name")
    LsdAssertMalformedParameterCase(
        "func main(name: string, ) {\n}",
        "Expected parameter name",
        11,
        "name: string,"
    )
    LsdAssertMalformedParameterCase("func main<T,>() {\n}", "Expected type parameter name", 10, "<T,>")
    LsdAssertMalformedParameterCase("class Box<> {\n}", "Expected type parameter name", 10, "<>")
}

test "DocumentManager additional malformed constructs use visible token spans" {
    LsdAssertAdditionalMalformedCase("class User {\n    Name:\n}", "Expected type name", 4, 5, "Name")
    LsdAssertAdditionalMalformedCase("class User {\n    Items: List<>\n}", "Expected type name", 4, 12, "List<>")
    LsdAssertAdditionalMalformedCase("func main() {\n    value := new\n}", "Expected type name", 4, 14, "new")
    LsdAssertAdditionalMalformedCase(
        "class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}",
        "Expected ':' after object initializer member 'Name'",
        7,
        24,
        "Name"
    )
}

test "DocumentManager missing field type before next field uses both owning spans" {
    source := LsdDecodedSource(
        """
package Playground

class User {
    Name:
    Items: List<>
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///field-type-before-next-field.nl", source)
    missingNameType := LsdSingleAt(diagnostics, "ExpectedToken", "Expected type name", 4, 5)
    LsdAssertSpan(missingNameType, 4, 5, "Name".Length)
    LsdAssertLspRange(missingNameType, 3, 4, 8)

    emptyGenericArgument := LsdSingleAt(diagnostics, "ExpectedToken", "Expected type name", 5, 12)
    LsdAssertSpan(emptyGenericArgument, 5, 12, "List<>".Length)
    LsdAssertLspRange(emptyGenericArgument, 4, 11, 17)
}

test "DocumentManager incomplete member access points at receiver" {
    source := LsdDecodedSource(
        """
func main() {
    name := "Ada"
    name.
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///member-dot.nl", source)
    diagnostic := LsdSingle(diagnostics, "ExpectedToken", "Expected member name")
    LsdAssertSpan(diagnostic, 3, 5, "name".Length)
    assert LsdFieldText(diagnostic, "HumanExplanation").Contains("dot", StringComparison.OrdinalIgnoreCase)
    assert !LsdContains(diagnostics, "InvalidExpressionStatement", null)
    assert !LsdContainsMessage(diagnostics, "<error>")
    LsdAssertLspRange(diagnostic, 2, 4, 8)
}

test "DocumentManager incomplete member access before call points at receiver" {
    source := LsdDecodedSource(
        """
func main() {
    name := "Ada"
    name.()
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///member-dot-before-call.nl", source)
    diagnostic := LsdSingle(diagnostics, "ExpectedToken", "Expected member name")
    LsdAssertSpan(diagnostic, 3, 5, "name".Length)
    assert LsdFieldText(diagnostic, "HumanExplanation").Contains("dot (.)")
    assert !LsdContains(diagnostics, "InvalidExpressionStatement", null)
    assert !LsdContainsMessage(diagnostics, "<error>")
    LsdAssertLspRange(diagnostic, 2, 4, 8)
}

test "DocumentManager unterminated string literal points at literal token" {
    source := LsdDecodedSource(
        """
func main() {
    name := "Ada
    print name
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///unterminated-string.nl", source),
        "InvalidLiteral",
        "Unterminated string literal"
    )
    LsdAssertSpan(diagnostic, 2, 13, 4)
    assert LsdFieldText(diagnostic, "HumanExplanation").Contains(
        "closing quote",
        StringComparison.OrdinalIgnoreCase
    )
    LsdAssertLspRange(diagnostic, 1, 12, 16)
}

test "DocumentManager unterminated string with escaped quote points at literal token" {
    source := LsdDecodedSource(
        """
func main() {
    name := "Ada\"
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///unterminated-string-escaped-quote.nl", source),
        "InvalidLiteral",
        "Unterminated string literal"
    )
    LsdAssertSpan(diagnostic, 2, 13, 6)
    LsdAssertLspRange(diagnostic, 1, 12, 18)
}

test "DocumentManager unterminated triple quote string points at opening delimiter" {
    source := "func main() {\n    text := \"\"\"hello\nworld\n}\n"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///unterminated-triple-string.nl", source),
        "InvalidLiteral",
        "Unterminated triple-quoted string literal"
    )
    LsdAssertSpan(diagnostic, 2, 13, 3)
    LsdAssertLspRange(diagnostic, 1, 12, 15)
}

test "DocumentManager unterminated interpolated raw string points at opening delimiter" {
    source := "func main() {\n    text := $\"\"\"hello {name}\n}\n"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///unterminated-raw-string.nl", source),
        "InvalidLiteral",
        "Unterminated interpolated raw string literal"
    )
    LsdAssertSpan(diagnostic, 2, 13, 4)
    LsdAssertLspRange(diagnostic, 1, 12, 16)
}

test "DocumentManager missing closing paren points at call owner" {
    source := LsdDecodedSource(
        """
func main() {
    print("hello"
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-paren.nl", source),
        "MissingClosingParen",
        "Missing closing ')'"
    )
    LsdAssertSpan(diagnostic, 2, 5, "print".Length)
    assert LsdFieldText(diagnostic, "HumanExplanation").Contains(
        "closing ')'",
        StringComparison.OrdinalIgnoreCase
    )
    LsdAssertLspRange(diagnostic, 1, 4, 9)
}

test "DocumentManager unclosed empty call argument list points at call owner" {
    source := LsdDecodedSource(
        """
func main() {
    print(
    greeting.CompareTo("ter")
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///missing-empty-call-paren.nl", source)
    diagnostic := LsdSingle(diagnostics, "MissingClosingParen", "Missing closing ')'")
    LsdAssertSpan(diagnostic, 2, 5, "print".Length)
    assert !LsdContains(diagnostics, "UnexpectedToken", null)
    LsdAssertLspRange(diagnostic, 1, 4, 9)
}

test "DocumentManager unclosed empty function parameter list points at function name" {
    source := "func main(\n"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-empty-parameter-paren.nl", source),
        "MissingClosingParen",
        "Missing closing ')'"
    )
    LsdAssertSpan(diagnostic, 1, 6, "main".Length)
    LsdAssertLspRange(diagnostic, 0, 5, 9)
}

test "DocumentManager missing closing brace points at function name" {
    source := LsdDecodedSource(
        """
func main() {
    print "hi"
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-brace.nl", source),
        "MissingClosingBrace",
        "Missing closing '}'"
    )
    LsdAssertSpan(diagnostic, 1, 6, "main".Length)
    LsdAssertLspRange(diagnostic, 0, 5, 9)
}

test "DocumentManager missing closing bracket points at assigned variable" {
    source := LsdDecodedSource(
        """
func main() {
    nums := [1, 2
    print nums
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-bracket.nl", source),
        "MissingClosingBracket",
        "Missing closing ']'"
    )
    LsdAssertSpan(diagnostic, 2, 5, "nums".Length)
    LsdAssertLspRange(diagnostic, 1, 4, 8)
}

test "DocumentManager missing parameter colon uses parameter name span" {
    source := "func greet(name string): string { return name }"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-parameter-colon.nl", source),
        "ExpectedToken",
        "Expected ':' after parameter name"
    )
    LsdAssertSpan(diagnostic, 1, 12, "name".Length)
    LsdAssertLspRange(diagnostic, 0, 11, 15)
    assert LsdFieldText(diagnostic, "ContextualHint").Contains("name: Type")
}

test "DocumentManager missing field colon uses field name span" {
    source := LsdDecodedSource(
        """
class User {
    Name string
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-field-colon.nl", source),
        "ExpectedToken",
        "Expected ':' or ':=' after field name"
    )
    LsdAssertSpan(diagnostic, 2, 5, "Name".Length)
    LsdAssertLspRange(diagnostic, 1, 4, 8)
    assert LsdFieldText(diagnostic, "ContextualHint").Contains("Name: Type")
}

test "DocumentManager missing function return colon uses function name span" {
    source := "func answer() int { return 1 }"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///missing-function-return-colon.nl", source),
        "ExpectedToken",
        "Expected ':' before return type"
    )
    LsdAssertSpan(diagnostic, 1, 6, "answer".Length)
    LsdAssertLspRange(diagnostic, 0, 5, 11)
    assert LsdFieldText(diagnostic, "ContextualHint").Contains("func name(...): Type")
}

test "DocumentManager default parser span uses visible token span" {
    source := "enum Status: decimal { Open }"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///unsupported-enum-backing-type.nl", source),
        "UnexpectedToken",
        "Unsupported enum backing type"
    )
    LsdAssertSpan(diagnostic, 1, 14, "decimal".Length)
    LsdAssertLspRange(diagnostic, 0, 13, 20)
}

test "DocumentManager default semantic span uses visible token span" {
    source := LsdDecodedSource(
        """
func main(): int {
    let value: var = 42
    return value
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///explicit-var-type.nl", source),
        "InvalidSyntax",
        "'var' is not a type"
    )
    LsdAssertSpan(diagnostic, 2, 16, "var".Length)
    LsdAssertLspRange(diagnostic, 1, 15, 18)
}

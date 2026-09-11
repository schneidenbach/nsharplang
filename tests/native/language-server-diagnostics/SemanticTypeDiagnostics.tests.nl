namespace NSharpLang.LanguageServerDiagnostics.Tests

test "DocumentManager possible null access uses stable compiler code" {
    source := LsdLeadingNewlineSource(
        """
func main() {
    x: string? = "hello"
    len := x.Length
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///nullable.nl", source)
    diagnostic := LsdSingle(diagnostics, "PossibleNullAccess", null)
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL905"
    assert LsdFieldText(diagnostic, "Severity") == "Error"
    assert LsdFieldText(diagnostic, "Suggestion").Contains("?.", StringComparison.Ordinal)
}

test "DocumentManager possible null access squiggle covers receiver token" {
    source := "func main() {\n    x: string? = \"hello\"\n    len := x.Length\n}"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nullable-span.nl", source),
        "PossibleNullAccess",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL905"
    LsdAssertSpan(diagnostic, 3, 12, "x".Length)
    LsdAssertLspRange(diagnostic, 2, 11, 12)
}

test "DocumentManager possible null access underlines receiver expression" {
    source := "func main() {\n    customer: string? = \"Ada\"\n    len := customer.Length\n}"
    nullAccess := LsdSingle(
        LsdCompilerDiagnostics("file:///null-receiver-span.nl", source),
        "PossibleNullAccess",
        null
    )
    assert LsdFieldText(nullAccess, "Severity") == "Error"
    LsdAssertSpan(nullAccess, 3, 12, "customer".Length)
    LsdAssertLspRange(nullAccess, 2, 11, 11 + "customer".Length)
}

test "DocumentManager nullable value access squiggle covers Value token" {
    source := "func Main(input: int?): int {\n    return input.Value\n}"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nullable-value-span.nl", source),
        "NullabilityWarning",
        ".Value"
    )
    assert LsdFieldText(diagnostic, "Severity") == "Error"
    LsdAssertSpan(diagnostic, 2, 18, "Value".Length)
    LsdAssertLspRange(diagnostic, 1, 17, 22)
}

test "DocumentManager possible null index underlines receiver expression" {
    source := "func first(items: int[]?): int {\n    return items[0]\n}"
    nullAccess := LsdSingle(
        LsdCompilerDiagnostics("file:///null-index-span.nl", source),
        "PossibleNullAccess",
        null
    )
    assert LsdFieldText(nullAccess, "Severity") == "Error"
    LsdAssertSpan(nullAccess, 2, 12, "items".Length)
    LsdAssertLspRange(nullAccess, 1, 11, 11 + "items".Length)
}

test "DocumentManager redundant must unwrap squiggle covers must keyword" {
    source := "func Main(input: int?): int {\n    if input.HasValue {\n        return must input\n    }\n    return 0\n}"
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///redundant-must-span.nl", source),
        "NullabilityWarning",
        "redundant"
    )
    assert LsdFieldText(diagnostic, "Severity") == "Error"
    LsdAssertSpan(diagnostic, 3, 16, "must".Length)
    LsdAssertLspRange(diagnostic, 2, 15, 19)
}

test "DocumentManager semantic errors use expected token spans" {
    source := LsdDecodedSource(
        """
func TakesInt(value: int) {}
func main() {
    maybeCustomerName: string? = "Ada"
    print maybeCustomerName.Length
    TakesInt("oops")
    TakesInt()
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///semantic-spans.nl", source)

    nullAccess := LsdSingle(diagnostics, "PossibleNullAccess", null)
    LsdAssertSpan(nullAccess, 4, 11, "maybeCustomerName".Length)
    LsdAssertLspRange(nullAccess, 3, 10, 27)

    wrongArgument := LsdSingle(diagnostics, "TypeMismatch", "Cannot pass")
    LsdAssertSpan(wrongArgument, 5, 14, "\"oops\"".Length)
    LsdAssertLspRange(wrongArgument, 4, 13, 19)

    wrongCount := LsdSingle(diagnostics, "WrongArgumentCount", null)
    LsdAssertSpan(wrongCount, 6, 5, "TakesInt".Length)
    LsdAssertLspRange(wrongCount, 5, 4, 12)
}

test "DocumentManager type mismatches use offending expression spans" {
    source := LsdDecodedSource(
        """
func TakesVoid(): void {
}

func ExpressionBodyMismatch(): int => "bad"

func ExpressionBodyRequiresReturnType() => "bad"

func main(): int {
    declared: int = "hi"
    inferred := TakesVoid()
    if "yes" {
        return "bad"
    }
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///type-mismatch-spans.nl", source)

    expressionBodyMismatch := LsdSingle(diagnostics, "TypeMismatch", "ExpressionBodyMismatch")
    LsdAssertSpan(expressionBodyMismatch, 4, 39, "\"bad\"".Length)
    LsdAssertLspRange(expressionBodyMismatch, 3, 38, 43)

    expressionBodyRequiresReturnType := LsdSingle(diagnostics, "TypeMismatch", "ExpressionBodyRequiresReturnType")
    LsdAssertSpan(expressionBodyRequiresReturnType, 6, 6, "ExpressionBodyRequiresReturnType".Length)
    LsdAssertLspRange(expressionBodyRequiresReturnType, 5, 5, 37)

    localInitializer := LsdSingleAt(diagnostics, "TypeMismatch", null, 9, -1)
    assert LsdFieldText(localInitializer, "Message") == "Variable 'declared' is typed as 'int', but the value is 'string'"
    LsdAssertSpan(localInitializer, 9, 21, "\"hi\"".Length)
    LsdAssertLspRange(localInitializer, 8, 20, 24)

    voidAssignment := LsdSingle(diagnostics, "TypeMismatch", "void")
    LsdAssertSpan(voidAssignment, 10, 17, "TakesVoid".Length)
    LsdAssertLspRange(voidAssignment, 9, 16, 25)

    ifCondition := LsdSingleAt(diagnostics, "TypeMismatch", null, 11, -1)
    assert LsdFieldText(ifCondition, "Message") == "The condition in an 'if' must be a boolean, but I found 'string'"
    LsdAssertSpan(ifCondition, 11, 8, "\"yes\"".Length)
    LsdAssertLspRange(ifCondition, 10, 7, 12)

    returnValue := LsdSingleAt(diagnostics, "TypeMismatch", null, 12, -1)
    returnMessage := LsdFieldText(returnValue, "Message")
    assert returnMessage.Contains("main")
    assert returnMessage.Contains("returns string")
    LsdAssertSpan(returnValue, 12, 16, "\"bad\"".Length)
    LsdAssertLspRange(returnValue, 11, 15, 20)
}

test "DocumentManager enum initializer mismatches use initializer value spans" {
    source := LsdDecodedSource(
        """
enum HttpCode: int {
    Ok = "ok"
}

enum Label: string {
    Ready = 1
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///enum-value-spans.nl", source)

    numericValue := LsdSingle(diagnostics, "TypeMismatch", "'Ok'")
    LsdAssertSpan(numericValue, 2, 10, "\"ok\"".Length)
    LsdAssertLspRange(numericValue, 1, 9, 13)

    stringValue := LsdSingle(diagnostics, "TypeMismatch", "'Ready'")
    LsdAssertSpan(stringValue, 6, 13, "1".Length)
    LsdAssertLspRange(stringValue, 5, 12, 13)
}

test "DocumentManager control flow and collection mismatches use offending expression spans" {
    source := LsdDecodedSource(
        """
func main() {
    while "loop" {
    }

    for i := 0; "loop"; i++ {
    }

    value := 1
    answer := "maybe" ? 1 : 2
    numbers := [1, "two"]
    label := match value {
        n when "guard" => "positive",
        _ => 12345
    }
    print label
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///control-flow-type-mismatch-spans.nl", source)

    whileCondition := LsdSingle(diagnostics, "TypeMismatch", "'while'")
    LsdAssertSpan(whileCondition, 2, 11, "\"loop\"".Length)
    LsdAssertLspRange(whileCondition, 1, 10, 16)

    forCondition := LsdSingle(diagnostics, "TypeMismatch", "'for'")
    LsdAssertSpan(forCondition, 5, 17, "\"loop\"".Length)
    LsdAssertLspRange(forCondition, 4, 16, 22)

    ternaryCondition := LsdSingle(diagnostics, "TypeMismatch", "ternary expression")
    LsdAssertSpan(ternaryCondition, 9, 15, "\"maybe\"".Length)
    LsdAssertLspRange(ternaryCondition, 8, 14, 21)

    arrayElement := LsdSingle(diagnostics, "TypeMismatch", "All elements in an array")
    LsdAssertSpan(arrayElement, 10, 20, "\"two\"".Length)
    LsdAssertLspRange(arrayElement, 9, 19, 24)

    matchGuard := LsdSingle(diagnostics, "GuardNotBoolean", null)
    LsdAssertSpan(matchGuard, 12, 16, "\"guard\"".Length)
    LsdAssertLspRange(matchGuard, 11, 15, 22)

    matchArm := LsdSingle(diagnostics, "TypeMismatch", "All match arms")
    LsdAssertSpan(matchArm, 13, 14, "12345".Length)
    LsdAssertLspRange(matchArm, 12, 13, 18)
}

test "DocumentManager loop control outside loop uses full keyword spans" {
    source := LsdDecodedSource(
        """
func main() {
    break
    continue
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///loop-control-spans.nl", source)

    breakDiagnostic := LsdSingle(diagnostics, "InvalidSyntax", "'break'")
    LsdAssertSpan(breakDiagnostic, 2, 5, "break".Length)
    LsdAssertLspRange(breakDiagnostic, 1, 4, 9)

    continueDiagnostic := LsdSingle(diagnostics, "InvalidSyntax", "'continue'")
    LsdAssertSpan(continueDiagnostic, 3, 5, "continue".Length)
    LsdAssertLspRange(continueDiagnostic, 2, 4, 12)
}

test "DocumentManager return outside function and targetless default use full keyword spans" {
    source := LsdDecodedSource(
        """
func main() {
    value := default
}

test "does not return" {
    return
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///keyword-semantic-spans.tests.nl", source)

    targetlessDefault := LsdSingle(diagnostics, "CannotInferType", "'default'")
    LsdAssertSpan(targetlessDefault, 2, 14, "default".Length)
    LsdAssertLspRange(targetlessDefault, 1, 13, 20)

    returnOutsideFunction := LsdSingle(diagnostics, "InvalidSyntax", "'return' can only")
    LsdAssertSpan(returnOutsideFunction, 6, 5, "return".Length)
    LsdAssertLspRange(returnOutsideFunction, 5, 4, 10)
}

test "DocumentManager readonly assignment uses assigned field name span" {
    source := LsdDecodedSource(
        """
class Account {
    readonly id: string = "initial"

    func Change() {
        id = "next"
        this.id = "again"
    }
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///readonly-assignment-spans.nl", source)

    directAssignment := LsdSingleAt(diagnostics, "ReadonlyAssignment", null, 5, -1)
    LsdAssertSpan(directAssignment, 5, 9, "id".Length)
    LsdAssertLspRange(directAssignment, 4, 8, 10)

    memberAssignment := LsdSingleAt(diagnostics, "ReadonlyAssignment", null, 6, -1)
    LsdAssertSpan(memberAssignment, 6, 14, "id".Length)
    LsdAssertLspRange(memberAssignment, 5, 13, 15)
}

test "DocumentManager undefined member uses member name span" {
    source := LsdDecodedSource(
        """
func main() {
    print "asdf".ToUp()
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///undefined-member-spans.nl", source),
        "UndefinedMember",
        "ToUp"
    )
    LsdAssertSpan(diagnostic, 2, 18, "ToUp".Length)
    LsdAssertLspRange(diagnostic, 1, 17, 21)
}

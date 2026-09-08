namespace NSharpLang.LanguageServerDiagnostics.Tests

test "DocumentManager publishes invalid member statement and bad call diagnostics" {
    source := LsdLeadingNewlineSource(
        """
func main() {
    greeting := "hello"
    greeting.CompareTo
    greeting.CompareTo()
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///test.nl", source)
    assert LsdContains(diagnostics, "MethodGroupUsedAsValue", null)
    assert LsdContains(diagnostics, "NoMatchingOverload", null)
}

test "DocumentManager NSharp overload error uses callable name span and candidate hints" {
    source := LsdDecodedSource(
        """
class Processor {
    func Process(x: int): int { return x }
    func Process(x: string): string { return x }
}

func main() {
    p := new Processor()
    p.Process(true)
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///nsharp-overload-spans.nl", source),
        "NoMatchingOverload",
        "Process"
    )
    LsdAssertSpan(diagnostic, 8, 7, "Process".Length)
    LsdAssertLspRange(diagnostic, 7, 6, 13)
    hint := LsdFieldText(diagnostic, "ContextualHint")
    assert hint.Contains("Process(x: int): int")
    assert hint.Contains("Process(x: string): string")
}

test "DocumentManager error tuple result requires null error proof" {
    source := LsdDecodedSource(
        """
func Hi(): int {
    return 1
}

func Main() {
    i, err := Hi()
    if err != null {
        print err
    }

    print i
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///error-tuple-result.nl", source),
        "UnverifiedErrorResult",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL314"
    message := LsdFieldText(diagnostic, "Message")
    assert message.Contains("'i'")
    assert message.Contains("'err'")
    LsdAssertSpan(diagnostic, 11, 11, "i".Length)
    LsdAssertLspRange(diagnostic, 10, 10, 11)
}

test "DocumentManager discarded MustUse result underlines callee name" {
    source := LsdDecodedSource(
        """
[MustUse]
func Compute(): int {
    return 42
}

func Main() {
    Compute()
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///discarded-must-use.nl", source),
        "DiscardedMustUseResult",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL315"
    assert LsdFieldText(diagnostic, "Message").Contains("'Compute'")
    LsdAssertSpan(diagnostic, 7, 5, "Compute".Length)
    LsdAssertLspRange(diagnostic, 6, 4, 11)
}

test "DocumentManager undefined bare call reports function rather than variable" {
    source := LsdDecodedSource(
        """
func Main() {
    i := Hi()
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///undefined-bare-call.nl", source)
    diagnostic := LsdSingle(diagnostics, "UndefinedFunction", null)
    assert LsdFieldText(diagnostic, "Message") == "Function 'Hi' not found"
    explanation := LsdFieldText(diagnostic, "HumanExplanation")
    assert explanation.Contains("function named `Hi`")
    assert !LsdContains(diagnostics, "UndefinedVariable", "Hi")
    LsdAssertSpan(diagnostic, 2, 10, "Hi".Length)
    LsdAssertLspRange(diagnostic, 1, 9, 11)
}

test "DocumentManager function call errors underline callee names with exact ranges" {
    source := LsdDecodedSource(
        """
func TakesInt(value: int) {}

func main() {
    TakesInt()
    Unknown()
    TakesInt
}
"""
    )
    diagnostics := LsdCompilerDiagnostics("file:///function-call-spans.nl", source)

    wrongCount := LsdSingle(diagnostics, "WrongArgumentCount", null)
    assert LsdFieldText(wrongCount, "Message") == "Function 'TakesInt' expects 1 argument but got 0"
    LsdAssertSpan(wrongCount, 4, 5, "TakesInt".Length)
    LsdAssertLspRange(wrongCount, 3, 4, 12)

    undefinedFunction := LsdSingle(diagnostics, "UndefinedFunction", null)
    assert LsdFieldText(undefinedFunction, "Message") == "Function 'Unknown' not found"
    LsdAssertSpan(undefinedFunction, 5, 5, "Unknown".Length)
    LsdAssertLspRange(undefinedFunction, 4, 4, 11)

    methodGroup := LsdSingle(diagnostics, "MethodGroupUsedAsValue", null)
    assert LsdFieldText(methodGroup, "Message") == "Method 'TakesInt' must be called or passed to a delegate"
    LsdAssertSpan(methodGroup, 6, 5, "TakesInt".Length)
    LsdAssertLspRange(methodGroup, 5, 4, 12)
}

test "DocumentManager overload error pluralizes argument count" {
    source := LsdDecodedSource(
        """
class Processor {
    func Process(x: int): int { return x }
    func Process(x: string): string { return x }
}

func main() {
    p := new Processor()
    p.Process(true)
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///overload-plural.nl", source),
        "NoMatchingOverload",
        null
    )
    assert LsdFieldText(diagnostic, "Message") == "No overload of 'Process' accepts 1 argument with these types"
    LsdAssertSpan(diagnostic, 8, 7, "Process".Length)
    LsdAssertLspRange(diagnostic, 7, 6, 13)
}

test "DocumentManager shadowed local underlines inner name" {
    source := LsdDecodedSource(
        """
func Main() {
    count := 1
    if count > 0 {
        count := 2
        print $"{count}"
    }
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///shadowing.nl", source),
        "ShadowedDeclaration",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL316"
    assert LsdFieldText(diagnostic, "Message").Contains("'count'")
    LsdAssertSpan(diagnostic, 4, 9, "count".Length)
    LsdAssertLspRange(diagnostic, 3, 8, 13)
}

test "DocumentManager shadowed parameter underlines inner local name" {
    source := LsdDecodedSource(
        """
func Greet(name: string) {
    name := "override"
    print name
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///shadow-param.nl", source),
        "ShadowedDeclaration",
        null
    )
    LsdAssertSpan(diagnostic, 2, 5, "name".Length)
    LsdAssertLspRange(diagnostic, 1, 4, 8)
}

test "DocumentManager read before definite assignment underlines the read" {
    source := LsdDecodedSource(
        """
func Cond(): bool {
    return true
}

func Main() {
    let total: int
    if Cond() {
        total = 5
    }
    print total
}
"""
    )
    diagnostic := LsdSingle(
        LsdCompilerDiagnostics("file:///definite-assignment.nl", source),
        "DefiniteAssignmentError",
        null
    )
    assert LsdPropertyText(diagnostic, "DiagnosticId") == "NL304"
    assert LsdFieldText(diagnostic, "Message").Contains("'total'")
    LsdAssertSpan(diagnostic, 10, 11, "total".Length)
    LsdAssertLspRange(diagnostic, 9, 10, 15)
}

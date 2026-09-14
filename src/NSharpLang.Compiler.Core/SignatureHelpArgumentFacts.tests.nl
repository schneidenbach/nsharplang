namespace NSharpLang.Compiler

test "signature help selects the unmatched outer call after a completed nested call" {
    source := "func main(): void\n    Outer(Build(1, 2), second: "
    context := SignatureHelpArgumentFacts.ActiveCallAtPosition(source, 1, 39)
    assert context != null
    assert context.MethodName == "Outer"
    assert context.ArgumentText == "Build(1, 2), second: "
}

test "signature help call selection ignores parens in strings and comments across lines" {
    source := "func main(): void\n    Outer(\"(\", // ) ignored\n        second: "
    context := SignatureHelpArgumentFacts.ActiveCallAtPosition(source, 2, 16)
    assert context != null
    assert context.MethodName == "Outer"
    assert context.ArgumentText.Contains("second: ", StringComparison.Ordinal)
}

test "signature help recovers generic function and constructor callees" {
    functionContext := SignatureHelpArgumentFacts.ActiveCallAtPosition("func main(): void\n    Choose<int>(second: 2, first: ", 1, 42)
    assert functionContext != null
    assert functionContext.MethodName == "Choose"
    assert !functionContext.IsConstructor

    constructorContext := SignatureHelpArgumentFacts.ActiveCallAtPosition("func main(): void\n    new Box<Result<int, string>>(value: ", 1, 48)
    assert constructorContext != null
    assert constructorContext.MethodName == "Box"
    assert constructorContext.IsConstructor
}

test "signature help follows the parameter named by the current argument" {
    labels := ["numerator: int", "denominator: int"]
    assert SignatureHelpArgumentFacts.ActiveParameterIndex("denominator: 2, numerator: ", labels) == 0
    assert SignatureHelpArgumentFacts.ActiveParameterIndex("numerator: 10, denominator: ", labels) == 1
    assert SignatureHelpArgumentFacts.ActiveParameterIndex("result: ", ["value: int", "result: out int"]) == 1
}

test "signature help uses parser generic disambiguation instead of treating comparisons as type arguments" {
    labels := ["first: bool", "second: int"]
    assert SignatureHelpArgumentFacts.ArgumentCount("a < b, second: ") == 2
    assert SignatureHelpArgumentFacts.ActiveParameterIndex("a < b, second: ", labels) == 1
    assert SignatureHelpArgumentFacts.ArgumentCount("a < b && c > d, second: ") == 2
    assert SignatureHelpArgumentFacts.ArgumentCount("Factory<Result<int, string>>(), second: ") == 2
}

test "signature help ignores commas in object initializers arrays and block lambdas" {
    labels := ["factory: object", "second: int"]
    initializer := "new Config { Values = [1, 2], Name = \"a,b\" }, second: "
    assert SignatureHelpArgumentFacts.ArgumentCount(initializer) == 2
    assert SignatureHelpArgumentFacts.ActiveParameterIndex(initializer, labels) == 1

    blockLambda := "x => { Log(1, 2)\nreturn x }, second: "
    assert SignatureHelpArgumentFacts.ArgumentCount(blockLambda) == 2
    assert SignatureHelpArgumentFacts.ActiveParameterIndex(blockLambda, labels) == 1
}

test "signature help ignores comment and string token contents" {
    labels := ["first: string", "second: int"]
    commented := "first, // ignored, comma\nsecond: "
    assert SignatureHelpArgumentFacts.ArgumentCount(commented) == 2
    assert SignatureHelpArgumentFacts.ActiveParameterIndex(commented, labels) == 1

    assert SignatureHelpArgumentFacts.ArgumentCount("$\"value: {Join(\",\", items)}\", second: ") == 2
    assert SignatureHelpArgumentFacts.ArgumentCount("\"\"\"a,b\"\"\", second: ") == 2
}

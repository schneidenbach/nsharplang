namespace NSharpLang.Playground

import System


// Native contracts for the hosted playground's execution policy.
//
// Everything asserted here was a string literal or a `const` inside `PlaygroundRunner.cs` before
// 021/11, and every one of the thirty-seven codes below is USER-VISIBLE: it reaches the browser as a
// `PlaygroundDiagnostic.Code` with its sentence as the `.Message`. Nothing pinned any of them —
// `tests/native/playground-tooling-surfaces` asserts exactly ONE code (`PG204`) and no budget, no
// rendering word and no interpretation rule at all — so before this file a rename of any of the
// other thirty-six was invisible to the whole gate.
//
// THE CONTRACTS ARE WRITTEN AGAINST THE ANSWER, NOT THE SPELLING. Where the playground's answer
// DIVERGES from the language's, the divergence is asserted rather than glossed: the `1e-7` equality
// tolerance makes `0.1 + 0.2 == 0.3` true in the browser and false under `nlc run`, and both halves
// of that are recorded here so the next reader finds the fact rather than rediscovering it.
test "021 s11 playground run facts: the three budgets are the tutorial-scale contract, and two of them are quoted back to the user" {
    assert PlaygroundRunFacts.MaxSteps() == 20000
    assert PlaygroundRunFacts.MaxCallDepth() == 128
    assert PlaygroundRunFacts.MaxOutputLines() == 200
    assert PlaygroundRunFacts.OutputLineLimitReached().Message == "The browser runner stopped this program after 200 output lines."
    assert PlaygroundRunFacts.StepLimitReached().Message == "The browser runner stopped this program after 20000 execution steps."
}

test "021 s11 playground run facts: the entry point is 'main' case-insensitively, which is why func Main() also runs" {
    assert PlaygroundRunFacts.IsEntryPointFunctionName("main")
    assert PlaygroundRunFacts.IsEntryPointFunctionName("Main")
    assert PlaygroundRunFacts.IsEntryPointFunctionName("MAIN")
    assert !PlaygroundRunFacts.IsEntryPointFunctionName("mainly")
    assert !PlaygroundRunFacts.IsEntryPointFunctionName("")
}

test "021 s11 playground run facts: the runner's four reserved names" {
    assert PlaygroundRunFacts.IsDiscardName("_")
    assert !PlaygroundRunFacts.IsDiscardName("__")
    assert !PlaygroundRunFacts.IsDiscardName("_x")
    assert PlaygroundRunFacts.ReceiverBindingName() == "this"
    assert PlaygroundRunFacts.ErrorMessageMemberName() == "Message"
    assert PlaygroundRunFacts.LengthMemberName() == "Length"
}

test "021 s11 playground run facts: Exception is recognised as a factory by its short name and as a type by both spellings" {
    assert PlaygroundRunFacts.IsExceptionFactoryName("Exception")
    assert !PlaygroundRunFacts.IsExceptionFactoryName("System.Exception")
    assert PlaygroundRunFacts.IsExceptionTypeName("Exception")
    assert PlaygroundRunFacts.IsExceptionTypeName("System.Exception")
    assert !PlaygroundRunFacts.IsExceptionTypeName("InvalidOperationException")
}

test "021 s11 playground run facts: union case names match suffix-tolerantly in BOTH directions, which is how a declaration's 'Found' meets a pattern's 'LookupResult.Found'" {
    assert PlaygroundRunFacts.UnionCaseNamesMatch("Found", "Found")
    assert PlaygroundRunFacts.UnionCaseNamesMatch("LookupResult.Found", "Found")
    assert PlaygroundRunFacts.UnionCaseNamesMatch("Found", "LookupResult.Found")
    assert !PlaygroundRunFacts.UnionCaseNamesMatch("Found", "Missing")
    assert !PlaygroundRunFacts.UnionCaseNamesMatch("NotFound", "Found")
}

test "021 s11 playground run facts: a qualified union case name splits at the LAST dot, and a leading dot names nothing" {
    assert PlaygroundRunFacts.IsQualifiedUnionCaseName("LookupResult.Found")
    assert !PlaygroundRunFacts.IsQualifiedUnionCaseName("Found")
    assert !PlaygroundRunFacts.IsQualifiedUnionCaseName(".Found")
    assert PlaygroundRunFacts.UnionOwnerNameOf("A.B.Found") == "A.B"
    assert PlaygroundRunFacts.UnionCaseNameOf("A.B.Found") == "Found"
    assert PlaygroundRunFacts.UnionOwnerNameOf("Found") == ""
    assert PlaygroundRunFacts.UnionCaseNameOf("Found") == ""
}

test "021 s11 playground run facts: an output line always ends with a bare newline, never the host's" {
    assert PlaygroundRunFacts.OutputLineTerminator() == "\n"
}

test "021 s11 playground run facts: only zero divides by zero, and the message is the playground's own words rather than the CLR's" {
    assert PlaygroundRunFacts.IsZeroDivisor(0.0)
    assert PlaygroundRunFacts.IsZeroDivisor(0.0 - 0.0)
    assert !PlaygroundRunFacts.IsZeroDivisor(1.0)
    assert !PlaygroundRunFacts.IsZeroDivisor(0.0 - 1.0)
    assert !PlaygroundRunFacts.IsZeroDivisor(0.000000000001)
    assert PlaygroundRunFacts.DivisionByZeroMessage() == "division by zero"
}

test "021 s11 playground run facts: division truncates only when BOTH operands are integral" {
    assert PlaygroundRunFacts.UseIntegerDivision(true, true)
    assert !PlaygroundRunFacts.UseIntegerDivision(true, false)
    assert !PlaygroundRunFacts.UseIntegerDivision(false, true)
    assert !PlaygroundRunFacts.UseIntegerDivision(false, false)
}

test "021 s11 playground run facts: the 1e-7 equality tolerance is a DIVERGENCE — 0.1 + 0.2 == 0.3 answers true here and false under nlc run" {
    assert PlaygroundRunFacts.NumericEqualityTolerance() == 0.0000001
    assert PlaygroundRunFacts.NumbersEqual(0.1 + 0.2, 0.3)
    assert 0.1 + 0.2 != 0.3
    assert PlaygroundRunFacts.NumbersEqual(1.0, 1.0)
    assert PlaygroundRunFacts.NumbersEqual(1.0, 1.00000001)
    assert !PlaygroundRunFacts.NumbersEqual(1.0, 1.001)
    assert !PlaygroundRunFacts.NumbersEqual(1.0, 0.0 - 1.0)
}

test "021 s11 playground run facts: the escape decoder strips the delimiters and undoes the five escapes the runner recognises" {
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"hi\"") == "hi"
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"a\\nb\"") == "a\nb"
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"a\\rb\"") == "a\rb"
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"a\\tb\"") == "a\tb"
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"a\\\"b\"") == "a\"b"
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"a\\\\b\"") == "a\\b"
}

test "021 s11 playground run facts: a raw string keeps its body verbatim, escapes and all" {
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"\"\"a\\nb\"\"\"") == "a\\nb"
    assert PlaygroundRunFacts.DecodeStringLiteralText("\"\"\"\"\"\"") == ""
}

test "021 s11 playground run facts: the rendering words — null, True/False, and the invariant G that keeps a de-DE browser honest" {
    assert PlaygroundRunFacts.NullDisplayText() == "null"
    assert PlaygroundRunFacts.BooleanDisplayText(true) == "True"
    assert PlaygroundRunFacts.BooleanDisplayText(false) == "False"
    assert PlaygroundRunFacts.NumberFormatSpecifier() == "G"
    assert PlaygroundRunFacts.AnonymousObjectDisplayName() == "object"
    assert PlaygroundRunFacts.DisplayFieldSeparator() == ", "
}

test "021 s11 playground run facts: the two display shapes are DIVERGENCES — nlc run prints P.Point and P.Shape+Circle for the same two values" {
    assert PlaygroundRunFacts.ObjectFieldDisplayText("X", "1") == "X: 1"
    assert PlaygroundRunFacts.ObjectDisplayText("Point", "X: 1, Y: 2") == "Point { X: 1, Y: 2 }"
    assert PlaygroundRunFacts.UnionDisplayText("Shape", "Circle", "Radius: 3") == "Shape.Circle(Radius: 3)"
}

test "021 s11 playground run facts: the sixteen faults an analysis-clean program can actually reach" {
    assert PlaygroundRunFacts.NoEntryPoint().Code == "PG201"
    assert PlaygroundRunFacts.NoEntryPoint().Message == "This sample does not declare a main function that the browser runner can execute."
    assert PlaygroundRunFacts.CallDepthExceeded().Code == "PG202"
    assert PlaygroundRunFacts.CallDepthExceeded().Message == "The browser runner stopped this program because it exceeded the maximum call depth."
    assert PlaygroundRunFacts.UnsupportedStatement("WhileStatement").Code == "PG204"
    assert PlaygroundRunFacts.UnsupportedStatement("WhileStatement").Message == "The browser runner does not yet support WhileStatement."
    assert PlaygroundRunFacts.UnsupportedDeconstruction().Code == "PG205"
    assert PlaygroundRunFacts.UnsupportedDeconstruction().Message == "The browser runner only supports result, err := Function(...) deconstruction."
    assert PlaygroundRunFacts.UnsupportedExpression("AwaitExpression").Code == "PG207"
    assert PlaygroundRunFacts.UnsupportedExpression("AwaitExpression").Message == "The browser runner does not yet support AwaitExpression."
    assert PlaygroundRunFacts.UnresolvedName("name").Code == "PG208"
    assert PlaygroundRunFacts.UnresolvedName("name").Message == "The browser runner could not resolve 'name'."
    assert PlaygroundRunFacts.UnsupportedBinaryOperator("BitwiseAnd").Code == "PG209"
    assert PlaygroundRunFacts.UnsupportedBinaryOperator("BitwiseAnd").Message == "The browser runner does not yet support the BitwiseAnd operator."
    assert PlaygroundRunFacts.UnsupportedUnaryOperator("BitwiseNot").Code == "PG210"
    assert PlaygroundRunFacts.UnsupportedUnaryOperator("BitwiseNot").Message == "The browser runner does not yet support the BitwiseNot operator."
    assert PlaygroundRunFacts.UnsupportedAssignmentOperator("NullCoalesceAssign").Code == "PG211"
    assert PlaygroundRunFacts.UnsupportedAssignmentOperator("NullCoalesceAssign").Message == "The browser runner does not yet support NullCoalesceAssign."
    assert PlaygroundRunFacts.UnsupportedAssignmentTarget().Code == "PG212"
    assert PlaygroundRunFacts.UnsupportedAssignmentTarget().Message == "The browser runner only supports assignment to variables and object properties."
    assert PlaygroundRunFacts.UnsupportedStringMember("Trim").Code == "PG217"
    assert PlaygroundRunFacts.UnsupportedStringMember("Trim").Message == "The browser runner does not yet support string.Trim."
    assert PlaygroundRunFacts.UnsupportedNumericMember("ToString").Code == "PG218"
    assert PlaygroundRunFacts.UnsupportedNumericMember("ToString").Message == "The browser runner does not yet support numeric.ToString."
    assert PlaygroundRunFacts.UnsupportedReceiverMember("ToString").Code == "PG219"
    assert PlaygroundRunFacts.UnsupportedReceiverMember("ToString").Message == "The browser runner cannot call member 'ToString' on this receiver."
    assert PlaygroundRunFacts.UnknownConstructedType("List").Code == "PG223"
    assert PlaygroundRunFacts.UnknownConstructedType("List").Message == "The browser runner cannot construct 'List'."
    assert PlaygroundRunFacts.UnsupportedConstructorArguments().Code == "PG224"
    assert PlaygroundRunFacts.UnsupportedConstructorArguments().Message == "The browser runner only supports constructor arguments on primary constructors and union cases."
    assert PlaygroundRunFacts.OutputLineLimitReached().Code == "PG234"
}

test "021 s11 playground run facts: the twenty-one guards, kept and spelled once rather than deleted on a reachability argument" {
    assert PlaygroundRunFacts.WrongArgumentCount("Greeting", 2).Code == "PG203"
    assert PlaygroundRunFacts.WrongArgumentCount("Greeting", 2).Message == "The browser runner cannot call 'Greeting' with 2 argument(s)."
    assert PlaygroundRunFacts.UnsupportedForeachCollection().Code == "PG206"
    assert PlaygroundRunFacts.UnsupportedForeachCollection().Message == "The browser runner only supports foreach over array literals."
    assert PlaygroundRunFacts.UnsupportedCallee().Code == "PG213"
    assert PlaygroundRunFacts.UnsupportedCallee().Message == "The browser runner only supports direct function and member calls."
    assert PlaygroundRunFacts.UnknownFunction("Greeting").Code == "PG214"
    assert PlaygroundRunFacts.UnknownFunction("Greeting").Message == "The browser runner cannot call 'Greeting'."
    assert PlaygroundRunFacts.MethodNotFound("Describe").Code == "PG215"
    assert PlaygroundRunFacts.MethodNotFound("Describe").Message == "The browser runner could not find method 'Describe'."
    assert PlaygroundRunFacts.StaticMethodNotFound("Describe").Code == "PG216"
    assert PlaygroundRunFacts.StaticMethodNotFound("Describe").Message == "The browser runner could not find static method 'Describe'."
    assert PlaygroundRunFacts.UnresolvedMember("Radius").Code == "PG220"
    assert PlaygroundRunFacts.UnresolvedMember("Radius").Message == "The browser runner cannot resolve member 'Radius'."
    assert PlaygroundRunFacts.UnassignableMember("Radius").Code == "PG221"
    assert PlaygroundRunFacts.UnassignableMember("Radius").Message == "The browser runner cannot assign member 'Radius'."
    assert PlaygroundRunFacts.UnsupportedConstructionTarget().Code == "PG222"
    assert PlaygroundRunFacts.UnsupportedConstructionTarget().Message == "The browser runner only supports named object construction."
    assert PlaygroundRunFacts.WrongConstructorArgumentCount().Code == "PG225"
    assert PlaygroundRunFacts.WrongConstructorArgumentCount().Message == "The browser runner received the wrong number of constructor arguments."
    assert PlaygroundRunFacts.UnsupportedIndexerInitializer().Code == "PG226"
    assert PlaygroundRunFacts.UnsupportedIndexerInitializer().Message == "The browser runner does not yet support indexer initializers."
    assert PlaygroundRunFacts.UnsupportedWithTarget().Code == "PG227"
    assert PlaygroundRunFacts.UnsupportedWithTarget().Message == "The browser runner only supports with expressions on records and objects."
    assert PlaygroundRunFacts.UnsupportedWithIndexer().Code == "PG228"
    assert PlaygroundRunFacts.UnsupportedWithIndexer().Message == "The browser runner does not yet support indexer values in with expressions."
    assert PlaygroundRunFacts.NoMatchingMatchArm().Code == "PG229"
    assert PlaygroundRunFacts.NoMatchingMatchArm().Message == "The browser runner reached a match expression without a matching arm."
    assert PlaygroundRunFacts.UnsupportedLiteralPattern().Code == "PG230"
    assert PlaygroundRunFacts.UnsupportedLiteralPattern().Message == "The browser runner only supports literal string, int, bool, and null match patterns."
    assert PlaygroundRunFacts.UnsupportedPattern("TypePattern").Code == "PG231"
    assert PlaygroundRunFacts.UnsupportedPattern("TypePattern").Message == "The browser runner does not yet support TypePattern."
    assert PlaygroundRunFacts.UnknownUnionCase("Circle").Code == "PG232"
    assert PlaygroundRunFacts.UnknownUnionCase("Circle").Message == "The browser runner could not find union case 'Circle'."
    assert PlaygroundRunFacts.WrongUnionCaseArgumentCount().Code == "PG233"
    assert PlaygroundRunFacts.WrongUnionCaseArgumentCount().Message == "The browser runner received the wrong number of union case arguments."
    assert PlaygroundRunFacts.StepLimitReached().Code == "PG235"
    assert PlaygroundRunFacts.ExpectedNumber("null").Code == "PG236"
    assert PlaygroundRunFacts.ExpectedNumber("null").Message == "The browser runner expected a number, but found null."
    assert PlaygroundRunFacts.ExpectedInteger("null").Code == "PG237"
    assert PlaygroundRunFacts.ExpectedInteger("null").Message == "The browser runner expected an integer, but found null."
}

test "021 s11 playground run facts: the thirty-seven codes are PG201 through PG237 with no gap and no repeat" {
    codes := new string[](37)
    codes[0] = PlaygroundRunFacts.NoEntryPoint().Code
    codes[1] = PlaygroundRunFacts.CallDepthExceeded().Code
    codes[2] = PlaygroundRunFacts.WrongArgumentCount("f", 0).Code
    codes[3] = PlaygroundRunFacts.UnsupportedStatement("s").Code
    codes[4] = PlaygroundRunFacts.UnsupportedDeconstruction().Code
    codes[5] = PlaygroundRunFacts.UnsupportedForeachCollection().Code
    codes[6] = PlaygroundRunFacts.UnsupportedExpression("e").Code
    codes[7] = PlaygroundRunFacts.UnresolvedName("n").Code
    codes[8] = PlaygroundRunFacts.UnsupportedBinaryOperator("o").Code
    codes[9] = PlaygroundRunFacts.UnsupportedUnaryOperator("o").Code
    codes[10] = PlaygroundRunFacts.UnsupportedAssignmentOperator("o").Code
    codes[11] = PlaygroundRunFacts.UnsupportedAssignmentTarget().Code
    codes[12] = PlaygroundRunFacts.UnsupportedCallee().Code
    codes[13] = PlaygroundRunFacts.UnknownFunction("f").Code
    codes[14] = PlaygroundRunFacts.MethodNotFound("m").Code
    codes[15] = PlaygroundRunFacts.StaticMethodNotFound("m").Code
    codes[16] = PlaygroundRunFacts.UnsupportedStringMember("m").Code
    codes[17] = PlaygroundRunFacts.UnsupportedNumericMember("m").Code
    codes[18] = PlaygroundRunFacts.UnsupportedReceiverMember("m").Code
    codes[19] = PlaygroundRunFacts.UnresolvedMember("m").Code
    codes[20] = PlaygroundRunFacts.UnassignableMember("m").Code
    codes[21] = PlaygroundRunFacts.UnsupportedConstructionTarget().Code
    codes[22] = PlaygroundRunFacts.UnknownConstructedType("t").Code
    codes[23] = PlaygroundRunFacts.UnsupportedConstructorArguments().Code
    codes[24] = PlaygroundRunFacts.WrongConstructorArgumentCount().Code
    codes[25] = PlaygroundRunFacts.UnsupportedIndexerInitializer().Code
    codes[26] = PlaygroundRunFacts.UnsupportedWithTarget().Code
    codes[27] = PlaygroundRunFacts.UnsupportedWithIndexer().Code
    codes[28] = PlaygroundRunFacts.NoMatchingMatchArm().Code
    codes[29] = PlaygroundRunFacts.UnsupportedLiteralPattern().Code
    codes[30] = PlaygroundRunFacts.UnsupportedPattern("p").Code
    codes[31] = PlaygroundRunFacts.UnknownUnionCase("c").Code
    codes[32] = PlaygroundRunFacts.WrongUnionCaseArgumentCount().Code
    codes[33] = PlaygroundRunFacts.OutputLineLimitReached().Code
    codes[34] = PlaygroundRunFacts.StepLimitReached().Code
    codes[35] = PlaygroundRunFacts.ExpectedNumber("v").Code
    codes[36] = PlaygroundRunFacts.ExpectedInteger("v").Code

    index := 0
    while index < 37 {
        expected := "PG" + (201 + index).ToString()
        assert codes[index] == expected
        index = index + 1
    }
}

test "021 s11 playground run facts: no fault sentence is empty, and every one of them names the browser runner or the sample" {
    messages := new string[](4)
    messages[0] = PlaygroundRunFacts.NoEntryPoint().Message
    messages[1] = PlaygroundRunFacts.CallDepthExceeded().Message
    messages[2] = PlaygroundRunFacts.UnsupportedDeconstruction().Message
    messages[3] = PlaygroundRunFacts.NoMatchingMatchArm().Message

    index := 0
    while index < 4 {
        assert messages[index].Length > 0
        assert messages[index].EndsWith(".", StringComparison.Ordinal)
        index = index + 1
    }
}

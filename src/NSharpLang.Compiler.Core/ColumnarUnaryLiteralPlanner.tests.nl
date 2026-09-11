namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler

func ColumnarUnaryPlannerTree(
    operatorText: string,
    operandKind: int,
    operandText: string
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    operatorStart := builder.AddToken(operatorText)
    operand := builder.AddLeaf(operandKind, operandText)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        operatorStart,
        operatorText.Length,
        operatorStart,
        operatorText.Length + operandText.Length,
        ColumnarRangePlannerChildren1(operand)
    )
    return builder.Build(root)
}

func ColumnarUnaryPlannerPlan(
    operatorText: string,
    operandKind: int,
    operandText: string
): ColumnarCodePlan {
    tree := ColumnarUnaryPlannerTree(operatorText, operandKind, operandText)
    plan := new ColumnarCodePlan()
    assert ColumnarUnaryLiteralPlanner.Plan(tree.Nodes, tree.Source, tree.Root, plan) == ColumnarFragmentPlanStatus.Planned
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ColumnarUnaryPlannerDeclines(
    operatorText: string,
    operandKind: int,
    operandText: string
) {
    tree := ColumnarUnaryPlannerTree(operatorText, operandKind, operandText)
    plan := new ColumnarCodePlan()
    assert ColumnarUnaryLiteralPlanner.Plan(tree.Nodes, tree.Source, tree.Root, plan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(plan)
}

func ColumnarUnaryPlannerFromEndNegative(operandText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    caretStart := builder.AddToken("^")
    minusStart := builder.AddToken("-")
    operand := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), operandText)
    negativeOne := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        minusStart,
        1,
        minusStart,
        1 + operandText.Length,
        ColumnarRangePlannerChildren1(operand)
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caretStart,
        1,
        caretStart,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(negativeOne)
    )
    return builder.Build(root)
}

func ColumnarUnaryPlannerFlattenedIdentifier(prefix: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    caretStart := builder.AddToken("^")
    spanStart := builder.AddToken(prefix)
    valueStart := builder.AddToken("count")
    identifier := builder.AddNode(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        valueStart,
        5,
        spanStart,
        prefix.Length + 5,
        new int[](0)
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caretStart,
        1,
        caretStart,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(identifier)
    )
    return builder.Build(root)
}

test "unary literal planner owns the exact Int32 minimum through unchecked negate" {
    intMinimum := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "2147483648"
    )
    assert intMinimum.ResultType == typeof(int)
    assert intMinimum.FragmentCount == 2
    assert intMinimum.OperationCount == 2
    assert intMinimum.Int32Values[intMinimum.OperandIndices[0]] == -2147483648
    assert intMinimum.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert intMinimum.OpCodeValues[1] == ColumnarCodePlanContract.Neg()

    separatedMinimum := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "2_147_483_648"
    )
    assert separatedMinimum.Int32Values[separatedMinimum.OperandIndices[0]] == -2147483648

    hexadecimalMinimum := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "0x80000000"
    )
    assert hexadecimalMinimum.Int32Values[hexadecimalMinimum.OperandIndices[0]] == -2147483648

    binaryMinimum := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "0b10000000000000000000000000000000"
    )
    assert binaryMinimum.Int32Values[binaryMinimum.OperandIndices[0]] == -2147483648
}

test "unary literal planner owns negate complement and logical-not families" {
    negativeInt := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "42"
    )
    assert negativeInt.ResultType == typeof(int)
    assert negativeInt.OpCodeValues[1] == ColumnarCodePlanContract.Neg()

    negativeDouble := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "1.25"
    )
    assert negativeDouble.ResultType == typeof(double)
    assert negativeDouble.OpCodeValues[1] == ColumnarCodePlanContract.Neg()

    negativeLong := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1L"
    )
    assert negativeLong.ResultType == typeof(long)
    assert negativeLong.OpCodeValues[1] == ColumnarCodePlanContract.Neg()

    negativeSingle := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "1.25f"
    )
    assert negativeSingle.ResultType == typeof(float)
    assert negativeSingle.OpCodeValues[1] == ColumnarCodePlanContract.Neg()

    complementLong := ColumnarUnaryPlannerPlan(
        "~",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1L"
    )
    assert complementLong.ResultType == typeof(long)
    assert complementLong.OpCodeValues[1] == ColumnarCodePlanContract.Not()

    complementUnsigned := ColumnarUnaryPlannerPlan(
        "~",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "0UL"
    )
    assert complementUnsigned.ResultType == typeof(ulong)
    assert complementUnsigned.OpCodeValues[1] == ColumnarCodePlanContract.Not()

    logicalNot := ColumnarUnaryPlannerPlan(
        "!",
        ColumnarExpressionNodeKind.BoolLiteralExpression(),
        "true"
    )
    assert logicalNot.ResultType == typeof(bool)
    assert logicalNot.OperationCount == 3
    assert logicalNot.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_0()
    assert logicalNot.OpCodeValues[2] == ColumnarCodePlanContract.Ceq()

    // Decimal negation is not an IL neg: the planner closes it through the exact
    // System.Decimal.op_UnaryNegation static, mirroring the legacy unary arm.
    negativeDecimal := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "1.25m"
    )
    assert negativeDecimal.ResultType == typeof(decimal)
    assert negativeDecimal.MethodCount == 1
    assert negativeDecimal.MethodUsesDeclaredSignature[0]
    negationMethod := negativeDecimal.Methods[0]
    assert negationMethod.get_DeclaringType() == typeof(decimal)
    assert negationMethod.get_Name() == "op_UnaryNegation"
    assert negativeDecimal.MethodParameterTypes[0].Length == 1
    assert negativeDecimal.MethodParameterTypes[0][0] == typeof(decimal)
    assert negativeDecimal.MethodReturnTypes[0] == typeof(decimal)

    negativeIntegerFormDecimal := ColumnarUnaryPlannerPlan(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "5m"
    )
    assert negativeIntegerFormDecimal.ResultType == typeof(decimal)
    assert negativeIntegerFormDecimal.MethodCount == 1
    assert negativeIntegerFormDecimal.Methods[0].get_Name() == "op_UnaryNegation"
}

test "unary literal planner executes every admitted opcode through DynamicMethod" {
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            "42"
        ),
        typeof(int)
    ) == "-42"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.FloatLiteralExpression(),
            "1.25"
        ),
        typeof(double)
    ) == "-1.25"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            "1L"
        ),
        typeof(long)
    ) == "-1"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.FloatLiteralExpression(),
            "1.25f"
        ),
        typeof(float)
    ) == "-1.25"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "~",
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            "0"
        ),
        typeof(int)
    ) == "-1"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "~",
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            "1L"
        ),
        typeof(long)
    ) == "-2"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "!",
            ColumnarExpressionNodeKind.BoolLiteralExpression(),
            "true"
        ),
        typeof(bool)
    ) == "False"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            "2147483648"
        ),
        typeof(int)
    ) == "-2147483648"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.FloatLiteralExpression(),
            "1.25m"
        ),
        typeof(decimal)
    ) == "-1.25"
    assert ExecutorRunV3ScalarPlan(
        ColumnarUnaryPlannerPlan(
            "-",
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            "5m"
        ),
        typeof(decimal)
    ) == "-5"
}

test "unary literal planner declines unsupported operators types and spellings atomically" {
    ColumnarUnaryPlannerDeclines(
        "+",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1"
    )
    ColumnarUnaryPlannerDeclines(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1UL"
    )
    ColumnarUnaryPlannerDeclines(
        "~",
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "1.0"
    )
    ColumnarUnaryPlannerDeclines(
        "!",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1"
    )
    ColumnarUnaryPlannerDeclines(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "9223372036854775808L"
    )
    ColumnarUnaryPlannerDeclines(
        "-",
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "not-a-decimal-m"
    )
    ColumnarUnaryPlannerDeclines(
        "-",
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "9223372036854775808LL"
    )

    malformedBuilder := new ColumnarRangePlannerNodeBuilder()
    malformedStart := malformedBuilder.AddToken("-")
    malformedRoot := malformedBuilder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        malformedStart,
        1,
        malformedStart,
        1,
        new int[](0)
    )
    malformed := malformedBuilder.Build(malformedRoot)
    malformedPlan := new ColumnarCodePlan()
    assert ColumnarUnaryLiteralPlanner.Plan(
        malformed.Nodes,
        malformed.Source,
        malformed.Root,
        malformedPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(malformedPlan)

    magnitude := 1UL
    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("0x", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("0b", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("0o", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(
        "18446744073709551616",
        out magnitude
    )
    assert magnitude == 0UL
}

test "range planner recursively consumes negative literals and rolls invalid endpoint types back" {
    tree := ColumnarUnaryPlannerFromEndNegative("1")
    plan := ColumnarRangePlannerPlan(tree, ColumnarRangePlannerEmptyBindings())
    assert plan.ResultType == typeof(Index)
    assert plan.FragmentCount == 3
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Neg()

    longTree := ColumnarUnaryPlannerFromEndNegative("1L")
    longPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        longTree.Nodes,
        longTree.Source,
        longTree.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        longPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(longPlan)
}

test "range planner never binds flattened explicit-this syntax as a bare value" {
    explicitThis := ColumnarUnaryPlannerFlattenedIdentifier("this.")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "count", 0, typeof(int))
    rejected := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        explicitThis.Nodes,
        explicitThis.Source,
        explicitThis.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        rejected
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(rejected)

    spacedBeforeDot := ColumnarUnaryPlannerFlattenedIdentifier("this .")
    spacedBeforeDotPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        spacedBeforeDot.Nodes,
        spacedBeforeDot.Source,
        spacedBeforeDot.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        spacedBeforeDotPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(spacedBeforeDotPlan)

    spacedAfterDot := ColumnarUnaryPlannerFlattenedIdentifier("this. ")
    spacedAfterDotPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        spacedAfterDot.Nodes,
        spacedAfterDot.Source,
        spacedAfterDot.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        spacedAfterDotPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(spacedAfterDotPlan)

    commentTrivia := ColumnarUnaryPlannerFlattenedIdentifier("this /* field */ . ")
    commentTriviaPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        commentTrivia.Nodes,
        commentTrivia.Source,
        commentTrivia.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        commentTriviaPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(commentTriviaPlan)

    bare := ColumnarRangePlannerFromEndIdentifier("count")
    barePlan := ColumnarRangePlannerPlan(bare, bindings)
    assert barePlan.ResultType == typeof(Index)

    nonPrefix := ColumnarUnaryPlannerFlattenedIdentifier("that.")
    nonPrefixPlan := ColumnarRangePlannerPlan(nonPrefix, bindings)
    assert nonPrefixPlan.ResultType == typeof(Index)
}

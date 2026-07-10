namespace NSharpLang.Compiler.Columnar

import System

public class ColumnarScalarPlannerTestTree {
    public Nodes: ColumnarNodeTable
    public Source: string
    public Root: int

    constructor(nodes: ColumnarNodeTable, source: string, root: int) {
        Nodes = nodes
        Source = source
        Root = root
    }
}

func ColumnarScalarPlannerRawTree(
    kind: int,
    text: string,
    childCount: int,
    valueStart: int,
    valueLength: int): ColumnarScalarPlannerTestTree {
    kinds := new int[](1)
    kinds[0] = kind
    valueStarts := new int[](1)
    valueStarts[0] = valueStart
    valueLengths := new int[](1)
    valueLengths[0] = valueLength
    childStarts := new int[](1)
    childStarts[0] = 0
    childCounts := new int[](1)
    childCounts[0] = childCount
    children := new int[](childCount)
    spanStarts := new int[](1)
    spanStarts[0] = 0
    spanLengths := new int[](1)
    spanLengths[0] = text.Length
    nodes := new ColumnarNodeTable(
        kinds,
        valueStarts,
        valueLengths,
        childStarts,
        childCounts,
        children,
        spanStarts,
        spanLengths)
    return new ColumnarScalarPlannerTestTree(nodes, text, 0)
}

func ColumnarScalarPlannerTree(kind: int, text: string): ColumnarScalarPlannerTestTree {
    return ColumnarScalarPlannerRawTree(kind, text, 0, 0, text.Length)
}

func ColumnarScalarPlannerTreeWithChild(
    kind: int,
    text: string): ColumnarScalarPlannerTestTree {
    return ColumnarScalarPlannerRawTree(kind, text, 1, 0, text.Length)
}

func ColumnarScalarPlannerTreeWithSpan(
    kind: int,
    text: string,
    valueStart: int,
    valueLength: int): ColumnarScalarPlannerTestTree {
    return ColumnarScalarPlannerRawTree(kind, text, 0, valueStart, valueLength)
}

func ColumnarScalarPlannerPlan(tree: ColumnarScalarPlannerTestTree): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    status := ColumnarScalarLiteralPlanner.Plan(tree.Nodes, tree.Source, tree.Root, plan)
    if status != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected scalar-literal planner ownership.")
    }
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ColumnarScalarPlannerAssertEmpty(plan: ColumnarCodePlan) {
    assert plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Building
    assert plan.OperationCount == 0
    assert plan.FragmentCount == 0
    assert plan.TypeCount == 0
    assert plan.Int32Count == 0
    assert plan.Int64Count == 0
    assert plan.SingleCount == 0
    assert plan.DoubleCount == 0
    assert plan.StringCount == 0
    assert plan.ArgumentCount == 0
    assert plan.AmbientLocalCount == 0
    assert plan.MethodCount == 0
    assert plan.ConstructorCount == 0
    assert plan.FieldCount == 0
    assert plan.PlanLocalCount == 0
    assert plan.LabelCount == 0
}

func ColumnarScalarPlannerAssertInt32(text: string, expected: int) {
    tree := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.IntLiteralExpression(), text)
    plan := ColumnarScalarPlannerPlan(tree)
    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 1
    assert plan.FragmentCount == 1
    assert plan.Int32Count == 1
    assert plan.Int64Count == 0
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[0]] == expected
}

func ColumnarScalarPlannerAssertInt64(text: string, expected: long, resultType: Type) {
    tree := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.IntLiteralExpression(), text)
    plan := ColumnarScalarPlannerPlan(tree)
    assert plan.ResultType == resultType
    assert plan.OperationCount == 1
    assert plan.FragmentCount == 1
    assert plan.Int32Count == 0
    assert plan.Int64Count == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI8()
    assert plan.Int64Values[plan.OperandIndices[0]] == expected
}

func ColumnarScalarPlannerDeclines(kind: int, text: string) {
    tree := ColumnarScalarPlannerTree(kind, text)
    plan := new ColumnarCodePlan()
    assert ColumnarScalarLiteralPlanner.Plan(tree.Nodes, tree.Source, tree.Root, plan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(plan)
}

func ColumnarScalarPlannerEscapedChar(code: string): string {
    return "'" + "\\" + code + "'"
}

func ColumnarScalarPlannerTryAppend(
    tree: ColumnarScalarPlannerTestTree,
    plan: ColumnarCodePlan): bool {
    resultType := typeof(int)
    return ColumnarScalarLiteralPlanner.TryAppendLiteral(
        tree.Nodes, tree.Source, tree.Root, plan, out resultType)
}

test "scalar literal planner owns exact integer families and bit patterns" {
    ColumnarScalarPlannerAssertInt32("0", 0)
    ColumnarScalarPlannerAssertInt32("2147483647", 2147483647)
    ColumnarScalarPlannerAssertInt32("1_0", 10)
    ColumnarScalarPlannerAssertInt32("0x7fff_ffff", 2147483647)
    ColumnarScalarPlannerAssertInt32("0b1010_0101", 165)

    ColumnarScalarPlannerAssertInt64("7l", 7L, typeof(long))
    ColumnarScalarPlannerAssertInt64(
        "9223372036854775807L", 9223372036854775807L, typeof(long))
    ColumnarScalarPlannerAssertInt64("7uL", 7L, typeof(ulong))
    ColumnarScalarPlannerAssertInt64("9223372036854775808Lu", -9223372036854775808L, typeof(ulong))
    ColumnarScalarPlannerAssertInt64("18446744073709551615UL", -1L, typeof(ulong))
}

test "scalar literal planner decodes every admitted character escape" {
    direct := ColumnarScalarPlannerPlan(
        ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.CharLiteralExpression(), "'x'"))
    assert direct.ResultType == typeof(char)
    assert direct.Int32Values[direct.OperandIndices[0]] == (int)'x'

    codes := new string[](11)
    codes[0] = "'"
    codes[1] = "\""
    codes[2] = "\\"
    codes[3] = "0"
    codes[4] = "a"
    codes[5] = "b"
    codes[6] = "f"
    codes[7] = "n"
    codes[8] = "r"
    codes[9] = "t"
    codes[10] = "v"
    expected := new int[](11)
    expected[0] = (int)'\''
    expected[1] = (int)'"'
    expected[2] = (int)'\\'
    expected[3] = (int)'\0'
    expected[4] = (int)'\a'
    expected[5] = (int)'\b'
    expected[6] = (int)'\f'
    expected[7] = (int)'\n'
    expected[8] = (int)'\r'
    expected[9] = (int)'\t'
    expected[10] = (int)'\v'

    i := 0
    while i < codes.Length {
        plan := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
            ColumnarExpressionNodeKind.CharLiteralExpression(),
            ColumnarScalarPlannerEscapedChar(codes[i])))
        assert plan.ResultType == typeof(char)
        assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
        assert plan.Int32Values[plan.OperandIndices[0]] == expected[i]
        i = i + 1
    }
}

test "scalar literal planner decodes ordinary strings and preserves triple strings" {
    quote := "\""
    empty := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(), quote + quote))
    assert empty.ResultType == typeof(string)
    assert empty.StringValues[empty.OperandIndices[0]] == ""

    ordinaryText := quote + "line\\nquote\\\"slash\\\\" + quote
    ordinary := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(), ordinaryText))
    assert ordinary.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert ordinary.StringValues[ordinary.OperandIndices[0]] == "line\nquote\"slash\\"

    triple := quote + quote + quote
    rawText := triple + "slash\\n" + triple
    raw := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(), rawText))
    assert raw.StringValues[raw.OperandIndices[0]] == "slash\\n"
}

test "scalar literal planner facades report the sealed exact type" {
    tree := ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "9223372036854775807L")
    plan := new ColumnarCodePlan()
    resultType := typeof(int)
    assert ColumnarScalarLiteralPlanner.TryGetType(
        tree.Nodes, tree.Source, tree.Root, plan, out resultType)
    assert resultType == typeof(long)
    assert plan.ResultType == typeof(long)
    assert plan.Status == ColumnarFragmentPlanStatus.Planned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
}

test "scalar literal planner rejects excluded and malformed literal families without mutation" {
    invalidIntegers := new string[](14)
    invalidIntegers[0] = ""
    invalidIntegers[1] = "2147483648"
    invalidIntegers[2] = "9223372036854775808L"
    invalidIntegers[3] = "18446744073709551616UL"
    invalidIntegers[4] = "1U"
    invalidIntegers[5] = "1LL"
    invalidIntegers[6] = "1UU"
    invalidIntegers[7] = "1ULU"
    invalidIntegers[8] = "0x"
    invalidIntegers[9] = "0x_FF"
    invalidIntegers[10] = "0b2"
    invalidIntegers[11] = "-1"
    invalidIntegers[12] = "1.0"
    invalidIntegers[13] = "_1"
    i := 0
    while i < invalidIntegers.Length {
        ColumnarScalarPlannerDeclines(
            ColumnarExpressionNodeKind.IntLiteralExpression(), invalidIntegers[i])
        i = i + 1
    }

    invalidChars := new string[](6)
    invalidChars[0] = "''"
    invalidChars[1] = "'ab'"
    invalidChars[2] = ColumnarScalarPlannerEscapedChar("u")
    invalidChars[3] = ColumnarScalarPlannerEscapedChar("q")
    invalidChars[4] = "'\\'"
    invalidChars[5] = "x"
    i = 0
    while i < invalidChars.Length {
        ColumnarScalarPlannerDeclines(
            ColumnarExpressionNodeKind.CharLiteralExpression(), invalidChars[i])
        i = i + 1
    }

    quote := "\""
    triple := quote + quote + quote
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(), "$" + quote + "x" + quote)
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(), "$" + triple + "x" + triple)
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(), quote + "unterminated")
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(), triple + "short")

    ColumnarScalarPlannerDeclines(ColumnarExpressionNodeKind.FloatLiteralExpression(), "1.25")
    ColumnarScalarPlannerDeclines(ColumnarExpressionNodeKind.FloatLiteralExpression(), "1m")
    ColumnarScalarPlannerDeclines(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    ColumnarScalarPlannerDeclines(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true")
}

test "scalar literal planner rolls malformed table shapes back exactly" {
    childTree := ColumnarScalarPlannerTreeWithChild(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "7")
    childPlan := new ColumnarCodePlan()
    assert ColumnarScalarLiteralPlanner.Plan(
        childTree.Nodes, childTree.Source, childTree.Root, childPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(childPlan)

    badStart := ColumnarScalarPlannerTreeWithSpan(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "7", -1, 1)
    badStartPlan := new ColumnarCodePlan()
    assert ColumnarScalarLiteralPlanner.Plan(
        badStart.Nodes, badStart.Source, badStart.Root, badStartPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(badStartPlan)

    badLength := ColumnarScalarPlannerTreeWithSpan(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "7", 0, 2)
    badLengthPlan := new ColumnarCodePlan()
    assert ColumnarScalarLiteralPlanner.Plan(
        badLength.Nodes, badLength.Source, badLength.Root, badLengthPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(badLengthPlan)
}

test "scalar literal recursive append is atomic and enforces schema lifecycle" {
    valid := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.IntLiteralExpression(), "7")
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    resultType := typeof(string)
    assert ColumnarScalarLiteralPlanner.TryAppendLiteral(
        valid.Nodes, valid.Source, valid.Root, plan, out resultType)
    assert resultType == typeof(int)
    assert plan.OperationCount == 1
    assert plan.Int32Count == 1
    plan.CompleteFragment(fragment, resultType)
    plan.CompleteV3(resultType)
    ColumnarCodePlanExecutor.Validate(plan)

    malformed := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.IntLiteralExpression(), "1U")
    atomic := new ColumnarCodePlan()
    atomic.PrepareV3()
    atomic.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    existing := atomic.AddInt32(99)
    atomic.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), existing)
    assert !ColumnarScalarPlannerTryAppend(malformed, atomic)
    assert atomic.OperationCount == 1
    assert atomic.Int32Count == 1
    assert atomic.Int32Values[0] == 99

    v2 := new ColumnarCodePlan()
    v2.PrepareV2()
    v2.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    assert throws InvalidOperationException { ColumnarScalarPlannerTryAppend(valid, v2) }

    closed := new ColumnarCodePlan()
    closed.PrepareV3()
    closedFragment := closed.BeginFragment(
        -1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    closed.CompleteFragment(closedFragment, typeof(int))
    assert throws InvalidOperationException { ColumnarScalarPlannerTryAppend(valid, closed) }
}

test "scalar literal planner validates nulls and root indices before mutation" {
    tree := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.Plan(null, tree.Source, tree.Root, new ColumnarCodePlan())
    }
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.Plan(tree.Nodes, null, tree.Root, new ColumnarCodePlan())
    }
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.Plan(tree.Nodes, tree.Source, tree.Root, null)
    }
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.Plan(tree.Nodes, tree.Source, -1, new ColumnarCodePlan())
    }
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.Plan(tree.Nodes, tree.Source, 1, new ColumnarCodePlan())
    }
}

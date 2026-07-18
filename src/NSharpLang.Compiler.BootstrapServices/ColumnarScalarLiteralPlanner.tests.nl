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

func ColumnarScalarPlannerAssertDouble(text: string, expected: double) {
    tree := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.FloatLiteralExpression(), text)
    plan := ColumnarScalarPlannerPlan(tree)
    assert plan.ResultType == typeof(double)
    assert plan.OperationCount == 1
    assert plan.FragmentCount == 1
    assert plan.SingleCount == 0
    assert plan.DoubleCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcR8()
    assert plan.DoubleValues[plan.OperandIndices[0]] == expected
}

func ColumnarScalarPlannerAssertSingle(text: string, expected: float) {
    tree := ColumnarScalarPlannerTree(ColumnarExpressionNodeKind.FloatLiteralExpression(), text)
    plan := ColumnarScalarPlannerPlan(tree)
    assert plan.ResultType == typeof(float)
    assert plan.OperationCount == 1
    assert plan.FragmentCount == 1
    assert plan.SingleCount == 1
    assert plan.DoubleCount == 0
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcR4()
    assert plan.SingleValues[plan.OperandIndices[0]] == expected
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
    ColumnarScalarPlannerAssertInt64("9223372036854775808Lu", long.MinValue, typeof(ulong))
    ColumnarScalarPlannerAssertInt64("18446744073709551615UL", -1L, typeof(ulong))
}

test "scalar literal planner owns invariant double and single families" {
    ColumnarScalarPlannerAssertDouble("0.0", 0.0)
    ColumnarScalarPlannerAssertDouble("1.25", 1.25)
    ColumnarScalarPlannerAssertDouble("1.25d", 1.25)
    ColumnarScalarPlannerAssertDouble("1.25D", 1.25)
    ColumnarScalarPlannerAssertDouble("1_2.5_0", 12.5)
    ColumnarScalarPlannerAssertDouble("6.25e-1", 0.625)
    ColumnarScalarPlannerAssertDouble("6.25E+1", 62.5)
    ColumnarScalarPlannerAssertDouble(" 1.25 ", 1.25)

    ColumnarScalarPlannerAssertSingle("0.0f", 0.0f)
    ColumnarScalarPlannerAssertSingle("1.25f", 1.25f)
    ColumnarScalarPlannerAssertSingle("1.25F", 1.25f)
    ColumnarScalarPlannerAssertSingle("1_2.5_0f", 12.5f)
    ColumnarScalarPlannerAssertSingle("6.25e-1F", 0.625f)
    ColumnarScalarPlannerAssertSingle("1.0000000596046448f", 1.0f)
    ColumnarScalarPlannerAssertSingle("16777217.0f", 16777216.0f)
}

func ColumnarScalarPlannerAssertDecimal(kind: int, text: string, expected: decimal) {
    tree := ColumnarScalarPlannerTree(kind, text)
    plan := ColumnarScalarPlannerPlan(tree)
    assert plan.ResultType == typeof(decimal)
    // Five ldc.i4 words (lo, mid, high, sign, scale) plus the canonical bits constructor.
    assert plan.OperationCount == 6
    assert plan.FragmentCount == 1
    assert plan.Int32Count == 5
    assert plan.ConstructorCount == 1
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Newobj()
    bitsConstructor := plan.Constructors[0]
    assert bitsConstructor.get_DeclaringType() == typeof(decimal)
    bitsParameters := bitsConstructor.GetParameters()
    assert bitsParameters.Length == 5
    assert bitsParameters[0].get_ParameterType() == typeof(int)
    assert bitsParameters[1].get_ParameterType() == typeof(int)
    assert bitsParameters[2].get_ParameterType() == typeof(int)
    assert bitsParameters[3].get_ParameterType() == typeof(bool)
    assert bitsParameters[4].get_ParameterType() == typeof(byte)
    assert ExecutorRunV3ScalarPlan(plan, typeof(decimal)) == expected.ToString()
}

test "scalar literal planner owns integer and fractional decimal literals" {
    // `5m` arrives as an Int literal token; `2.5m` as a Float literal token. Both lower to the
    // exact legacy shape: ldc.i4 x5 + newobj Decimal(int, int, int, bool, byte).
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "5m", 5m)
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "5M", 5m)
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "2.5m", 2.5m)
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "24.5m", 24.5m)
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1_000.2_5m", 1000.25m)
    // The scale survives exactly: 5.00m prints its two fractional digits.
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "5.00m", 5.00m)
    ColumnarScalarPlannerAssertDecimal(
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "79228162514264337593543950335m",
        79228162514264337593543950335m)
}

test "scalar literal planner preserves TryParse overflow and narrowing bounds" {
    maxDouble := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(),
        "1.7976931348623157e308"))
    overflowDouble := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1e9999"))
    assert overflowDouble.DoubleValues[0] > maxDouble.DoubleValues[0]

    underflowDouble := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1e-5000"))
    assert underflowDouble.DoubleValues[0] == 0.0
    assert 1.0 / underflowDouble.DoubleValues[0] > 0.0

    maxSingle := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "3.4028234e38f"))
    overflowSingle := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "3.5e38f"))
    assert overflowSingle.SingleValues[0] > maxSingle.SingleValues[0]
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

test "scalar literal planner folds the complete zero-hole interpolated family" {
    quote := "\""
    interpolated := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(),
        "$" + quote + "line\\n{{value}}" + quote))
    assert interpolated.ResultType == typeof(string)
    assert interpolated.OperationCount == 1
    assert interpolated.StringCount == 1
    assert interpolated.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert interpolated.StringValues[interpolated.OperandIndices[0]] == "line\n{value}"

    triple := quote + quote + quote
    raw := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(),
        "$" + triple + "slash\\n{{value}}" + triple))
    assert raw.StringValues[raw.OperandIndices[0]] == "slash\\n{value}"

    empty := ColumnarScalarPlannerPlan(ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(), "$" + quote + quote))
    assert empty.StringValues[empty.OperandIndices[0]] == ""
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

    floatingTree := ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1.25f")
    floatingPlan := new ColumnarCodePlan()
    resultType = typeof(int)
    assert ColumnarScalarLiteralPlanner.TryGetType(
        floatingTree.Nodes,
        floatingTree.Source,
        floatingTree.Root,
        floatingPlan,
        out resultType)
    assert resultType == typeof(float)
    assert floatingPlan.ResultType == typeof(float)

    doubleTree := ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1.25d")
    doublePlan := new ColumnarCodePlan()
    resultType = typeof(int)
    assert ColumnarScalarLiteralPlanner.TryGetType(
        doubleTree.Nodes,
        doubleTree.Source,
        doubleTree.Root,
        doublePlan,
        out resultType)
    assert resultType == typeof(double)
    assert doublePlan.ResultType == typeof(double)
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
        ColumnarExpressionNodeKind.StringLiteralExpression(),
        "$" + quote + "{value}" + quote)
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(),
        "$" + triple + "{value}" + triple)
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(), quote + "unterminated")
    ColumnarScalarPlannerDeclines(
        ColumnarExpressionNodeKind.StringLiteralExpression(), triple + "short")

    // Decimal literal text (`1.25m`) is now owned by the decimal-constructor lowering; only its
    // malformed forms remain rejections (see the decimal-literal ownership test).
    invalidFloating := new string[](13)
    invalidFloating[0] = ""
    invalidFloating[1] = "f"
    invalidFloating[2] = "d"
    invalidFloating[3] = "1.25ff"
    invalidFloating[4] = "1.25fd"
    invalidFloating[5] = "1.2.5m"
    invalidFloating[6] = "m"
    invalidFloating[7] = "1e"
    invalidFloating[8] = "1e+"
    invalidFloating[9] = "."
    invalidFloating[10] = "_"
    invalidFloating[11] = "not-a-number"
    invalidFloating[12] = " 1.25D "
    i = 0
    while i < invalidFloating.Length {
        ColumnarScalarPlannerDeclines(
            ColumnarExpressionNodeKind.FloatLiteralExpression(), invalidFloating[i])
        i = i + 1
    }

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

    floatingChildTree := ColumnarScalarPlannerTreeWithChild(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1.25")
    floatingChildPlan := new ColumnarCodePlan()
    assert ColumnarScalarLiteralPlanner.Plan(
        floatingChildTree.Nodes,
        floatingChildTree.Source,
        floatingChildTree.Root,
        floatingChildPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarScalarPlannerAssertEmpty(floatingChildPlan)

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

    malformedFloating := ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.FloatLiteralExpression(), "1e+")
    floatingAtomic := new ColumnarCodePlan()
    floatingAtomic.PrepareV3()
    floatingAtomic.BeginFragment(-1, ColumnarExpressionNodeKind.FloatLiteralExpression(), 0)
    existingDouble := floatingAtomic.AddDouble(99.0)
    floatingAtomic.AppendDoubleInstruction(ColumnarCodePlanContract.LdcR8(), existingDouble)
    assert !ColumnarScalarPlannerTryAppend(malformedFloating, floatingAtomic)
    assert floatingAtomic.OperationCount == 1
    assert floatingAtomic.DoubleCount == 1
    assert floatingAtomic.SingleCount == 0
    assert floatingAtomic.DoubleValues[0] == 99.0

    hole := ColumnarScalarPlannerTree(
        ColumnarExpressionNodeKind.StringLiteralExpression(), "$\"{value}\"")
    assert !ColumnarScalarPlannerTryAppend(hole, atomic)
    assert atomic.OperationCount == 1
    assert atomic.Int32Count == 1
    assert atomic.StringCount == 0

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

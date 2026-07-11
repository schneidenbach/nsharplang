namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

enum ColumnarRangePlannerProbeEnum {
    Zero = 0,
    One = 1,
    Four = 4
}

public class ColumnarRangePlannerTestTree {
    public Nodes: ColumnarNodeTable
    public Source: string
    public Root: int

    constructor(nodes: ColumnarNodeTable, source: string, root: int) {
        Nodes = nodes
        Source = source
        Root = root
    }
}

class ColumnarRangePlannerNodeBuilder {
    public Source: string
    kinds: List<int>
    valueStarts: List<int>
    valueLengths: List<int>
    childStarts: List<int>
    childCounts: List<int>
    children: List<int>
    spanStarts: List<int>
    spanLengths: List<int>

    constructor() {
        Source = ""
        kinds = new List<int>()
        valueStarts = new List<int>()
        valueLengths = new List<int>()
        childStarts = new List<int>()
        childCounts = new List<int>()
        children = new List<int>()
        spanStarts = new List<int>()
        spanLengths = new List<int>()
    }

    public func AddToken(text: string): int {
        start := Source.Length
        Source = Source + text
        return start
    }

    public func AddNode(
        kind: int,
        valueStart: int,
        valueLength: int,
        spanStart: int,
        spanLength: int,
        nodeChildren: int[]): int {
        index := kinds.Count
        kinds.Add(kind)
        valueStarts.Add(valueStart)
        valueLengths.Add(valueLength)
        childStarts.Add(children.Count)
        childCounts.Add(nodeChildren.Length)
        for child in nodeChildren {
            children.Add(child)
        }
        spanStarts.Add(spanStart)
        spanLengths.Add(spanLength)
        return index
    }

    public func AddLeaf(kind: int, text: string): int {
        start := AddToken(text)
        return AddNode(kind, start, text.Length, start, text.Length, new int[](0))
    }

    public func Build(root: int): ColumnarRangePlannerTestTree {
        table := new ColumnarNodeTable(
            kinds.ToArray(),
            valueStarts.ToArray(),
            valueLengths.ToArray(),
            childStarts.ToArray(),
            childCounts.ToArray(),
            children.ToArray(),
            spanStarts.ToArray(),
            spanLengths.ToArray())
        return new ColumnarRangePlannerTestTree(table, Source, root)
    }
}

func ColumnarRangePlannerChildren1(first: int): int[] {
    values := new int[](1)
    values[0] = first
    return values
}

func ColumnarRangePlannerChildren2(first: int, second: int): int[] {
    values := new int[](2)
    values[0] = first
    values[1] = second
    return values
}

func ColumnarRangePlannerChildren3(first: int, second: int, third: int): int[] {
    values := new int[](3)
    values[0] = first
    values[1] = second
    values[2] = third
    return values
}

func ColumnarRangePlannerEmptyBindings(): ColumnarFragmentBindings {
    return new ColumnarFragmentBindings(
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, System.Reflection.Emit.LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal))
}

func ColumnarRangePlannerAddParameter(
    bindings: ColumnarFragmentBindings,
    name: string,
    ordinal: int,
    parameterType: Type) {
    bindings.ParameterOrdinals[name] = ordinal
    bindings.ParameterTypes[name] = parameterType
}

func ColumnarRangePlannerEmptyLiftedFacts(): Dictionary<string, (Box: System.Reflection.Emit.LocalBuilder, ValueType: Type)> {
    return new Dictionary<string, (Box: System.Reflection.Emit.LocalBuilder, ValueType: Type)>(StringComparer.Ordinal)
}

func ColumnarRangePlannerEmptyBoxedFacts(): Dictionary<string, (BoxField: System.Reflection.FieldInfo, ValueType: Type)> {
    return new Dictionary<string, (BoxField: System.Reflection.FieldInfo, ValueType: Type)>(StringComparer.Ordinal)
}

func ColumnarRangePlannerAddNumericEnum(
    bindings: ColumnarFragmentBindings,
    name: string) {
    constants := new Dictionary<string, int>(StringComparer.Ordinal)
    constants["Zero"] = 0
    constants["One"] = 1
    constants["Four"] = 4
    bindings.Enums[name] = new ColumnarEnumDef(typeof(ColumnarRangePlannerProbeEnum), constants)
}

func ColumnarRangePlannerFromEndLiteral(text: string, parentheses: int = 0): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    caretStart := builder.AddToken("^")
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), text)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caretStart,
        1,
        caretStart,
        1 + text.Length,
        ColumnarRangePlannerChildren1(literal))
    i := 0
    while i < parentheses {
        root = builder.AddNode(
            ColumnarExpressionNodeKind.ParenthesizedExpression(),
            -1,
            0,
            caretStart,
            1 + text.Length,
            ColumnarRangePlannerChildren1(root))
        i = i + 1
    }
    return builder.Build(root)
}

func ColumnarRangePlannerFromEndIdentifier(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    caretStart := builder.AddToken("^")
    identifier := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caretStart,
        1,
        caretStart,
        1 + name.Length,
        ColumnarRangePlannerChildren1(identifier))
    return builder.Build(root)
}

func ColumnarRangePlannerDirectAccess(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "target")
    selector := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "selector")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(receiver, selector))
    return builder.Build(root)
}

func ColumnarRangePlannerOrdinaryLiteralAccess(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "target")
    selector := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(receiver, selector))
    return builder.Build(root)
}

func ColumnarRangePlannerFromEndIndexedCount(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    values := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")
    counts := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "counts")
    zero := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    count := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(counts, zero))
    caret := builder.AddToken("^")
    fromEnd := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        caret,
        1,
        ColumnarRangePlannerChildren1(count))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(values, fromEnd))
    return builder.Build(root)
}

func ColumnarRangePlannerOrdinaryIndexedCount(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    values := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")
    counts := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "counts")
    zero := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    count := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(counts, zero))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(values, count))
    return builder.Build(root)
}

func ColumnarRangePlannerNestedArrayFromEnd(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    matrix := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "matrix")
    zero := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    row := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(matrix, zero))
    caret := builder.AddToken("^")
    one := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    fromEnd := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        caret,
        2,
        ColumnarRangePlannerChildren1(one))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(row, fromEnd))
    return builder.Build(root)
}

func ColumnarRangePlannerRangeForm(form: int): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    startToken := -1
    endToken := -1
    dotToken := -1
    startNode := -1
    endNode := -1

    if form == 0 || form == 2 {
        startToken = builder.AddToken("1")
    }
    dotToken = builder.AddToken("..")
    if form == 0 || form == 1 {
        endToken = builder.AddToken("4")
    }
    if startToken >= 0 {
        startNode = builder.AddNode(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            startToken,
            1,
            startToken,
            1,
            new int[](0))
    }
    if endToken >= 0 {
        endNode = builder.AddNode(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            endToken,
            1,
            endToken,
            1,
            new int[](0))
    }

    nodeChildren := new int[](0)
    if startNode >= 0 && endNode >= 0 {
        nodeChildren = ColumnarRangePlannerChildren2(startNode, endNode)
    } else if startNode >= 0 {
        nodeChildren = ColumnarRangePlannerChildren1(startNode)
    } else if endNode >= 0 {
        nodeChildren = ColumnarRangePlannerChildren1(endNode)
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.RangeExpression(),
        dotToken,
        2,
        0,
        builder.Source.Length,
        nodeChildren)
    return builder.Build(root)
}

func ColumnarRangePlannerPlan(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    status := ColumnarRangeIndexPlanner.Plan(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        plan)
    if status != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected range/index planner ownership.")
    }
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ColumnarRangePlannerAssertEmptyRollback(plan: ColumnarCodePlan) {
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Building
    assert plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
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

func ColumnarRangePlannerAssertArrayIndexOpcode(
    arrayType: Type,
    elementType: Type,
    expectedOpcode: short,
    expectedOperandKind: int) {
    tree := ColumnarRangePlannerDirectAccess()
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "target", 0, arrayType)
    ColumnarRangePlannerAddParameter(bindings, "selector", 1, typeof(Index))
    plan := ColumnarRangePlannerPlan(tree, bindings)
    last := plan.OperationCount - 1
    assert plan.ResultType == elementType
    assert plan.OperationCount == 11
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Stloc()
    assert plan.OperandIndices[2] == 0
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Stloc()
    assert plan.OperandIndices[3] == 1
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Ldloca()
    assert plan.OperandIndices[5] == 0
    assert plan.OpCodeValues[7] == ColumnarCodePlanContract.Ldlen()
    assert plan.OpCodeValues[8] == ColumnarCodePlanContract.ConvI4()
    assert plan.OpCodeValues[9] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[last] == expectedOpcode
    assert plan.OperandKinds[last] == expectedOperandKind
    if expectedOperandKind == ColumnarCodePlanContract.TypeOperand() {
        assert plan.Types[plan.OperandIndices[last]] == elementType
    }
}

test "range planner owns from-end literals with transparent parentheses" {
    tree := ColumnarRangePlannerFromEndLiteral("2", 2)
    plan := ColumnarRangePlannerPlan(tree, ColumnarRangePlannerEmptyBindings())

    assert plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert plan.ResultType == typeof(Index)
    assert plan.OperationCount == 3
    assert plan.FragmentCount == 2
    assert plan.FragmentKinds[0] == ColumnarExpressionNodeKind.UnaryExpression()
    assert plan.FragmentKinds[1] == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert plan.FragmentParentIndices[0] == -1
    assert plan.FragmentParentIndices[1] == 0
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[0]] == 2
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_1()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert plan.OperationOwnerFragmentIndices[0] == 1
    assert plan.OperationOwnerFragmentIndices[1] == 0
    assert plan.OperationOwnerFragmentIndices[2] == 0
}

test "range planner recursively delegates underscored scalar literals" {
    tree := ColumnarRangePlannerFromEndLiteral("1_0", 0)
    plan := ColumnarRangePlannerPlan(tree, ColumnarRangePlannerEmptyBindings())

    assert plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert plan.ResultType == typeof(Index)
    assert plan.OperationCount == 3
    assert plan.FragmentCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[0]] == 10
}

test "range planner emits each open and closed range form exactly" {
    form := 0
    while form < 4 {
        tree := ColumnarRangePlannerRangeForm(form)
        plan := ColumnarRangePlannerPlan(tree, ColumnarRangePlannerEmptyBindings())
        expectedFragments := 3
        if form == 1 || form == 2 {
            expectedFragments = 2
        } else if form == 3 {
            expectedFragments = 1
        }
        assert plan.ResultType == typeof(Range)
        assert plan.OperationCount == 7
        assert plan.FragmentCount == expectedFragments
        assert plan.OpCodeValues[plan.OperationCount - 1]
            == ColumnarCodePlanContract.Newobj()
        if form == 0 {
            assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
            assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_0()
            assert plan.OpCodeValues[3] == ColumnarCodePlanContract.LdcI4()
            assert plan.OpCodeValues[4] == ColumnarCodePlanContract.LdcI4_0()
        } else if form == 1 {
            assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4_0()
            assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_0()
            assert plan.OpCodeValues[3] == ColumnarCodePlanContract.LdcI4()
            assert plan.OpCodeValues[4] == ColumnarCodePlanContract.LdcI4_0()
        } else {
            if form == 2 {
                assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
            } else {
                assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4_0()
            }
            assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_0()
            assert plan.OpCodeValues[3] == ColumnarCodePlanContract.LdcI4_0()
            assert plan.OpCodeValues[4] == ColumnarCodePlanContract.LdcI4_1()
        }
        assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
        assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Newobj()
        rangeConstructor := plan.Constructors[plan.OperandIndices[plan.OperationCount - 1]]
        assert rangeConstructor.get_DeclaringType() == typeof(Range)
        form = form + 1
    }
}

test "range planner owns parenthesized start through an inclusive from-end-zero boundary" {
    builder := new ColumnarRangePlannerNodeBuilder()
    startToken := builder.AddToken("1")
    dotToken := builder.AddToken("..")
    caretToken := builder.AddToken("^")
    zeroToken := builder.AddToken("0")
    start := builder.AddNode(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        startToken,
        1,
        startToken,
        1,
        new int[](0))
    parenthesizedStart := builder.AddNode(
        ColumnarExpressionNodeKind.ParenthesizedExpression(),
        -1,
        0,
        startToken,
        1,
        ColumnarRangePlannerChildren1(start))
    zero := builder.AddNode(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        zeroToken,
        1,
        zeroToken,
        1,
        new int[](0))
    fromEndZero := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caretToken,
        1,
        caretToken,
        2,
        ColumnarRangePlannerChildren1(zero))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.RangeExpression(),
        dotToken,
        2,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(parenthesizedStart, fromEndZero))
    plan := ColumnarRangePlannerPlan(builder.Build(root), ColumnarRangePlannerEmptyBindings())

    assert plan.ResultType == typeof(Range)
    assert plan.OperationCount == 7
    assert plan.FragmentCount == 4
    assert plan.FragmentKinds[1] == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert plan.FragmentKinds[2] == ColumnarExpressionNodeKind.UnaryExpression()
    assert plan.FragmentKinds[3] == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[3]] == 0
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.LdcI4_1()
}

test "range planner accepts direct Index endpoints and exact small integral conversions" {
    builder := new ColumnarRangePlannerNodeBuilder()
    start := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "start")
    dot := builder.AddToken("..")
    end := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "end")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.RangeExpression(),
        dot,
        2,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(start, end))
    tree := builder.Build(root)

    indexBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(indexBindings, "start", 0, typeof(Index))
    ColumnarRangePlannerAddParameter(indexBindings, "end", 1, typeof(Index))
    indexPlan := ColumnarRangePlannerPlan(tree, indexBindings)
    assert indexPlan.OperationCount == 3
    assert indexPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert indexPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldarg()
    assert indexPlan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()

    smallBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(smallBindings, "start", 0, typeof(byte))
    ColumnarRangePlannerAddParameter(smallBindings, "end", 1, typeof(short))
    smallPlan := ColumnarRangePlannerPlan(tree, smallBindings)
    assert smallPlan.OperationCount == 9
    assert smallPlan.OpCodeValues[1] == ColumnarCodePlanContract.ConvI4()
    assert smallPlan.OpCodeValues[5] == ColumnarCodePlanContract.ConvI4()
}

test "range planner resolves exact numeric enum members and rejects every shadow tier" {
    builder := new ColumnarRangePlannerNodeBuilder()
    caret := builder.AddToken("^")
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "Bound")
    memberToken := builder.AddToken("One")
    member := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        memberToken,
        3,
        1,
        8,
        ColumnarRangePlannerChildren1(owner))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(member))
    tree := builder.Build(root)

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddNumericEnum(bindings, "Bound")
    plan := ColumnarRangePlannerPlan(tree, bindings)
    assert plan.ResultType == typeof(Index)
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.ConvI4()
    assert plan.Int32Values[plan.OperandIndices[0]] == 1

    blockedNames := new HashSet<string>(StringComparer.Ordinal)
    callableNames := new HashSet<string>(StringComparer.Ordinal)
    shadowed := new ColumnarFragmentBindings(
        bindings.ParameterOrdinals,
        bindings.ParameterTypes,
        bindings.Locals,
        bindings.Enums,
        blockedNames,
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        callableNames)

    blockedNames.Add("Bound")
    blockedPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, shadowed,
        ColumnarRangeIndexHandles.Resolve(), blockedPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(blockedPlan)

    blockedNames.Remove("Bound")
    callableNames.Add("Bound")
    callablePlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, shadowed,
        ColumnarRangeIndexHandles.Resolve(), callablePlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(callablePlan)

    callableNames.Remove("Bound")
    ColumnarRangePlannerAddParameter(shadowed, "Bound", 7, typeof(int))
    parameterPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, shadowed,
        ColumnarRangeIndexHandles.Resolve(), parameterPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(parameterPlan)

    unknownBindings := ColumnarRangePlannerEmptyBindings()
    unknownBindings.Enums["Bound"] = new ColumnarEnumDef(
        typeof(ColumnarRangePlannerProbeEnum),
        new Dictionary<string, int>(StringComparer.Ordinal))
    unknownPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, unknownBindings,
        ColumnarRangeIndexHandles.Resolve(), unknownPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(unknownPlan)

    stringConstants := new Dictionary<string, string>(StringComparer.Ordinal)
    stringConstants["One"] = "one"
    stringBindings := ColumnarRangePlannerEmptyBindings()
    stringBindings.Enums["Bound"] = new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        stringConstants)
    stringPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, stringBindings,
        ColumnarRangeIndexHandles.Resolve(), stringPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(stringPlan)
}

test "range planner resolves dotted enum names by exact root and member identity" {
    builder := new ColumnarRangePlannerNodeBuilder()
    caret := builder.AddToken("^")
    packageNode := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "Pkg")
    ownerToken := builder.AddToken("Bound")
    owner := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        ownerToken,
        5,
        1,
        8,
        ColumnarRangePlannerChildren1(packageNode))
    memberToken := builder.AddToken("Four")
    member := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        memberToken,
        4,
        1,
        12,
        ColumnarRangePlannerChildren1(owner))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(member))
    tree := builder.Build(root)
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddNumericEnum(bindings, "Pkg.Bound")
    plan := ColumnarRangePlannerPlan(tree, bindings)
    assert plan.Int32Values[plan.OperandIndices[0]] == 4
}

test "range planner emits exact string Index and Range read sequences" {
    tree := ColumnarRangePlannerDirectAccess()

    indexBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(indexBindings, "target", 0, typeof(string))
    ColumnarRangePlannerAddParameter(indexBindings, "selector", 1, typeof(Index))
    indexPlan := ColumnarRangePlannerPlan(tree, indexBindings)
    assert indexPlan.ResultType == typeof(char)
    assert indexPlan.OperationCount == 10
    assert indexPlan.PlanLocalCount == 2
    assert indexPlan.MethodCount == 3
    assert indexPlan.OpCodeValues[2] == ColumnarCodePlanContract.Stloc()
    assert indexPlan.OperandIndices[2] == 0
    assert indexPlan.OpCodeValues[3] == ColumnarCodePlanContract.Stloc()
    assert indexPlan.OperandIndices[3] == 1
    assert indexPlan.OpCodeValues[5] == ColumnarCodePlanContract.Ldloca()
    assert indexPlan.OpCodeValues[7] == ColumnarCodePlanContract.Callvirt()
    assert indexPlan.OpCodeValues[8] == ColumnarCodePlanContract.Call()
    assert indexPlan.OpCodeValues[9] == ColumnarCodePlanContract.Callvirt()

    rangeBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(rangeBindings, "target", 0, typeof(string))
    ColumnarRangePlannerAddParameter(rangeBindings, "selector", 1, typeof(Range))
    rangePlan := ColumnarRangePlannerPlan(tree, rangeBindings)
    assert rangePlan.ResultType == typeof(string)
    assert rangePlan.OperationCount == 15
    assert rangePlan.PlanLocalCount == 3
    assert rangePlan.MethodCount == 3
    assert rangePlan.FieldCount == 2
    assert rangePlan.OpCodeValues[4] == ColumnarCodePlanContract.Ldloca()
    assert rangePlan.OperandIndices[2] == 0
    assert rangePlan.OperandIndices[3] == 1
    assert rangePlan.OperandIndices[8] == 2
    assert rangePlan.OpCodeValues[11] == ColumnarCodePlanContract.Ldfld()
    assert rangePlan.OpCodeValues[13] == ColumnarCodePlanContract.Ldfld()
    assert rangePlan.OpCodeValues[14] == ColumnarCodePlanContract.Callvirt()
}

test "range planner selects every exact SZ-array Index load family" {
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(bool[]), typeof(bool), ColumnarCodePlanContract.LdelemU1(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(char[]), typeof(char), ColumnarCodePlanContract.LdelemU2(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(int[]), typeof(int), ColumnarCodePlanContract.LdelemI4(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(uint[]), typeof(uint), ColumnarCodePlanContract.LdelemU4(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(long[]), typeof(long), ColumnarCodePlanContract.LdelemI8(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(ulong[]), typeof(ulong), ColumnarCodePlanContract.LdelemI8(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(float[]), typeof(float), ColumnarCodePlanContract.LdelemR4(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(double[]), typeof(double), ColumnarCodePlanContract.LdelemR8(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(string[]), typeof(string), ColumnarCodePlanContract.LdelemRef(),
        ColumnarCodePlanContract.NoOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(object[]), typeof(object), ColumnarCodePlanContract.LdelemRef(),
        ColumnarCodePlanContract.NoOperand())
}

test "range planner uses typed ldelem for narrow enum struct and generic elements" {
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(byte[]), typeof(byte), ColumnarCodePlanContract.Ldelem(),
        ColumnarCodePlanContract.TypeOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(sbyte[]), typeof(sbyte), ColumnarCodePlanContract.Ldelem(),
        ColumnarCodePlanContract.TypeOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(short[]), typeof(short), ColumnarCodePlanContract.Ldelem(),
        ColumnarCodePlanContract.TypeOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(ushort[]), typeof(ushort), ColumnarCodePlanContract.Ldelem(),
        ColumnarCodePlanContract.TypeOperand())
    ColumnarRangePlannerAssertArrayIndexOpcode(
        typeof(ColumnarRangePlannerProbeEnum[]), typeof(ColumnarRangePlannerProbeEnum),
        ColumnarCodePlanContract.Ldelem(), ColumnarCodePlanContract.TypeOperand())
    tupleElement := typeof(ValueTuple<int, int>)
    tupleArray := tupleElement.MakeArrayType()
    ColumnarRangePlannerAssertArrayIndexOpcode(
        tupleArray, tupleElement,
        ColumnarCodePlanContract.Ldelem(), ColumnarCodePlanContract.TypeOperand())

    genericElement := RangeHandleGenericParameter()
    ColumnarRangePlannerAssertArrayIndexOpcode(
        genericElement.MakeArrayType(), genericElement,
        ColumnarCodePlanContract.Ldelem(), ColumnarCodePlanContract.TypeOperand())
}

test "range planner closes exact GetSubArray handles for concrete and generic arrays" {
    tree := ColumnarRangePlannerDirectAccess()
    arrayTypes := new Type[](3)
    arrayTypes[0] = typeof(int[])
    arrayTypes[1] = typeof(string[])
    arrayTypes[2] = RangeHandleGenericParameter().MakeArrayType()

    i := 0
    while i < arrayTypes.Length {
        bindings := ColumnarRangePlannerEmptyBindings()
        ColumnarRangePlannerAddParameter(bindings, "target", 0, arrayTypes[i])
        ColumnarRangePlannerAddParameter(bindings, "selector", 1, typeof(Range))
        plan := ColumnarRangePlannerPlan(tree, bindings)
        assert plan.ResultType == arrayTypes[i]
        assert plan.OperationCount == 3
        assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
        method := plan.Methods[plan.OperandIndices[2]]
        parameters := method.GetParameters()
        assert method.get_ReturnType() == arrayTypes[i]
        assert parameters[0].get_ParameterType() == arrayTypes[i]
        assert parameters[1].get_ParameterType() == typeof(Range)
        i = i + 1
    }
}

test "range planner recursively plans conditional Index and Range selectors" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")
    condition := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "choose")
    firstCaret := builder.AddToken("^")
    firstValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    firstIndex := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        firstCaret,
        1,
        firstCaret,
        2,
        ColumnarRangePlannerChildren1(firstValue))
    secondCaret := builder.AddToken("^")
    secondValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    secondIndex := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        secondCaret,
        1,
        secondCaret,
        2,
        ColumnarRangePlannerChildren1(secondValue))
    conditional := builder.AddNode(
        ColumnarExpressionNodeKind.TernaryExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(condition, firstIndex, secondIndex))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(receiver, conditional))
    tree := builder.Build(root)

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "values", 0, typeof(int[]))
    ColumnarRangePlannerAddParameter(bindings, "choose", 1, typeof(bool))
    plan := ColumnarRangePlannerPlan(tree, bindings)
    assert plan.ResultType == typeof(int)
    assert plan.LabelCount == 2
    assert plan.FragmentCount == 8
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Brfalse()
    assert plan.OpCodeValues[6] == ColumnarCodePlanContract.Br()
    assert plan.OperationKinds[7] == ColumnarCodePlanContract.MarkLabelOperation()
    assert plan.OperationKinds[11] == ColumnarCodePlanContract.MarkLabelOperation()
}

test "range planner recursively plans bool literal and parenthesized conditional Range selectors" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "text")
    condition := builder.AddLeaf(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true")
    firstRange := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "first")
    firstParenthesized := builder.AddNode(
        ColumnarExpressionNodeKind.ParenthesizedExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(firstRange))
    secondRange := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "second")
    secondParenthesized := builder.AddNode(
        ColumnarExpressionNodeKind.ParenthesizedExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(secondRange))
    conditional := builder.AddNode(
        ColumnarExpressionNodeKind.TernaryExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(
            condition,
            firstParenthesized,
            secondParenthesized))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(receiver, conditional))
    tree := builder.Build(root)

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "text", 0, typeof(string))
    ColumnarRangePlannerAddParameter(bindings, "first", 1, typeof(Range))
    ColumnarRangePlannerAddParameter(bindings, "second", 2, typeof(Range))
    plan := ColumnarRangePlannerPlan(tree, bindings)
    assert plan.ResultType == typeof(string)
    assert plan.LabelCount == 2
    assert plan.FragmentCount == 6
    assert plan.FragmentKinds[3] == ColumnarExpressionNodeKind.BoolLiteralExpression()
    assert plan.FragmentKinds[4] == ColumnarExpressionNodeKind.IdentifierExpression()
    assert plan.FragmentKinds[5] == ColumnarExpressionNodeKind.IdentifierExpression()

    bindings.ParameterTypes["second"] = typeof(Index)
    rejected := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, bindings,
        ColumnarRangeIndexHandles.Resolve(), rejected)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(rejected)
}

test "range planner owns ordinary Int32 indexing only beneath an owned range-index root" {
    indexedCount := ColumnarRangePlannerFromEndIndexedCount()
    countBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(countBindings, "values", 0, typeof(int[]))
    ColumnarRangePlannerAddParameter(countBindings, "counts", 1, typeof(int[]))
    countPlan := ColumnarRangePlannerPlan(indexedCount, countBindings)

    assert countPlan.ResultType == typeof(int)
    assert countPlan.OperationCount == 15
    assert countPlan.FragmentCount == 6
    assert countPlan.PlanLocalCount == 2
    assert countPlan.OpCodeValues[3] == ColumnarCodePlanContract.LdelemI4()
    assert countPlan.OperationOwnerFragmentIndices[3] == 3
    assert countPlan.OpCodeValues[4] == ColumnarCodePlanContract.LdcI4_1()
    assert countPlan.OpCodeValues[5] == ColumnarCodePlanContract.Newobj()
    assert countPlan.OpCodeValues[14] == ColumnarCodePlanContract.LdelemI4()

    stringCountBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(stringCountBindings, "values", 0, typeof(int[]))
    ColumnarRangePlannerAddParameter(stringCountBindings, "counts", 1, typeof(string))
    stringCountPlan := ColumnarRangePlannerPlan(indexedCount, stringCountBindings)
    assert stringCountPlan.ResultType == typeof(int)
    assert stringCountPlan.OperationCount == 16
    assert stringCountPlan.OpCodeValues[3] == ColumnarCodePlanContract.Callvirt()
    assert stringCountPlan.OperationOwnerFragmentIndices[3] == 3
    assert stringCountPlan.OpCodeValues[4] == ColumnarCodePlanContract.ConvI4()

    nestedArray := ColumnarRangePlannerNestedArrayFromEnd()
    matrixBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(matrixBindings, "matrix", 0, typeof(int[][]))
    matrixPlan := ColumnarRangePlannerPlan(nestedArray, matrixBindings)

    assert matrixPlan.ResultType == typeof(int)
    assert matrixPlan.OperationCount == 15
    assert matrixPlan.FragmentCount == 6
    assert matrixPlan.PlanLocalCount == 2
    assert matrixPlan.OpCodeValues[2] == ColumnarCodePlanContract.LdelemRef()
    assert matrixPlan.OperationOwnerFragmentIndices[2] == 1
    assert matrixPlan.OpCodeValues[14] == ColumnarCodePlanContract.LdelemI4()
}

test "range planner rolls back an unsupported ordinary index child without widening root ownership" {
    nested := ColumnarRangePlannerFromEndIndexedCount()
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "values", 0, typeof(int[]))
    ColumnarRangePlannerAddParameter(bindings, "counts", 1, typeof(int))
    rejected := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        nested.Nodes,
        nested.Source,
        nested.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        rejected)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(rejected)

    direct := ColumnarRangePlannerOrdinaryLiteralAccess()
    directBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(directBindings, "target", 0, typeof(int[]))
    directPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        direct.Nodes,
        direct.Source,
        direct.Root,
        directBindings,
        ColumnarRangeIndexHandles.Resolve(),
        directPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(directPlan)

    nestedDirect := ColumnarRangePlannerOrdinaryIndexedCount()
    nestedDirectBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(nestedDirectBindings, "values", 0, typeof(int[]))
    ColumnarRangePlannerAddParameter(nestedDirectBindings, "counts", 1, typeof(int[]))
    nestedDirectPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        nestedDirect.Nodes,
        nestedDirect.Source,
        nestedDirect.Root,
        nestedDirectBindings,
        ColumnarRangeIndexHandles.Resolve(),
        nestedDirectPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(nestedDirectPlan)
}

test "range planner declines atomically on unknown wide and ordinary root forms" {
    tree := ColumnarRangePlannerDirectAccess()
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "target", 0, typeof(int[]))
    ColumnarRangePlannerAddParameter(bindings, "selector", 1, typeof(int))
    plan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        tree.Nodes, tree.Source, tree.Root, bindings,
        ColumnarRangeIndexHandles.Resolve(), plan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)

    unknown := ColumnarRangePlannerFromEndIdentifier("missing")
    unknownPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        unknown.Nodes, unknown.Source, unknown.Root, ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(), unknownPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(unknownPlan)

    uintTree := ColumnarRangePlannerFromEndIdentifier("wide")
    uintBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(uintBindings, "wide", 0, typeof(uint))
    uintPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        uintTree.Nodes, uintTree.Source, uintTree.Root, uintBindings,
        ColumnarRangeIndexHandles.Resolve(), uintPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(uintPlan)
}

test "range planner declines malformed literals branches and node shapes atomically" {
    overflow := ColumnarRangePlannerFromEndLiteral("2147483648", 0)
    overflowPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        overflow.Nodes, overflow.Source, overflow.Root, ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(), overflowPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(overflowPlan)

    suffix := ColumnarRangePlannerFromEndLiteral("1L", 0)
    suffixPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        suffix.Nodes, suffix.Source, suffix.Root, ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(), suffixPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(suffixPlan)

    builder := new ColumnarRangePlannerNodeBuilder()
    caret := builder.AddToken("^")
    badRoot := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        0,
        1,
        new int[](0))
    malformed := builder.Build(badRoot)
    malformedPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        malformed.Nodes, malformed.Source, malformed.Root, ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(), malformedPlan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(malformedPlan)
}

test "range planner root ownership excludes scalar leaves and standalone ternaries" {
    builder := new ColumnarRangePlannerNodeBuilder()
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    scalar := builder.Build(literal)
    plan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        scalar.Nodes, scalar.Source, scalar.Root, ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(), plan)
        == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "range planner raw-facts type facade owns construction and nullable boxed normalization" {
    tree := ColumnarRangePlannerFromEndLiteral("2", 0)
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    locals := new Dictionary<string, System.Reflection.Emit.LocalBuilder>(StringComparer.Ordinal)
    enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    lifted := ColumnarRangePlannerEmptyLiftedFacts()
    enclosing := new HashSet<string>(StringComparer.Ordinal)
    siblings := new HashSet<string>(StringComparer.Ordinal)
    visibleLocals := new HashSet<string>(StringComparer.Ordinal)
    plan := new ColumnarCodePlan()
    identifierOwned := false
    resultType := typeof(int)

    assert ColumnarRangeIndexPlanner.TryGetTypeFromFacts(
        tree.Nodes,
        tree.Source,
        tree.Root,
        parameterOrdinals,
        parameterTypes,
        locals,
        enums,
        lifted,
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        enclosing,
        siblings,
        visibleLocals,
        plan,
        out identifierOwned,
        out resultType)
    assert !identifierOwned
    assert resultType == typeof(Index)
    assert plan.Status == ColumnarFragmentPlanStatus.Planned
    ColumnarCodePlanExecutor.Validate(plan)
}

test "range planner raw-facts facades gate ordinary int indexing before facts handles or IL" {
    tree := ColumnarRangePlannerOrdinaryLiteralAccess()
    typePlan := new ColumnarCodePlan()
    typeIdentifierOwned := false
    typeResult := typeof(object)
    assert !ColumnarRangeIndexPlanner.TryGetTypeFromFacts(
        tree.Nodes,
        tree.Source,
        tree.Root,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        typePlan,
        out typeIdentifierOwned,
        out typeResult)
    assert !typeIdentifierOwned
    ColumnarRangePlannerAssertEmptyRollback(typePlan)

    emitPlan := new ColumnarCodePlan()
    emitIdentifierOwned := false
    emitResult := typeof(object)
    assert !ColumnarRangeIndexPlanner.TryEmitFromFacts(
        tree.Nodes,
        tree.Source,
        tree.Root,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        emitPlan,
        null,
        out emitIdentifierOwned,
        out emitResult)
    assert !emitIdentifierOwned
    ColumnarRangePlannerAssertEmptyRollback(emitPlan)

    identifierTree := ColumnarRangePlannerDirectAccess()
    identifierOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    identifierTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    identifierOrdinals["selector"] = 1
    identifierTypes["selector"] = typeof(int)
    identifierPlan := new ColumnarCodePlan()
    identifierOwned := false
    identifierResult := typeof(object)
    assert !ColumnarRangeIndexPlanner.TryGetTypeFromFacts(
        identifierTree.Nodes,
        identifierTree.Source,
        identifierTree.Root,
        identifierOrdinals,
        identifierTypes,
        new Dictionary<string, System.Reflection.Emit.LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        ColumnarRangePlannerEmptyLiftedFacts(),
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        new HashSet<string>(StringComparer.Ordinal),
        identifierPlan,
        out identifierOwned,
        out identifierResult)
    assert !identifierOwned
    ColumnarRangePlannerAssertEmptyRollback(identifierPlan)
}

test "range planner raw-facts facade admits an ordinary child beneath an owned root" {
    tree := ColumnarRangePlannerFromEndIndexedCount()
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameterOrdinals["values"] = 0
    parameterTypes["values"] = typeof(int[])
    parameterOrdinals["counts"] = 1
    parameterTypes["counts"] = typeof(int[])
    emptyNames := new HashSet<string>(StringComparer.Ordinal)
    plan := new ColumnarCodePlan()
    identifierOwned := false
    resultType := typeof(object)

    assert ColumnarRangeIndexPlanner.TryGetTypeFromFacts(
        tree.Nodes,
        tree.Source,
        tree.Root,
        parameterOrdinals,
        parameterTypes,
        new Dictionary<string, System.Reflection.Emit.LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        ColumnarRangePlannerEmptyLiftedFacts(),
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        emptyNames,
        emptyNames,
        emptyNames,
        plan,
        out identifierOwned,
        out resultType)
    assert !identifierOwned
    assert resultType == typeof(int)
    assert plan.Status == ColumnarFragmentPlanStatus.Planned
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.LdelemI4()
    ColumnarCodePlanExecutor.Validate(plan)
}

test "range planner raw-facts selector gate recognizes direct Range parameters" {
    tree := ColumnarRangePlannerDirectAccess()
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameterOrdinals["target"] = 0
    parameterTypes["target"] = typeof(string)
    parameterOrdinals["selector"] = 1
    parameterTypes["selector"] = typeof(Range)
    emptyNames := new HashSet<string>(StringComparer.Ordinal)
    plan := new ColumnarCodePlan()
    identifierOwned := false
    resultType := typeof(int)

    assert ColumnarRangeIndexPlanner.TryGetTypeFromFacts(
        tree.Nodes,
        tree.Source,
        tree.Root,
        parameterOrdinals,
        parameterTypes,
        new Dictionary<string, System.Reflection.Emit.LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        ColumnarRangePlannerEmptyLiftedFacts(),
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        emptyNames,
        emptyNames,
        emptyNames,
        plan,
        out identifierOwned,
        out resultType)
    assert !identifierOwned
    assert resultType == typeof(string)
    ColumnarCodePlanExecutor.Validate(plan)
}

test "range planner rejects corrupt parameter facts and invalid roots" {
    tree := ColumnarRangePlannerFromEndIdentifier("value")
    corrupt := ColumnarRangePlannerEmptyBindings()
    corrupt.ParameterOrdinals["value"] = 0
    assert throws InvalidOperationException {
        ColumnarRangeIndexPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, corrupt,
            ColumnarRangeIndexHandles.Resolve(), new ColumnarCodePlan())
    }

    assert throws InvalidOperationException {
        ColumnarRangeIndexPlanner.Plan(
            tree.Nodes, tree.Source, 50, ColumnarRangePlannerEmptyBindings(),
            ColumnarRangeIndexHandles.Resolve(), new ColumnarCodePlan())
    }
    assert throws InvalidOperationException {
        ColumnarRangeIndexPlanner.Plan(
            null, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(),
            ColumnarRangeIndexHandles.Resolve(), new ColumnarCodePlan())
    }
}

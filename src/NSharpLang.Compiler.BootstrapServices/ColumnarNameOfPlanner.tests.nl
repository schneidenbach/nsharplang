namespace NSharpLang.Compiler.Columnar

import System

func ColumnarNameOfPlannerTree(
    targetKind: int,
    targetText: string,
    parentheses: int
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    target := builder.AddLeaf(targetKind, targetText)
    i := 0
    while i < parentheses {
        target = builder.AddNode(
            ColumnarExpressionNodeKind.ParenthesizedExpression(),
            -1,
            0,
            0,
            builder.Source.Length,
            ColumnarRangePlannerChildren1(target)
        )
        i = i + 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NameOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(target)
    )
    return builder.Build(root)
}

func ColumnarNameOfPlannerMemberTree(
    owner: string,
    member: string,
    parentheses: int
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), owner)
    memberStart := builder.AddToken(member)
    target := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        memberStart,
        member.Length,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(receiver)
    )
    i := 0
    while i < parentheses {
        target = builder.AddNode(
            ColumnarExpressionNodeKind.ParenthesizedExpression(),
            -1,
            0,
            0,
            builder.Source.Length,
            ColumnarRangePlannerChildren1(target)
        )
        i = i + 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NameOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(target)
    )
    return builder.Build(root)
}

func ColumnarNameOfPlannerPlan(tree: ColumnarRangePlannerTestTree): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    assert ColumnarNameOfPlanner.Plan(tree.Nodes, tree.Source, tree.Root, plan) == ColumnarFragmentPlanStatus.Planned
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ColumnarNameOfRangeReceiverTree(useNameOf: bool): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := -1
    if useNameOf {
        target := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")
        receiver = builder.AddNode(
            ColumnarExpressionNodeKind.NameOfExpression(),
            -1,
            0,
            0,
            builder.Source.Length,
            ColumnarRangePlannerChildren1(target)
        )
    } else {
        receiver = builder.AddLeaf(
            ColumnarExpressionNodeKind.StringLiteralExpression(),
            "\"values\""
        )
    }
    caret := builder.AddToken("^")
    one := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    fromEnd := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        caret,
        2,
        ColumnarRangePlannerChildren1(one)
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IndexAccessExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(receiver, fromEnd)
    )
    return builder.Build(root)
}

func ColumnarNameOfCharFromEndTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    caret := builder.AddToken("^")
    character := builder.AddLeaf(ColumnarExpressionNodeKind.CharLiteralExpression(), "'A'")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        caret,
        1,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(character)
    )
    return builder.Build(root)
}

func ColumnarNameOfPlannerAssertEmpty(plan: ColumnarCodePlan) {
    assert plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Building
    assert plan.OperationCount == 0
    assert plan.FragmentCount == 0
    assert plan.StringCount == 0
    assert plan.TypeCount == 0
    assert plan.Int32Count == 0
    assert plan.MethodCount == 0
    assert plan.ConstructorCount == 0
}

test "nameof planner owns identifier member and transparent-parenthesis targets" {
    identifier := ColumnarNameOfPlannerPlan(ColumnarNameOfPlannerTree(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "value",
        0
    ))
    assert identifier.ResultType == typeof(string)
    assert identifier.OperationCount == 1
    assert identifier.FragmentCount == 1
    assert identifier.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert identifier.StringValues[identifier.OperandIndices[0]] == "value"

    member := ColumnarNameOfPlannerPlan(
        ColumnarNameOfPlannerMemberTree("owner", "FinalMember", 3)
    )
    assert member.ResultType == typeof(string)
    assert member.StringValues[member.OperandIndices[0]] == "FinalMember"
}

test "nameof planner type facade seals the exact string result" {
    tree := ColumnarNameOfPlannerTree(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "value",
        1
    )
    plan := new ColumnarCodePlan()
    resultType := typeof(int)
    assert ColumnarNameOfPlanner.TryGetType(
        tree.Nodes,
        tree.Source,
        tree.Root,
        plan,
        out resultType
    )
    assert resultType == typeof(string)
    assert plan.ResultType == typeof(string)
    assert plan.Status == ColumnarFragmentPlanStatus.Planned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
}

test "nameof planner declines malformed and non-name targets without mutation" {
    nonName := ColumnarNameOfPlannerTree(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1",
        0
    )
    nonNamePlan := new ColumnarCodePlan()
    assert ColumnarNameOfPlanner.Plan(
        nonName.Nodes,
        nonName.Source,
        nonName.Root,
        nonNamePlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarNameOfPlannerAssertEmpty(nonNamePlan)

    emptyName := ColumnarNameOfPlannerTree(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "",
        0
    )
    emptyNamePlan := new ColumnarCodePlan()
    assert ColumnarNameOfPlanner.Plan(
        emptyName.Nodes,
        emptyName.Source,
        emptyName.Root,
        emptyNamePlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarNameOfPlannerAssertEmpty(emptyNamePlan)

    builder := new ColumnarRangePlannerNodeBuilder()
    malformedRoot := builder.AddNode(
        ColumnarExpressionNodeKind.NameOfExpression(),
        -1,
        0,
        0,
        0,
        new int[](0)
    )
    malformed := builder.Build(malformedRoot)
    malformedPlan := new ColumnarCodePlan()
    assert ColumnarNameOfPlanner.Plan(
        malformed.Nodes,
        malformed.Source,
        malformed.Root,
        malformedPlan
    ) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarNameOfPlannerAssertEmpty(malformedPlan)
}

test "nameof recursive append is mutation-free on rejection" {
    tree := ColumnarNameOfPlannerTree(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1",
        0
    )
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    fragment := plan.BeginFragment(-1, 69, 0)
    resultType := typeof(int)
    operationCount := plan.OperationCount
    stringCount := plan.StringCount
    fragmentCount := plan.FragmentCount
    assert !ColumnarNameOfPlanner.TryAppendNameOf(
        tree.Nodes,
        tree.Source,
        tree.Root,
        plan,
        out resultType
    )
    assert plan.OperationCount == operationCount
    assert plan.StringCount == stringCount
    assert plan.FragmentCount == fragmentCount
    assert !plan.FragmentCompleted[fragment]
}

test "range planner consumes nameof string and character constant children" {
    nameOfReceiver := ColumnarNameOfRangeReceiverTree(true)
    nameOfPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        nameOfReceiver.Nodes,
        nameOfReceiver.Source,
        nameOfReceiver.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        nameOfPlan
    ) == ColumnarFragmentPlanStatus.Planned
    assert nameOfPlan.ResultType == typeof(char)
    assert nameOfPlan.StringCount == 1
    assert nameOfPlan.StringValues[0] == "values"
    ColumnarCodePlanExecutor.Validate(nameOfPlan)

    stringReceiver := ColumnarNameOfRangeReceiverTree(false)
    stringPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        stringReceiver.Nodes,
        stringReceiver.Source,
        stringReceiver.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        stringPlan
    ) == ColumnarFragmentPlanStatus.Planned
    assert stringPlan.ResultType == typeof(char)
    assert stringPlan.StringValues[0] == "values"
    ColumnarCodePlanExecutor.Validate(stringPlan)

    charEndpoint := ColumnarNameOfCharFromEndTree()
    charPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(
        charEndpoint.Nodes,
        charEndpoint.Source,
        charEndpoint.Root,
        ColumnarRangePlannerEmptyBindings(),
        ColumnarRangeIndexHandles.Resolve(),
        charPlan
    ) == ColumnarFragmentPlanStatus.Planned
    assert charPlan.ResultType == typeof(Index)
    assert charPlan.Int32Values[0] == (int)'A'
    ColumnarCodePlanExecutor.Validate(charPlan)
}

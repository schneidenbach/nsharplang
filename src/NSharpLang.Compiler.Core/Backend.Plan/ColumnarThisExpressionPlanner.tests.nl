namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

// A state machine's shape at runtime: argument 0 of its `MoveNext` is THIS object, which holds the
// object the source wrote `this` about in `Receiver` and hoists a same-named `Field` of its own.
class ColumnarThisExpressionMachineProbe {
    Receiver: ColumnarBoundIdentifierCurrentClassProbe
    Field: int

    constructor(receiver: ColumnarBoundIdentifierCurrentClassProbe) {
        Receiver = receiver
        Field = -1
    }
}

func ThisExpressionTree(parentheses: int): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    node := builder.AddLeaf(ColumnarExpressionNodeKind.ThisExpression, "this")
    i := 0
    while i < parentheses {
        node = builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(node))
        i = i + 1
    }
    return builder.Build(node)
}

func ThisExpressionPlan(bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    tree := ThisExpressionTree(0)
    plan := new ColumnarCodePlan()
    if ColumnarThisExpressionPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected this-expression ownership.")
    }

    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ThisExpressionMachineBindings(): ColumnarFragmentBindings {
    machineType := typeof(ColumnarThisExpressionMachineProbe)
    machineFacts := new ColumnarCurrentInstanceFacts(machineType, true)
    machineFacts.Fields["Field"] = BoundRequiredField(machineType, "Field")
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = machineFacts
    bindings.CapturedReceiverField = BoundRequiredField(machineType, "Receiver")
    return bindings
}

func ThisExpressionInvoke(plan: ColumnarCodePlan, name: string, returnType: Type, argumentType: Type, argument: object): object {
    parameterTypes := new Type[](1)
    parameterTypes[0] = argumentType
    method := BoundDynamicMethod(name, returnType, parameterTypes)
    il := method.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    il.Emit(OpCodes.Ret)
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, argument)
    target: object? = null
    result := method.Invoke(target, arguments)
    if result == null {
        throw new InvalidOperationException("The this-expression DynamicMethod returned null.")
    }
    return result
}

func ThisExpressionDisplay(name: string, enclosing: ColumnarStructDef): ColumnarStructDef {
    display := new ColumnarStructDef(
        TypeOfCreateBuilder(name, name + ".Tests", 0),
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        true,
        "<>c__DisplayClass0"
    )
    display.ClosureEnclosingDef = enclosing
    return display
}

func ThisExpressionReturnBody(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    value := builder.AddLeaf(ColumnarExpressionNodeKind.ThisExpression, "this")
    return MethodBodyFactsWrapValueInBody(builder, value, 0, "")
}

func ThisExpressionPlanReturnBody(currentInstance: ColumnarStructDef?, returnType: Type, plan: ColumnarCodePlan): bool {
    tree := ThisExpressionReturnBody()
    return ColumnarMethodBodyPlanner.TryPlanBody(
        tree.Nodes,
        tree.Source,
        tree.Root,
        returnType,
        false,
        MethodBodyFactsNoOrdinals(),
        MethodBodyFactsNoTypes(),
        MethodBodyFactsLocals(),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal),
        null,
        currentInstance,
        currentInstance,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        new Dictionary<string, string>(StringComparer.Ordinal),
        new string[](0),
        new string[](0),
        new string[](0),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        false,
        new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal),
        plan,
        null
    )
}

test "this in a class body is argument zero itself" {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = BoundCurrentFacts(typeof(ColumnarBoundIdentifierCurrentClassProbe), true)

    plan := ThisExpressionPlan(bindings)
    assert plan.ResultType == typeof(ColumnarBoundIdentifierCurrentClassProbe)
    assert plan.OperationCount == 1
    assert plan.ArgumentCount == 1
    assert plan.ArgumentOrdinals[0] == 0
    assert !plan.ArgumentIsAddress[0]
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()

    probe := new ColumnarBoundIdentifierCurrentClassProbe(3)
    result := ThisExpressionInvoke(plan, "ThisClassBody", typeof(ColumnarBoundIdentifierCurrentClassProbe), typeof(ColumnarBoundIdentifierCurrentClassProbe), probe)
    assert object.ReferenceEquals(result, probe)
}

test "this in a struct body is a copy of the value argument zero points at" {
    structType := typeof(ColumnarBoundIdentifierCurrentStructProbe)
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = BoundCurrentFacts(structType, false)

    plan := ThisExpressionPlan(bindings)
    assert plan.ResultType == structType
    assert plan.OperationCount == 2
    assert plan.ArgumentIsAddress[0]
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldobj()

    result := ThisExpressionInvoke(plan, "ThisStructBody", structType, structType.MakeByRefType(), new ColumnarBoundIdentifierCurrentStructProbe(12))
    assert ((ColumnarBoundIdentifierCurrentStructProbe)result).Field == 12
}

test "this reads the captured receiver when argument zero is a state machine" {
    plan := ThisExpressionPlan(ThisExpressionMachineBindings())
    assert plan.ResultType == typeof(ColumnarBoundIdentifierCurrentClassProbe)
    assert plan.OperationCount == 2
    assert plan.Types[plan.ArgumentTypeIndices[0]] == typeof(ColumnarThisExpressionMachineProbe)
    assert !plan.ArgumentIsAddress[0]
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert plan.Fields[0] == BoundRequiredField(typeof(ColumnarThisExpressionMachineProbe), "Receiver")

    receiver := new ColumnarBoundIdentifierCurrentClassProbe(8)
    machine := new ColumnarThisExpressionMachineProbe(receiver)
    result := ThisExpressionInvoke(plan, "ThisCapturedReceiver", typeof(ColumnarBoundIdentifierCurrentClassProbe), typeof(ColumnarThisExpressionMachineProbe), machine)
    assert object.ReferenceEquals(result, receiver)
}

test "this through a nested closure display walks one captured receiver per display" {
    owner := SourceCallDefinition("ColumnarThisDisplayOwner", true)
    outer := ThisExpressionDisplay("ColumnarThisDisplayOuter", owner)
    outerReceiver := ConstructionDefinePublicField(outer.Builder, ColumnarClosureBindingPlanner.CapturedEnclosingInstanceFieldName(), owner.Builder)
    outer.Fields[ColumnarClosureBindingPlanner.CapturedEnclosingInstanceFieldName()] = outerReceiver
    inner := ThisExpressionDisplay("ColumnarThisDisplayInner", outer)
    innerReceiver := ConstructionDefinePublicField(inner.Builder, ColumnarClosureBindingPlanner.CapturedEnclosingInstanceFieldName(), outer.Builder)
    inner.Fields[ColumnarClosureBindingPlanner.CapturedEnclosingInstanceFieldName()] = innerReceiver

    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(inner)
    plan := ThisExpressionPlan(bindings)
    ownerType: Type = owner.Builder
    assert plan.ResultType == ownerType
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldfld()
    assert object.ReferenceEquals(plan.Fields[0], innerReceiver)
    assert object.ReferenceEquals(plan.Fields[1], outerReceiver)

    // A display that captured no receiver has no `this` to give.
    uncaptured := ThisExpressionDisplay("ColumnarThisDisplayUncaptured", owner)
    uncapturedBindings := ColumnarRangePlannerEmptyBindings()
    uncapturedBindings.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(uncaptured)
    tree := ThisExpressionTree(0)
    declined := new ColumnarCodePlan()
    assert ColumnarThisExpressionPlanner.Plan(tree.Nodes, tree.Source, tree.Root, uncapturedBindings, declined) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(declined)
}

test "this declines without a current instance and leaves the plan empty" {
    tree := ThisExpressionTree(0)
    plan := new ColumnarCodePlan()
    assert ColumnarThisExpressionPlanner.Plan(tree.Nodes, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), plan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "a parenthesised this is the same root and the facade claims it" {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = BoundCurrentFacts(typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    tree := ThisExpressionTree(2)
    assert ColumnarThisExpressionPlanner.MayPlanRoot(tree.Nodes, tree.Root)
    assert ColumnarRangeIndexPlanner.FacadeRootMayNeedFacts(tree.Nodes, tree.Source, tree.Root)
    plan := new ColumnarCodePlan()
    assert ColumnarThisExpressionPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan) == ColumnarFragmentPlanStatus.Planned
    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
}

test "this is admitted as a call argument and appended as a nested value in a method body" {
    tree := ThisExpressionTree(0)
    assert ColumnarDirectCallPlanner.IsAdmittedValueSyntax(tree.Nodes, tree.Source, tree.Root, 0)

    bindings := ThisExpressionMachineBindings()
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    resultType := typeof(int)
    assert ColumnarRangeIndexPlanner.TryAppendConstructionValue(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan, -1, 0, out resultType)
    assert resultType == typeof(ColumnarBoundIdentifierCurrentClassProbe)
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
}

test "explicit this.Member in a generator body reads the object through the captured receiver" {
    owner := SourceCallDefinition("ColumnarThisReceiverOwner", true)
    ownerTag := ConstructionDefinePublicField(owner.Builder, "Tag", typeof(string))
    owner.Fields["Tag"] = ownerTag
    owner.Fields["hidden"] = ConstructionDefineField(owner.Builder, "hidden", typeof(string), 1)
    machine := TypeOfCreateBuilder("ColumnarThisReceiverMachine", "ColumnarThisReceiverMachine.Tests", 0)
    receiver := ConstructionDefinePublicField(machine, "<>__this", owner.Builder)
    hoisted := ConstructionDefinePublicField(machine, "Tag", typeof(int))
    machineFacts := new ColumnarCurrentInstanceFacts(machine, true)
    machineFacts.Fields["Tag"] = hoisted

    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = machineFacts
    bindings.SetEnclosingTypeDefinition(owner)

    // Without the captured receiver, argument 0 answers — the machine's hoisted `Tag`, not the object's.
    unanchored := BoundPlan(BoundExplicitThisTree("Tag"), bindings)
    assert unanchored.ResultType == typeof(int)

    bindings.CapturedReceiverField = receiver
    anchored := BoundPlan(BoundExplicitThisTree("Tag"), bindings)
    assert anchored.ResultType == typeof(string)
    assert anchored.OperationCount == 3
    assert anchored.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert anchored.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert anchored.OpCodeValues[2] == ColumnarCodePlanContract.Ldfld()
    assert object.ReferenceEquals(anchored.Fields[0], receiver)
    assert object.ReferenceEquals(anchored.Fields[1], ownerTag)

    // The bare name is still whatever the body binds it to.
    bare := BoundPlan(BoundIdentifierTree("Tag"), bindings)
    assert bare.ResultType == typeof(int)

    // A private member is out of the separate machine type's reach, so the explicit read declines.
    hiddenTree := BoundExplicitThisTree("hidden")
    hiddenPlan := new ColumnarCodePlan()
    assert ColumnarBoundIdentifierPlanner.Plan(hiddenTree.Nodes, hiddenTree.Source, hiddenTree.Root, bindings, hiddenPlan) == ColumnarFragmentPlanStatus.NotOwned
}

test "the method-body door claims return this through the same owner" {
    classOwner := SourceCallDefinition("ColumnarThisDoorClass", true)
    classPlan := new ColumnarCodePlan()
    assert ThisExpressionPlanReturnBody(classOwner, classOwner.Builder, classPlan)
    assert classPlan.OperationCount == 2
    assert !classPlan.ArgumentIsAddress[0]
    assert classPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert classPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()

    structOwner := SourceCallDefinition("ColumnarThisDoorStruct", false)
    structPlan := new ColumnarCodePlan()
    assert ThisExpressionPlanReturnBody(structOwner, structOwner.Builder, structPlan)
    assert structPlan.OperationCount == 3
    assert structPlan.ArgumentIsAddress[0]
    assert structPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert structPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldobj()
    assert structPlan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()

    // A static body has no instance: the door declines rather than hand out the first parameter.
    staticPlan := new ColumnarCodePlan()
    assert !ThisExpressionPlanReturnBody(null, typeof(object), staticPlan)
}

test "ldobj takes an exact managed address to its value type and nothing else" {
    structType := typeof(ColumnarBoundIdentifierCurrentStructProbe)
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.ThisExpression, 0)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), plan.AddArgument(0, plan.AddType(structType)))
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldobj(), plan.AddType(structType))
    plan.CompleteFragment(fragment, structType)

    // Argument 0 was pooled as a VALUE, so the row has no address to read through.
    threw := false
    try {
        plan.CompleteV3(structType)
        ColumnarCodePlanExecutor.Validate(plan)
    } catch ex: InvalidOperationException {
        threw = ex.Message.Contains("ldobj requires an exact managed address")
    }
    assert threw
}

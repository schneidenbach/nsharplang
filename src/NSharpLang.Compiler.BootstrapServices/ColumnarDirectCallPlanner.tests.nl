namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

struct ColumnarDirectCallMutableReceiverProbe {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func Increment(): void {
    }
}

class ColumnarDirectCallMutableHolderProbe {
    Counter: ColumnarDirectCallMutableReceiverProbe

    constructor(value: int) {
        Counter = new ColumnarDirectCallMutableReceiverProbe(value)
    }
}

func DirectCallAppendMember(builder: ColumnarRangePlannerNodeBuilder, receiver: int, memberName: string): int {
    memberStart := builder.AddToken(memberName)
    return builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, memberStart, memberName.Length, ColumnarRangePlannerChildren1(receiver))
}

func DirectCallAppendCall(builder: ColumnarRangePlannerNodeBuilder, callee: int, arguments: int[]): int {
    children := new int[](arguments.Length + 1)
    children[0] = callee
    index := 0
    while index < arguments.Length {
        children[index + 1] = arguments[index]
        index += 1
    }

    return builder.AddNode(ColumnarExpressionNodeKind.CallExpression(), -1, 0, 0, builder.Source.Length, children)
}

func DirectCallNoArguments(): int[] {
    return new int[](0)
}

func DirectCallOneArgument(first: int): int[] {
    result := new int[](1)
    result[0] = first
    return result
}

func DirectCallTwoArguments(first: int, second: int): int[] {
    result := new int[](2)
    result[0] = first
    result[1] = second
    return result
}

func DirectCallQualifiedTree(ownerName: string, memberName: string, argumentTexts: string[], argumentKinds: int[]): ColumnarRangePlannerTestTree {
    if argumentTexts.Length != argumentKinds.Length {
        throw new InvalidOperationException("Direct-call test argument text and kind counts must match.")
    }

    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerName)

    member := DirectCallAppendMember(builder, owner, memberName)
    arguments := new int[](argumentTexts.Length)
    index := 0
    while index < arguments.Length {
        arguments[index] = builder.AddLeaf(argumentKinds[index], argumentTexts[index])

        index += 1
    }

    root := DirectCallAppendCall(builder, member, arguments)
    return builder.Build(root)
}

func DirectCallParsedTree(source: string): ColumnarRangePlannerTestTree {
    probe := new ColumnarNumericLiteralParseProbe(source)
    if probe.NodeCount <= 0 || probe.ParseResult[0] < 0 {
        throw new InvalidOperationException("Direct-call parser fixture did not produce an expression tree.")
    }

    nodes := new ColumnarNodeTable(probe.NodeKinds, probe.NodeValueStarts, probe.NodeValueLengths, probe.NodeChildStarts, probe.NodeChildCounts, probe.NodeChildren, probe.NodeSpanStarts, probe.NodeSpanLengths)
    return new ColumnarRangePlannerTestTree(nodes, source, probe.ParseResult[0])
}

func DirectCallBareTree(memberName: string, argumentTexts: string[], argumentKinds: int[]): ColumnarRangePlannerTestTree {
    if argumentTexts.Length != argumentKinds.Length {
        throw new InvalidOperationException("Direct-call test argument text and kind counts must match.")
    }

    builder := new ColumnarRangePlannerNodeBuilder()
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), memberName)

    arguments := new int[](argumentTexts.Length)
    index := 0
    while index < arguments.Length {
        arguments[index] = builder.AddLeaf(argumentKinds[index], argumentTexts[index])

        index += 1
    }

    root := DirectCallAppendCall(builder, callee, arguments)
    return builder.Build(root)
}

func DirectCallInstanceTree(receiverName: string, memberName: string, argumentTexts: string[], argumentKinds: int[]): ColumnarRangePlannerTestTree {
    if argumentTexts.Length != argumentKinds.Length {
        throw new InvalidOperationException("Direct-call test argument text and kind counts must match.")
    }

    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)

    member := DirectCallAppendMember(builder, receiver, memberName)
    arguments := new int[](argumentTexts.Length)
    index := 0
    while index < arguments.Length {
        arguments[index] = builder.AddLeaf(argumentKinds[index], argumentTexts[index])

        index += 1
    }

    root := DirectCallAppendCall(builder, member, arguments)
    return builder.Build(root)
}

func DirectCallEmptyTexts(): string[] {
    return new string[](0)
}

func DirectCallEmptyKinds(): int[] {
    return new int[](0)
}

func DirectCallOneText(value: string): string[] {
    result := new string[](1)
    result[0] = value
    return result
}

func DirectCallOneKind(value: int): int[] {
    result := new int[](1)
    result[0] = value
    return result
}

func DirectCallBindings(definitions: ColumnarStructDef[]): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    return bindings
}

func DirectCallSingleDefinitionBindings(definition: ColumnarStructDef): ColumnarFragmentBindings {
    return DirectCallBindings(SourceCallDefinitions(definition))
}

func DirectCallPlan(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    ownership := ColumnarDirectCallOwnership.NotOwned
    _legacyWholeSubtreePlanning := false
    resultType := typeof(int)
    status := ColumnarDirectCallPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan, out ownership, out _legacyWholeSubtreePlanning, out resultType)

    if status != ColumnarFragmentPlanStatus.Planned || ownership != ColumnarDirectCallOwnership.Planned {
        throw new InvalidOperationException("Expected direct-call planner ownership.")
    }

    assert plan.ResultType == resultType
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func DirectCallRejected(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    resultType := typeof(int)
    legacyWholeSubtreePlanning = false
    status := ColumnarDirectCallPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)

    assert status == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
    return plan
}

func DirectCallHasMethod(plan: ColumnarCodePlan, name: string): bool {
    index := 0
    while index < plan.MethodCount {
        method := plan.Methods[index]
        if method != null && method.get_Name() == name {
            return true
        }

        index += 1
    }

    return false
}

func DirectCallSourceLocal(owner: ColumnarStructDef, valueType: Type): LocalBuilder {
    method := owner.Builder.DefineMethod("DirectCallLocalStorageProbe", (MethodAttributes)22, typeof(int), new Type[](0))

    il := TypeOfMethodBuilderIL(method)
    return il.DeclareLocal(valueType)
}

test "direct-call planner owns qualified and bare source static calls with exact overloads" {
    owner := SourceCallDefinition("DirectCallStaticOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    doubleParameters := new Type[](1)
    doubleParameters[0] = typeof(double)
    _intMethod := SourceCallPublicStatic(owner, "Pick", intParameters, typeof(int))

    _stringMethod := SourceCallPublicStatic(owner, "Pick", stringParameters, typeof(string))
    _doubleMethod := SourceCallPublicStatic(owner, "Pick", doubleParameters, typeof(double))

    explicitTree := DirectCallQualifiedTree("DirectCallStaticOwner", "Pick", DirectCallOneText("17"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    explicitPlan := DirectCallPlan(explicitTree, DirectCallSingleDefinitionBindings(owner))

    assert explicitPlan.ResultType == typeof(int)
    assert explicitPlan.OperationCount == 2
    assert explicitPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert explicitPlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert explicitPlan.Methods[explicitPlan.OperandIndices[1]].get_Name() == "Pick"

    floatingTree := DirectCallQualifiedTree("DirectCallStaticOwner", "Pick", DirectCallOneText("1.5"), DirectCallOneKind(ColumnarExpressionNodeKind.FloatLiteralExpression()))
    floatingPlan := DirectCallPlan(floatingTree, DirectCallSingleDefinitionBindings(owner))
    assert floatingPlan.ResultType == typeof(double)
    assert floatingPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcR8()

    bareBindings := DirectCallSingleDefinitionBindings(owner)
    bareBindings.SetEnclosingTypeDefinition(owner)
    bareTree := DirectCallBareTree("Pick", DirectCallOneText("\"chosen\""), DirectCallOneKind(ColumnarExpressionNodeKind.StringLiteralExpression()))

    barePlan := DirectCallPlan(bareTree, bareBindings)

    assert barePlan.ResultType == typeof(string)
    assert barePlan.OperationCount == 2
    assert barePlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert barePlan.Methods[barePlan.OperandIndices[1]].get_Name() == "Pick"
}

test "direct-call planner validates List of source values flowing to IReadOnlyList" {
    element := SourceCallDefinition("DirectCallSourceListElement", true)
    owner := SourceCallDefinition("DirectCallSourceListOwner", true)
    elementType: Type = element.Builder
    typeArguments := new Type[](1)
    typeArguments[0] = elementType
    listType := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)
    readOnlyListType := typeof(IReadOnlyList<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)

    parameterTypes := new Type[](1)
    parameterTypes[0] = readOnlyListType
    _consume := SourceCallPublicStatic(
        owner, "Consume", parameterTypes, typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "items", 0, listType)
    tree := DirectCallQualifiedTree(
        "DirectCallSourceListOwner",
        "Consume",
        DirectCallOneText("items"),
        DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    argumentIndex := plan.OperandIndices[0]
    actualType := plan.Types[plan.ArgumentTypeIndices[argumentIndex]]
    methodIndex := plan.OperandIndices[1]
    assert plan.MethodUsesDeclaredSignature[methodIndex]
    assert plan.Methods[methodIndex].get_Name() == "Consume"
    assert plan.MethodParameterTypes[methodIndex].Length == 1
    assert ColumnarReferenceConversionFacts.ExactTypeShapeMatches(
        actualType, listType)
    assert ColumnarReferenceConversionFacts.ExactTypeShapeMatches(
        plan.MethodParameterTypes[methodIndex][0], readOnlyListType)
}

test "direct-call planner emits exact duck-interface List Add flows for classes and structs" {
    notifier := SourceCallInterfaceDefinition(
        "DirectCallDuckListNotifier")
    referenceNotifier := SourceCallDefinition(
        "DirectCallDuckListClass", true)
    referenceNotifier.ImplementedInterfaces.Add(notifier)
    referenceNotifier.Builder.AddInterfaceImplementation(notifier.Builder)
    valueNotifier := SourceCallDefinition(
        "DirectCallDuckListStruct", false)
    valueNotifier.ImplementedInterfaces.Add(notifier)
    valueNotifier.Builder.AddInterfaceImplementation(notifier.Builder)
    valueNotifierType: Type = valueNotifier.Builder

    definitions := new ColumnarStructDef[](3)
    definitions[0] = notifier
    definitions[1] = referenceNotifier
    definitions[2] = valueNotifier

    notifierType: Type = notifier.Builder
    interfaceArguments := new Type[](1)
    interfaceArguments[0] = notifierType
    listType := typeof(List<int>)
        .GetGenericTypeDefinition()
        .MakeGenericType(interfaceArguments)
    tree := DirectCallInstanceTree(
        "notifiers",
        "Add",
        DirectCallOneText("notifier"),
        DirectCallOneKind(
            ColumnarExpressionNodeKind.IdentifierExpression()))

    referenceBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        referenceBindings, "notifiers", 0, listType)
    ColumnarRangePlannerAddParameter(
        referenceBindings,
        "notifier",
        1,
        referenceNotifier.Builder)
    referencePlan := DirectCallPlan(tree, referenceBindings)

    assert referencePlan.ResultType == SourceCallVoidType()
    assert referencePlan.OperationCount == 4
    assert referencePlan.OpCodeValues[0]
        == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.OpCodeValues[1]
        == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.OpCodeValues[2]
        == ColumnarCodePlanContract.Castclass()
    assert referencePlan.Types[referencePlan.OperandIndices[2]]
        == notifierType
    assert referencePlan.OpCodeValues[3]
        == ColumnarCodePlanContract.Callvirt()
    assert !ConversionDirectCallHasOpcode(
        referencePlan, ColumnarCodePlanContract.Box())
    referenceMethod := referencePlan.OperandIndices[3]
    assert referencePlan.Methods[referenceMethod].get_Name() == "Add"
    assert referencePlan.MethodParameterTypes[referenceMethod].Length == 1
    assert referencePlan.MethodParameterTypes[referenceMethod][0]
        == notifierType

    valueBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        valueBindings, "notifiers", 0, listType)
    ColumnarRangePlannerAddParameter(
        valueBindings,
        "notifier",
        1,
        valueNotifier.Builder)
    valuePlan := DirectCallPlan(tree, valueBindings)

    assert valuePlan.ResultType == SourceCallVoidType()
    assert valuePlan.OperationCount == 5
    assert valuePlan.OpCodeValues[0]
        == ColumnarCodePlanContract.Ldarg()
    assert valuePlan.OpCodeValues[1]
        == ColumnarCodePlanContract.Ldarg()
    assert valuePlan.OpCodeValues[2]
        == ColumnarCodePlanContract.Box()
    assert valuePlan.Types[valuePlan.OperandIndices[2]]
        == valueNotifierType
    assert valuePlan.OpCodeValues[3]
        == ColumnarCodePlanContract.Castclass()
    assert valuePlan.Types[valuePlan.OperandIndices[3]]
        == notifierType
    assert valuePlan.OpCodeValues[4]
        == ColumnarCodePlanContract.Callvirt()
    valueMethod := valuePlan.OperandIndices[4]
    assert valuePlan.Methods[valueMethod].get_Name() == "Add"
    assert valuePlan.MethodParameterTypes[valueMethod].Length == 1
    assert valuePlan.MethodParameterTypes[valueMethod][0]
        == notifierType
}

test "direct-call planner keeps unrelated duck-interface List Add terminally rejected" {
    target := SourceCallInterfaceDefinition(
        "DirectCallDuckListExactTarget")
    nearMiss := SourceCallInterfaceDefinition(
        "DirectCallDuckListNearMissTarget")
    target.DeclaredTypeName = "INotifier"
    nearMiss.DeclaredTypeName = "INotifier"

    implementer := SourceCallDefinition(
        "DirectCallDuckListNearMissClass", true)
    implementer.ImplementedInterfaces.Add(nearMiss)
    implementer.Builder.AddInterfaceImplementation(nearMiss.Builder)

    definitions := new ColumnarStructDef[](3)
    definitions[0] = target
    definitions[1] = nearMiss
    definitions[2] = implementer

    targetType: Type = target.Builder
    interfaceArguments := new Type[](1)
    interfaceArguments[0] = targetType
    listType := typeof(List<int>)
        .GetGenericTypeDefinition()
        .MakeGenericType(interfaceArguments)
    bindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        bindings, "notifiers", 0, listType)
    ColumnarRangePlannerAddParameter(
        bindings, "notifier", 1, implementer.Builder)
    tree := DirectCallInstanceTree(
        "notifiers",
        "Add",
        DirectCallOneText("notifier"),
        DirectCallOneKind(
            ColumnarExpressionNodeKind.IdentifierExpression()))

    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(
        tree,
        bindings,
        out ownership,
        out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner emits exact external IDisposable List Add flows" {
    disposableType := TypeOfRequiredRuntimeType(
        typeof(Type), "System.IDisposable")
    referenceDisposable := SourceCallDefinition(
        "DirectCallExternalDisposableClass", true)
    referenceDisposable.ExternalInterfaces.Add(disposableType)
    referenceDisposable.Builder.AddInterfaceImplementation(
        disposableType)
    valueDisposable := SourceCallDefinition(
        "DirectCallExternalDisposableStruct", false)
    valueDisposable.ExternalInterfaces.Add(disposableType)
    valueDisposable.Builder.AddInterfaceImplementation(
        disposableType)
    valueDisposableType: Type = valueDisposable.Builder

    definitions := new ColumnarStructDef[](2)
    definitions[0] = referenceDisposable
    definitions[1] = valueDisposable

    interfaceArguments := new Type[](1)
    interfaceArguments[0] = disposableType
    listType := typeof(List<int>)
        .GetGenericTypeDefinition()
        .MakeGenericType(interfaceArguments)
    tree := DirectCallInstanceTree(
        "items",
        "Add",
        DirectCallOneText("item"),
        DirectCallOneKind(
            ColumnarExpressionNodeKind.IdentifierExpression()))

    referenceBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        referenceBindings, "items", 0, listType)
    ColumnarRangePlannerAddParameter(
        referenceBindings,
        "item",
        1,
        referenceDisposable.Builder)
    referencePlan := DirectCallPlan(tree, referenceBindings)

    assert referencePlan.ResultType == SourceCallVoidType()
    assert referencePlan.OperationCount == 4
    assert referencePlan.OpCodeValues[0]
        == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.OpCodeValues[1]
        == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.OpCodeValues[2]
        == ColumnarCodePlanContract.Castclass()
    assert referencePlan.Types[referencePlan.OperandIndices[2]]
        == disposableType
    assert referencePlan.OpCodeValues[3]
        == ColumnarCodePlanContract.Callvirt()
    assert !ConversionDirectCallHasOpcode(
        referencePlan, ColumnarCodePlanContract.Box())
    referenceMethod := referencePlan.OperandIndices[3]
    assert referencePlan.Methods[referenceMethod].get_Name() == "Add"
    assert referencePlan.MethodParameterTypes[referenceMethod].Length == 1
    assert referencePlan.MethodParameterTypes[referenceMethod][0]
        == disposableType

    valueBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        valueBindings, "items", 0, listType)
    ColumnarRangePlannerAddParameter(
        valueBindings,
        "item",
        1,
        valueDisposable.Builder)
    valuePlan := DirectCallPlan(tree, valueBindings)

    assert valuePlan.ResultType == SourceCallVoidType()
    assert valuePlan.OperationCount == 5
    assert valuePlan.OpCodeValues[0]
        == ColumnarCodePlanContract.Ldarg()
    assert valuePlan.OpCodeValues[1]
        == ColumnarCodePlanContract.Ldarg()
    assert valuePlan.OpCodeValues[2]
        == ColumnarCodePlanContract.Box()
    assert valuePlan.Types[valuePlan.OperandIndices[2]]
        == valueDisposableType
    assert valuePlan.OpCodeValues[3]
        == ColumnarCodePlanContract.Castclass()
    assert valuePlan.Types[valuePlan.OperandIndices[3]]
        == disposableType
    assert valuePlan.OpCodeValues[4]
        == ColumnarCodePlanContract.Callvirt()
    valueMethod := valuePlan.OperandIndices[4]
    assert valuePlan.Methods[valueMethod].get_Name() == "Add"
    assert valuePlan.MethodParameterTypes[valueMethod].Length == 1
    assert valuePlan.MethodParameterTypes[valueMethod][0]
        == disposableType
}

test "direct-call planner terminally rejects external IDisposable near misses" {
    disposableType := TypeOfRequiredRuntimeType(
        typeof(Type), "System.IDisposable")
    comparableType := TypeOfRequiredRuntimeType(
        typeof(Type), "System.IComparable")
    sameSpelled := SourceCallInterfaceDefinition(
        "DirectCallExternalSameSpelledDisposable")
    sameSpelled.DeclaredTypeName = "IDisposable"
    sameSpelledImplementer := SourceCallDefinition(
        "DirectCallExternalSameSpelledDisposableClass", true)
    sameSpelledImplementer.ImplementedInterfaces.Add(sameSpelled)
    sameSpelledImplementer.Builder.AddInterfaceImplementation(
        sameSpelled.Builder)
    unsupported := SourceCallDefinition(
        "DirectCallExternalComparableClass", true)
    unsupported.ExternalInterfaces.Add(comparableType)
    unsupported.Builder.AddInterfaceImplementation(comparableType)
    unregistered := SourceCallDefinition(
        "DirectCallExternalUnregisteredDisposableClass", true)
    unregistered.Builder.AddInterfaceImplementation(disposableType)

    definitions := new ColumnarStructDef[](4)
    definitions[0] = sameSpelled
    definitions[1] = sameSpelledImplementer
    definitions[2] = unsupported
    definitions[3] = unregistered

    interfaceArguments := new Type[](1)
    interfaceArguments[0] = disposableType
    listType := typeof(List<int>)
        .GetGenericTypeDefinition()
        .MakeGenericType(interfaceArguments)
    tree := DirectCallInstanceTree(
        "items",
        "Add",
        DirectCallOneText("item"),
        DirectCallOneKind(
            ColumnarExpressionNodeKind.IdentifierExpression()))

    sameSpelledBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        sameSpelledBindings, "items", 0, listType)
    ColumnarRangePlannerAddParameter(
        sameSpelledBindings,
        "item",
        1,
        sameSpelledImplementer.Builder)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(
        tree,
        sameSpelledBindings,
        out ownership,
        out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning

    unsupportedBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        unsupportedBindings, "items", 0, listType)
    ColumnarRangePlannerAddParameter(
        unsupportedBindings,
        "item",
        1,
        unsupported.Builder)
    ownership = ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning = true
    DirectCallRejected(
        tree,
        unsupportedBindings,
        out ownership,
        out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning

    unregisteredBindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(
        unregisteredBindings, "items", 0, listType)
    ColumnarRangePlannerAddParameter(
        unregisteredBindings,
        "item",
        1,
        unregistered.Builder)
    ownership = ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning = true
    DirectCallRejected(
        tree,
        unregisteredBindings,
        out ownership,
        out legacyWholeSubtreePlanning)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner owns scoped runtime static calls with exact handles" {
    tree := DirectCallQualifiedTree("Type", "GetType", DirectCallOneText("\"System.String\""), DirectCallOneKind(ColumnarExpressionNodeKind.StringLiteralExpression()))

    ExternalStampScope(tree, "import System")

    plan := DirectCallPlan(tree, ColumnarRangePlannerEmptyBindings())

    assert plan.ResultType == typeof(Type)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    methodIndex := plan.OperandIndices[1]
    assert plan.Methods[methodIndex].get_Name() == "GetType"
    assert plan.MethodDeclaringTypes[methodIndex] == typeof(Type)
    assert plan.MethodParameterTypes[methodIndex].Length == 1
    assert plan.MethodParameterTypes[methodIndex][0] == typeof(string)
    assert plan.MethodReturnTypes[methodIndex] == typeof(Type)
}

test "direct-call planner owns fully qualified runtime static owner chains" {
    tree := DirectCallParsedTree("System.Object.ReferenceEquals(left, right)")
    ExternalStampScope(tree, "import System")

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "left", 0, typeof(MethodInfo))
    ColumnarRangePlannerAddParameter(bindings, "right", 1, typeof(MethodInfo))
    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(bool)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    methodIndex := plan.OperandIndices[2]
    assert plan.MethodDeclaringTypes[methodIndex] == typeof(object)
    assert plan.Methods[methodIndex].get_Name() == "ReferenceEquals"
    assert plan.MethodIsStatic[methodIndex]
}

test "direct-call planner owns String.Join over a List of string via the enumerable overload" {
    tree := DirectCallParsedTree("String.Join(sep, tags)")
    ExternalStampScope(tree, "import System\nimport System.Collections.Generic")

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "sep", 0, typeof(string))
    ColumnarRangePlannerAddParameter(bindings, "tags", 1, typeof(List<string>))
    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(string)
    // ldarg sep, ldarg tags, call Join. The List<string> flows to the IEnumerable<string>
    // parameter by ordinary reference upcast, so no cast instruction is emitted.
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    methodIndex := plan.OperandIndices[2]
    assert plan.Methods[methodIndex].get_Name() == "Join"
    assert plan.MethodDeclaringTypes[methodIndex] == typeof(string)
    assert plan.MethodIsStatic[methodIndex]
    assert plan.MethodParameterTypes[methodIndex].Length == 2
    assert plan.MethodParameterTypes[methodIndex][0] == typeof(string)
    assert plan.MethodParameterTypes[methodIndex][1] == typeof(IEnumerable<string>)
}

test "direct-call planner defers nested type-alias receivers but still owns direct aliases" {
    nestedTree := DirectCallParsedTree("ByteArrayPool.Shared.Rent(65536)")
    ExternalStampScope(nestedTree, "import System.Buffers\ntype ByteArrayPool = ArrayPool<byte>\n")

    ownership := ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning := false
    _nestedPlan := DirectCallRejected(nestedTree, ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning

    directTree := DirectCallParsedTree("MathAlias.Abs(7)")
    ExternalStampScope(directTree, "import System\ntype MathAlias = System.Math\n")

    directPlan := DirectCallPlan(directTree, ColumnarRangePlannerEmptyBindings())
    assert directPlan.ResultType == typeof(int)
    assert DirectCallHasMethod(directPlan, "Abs")
}

test "direct-call planner owns explicit and bare source reference receivers with callvirt" {
    owner := SourceCallDefinition("DirectCallReferenceOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    _selected := SourceCallPublicInstance(owner, "Measure", intParameters, typeof(int))

    explicitBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(explicitBindings, "receiver", 0, owner.Builder)

    explicitTree := DirectCallInstanceTree("receiver", "Measure", DirectCallOneText("9"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    explicitPlan := DirectCallPlan(explicitTree, explicitBindings)

    assert explicitPlan.ResultType == typeof(int)
    assert explicitPlan.OperationCount == 3
    assert explicitPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert !explicitPlan.ArgumentIsAddress[explicitPlan.OperandIndices[0]]
    assert explicitPlan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()
    assert explicitPlan.Methods[explicitPlan.OperandIndices[2]].get_Name() == "Measure"

    bareBindings := DirectCallSingleDefinitionBindings(owner)
    bareBindings.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(owner)

    bareTree := DirectCallBareTree("Measure", DirectCallOneText("10"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    barePlan := DirectCallPlan(bareTree, bareBindings)

    assert barePlan.OperationCount == 3
    assert barePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert barePlan.ArgumentOrdinals[barePlan.OperandIndices[0]] == 0
    assert barePlan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()
    assert barePlan.Methods[barePlan.OperandIndices[2]].get_Name() == "Measure"
}

test "direct-call planner reuses the implicit receiver slot across nested calls" {
    owner := SourceCallDefinition("DirectCallNestedImplicitOwner", true)
    noParameters := new Type[](0)
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    _inner := SourceCallPublicInstance(owner, "Inner", noParameters, typeof(int))
    _outer := SourceCallPublicInstance(owner, "Outer", oneInt, typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    bindings.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(owner)
    tree := DirectCallParsedTree("Outer(Inner())")

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.ArgumentCount == 1
    assert plan.ArgumentOrdinals[0] == 0
    assert plan.OperationCount == 4
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldarg()
    assert plan.OperandIndices[0] == plan.OperandIndices[1]
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()
    assert plan.Methods[plan.OperandIndices[2]].get_Name() == "Inner"
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Callvirt()
    assert plan.Methods[plan.OperandIndices[3]].get_Name() == "Outer"
}

test "direct-call planner declines synthetic contextual lambda instance frames atomically" {
    owner := SourceCallDefinition("DirectCallContextualLambdaOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    _selected := SourceCallPublicInstance(owner, "Measure", intParameters, typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    bindings.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(owner)
    ColumnarRangePlannerAddParameter(bindings, "lambdaValue", 0, typeof(int))

    tree := DirectCallBareTree("Measure", DirectCallOneText("lambdaValue"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner preserves value receiver storage and emits direct call" {
    owner := SourceCallDefinition("DirectCallValueOwner", false)
    noParameters := new Type[](0)
    _selected := SourceCallPublicInstance(owner, "Read", noParameters, typeof(int))

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "receiver", 0, owner.Builder)
    tree := DirectCallInstanceTree("receiver", "Read", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarga()
    assert plan.ArgumentOrdinals[plan.OperandIndices[0]] == 0
    assert !plan.ArgumentIsAddress[plan.OperandIndices[0]]
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[1]].get_Name() == "Read"
    assert plan.PlanLocalCount == 0

    localBindings := DirectCallSingleDefinitionBindings(owner)
    localBindings.Locals["receiver"] = DirectCallSourceLocal(owner, owner.Builder)
    localPlan := DirectCallPlan(tree, localBindings)

    assert localPlan.OperationCount == 2
    assert localPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloca()
    assert localPlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert localPlan.PlanLocalCount == 0
}

test "direct-call planner preserves an addressable value field receiver" {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("this.")
    counterStart := builder.AddToken("Counter")
    counter := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), counterStart, "Counter".Length, 0, builder.Source.Length, new int[](0))

    increment := DirectCallAppendMember(builder, counter, "Increment")
    root := DirectCallAppendCall(builder, increment, DirectCallNoArguments())
    tree := builder.Build(root)

    bindings := ColumnarRangePlannerEmptyBindings()
    facts := new ColumnarCurrentInstanceFacts(typeof(ColumnarDirectCallMutableHolderProbe), true)
    facts.Fields["Counter"] = BoundRequiredField(typeof(ColumnarDirectCallMutableHolderProbe), "Counter")
    bindings.CurrentInstance = facts

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType.FullName == "System.Void"
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldflda()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    assert plan.PlanLocalCount == 0
}

test "direct-call planner admits root void calls and records exact call shape" {
    owner := SourceCallDefinition("DirectCallVoidOwner", true)
    noParameters := new Type[](0)
    _selected := SourceCallPublicStatic(owner, "Reset", noParameters, SourceCallVoidType())

    tree := DirectCallQualifiedTree("DirectCallVoidOwner", "Reset", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    plan := DirectCallPlan(tree, DirectCallSingleDefinitionBindings(owner))

    assert plan.ResultType != null
    assert plan.ResultType.FullName == "System.Void"
    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[0]].get_Name() == "Reset"
    assert plan.FragmentOperationCounts[0] == 1
}

test "direct-call planner rejects bad source shapes and owns target-typed reference null" {
    owner := SourceCallDefinition("DirectCallRejectedOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    SourceCallPublicStatic(owner, "Pick", intParameters, typeof(int))
    SourceCallPublicInstance(owner, "Measure", intParameters, typeof(int))
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    _nullableMethod := SourceCallPublicStatic(owner, "NullableTarget", stringParameters, typeof(int))
    SourceCallDefineStatic(owner, "Hidden", intParameters, new int[](0), typeof(int), (MethodAttributes)17)
    paramsTypes := new Type[](1)
    paramsTypes[0] = typeof(int[])
    paramsKinds := new int[](1)
    paramsKinds[0] = 3
    _paramsMethod := SourceCallDefineStatic(owner, "Expanded", paramsTypes, paramsKinds, typeof(int), (MethodAttributes)22)

    bindings := DirectCallSingleDefinitionBindings(owner)

    badType := DirectCallQualifiedTree("DirectCallRejectedOwner", "Pick", DirectCallOneText("\"wrong\""), DirectCallOneKind(ColumnarExpressionNodeKind.StringLiteralExpression()))

    badTypeOwnership := ColumnarDirectCallOwnership.NotOwned
    badTypeLegacy := false
    DirectCallRejected(badType, bindings, out badTypeOwnership, out badTypeLegacy)
    assert badTypeOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !badTypeLegacy

    badArity := DirectCallQualifiedTree("DirectCallRejectedOwner", "Pick", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    badArityOwnership := ColumnarDirectCallOwnership.NotOwned
    badArityLegacy := false
    DirectCallRejected(badArity, bindings, out badArityOwnership, out badArityLegacy)
    assert badArityOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !badArityLegacy

    inaccessible := DirectCallQualifiedTree("DirectCallRejectedOwner", "Hidden", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    inaccessibleOwnership := ColumnarDirectCallOwnership.NotOwned
    inaccessibleLegacy := false
    DirectCallRejected(inaccessible, bindings, out inaccessibleOwnership, out inaccessibleLegacy)
    assert inaccessibleOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !inaccessibleLegacy

    instanceBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(instanceBindings, "receiver", 0, owner.Builder)

    badInstanceArity := DirectCallInstanceTree("receiver", "Measure", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    badInstanceOwnership := ColumnarDirectCallOwnership.NotOwned
    badInstanceLegacy := false
    DirectCallRejected(badInstanceArity, instanceBindings, out badInstanceOwnership, out badInstanceLegacy)

    assert badInstanceOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !badInstanceLegacy

    absentInstance := DirectCallInstanceTree("receiver", "Missing", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    absentInstanceOwnership := ColumnarDirectCallOwnership.OwnedRejected
    absentInstanceLegacy := false
    DirectCallRejected(absentInstance, instanceBindings, out absentInstanceOwnership, out absentInstanceLegacy)

    assert absentInstanceOwnership == ColumnarDirectCallOwnership.NotOwned
    assert absentInstanceLegacy

    expandedTexts := new string[](2)
    expandedTexts[0] = "1"
    expandedTexts[1] = "2"
    expandedKinds := new int[](2)
    expandedKinds[0] = ColumnarExpressionNodeKind.IntLiteralExpression()
    expandedKinds[1] = ColumnarExpressionNodeKind.IntLiteralExpression()
    expanded := DirectCallQualifiedTree("DirectCallRejectedOwner", "Expanded", expandedTexts, expandedKinds)
    expandedOwnership := ColumnarDirectCallOwnership.OwnedRejected
    expandedLegacy := true
    DirectCallRejected(expanded, bindings, out expandedOwnership, out expandedLegacy)
    assert expandedOwnership == ColumnarDirectCallOwnership.NotOwned
    assert expandedLegacy

    nullArgument := DirectCallQualifiedTree("DirectCallRejectedOwner", "NullableTarget", DirectCallOneText("null"), DirectCallOneKind(ColumnarExpressionNodeKind.NullLiteralExpression()))
    nullPlan := DirectCallPlan(nullArgument, bindings)

    assert nullPlan.OperationCount == 2
    assert nullPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldnull()
    assert nullPlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    nullMethodIndex := nullPlan.OperandIndices[1]
    assert nullMethodIndex >= 0 && nullMethodIndex < nullPlan.MethodCount
    nullParameters := nullPlan.MethodParameterTypes[nullMethodIndex]
    assert nullParameters.Length == 1
    assert nullParameters[0] == typeof(string)
}

test "direct-call planner leaves generic extension and ref-out source families to their owners" {
    owner := SourceCallDefinition("DirectCallExcludedOwner", true)
    ownerType: Type = owner.Builder
    noParameters := new Type[](0)
    genericInstance := SourceCallPublicInstance(owner, "GenericInstance", noParameters, typeof(int))
    SourceCallMakeGeneric(genericInstance.Builder)
    genericStatic := SourceCallPublicStatic(owner, "GenericStatic", noParameters, typeof(int))
    SourceCallMakeGeneric(genericStatic.Builder)

    byRefValueType := InstanceByRefType("RuntimeValue")
    byRefTypes := new Type[](1)
    byRefTypes[0] = byRefValueType
    refKinds := new int[](1)
    refKinds[0] = 1
    SourceCallDefineInstance(owner, "RefCall", byRefTypes, refKinds, typeof(int), (MethodAttributes)6)
    outKinds := new int[](1)
    outKinds[0] = 2
    SourceCallDefineInstance(owner, "OutCall", byRefTypes, outKinds, typeof(int), (MethodAttributes)6)

    extensionTypes := new Type[](1)
    extensionTypes[0] = ownerType
    extensionKinds := new int[](1)
    extensionKinds[0] = 4
    SourceCallDefineStatic(owner, "ExtensionCall", extensionTypes, extensionKinds, typeof(int), (MethodAttributes)22)

    definitions := DirectCallSingleDefinitionBindings(owner)

    instanceBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(instanceBindings, "receiver", 0, owner.Builder)
    ColumnarRangePlannerAddParameter(instanceBindings, "value", 1, typeof(int))

    genericInstanceTree := DirectCallInstanceTree("receiver", "GenericInstance", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    genericInstanceOwnership := ColumnarDirectCallOwnership.OwnedRejected
    genericInstanceLegacy := true
    DirectCallRejected(genericInstanceTree, instanceBindings, out genericInstanceOwnership, out genericInstanceLegacy)
    assert genericInstanceOwnership == ColumnarDirectCallOwnership.NotOwned
    assert genericInstanceLegacy

    genericStaticTree := DirectCallQualifiedTree("DirectCallExcludedOwner", "GenericStatic", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    genericStaticOwnership := ColumnarDirectCallOwnership.OwnedRejected
    genericStaticLegacy := true
    DirectCallRejected(genericStaticTree, definitions, out genericStaticOwnership, out genericStaticLegacy)
    assert genericStaticOwnership == ColumnarDirectCallOwnership.NotOwned
    assert genericStaticLegacy

    refTree := DirectCallInstanceTree("receiver", "RefCall", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    refOwnership := ColumnarDirectCallOwnership.OwnedRejected
    refLegacy := true
    DirectCallRejected(refTree, instanceBindings, out refOwnership, out refLegacy)
    assert refOwnership == ColumnarDirectCallOwnership.NotOwned
    assert refLegacy

    outTree := DirectCallInstanceTree("receiver", "OutCall", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    outOwnership := ColumnarDirectCallOwnership.OwnedRejected
    outLegacy := true
    DirectCallRejected(outTree, instanceBindings, out outOwnership, out outLegacy)
    assert outOwnership == ColumnarDirectCallOwnership.NotOwned
    assert outLegacy

    extensionTree := DirectCallQualifiedTree("DirectCallExcludedOwner", "ExtensionCall", DirectCallOneText("receiver"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    extensionOwnership := ColumnarDirectCallOwnership.OwnedRejected
    extensionLegacy := true
    DirectCallRejected(extensionTree, instanceBindings, out extensionOwnership, out extensionLegacy)
    assert extensionOwnership == ColumnarDirectCallOwnership.NotOwned
    assert extensionLegacy
}

test "direct-call planner still owns an exact ordinary overload beside an excluded overload" {
    owner := SourceCallDefinition("DirectCallMixedOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    SourceCallPublicStatic(owner, "Pick", intParameters, typeof(int))

    paramsTypes := new Type[](1)
    paramsTypes[0] = typeof(int[])
    paramsKinds := new int[](1)
    paramsKinds[0] = 3
    SourceCallDefineStatic(owner, "Pick", paramsTypes, paramsKinds, typeof(int), (MethodAttributes)22)

    tree := DirectCallQualifiedTree("DirectCallMixedOwner", "Pick", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    plan := DirectCallPlan(tree, DirectCallSingleDefinitionBindings(owner))

    assert plan.ResultType == typeof(int)
    assert plan.OpCodeValues[plan.OperationCount - 1] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[plan.OperationCount - 1]].get_Name() == "Pick"
}

test "direct-call planner emits abstract interface dispatch and rolls back malformed handles" {
    abstraction := SourceCallInterfaceDefinition("DirectCallInterfaceOwner")
    noParameters := new Type[](0)
    _abstractMethod := SourceCallDefineInstance(abstraction, "Read", noParameters, new int[](0), typeof(int), (MethodAttributes)1094)

    abstractBindings := DirectCallSingleDefinitionBindings(abstraction)
    ColumnarRangePlannerAddParameter(abstractBindings, "receiver", 0, abstraction.Builder)

    abstractTree := DirectCallInstanceTree("receiver", "Read", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    abstractPlan := DirectCallPlan(abstractTree, abstractBindings)

    assert abstractPlan.OperationCount == 2
    assert abstractPlan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    methodIndex := abstractPlan.OperandIndices[1]
    assert abstractPlan.Methods[methodIndex].get_Name() == "Read"
    assert abstractPlan.MethodIsAbstract[methodIndex]

    malformedOwner := SourceCallDefinition("DirectCallMalformedOwner", true)
    malformed := SourceCallPublicStatic(malformedOwner, "Broken", noParameters, typeof(int))

    malformed.ReturnType = typeof(string)
    malformedTree := DirectCallQualifiedTree("DirectCallMalformedOwner", "Broken", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    malformedBindings := DirectCallSingleDefinitionBindings(malformedOwner)
    malformedPlan := new ColumnarCodePlan()
    malformedOwnership := ColumnarDirectCallOwnership.NotOwned
    _malformedLegacyChildPlanning := false
    malformedResult := typeof(int)
    assert throws InvalidOperationException {
        ColumnarDirectCallPlanner.Plan(malformedTree.Nodes, malformedTree.Source, malformedTree.Root, malformedBindings, malformedPlan, out malformedOwnership, out _malformedLegacyChildPlanning, out malformedResult)
    }

    ColumnarRangePlannerAssertEmptyRollback(malformedPlan)
}

test "direct-call planner recursively owns nested calls and range-index arguments" {
    owner := SourceCallDefinition("DirectCallRecursiveOwner", true)
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    twoInts := new Type[](2)
    twoInts[0] = typeof(int)
    twoInts[1] = typeof(int)
    SourceCallPublicStatic(owner, "Increment", oneInt, typeof(int))
    SourceCallPublicStatic(owner, "Combine", twoInts, typeof(int))

    builder := new ColumnarRangePlannerNodeBuilder()
    innerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "DirectCallRecursiveOwner")

    innerMember := DirectCallAppendMember(builder, innerOwner, "Increment")
    one := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    innerCall := DirectCallAppendCall(builder, innerMember, DirectCallOneArgument(one))

    values := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")

    caret := builder.AddToken("^")
    fromEndValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")

    fromEnd := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), caret, 1, caret, 2, ColumnarRangePlannerChildren1(fromEndValue))

    indexed := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(values, fromEnd))

    outerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "DirectCallRecursiveOwner")

    outerMember := DirectCallAppendMember(builder, outerOwner, "Combine")
    root := DirectCallAppendCall(builder, outerMember, DirectCallTwoArguments(innerCall, indexed))

    tree := builder.Build(root)
    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "values", 0, typeof(int[]))
    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.FragmentCount >= 6
    assert DirectCallHasMethod(plan, "Increment")
    assert DirectCallHasMethod(plan, "Combine")
    last := plan.OperationCount - 1
    assert plan.OpCodeValues[last] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[last]].get_Name() == "Combine"
}

test "direct-call planner executes persisted reference and void runtime handles" {
    randomTexts := new string[](2)
    randomTexts[0] = "10"
    randomTexts[1] = "11"
    randomKinds := new int[](2)
    randomKinds[0] = ColumnarExpressionNodeKind.IntLiteralExpression()
    randomKinds[1] = ColumnarExpressionNodeKind.IntLiteralExpression()
    randomTree := DirectCallInstanceTree("random", "Next", randomTexts, randomKinds)

    randomBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(randomBindings, "random", 0, typeof(Random))

    randomPlan := DirectCallPlan(randomTree, randomBindings)

    assert randomPlan.OpCodeValues[randomPlan.OperationCount - 1] == ColumnarCodePlanContract.Callvirt()

    randomParameters := new Type[](1)
    randomParameters[0] = typeof(Random)
    randomMethod := BoundDynamicMethod("DirectCallPersistedRandom", typeof(int), randomParameters)

    randomIl := randomMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(randomPlan, randomIl)
    randomIl.Emit(OpCodes.Ret)
    randomArguments := new object[](1)
    randomConstructorTypes := new Type[](1)
    randomConstructorTypes[0] = typeof(int)
    randomConstructor := ExecutorRequiredConstructor(typeof(Random), randomConstructorTypes)

    randomConstructorArguments := new object[](1)
    ExecutorSetObject(randomConstructorArguments, 0, 1234)
    randomValue := TypeOfRequiredConstruction(randomConstructor, randomConstructorArguments)

    ExecutorSetObject(randomArguments, 0, randomValue)
    assert BoundInvokeText(randomMethod, randomArguments) == "10"

    textWriterType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.TextWriter")

    writerTree := DirectCallInstanceTree("writer", "WriteLine", DirectCallOneText("\"persisted\""), DirectCallOneKind(ColumnarExpressionNodeKind.StringLiteralExpression()))

    writerBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(writerBindings, "writer", 0, textWriterType)

    writerPlan := DirectCallPlan(writerTree, writerBindings)

    assert writerPlan.ResultType != null
    assert writerPlan.ResultType.FullName == "System.Void"
    assert writerPlan.OpCodeValues[writerPlan.OperationCount - 1] == ColumnarCodePlanContract.Callvirt()

    writerParameters := new Type[](1)
    writerParameters[0] = textWriterType
    stringWriterType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.StringWriter")

    noConstructorTypes := new Type[](0)
    writerConstructor := ExecutorRequiredConstructor(stringWriterType, noConstructorTypes)

    noConstructorArguments := new object[](0)
    writer := TypeOfRequiredConstruction(writerConstructor, noConstructorArguments)

    writerArguments := new object[](1)
    ExecutorSetObject(writerArguments, 0, writer)
    ExecutorRunV3VoidPlan(writerPlan, writerParameters, writerArguments)
    assert writer.ToString().Contains("persisted")
}

test "direct-call planner preserves exact constructed generic runtime returns" {
    streamReaderType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.StreamReader")
    tree := DirectCallInstanceTree("reader", "ReadToEndAsync", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "reader", 0, streamReaderType)

    plan := DirectCallPlan(tree, bindings)
    expectedReturnType := typeof(Task<string>)
    last := plan.OperationCount - 1
    methodIndex := plan.OperandIndices[last]

    assert plan.ResultType == expectedReturnType
    assert plan.OpCodeValues[last] == ColumnarCodePlanContract.Callvirt()
    assert plan.MethodDeclaringTypes[methodIndex] == streamReaderType
    assert plan.MethodReturnTypes[methodIndex] == expectedReturnType
    assert plan.Methods[methodIndex].get_ReturnType() == expectedReturnType
}

// Build a sibling MethodBuilder on a throwaway program-type host and wrap it as ordinary,
// non-generic sibling facts. The host is never installed as an enclosing/source definition, so the
// planner sees the method only through SiblingCallables.
func DirectCallSiblingFacts(hostName: string, name: string, parameterTypes: Type[], returnType: Type): ColumnarSiblingCallFacts {
    host := SourceCallDefinition(hostName, true)
    method := host.Builder.DefineMethod(name, (MethodAttributes)22, returnType, parameterTypes)
    return new ColumnarSiblingCallFacts(method, parameterTypes, new int[](0), returnType, 0)
}

func DirectCallSiblingFactsWithModifiers(hostName: string, name: string, parameterTypes: Type[], modifierKinds: int[], returnType: Type, typeParameterCount: int): ColumnarSiblingCallFacts {
    host := SourceCallDefinition(hostName, true)
    method := host.Builder.DefineMethod(name, (MethodAttributes)22, returnType, parameterTypes)
    return new ColumnarSiblingCallFacts(method, parameterTypes, modifierKinds, returnType, typeParameterCount)
}

func DirectCallSiblingBindings(name: string, facts: ColumnarSiblingCallFacts): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SiblingCallables[name] = facts
    return bindings
}

func DirectCallLocalFunctionBindings(name: string): ColumnarFragmentBindings {
    visibleFunctions := new HashSet<string>(StringComparer.Ordinal)
    visibleFunctions.Add(name)
    return new ColumnarFragmentBindings(new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), new Dictionary<string, LocalBuilder>(StringComparer.Ordinal), new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal), new HashSet<string>(StringComparer.Ordinal), visibleFunctions)
}

test "direct-call planner owns a zero-argument sibling call" {
    facts := DirectCallSiblingFacts("DirectCallSiblingZeroHost", "Ping", new Type[](0), typeof(int))
    bindings := DirectCallSiblingBindings("Ping", facts)
    tree := DirectCallBareTree("Ping", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[0]].get_Name() == "Ping"
    assert plan.MethodIsStatic[plan.OperandIndices[0]]
}

test "direct-call planner owns a multi-argument sibling call with exact literal arguments" {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(int)
    facts := DirectCallSiblingFacts("DirectCallSiblingAddHost", "Add", parameterTypes, typeof(int))
    bindings := DirectCallSiblingBindings("Add", facts)

    argumentTexts := new string[](2)
    argumentTexts[0] = "3"
    argumentTexts[1] = "4"
    argumentKinds := new int[](2)
    argumentKinds[0] = ColumnarExpressionNodeKind.IntLiteralExpression()
    argumentKinds[1] = ColumnarExpressionNodeKind.IntLiteralExpression()
    tree := DirectCallBareTree("Add", argumentTexts, argumentKinds)

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[2]].get_Name() == "Add"
}

test "direct-call planner plans a sibling call nested as a sibling argument" {
    innerFacts := DirectCallSiblingFacts("DirectCallSiblingNestedInnerHost", "Inner", new Type[](0), typeof(int))
    outerParameters := new Type[](1)
    outerParameters[0] = typeof(int)
    outerFacts := DirectCallSiblingFacts("DirectCallSiblingNestedOuterHost", "Outer", outerParameters, typeof(int))

    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SiblingCallables["Inner"] = innerFacts
    bindings.SiblingCallables["Outer"] = outerFacts
    tree := DirectCallParsedTree("Outer(Inner())")

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[0]].get_Name() == "Inner"
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[1]].get_Name() == "Outer"
}

test "direct-call planner plans a sibling call as a binary equality operand" {
    facts := DirectCallSiblingFacts("DirectCallSiblingBinaryEqualityHost", "Answer", new Type[](0), typeof(int))
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SiblingCallables["Answer"] = facts
    tree := DirectCallParsedTree("Answer() == 42")

    plan := new ColumnarCodePlan()
    owned := false
    wholeSubtree := false
    resultType := typeof(int)
    assert ColumnarPrimitiveBinaryPlanner.TryGetTypeRoot(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out owned, out wholeSubtree, out resultType)

    assert owned
    assert resultType == typeof(bool)
    assert DirectCallHasMethod(plan, "Answer")
    ColumnarCodePlanExecutor.Validate(plan)
}

test "direct-call planner plans two sibling calls as an additive binary" {
    leftFacts := DirectCallSiblingFacts("DirectCallSiblingBinaryLeftHost", "Left", new Type[](0), typeof(int))
    rightParameters := new Type[](1)
    rightParameters[0] = typeof(int)
    rightFacts := DirectCallSiblingFacts("DirectCallSiblingBinaryRightHost", "Right", rightParameters, typeof(int))

    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SiblingCallables["Left"] = leftFacts
    bindings.SiblingCallables["Right"] = rightFacts
    tree := DirectCallParsedTree("Left() + Right(1)")

    plan := new ColumnarCodePlan()
    owned := false
    wholeSubtree := false
    resultType := typeof(int)
    assert ColumnarPrimitiveBinaryPlanner.TryGetTypeRoot(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out owned, out wholeSubtree, out resultType)

    assert owned
    assert resultType == typeof(int)
    assert DirectCallHasMethod(plan, "Left")
    assert DirectCallHasMethod(plan, "Right")
    ColumnarCodePlanExecutor.Validate(plan)
}

test "direct-call planner invokes a delegate-typed parameter through Invoke" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "zero", 0, typeof(Func<int>))
    tree := DirectCallParsedTree("zero()")

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    methodIndex := plan.OperandIndices[1]
    assert plan.Methods[methodIndex].get_Name() == "Invoke"
    assert plan.MethodDeclaringTypes[methodIndex] == typeof(Func<int>)
    assert !plan.MethodIsStatic[methodIndex]
    assert plan.MethodReturnTypes[methodIndex] == typeof(int)
}

test "direct-call planner invokes a delegate-typed value with an exact argument" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "add", 0, typeof(Func<int, int>))
    ColumnarRangePlannerAddParameter(bindings, "x", 1, typeof(int))
    tree := DirectCallParsedTree("add(x)")

    plan := DirectCallPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()
    methodIndex := plan.OperandIndices[2]
    assert plan.Methods[methodIndex].get_Name() == "Invoke"
    assert plan.MethodParameterTypes[methodIndex].Length == 1
    assert plan.MethodParameterTypes[methodIndex][0] == typeof(int)
}

test "direct-call planner plans a delegate invocation as a binary equality operand" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "zero", 0, typeof(Func<int>))
    tree := DirectCallParsedTree("zero() == 42")

    plan := new ColumnarCodePlan()
    owned := false
    wholeSubtree := false
    resultType := typeof(int)
    assert ColumnarPrimitiveBinaryPlanner.TryGetTypeRoot(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out owned, out wholeSubtree, out resultType)

    assert owned
    assert resultType == typeof(bool)
    assert DirectCallHasMethod(plan, "Invoke")
    ColumnarCodePlanExecutor.Validate(plan)
}

test "direct-call planner yields the whole subtree for a non-delegate value call" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "count", 0, typeof(int))
    tree := DirectCallParsedTree("count()")

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner yields the whole subtree for a delegate argument mismatch" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "add", 0, typeof(Func<int, int>))
    ColumnarRangePlannerAddParameter(bindings, "text", 1, typeof(string))
    tree := DirectCallParsedTree("add(text)")

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner yields the whole subtree for a delegate arity mismatch" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "zero", 0, typeof(Func<int>))
    ColumnarRangePlannerAddParameter(bindings, "x", 1, typeof(int))
    tree := DirectCallParsedTree("zero(x)")

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner yields the whole subtree for a sibling arity mismatch" {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    facts := DirectCallSiblingFacts("DirectCallSiblingArityHost", "Need", parameterTypes, typeof(int))
    bindings := DirectCallSiblingBindings("Need", facts)
    tree := DirectCallBareTree("Need", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner yields the whole subtree for a generic sibling call" {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    facts := DirectCallSiblingFactsWithModifiers("DirectCallSiblingGenericHost", "Identity", parameterTypes, new int[](0), typeof(int), 1)
    bindings := DirectCallSiblingBindings("Identity", facts)
    tree := DirectCallBareTree("Identity", DirectCallOneText("5"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner yields the whole subtree for a by-ref sibling parameter" {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int).MakeByRefType()
    modifierKinds := new int[](1)
    modifierKinds[0] = (int)ParameterModifier.Ref
    facts := DirectCallSiblingFactsWithModifiers("DirectCallSiblingByRefHost", "Bump", parameterTypes, modifierKinds, typeof(int), 0)
    bindings := DirectCallSiblingBindings("Bump", facts)
    tree := DirectCallBareTree("Bump", DirectCallOneText("5"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner yields the whole subtree when a value binding shadows a sibling" {
    facts := DirectCallSiblingFacts("DirectCallSiblingShadowHost", "Shadowed", new Type[](0), typeof(int))
    bindings := DirectCallSiblingBindings("Shadowed", facts)
    ColumnarRangePlannerAddParameter(bindings, "Shadowed", 0, typeof(int))
    tree := DirectCallBareTree("Shadowed", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner declines a visible local-function call without owning it" {
    bindings := DirectCallLocalFunctionBindings("Helper")
    tree := DirectCallBareTree("Helper", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    ownership := ColumnarDirectCallOwnership.Planned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert !legacyWholeSubtreePlanning
}


// ---- 015-B13: THE NINTH ARGUMENT SITE, AND THE RECEIVER PAIR THAT IS NOT ONE ----

// ⚠ THE DELEGATE-INVOKE ARGUMENT LOOP IS THE ONE ARGUMENT LIST THAT DOES NOT ROUTE THROUGH
// `AppendArguments`, WHICH IS WHY `015-B9`'s THREADING NEVER REACHED IT.
//
// `015-B12`'s census listed this site with the two RECEIVER sites as one family of "hard-coded PLAIN
// inner positions". It is not the same question. `TryGetArgumentTypes` is called EXACTLY ONCE in the
// whole tree, with `ArgumentsAdmitPrimitiveBinary()`, and `TryAppendBareCall` hands the very
// `argumentTypes` it produced into `TryAppendDelegateInvoke` — so this site's TYPE side already
// admitted a primitive binary while its APPEND side refused one. `d(x + y)` therefore typed and then
// FAILED at the append, which is precisely the "a type side that admitted more than the append side
// would only manufacture declines one step later" that the RECEIVER comment states as its own reason.
// Reading the same named decision the other eight sites read makes the two sides agree; it adds no
// rule.
test "the delegate-invoke argument surface is the one its own type side already admitted" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "add", 0, typeof(Func<int, int>))
    ColumnarRangePlannerAddParameter(bindings, "x", 1, typeof(int))
    ColumnarRangePlannerAddParameter(bindings, "y", 2, typeof(int))

    plan := DirectCallPlan(DirectCallParsedTree("add(x + y)"), bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 5
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Add()
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Callvirt()
    assert plan.Methods[plan.OperandIndices[4]].get_Name() == "Invoke"

    // The ordinary argument stays exactly as it was — the widening is a SUPERSET, not a reroute.
    plainBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(plainBindings, "add", 0, typeof(Func<int, int>))
    ColumnarRangePlannerAddParameter(plainBindings, "x", 1, typeof(int))
    plainPlan := DirectCallPlan(DirectCallParsedTree("add(x)"), plainBindings)
    assert plainPlan.OperationCount == 3
    assert plainPlan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()

    // ONE decision, ONE home, ONE mutation anchor — now read by NINE sites rather than eight.
    assert ColumnarDirectCallPlanner.ArgumentsAdmitPrimitiveBinary()
}

// ⚠ THE RECEIVER PAIR IS PINNED, AND THE PIN IS ASSERTED RATHER THAN LEFT AS A COMMENT.
//
// `AppendExtensionReceiver` and `AppendExplicitReceiver` still hard-code the PLAIN surface, and unlike
// the delegate-invoke argument above they are CONSISTENT with their type side: `TryAppendMemberCall`
// passes a matching `false` to `TryGetPlannableValueType`, with the rule written beside it. So a
// binary RECEIVER declines on both sides and belongs to the host, while a binary ARGUMENT is planned.
// This block holds the two halves apart so a future slice that widens one and not the other breaks a
// contract instead of merely diverging.
test "the receiver surface stays plain on both sides while the argument surface admits a binary" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "x", 0, typeof(int))
    ColumnarRangePlannerAddParameter(bindings, "y", 1, typeof(int))

    receiverPlan := new ColumnarCodePlan()
    receiverOwnership := ColumnarDirectCallOwnership.Planned
    receiverLegacy := false
    receiverType := typeof(int)
    receiverTree := DirectCallParsedTree("(x + y).ToString()")
    receiverStatus := ColumnarDirectCallPlanner.Plan(receiverTree.Nodes, receiverTree.Source, receiverTree.Root, bindings, receiverPlan, out receiverOwnership, out receiverLegacy, out receiverType)
    assert receiverStatus != ColumnarFragmentPlanStatus.Planned
    assert receiverOwnership != ColumnarDirectCallOwnership.Planned

    // ⚠ THE OUTS ARE ASSERTED, NOT JUST THE OUTCOME, AND `015-B13`'s CONTROL `C7` IS WHY.
    // `C7` widened the TYPE side alone (`TryGetPlannableValueType`'s `false` -> `true`) and the first
    // spelling of this block still PASSED: with the append side still plain, the call was refused ONE
    // STEP LATER and the outcome was unchanged. That is exactly the "manufacture declines one step
    // later" the rule at the type side names, and it is invisible from the status alone. `legacy` is
    // where it shows: at this tip the receiver is refused BEFORE the owner claims anything, so the
    // whole subtree goes legacy. A one-sided widening moves that, and this block now moves with it.
    assert receiverOwnership == ColumnarDirectCallOwnership.NotOwned
    assert receiverLegacy

    // The SAME binary, in the SAME owner, one position over: an argument is planned.
    argumentBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(argumentBindings, "add", 0, typeof(Func<int, int>))
    ColumnarRangePlannerAddParameter(argumentBindings, "x", 1, typeof(int))
    ColumnarRangePlannerAddParameter(argumentBindings, "y", 2, typeof(int))
    argumentPlan := DirectCallPlan(DirectCallParsedTree("add(x + y)"), argumentBindings)
    assert argumentPlan.OpCodeValues[3] == ColumnarCodePlanContract.Add()

    // And the ordinary receiver is untouched by any of it.
    plainBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(plainBindings, "x", 0, typeof(int))
    plainPlan := DirectCallPlan(DirectCallParsedTree("x.ToString()"), plainBindings)
    assert plainPlan.ResultType == typeof(string)
}

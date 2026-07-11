namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

public class ColumnarBoundIdentifierBoxOwner<T> {
    public Box: T

    constructor(value: T) {
        Box = value
    }
}

public class ColumnarBoundIdentifierByRefProbe {
    public static func Set(out value: int): bool {
        value = 0
        return true
    }
}

public class ColumnarBoundIdentifierCurrentClassProbe {
    public Field: int

    constructor(value: int) {
        Field = value
    }

    public Value: int => Field

    public func Identity(value: int): int {
        return value
    }
}

public struct ColumnarBoundIdentifierCurrentStructProbe {
    public Field: int

    constructor(value: int) {
        Field = value
    }

    public Value: int => Field
}

func BoundIdentifierTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    return builder.Build(root)
}

func BoundExplicitThisTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("this.")
    valueStart := builder.AddToken(name)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        valueStart,
        name.Length,
        0,
        5 + name.Length,
        new int[](0))
    return builder.Build(root)
}

func BoundRepeatedRangeTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    start := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    end := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    dots := builder.AddToken("..")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.RangeExpression(),
        dots,
        2,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(start, end))
    return builder.Build(root)
}

func BoundMixedRangeTree(startName: string, endName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    start := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), startName)
    end := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), endName)
    dots := builder.AddToken("..")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.RangeExpression(),
        dots,
        2,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(start, end))
    return builder.Build(root)
}

func BoundPlan(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    if ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, bindings, plan)
        != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected bound-identifier ownership.")
    }
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func BoundDynamicMethod(
    name: string,
    returnType: Type,
    parameterTypes: Type[]): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := ExecutorRequiredConstructor(typeof(DynamicMethod), constructorTypes)
    constructorArguments := new object[](3)
    ExecutorSetObject(constructorArguments, 0, name)
    ExecutorSetObject(constructorArguments, 1, returnType)
    ExecutorSetObject(constructorArguments, 2, parameterTypes)
    return (DynamicMethod)constructorInfo.Invoke(constructorArguments)
}

func BoundInvokeText(dynamicMethod: DynamicMethod, arguments: object[]): string {
    target: object? = null
    result := dynamicMethod.Invoke(target, arguments)
    if result == null {
        throw new InvalidOperationException("Bound-identifier DynamicMethod returned null.")
    }
    return result.ToString() ?? ""
}

func BoundStrongBoxType(): Type {
    value := Type.GetType(
        "System.Runtime.CompilerServices.StrongBox`1[System.Int32], System.Private.CoreLib")
    if value == null {
        throw new InvalidOperationException("StrongBox<int> runtime type was not found.")
    }
    return value
}

func BoundVoidType(): Type {
    value := Type.GetType("System.Void")
    if value == null {
        throw new InvalidOperationException("System.Void runtime type was not found.")
    }
    return value
}

func BoundByRefType(): Type {
    method := typeof(ColumnarBoundIdentifierByRefProbe).GetMethod("Set")
    if method == null {
        throw new InvalidOperationException("By-reference probe method was not found.")
    }
    parameters := method.GetParameters()
    if parameters.Length != 1 {
        throw new InvalidOperationException("By-reference probe signature is invalid.")
    }
    return parameters[0].get_ParameterType()
}

func BoundBoxOwnerType(): Type {
    definition := typeof(ColumnarBoundIdentifierBoxOwner<int>).GetGenericTypeDefinition()
    arguments := new Type[](1)
    arguments[0] = BoundStrongBoxType()
    return definition.MakeGenericType(arguments)
}

func BoundCreateBoxOwner(value: int): object {
    boxType := BoundStrongBoxType()
    boxConstructorTypes := new Type[](1)
    boxConstructorTypes[0] = typeof(int)
    boxConstructor := ExecutorRequiredConstructor(boxType, boxConstructorTypes)
    boxArguments := new object[](1)
    ExecutorSetObject(boxArguments, 0, value)
    box := boxConstructor.Invoke(boxArguments)
    if box == null {
        throw new InvalidOperationException("StrongBox<int> construction returned null.")
    }

    ownerType := BoundBoxOwnerType()
    ownerConstructorTypes := new Type[](1)
    ownerConstructorTypes[0] = boxType
    ownerConstructor := ExecutorRequiredConstructor(ownerType, ownerConstructorTypes)
    ownerArguments := new object[](1)
    ExecutorSetObject(ownerArguments, 0, box)
    owner := ownerConstructor.Invoke(ownerArguments)
    if owner == null {
        throw new InvalidOperationException("Boxed-capture owner construction returned null.")
    }
    return owner
}

func BoundRequiredField(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException(
            "Required current-instance field was not found.")
    }
    return field
}

func BoundRequiredGetter(owner: Type, name: string): MethodInfo {
    noParameters := new Type[](0)
    getter := owner.GetMethod(name, noParameters)
    if getter == null {
        throw new InvalidOperationException(
            "Required current-instance getter was not found.")
    }
    return getter
}

func BoundCurrentFacts(
    owner: Type,
    isReference: bool): ColumnarCurrentInstanceFacts {
    facts := new ColumnarCurrentInstanceFacts(owner, isReference)
    facts.Fields["Field"] = BoundRequiredField(owner, "Field")
    facts.Properties["Value"] = new ColumnarCurrentPropertyFact(
        BoundRequiredGetter(owner, "get_Value"), typeof(int), 0)
    return facts
}

test "bound identifier planner owns exact parameter and local roots" {
    tree := BoundIdentifierTree("value")

    parameterBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(parameterBindings, "value", 7, typeof(int))
    parameterPlan := BoundPlan(tree, parameterBindings)
    assert parameterPlan.ResultType == typeof(int)
    assert parameterPlan.OperationCount == 1
    assert parameterPlan.ArgumentCount == 1
    assert parameterPlan.ArgumentOrdinals[0] == 7
    assert parameterPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()

    localBindings := ColumnarRangePlannerEmptyBindings()
    local := ExternalProbeLocal(typeof(string))
    localBindings.Locals["value"] = local
    localPlan := BoundPlan(tree, localBindings)
    assert localPlan.ResultType == typeof(string)
    assert localPlan.OperationCount == 1
    assert localPlan.AmbientLocalCount == 1
    assert localPlan.AmbientLocals[0].get_LocalType() == typeof(string)
    assert localPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloc()
}

test "bound identifier planner owns exact class and struct current-instance roots" {
    classBindings := ColumnarRangePlannerEmptyBindings()
    classBindings.CurrentInstance = BoundCurrentFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)

    classField := BoundPlan(BoundIdentifierTree("Field"), classBindings)
    assert classField.ResultType == typeof(int)
    assert classField.ArgumentCount == 1
    assert classField.ArgumentOrdinals[0] == 0
    assert !classField.ArgumentIsAddress[0]
    assert classField.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert classField.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()

    classProperty := BoundPlan(BoundIdentifierTree("Value"), classBindings)
    assert classProperty.ResultType == typeof(int)
    assert !classProperty.ArgumentIsAddress[0]
    assert classProperty.MethodUsesDeclaredSignature[0]
    assert classProperty.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert classProperty.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()

    structBindings := ColumnarRangePlannerEmptyBindings()
    structBindings.CurrentInstance = BoundCurrentFacts(
        typeof(ColumnarBoundIdentifierCurrentStructProbe), false)

    structField := BoundPlan(BoundIdentifierTree("Field"), structBindings)
    assert structField.ArgumentIsAddress[0]
    assert structField.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert structField.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()

    structProperty := BoundPlan(BoundIdentifierTree("Value"), structBindings)
    assert structProperty.ArgumentIsAddress[0]
    assert structProperty.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert structProperty.OpCodeValues[1] == ColumnarCodePlanContract.Call()
}

test "bound identifier planner preserves current-member shadowing and explicit-this escape" {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = BoundCurrentFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    ColumnarRangePlannerAddParameter(bindings, "Field", 3, typeof(int))

    barePlan := BoundPlan(BoundIdentifierTree("Field"), bindings)
    assert barePlan.OperationCount == 1
    assert barePlan.ArgumentOrdinals[0] == 3
    assert barePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()

    explicitPlan := BoundPlan(BoundExplicitThisTree("Field"), bindings)
    assert explicitPlan.OperationCount == 2
    assert explicitPlan.ArgumentOrdinals[0] == 0
    assert explicitPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert explicitPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
}

test "range planner recursively consumes current fields and properties" {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.CurrentInstance = BoundCurrentFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)

    fieldPlan := ColumnarRangePlannerPlan(
        ColumnarRangePlannerFromEndIdentifier("Field"), bindings)
    assert fieldPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert fieldPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()

    propertyPlan := ColumnarRangePlannerPlan(
        ColumnarRangePlannerFromEndIdentifier("Value"), bindings)
    assert propertyPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert propertyPlan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
}

test "bound identifier planner owns exact lifted and boxed roots" {
    tree := BoundIdentifierTree("value")
    boxType := BoundStrongBoxType()

    liftedBindings := ColumnarRangePlannerEmptyBindings()
    liftedLocal := ExternalProbeLocal(boxType)
    liftedBindings.LiftedLocals["value"] = (
        Box: liftedLocal,
        ValueType: typeof(int))
    liftedPlan := BoundPlan(tree, liftedBindings)
    assert liftedPlan.ResultType == typeof(int)
    assert liftedPlan.OperationCount == 2
    assert liftedPlan.AmbientLocals[0].get_LocalType() == boxType
    assert liftedPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloc()
    assert liftedPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert liftedPlan.Fields[0].get_DeclaringType() == boxType
    assert liftedPlan.Fields[0].get_FieldType() == typeof(int)

    boxedBindings := ColumnarRangePlannerEmptyBindings()
    ownerType := BoundBoxOwnerType()
    boxField := ownerType.GetField("Box")
    if boxField == null {
        throw new InvalidOperationException("Boxed-capture owner field was not found.")
    }
    boxedBindings.BoxedCaptures["value"] = (
        BoxField: boxField,
        ValueType: typeof(int))
    boxedPlan := BoundPlan(tree, boxedBindings)
    assert boxedPlan.ResultType == typeof(int)
    assert boxedPlan.OperationCount == 3
    assert boxedPlan.ArgumentCount == 1
    assert boxedPlan.ArgumentOrdinals[0] == 0
    assert boxedPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert boxedPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert boxedPlan.OpCodeValues[2] == ColumnarCodePlanContract.Ldfld()
    assert boxedPlan.Fields[0].get_DeclaringType() == ownerType
    assert boxedPlan.Fields[0].get_FieldType() == boxType
    assert boxedPlan.Fields[1].get_DeclaringType() == boxType
    assert boxedPlan.Fields[1].get_FieldType() == typeof(int)
}

test "bound identifier planner preserves lifted parameter priority and rejects invalid shadow facts" {
    tree := BoundIdentifierTree("value")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "value", 3, typeof(int))
    liftedLocal := ExternalProbeLocal(BoundStrongBoxType())
    bindings.LiftedLocals["value"] = (
        Box: liftedLocal,
        ValueType: typeof(int))

    plan := BoundPlan(tree, bindings)
    assert plan.AmbientLocalCount == 1
    assert plan.ArgumentCount == 0
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloc()

    overlapping := ColumnarRangePlannerEmptyBindings()
    overlapping.Locals["value"] = ExternalProbeLocal(typeof(int))
    ColumnarRangePlannerAddParameter(overlapping, "value", 0, typeof(int))
    overlapPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, overlapping, overlapPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(overlapPlan)
}

test "bound identifier planner declines unknown and explicit-this forms atomically" {
    unknown := BoundIdentifierTree("missing")
    unknownPlan := new ColumnarCodePlan()
    assert ColumnarBoundIdentifierPlanner.Plan(
        unknown.Nodes,
        unknown.Source,
        unknown.Root,
        ColumnarRangePlannerEmptyBindings(),
        unknownPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(unknownPlan)

    explicitThis := BoundExplicitThisTree("value")
    explicitBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(explicitBindings, "value", 0, typeof(int))
    explicitPlan := new ColumnarCodePlan()
    assert ColumnarBoundIdentifierPlanner.Plan(
        explicitThis.Nodes,
        explicitThis.Source,
        explicitThis.Root,
        explicitBindings,
        explicitPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(explicitPlan)

}

test "bound identifier facade reports exact ownership and preserves byref fallback" {
    tree := BoundIdentifierTree("value")
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameterOrdinals["value"] = 2
    parameterTypes["value"] = typeof(int)
    emptyNames := new HashSet<string>(StringComparer.Ordinal)
    plan := new ColumnarCodePlan()
    owned := false
    resultType := typeof(object)

    assert ColumnarRangeIndexPlanner.TryGetTypeFromFacts(
        tree.Nodes,
        tree.Source,
        tree.Root,
        parameterOrdinals,
        parameterTypes,
        new Dictionary<string, LocalBuilder>(StringComparer.Ordinal),
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
        out owned,
        out resultType)
    assert owned
    assert resultType == typeof(int)
    ColumnarCodePlanExecutor.Validate(plan)

    byrefBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(
        byrefBindings, "value", 2, BoundByRefType())
    assert !ColumnarBoundIdentifierPlanner.ClaimsRoot(
        tree.Nodes, tree.Source, tree.Root, byrefBindings)

    explicitTree := BoundExplicitThisTree("missing")
    assert ColumnarBoundIdentifierPlanner.ClaimsRoot(
        explicitTree.Nodes,
        explicitTree.Source,
        explicitTree.Root,
        ColumnarRangePlannerEmptyBindings())

    blockedBindings := ColumnarRangePlannerEmptyBindings()
    blockedNames := new string[](1)
    blockedNames[0] = "value"
    blockedBindings = new ColumnarFragmentBindings(
        blockedBindings.ParameterOrdinals,
        blockedBindings.ParameterTypes,
        blockedBindings.Locals,
        blockedBindings.Enums,
        new string[](0),
        new string[](0),
        blockedNames,
        new string[](0),
        new string[](0))
    assert ColumnarBoundIdentifierPlanner.ClaimsRoot(
        tree.Nodes, tree.Source, tree.Root, blockedBindings)

    unknown := BoundIdentifierTree("other")
    assert !ColumnarBoundIdentifierPlanner.ClaimsRoot(
        unknown.Nodes,
        unknown.Source,
        unknown.Root,
        ColumnarRangePlannerEmptyBindings())
}

test "bound identifier planner rejects malformed exact facts without partial plans" {
    tree := BoundIdentifierTree("value")

    missingType := ColumnarRangePlannerEmptyBindings()
    missingType.ParameterOrdinals["value"] = 0
    missingTypePlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, missingType, missingTypePlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(missingTypePlan)

    voidParameter := ColumnarRangePlannerEmptyBindings()
    voidType := BoundVoidType()
    ColumnarRangePlannerAddParameter(voidParameter, "value", 0, voidType)
    voidPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, voidParameter, voidPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(voidPlan)

    openParameter := ColumnarRangePlannerEmptyBindings()
    openType := typeof(ColumnarBoundIdentifierBoxOwner<int>).GetGenericTypeDefinition()
    ColumnarRangePlannerAddParameter(openParameter, "value", 0, openType)
    openPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, openParameter, openPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(openPlan)

    voidLocal := ColumnarRangePlannerEmptyBindings()
    voidLocal.Locals["value"] = ExternalProbeLocal(BoundVoidType())
    voidLocalPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, voidLocal, voidLocalPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(voidLocalPlan)

    openLocal := ColumnarRangePlannerEmptyBindings()
    openLocal.Locals["value"] = ExternalProbeLocal(openType)
    openLocalPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, openLocal, openLocalPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(openLocalPlan)

    badLifted := ColumnarRangePlannerEmptyBindings()
    badLifted.LiftedLocals["value"] = (
        Box: ExternalProbeLocal(typeof(object)),
        ValueType: typeof(int))
    badLiftedPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, badLifted, badLiftedPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(badLiftedPlan)

    ownerType := BoundBoxOwnerType()
    boxField := ownerType.GetField("Box")
    if boxField == null {
        throw new InvalidOperationException("Boxed-capture owner field was not found.")
    }
    badBoxed := ColumnarRangePlannerEmptyBindings()
    badBoxed.BoxedCaptures["value"] = (
        BoxField: boxField,
        ValueType: typeof(string))
    badBoxedPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, badBoxed, badBoxedPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(badBoxedPlan)

    wrongProperty := ColumnarRangePlannerEmptyBindings()
    wrongFacts := new ColumnarCurrentInstanceFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    wrongFacts.Properties["value"] = new ColumnarCurrentPropertyFact(
        BoundRequiredGetter(
            typeof(ColumnarBoundIdentifierCurrentClassProbe), "get_Value"),
        typeof(string),
        0)
    wrongProperty.CurrentInstance = wrongFacts
    wrongPropertyPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, wrongProperty, wrongPropertyPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(wrongPropertyPlan)

    wrongArity := ColumnarRangePlannerEmptyBindings()
    wrongArityFacts := new ColumnarCurrentInstanceFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    wrongGetter := typeof(ColumnarBoundIdentifierCurrentClassProbe).GetMethod(
        "Identity", oneInt)
    if wrongGetter == null {
        throw new InvalidOperationException(
            "Required malformed current-instance method was not found.")
    }
    wrongArityFacts.Properties["value"] = new ColumnarCurrentPropertyFact(
        wrongGetter, typeof(int), 1)
    wrongArity.CurrentInstance = wrongArityFacts
    wrongArityPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, wrongArity, wrongArityPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(wrongArityPlan)

    cyclic := ColumnarRangePlannerEmptyBindings()
    cyclicFacts := new ColumnarCurrentInstanceFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    cyclicFacts.BaseFacts = cyclicFacts
    cyclic.CurrentInstance = cyclicFacts
    missingTree := BoundIdentifierTree("missing")
    cyclicPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.Plan(
            missingTree.Nodes,
            missingTree.Source,
            missingTree.Root,
            cyclic,
            cyclicPlan)
    }
    ColumnarRangePlannerAssertEmptyRollback(cyclicPlan)
}

test "bound identifier failures roll back an earlier recursive range child" {
    tree := BoundMixedRangeTree("start", "end")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "start", 0, typeof(int))
    bindings.LiftedLocals["end"] = (
        Box: ExternalProbeLocal(typeof(object)),
        ValueType: typeof(int))
    plan := new ColumnarCodePlan()

    assert throws InvalidOperationException {
        ColumnarRangeIndexPlanner.Plan(
            tree.Nodes,
            tree.Source,
            tree.Root,
            bindings,
            ColumnarRangeIndexHandles.Resolve(),
            plan)
    }
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "range planner recursively consumes every bound identifier storage form" {
    tree := ColumnarRangePlannerFromEndIdentifier("value")

    parameterBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(parameterBindings, "value", 0, typeof(int))
    parameterPlan := ColumnarRangePlannerPlan(tree, parameterBindings)
    assert parameterPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()

    localBindings := ColumnarRangePlannerEmptyBindings()
    localBindings.Locals["value"] = ExternalProbeLocal(typeof(int))
    localPlan := ColumnarRangePlannerPlan(tree, localBindings)
    assert localPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloc()

    liftedBindings := ColumnarRangePlannerEmptyBindings()
    liftedBindings.LiftedLocals["value"] = (
        Box: ExternalProbeLocal(BoundStrongBoxType()),
        ValueType: typeof(int))
    liftedPlan := ColumnarRangePlannerPlan(tree, liftedBindings)
    assert liftedPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloc()
    assert liftedPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()

    boxedBindings := ColumnarRangePlannerEmptyBindings()
    ownerType := BoundBoxOwnerType()
    boxField := ownerType.GetField("Box")
    if boxField == null {
        throw new InvalidOperationException("Boxed-capture owner field was not found.")
    }
    boxedBindings.BoxedCaptures["value"] = (
        BoxField: boxField,
        ValueType: typeof(int))
    boxedPlan := ColumnarRangePlannerPlan(tree, boxedBindings)
    assert boxedPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert boxedPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert boxedPlan.OpCodeValues[2] == ColumnarCodePlanContract.Ldfld()
}

test "bound identifier planner interns repeated parameter ordinals" {
    tree := BoundRepeatedRangeTree("start")
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "start", 4, typeof(int))
    plan := ColumnarRangePlannerPlan(tree, bindings)

    assert plan.ArgumentCount == 1
    assert plan.ArgumentOrdinals[0] == 4
    assert plan.OperationCount == 7
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ldarg()
    ColumnarCodePlanExecutor.Validate(plan)
}

test "bound identifier plans execute parameters locals lifted values and boxed captures" {
    tree := BoundIdentifierTree("value")

    parameterBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(parameterBindings, "value", 0, typeof(int))
    parameterPlan := BoundPlan(tree, parameterBindings)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    parameterMethod := BoundDynamicMethod(
        "BoundParameter", typeof(int), parameterTypes)
    parameterIl := parameterMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(parameterPlan, parameterIl)
    parameterIl.Emit(OpCodes.Ret)
    parameterArgs := new object[](1)
    ExecutorSetObject(parameterArgs, 0, 41)
    assert BoundInvokeText(parameterMethod, parameterArgs) == "41"

    localMethod := BoundDynamicMethod(
        "BoundLocal", typeof(int), new Type[](0))
    localIl := localMethod.GetILGenerator()
    local := localIl.DeclareLocal(typeof(int))
    localIl.Emit(OpCodes.Ldc_I4, 42)
    localIl.Emit(OpCodes.Stloc, local)
    localBindings := ColumnarRangePlannerEmptyBindings()
    localBindings.Locals["value"] = local
    localPlan := BoundPlan(tree, localBindings)
    ColumnarCodePlanExecutor.Execute(localPlan, localIl)
    localIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(localMethod, new object[](0)) == "42"

    liftedMethod := BoundDynamicMethod(
        "BoundLifted", typeof(int), new Type[](0))
    liftedIl := liftedMethod.GetILGenerator()
    boxType := BoundStrongBoxType()
    boxConstructorTypes := new Type[](1)
    boxConstructorTypes[0] = typeof(int)
    boxConstructor := ExecutorRequiredConstructor(boxType, boxConstructorTypes)
    boxLocal := liftedIl.DeclareLocal(boxType)
    liftedIl.Emit(OpCodes.Ldc_I4, 43)
    liftedIl.Emit(OpCodes.Newobj, boxConstructor)
    liftedIl.Emit(OpCodes.Stloc, boxLocal)
    liftedBindings := ColumnarRangePlannerEmptyBindings()
    liftedBindings.LiftedLocals["value"] = (
        Box: boxLocal,
        ValueType: typeof(int))
    liftedPlan := BoundPlan(tree, liftedBindings)
    ColumnarCodePlanExecutor.Execute(liftedPlan, liftedIl)
    liftedIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(liftedMethod, new object[](0)) == "43"

    ownerType := BoundBoxOwnerType()
    boxedParameterTypes := new Type[](1)
    boxedParameterTypes[0] = ownerType
    boxedMethod := BoundDynamicMethod(
        "BoundBoxed", typeof(int), boxedParameterTypes)
    boxedBindings := ColumnarRangePlannerEmptyBindings()
    boxField := ownerType.GetField("Box")
    if boxField == null {
        throw new InvalidOperationException("Boxed-capture owner field was not found.")
    }
    boxedBindings.BoxedCaptures["value"] = (
        BoxField: boxField,
        ValueType: typeof(int))
    boxedPlan := BoundPlan(tree, boxedBindings)
    boxedIl := boxedMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(boxedPlan, boxedIl)
    boxedIl.Emit(OpCodes.Ret)
    boxedArgs := new object[](1)
    ExecutorSetObject(boxedArgs, 0, BoundCreateBoxOwner(44))
    assert BoundInvokeText(boxedMethod, boxedArgs) == "44"
}

test "bound identifier plans execute current class fields and properties" {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(ColumnarBoundIdentifierCurrentClassProbe)
    arguments := new object[](1)
    ExecutorSetObject(
        arguments, 0, new ColumnarBoundIdentifierCurrentClassProbe(45))

    fieldBindings := ColumnarRangePlannerEmptyBindings()
    fieldBindings.CurrentInstance = BoundCurrentFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    fieldPlan := BoundPlan(BoundIdentifierTree("Field"), fieldBindings)
    fieldMethod := BoundDynamicMethod(
        "BoundCurrentField", typeof(int), parameterTypes)
    fieldIl := fieldMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(fieldPlan, fieldIl)
    fieldIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(fieldMethod, arguments) == "45"

    propertyBindings := ColumnarRangePlannerEmptyBindings()
    propertyBindings.CurrentInstance = BoundCurrentFacts(
        typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    propertyPlan := BoundPlan(BoundIdentifierTree("Value"), propertyBindings)
    propertyMethod := BoundDynamicMethod(
        "BoundCurrentProperty", typeof(int), parameterTypes)
    propertyIl := propertyMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(propertyPlan, propertyIl)
    propertyIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(propertyMethod, arguments) == "45"
}

namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Text

enum ColumnarTypeOfProbeEnum {
    None = 0,
    Ready = 1
}

func TypeOfSimpleTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    typeNode := builder.AddLeaf(0, name)
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(typeNode))
    return builder.Build(root)
}

func TypeOfUnaryTypeTree(
    typeKind: int,
    prefix: string,
    name: string,
    suffix: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    typeStart := builder.AddToken(prefix)
    element := builder.AddLeaf(0, name)
    builder.AddToken(suffix)
    typeNode := builder.AddNode(
        typeKind,
        -1,
        0,
        typeStart,
        builder.Source.Length - typeStart,
        ColumnarRangePlannerChildren1(element))
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(typeNode))
    return builder.Build(root)
}

func TypeOfArrayTree(name: string): ColumnarRangePlannerTestTree {
    return TypeOfUnaryTypeTree(2, "", name, "[]")
}

func TypeOfNullableTree(name: string): ColumnarRangePlannerTestTree {
    return TypeOfUnaryTypeTree(3, "", name, "?")
}

func TypeOfGenericTree(
    name: string,
    firstName: string,
    secondName: string = ""): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    typeStart := builder.AddToken(name)
    builder.AddToken("<")
    first := builder.AddLeaf(0, firstName)
    typeChildren := ColumnarRangePlannerChildren1(first)
    if secondName.Length > 0 {
        builder.AddToken(",")
        second := builder.AddLeaf(0, secondName)
        typeChildren = ColumnarRangePlannerChildren2(first, second)
    }
    builder.AddToken(">")
    typeNode := builder.AddNode(
        1,
        typeStart,
        name.Length,
        typeStart,
        builder.Source.Length - typeStart,
        typeChildren)
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(typeNode))
    return builder.Build(root)
}

func TypeOfTupleTree(
    firstName: string,
    secondName: string,
    named: bool = false): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    tupleStart := builder.AddToken("(")
    firstNameStart := -1
    if named {
        firstNameStart = builder.AddToken("left")
        builder.AddToken(":")
    }
    first := builder.AddLeaf(0, firstName)
    if named {
        first = builder.AddNode(
            7,
            firstNameStart,
            4,
            firstNameStart,
            builder.Source.Length - firstNameStart,
            ColumnarRangePlannerChildren1(first))
    }
    builder.AddToken(",")
    secondNameStart := -1
    if named {
        secondNameStart = builder.AddToken("right")
        builder.AddToken(":")
    }
    second := builder.AddLeaf(0, secondName)
    if named {
        second = builder.AddNode(
            7,
            secondNameStart,
            5,
            secondNameStart,
            builder.Source.Length - secondNameStart,
            ColumnarRangePlannerChildren1(second))
    }
    builder.AddToken(")")
    tuple := builder.AddNode(
        6,
        -1,
        0,
        tupleStart,
        builder.Source.Length - tupleStart,
        ColumnarRangePlannerChildren2(first, second))
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(tuple))
    return builder.Build(root)
}

func TypeOfUnionTree(
    firstName: string,
    secondName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    first := builder.AddLeaf(0, firstName)
    builder.AddToken("|")
    second := builder.AddLeaf(0, secondName)
    unionNode := builder.AddNode(
        4,
        -1,
        0,
        7,
        builder.Source.Length - 7,
        ColumnarRangePlannerChildren2(first, second))
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(unionNode))
    return builder.Build(root)
}

func TypeOfArrayUnionTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    firstStart := builder.Source.Length
    firstElement := builder.AddLeaf(0, name)
    builder.AddToken("[]")
    first := builder.AddNode(
        2,
        -1,
        0,
        firstStart,
        builder.Source.Length - firstStart,
        ColumnarRangePlannerChildren1(firstElement))
    builder.AddToken("|")
    secondStart := builder.Source.Length
    secondElement := builder.AddLeaf(0, name)
    builder.AddToken("[]")
    second := builder.AddNode(
        2,
        -1,
        0,
        secondStart,
        builder.Source.Length - secondStart,
        ColumnarRangePlannerChildren1(secondElement))
    unionNode := builder.AddNode(
        4,
        -1,
        0,
        firstStart,
        builder.Source.Length - firstStart,
        ColumnarRangePlannerChildren2(first, second))
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(unionNode))
    return builder.Build(root)
}

func TypeOfDelegateWithSourceCollectionTree(
    sourceTypeName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    functionStart := builder.AddToken("Func")
    builder.AddToken("<")
    listStart := builder.AddToken("List")
    builder.AddToken("<")
    sourceType := builder.AddLeaf(0, sourceTypeName)
    builder.AddToken(">")
    listType := builder.AddNode(
        1,
        listStart,
        4,
        listStart,
        builder.Source.Length - listStart,
        ColumnarRangePlannerChildren1(sourceType))
    builder.AddToken(",")
    resultType := builder.AddLeaf(0, "int")
    builder.AddToken(">")
    functionType := builder.AddNode(
        1,
        functionStart,
        4,
        functionStart,
        builder.Source.Length - functionStart,
        ColumnarRangePlannerChildren2(listType, resultType))
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(functionType))
    return builder.Build(root)
}

func TypeOfMalformedTree(
    typeOfChildren: int[],
    includeGeneric: bool = false): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    children := typeOfChildren
    if includeGeneric {
        nameStart := builder.AddToken("List")
        generic := builder.AddNode(
            1,
            nameStart,
            4,
            nameStart,
            4,
            new int[](0))
        children = ColumnarRangePlannerChildren1(generic)
    }
    builder.AddToken(")")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        children)
    return builder.Build(root)
}

func TypeOfPlan(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    if ColumnarTypeOfPlanner.Plan(
            tree.Nodes, tree.Source, tree.Root, bindings, plan)
        != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException(
            "Expected typeof planner ownership: " + tree.Source)
    }
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func TypeOfRequiredRuntimeType(owner: Type, name: string): Type {
    result := owner.get_Assembly().GetType(name)
    if result == null {
        throw new InvalidOperationException(
            "Required runtime type was not found: " + name)
    }
    return result
}

func TypeOfRequiredStaticField(owner: Type, name: string): object {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException(
            "Required runtime field was not found: " + name)
    }
    value := field.GetValue(null)
    if value == null {
        throw new InvalidOperationException(
            "Required runtime field returned null: " + name)
    }
    return value
}

func TypeOfRequiredInvocation(
    method: MethodInfo,
    target: object?,
    arguments: object[]): object {
    parameters := method.GetParameters()
    if parameters.Length != arguments.Length {
        throw new InvalidOperationException(
            "Required reflection invocation argument count is invalid.")
    }
    isStatic := method.get_IsStatic()
    offset := isStatic ? 0 : 1
    parameterTypes := new Type[](parameters.Length + offset)
    invocationArguments := new object[](arguments.Length + offset)
    if !isStatic {
        declaringType := method.get_DeclaringType()
        if declaringType == null || target == null {
            throw new InvalidOperationException(
                "Required instance reflection invocation has no receiver.")
        }
        parameterTypes[0] = declaringType
        ExecutorSetObject(invocationArguments, 0, target)
    }
    i := 0
    while i < parameters.Length {
        parameter := parameters[i]
        parameterTypes[i + offset] = parameter.get_ParameterType()
        argument := arguments[i]
        ExecutorSetObject(invocationArguments, i + offset, argument)
        i += 1
    }

    dynamicMethod := BoundDynamicMethod(
        "TypeOfReflectionInvocation",
        method.get_ReturnType(),
        parameterTypes)
    il := dynamicMethod.GetILGenerator()
    i = 0
    while i < parameterTypes.Length {
        il.Emit(OpCodes.Ldarg, (short)i)
        i += 1
    }
    if isStatic {
        il.Emit(OpCodes.Call, method)
    } else {
        il.Emit(OpCodes.Callvirt, method)
    }
    il.Emit(OpCodes.Ret)
    invocationTarget: object? = null
    value := dynamicMethod.Invoke(invocationTarget, invocationArguments)
    if value == null {
        throw new InvalidOperationException(
            "Required reflection invocation returned null.")
    }
    return value
}

func TypeOfRequiredConstruction(
    constructorInfo: ConstructorInfo,
    arguments: object[]): object {
    value := constructorInfo.Invoke(arguments)
    if value == null {
        throw new InvalidOperationException(
            "Required reflection construction returned null.")
    }
    return value
}

func TypeOfCreateSourceBuilder(name: string, generic: bool = false): TypeBuilder {
    genericParameterCount := generic ? 1 : 0
    return TypeOfCreateBuilder(
        name,
        "ColumnarTypeOfTests." + name,
        genericParameterCount)
}

func TypeOfCreateBuilder(
    name: string,
    assemblyIdentity: string,
    genericParameterCount: int): TypeBuilder {
    assemblyBuilderType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilder")
    assemblyBuilderAccessType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder), "System.Reflection.Emit.AssemblyBuilderAccess")
    moduleBuilderType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder), "System.Reflection.Emit.ModuleBuilder")
    typeAttributesType := TypeOfRequiredRuntimeType(
        typeof(AssemblyName), "System.Reflection.TypeAttributes")

    assemblyNameConstructorTypes := new Type[](1)
    assemblyNameConstructorTypes[0] = typeof(string)
    assemblyNameConstructor := ExecutorRequiredConstructor(
        typeof(AssemblyName), assemblyNameConstructorTypes)
    assemblyNameArguments := new object[](1)
    ExecutorSetObject(
        assemblyNameArguments,
        0,
        assemblyIdentity)
    assemblyName := TypeOfRequiredConstruction(
        assemblyNameConstructor,
        assemblyNameArguments)

    defineAssemblyTypes := new Type[](2)
    defineAssemblyTypes[0] = typeof(AssemblyName)
    defineAssemblyTypes[1] = assemblyBuilderAccessType
    defineAssembly := ExecutorRequiredMethod(
        assemblyBuilderType,
        "DefineDynamicAssembly",
        defineAssemblyTypes)
    defineAssemblyArguments := new object[](2)
    ExecutorSetObject(defineAssemblyArguments, 0, assemblyName)
    ExecutorSetObject(
        defineAssemblyArguments,
        1,
        TypeOfRequiredStaticField(assemblyBuilderAccessType, "Run"))
    assemblyBuilder := TypeOfRequiredInvocation(
        defineAssembly,
        null,
        defineAssemblyArguments)

    defineModuleTypes := new Type[](1)
    defineModuleTypes[0] = typeof(string)
    defineModule := ExecutorRequiredMethod(
        assemblyBuilderType,
        "DefineDynamicModule",
        defineModuleTypes)
    defineModuleArguments := new object[](1)
    ExecutorSetObject(defineModuleArguments, 0, name)
    moduleBuilder := TypeOfRequiredInvocation(
        defineModule,
        assemblyBuilder,
        defineModuleArguments)

    defineTypeTypes := new Type[](2)
    defineTypeTypes[0] = typeof(string)
    defineTypeTypes[1] = typeAttributesType
    defineType := ExecutorRequiredMethod(
        moduleBuilderType,
        "DefineType",
        defineTypeTypes)
    defineTypeArguments := new object[](2)
    ExecutorSetObject(defineTypeArguments, 0, name)
    ExecutorSetObject(
        defineTypeArguments,
        1,
        TypeOfRequiredStaticField(typeAttributesType, "Public"))
    created := TypeOfRequiredInvocation(
        defineType,
        moduleBuilder,
        defineTypeArguments)
    builder := created as TypeBuilder
    if builder == null {
        throw new InvalidOperationException(
            "Reflection.Emit did not return a TypeBuilder.")
    }

    if genericParameterCount > 0 {
        genericParameterTypes := new Type[](1)
        genericParameterTypes[0] = typeof(string[])
        defineParameters := ExecutorRequiredMethod(
            typeof(TypeBuilder),
            "DefineGenericParameters",
            genericParameterTypes)
        parameterNames := new string[](genericParameterCount)
        parameterIndex := 0
        while parameterIndex < parameterNames.Length {
            parameterNames[parameterIndex] = "T" + parameterIndex.ToString()
            parameterIndex += 1
        }
        defineParameterArguments := new object[](1)
        ExecutorSetObject(defineParameterArguments, 0, parameterNames)
        TypeOfRequiredInvocation(
            defineParameters,
            builder,
            defineParameterArguments)
    }

    return builder
}

func TypeOfInstallRuntimeUnion(): Type {
    builder := TypeOfCreateBuilder(
        "NSharpLang.Runtime.Union`2",
        "NSharpLang.Runtime",
        2)
    createType := ExecutorRequiredMethod(
        typeof(TypeBuilder), "CreateType", new Type[](0))
    value := TypeOfRequiredInvocation(
        createType, builder, new object[](0))
    runtimeType := value as Type
    if runtimeType == null {
        throw new InvalidOperationException(
            "Runtime union fixture did not produce a Type.")
    }
    return runtimeType
}

func TypeOfSourceDefinition(builder: TypeBuilder): ColumnarStructDef {
    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true)
}

func TypeOfMethodBuilderIL(methodBuilder: MethodBuilder): ILGenerator {
    method := ExecutorRequiredMethod(
        typeof(MethodBuilder), "GetILGenerator", new Type[](0))
    value := TypeOfRequiredInvocation(
        method, methodBuilder, new object[](0))
    il := value as ILGenerator
    if il == null {
        throw new InvalidOperationException(
            "MethodBuilder.GetILGenerator returned an invalid value.")
    }
    return il
}

func TypeOfNullableIntType(): Type {
    definition := Type.GetType("System.Nullable`1")
    if definition == null {
        throw new InvalidOperationException(
            "System.Nullable<T> runtime type was not found.")
    }
    arguments := new Type[](1)
    arguments[0] = typeof(int)
    return definition.MakeGenericType(arguments)
}

func TypeOfAssertTarget(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings,
    expected: Type) {
    plan := TypeOfPlan(tree, bindings)
    assert plan.TypeCount == 1
    assert plan.Types[0] == expected
    assert plan.ResultType == typeof(Type)
}

test "typeof planner emits exact schema v3 type-handle plan and executes" {
    tree := TypeOfSimpleTree("string")
    bindings := ColumnarRangePlannerEmptyBindings()

    assert ColumnarTypeOfPlanner.MayPlanRoot(tree.Nodes, tree.Root)
    assert ColumnarTypeOfPlanner.ClaimsRoot(tree.Nodes, tree.Root)

    plan := TypeOfPlan(tree, bindings)
    assert plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    assert plan.ResultType == typeof(Type)
    assert plan.FragmentCount == 1
    assert plan.OperationCount == 2
    assert plan.TypeCount == 1
    assert plan.MethodCount == 1
    assert plan.Types[0] == typeof(string)
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldtoken()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.TypeOperand()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.OperandKinds[1] == ColumnarCodePlanContract.MethodOperand()
    assert plan.Methods[0].get_DeclaringType() == typeof(Type)
    assert plan.MethodDeclaringTypes[0] == typeof(Type)
    assert plan.MethodReturnTypes[0] == typeof(Type)
    assert plan.MethodParameterTypes[0].Length == 1
    assert plan.MethodParameterTypes[0][0] == typeof(RuntimeTypeHandle)
    assert plan.MethodIsStatic[0]
    assert !plan.MethodIsAbstract[0]
    assert ExecutorRunV3ScalarPlan(plan, typeof(Type)) == "System.String"

    emitPlan := new ColumnarCodePlan()
    method := BoundDynamicMethod("TypeOfDirectEmit", typeof(Type), new Type[](0))
    resultType := typeof(object)
    assert ColumnarTypeOfPlanner.TryEmit(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        emitPlan,
        method.GetILGenerator(),
        out resultType)
    assert resultType == typeof(Type)
    method.GetILGenerator().Emit(OpCodes.Ret)
    assert BoundInvokeText(method, new object[](0)) == "System.String"
}

test "typeof planner resolves builtin enum array nullable tuple and anonymous union shapes" {
    runtimeUnion := TypeOfInstallRuntimeUnion()
    assert runtimeUnion.get_IsGenericTypeDefinition()
    bindings := ColumnarRangePlannerEmptyBindings()
    constants := new Dictionary<string, int>(StringComparer.Ordinal)
    constants["None"] = 0
    constants["Ready"] = 1
    bindings.Enums["ProbeState"] = new ColumnarEnumDef(
        typeof(ColumnarTypeOfProbeEnum), constants)

    intTree := TypeOfSimpleTree("int")
    TypeOfAssertTarget(intTree, bindings, typeof(int))
    enumTree := TypeOfSimpleTree("ProbeState")
    TypeOfAssertTarget(
        enumTree,
        bindings,
        typeof(ColumnarTypeOfProbeEnum))
    arrayTree := TypeOfArrayTree("int")
    TypeOfAssertTarget(arrayTree, bindings, typeof(int[]))
    nullableTree := TypeOfNullableTree("int")
    nullableType := TypeOfNullableIntType()
    TypeOfAssertTarget(
        nullableTree,
        bindings,
        nullableType)
    tupleType := typeof(ValueTuple<int, string>)
    tupleTree := TypeOfTupleTree("int", "string", false)
    TypeOfAssertTarget(tupleTree, bindings, tupleType)
    namedTupleTree := TypeOfTupleTree("int", "string", true)
    TypeOfAssertTarget(namedTupleTree, bindings, tupleType)

    unionTree := TypeOfUnionTree("int", "string")
    unionPlan := TypeOfPlan(unionTree, bindings)
    unionTarget := unionPlan.Types[0]
    assert unionTarget.get_IsGenericType()
    unionDefinition := unionTarget.GetGenericTypeDefinition()
    assert unionDefinition.FullName == "NSharpLang.Runtime.Union`2"
    unionArguments := unionTarget.GetGenericArguments()
    assert unionArguments.Length == 2
    assert unionArguments[0] == typeof(int)
    assert unionArguments[1] == typeof(string)

}

test "typeof planner resolves live source struct union and closed generic builders" {
    sourceBuilder := TypeOfCreateSourceBuilder("TypeOfSourceRecord", false)
    unionBuilder := TypeOfCreateSourceBuilder("TypeOfSourceChoice", false)
    genericBuilder := TypeOfCreateSourceBuilder("TypeOfSourceBox", true)

    bindings := ColumnarRangePlannerEmptyBindings()
    definitions := new ColumnarStructDef[](2)
    definitions[0] = TypeOfSourceDefinition(sourceBuilder)
    definitions[1] = TypeOfSourceDefinition(genericBuilder)
    bindings.SourceTypeDefinitions = definitions
    unions := new ColumnarUnionDef[](1)
    unions[0] = new ColumnarUnionDef(unionBuilder)
    bindings.SourceUnionDefinitions = unions

    sourceTree := TypeOfSimpleTree("TypeOfSourceRecord")
    TypeOfAssertTarget(sourceTree, bindings, sourceBuilder)
    unionTree := TypeOfSimpleTree("TypeOfSourceChoice")
    TypeOfAssertTarget(unionTree, bindings, unionBuilder)

    closedTree := TypeOfGenericTree("TypeOfSourceBox", "int", "")
    closedPlan := TypeOfPlan(closedTree, bindings)
    closedTarget := closedPlan.Types[0]
    assert closedTarget.get_IsGenericType()
    assert !closedTarget.get_IsGenericTypeDefinition()
    closedDefinition := closedTarget.GetGenericTypeDefinition()
    expectedClosedDefinition: Type = genericBuilder
    assert closedDefinition == expectedClosedDefinition
    closedArguments := closedTarget.GetGenericArguments()
    assert closedArguments.Length == 1
    assert closedArguments[0] == typeof(int)

    listTree := TypeOfGenericTree("List", "string", "")
    listPlan := TypeOfPlan(listTree, bindings)
    assert listPlan.Types[0] == typeof(List<string>)
}

test "typeof source lookup honors exact qualified names and deterministic short aliases" {
    firstType := TypeOfCreateSourceBuilder("TypeOfScopeA.Widget", false)
    secondType := TypeOfCreateSourceBuilder("TypeOfScopeB.Widget", false)
    unqualifiedType := TypeOfCreateSourceBuilder("Widget", false)
    firstGeneric := TypeOfCreateSourceBuilder("TypeOfScopeA.Box", true)
    secondGeneric := TypeOfCreateSourceBuilder("TypeOfScopeB.Box", true)
    choiceStruct := TypeOfCreateSourceBuilder("TypeOfScopeA.Choice", false)
    genericChoiceType := TypeOfCreateSourceBuilder(
        "TypeOfScopeA.GenericChoice", true)
    dateTimeSource := TypeOfCreateSourceBuilder("DateTime", false)
    stringBuilderSource := TypeOfCreateSourceBuilder("StringBuilder", false)
    nonGenericBox := TypeOfCreateSourceBuilder(
        "TypeOfScopeA.BlockedBox", false)
    laterGenericBox := TypeOfCreateSourceBuilder(
        "TypeOfScopeB.BlockedBox", true)
    firstUnion := TypeOfCreateSourceBuilder("TypeOfScopeA.Choice", false)
    secondUnion := TypeOfCreateSourceBuilder("TypeOfScopeB.Choice", false)
    genericChoiceUnion := TypeOfCreateSourceBuilder("GenericChoice", true)

    bindings := ColumnarRangePlannerEmptyBindings()
    definitions := new ColumnarStructDef[](11)
    definitions[0] = TypeOfSourceDefinition(firstType)
    definitions[1] = TypeOfSourceDefinition(secondType)
    definitions[2] = TypeOfSourceDefinition(unqualifiedType)
    definitions[3] = TypeOfSourceDefinition(firstGeneric)
    definitions[4] = TypeOfSourceDefinition(secondGeneric)
    definitions[5] = TypeOfSourceDefinition(choiceStruct)
    definitions[6] = TypeOfSourceDefinition(genericChoiceType)
    definitions[7] = TypeOfSourceDefinition(dateTimeSource)
    definitions[8] = TypeOfSourceDefinition(stringBuilderSource)
    definitions[9] = TypeOfSourceDefinition(nonGenericBox)
    definitions[10] = TypeOfSourceDefinition(laterGenericBox)
    bindings.SourceTypeDefinitions = definitions
    unions := new ColumnarUnionDef[](3)
    unions[0] = new ColumnarUnionDef(firstUnion)
    unions[1] = new ColumnarUnionDef(secondUnion)
    unions[2] = new ColumnarUnionDef(genericChoiceUnion, 1)
    bindings.SourceUnionDefinitions = unions

    qualifiedWidgetTree := TypeOfSimpleTree("TypeOfScopeB.Widget")
    TypeOfAssertTarget(qualifiedWidgetTree, bindings, secondType)
    unqualifiedWidgetTree := TypeOfSimpleTree("Widget")
    TypeOfAssertTarget(unqualifiedWidgetTree, bindings, unqualifiedType)
    qualifiedChoiceTree := TypeOfSimpleTree("TypeOfScopeB.Choice")
    TypeOfAssertTarget(qualifiedChoiceTree, bindings, secondUnion)
    unqualifiedChoiceTree := TypeOfSimpleTree("Choice")
    TypeOfAssertTarget(unqualifiedChoiceTree, bindings, choiceStruct)
    dateTimeTree := TypeOfSimpleTree("DateTime")
    TypeOfAssertTarget(dateTimeTree, bindings, dateTimeSource)
    stringBuilderTree := TypeOfSimpleTree("StringBuilder")
    TypeOfAssertTarget(stringBuilderTree, bindings, typeof(StringBuilder))

    // Generic heads are historically unqualified before keyed lookup. The first short alias
    // therefore wins deterministically, even when the source spelling carries a qualifier.
    genericTree := TypeOfGenericTree("TypeOfScopeB.Box", "int", "")
    generic := TypeOfPlan(genericTree, bindings)
    genericTarget := generic.Types[0]
    genericDefinition := genericTarget.GetGenericTypeDefinition()
    expectedGenericDefinition: Type = firstGeneric
    assert genericDefinition == expectedGenericDefinition

    genericCategoryTree := TypeOfGenericTree("GenericChoice", "int", "")
    genericCategoryCollision := TypeOfPlan(genericCategoryTree, bindings)
    genericCategoryTarget := genericCategoryCollision.Types[0]
    genericCategoryDefinition := genericCategoryTarget.GetGenericTypeDefinition()
    expectedCategoryDefinition: Type = genericChoiceType
    assert genericCategoryDefinition == expectedCategoryDefinition

    blockedGenericTree := TypeOfGenericTree(
        "TypeOfScopeB.BlockedBox", "int", "")
    blockedGenericPlan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        blockedGenericTree.Nodes,
        blockedGenericTree.Source,
        blockedGenericTree.Root,
        bindings,
        blockedGenericPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(blockedGenericPlan)
}

test "typeof rejects structurally equivalent source array union arms" {
    runtimeUnion := TypeOfInstallRuntimeUnion()
    assert runtimeUnion.get_IsGenericTypeDefinition()
    sourceBuilder := TypeOfCreateSourceBuilder("TypeOfArrayArm", false)
    bindings := ColumnarRangePlannerEmptyBindings()
    definitions := new ColumnarStructDef[](1)
    definitions[0] = TypeOfSourceDefinition(sourceBuilder)
    bindings.SourceTypeDefinitions = definitions

    tree := TypeOfArrayUnionTree("TypeOfArrayArm")
    plan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        plan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "typeof delegate target keeps direct emit broader than receiver preflight" {
    sourceBuilder := TypeOfCreateSourceBuilder("TypeOfDelegateElement", false)
    bindings := ColumnarRangePlannerEmptyBindings()
    definitions := new ColumnarStructDef[](1)
    definitions[0] = TypeOfSourceDefinition(sourceBuilder)
    bindings.SourceTypeDefinitions = definitions
    tree := TypeOfDelegateWithSourceCollectionTree("TypeOfDelegateElement")

    direct := TypeOfPlan(tree, bindings)
    target := direct.Types[0]
    assert target.get_IsGenericType()
    targetDefinition := target.GetGenericTypeDefinition()
    expectedTargetDefinition := typeof(Func<int, int>).GetGenericTypeDefinition()
    assert targetDefinition == expectedTargetDefinition
    targetArguments := target.GetGenericArguments()
    assert targetArguments.Length == 2
    targetParameter := targetArguments[0]
    targetParameterDefinition := targetParameter.GetGenericTypeDefinition()
    expectedParameterDefinition := typeof(List<int>).GetGenericTypeDefinition()
    assert targetParameterDefinition == expectedParameterDefinition
    targetParameterArguments := targetParameter.GetGenericArguments()
    expectedSourceArgument: Type = sourceBuilder
    assert targetParameterArguments[0] == expectedSourceArgument
    assert targetArguments[1] == typeof(int)

    emitPlan := new ColumnarCodePlan()
    attributes := (MethodAttributes)22
    methodBuilder := sourceBuilder.DefineMethod(
        "TypeOfBuilderDelegateEmit",
        attributes,
        typeof(Type),
        new Type[](0))
    il := TypeOfMethodBuilderIL(methodBuilder)
    resultType := typeof(object)
    assert ColumnarTypeOfPlanner.TryEmit(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        emitPlan,
        il,
        out resultType)
    assert resultType == typeof(Type)
    il.Emit(OpCodes.Ret)

    preflight := new ColumnarCodePlan()
    preflightType := typeof(object)
    assert !ColumnarTypeOfPlanner.TryGetType(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        preflight,
        out preflightType)
    assert preflightType == typeof(Type)
    ColumnarRangePlannerAssertEmptyRollback(preflight)
}

test "typeof append composes recursively and rolls back atomically on decline" {
    bindings := ColumnarRangePlannerEmptyBindings()
    successTree := TypeOfSimpleTree("int")
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    outer := plan.BeginFragment(-1, 7001, successTree.Root)
    resultType := typeof(object)
    assert ColumnarTypeOfPlanner.TryAppendTypeOf(
        successTree.Nodes,
        successTree.Source,
        successTree.Root,
        bindings,
        plan,
        out resultType)
    assert resultType == typeof(Type)
    assert plan.OperationCount == 2
    assert plan.TypeCount == 1
    assert plan.MethodCount == 1
    plan.CompleteFragment(outer, resultType)
    plan.CompleteV3(resultType)
    ColumnarCodePlanExecutor.Validate(plan)

    rejectedTree := TypeOfSimpleTree("MissingType")
    rejected := new ColumnarCodePlan()
    rejected.PrepareV3()
    rejectedOuter := rejected.BeginFragment(-1, 7002, rejectedTree.Root)
    rejected.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    rejectedResult := typeof(object)
    assert !ColumnarTypeOfPlanner.TryAppendTypeOf(
        rejectedTree.Nodes,
        rejectedTree.Source,
        rejectedTree.Root,
        bindings,
        rejected,
        out rejectedResult)
    assert rejectedResult == typeof(Type)
    assert rejected.OperationCount == 1
    assert rejected.TypeCount == 0
    assert rejected.MethodCount == 0
    assert rejected.FragmentCount == 1
    rejected.CompleteFragment(rejectedOuter, typeof(int))
    rejected.CompleteV3(typeof(int))
    ColumnarCodePlanExecutor.Validate(rejected)
}

test "typeof planner admits resolved runtime enums in emit and preflight" {
    tree := TypeOfSimpleTree("SearchOption")
    bindings := ColumnarRangePlannerEmptyBindings()

    direct := TypeOfPlan(tree, bindings)
    assert direct.Types[0] == typeof(System.IO.SearchOption)
    assert ExecutorRunV3ScalarPlan(direct, typeof(Type))
        == "System.IO.SearchOption"

    preflight := new ColumnarCodePlan()
    resultType := typeof(object)
    assert ColumnarTypeOfPlanner.TryGetType(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        preflight,
        out resultType)
    assert resultType == typeof(Type)
    ColumnarCodePlanExecutor.Validate(preflight)
}

test "typeof roots remain terminal while every rejected shape leaves an empty plan" {
    bindings := ColumnarRangePlannerEmptyBindings()
    unknown := TypeOfSimpleTree("MissingType")
    assert ColumnarTypeOfPlanner.ClaimsRoot(unknown.Nodes, unknown.Root)
    unknownPlan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        unknown.Nodes,
        unknown.Source,
        unknown.Root,
        bindings,
        unknownPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(unknownPlan)

    noChildren := TypeOfMalformedTree(new int[](0), false)
    assert ColumnarTypeOfPlanner.ClaimsRoot(noChildren.Nodes, noChildren.Root)
    noChildrenPlan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        noChildren.Nodes,
        noChildren.Source,
        noChildren.Root,
        bindings,
        noChildrenPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(noChildrenPlan)

    malformedGeneric := TypeOfMalformedTree(new int[](0), true)
    assert ColumnarTypeOfPlanner.ClaimsRoot(
        malformedGeneric.Nodes, malformedGeneric.Root)
    malformedPlan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        malformedGeneric.Nodes,
        malformedGeneric.Source,
        malformedGeneric.Root,
        bindings,
        malformedPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(malformedPlan)

    unsupportedTuple := TypeOfTupleTree("ProbeState", "int", false)
    constants := new Dictionary<string, int>(StringComparer.Ordinal)
    bindings.Enums["ProbeState"] = new ColumnarEnumDef(
        typeof(ColumnarTypeOfProbeEnum), constants)
    unsupportedTuplePlan := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(
        unsupportedTuple.Nodes,
        unsupportedTuple.Source,
        unsupportedTuple.Root,
        bindings,
        unsupportedTuplePlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(unsupportedTuplePlan)
}

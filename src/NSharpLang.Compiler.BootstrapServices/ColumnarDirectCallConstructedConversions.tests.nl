namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import System.Globalization

class ColumnarConstructedConversionProbeMethods {
    static func AcceptSpan(_values: Span<int>): int {
        return 31
    }

    static func AcceptReadOnlySpan(_values: ReadOnlySpan<int>): int {
        return 32
    }
}

func ConstructedConversionOneType(valueType: Type): Type[] {
    values := new Type[](1)
    values[0] = valueType
    return values
}

func ConstructedConversionRequiredMethod(ownerType: Type, methodName: string, parameterType: Type): MethodInfo {
    method := ownerType.GetMethod(methodName, ConstructedConversionOneType(parameterType))

    if method == null {
        throw new InvalidOperationException("Required constructed-conversion probe method was not found: " + methodName)
    }

    return method
}

func ConstructedConversionRequiredConstructor(ownerType: Type, parameterTypes: Type[]): ConstructorInfo {
    constructorHandle := ownerType.GetConstructor(parameterTypes)
    if constructorHandle == null {
        throw new InvalidOperationException("Required constructed-conversion probe constructor was not found.")
    }

    return constructorHandle
}

func ConstructedConversionUnionType(firstArm: Type, secondArm: Type): Type {
    definition := ConstructedConversionInstallUnionDefinition()

    arguments := new Type[](2)
    arguments[0] = firstArm
    arguments[1] = secondArm
    return definition.MakeGenericType(arguments)
}

func ConstructedConversionUnionBuilder(): TypeBuilder {
    typeAttributesType := TypeOfRequiredRuntimeType(typeof(AssemblyName), "System.Reflection.TypeAttributes")

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(Type)
    parseParameterTypes[1] = typeof(string)
    enumType := Type.GetType("System.Enum")
    if enumType == null {
        throw new InvalidOperationException("System.Enum runtime type was not found.")
    }

    parseAttributes := ExecutorRequiredMethod(enumType, "Parse", parseParameterTypes)
    parseArguments := new object[](2)
    ConstructedConversionSetObject(parseArguments, 0, typeAttributesType)
    ConstructedConversionSetObject(parseArguments, 1, "Public, SequentialLayout, Sealed")
    attributes := TypeOfRequiredInvocation(parseAttributes, null, parseArguments)

    seed := TypeOfCreateBuilder("ConstructedConversionUnionSeed", "NSharpLang.Runtime", 0)
    getModule := ExecutorRequiredMethod(typeof(TypeBuilder), "get_Module", new Type[](0))
    module := TypeOfRequiredInvocation(getModule, seed, new object[](0))
    moduleBuilderType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.Emit.ModuleBuilder")

    defineTypeParameterTypes := new Type[](2)
    defineTypeParameterTypes[0] = typeof(string)
    defineTypeParameterTypes[1] = typeAttributesType
    defineType := ExecutorRequiredMethod(moduleBuilderType, "DefineType", defineTypeParameterTypes)
    defineTypeArguments := new object[](2)
    ConstructedConversionSetObject(defineTypeArguments, 0, "NSharpLang.Runtime.Union`2")
    ConstructedConversionSetObject(defineTypeArguments, 1, attributes)
    created := TypeOfRequiredInvocation(defineType, module, defineTypeArguments)
    builder := created as TypeBuilder
    if builder == null {
        throw new InvalidOperationException("Anonymous-union fixture did not create a TypeBuilder.")
    }

    setParentParameterTypes := new Type[](1)
    setParentParameterTypes[0] = typeof(Type)
    setParent := ExecutorRequiredMethod(typeof(TypeBuilder), "SetParent", setParentParameterTypes)
    valueType := Type.GetType("System.ValueType")
    if valueType == null {
        throw new InvalidOperationException("System.ValueType runtime type was not found.")
    }

    wrapperParameterTypes := new Type[](2)
    wrapperParameterTypes[0] = typeof(TypeBuilder)
    wrapperParameterTypes[1] = typeof(Type)
    wrapper := BoundDynamicMethod("ConstructedConversionSetValueTypeParent", typeof(int), wrapperParameterTypes)
    wrapperIl := wrapper.GetILGenerator()
    wrapperIl.Emit(OpCodes.Ldarg, (short)0)
    wrapperIl.Emit(OpCodes.Ldarg, (short)1)
    wrapperIl.Emit(OpCodes.Callvirt, setParent)
    wrapperIl.Emit(OpCodes.Ldc_I4, 0)
    wrapperIl.Emit(OpCodes.Ret)
    wrapperArguments := new object[](2)
    ConstructedConversionSetObject(wrapperArguments, 0, builder)
    ConstructedConversionSetObject(wrapperArguments, 1, valueType)
    wrapperTarget: object? = null
    wrapperResult := wrapper.Invoke(wrapperTarget, wrapperArguments)
    if wrapperResult == null {
        throw new InvalidOperationException("Anonymous-union fixture did not install its value-type parent.")
    }

    defineGenericParameterTypes := new Type[](1)
    defineGenericParameterTypes[0] = typeof(string[])
    defineGenericParameters := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineGenericParameters", defineGenericParameterTypes)
    parameterNames := new string[](2)
    parameterNames[0] = "T0"
    parameterNames[1] = "T1"
    defineGenericArguments := new object[](1)
    ConstructedConversionSetObject(defineGenericArguments, 0, parameterNames)
    TypeOfRequiredInvocation(defineGenericParameters, builder, defineGenericArguments)

    return builder
}

func ConstructedConversionInstallUnionDefinition(): Type {
    builder := ConstructedConversionUnionBuilder()

    builderType: Type = builder
    genericArguments := builderType.GetGenericArguments()
    if genericArguments.Length != 2 {
        throw new InvalidOperationException("Anonymous-union fixture did not declare two generic arms.")
    }

    callingConventionsType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Reflection.CallingConventions")

    defineConstructorTypes := new Type[](3)
    defineConstructorTypes[0] = typeof(MethodAttributes)
    defineConstructorTypes[1] = callingConventionsType
    defineConstructorTypes[2] = typeof(Type[])
    defineConstructor := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineConstructor", defineConstructorTypes)

    getIlGenerator := ExecutorRequiredMethod(typeof(ConstructorBuilder), "GetILGenerator", new Type[](0))

    armIndex := 0
    while armIndex < genericArguments.Length {
        constructorArguments := new object[](3)
        ConstructedConversionSetObject(constructorArguments, 0, (MethodAttributes)6)

        ConstructedConversionSetObject(constructorArguments, 1, TypeOfRequiredStaticField(callingConventionsType, "Standard"))

        ConstructedConversionSetObject(constructorArguments, 2, ConstructedConversionOneType(genericArguments[armIndex]))

        created := TypeOfRequiredInvocation(defineConstructor, builder, constructorArguments)

        constructorBuilder := created as ConstructorBuilder
        if constructorBuilder == null {
            throw new InvalidOperationException("Anonymous-union fixture did not create an arm constructor.")
        }

        ilValue := TypeOfRequiredInvocation(getIlGenerator, constructorBuilder, new object[](0))

        il := ilValue as ILGenerator
        if il == null {
            throw new InvalidOperationException("Anonymous-union fixture did not create a constructor body.")
        }

        il.Emit(OpCodes.Ret)

        armIndex += 1
    }

    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))

    createdType := TypeOfRequiredInvocation(createType, builder, new object[](0))

    definition := createdType as Type

    if definition == null {
        throw new InvalidOperationException("Required anonymous-union runtime definition was not found.")
    }

    return definition
}

func ConstructedConversionSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func ConstructedConversionDynamicMethod(name: string, resultType: Type, parameterTypes: Type[]): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorHandle := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if constructorHandle == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }

    constructorArguments := new object[](3)
    ConstructedConversionSetObject(constructorArguments, 0, name)
    ConstructedConversionSetObject(constructorArguments, 1, resultType)
    ConstructedConversionSetObject(constructorArguments, 2, parameterTypes)

    return (DynamicMethod)constructorHandle.Invoke(constructorArguments)
}

func ConstructedConversionRunArrayPlan(plan: ColumnarCodePlan, values: int[]): string {
    parameterTypes := ConstructedConversionOneType(typeof(int[]))
    dynamicMethod := ConstructedConversionDynamicMethod("NSharpConstructedArrayConversion", typeof(int), parameterTypes)

    il := dynamicMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    il.Emit(OpCodes.Ret)

    arguments := new object[](1)
    ConstructedConversionSetObject(arguments, 0, values)
    target: object? = null
    result := dynamicMethod.Invoke(target, arguments)
    if result == null {
        throw new InvalidOperationException("Constructed array conversion returned null unexpectedly.")
    }

    return Convert.ToString(result, CultureInfo.InvariantCulture) ?? ""
}

func ConstructedConversionRunNoArgumentPlan(plan: ColumnarCodePlan, resultType: Type): Type {
    dynamicMethod := ConstructedConversionDynamicMethod("NSharpConstructedUnionConversion", resultType, new Type[](0))

    il := dynamicMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    il.Emit(OpCodes.Ret)

    target: object? = null
    result := dynamicMethod.Invoke(target, new object[](0))
    if result == null {
        throw new InvalidOperationException("Constructed union conversion returned null unexpectedly.")
    }

    return result.GetType()
}

func ConstructedConversionArrayPlan(expectedType: Type, targetName: string): ColumnarCodePlan {
    target := ConstructedConversionRequiredMethod(typeof(ColumnarConstructedConversionProbeMethods), targetName, expectedType)

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1300, 0)
    arrayTypeIndex := plan.AddType(typeof(int[]))
    argumentIndex := plan.AddArgument(0, arrayTypeIndex)
    targetIndex := plan.AddMethod(target)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)

    assert ColumnarDirectCallConstructedConversions.TryAppend(plan, expectedType, typeof(int[]))

    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), targetIndex)

    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
    return plan
}

func ConstructedConversionSpanToReadOnlySpanPlan(): ColumnarCodePlan {
    spanType := typeof(Span<int>)
    readOnlySpanType := typeof(ReadOnlySpan<int>)
    target := ConstructedConversionRequiredMethod(typeof(ColumnarConstructedConversionProbeMethods), "AcceptReadOnlySpan", readOnlySpanType)

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1305, 0)
    arrayTypeIndex := plan.AddType(typeof(int[]))
    argumentIndex := plan.AddArgument(0, arrayTypeIndex)
    targetIndex := plan.AddMethod(target)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)

    assert ColumnarDirectCallConstructedConversions.TryAppend(plan, spanType, typeof(int[]))

    assert ColumnarDirectCallConstructedConversions.TryAppend(plan, readOnlySpanType, spanType)

    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), targetIndex)

    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
    return plan
}

func ConstructedConversionIntUnionPlan(unionType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1301, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_7())

    assert ColumnarDirectCallConstructedConversions.TryAppend(plan, unionType, typeof(int))

    plan.CompleteFragment(root, unionType)
    plan.CompleteV3(unionType)
    return plan
}

func ConstructedConversionStringUnionPlan(unionType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1302, 0)
    stringIndex := plan.AddString("second")
    plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), stringIndex)

    assert ColumnarDirectCallConstructedConversions.TryAppend(plan, unionType, typeof(string))

    plan.CompleteFragment(root, unionType)
    plan.CompleteV3(unionType)
    return plan
}

test "constructed direct-call conversions use the analyzer assignable score tier" {
    spanType := typeof(Span<int>)
    readOnlySpanType := typeof(ReadOnlySpan<int>)
    unionType := ConstructedConversionUnionType(typeof(int), typeof(string))

    assert ColumnarDirectCallConstructedConversions.ArgumentFlowScore(spanType, typeof(int[])) == 4

    assert ColumnarDirectCallConstructedConversions.ArgumentFlowScore(readOnlySpanType, typeof(int[])) == 4

    assert ColumnarDirectCallConstructedConversions.ArgumentFlowScore(readOnlySpanType, spanType) == 4

    assert ColumnarDirectCallConstructedConversions.ArgumentFlowScore(unionType, typeof(int)) == 4

    // Exact and numeric overloads remain strictly better.
    assert ColumnarSourceDirectCallResolver.ArgumentFlowScore(typeof(int[]), typeof(int[])) == 8

    assert ColumnarSourceDirectCallResolver.ArgumentFlowScore(typeof(long), typeof(int)) == 6

    // Object/reference alternatives occupy the same tier and therefore stay ambiguous.
    assert ColumnarSourceDirectCallResolver.ArgumentFlowScore(typeof(object), typeof(int[])) == 4

    assert ColumnarSourceDirectCallResolver.ArgumentFlowScore(typeof(object), typeof(int)) == 4

    assert ColumnarSourceDirectCallResolver.ArgumentFlowScore(readOnlySpanType, spanType) == 4
}

test "source direct-call overloads rank constructed conversions exactly like the analyzer" {
    owner := SourceCallDefinition("ConstructedConversionOverloads", true)

    arrayParameters := ConstructedConversionOneType(typeof(int[]))
    spanParameters := ConstructedConversionOneType(typeof(Span<int>))
    readOnlySpanParameters := ConstructedConversionOneType(typeof(ReadOnlySpan<int>))
    objectParameters := ConstructedConversionOneType(typeof(object))
    longParameters := ConstructedConversionOneType(typeof(long))
    unionType := ConstructedConversionUnionType(typeof(int), typeof(string))

    unionParameters := ConstructedConversionOneType(unionType)

    SourceCallPublicStatic(owner, "SpanOnly", spanParameters, typeof(int))

    SourceCallPublicStatic(owner, "SpanExact", spanParameters, typeof(int))

    SourceCallPublicStatic(owner, "SpanExact", arrayParameters, typeof(int))

    SourceCallPublicStatic(owner, "SpanTie", spanParameters, typeof(int))

    SourceCallPublicStatic(owner, "SpanTie", objectParameters, typeof(int))

    SourceCallPublicStatic(owner, "ReadOnlyOnly", readOnlySpanParameters, typeof(int))

    SourceCallPublicStatic(owner, "ReadOnlyExact", readOnlySpanParameters, typeof(int))

    SourceCallPublicStatic(owner, "ReadOnlyExact", spanParameters, typeof(int))

    SourceCallPublicStatic(owner, "UnionOnly", unionParameters, typeof(int))

    SourceCallPublicStatic(owner, "UnionExact", unionParameters, typeof(int))

    SourceCallPublicStatic(owner, "UnionExact", ConstructedConversionOneType(typeof(int)), typeof(int))

    SourceCallPublicStatic(owner, "UnionNumeric", unionParameters, typeof(int))

    SourceCallPublicStatic(owner, "UnionNumeric", longParameters, typeof(int))

    SourceCallPublicStatic(owner, "UnionTie", unionParameters, typeof(int))

    SourceCallPublicStatic(owner, "UnionTie", objectParameters, typeof(int))

    spanActual := ConstructedConversionOneType(typeof(int[]))
    spanOnly := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "SpanOnly", spanActual)

    spanExact := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "SpanExact", spanActual)

    spanTie := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "SpanTie", spanActual)

    assert spanOnly.IsSelected
    assert spanOnly.ParameterTypes[0] == typeof(Span<int>)
    assert spanExact.IsSelected
    assert spanExact.ParameterTypes[0] == typeof(int[])
    assert !spanTie.IsSelected
    assert spanTie.Status == ColumnarSourceDirectCallStatus.Rejected

    readOnlyActual := ConstructedConversionOneType(typeof(Span<int>))
    readOnlyOnly := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "ReadOnlyOnly", readOnlyActual)

    readOnlyExact := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "ReadOnlyExact", readOnlyActual)

    assert readOnlyOnly.IsSelected
    assert readOnlyOnly.ParameterTypes[0] == typeof(ReadOnlySpan<int>)
    assert readOnlyExact.IsSelected
    assert readOnlyExact.ParameterTypes[0] == typeof(Span<int>)

    unionActual := ConstructedConversionOneType(typeof(int))
    unionOnly := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "UnionOnly", unionActual)

    unionExact := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "UnionExact", unionActual)

    unionNumeric := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "UnionNumeric", unionActual)

    unionTie := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(owner, owner.Builder, "UnionTie", unionActual)

    assert unionOnly.IsSelected
    assert unionOnly.ParameterTypes[0] == unionType
    assert unionExact.IsSelected
    assert unionExact.ParameterTypes[0] == typeof(int)
    assert unionNumeric.IsSelected
    assert unionNumeric.ParameterTypes[0] == typeof(long)
    assert !unionTie.IsSelected
    assert unionTie.Status == ColumnarSourceDirectCallStatus.Rejected
}

test "constructed direct-call conversion classification pins exact span and union shapes" {
    spanSelection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(typeof(Span<int>), typeof(int[]), out spanSelection)

    assert spanSelection != null
    assert spanSelection.Kind == ColumnarDirectCallConstructedConversionKind.ArrayToSpan

    assert spanSelection.Score == 4

    readOnlySelection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(typeof(ReadOnlySpan<int>), typeof(int[]), out readOnlySelection)

    assert readOnlySelection != null
    assert readOnlySelection.Kind == ColumnarDirectCallConstructedConversionKind.ArrayToReadOnlySpan

    spanToReadOnlySelection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(typeof(ReadOnlySpan<int>), typeof(Span<int>), out spanToReadOnlySelection)

    assert spanToReadOnlySelection != null
    assert spanToReadOnlySelection.Kind == ColumnarDirectCallConstructedConversionKind.SpanToReadOnlySpan
    assert spanToReadOnlySelection.ConstructorHandle == null
    assert spanToReadOnlySelection.MethodHandle != null
    spanToReadOnlyMethod := spanToReadOnlySelection.MethodHandle
    assert spanToReadOnlyMethod.get_Name() == "op_Implicit"
    assert spanToReadOnlyMethod.get_IsPublic()
    assert spanToReadOnlyMethod.get_IsStatic()
    assert !spanToReadOnlyMethod.get_IsGenericMethod()
    assert spanToReadOnlyMethod.get_DeclaringType() == typeof(Span<int>)
    assert spanToReadOnlyMethod.get_ReturnType() == typeof(ReadOnlySpan<int>)
    spanToReadOnlyParameters := spanToReadOnlyMethod.GetParameters()
    assert spanToReadOnlyParameters.Length == 1
    assert spanToReadOnlyParameters[0].get_ParameterType() == typeof(Span<int>)

    unionType := ConstructedConversionUnionType(typeof(int), typeof(string))

    firstSelection: ColumnarDirectCallConstructedConversionSelection? = null
    secondSelection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(unionType, typeof(int), out firstSelection)

    assert ColumnarDirectCallConstructedConversions.TryClassify(unionType, typeof(string), out secondSelection)

    assert firstSelection != null
    assert secondSelection != null
    assert firstSelection.Kind == ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm0

    assert secondSelection.Kind == ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm1
}

test "constructed direct-call conversions reject non-exact and analyzer-declined shapes" {
    assert !ColumnarDirectCallConstructedConversions.CanConvert(typeof(Span<long>), typeof(int[]))

    assert ColumnarDirectCallConstructedConversions.CanConvert(typeof(ReadOnlySpan<int>), typeof(Span<int>))

    assert !ColumnarDirectCallConstructedConversions.CanConvert(typeof(ReadOnlySpan<long>), typeof(Span<int>))

    assert !ColumnarDirectCallConstructedConversions.CanConvert(typeof(Span<int>), typeof(ReadOnlySpan<int>))

    assert !ColumnarDirectCallConstructedConversions.CanConvert(typeof(Span<int>), typeof(int[][]))

    assert !ColumnarDirectCallConstructedConversions.CanConvert(typeof(object), typeof(int[]))

    unionType := ConstructedConversionUnionType(typeof(long), typeof(string))

    assert !ColumnarDirectCallConstructedConversions.CanConvert(unionType, typeof(int))

    duplicateArms := ConstructedConversionUnionType(typeof(int), typeof(int))

    assert !ColumnarDirectCallConstructedConversions.CanConvert(duplicateArms, typeof(int))
}

test "constructed array conversions persist exact newobj and call rows and execute" {
    spanPlan := ConstructedConversionArrayPlan(typeof(Span<int>), "AcceptSpan")

    readOnlyPlan := ConstructedConversionArrayPlan(typeof(ReadOnlySpan<int>), "AcceptReadOnlySpan")

    assert spanPlan.OperationCount == 3
    assert spanPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert spanPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
    assert spanPlan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    assert spanPlan.ConstructorCount == 1
    assert spanPlan.ConstructorUsesDeclaredSignature[0]
    assert spanPlan.ConstructorDeclaringTypes[0] == typeof(Span<int>)
    spanDeclaredParameters := spanPlan.ConstructorParameterTypes[0]
    assert spanDeclaredParameters.Length == 1
    assert spanDeclaredParameters[0] == typeof(int[])
    spanConstructor := spanPlan.Constructors[0]
    assert spanConstructor.get_DeclaringType() == typeof(Span<int>)
    spanParameters := spanConstructor.GetParameters()
    assert spanParameters.Length == 1
    assert spanParameters[0].get_ParameterType() == typeof(int[])

    assert readOnlyPlan.OperationCount == 3
    assert readOnlyPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()

    assert readOnlyPlan.OpCodeValues[2] == ColumnarCodePlanContract.Call()

    assert readOnlyPlan.Constructors[0].get_DeclaringType() == typeof(ReadOnlySpan<int>)

    values := new int[](3)
    values[0] = 5
    values[1] = 8
    values[2] = 13
    assert ConstructedConversionRunArrayPlan(spanPlan, values) == "31"
    assert ConstructedConversionRunArrayPlan(readOnlyPlan, values) == "32"
    assert spanPlan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
    assert readOnlyPlan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
}

test "span to readonly span conversion persists the exact implicit call and executes" {
    plan := ConstructedConversionSpanToReadOnlySpanPlan()

    assert plan.OperationCount == 4
    opCodes := plan.OpCodeValues
    assert opCodes[0] == ColumnarCodePlanContract.Ldarg()
    assert opCodes[1] == ColumnarCodePlanContract.Newobj()
    assert opCodes[2] == ColumnarCodePlanContract.Call()
    assert opCodes[3] == ColumnarCodePlanContract.Call()
    assert plan.ConstructorCount == 1
    assert plan.MethodCount == 2

    operandIndices := plan.OperandIndices
    conversionIndex := operandIndices[2]
    targetIndex := operandIndices[3]
    assert conversionIndex >= 0 && conversionIndex < plan.MethodCount
    assert targetIndex >= 0 && targetIndex < plan.MethodCount
    assert plan.Methods[conversionIndex].get_Name() == "op_Implicit"
    assert plan.MethodUsesDeclaredSignature[conversionIndex]
    assert plan.MethodDeclaringTypes[conversionIndex] == typeof(Span<int>)
    conversionParameters := plan.MethodParameterTypes[conversionIndex]
    assert conversionParameters.Length == 1
    assert conversionParameters[0] == typeof(Span<int>)
    assert plan.MethodReturnTypes[conversionIndex] == typeof(ReadOnlySpan<int>)
    assert plan.MethodIsStatic[conversionIndex]
    assert !plan.MethodIsAbstract[conversionIndex]
    assert plan.Methods[targetIndex].get_Name() == "AcceptReadOnlySpan"

    values := new int[](3)
    values[0] = 3
    values[1] = 5
    values[2] = 8
    assert ConstructedConversionRunArrayPlan(plan, values) == "32"
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
}

test "constructed anonymous-union arm conversions persist exact constructors and execute" {
    unionType := ConstructedConversionUnionType(typeof(int), typeof(string))

    firstPlan := ConstructedConversionIntUnionPlan(unionType)
    secondPlan := ConstructedConversionStringUnionPlan(unionType)

    assert firstPlan.OperationCount == 2
    assert firstPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
    assert firstPlan.ConstructorCount == 1
    assert firstPlan.ConstructorUsesDeclaredSignature[0]
    assert firstPlan.ConstructorDeclaringTypes[0] == unionType
    firstDeclaredParameters := firstPlan.ConstructorParameterTypes[0]
    assert firstDeclaredParameters.Length == 1
    assert firstDeclaredParameters[0] == typeof(int)
    firstParameters := firstPlan.Constructors[0].GetParameters()
    assert firstParameters.Length == 1
    assert firstParameters[0].get_ParameterType() == typeof(int)

    assert secondPlan.OperationCount == 2
    assert secondPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
    secondParameters := secondPlan.Constructors[0].GetParameters()
    assert secondParameters.Length == 1
    assert secondParameters[0].get_ParameterType() == typeof(string)

    assert ConstructedConversionRunNoArgumentPlan(firstPlan, unionType) == unionType
    assert ConstructedConversionRunNoArgumentPlan(secondPlan, unionType) == unionType
}

test "constructed anonymous-union conversion preserves a builder-bound arm signature" {
    sourceBuilder := TypeOfCreateBuilder("ConstructedConversionSourceArm", "ColumnarConstructedConversionTests.SourceArm", 0)
    sourceType: Type = sourceBuilder

    unionType := ConstructedConversionUnionType(sourceType, typeof(string))

    selection: ColumnarDirectCallConstructedConversionSelection? = null
    if !ColumnarDirectCallConstructedConversions.TryClassify(unionType, sourceType, out selection) || selection == null {
        throw new InvalidOperationException("Builder-bound anonymous-union arm classification failed.")
    }

    if selection.Kind != ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm0 {
        throw new InvalidOperationException("Builder-bound anonymous-union arm classification chose the wrong arm.")
    }

    constructorHandle := selection.ConstructorHandle
    if constructorHandle == null {
        throw new InvalidOperationException("Builder-bound anonymous-union selection lost its constructor handle.")
    }

    openParameters := constructorHandle.GetParameters()
    if openParameters.Length != 1 {
        throw new InvalidOperationException("Builder-bound anonymous-union constructor did not expose one parameter.")
    }

    openParameterType := openParameters[0].get_ParameterType()
    if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(openParameterType, sourceType) && (!openParameterType.get_IsGenericParameter() || openParameterType.get_GenericParameterPosition() != 0) {
        throw new InvalidOperationException("Builder-bound anonymous-union constructor exposed the wrong arm parameter.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1304, 0)
    sourceTypeIndex := plan.AddType(sourceType)
    argumentIndex := plan.AddArgument(0, sourceTypeIndex)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)

    if !ColumnarDirectCallConstructedConversions.TryAppend(plan, selection) {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion did not append.")
    }

    plan.CompleteFragment(root, unionType)
    plan.CompleteV3(unionType)

    if plan.OperationCount != 2 || plan.OpCodeValues[1] != ColumnarCodePlanContract.Newobj() {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion emitted the wrong operation shape.")
    }

    if plan.ConstructorCount != 1 {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion did not persist one constructor.")
    }

    signatureFlags := plan.ConstructorUsesDeclaredSignature
    declaringTypes := plan.ConstructorDeclaringTypes
    parameterLists := plan.ConstructorParameterTypes
    if signatureFlags.Length < 1 || !signatureFlags[0] {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion did not persist a declared signature.")
    }

    if declaringTypes.Length < 1 || declaringTypes[0] != unionType {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion persisted the wrong declaring type.")
    }

    if parameterLists.Length < 1 {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion persisted the wrong parameter-list count.")
    }

    constructorParameters := parameterLists[0]
    if constructorParameters.Length != 1 || constructorParameters[0] != sourceType {
        throw new InvalidOperationException("Builder-bound anonymous-union conversion persisted the wrong arm parameter.")
    }

    ColumnarCodePlanExecutor.Validate(plan)
}

test "constructed conversion append rejects corrupt constructor facts atomically" {
    unionType := ConstructedConversionUnionType(typeof(int), typeof(string))

    selection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(unionType, typeof(int), out selection)

    assert selection != null

    selection.ConstructorHandle = ConstructedConversionRequiredConstructor(unionType, ConstructedConversionOneType(typeof(string)))

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1303, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())

    operationCount := plan.OperationCount
    constructorCount := plan.ConstructorCount

    assert !ColumnarDirectCallConstructedConversions.TryAppend(plan, selection)

    assert plan.OperationCount == operationCount
    assert plan.ConstructorCount == constructorCount

    indexParameters := new Type[](2)
    indexParameters[0] = typeof(int)
    indexParameters[1] = typeof(bool)
    selection.ConstructorHandle = ConstructedConversionRequiredConstructor(typeof(Index), indexParameters)

    assert !ColumnarDirectCallConstructedConversions.TryAppend(plan, selection)

    assert plan.OperationCount == operationCount
    assert plan.ConstructorCount == constructorCount
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
}

test "span to readonly span append rejects corrupt method facts atomically" {
    expectedType := typeof(ReadOnlySpan<int>)
    actualType := typeof(Span<int>)
    selection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(expectedType, actualType, out selection)
    assert selection != null

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1306, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    operationCount := plan.OperationCount
    methodCount := plan.MethodCount
    constructorCount := plan.ConstructorCount

    // Same declaring type, but the array conversion has the wrong exact parameter and return.
    selection.MethodHandle = ConstructedConversionRequiredMethod(typeof(Span<int>), "op_Implicit", typeof(int[]))
    assert !ColumnarDirectCallConstructedConversions.TryAppend(plan, selection)
    assert plan.OperationCount == operationCount
    assert plan.MethodCount == methodCount
    assert plan.ConstructorCount == constructorCount

    // An otherwise exact method shape from another owner is not the CLR span conversion handle.
    foreignOwner := SourceCallDefinition("ConstructedConversionForeignOwner", true)
    foreignMethod := SourceCallDefineStatic(foreignOwner, "op_Implicit", ConstructedConversionOneType(actualType), new int[](0), expectedType, (MethodAttributes)2070)
    selection.MethodHandle = foreignMethod.Builder
    assert !ColumnarDirectCallConstructedConversions.TryAppend(plan, selection)
    assert plan.OperationCount == operationCount
    assert plan.MethodCount == methodCount
    assert plan.ConstructorCount == constructorCount

    // Method-based selections must never carry a constructor as a second competing handle.
    validSelection: ColumnarDirectCallConstructedConversionSelection? = null
    assert ColumnarDirectCallConstructedConversions.TryClassify(expectedType, actualType, out validSelection)
    assert validSelection != null
    validSelection.ConstructorHandle = ConstructedConversionRequiredConstructor(typeof(Span<int>), ConstructedConversionOneType(typeof(int[])))
    assert !ColumnarDirectCallConstructedConversions.TryAppend(plan, validSelection)
    assert plan.OperationCount == operationCount
    assert plan.MethodCount == methodCount
    assert plan.ConstructorCount == constructorCount

    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
}

test "constructed conversion append rolls back a failed plan mutation" {
    unionType := ConstructedConversionUnionType(typeof(int), typeof(string))

    plan := new ColumnarCodePlan()
    plan.PrepareV3()

    // No fragment is open, so appending the row fails after the constructor pool mutation.
    assert throws InvalidOperationException {
        ColumnarDirectCallConstructedConversions.TryAppend(plan, unionType, typeof(int))
    }

    assert plan.OperationCount == 0
    assert plan.ConstructorCount == 0
    assert plan.FragmentCount == 0
}

test "span to readonly span append rolls back its method pool mutation" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()

    // No fragment is open, so appending Call fails after the exact method is persisted.
    assert throws InvalidOperationException {
        ColumnarDirectCallConstructedConversions.TryAppend(plan, typeof(ReadOnlySpan<int>), typeof(Span<int>))
    }

    assert plan.OperationCount == 0
    assert plan.MethodCount == 0
    assert plan.ConstructorCount == 0
    assert plan.FragmentCount == 0
}

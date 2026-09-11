namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

class ColumnarSourceImplicitConversionProbeMethods {
    static func Accept(value: int): int {
        return value + 1
    }
}

func SourceImplicitOneType(value: Type): Type[] {
    result := new Type[](1)
    result[0] = value
    return result
}

func SourceImplicitDefinitions(first: ColumnarStructDef, second: ColumnarStructDef): ColumnarStructDef[] {
    result := new ColumnarStructDef[](2)
    result[0] = first
    result[1] = second
    return result
}

func SourceImplicitThreeDefinitions(first: ColumnarStructDef, second: ColumnarStructDef, third: ColumnarStructDef): ColumnarStructDef[] {
    result := new ColumnarStructDef[](3)
    result[0] = first
    result[1] = second
    result[2] = third
    return result
}

func SourceImplicitTwoTypes(first: Type, second: Type): Type[] {
    result := new Type[](2)
    result[0] = first
    result[1] = second
    return result
}

func SourceImplicitOperator(owner: ColumnarStructDef, sourceType: Type, targetType: Type): ColumnarStaticMethodDef {
    // Public | Static | SpecialName, matching the metadata emitted for N# conversion syntax.
    return SourceCallDefineStatic(owner, "op_Implicit", SourceImplicitOneType(sourceType), new int[](0), targetType, (MethodAttributes)2070)
}

func SourceImplicitRequiredMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("Required source implicit-conversion probe method was not found: " + name)
    }

    return method
}

func SourceImplicitBake(owner: ColumnarStructDef): Type {
    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))

    value := TypeOfRequiredInvocation(createType, owner.Builder, new object[](0))

    baked := value as Type
    if baked == null {
        throw new InvalidOperationException("Source implicit-conversion fixture did not produce a runtime type.")
    }

    return baked
}

func SourceImplicitExecutionPlan(selection: ColumnarSourceImplicitConversionSelection): ColumnarCodePlan {
    targetParameters := SourceImplicitOneType(typeof(int))
    target := SourceImplicitRequiredMethod(typeof(ColumnarSourceImplicitConversionProbeMethods), "Accept", targetParameters)

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1700, 0)
    sourceTypeIndex := plan.AddType(selection.SourceType)
    sourceArgument := plan.AddArgument(0, sourceTypeIndex, false)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), sourceArgument)
    if !ColumnarSourceImplicitConversionResolver.TryAppendCall(plan, selection) {
        throw new InvalidOperationException("Expected an exact source implicit-conversion call append.")
    }

    targetIndex := plan.AddMethodWithSignature(target, typeof(ColumnarSourceImplicitConversionProbeMethods), targetParameters, typeof(int), true, false)

    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), targetIndex)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV3(typeof(int))
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

test "source implicit conversion requires exact source-owned parameter and return identities" {
    source := SourceCallDefinition("SourceImplicitExactSource", true)
    target := SourceCallDefinition("SourceImplicitExactTarget", true)
    sourceType: Type = source.Builder
    targetType: Type = target.Builder
    definition := SourceImplicitOperator(source, sourceType, targetType)
    definitionMethod: MethodInfo = definition.Builder
    definitions := SourceImplicitDefinitions(source, target)

    selected := ColumnarSourceImplicitConversionResolver.ResolveExact(sourceType, targetType, definitions)

    assert selected.Status == ColumnarSourceImplicitConversionStatus.Selected
    assert selected.IsSelected
    assert selected.SourceDefinition == source
    assert selected.OperatorDefinition == definition
    assert selected.SourceType == sourceType
    assert selected.TargetType == targetType
    assert selected.DeclaringType == sourceType
    assert Object.ReferenceEquals(selected.Method, definitionMethod)
    assert selected.ParameterTypes.Length == 1
    assert selected.ParameterTypes[0] == sourceType
    selectedMethod := selected.Method
    if selectedMethod == null {
        throw new InvalidOperationException("Selected source implicit conversion has no method.")
    }

    assert selectedMethod.get_IsPublic()
    assert selectedMethod.get_IsStatic()
    assert !selectedMethod.get_IsGenericMethod()

    wrongSource := SourceCallDefinition("SourceImplicitWrongParameter", true)
    wrongSourceType: Type = wrongSource.Builder
    SourceImplicitOperator(wrongSource, typeof(string), targetType)
    wrongSourceResult := ColumnarSourceImplicitConversionResolver.ResolveExact(wrongSourceType, targetType, SourceImplicitDefinitions(wrongSource, target))

    assert wrongSourceResult.Status == ColumnarSourceImplicitConversionStatus.NoConversion

    returnUpcast := SourceCallDefinition("SourceImplicitReturnUpcast", true)
    returnUpcastType: Type = returnUpcast.Builder
    SourceImplicitOperator(returnUpcast, returnUpcastType, typeof(string))
    returnUpcastResult := ColumnarSourceImplicitConversionResolver.ResolveExact(returnUpcastType, typeof(object), SourceCallDefinitions(returnUpcast))

    // The analyzer can describe this as assignable, but the backend cannot lower an exact
    // source operator plus a second return upcast as one argument conversion.
    assert returnUpcastResult.Status == ColumnarSourceImplicitConversionStatus.NoConversion
}

test "target-only and inherited implicit operators stay outside the analyzer backend intersection" {
    source := SourceCallDefinition("SourceImplicitTargetOnlySource", true)
    target := SourceCallDefinition("SourceImplicitTargetOnlyTarget", true)
    SourceImplicitOperator(target, source.Builder, target.Builder)

    targetOnly := ColumnarSourceImplicitConversionResolver.ResolveExact(source.Builder, target.Builder, SourceImplicitDefinitions(source, target))

    assert targetOnly.Status == ColumnarSourceImplicitConversionStatus.NoConversion
    assert !targetOnly.IsSelected

    baseDefinition := SourceCallDefinition("SourceImplicitBaseOwner", true)
    derivedDefinition := SourceCallDefinition("SourceImplicitDerivedSource", true)
    inheritedTarget := SourceCallDefinition("SourceImplicitInheritedTarget", true)
    derivedDefinition.BaseDef = baseDefinition
    SourceImplicitOperator(baseDefinition, derivedDefinition.Builder, inheritedTarget.Builder)

    allDefinitions := new ColumnarStructDef[](3)
    allDefinitions[0] = baseDefinition
    allDefinitions[1] = derivedDefinition
    allDefinitions[2] = inheritedTarget
    inherited := ColumnarSourceImplicitConversionResolver.ResolveExact(derivedDefinition.Builder, inheritedTarget.Builder, allDefinitions)

    assert inherited.Status == ColumnarSourceImplicitConversionStatus.NoConversion
    assert !inherited.IsSelected
}

test "source implicit conversion ambiguity and malformed facts never select a call" {
    source := SourceCallDefinition("SourceImplicitAmbiguousSource", true)
    target := SourceCallDefinition("SourceImplicitAmbiguousTarget", true)
    SourceImplicitOperator(source, source.Builder, target.Builder)
    SourceImplicitOperator(source, source.Builder, target.Builder)
    definitions := SourceImplicitDefinitions(source, target)

    ambiguous := ColumnarSourceImplicitConversionResolver.ResolveExact(source.Builder, target.Builder, definitions)

    assert ambiguous.Status == ColumnarSourceImplicitConversionStatus.Ambiguous, "two distinct exact source operators must be ambiguous"
    assert ambiguous.IsAmbiguous, "ambiguous source conversion must expose its status"
    assert !ambiguous.IsSelected, "ambiguous source conversion cannot select an operator"

    score := 0
    classified := new ColumnarSourceImplicitConversionSelection(ColumnarSourceImplicitConversionStatus.NoConversion, null, null, source.Builder, target.Builder, typeof(object), null, new Type[](0))

    assert !ColumnarSourceImplicitConversionResolver.TryClassifyArgument(target.Builder, source.Builder, definitions, out score, out classified), "ambiguous source conversion cannot classify an argument"

    assert score == -1, "failed ambiguous classification must retain the rejection score"
    assert classified.IsAmbiguous, "failed classification must return the ambiguous facts"

    repeatedSource := SourceCallDefinition("SourceImplicitRepeatedHandleSource", true)
    repeatedTarget := SourceCallDefinition("SourceImplicitRepeatedHandleTarget", true)
    repeatedSourceType: Type = repeatedSource.Builder
    repeatedTargetType: Type = repeatedTarget.Builder
    repeatedOperator := SourceImplicitOperator(repeatedSource, repeatedSourceType, repeatedTargetType)

    repeatedMethod: MethodInfo = repeatedOperator.Builder
    SourceCallAddStaticFact(repeatedSource, "op_Implicit", repeatedOperator)
    repeated := ColumnarSourceImplicitConversionResolver.ResolveExact(repeatedSourceType, repeatedTargetType, SourceImplicitDefinitions(repeatedSource, repeatedTarget))

    assert repeated.Status == ColumnarSourceImplicitConversionStatus.Selected, "repeated facts for one exact handle must deduplicate"
    assert Object.ReferenceEquals(repeated.Method, repeatedMethod), "deduplication must retain the exact repeated handle"

    malformedSource := SourceCallDefinition("SourceImplicitMalformedSource", true)
    malformedTarget := SourceCallDefinition("SourceImplicitMalformedTarget", true)
    foreignOwner := SourceCallDefinition("SourceImplicitForeignOwner", true)
    foreignOperator := SourceImplicitOperator(foreignOwner, malformedSource.Builder, malformedTarget.Builder)

    SourceCallAddStaticFact(malformedSource, "op_Implicit", foreignOperator)

    assert throws InvalidOperationException {
        ColumnarSourceImplicitConversionResolver.ResolveExact(malformedSource.Builder, malformedTarget.Builder, SourceImplicitDefinitions(malformedSource, malformedTarget))
    }
}

test "source implicit conversion excludes inaccessible generic and modified operator shapes" {
    target := SourceCallDefinition("SourceImplicitExcludedTarget", true)

    privateSource := SourceCallDefinition("SourceImplicitPrivateSource", true)
    SourceCallDefineStatic(privateSource, "op_Implicit", SourceImplicitOneType(privateSource.Builder), new int[](0), target.Builder, (MethodAttributes)2065)
    privateResult := ColumnarSourceImplicitConversionResolver.ResolveExact(privateSource.Builder, target.Builder, SourceImplicitDefinitions(privateSource, target))

    assert privateResult.Status == ColumnarSourceImplicitConversionStatus.NoConversion

    genericSource := SourceCallDefinition("SourceImplicitGenericSource", true)
    genericOperator := SourceImplicitOperator(genericSource, genericSource.Builder, target.Builder)
    SourceCallMakeGeneric(genericOperator.Builder)
    genericResult := ColumnarSourceImplicitConversionResolver.ResolveExact(genericSource.Builder, target.Builder, SourceImplicitDefinitions(genericSource, target))

    assert genericResult.Status == ColumnarSourceImplicitConversionStatus.NoConversion

    modifiedSource := SourceCallDefinition("SourceImplicitModifiedSource", true)
    modifiers := new int[](1)
    modifiers[0] = 1
    SourceCallDefineStatic(modifiedSource, "op_Implicit", SourceImplicitOneType(modifiedSource.Builder), modifiers, target.Builder, (MethodAttributes)2070)
    modifiedResult := ColumnarSourceImplicitConversionResolver.ResolveExact(modifiedSource.Builder, target.Builder, SourceImplicitDefinitions(modifiedSource, target))

    assert modifiedResult.Status == ColumnarSourceImplicitConversionStatus.NoConversion
}

test "source implicit conversion scoring preserves exact numeric and assignability betterness" {
    source := SourceCallDefinition("SourceImplicitScoreSource", true)
    target := SourceCallDefinition("SourceImplicitScoreTarget", true)
    SourceImplicitOperator(source, source.Builder, target.Builder)
    definitions := SourceImplicitDefinitions(source, target)

    exactScore := -1
    exactConversion := ColumnarSourceImplicitConversionResolver.ResolveExact(source.Builder, target.Builder, definitions)

    assert ColumnarSourceImplicitConversionResolver.TryClassifyArgument(source.Builder, source.Builder, definitions, out exactScore, out exactConversion)

    assert exactScore == 8
    assert !exactConversion.IsSelected

    numericScore := -1
    numericConversion := ColumnarSourceImplicitConversionResolver.ResolveExact(source.Builder, target.Builder, definitions)

    assert ColumnarSourceImplicitConversionResolver.TryClassifyArgument(typeof(long), typeof(int), definitions, out numericScore, out numericConversion)

    assert numericScore == 6
    assert !numericConversion.IsSelected

    conversionScore := -1
    conversion := ColumnarSourceImplicitConversionResolver.ResolveExact(source.Builder, target.Builder, definitions)

    assert ColumnarSourceImplicitConversionResolver.TryClassifyArgument(target.Builder, source.Builder, definitions, out conversionScore, out conversion)

    assert conversionScore == ColumnarSourceImplicitConversionResolver.CompatibilityScore()

    assert conversion.IsSelected

    assignableScore := -1
    assignableConversion := conversion
    assert ColumnarSourceImplicitConversionResolver.TryClassifyArgument(typeof(object), source.Builder, definitions, out assignableScore, out assignableConversion)

    assert assignableScore == conversionScore
    assert !assignableConversion.IsSelected

    assert exactScore > numericScore
    assert numericScore > conversionScore

    // Multi-argument overload totals retain the analyzer's deliberate tie: one exact plus one
    // user conversion equals two numeric conversions, while exact plus numeric wins both.
    assert exactScore + conversionScore == numericScore + numericScore
    assert exactScore + numericScore > exactScore + conversionScore
}

test "source direct-call overloads apply implicit conversion scores without weakening betterness" {
    source := SourceCallDefinition("SourceImplicitOverloadSource", true)
    target := SourceCallDefinition("SourceImplicitOverloadTarget", true)
    owner := SourceCallDefinition("SourceImplicitOverloadOwner", true)
    sourceType: Type = source.Builder
    targetType: Type = target.Builder
    ownerType: Type = owner.Builder
    SourceImplicitOperator(source, sourceType, targetType)
    definitions := SourceImplicitThreeDefinitions(source, target, owner)

    SourceCallPublicStatic(owner, "ExactFirst", SourceImplicitOneType(targetType), typeof(int))
    SourceCallPublicStatic(owner, "ExactFirst", SourceImplicitOneType(sourceType), typeof(int))

    exactFacts := ColumnarDirectCallArgumentFacts.Empty(1)
    exactFacts.SourceTypeDefinitions = definitions
    exact := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "ExactFirst", SourceImplicitOneType(sourceType), definitions, exactFacts)

    assert exact.IsSelected
    exactParameterTypes := exact.ParameterTypes
    assert exactParameterTypes.Length == 1
    assert exactParameterTypes[0] == sourceType

    SourceCallPublicStatic(owner, "NumericWins", SourceImplicitTwoTypes(targetType, typeof(int)), typeof(int))
    SourceCallPublicStatic(owner, "NumericWins", SourceImplicitTwoTypes(sourceType, typeof(long)), typeof(int))

    twoFacts := ColumnarDirectCallArgumentFacts.Empty(2)
    twoFacts.SourceTypeDefinitions = definitions
    actualTypes := SourceImplicitTwoTypes(sourceType, typeof(int))
    numericWinner := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "NumericWins", actualTypes, definitions, twoFacts)

    assert numericWinner.IsSelected
    numericParameterTypes := numericWinner.ParameterTypes
    assert numericParameterTypes[0] == sourceType
    assert numericParameterTypes[1] == typeof(long)

    SourceCallPublicStatic(owner, "AssignableTie", SourceImplicitTwoTypes(targetType, typeof(int)), typeof(int))
    SourceCallPublicStatic(owner, "AssignableTie", SourceImplicitTwoTypes(sourceType, typeof(object)), typeof(int))
    tied := ColumnarSourceDirectCallResolver.ResolveExplicitStatic(ownerType, "AssignableTie", actualTypes, definitions, twoFacts)

    assert tied.Status == ColumnarSourceDirectCallStatus.Rejected
    assert !tied.IsSelected
}

test "direct-call planner places the exact source implicit operator before its target call" {
    source := SourceCallDefinition("SourceImplicitPlannerSource", true)
    target := SourceCallDefinition("SourceImplicitPlannerTarget", true)
    owner := SourceCallDefinition("SourceImplicitPlannerOwner", true)
    sourceType: Type = source.Builder
    targetType: Type = target.Builder
    definition := SourceImplicitOperator(source, sourceType, targetType)
    definitionMethod: MethodInfo = definition.Builder
    targetMethod := SourceCallPublicStatic(owner, "Take", SourceImplicitOneType(targetType), typeof(int))
    targetMethodHandle: MethodInfo = targetMethod.Builder
    definitions := SourceImplicitThreeDefinitions(source, target, owner)

    bindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, sourceType)
    tree := DirectCallQualifiedTree("SourceImplicitPlannerOwner", "Take", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    plan := DirectCallPlan(tree, bindings)

    assert plan.OperationCount == 3
    opCodes := plan.OpCodeValues
    assert opCodes[0] == ColumnarCodePlanContract.Ldarg()
    assert opCodes[1] == ColumnarCodePlanContract.Call()
    assert opCodes[2] == ColumnarCodePlanContract.Call()
    operandIndices := plan.OperandIndices
    conversionIndex := operandIndices[1]
    targetIndex := operandIndices[2]
    methods := plan.Methods
    methodParameterTypes := plan.MethodParameterTypes
    methodReturnTypes := plan.MethodReturnTypes
    conversionParameterTypes := methodParameterTypes[conversionIndex]
    targetParameterTypes := methodParameterTypes[targetIndex]
    assert Object.ReferenceEquals(methods[conversionIndex], definitionMethod)
    assert conversionParameterTypes[0] == sourceType
    assert methodReturnTypes[conversionIndex] == targetType
    assert Object.ReferenceEquals(methods[targetIndex], targetMethodHandle)
    assert targetParameterTypes[0] == targetType
}

test "source implicit conversion append is atomic when selected facts become malformed" {
    source := SourceCallDefinition("SourceImplicitRollbackSource", true)
    target := SourceCallDefinition("SourceImplicitRollbackTarget", true)
    definition := SourceImplicitOperator(source, source.Builder, target.Builder)
    selection := ColumnarSourceImplicitConversionResolver.ResolveExact(source.Builder, target.Builder, SourceImplicitDefinitions(source, target))

    plan := new ColumnarCodePlan()
    plan.PrepareV3()

    // Corrupt the live declaration after selection. Append must revalidate the handle snapshot
    // inside its own transaction and restore every pool/operation count on failure.
    definition.ReturnType = typeof(string)
    assert throws InvalidOperationException {
        ColumnarSourceImplicitConversionResolver.TryAppendCall(plan, selection)
    }

    ColumnarRangePlannerAssertEmptyRollback(plan)

    unselected := ColumnarSourceImplicitConversionResolver.ResolveExact(typeof(int), typeof(string), SourceImplicitDefinitions(source, target))

    assert !ColumnarSourceImplicitConversionResolver.TryAppendCall(plan, unselected)
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "source implicit conversion call persists exact IL shape and executes before the target call" {
    source := SourceCallDefinition("SourceImplicitExecutionSource", true)
    sourceType: Type = source.Builder
    definition := SourceImplicitOperator(source, sourceType, typeof(int))
    definitionMethod: MethodInfo = definition.Builder
    selection := ColumnarSourceImplicitConversionResolver.ResolveExact(sourceType, typeof(int), SourceCallDefinitions(source))

    operatorIl := TypeOfMethodBuilderIL(definition.Builder)
    operatorIl.Emit(OpCodes.Ldc_I4, 41)
    operatorIl.Emit(OpCodes.Ret)

    plan := SourceImplicitExecutionPlan(selection)

    assert plan.OperationCount == 3
    opCodes := plan.OpCodeValues
    assert opCodes[0] == ColumnarCodePlanContract.Ldarg()
    assert opCodes[1] == ColumnarCodePlanContract.Call()
    assert opCodes[2] == ColumnarCodePlanContract.Call()

    operandIndices := plan.OperandIndices
    conversionIndex := operandIndices[1]
    targetIndex := operandIndices[2]
    assert conversionIndex >= 0 && conversionIndex < plan.MethodCount
    assert targetIndex >= 0 && targetIndex < plan.MethodCount
    methods := plan.Methods
    signatureFlags := plan.MethodUsesDeclaredSignature
    declaringTypes := plan.MethodDeclaringTypes
    parameterTypes := plan.MethodParameterTypes
    conversionParameterTypes := parameterTypes[conversionIndex]
    returnTypes := plan.MethodReturnTypes
    staticFlags := plan.MethodIsStatic
    abstractFlags := plan.MethodIsAbstract
    assert Object.ReferenceEquals(methods[conversionIndex], definitionMethod)
    assert signatureFlags[conversionIndex]
    assert declaringTypes[conversionIndex] == sourceType
    assert conversionParameterTypes.Length == 1
    assert conversionParameterTypes[0] == sourceType
    assert returnTypes[conversionIndex] == typeof(int)
    assert staticFlags[conversionIndex]
    assert !abstractFlags[conversionIndex]
    assert methods[targetIndex].get_Name() == "Accept"

    wrapperParameters := SourceImplicitOneType(sourceType)
    wrapperBuilder := source.Builder.DefineMethod("RunConversion", (MethodAttributes)22, typeof(int), wrapperParameters)
    wrapperIl := TypeOfMethodBuilderIL(wrapperBuilder)
    ColumnarCodePlanExecutor.Execute(plan, wrapperIl)
    wrapperIl.Emit(OpCodes.Ret)

    // Baking the owner validates the persisted MethodBuilder operand as real CLR IL, rather than
    // only replaying it through an in-memory assertion surface.
    bakedSource := SourceImplicitBake(source)
    constructor := bakedSource.GetConstructor(new Type[](0))
    if constructor == null {
        throw new InvalidOperationException("Source implicit-conversion runtime fixture has no default constructor.")
    }

    instance := TypeOfRequiredConstruction(constructor, new object[](0))
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, instance)
    runtimeWrapper := SourceImplicitRequiredMethod(bakedSource, "RunConversion", SourceImplicitOneType(bakedSource))
    result := TypeOfRequiredInvocation(runtimeWrapper, null, arguments)
    assert result.ToString() == "42"
}

namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

func ConstructorSignatureOneType(valueType: Type): Type[] {
    result := new Type[](1)
    result[0] = valueType
    return result
}

func ConstructorSignatureRequired(ownerType: Type, parameterType: Type): ConstructorInfo {
    constructorInfo := ownerType.GetConstructor(ConstructorSignatureOneType(parameterType))

    if constructorInfo == null {
        throw new InvalidOperationException("Required declared-signature constructor was not found.")
    }

    return constructorInfo
}

func ConstructorSignatureNullablePlan(): ColumnarCodePlan {
    nullableInt := NullableArgumentType(typeof(int))
    constructorInfo := ConstructorSignatureRequired(nullableInt, typeof(int))
    parameterTypes := ConstructorSignatureOneType(typeof(int))

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1320, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_7())
    constructorIndex := plan.AddConstructorWithSignature(constructorInfo, nullableInt, parameterTypes)

    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)

    plan.CompleteFragment(root, nullableInt)
    plan.CompleteV3(nullableInt)
    return plan
}

func ConstructorSignatureBuilderPlan(): ColumnarCodePlan {
    builder := TypeOfCreateBuilder("ColumnarDeclaredConstructorProbe`1", "ColumnarDeclaredConstructorProbe", 1)

    builderType: Type = builder
    genericArguments := builderType.GetGenericArguments()
    if genericArguments.Length != 1 {
        throw new InvalidOperationException("Generic constructor probe did not declare one parameter.")
    }

    callingConventionsType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Reflection.CallingConventions")

    defineConstructorTypes := new Type[](3)
    defineConstructorTypes[0] = typeof(MethodAttributes)
    defineConstructorTypes[1] = callingConventionsType
    defineConstructorTypes[2] = typeof(Type[])
    defineConstructor := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineConstructor", defineConstructorTypes)

    definitionParameters := ConstructorSignatureOneType(genericArguments[0])
    defineArguments := new object[](3)
    ExecutorSetObject(defineArguments, 0, (MethodAttributes)6)
    ExecutorSetObject(defineArguments, 1, TypeOfRequiredStaticField(callingConventionsType, "Standard"))

    ExecutorSetObject(defineArguments, 2, definitionParameters)
    defined := TypeOfRequiredInvocation(defineConstructor, builder, defineArguments)

    constructorBuilder := defined as ConstructorInfo
    if constructorBuilder == null {
        throw new InvalidOperationException("Generic constructor probe did not return a constructor handle.")
    }

    closedArguments := ConstructorSignatureOneType(typeof(int))
    closedType := builderType.MakeGenericType(closedArguments)
    getConstructorTypes := new Type[](2)
    getConstructorTypes[0] = typeof(Type)
    getConstructorTypes[1] = typeof(ConstructorInfo)
    getConstructor := ExecutorRequiredMethod(typeof(TypeBuilder), "GetConstructor", getConstructorTypes)

    getArguments := new object[](2)
    ExecutorSetObject(getArguments, 0, closedType)
    ExecutorSetObject(getArguments, 1, constructorBuilder)
    rebound := TypeOfRequiredInvocation(getConstructor, null, getArguments)

    reboundConstructor := rebound as ConstructorInfo
    if reboundConstructor == null {
        throw new InvalidOperationException("Generic constructor probe did not return its rebound handle.")
    }

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1321, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_5())
    parameterTypes := ConstructorSignatureOneType(typeof(int))
    constructorIndex := plan.AddConstructorWithSignature(reboundConstructor, closedType, parameterTypes)

    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)

    plan.CompleteFragment(root, closedType)
    plan.CompleteV3(closedType)
    return plan
}

test "constructor signature facts are copied persisted and executable" {
    nullableInt := NullableArgumentType(typeof(int))
    plan := ConstructorSignatureNullablePlan()

    ColumnarCodePlanExecutor.Validate(plan)
    assert plan.ConstructorCount == 1
    assert plan.ConstructorUsesDeclaredSignature[0]
    assert plan.ConstructorDeclaringTypes[0] == nullableInt
    assert plan.ConstructorParameterTypes[0].Length == 1
    assert plan.ConstructorParameterTypes[0][0] == typeof(int)
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()

    result := NullableArgumentRunPlan(plan, nullableInt)
    assert result != null
    assert result.ToString() == "7"
}

test "constructor signature validation admits an unbaked rebound generic handle" {
    plan := ConstructorSignatureBuilderPlan()

    ColumnarCodePlanExecutor.Validate(plan)
    assert plan.ConstructorCount == 1
    assert plan.ConstructorUsesDeclaredSignature[0]
    assert plan.ConstructorDeclaringTypes[0].get_IsGenericType()
    assert plan.ConstructorParameterTypes[0][0] == typeof(int)
}

test "constructor signature API copies caller-owned parameter arrays" {
    nullableInt := NullableArgumentType(typeof(int))
    constructorInfo := ConstructorSignatureRequired(nullableInt, typeof(int))
    parameters := ConstructorSignatureOneType(typeof(int))

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1322, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_3())
    constructorIndex := plan.AddConstructorWithSignature(constructorInfo, nullableInt, parameters)

    parameters[0] = typeof(string)
    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)

    plan.CompleteFragment(root, nullableInt)
    plan.CompleteV3(nullableInt)

    assert plan.ConstructorParameterTypes[0][0] == typeof(int)
    ColumnarCodePlanExecutor.Validate(plan)
}

test "constructor signature checkpoint rollback restores every logical pool count" {
    nullableInt := NullableArgumentType(typeof(int))
    constructorInfo := ConstructorSignatureRequired(nullableInt, typeof(int))
    parameters := ConstructorSignatureOneType(typeof(int))

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1323, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    checkpoint := plan.CreateCheckpoint()
    discarded := plan.AddConstructorWithSignature(constructorInfo, nullableInt, parameters)

    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), discarded)

    plan.Rollback(checkpoint)

    assert plan.ConstructorCount == 0
    assert plan.OperationCount == 1
    retained := plan.AddConstructorWithSignature(constructorInfo, nullableInt, parameters)

    assert retained == 0
    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), retained)

    plan.CompleteFragment(root, nullableInt)
    plan.CompleteV3(nullableInt)
    ColumnarCodePlanExecutor.Validate(plan)
}

test "constructor signature columns grow without losing declared facts" {
    nullableInt := NullableArgumentType(typeof(int))
    constructorInfo := ConstructorSignatureRequired(nullableInt, typeof(int))
    plan := new ColumnarCodePlan()
    plan.PrepareV3()

    index := 0
    while index < 19 {
        parameters := ConstructorSignatureOneType(typeof(int))
        added := plan.AddConstructorWithSignature(constructorInfo, nullableInt, parameters)

        assert added == index
        index += 1
    }

    assert plan.ConstructorCount == 19
    assert plan.Constructors.Length >= 19
    assert plan.ConstructorUsesDeclaredSignature.Length >= 19
    assert plan.ConstructorDeclaringTypes.Length >= 19
    assert plan.ConstructorParameterTypes.Length >= 19
    assert plan.ConstructorUsesDeclaredSignature[18]
    assert plan.ConstructorDeclaringTypes[18] == nullableInt
    assert plan.ConstructorParameterTypes[18][0] == typeof(int)
}

test "constructor signature validation rejects corrupt persisted facts" {
    missingColumns := ConstructorSignatureNullablePlan()
    missingColumns.ConstructorParameterTypes = null
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(missingColumns)
    }

    wrongOwner := ConstructorSignatureNullablePlan()
    wrongOwner.ConstructorDeclaringTypes[0] = typeof(string)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongOwner)
    }

    wrongParameter := ConstructorSignatureNullablePlan()
    wrongParameter.ConstructorParameterTypes[0][0] = typeof(string)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongParameter)
    }

    wrongHandle := ConstructorSignatureNullablePlan()
    nullableLong := NullableArgumentType(typeof(long))
    wrongHandle.Constructors[0] = ConstructorSignatureRequired(nullableLong, typeof(long))

    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongHandle)
    }
}

namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

func NullableArgumentType(elementType: Type): Type {
    definition := Type.GetType("System.Nullable`1")
    if definition == null {
        throw new InvalidOperationException("System.Nullable<T> runtime type was not found.")
    }

    arguments := new Type[](1)
    arguments[0] = elementType
    return definition.MakeGenericType(arguments)
}

func NullableArgumentNullPlan(targetType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1300, 0)
    if !ColumnarNullableArgumentLowering.TryAppendNullArgument(plan, root, 1301, 1, targetType) {
        throw new InvalidOperationException("The expected target-typed null argument was rejected.")
    }

    // A production call contributes a parent-owned call row after this argument fragment. Store
    // and reload here so the standalone execution fixture has the same strict child interval.
    targetIndex := plan.AddType(targetType)
    passthrough := plan.DeclarePlanLocal(targetIndex)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), passthrough)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), passthrough)

    plan.CompleteFragment(root, targetType)
    plan.CompleteV3(targetType)
    return plan
}

func NullableArgumentLiftPlan(actualType: Type, targetType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1302, 0)
    child := plan.BeginFragment(root, 1303, 1)
    if actualType == typeof(int) {
        valueIndex := plan.AddInt32(17)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
    } else if actualType == typeof(long) {
        valueIndex := plan.AddInt64((long)17)
        plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
    } else if actualType == typeof(float) {
        valueIndex := plan.AddSingle((float)17)
        plan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR4(), valueIndex)
    } else {
        throw new InvalidOperationException("The nullable argument test requested an unsupported source value.")
    }

    plan.CompleteFragment(child, actualType)
    if !ColumnarNullableArgumentLowering.TryAppendValueLift(plan, actualType, targetType) {
        throw new InvalidOperationException("The expected nullable value lift was rejected.")
    }

    plan.CompleteFragment(root, targetType)
    plan.CompleteV3(targetType)
    return plan
}

func NullableArgumentSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func NullableArgumentRunPlan(plan: ColumnarCodePlan, resultType: Type): object? {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if constructorInfo == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }

    constructorArguments := new object[](3)
    NullableArgumentSetObject(constructorArguments, 0, "NSharpNullableArgumentPlan")

    NullableArgumentSetObject(constructorArguments, 1, resultType)
    NullableArgumentSetObject(constructorArguments, 2, new Type[](0))
    dynamicMethod := (DynamicMethod)constructorInfo.Invoke(constructorArguments)
    il := dynamicMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    il.Emit(OpCodes.Ret)

    target: object? = null
    return dynamicMethod.Invoke(target, new object[](0))
}

test "nullable argument lowering classifies only supported target flows" {
    nullableInt := NullableArgumentType(typeof(int))
    nullableLong := NullableArgumentType(typeof(long))
    nullableDateTime := NullableArgumentType(typeof(DateTime))
    tupleType := typeof(ValueTuple<int, string>)
    nullableTuple := NullableArgumentType(tupleType)
    element := typeof(bool)

    assert ColumnarNullableArgumentLowering.CanAdoptNull(typeof(string))
    assert ColumnarNullableArgumentLowering.CanAdoptNull(nullableInt)
    assert !ColumnarNullableArgumentLowering.CanAdoptNull(typeof(int))
    assert !ColumnarNullableArgumentLowering.CanAdoptNull(nullableDateTime)
    assert ColumnarNullableArgumentLowering.CanAdoptNull(nullableTuple)
    assert ColumnarNullableArgumentLowering.TryGetSupportedNullableElement(nullableInt, out element)

    assert element == typeof(int)
    assert ColumnarNullableArgumentLowering.CanLiftValue(nullableInt, nullableInt)

    assert ColumnarNullableArgumentLowering.CanLiftValue(typeof(int), nullableInt)

    assert ColumnarNullableArgumentLowering.CanLiftValue(typeof(int), nullableLong)

    assert !ColumnarNullableArgumentLowering.CanLiftValue(nullableInt, nullableLong)

    assert !ColumnarNullableArgumentLowering.CanLiftValue(typeof(string), nullableInt)
    assert ColumnarNullableArgumentLowering.CanLiftValue(tupleType, nullableTuple)
}

test "reference null uses one exact schema v3 row and executes as null" {
    plan := NullableArgumentNullPlan(typeof(string))

    ColumnarCodePlanExecutor.Validate(plan)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldnull()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.NoOperand()
    assert plan.OperandIndices[0] == -1
    assert plan.FragmentCount == 2
    assert plan.FragmentResultTypes[1] == typeof(string)
    assert NullableArgumentRunPlan(plan, typeof(string)) == null
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
}

test "reference null merges only with reference stack values" {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1309, 0)
    falseLabel := plan.DefineLabel()
    endLabel := plan.DefineLabel()
    textIndex := plan.AddString("value")
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)
    plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), textIndex)
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
    plan.AppendMarkLabel(falseLabel)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
    plan.AppendMarkLabel(endLabel)
    plan.CompleteFragment(root, typeof(string))
    plan.CompleteV3(typeof(string))

    ColumnarCodePlanExecutor.Validate(plan)
    result := NullableArgumentRunPlan(plan, typeof(string))
    assert result != null
    assert result.ToString() == "value"

    valuePlan := new ColumnarCodePlan()
    valuePlan.PrepareV3()
    valueRoot := valuePlan.BeginFragment(-1, 1310, 0)
    valuePlan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
    valuePlan.CompleteFragment(valueRoot, typeof(int))
    valuePlan.CompleteV3(typeof(int))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(valuePlan)
    }
}

test "nullable null uses exact initobj local rows and executes as default" {
    nullableInt := NullableArgumentType(typeof(int))
    plan := NullableArgumentNullPlan(nullableInt)
    nullableTuple := NullableArgumentType(typeof(ValueTuple<int, string>))
    tuplePlan := NullableArgumentNullPlan(nullableTuple)

    ColumnarCodePlanExecutor.Validate(plan)
    assert plan.OperationCount == 5
    assert plan.TypeCount == 2
    assert plan.Types[0] == nullableInt
    assert plan.PlanLocalCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloca()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.PlanLocalOperand()

    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Initobj()
    assert plan.OperandKinds[1] == ColumnarCodePlanContract.TypeOperand()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert NullableArgumentRunPlan(plan, nullableInt) == null
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
    ColumnarCodePlanExecutor.Validate(tuplePlan)
    assert NullableArgumentRunPlan(tuplePlan, nullableTuple) == null
}

test "nullable identity element and numeric lifts persist exact constructor shapes" {
    nullableInt := NullableArgumentType(typeof(int))
    nullableLong := NullableArgumentType(typeof(long))
    nullableDouble := NullableArgumentType(typeof(double))
    nullableDecimal := NullableArgumentType(typeof(decimal))
    identity := NullableArgumentLiftPlan(typeof(int), nullableInt)
    numeric := NullableArgumentLiftPlan(typeof(int), nullableLong)
    longToDouble := NullableArgumentLiftPlan(typeof(long), nullableDouble)
    intToDecimal := NullableArgumentLiftPlan(typeof(int), nullableDecimal)

    ColumnarCodePlanExecutor.Validate(identity)
    ColumnarCodePlanExecutor.Validate(numeric)
    ColumnarCodePlanExecutor.Validate(longToDouble)
    ColumnarCodePlanExecutor.Validate(intToDecimal)
    assert identity.OperationCount == 2
    assert identity.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert identity.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
    assert identity.ConstructorCount == 1
    assert identity.Constructors[0].get_DeclaringType() == nullableInt
    assert numeric.OperationCount == 3
    assert numeric.OpCodeValues[1] == ColumnarCodePlanContract.ConvI8()
    assert numeric.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert numeric.Constructors[0].get_DeclaringType() == nullableLong
    assert longToDouble.OpCodeValues[1] == ColumnarCodePlanContract.ConvR8()
    assert longToDouble.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert intToDecimal.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert intToDecimal.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()

    identityResult := NullableArgumentRunPlan(identity, nullableInt)
    numericResult := NullableArgumentRunPlan(numeric, nullableLong)
    doubleResult := NullableArgumentRunPlan(longToDouble, nullableDouble)
    decimalResult := NullableArgumentRunPlan(intToDecimal, nullableDecimal)
    assert identityResult != null
    assert identityResult.ToString() == "17"
    assert numericResult != null
    assert numericResult.ToString() == "17"
    assert doubleResult != null
    assert doubleResult.ToString() == "17"
    assert decimalResult != null
    assert decimalResult.ToString() == "17"
}

test "nullable lowering rejects semantic misses without mutating its open plan" {
    nullableInt := NullableArgumentType(typeof(int))
    nullableLong := NullableArgumentType(typeof(long))
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1304, 0)
    operationCount := plan.OperationCount
    typeCount := plan.TypeCount
    constructorCount := plan.ConstructorCount
    fragmentCount := plan.FragmentCount

    assert throws InvalidOperationException {
        ColumnarNullableArgumentLowering.TryAppendNullArgument(plan, -1, 1305, 1, typeof(string))
    }

    assert !ColumnarNullableArgumentLowering.TryAppendNullArgument(plan, root, 1305, 1, typeof(int))

    assert !ColumnarNullableArgumentLowering.TryAppendValueLift(plan, typeof(string), nullableInt)

    assert !ColumnarNullableArgumentLowering.TryAppendValueLift(plan, nullableInt, nullableLong)

    assert plan.OperationCount == operationCount
    assert plan.TypeCount == typeCount
    assert plan.ConstructorCount == constructorCount
    assert plan.FragmentCount == fragmentCount
}

test "schema v3 rejects corrupt null and initobj rows before emission" {
    badNull := NullableArgumentNullPlan(typeof(string))
    badNull.OperandKinds[0] = ColumnarCodePlanContract.Int32Operand()
    badNull.OperandIndices[0] = 0
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(badNull)
    }

    nullableInt := NullableArgumentType(typeof(int))
    wrongAddress := new ColumnarCodePlan()
    wrongAddress.PrepareV3()
    wrongRoot := wrongAddress.BeginFragment(-1, 1306, 0)
    nullableIndex := wrongAddress.AddType(nullableInt)
    intIndex := wrongAddress.AddType(typeof(int))
    localIndex := wrongAddress.DeclarePlanLocal(nullableIndex)
    wrongAddress.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)

    wrongAddress.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), intIndex)

    wrongAddress.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)

    wrongAddress.CompleteFragment(wrongRoot, nullableInt)
    wrongAddress.CompleteV3(nullableInt)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongAddress)
    }

    noAddress := new ColumnarCodePlan()
    noAddress.PrepareV3()
    noAddressRoot := noAddress.BeginFragment(-1, 1307, 0)
    noAddressType := noAddress.AddType(nullableInt)
    noAddress.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())

    noAddress.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), noAddressType)

    noAddress.CompleteFragment(noAddressRoot, nullableInt)
    noAddress.CompleteV3(nullableInt)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(noAddress)
    }
}

test "ldnull and initobj are schema v3 only and rejected appends are atomic" {
    assert ColumnarCodePlanContract.Ldnull() == 20
    assert ColumnarCodePlanContract.Initobj() == -491
    assert ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Ldnull").IsSupported

    assert ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Initobj").IsSupported

    v2 := new ColumnarCodePlan()
    v2.PrepareV2()
    v2.BeginFragment(-1, 1308, 0)
    assert throws InvalidOperationException {
        v2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
    }

    assert v2.OperationCount == 0
    typeIndex := v2.AddType(typeof(int))
    assert throws InvalidOperationException {
        v2.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), typeIndex)
    }

    assert v2.OperationCount == 0
}

namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Runtime.CompilerServices

enum ColumnarExecutorProbeEnum {
    Zero = 0,
    One = 1
}

public class ColumnarExecutorProbeMethods {
    public static func IdentityBool(value: bool): bool { return value }
    public static func IdentityByte(value: byte): byte { return value }
    public static func IdentityInt(value: int): int { return value }
    public static func IdentityLong(value: long): long { return value }
    public static func Nothing() {}
}

func ExecutorRequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameters)
    if method == null {
        throw new InvalidOperationException("Required executor probe method was not found: " + name)
    }
    return method
}

func ExecutorRequiredConstructor(owner: Type, parameters: Type[]): ConstructorInfo {
    constructorInfo := owner.GetConstructor(parameters)
    if constructorInfo == null {
        throw new InvalidOperationException("Required executor probe constructor was not found.")
    }
    return constructorInfo
}

func ExecutorRequiredField(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("Required executor probe field was not found: " + name)
    }
    return field
}

func ExecutorOpenGenericParameter(): Type {
    definition := typeof(System.Array).GetMethod("Empty")
    if definition == null {
        throw new InvalidOperationException("Required generic parameter probe was not found.")
    }
    parameterType := definition.get_ReturnType().GetElementType()
    if parameterType == null {
        throw new InvalidOperationException("Required generic parameter type was not found.")
    }
    return parameterType
}

func ExecutorConstantPlan(resultType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1000, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.CompleteFragment(root, resultType)
    plan.CompleteV2(resultType)
    return plan
}

func ExecutorConditionalPlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1001, 0)
    falseLabel := plan.DefineLabel()
    endLabel := plan.DefineLabel()

    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
    plan.AppendMarkLabel(falseLabel)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_3())
    plan.AppendMarkLabel(endLabel)

    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    return plan
}

func ExecutorIntArrayPlan(opCodeValue: short): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1002, 0)
    arrayType := plan.AddType(typeof(int[]))
    argument := plan.AddArgument(0, arrayType)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    plan.AppendInstructionWithoutOperand(opCodeValue)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    return plan
}

func ExecutorStaticIntCallPlan(argumentTypeValue: Type, method: MethodInfo): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1003, 0)
    argumentType := plan.AddType(argumentTypeValue)
    argument := plan.AddArgument(0, argumentType)
    methodIndex := plan.AddMethod(method)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    plan.CompleteFragment(root, method.get_ReturnType())
    plan.CompleteV2(method.get_ReturnType())
    return plan
}

test "schema v2 executor accepts exact literal fragment categories without erasing loaded types" {
    intPlan := ExecutorConstantPlan(typeof(int))
    boolPlan := ExecutorConstantPlan(typeof(bool))
    uintPlan := ExecutorConstantPlan(typeof(uint))
    enumPlan := ExecutorConstantPlan(typeof(ColumnarExecutorProbeEnum))

    ColumnarCodePlanExecutor.Validate(intPlan)
    ColumnarCodePlanExecutor.Validate(boolPlan)
    ColumnarCodePlanExecutor.Validate(uintPlan)
    ColumnarCodePlanExecutor.Validate(enumPlan)
    assert intPlan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    assert boolPlan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
}

test "schema v2 executor range-checks literal adaptation" {
    badBool := new ColumnarCodePlan()
    badBool.PrepareV2()
    boolRoot := badBool.BeginFragment(-1, 1009, 0)
    fortyTwo := badBool.AddInt32(42)
    badBool.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), fortyTwo)
    badBool.CompleteFragment(boolRoot, typeof(bool))
    badBool.CompleteV2(typeof(bool))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badBool) }

    badByte := new ColumnarCodePlan()
    badByte.PrepareV2()
    byteRoot := badByte.BeginFragment(-1, 1014, 0)
    threeHundred := badByte.AddInt32(300)
    badByte.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), threeHundred)
    badByte.CompleteFragment(byteRoot, typeof(byte))
    badByte.CompleteV2(typeof(byte))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badByte) }

    validByte := new ColumnarCodePlan()
    validByte.PrepareV2()
    validByteRoot := validByte.BeginFragment(-1, 1015, 0)
    twoFiftyFive := validByte.AddInt32(255)
    validByte.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), twoFiftyFive)
    validByte.CompleteFragment(validByteRoot, typeof(byte))
    validByte.CompleteV2(typeof(byte))
    ColumnarCodePlanExecutor.Validate(validByte)

    badChar := new ColumnarCodePlan()
    badChar.PrepareV2()
    charRoot := badChar.BeginFragment(-1, 1016, 0)
    minusOne := badChar.AddInt32(-1)
    badChar.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), minusOne)
    badChar.CompleteFragment(charRoot, typeof(char))
    badChar.CompleteV2(typeof(char))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badChar) }

    oneByte := new Type[](1)
    oneByte[0] = typeof(byte)
    identityByte := ExecutorRequiredMethod(
        typeof(ColumnarExecutorProbeMethods),
        "IdentityByte",
        oneByte)
    badByteCall := new ColumnarCodePlan()
    badByteCall.PrepareV2()
    badByteCallRoot := badByteCall.BeginFragment(-1, 1018, 0)
    badByteValue := badByteCall.AddInt32(300)
    badByteMethod := badByteCall.AddMethod(identityByte)
    badByteCall.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), badByteValue)
    badByteCall.AppendMethodInstruction(ColumnarCodePlanContract.Call(), badByteMethod)
    badByteCall.CompleteFragment(badByteCallRoot, typeof(byte))
    badByteCall.CompleteV2(typeof(byte))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badByteCall) }
}

test "schema v2 executor validates a reachable forward conditional with equal stack merges" {
    plan := ExecutorConditionalPlan()
    ColumnarCodePlanExecutor.Validate(plan)
    assert plan.LabelCount == 2
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
}

test "schema v2 executor validates a long linear stream without boundary-sized stack copies" {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1017, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    i := 0
    while i < 8192 {
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        i += 1
    }
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(plan)
    assert plan.OperationCount == 8193
}

test "schema v2 executor accepts exact array element and length semantics" {
    typed := ExecutorIntArrayPlan(ColumnarCodePlanContract.LdelemI4())
    ColumnarCodePlanExecutor.Validate(typed)

    general := new ColumnarCodePlan()
    general.PrepareV2()
    root := general.BeginFragment(-1, 1004, 0)
    arrayType := general.AddType(typeof(int[]))
    elementType := general.AddType(typeof(int))
    argument := general.AddArgument(0, arrayType)
    general.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    general.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    general.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), elementType)
    general.CompleteFragment(root, typeof(int))
    general.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(general)

    length := new ColumnarCodePlan()
    length.PrepareV2()
    lengthRoot := length.BeginFragment(-1, 1005, 0)
    lengthArrayType := length.AddType(typeof(int[]))
    lengthArgument := length.AddArgument(0, lengthArrayType)
    length.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), lengthArgument)
    length.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldlen())
    length.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    length.CompleteFragment(lengthRoot, typeof(int))
    length.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(length)
}

test "schema v2 executor accepts exact static reference and value receiver calls" {
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    abs := ExecutorRequiredMethod(typeof(ColumnarExecutorProbeMethods), "IdentityInt", oneInt)
    staticCall := ExecutorStaticIntCallPlan(typeof(int), abs)
    ColumnarCodePlanExecutor.Validate(staticCall)

    noTypes := new Type[](0)
    stringLength := ExecutorRequiredMethod(typeof(string), "get_Length", noTypes)
    instanceCall := new ColumnarCodePlan()
    instanceCall.PrepareV2()
    instanceRoot := instanceCall.BeginFragment(-1, 1006, 0)
    stringType := instanceCall.AddType(typeof(string))
    stringArgument := instanceCall.AddArgument(0, stringType)
    lengthMethod := instanceCall.AddMethod(stringLength)
    instanceCall.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), stringArgument)
    instanceCall.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), lengthMethod)
    instanceCall.CompleteFragment(instanceRoot, typeof(int))
    instanceCall.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(instanceCall)

    indexCtorTypes := new Type[](2)
    indexCtorTypes[0] = typeof(int)
    indexCtorTypes[1] = typeof(bool)
    indexCtor := ExecutorRequiredConstructor(typeof(Index), indexCtorTypes)
    indexMethod := ExecutorRequiredMethod(typeof(Index), "GetOffset", oneInt)
    valueCall := new ColumnarCodePlan()
    valueCall.PrepareV2()
    valueRoot := valueCall.BeginFragment(-1, 1007, 0)
    indexType := valueCall.AddType(typeof(Index))
    indexLocal := valueCall.DeclarePlanLocal(indexType)
    ctorIndex := valueCall.AddConstructor(indexCtor)
    methodIndex := valueCall.AddMethod(indexMethod)
    valueCall.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    valueCall.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    valueCall.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), ctorIndex)
    valueCall.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), indexLocal)
    valueCall.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), indexLocal)
    valueCall.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_8())
    valueCall.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    valueCall.CompleteFragment(valueRoot, typeof(int))
    valueCall.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(valueCall)
}

test "schema v2 executor accepts exact newobj local and field semantics" {
    tupleType := typeof(ValueTuple<int, int>)
    twoInts := new Type[](2)
    twoInts[0] = typeof(int)
    twoInts[1] = typeof(int)
    tupleCtor := ExecutorRequiredConstructor(tupleType, twoInts)
    item1 := ExecutorRequiredField(tupleType, "Item1")

    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1008, 0)
    tupleTypeIndex := plan.AddType(tupleType)
    tupleLocal := plan.DeclarePlanLocal(tupleTypeIndex)
    constructorIndex := plan.AddConstructor(tupleCtor)
    fieldIndex := plan.AddField(item1)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), tupleLocal)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), tupleLocal)
    plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(plan)
}

test "schema v2 executor rejects hidden unused value and handle pools" {
    unusedType := new ColumnarCodePlan()
    unusedType.PrepareV2()
    typeRoot := unusedType.BeginFragment(-1, 1010, 0)
    unusedType.AddType(typeof(string))
    unusedType.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    unusedType.CompleteFragment(typeRoot, typeof(int))
    unusedType.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedType) }

    unusedInt := new ColumnarCodePlan()
    unusedInt.PrepareV2()
    intRoot := unusedInt.BeginFragment(-1, 1011, 0)
    unusedInt.AddInt32(42)
    unusedInt.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    unusedInt.CompleteFragment(intRoot, typeof(int))
    unusedInt.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedInt) }

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    abs := ExecutorRequiredMethod(typeof(ColumnarExecutorProbeMethods), "IdentityInt", oneInt)
    unusedMethod := new ColumnarCodePlan()
    unusedMethod.PrepareV2()
    methodRoot := unusedMethod.BeginFragment(-1, 1012, 0)
    unusedMethod.AddMethod(abs)
    unusedMethod.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    unusedMethod.CompleteFragment(methodRoot, typeof(int))
    unusedMethod.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedMethod) }

    unusedLocal := new ColumnarCodePlan()
    unusedLocal.PrepareV2()
    localRoot := unusedLocal.BeginFragment(-1, 1013, 0)
    localType := unusedLocal.AddType(typeof(int))
    unusedLocal.DeclarePlanLocal(localType)
    unusedLocal.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    unusedLocal.CompleteFragment(localRoot, typeof(int))
    unusedLocal.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedLocal) }
}

test "schema v2 executor rejects exact bool uint int and long ulong confusion" {
    boolIntoIntLocal := new ColumnarCodePlan()
    boolIntoIntLocal.PrepareV2()
    boolRoot := boolIntoIntLocal.BeginFragment(-1, 1020, 0)
    boolType := boolIntoIntLocal.AddType(typeof(bool))
    intType := boolIntoIntLocal.AddType(typeof(int))
    boolArgument := boolIntoIntLocal.AddArgument(0, boolType)
    intLocal := boolIntoIntLocal.DeclarePlanLocal(intType)
    boolIntoIntLocal.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), boolArgument)
    boolIntoIntLocal.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), intLocal)
    boolIntoIntLocal.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), intLocal)
    boolIntoIntLocal.CompleteFragment(boolRoot, typeof(int))
    boolIntoIntLocal.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(boolIntoIntLocal) }

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    absInt := ExecutorRequiredMethod(typeof(ColumnarExecutorProbeMethods), "IdentityInt", oneInt)
    uintIntoIntCall := ExecutorStaticIntCallPlan(typeof(uint), absInt)
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(uintIntoIntCall) }

    oneLong := new Type[](1)
    oneLong[0] = typeof(long)
    absLong := ExecutorRequiredMethod(typeof(ColumnarExecutorProbeMethods), "IdentityLong", oneLong)
    ulongIntoLongCall := ExecutorStaticIntCallPlan(typeof(ulong), absLong)
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(ulongIntoLongCall) }
}

test "schema v2 executor rejects exact bool and uint as array indexes or conditions" {
    badIndex := new ColumnarCodePlan()
    badIndex.PrepareV2()
    indexRoot := badIndex.BeginFragment(-1, 1021, 0)
    arrayType := badIndex.AddType(typeof(int[]))
    boolType := badIndex.AddType(typeof(bool))
    arrayArgument := badIndex.AddArgument(0, arrayType)
    boolArgument := badIndex.AddArgument(1, boolType)
    badIndex.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), arrayArgument)
    badIndex.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), boolArgument)
    badIndex.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI4())
    badIndex.CompleteFragment(indexRoot, typeof(int))
    badIndex.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badIndex) }

    badCondition := new ColumnarCodePlan()
    badCondition.PrepareV2()
    conditionRoot := badCondition.BeginFragment(-1, 1022, 0)
    uintType := badCondition.AddType(typeof(uint))
    uintArgument := badCondition.AddArgument(0, uintType)
    label := badCondition.DefineLabel()
    badCondition.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), uintArgument)
    badCondition.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), label)
    badCondition.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    badCondition.AppendLabelInstruction(ColumnarCodePlanContract.Br(), label)
    badCondition.AppendMarkLabel(label)
    badCondition.CompleteFragment(conditionRoot, typeof(int))
    badCondition.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badCondition) }
}

test "schema v2 executor rejects duplicate unreferenced backward and cross-owner labels" {
    duplicate := new ColumnarCodePlan()
    duplicate.PrepareV2()
    duplicateRoot := duplicate.BeginFragment(-1, 1030, 0)
    duplicateLabel := duplicate.DefineLabel()
    duplicate.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    duplicate.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), duplicateLabel)
    duplicate.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    duplicate.AppendMarkLabel(duplicateLabel)
    duplicate.AppendMarkLabel(duplicateLabel)
    duplicate.CompleteFragment(duplicateRoot, typeof(int))
    duplicate.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(duplicate) }

    unreferenced := new ColumnarCodePlan()
    unreferenced.PrepareV2()
    unreferencedRoot := unreferenced.BeginFragment(-1, 1031, 0)
    unreferenced.DefineLabel()
    unreferenced.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unreferenced.CompleteFragment(unreferencedRoot, typeof(int))
    unreferenced.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unreferenced) }

    backward := new ColumnarCodePlan()
    backward.PrepareV2()
    backwardRoot := backward.BeginFragment(-1, 1032, 0)
    backwardLabel := backward.DefineLabel()
    backward.AppendMarkLabel(backwardLabel)
    backward.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    backward.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), backwardLabel)
    backward.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    backward.CompleteFragment(backwardRoot, typeof(int))
    backward.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(backward) }

    crossOwner := new ColumnarCodePlan()
    crossOwner.PrepareV2()
    ownerRoot := crossOwner.BeginFragment(-1, 1033, 0)
    ownerLabel := crossOwner.DefineLabel()
    child := crossOwner.BeginFragment(ownerRoot, 1034, 1)
    crossOwner.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    crossOwner.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), ownerLabel)
    crossOwner.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    crossOwner.CompleteFragment(child, typeof(int))
    crossOwner.AppendMarkLabel(ownerLabel)
    crossOwner.CompleteFragment(ownerRoot, typeof(int))
    crossOwner.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(crossOwner) }
}

test "schema v2 executor rejects unreachable rows and incompatible control flow merges" {
    unreachable := new ColumnarCodePlan()
    unreachable.PrepareV2()
    unreachableRoot := unreachable.BeginFragment(-1, 1040, 0)
    target := unreachable.DefineLabel()
    unreachable.AppendLabelInstruction(ColumnarCodePlanContract.Br(), target)
    unreachable.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unreachable.AppendMarkLabel(target)
    unreachable.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    unreachable.CompleteFragment(unreachableRoot, typeof(int))
    unreachable.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unreachable) }

    depthMismatch := new ColumnarCodePlan()
    depthMismatch.PrepareV2()
    depthRoot := depthMismatch.BeginFragment(-1, 1041, 0)
    falseLabel := depthMismatch.DefineLabel()
    endLabel := depthMismatch.DefineLabel()
    depthMismatch.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    depthMismatch.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)
    depthMismatch.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    depthMismatch.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
    depthMismatch.AppendMarkLabel(falseLabel)
    depthMismatch.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    depthMismatch.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_3())
    depthMismatch.AppendMarkLabel(endLabel)
    depthMismatch.CompleteFragment(depthRoot, typeof(int))
    depthMismatch.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(depthMismatch) }

    typeMismatch := new ColumnarCodePlan()
    typeMismatch.PrepareV2()
    typeRoot := typeMismatch.BeginFragment(-1, 1042, 0)
    conditionType := typeMismatch.AddType(typeof(bool))
    valueBoolType := typeMismatch.AddType(typeof(bool))
    valueIntType := typeMismatch.AddType(typeof(int))
    conditionArgument := typeMismatch.AddArgument(0, conditionType)
    boolArgument := typeMismatch.AddArgument(1, valueBoolType)
    intArgument := typeMismatch.AddArgument(2, valueIntType)
    typeFalse := typeMismatch.DefineLabel()
    typeEnd := typeMismatch.DefineLabel()
    typeMismatch.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), conditionArgument)
    typeMismatch.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), typeFalse)
    typeMismatch.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), boolArgument)
    typeMismatch.AppendLabelInstruction(ColumnarCodePlanContract.Br(), typeEnd)
    typeMismatch.AppendMarkLabel(typeFalse)
    typeMismatch.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), intArgument)
    typeMismatch.AppendMarkLabel(typeEnd)
    typeMismatch.CompleteFragment(typeRoot, typeof(int))
    typeMismatch.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(typeMismatch) }
}

test "schema v2 executor validates every nested fragment result independently" {
    nested := new ColumnarCodePlan()
    nested.PrepareV2()
    nestedRoot := nested.BeginFragment(-1, 1050, 0)
    nestedChild := nested.BeginFragment(nestedRoot, 1051, 1)
    nested.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    nested.CompleteFragment(nestedChild, typeof(int))
    nested.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    nested.CompleteFragment(nestedRoot, typeof(int))
    nested.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(nested)

    wrongResult := ExecutorConstantPlan(typeof(string))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(wrongResult) }

    twoResults := new ColumnarCodePlan()
    twoResults.PrepareV2()
    twoRoot := twoResults.BeginFragment(-1, 1052, 0)
    intType := twoResults.AddType(typeof(int))
    temporary := twoResults.DeclarePlanLocal(intType)
    twoChild := twoResults.BeginFragment(twoRoot, 1053, 1)
    twoResults.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    twoResults.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    twoResults.CompleteFragment(twoChild, typeof(int))
    twoResults.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), temporary)
    twoResults.CompleteFragment(twoRoot, typeof(int))
    twoResults.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(twoResults) }
}

test "schema v2 executor refines child literals to their declared semantic type" {
    oneBool := new Type[](1)
    oneBool[0] = typeof(bool)
    identityBool := ExecutorRequiredMethod(
        typeof(ColumnarExecutorProbeMethods),
        "IdentityBool",
        oneBool)

    valid := new ColumnarCodePlan()
    valid.PrepareV2()
    validRoot := valid.BeginFragment(-1, 1054, 0)
    validChild := valid.BeginFragment(validRoot, 1055, 1)
    valid.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    valid.CompleteFragment(validChild, typeof(bool))
    validMethod := valid.AddMethod(identityBool)
    valid.AppendMethodInstruction(ColumnarCodePlanContract.Call(), validMethod)
    valid.CompleteFragment(validRoot, typeof(bool))
    valid.CompleteV2(typeof(bool))
    ColumnarCodePlanExecutor.Validate(valid)

    invalid := new ColumnarCodePlan()
    invalid.PrepareV2()
    invalidRoot := invalid.BeginFragment(-1, 1056, 0)
    invalidChild := invalid.BeginFragment(invalidRoot, 1057, 1)
    invalid.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    invalid.CompleteFragment(invalidChild, typeof(int))
    invalidMethod := invalid.AddMethod(identityBool)
    invalid.AppendMethodInstruction(ColumnarCodePlanContract.Call(), invalidMethod)
    invalid.CompleteFragment(invalidRoot, typeof(bool))
    invalid.CompleteV2(typeof(bool))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(invalid) }

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    identityInt := ExecutorRequiredMethod(
        typeof(ColumnarExecutorProbeMethods),
        "IdentityInt",
        oneInt)
    boolIntoInt := new ColumnarCodePlan()
    boolIntoInt.PrepareV2()
    boolIntoIntRoot := boolIntoInt.BeginFragment(-1, 1058, 0)
    boolIntoIntChild := boolIntoInt.BeginFragment(boolIntoIntRoot, 1059, 1)
    boolIntoInt.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    boolIntoInt.CompleteFragment(boolIntoIntChild, typeof(bool))
    identityIntIndex := boolIntoInt.AddMethod(identityInt)
    boolIntoInt.AppendMethodInstruction(ColumnarCodePlanContract.Call(), identityIntIndex)
    boolIntoInt.CompleteFragment(boolIntoIntRoot, typeof(int))
    boolIntoInt.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(boolIntoInt) }

    intCondition := new ColumnarCodePlan()
    intCondition.PrepareV2()
    conditionRoot := intCondition.BeginFragment(-1, 1063, 0)
    falseLabel := intCondition.DefineLabel()
    endLabel := intCondition.DefineLabel()
    conditionChild := intCondition.BeginFragment(conditionRoot, 1064, 1)
    intCondition.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    intCondition.CompleteFragment(conditionChild, typeof(int))
    intCondition.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)
    intCondition.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    intCondition.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
    intCondition.AppendMarkLabel(falseLabel)
    intCondition.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_3())
    intCondition.AppendMarkLabel(endLabel)
    intCondition.CompleteFragment(conditionRoot, typeof(int))
    intCondition.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(intCondition) }

    enumConversion := new ColumnarCodePlan()
    enumConversion.PrepareV2()
    enumRoot := enumConversion.BeginFragment(-1, 1065, 0)
    enumChild := enumConversion.BeginFragment(enumRoot, 1066, 1)
    enumConversion.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    enumConversion.CompleteFragment(enumChild, typeof(ColumnarExecutorProbeEnum))
    enumConversion.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
    enumConversion.CompleteFragment(enumRoot, typeof(int))
    enumConversion.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(enumConversion)
}

test "schema v2 executor rejects array opcode type and native length mismatches" {
    wrongTypedOpcode := ExecutorIntArrayPlan(ColumnarCodePlanContract.LdelemRef())
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(wrongTypedOpcode) }

    wrongGeneralType := new ColumnarCodePlan()
    wrongGeneralType.PrepareV2()
    generalRoot := wrongGeneralType.BeginFragment(-1, 1060, 0)
    arrayType := wrongGeneralType.AddType(typeof(int[]))
    requestedType := wrongGeneralType.AddType(typeof(uint))
    argument := wrongGeneralType.AddArgument(0, arrayType)
    wrongGeneralType.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    wrongGeneralType.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    wrongGeneralType.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), requestedType)
    wrongGeneralType.CompleteFragment(generalRoot, typeof(uint))
    wrongGeneralType.CompleteV2(typeof(uint))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(wrongGeneralType) }

    nativeLength := new ColumnarCodePlan()
    nativeLength.PrepareV2()
    nativeRoot := nativeLength.BeginFragment(-1, 1061, 0)
    nativeArrayType := nativeLength.AddType(typeof(int[]))
    nativeArgument := nativeLength.AddArgument(0, nativeArrayType)
    nativeLength.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), nativeArgument)
    nativeLength.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldlen())
    nativeLength.CompleteFragment(nativeRoot, typeof(int))
    nativeLength.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(nativeLength) }

    nonArray := new ColumnarCodePlan()
    nonArray.PrepareV2()
    nonArrayRoot := nonArray.BeginFragment(-1, 1062, 0)
    intType := nonArray.AddType(typeof(int))
    intArgument := nonArray.AddArgument(0, intType)
    nonArray.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), intArgument)
    nonArray.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldlen())
    nonArray.CompleteFragment(nonArrayRoot, typeof(int))
    nonArray.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(nonArray) }
}

test "schema v2 executor rejects static callvirt bad receivers and constructor arguments" {
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    identity := ExecutorRequiredMethod(
        typeof(ColumnarExecutorProbeMethods),
        "IdentityInt",
        oneInt)
    staticVirtual := new ColumnarCodePlan()
    staticVirtual.PrepareV2()
    staticRoot := staticVirtual.BeginFragment(-1, 1070, 0)
    staticMethod := staticVirtual.AddMethod(identity)
    staticVirtual.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    staticVirtual.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), staticMethod)
    staticVirtual.CompleteFragment(staticRoot, typeof(int))
    staticVirtual.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(staticVirtual) }

    noTypes := new Type[](0)
    lengthGetter := ExecutorRequiredMethod(typeof(string), "get_Length", noTypes)
    badReceiver := new ColumnarCodePlan()
    badReceiver.PrepareV2()
    receiverRoot := badReceiver.BeginFragment(-1, 1071, 0)
    getter := badReceiver.AddMethod(lengthGetter)
    badReceiver.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    badReceiver.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), getter)
    badReceiver.CompleteFragment(receiverRoot, typeof(int))
    badReceiver.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badReceiver) }

    ctorTypes := new Type[](2)
    ctorTypes[0] = typeof(int)
    ctorTypes[1] = typeof(bool)
    indexCtor := ExecutorRequiredConstructor(typeof(Index), ctorTypes)
    badConstructor := new ColumnarCodePlan()
    badConstructor.PrepareV2()
    constructorRoot := badConstructor.BeginFragment(-1, 1072, 0)
    stringType := badConstructor.AddType(typeof(string))
    stringArgument := badConstructor.AddArgument(0, stringType)
    constructorIndex := badConstructor.AddConstructor(indexCtor)
    badConstructor.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), stringArgument)
    badConstructor.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    badConstructor.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
    badConstructor.CompleteFragment(constructorRoot, typeof(Index))
    badConstructor.CompleteV2(typeof(Index))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badConstructor) }
}

test "schema v2 executor requires callvirt for abstract instance methods" {
    noTypes := new Type[](0)
    lengthGetter := ExecutorRequiredMethod(typeof(System.IO.Stream), "get_Length", noTypes)

    invalid := new ColumnarCodePlan()
    invalid.PrepareV2()
    invalidRoot := invalid.BeginFragment(-1, 1073, 0)
    invalidStreamType := invalid.AddType(typeof(System.IO.Stream))
    invalidArgument := invalid.AddArgument(0, invalidStreamType)
    invalidGetter := invalid.AddMethod(lengthGetter)
    invalid.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), invalidArgument)
    invalid.AppendMethodInstruction(ColumnarCodePlanContract.Call(), invalidGetter)
    invalid.CompleteFragment(invalidRoot, typeof(long))
    invalid.CompleteV2(typeof(long))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(invalid) }

    valid := new ColumnarCodePlan()
    valid.PrepareV2()
    validRoot := valid.BeginFragment(-1, 1074, 0)
    validStreamType := valid.AddType(typeof(System.IO.Stream))
    validArgument := valid.AddArgument(0, validStreamType)
    validGetter := valid.AddMethod(lengthGetter)
    valid.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), validArgument)
    valid.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), validGetter)
    valid.CompleteFragment(validRoot, typeof(long))
    valid.CompleteV2(typeof(long))
    ColumnarCodePlanExecutor.Validate(valid)
}

test "schema v2 executor rejects non-address value receivers and static fields" {
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    indexMethod := ExecutorRequiredMethod(typeof(Index), "GetOffset", oneInt)
    badValueReceiver := new ColumnarCodePlan()
    badValueReceiver.PrepareV2()
    valueRoot := badValueReceiver.BeginFragment(-1, 1080, 0)
    indexType := badValueReceiver.AddType(typeof(Index))
    indexArgument := badValueReceiver.AddArgument(0, indexType)
    methodIndex := badValueReceiver.AddMethod(indexMethod)
    badValueReceiver.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), indexArgument)
    badValueReceiver.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    badValueReceiver.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    badValueReceiver.CompleteFragment(valueRoot, typeof(int))
    badValueReceiver.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(badValueReceiver) }

    emptyField := ExecutorRequiredField(typeof(string), "Empty")
    staticField := new ColumnarCodePlan()
    staticField.PrepareV2()
    fieldRoot := staticField.BeginFragment(-1, 1081, 0)
    fieldIndex := staticField.AddField(emptyField)
    staticField.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    staticField.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
    staticField.CompleteFragment(fieldRoot, typeof(string))
    staticField.CompleteV2(typeof(string))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(staticField) }
}

test "schema v2 executor requires straight-line plan-local assignment" {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1082, 0)
    intType := plan.AddType(typeof(int))
    local := plan.DeclarePlanLocal(intType)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), local)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(plan) }
}

test "schema v2 executor intersects plan-local assignment across branches" {
    oneBranch := new ColumnarCodePlan()
    oneBranch.PrepareV2()
    oneRoot := oneBranch.BeginFragment(-1, 1083, 0)
    oneIntType := oneBranch.AddType(typeof(int))
    oneLocal := oneBranch.DeclarePlanLocal(oneIntType)
    oneFalse := oneBranch.DefineLabel()
    oneEnd := oneBranch.DefineLabel()
    oneBranch.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    oneBranch.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), oneFalse)
    oneBranch.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    oneBranch.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), oneLocal)
    oneBranch.AppendLabelInstruction(ColumnarCodePlanContract.Br(), oneEnd)
    oneBranch.AppendMarkLabel(oneFalse)
    oneBranch.AppendMarkLabel(oneEnd)
    oneBranch.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), oneLocal)
    oneBranch.CompleteFragment(oneRoot, typeof(int))
    oneBranch.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(oneBranch) }

    bothBranches := new ColumnarCodePlan()
    bothBranches.PrepareV2()
    bothRoot := bothBranches.BeginFragment(-1, 1084, 0)
    bothIntType := bothBranches.AddType(typeof(int))
    bothLocal := bothBranches.DeclarePlanLocal(bothIntType)
    bothFalse := bothBranches.DefineLabel()
    bothEnd := bothBranches.DefineLabel()
    bothBranches.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    bothBranches.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), bothFalse)
    bothBranches.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_2())
    bothBranches.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), bothLocal)
    bothBranches.AppendLabelInstruction(ColumnarCodePlanContract.Br(), bothEnd)
    bothBranches.AppendMarkLabel(bothFalse)
    bothBranches.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_3())
    bothBranches.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), bothLocal)
    bothBranches.AppendMarkLabel(bothEnd)
    bothBranches.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), bothLocal)
    bothBranches.CompleteFragment(bothRoot, typeof(int))
    bothBranches.CompleteV2(typeof(int))
    ColumnarCodePlanExecutor.Validate(bothBranches)
}

test "schema v2 executor rejects void and by-reference reflection signatures" {
    noTypes := new Type[](0)
    voidMethod := ExecutorRequiredMethod(
        typeof(ColumnarExecutorProbeMethods),
        "Nothing",
        noTypes)
    voidPlan := new ColumnarCodePlan()
    voidPlan.PrepareV2()
    voidRoot := voidPlan.BeginFragment(-1, 1090, 0)
    voidIndex := voidPlan.AddMethod(voidMethod)
    voidPlan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), voidIndex)
    voidPlan.CompleteFragment(voidRoot, typeof(int))
    voidPlan.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(voidPlan) }

    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    byRefGetter := ExecutorRequiredMethod(typeof(Span<int>), "get_Item", oneInt)
    byRefPlan := new ColumnarCodePlan()
    byRefPlan.PrepareV2()
    byRefRoot := byRefPlan.BeginFragment(-1, 1091, 0)
    byRefIndex := byRefPlan.AddMethod(byRefGetter)
    byRefPlan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    byRefPlan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), byRefIndex)
    byRefPlan.CompleteFragment(byRefRoot, typeof(int))
    byRefPlan.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(byRefPlan) }
}

test "schema v2 executor rejects method definitions but retains constructed open handles" {
    definition := typeof(RuntimeHelpers).GetMethod("GetSubArray")
    if definition == null {
        throw new InvalidOperationException("Required GetSubArray definition was not found.")
    }

    rawDefinition := new ColumnarCodePlan()
    rawDefinition.PrepareV2()
    rawRoot := rawDefinition.BeginFragment(-1, 1092, 0)
    rawParameters := definition.GetParameters()
    if rawParameters.Length != 2 {
        throw new InvalidOperationException("Raw GetSubArray signature is incomplete.")
    }
    rawArrayType := rawDefinition.AddType(rawParameters[0].get_ParameterType())
    rawRangeType := rawDefinition.AddType(rawParameters[1].get_ParameterType())
    rawArrayArgument := rawDefinition.AddArgument(0, rawArrayType)
    rawRangeArgument := rawDefinition.AddArgument(1, rawRangeType)
    rawMethod := rawDefinition.AddMethod(definition)
    rawDefinition.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), rawArrayArgument)
    rawDefinition.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), rawRangeArgument)
    rawDefinition.AppendMethodInstruction(ColumnarCodePlanContract.Call(), rawMethod)
    rawResultType := definition.get_ReturnType()
    rawDefinition.CompleteFragment(rawRoot, rawResultType)
    rawDefinition.CompleteV2(rawResultType)
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(rawDefinition) }

    genericParameter := ExecutorOpenGenericParameter()
    typeArguments := new Type[](1)
    typeArguments[0] = genericParameter
    constructed := definition.MakeGenericMethod(typeArguments)
    parameters := constructed.GetParameters()
    if parameters.Length != 2 {
        throw new InvalidOperationException("Constructed GetSubArray signature is incomplete.")
    }
    arrayTypeValue := parameters[0].get_ParameterType()
    rangeTypeValue := parameters[1].get_ParameterType()
    resultType := constructed.get_ReturnType()

    valid := new ColumnarCodePlan()
    valid.PrepareV2()
    validRoot := valid.BeginFragment(-1, 1093, 0)
    arrayType := valid.AddType(arrayTypeValue)
    rangeType := valid.AddType(rangeTypeValue)
    arrayArgument := valid.AddArgument(0, arrayType)
    rangeArgument := valid.AddArgument(1, rangeType)
    methodIndex := valid.AddMethod(constructed)
    valid.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), arrayArgument)
    valid.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), rangeArgument)
    valid.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    valid.CompleteFragment(validRoot, resultType)
    valid.CompleteV2(resultType)
    ColumnarCodePlanExecutor.Validate(valid)
}

test "schema v2 executor rejects raw generic type definitions" {
    definition := typeof(ValueTuple<int, int>).GetGenericTypeDefinition()
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1096, 0)
    definitionType := plan.AddType(definition)
    argument := plan.AddArgument(0, definitionType)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.CompleteFragment(root, definition)
    plan.CompleteV2(definition)
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(plan) }
}

test "schema v2 executor requires typed ldelem for generic parameters" {
    genericParameter := ExecutorOpenGenericParameter()
    genericArray := genericParameter.MakeArrayType()

    wrong := new ColumnarCodePlan()
    wrong.PrepareV2()
    wrongRoot := wrong.BeginFragment(-1, 1094, 0)
    wrongArrayType := wrong.AddType(genericArray)
    wrongArgument := wrong.AddArgument(0, wrongArrayType)
    wrong.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), wrongArgument)
    wrong.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    wrong.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemRef())
    wrong.CompleteFragment(wrongRoot, genericParameter)
    wrong.CompleteV2(genericParameter)
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(wrong) }

    typed := new ColumnarCodePlan()
    typed.PrepareV2()
    typedRoot := typed.BeginFragment(-1, 1095, 0)
    typedArrayType := typed.AddType(genericArray)
    typedElementType := typed.AddType(genericParameter)
    typedArgument := typed.AddArgument(0, typedArrayType)
    typed.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), typedArgument)
    typed.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    typed.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), typedElementType)
    typed.CompleteFragment(typedRoot, genericParameter)
    typed.CompleteV2(genericParameter)
    ColumnarCodePlanExecutor.Validate(typed)
}

test "schema v2 executor rejects every remaining unused pool and label declaration" {
    intTypeValues := new Type[](2)
    intTypeValues[0] = typeof(int)
    intTypeValues[1] = typeof(bool)
    indexCtor := ExecutorRequiredConstructor(typeof(Index), intTypeValues)
    item1 := ExecutorRequiredField(typeof(ValueTuple<int, int>), "Item1")

    unusedArgument := new ColumnarCodePlan()
    unusedArgument.PrepareV2()
    argumentRoot := unusedArgument.BeginFragment(-1, 1100, 0)
    intType := unusedArgument.AddType(typeof(int))
    unusedArgument.AddArgument(0, intType)
    unusedArgument.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unusedArgument.CompleteFragment(argumentRoot, typeof(int))
    unusedArgument.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedArgument) }

    unusedConstructor := new ColumnarCodePlan()
    unusedConstructor.PrepareV2()
    constructorRoot := unusedConstructor.BeginFragment(-1, 1101, 0)
    unusedConstructor.AddConstructor(indexCtor)
    unusedConstructor.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unusedConstructor.CompleteFragment(constructorRoot, typeof(int))
    unusedConstructor.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedConstructor) }

    unusedField := new ColumnarCodePlan()
    unusedField.PrepareV2()
    fieldRoot := unusedField.BeginFragment(-1, 1102, 0)
    unusedField.AddField(item1)
    unusedField.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unusedField.CompleteFragment(fieldRoot, typeof(int))
    unusedField.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedField) }

    unusedLabel := new ColumnarCodePlan()
    unusedLabel.PrepareV2()
    labelRoot := unusedLabel.BeginFragment(-1, 1103, 0)
    unusedLabel.DefineLabel()
    unusedLabel.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unusedLabel.CompleteFragment(labelRoot, typeof(int))
    unusedLabel.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(unusedLabel) }
}

test "schema v2 executor rejects duplicate argument ordinals" {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    root := plan.BeginFragment(-1, 1104, 0)
    intType := plan.AddType(typeof(int))
    first := plan.AddArgument(0, intType)
    second := plan.AddArgument(0, intType)
    temporary := plan.DeclarePlanLocal(intType)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), first)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), temporary)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), second)
    plan.CompleteFragment(root, typeof(int))
    plan.CompleteV2(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(plan) }
}

test "schema v2 executor validates before null IL and does not consume the plan" {
    plan := ExecutorConstantPlan(typeof(int))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Execute(plan, null) }
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    ColumnarCodePlanExecutor.Validate(plan)

    invalid := ExecutorConstantPlan(typeof(string))
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Execute(invalid, null) }
    assert invalid.Lifecycle == ColumnarCodePlanLifecycle.Sealed
}

test "schema v2 executor bounds tampered label counts before allocation" {
    plan := ExecutorConstantPlan(typeof(int))
    plan.LabelCount = 1000000000
    assert throws InvalidOperationException { ColumnarCodePlanExecutor.Validate(plan) }
}

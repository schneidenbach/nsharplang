namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

class ColumnarConversionProbeMethods {
    static func AcceptObject(_value: object): string {
        return "object"
    }
}

func ConversionRequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameters)
    if method == null {
        throw new InvalidOperationException("Required conversion probe method was not found: " + name)
    }

    return method
}

func ConversionComparableType(): Type {
    valueType := Type.GetType("System.IComparable, System.Private.CoreLib")
    if valueType == null {
        throw new InvalidOperationException("Required conversion interface type was not found.")
    }

    return valueType
}

func ConversionFromI4Plan(opCodeValue: short, resultType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1200, 0)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_7())
    plan.AppendInstructionWithoutOperand(opCodeValue)
    plan.CompleteFragment(root, resultType)
    plan.CompleteV3(resultType)
    return plan
}

func ConversionLongToSinglePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1201, 0)
    child := plan.BeginFragment(root, 1202, 1)
    valueIndex := plan.AddInt64((long)41)
    plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
    plan.CompleteFragment(child, typeof(long))
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR4())
    plan.CompleteFragment(root, typeof(float))
    plan.CompleteV3(typeof(float))
    return plan
}

func ConversionSingleToDoublePlan(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1203, 0)
    child := plan.BeginFragment(root, 1204, 1)
    valueIndex := plan.AddSingle((float)1.5)
    plan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR4(), valueIndex)
    plan.CompleteFragment(child, typeof(float))
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
    plan.CompleteFragment(root, typeof(double))
    plan.CompleteV3(typeof(double))
    return plan
}

func ConversionBoxPlan(resultType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1205, 0)
    intType := plan.AddType(typeof(int))
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_8())
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), intType)
    plan.CompleteFragment(root, resultType)
    plan.CompleteV3(resultType)
    return plan
}

func ConversionBoxCallPlan(parameterType: Type, methodName: string): ColumnarCodePlan {
    parameterTypes := new Type[](1)
    parameterTypes[0] = parameterType
    method := ConversionRequiredMethod(typeof(ColumnarConversionProbeMethods), methodName, parameterTypes)

    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1206, 0)
    intType := plan.AddType(typeof(int))
    methodIndex := plan.AddMethod(method)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_8())
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), intType)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    plan.CompleteFragment(root, typeof(string))
    plan.CompleteV3(typeof(string))
    return plan
}

func ConversionCastclassPlan(targetType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1212, 0)
    text := plan.AddString("cast-value")
    targetIndex := plan.AddType(targetType)
    plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), text)
    plan.AppendTypeInstruction(
        ColumnarCodePlanContract.Castclass(), targetIndex)
    plan.CompleteFragment(root, targetType)
    plan.CompleteV3(targetType)
    return plan
}

func ConversionSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func ConversionRunPlan(plan: ColumnarCodePlan, resultType: Type): string {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if constructorInfo == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }

    constructorArguments := new object[](3)
    ConversionSetObject(constructorArguments, 0, "NSharpConversionPlan")
    ConversionSetObject(constructorArguments, 1, resultType)
    ConversionSetObject(constructorArguments, 2, new Type[](0))
    dynamicMethod := (DynamicMethod)constructorInfo.Invoke(constructorArguments)
    il := dynamicMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    il.Emit(OpCodes.Ret)

    target: object? = null
    result := dynamicMethod.Invoke(target, new object[](0))
    if result == null {
        throw new InvalidOperationException("Conversion DynamicMethod returned null unexpectedly.")
    }

    return result.ToString() ?? ""
}

test "schema v3 conversion and box opcodes pin exact CLR identities and catalog facts" {
    assert ColumnarCodePlanContract.ConvI8() == 106
    assert ColumnarCodePlanContract.ConvR4() == 107
    assert ColumnarCodePlanContract.ConvR8() == 108
    assert ColumnarCodePlanContract.Castclass() == 116
    assert ColumnarCodePlanContract.Box() == 140

    assert ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Conv_I8").IsSupported

    assert ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Conv_R4").IsSupported

    assert ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Conv_R8").IsSupported

    assert ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Box").IsSupported

    assert ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "OpCodes", "Castclass").IsSupported
}

test "schema v3 admits conversion and box rows without widening v1 or v2" {
    i8 := ConversionFromI4Plan(ColumnarCodePlanContract.ConvI8(), typeof(long))

    r4 := ConversionFromI4Plan(ColumnarCodePlanContract.ConvR4(), typeof(float))

    r8 := ConversionFromI4Plan(ColumnarCodePlanContract.ConvR8(), typeof(double))

    boxed := ConversionBoxPlan(typeof(object))
    casted := ConversionCastclassPlan(ConversionComparableType())

    ColumnarCodePlanExecutor.Validate(i8)
    ColumnarCodePlanExecutor.Validate(r4)
    ColumnarCodePlanExecutor.Validate(r8)
    ColumnarCodePlanExecutor.Validate(boxed)
    ColumnarCodePlanExecutor.Validate(casted)
    assert i8.OperandKinds[1] == ColumnarCodePlanContract.NoOperand()
    assert boxed.OperandKinds[1] == ColumnarCodePlanContract.TypeOperand()
    assert casted.OperandKinds[1] == ColumnarCodePlanContract.TypeOperand()

    v1 := new ColumnarCodePlan()
    v1.Prepare()
    assert throws InvalidOperationException {
        v1.AppendInstruction(ColumnarCodePlanContract.ConvI8())
    }

    v2 := new ColumnarCodePlan()
    v2.PrepareV2()
    v2.BeginFragment(-1, 1207, 0)
    assert throws InvalidOperationException {
        v2.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
    }

    typeIndex := v2.AddType(typeof(int))
    assert throws InvalidOperationException {
        v2.AppendTypeInstruction(ColumnarCodePlanContract.Box(), typeIndex)
    }
    assert throws InvalidOperationException {
        v2.AppendTypeInstruction(
            ColumnarCodePlanContract.Castclass(), typeIndex)
    }
}

func ConversionFromArgumentPlan(sourceType: Type, opCodeValue: short, resultType: Type): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1220, 0)
    sourceIndex := plan.AddType(sourceType)
    argument := plan.AddArgument(0, sourceIndex)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendInstructionWithoutOperand(opCodeValue)
    plan.CompleteFragment(root, resultType)
    plan.CompleteV3(resultType)
    return plan
}

test "schema v3 admits the explicit-cast conversion opcodes over castable scalars" {
    // Narrowing/reinterpreting conversions from an Int32-slot literal.
    ColumnarCodePlanExecutor.Validate(
        ConversionFromI4Plan(ColumnarCodePlanContract.ConvI1(), typeof(sbyte)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromI4Plan(ColumnarCodePlanContract.ConvI2(), typeof(short)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromI4Plan(ColumnarCodePlanContract.ConvU1(), typeof(byte)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromI4Plan(ColumnarCodePlanContract.ConvU2(), typeof(char)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromI4Plan(ColumnarCodePlanContract.ConvU4(), typeof(uint)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromI4Plan(ColumnarCodePlanContract.ConvU8(), typeof(ulong)))

    // The shared widening arms now admit the full castable-scalar source set explicit casts need:
    // UInt32 -> Int64, Int64 -> Int32, and Double -> Single all validate.
    ColumnarCodePlanExecutor.Validate(
        ConversionFromArgumentPlan(typeof(uint), ColumnarCodePlanContract.ConvI8(), typeof(long)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromArgumentPlan(typeof(long), ColumnarCodePlanContract.ConvI4(), typeof(int)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromArgumentPlan(typeof(long), ColumnarCodePlanContract.ConvU4(), typeof(uint)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromArgumentPlan(typeof(uint), ColumnarCodePlanContract.ConvU8(), typeof(ulong)))
    ColumnarCodePlanExecutor.Validate(
        ConversionFromArgumentPlan(typeof(double), ColumnarCodePlanContract.ConvR4(), typeof(float)))

    // A managed reference is still outside every conversion arm's admitted set.
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(
            ConversionFromArgumentPlan(typeof(string), ColumnarCodePlanContract.ConvU2(), typeof(char)))
    }
}

test "schema v3 conversion plans execute through their persisted rows" {
    i8 := ConversionFromI4Plan(ColumnarCodePlanContract.ConvI8(), typeof(long))

    r4 := ConversionFromI4Plan(ColumnarCodePlanContract.ConvR4(), typeof(float))

    r8 := ConversionFromI4Plan(ColumnarCodePlanContract.ConvR8(), typeof(double))

    longToSingle := ConversionLongToSinglePlan()
    singleToDouble := ConversionSingleToDoublePlan()

    assert ConversionRunPlan(i8, typeof(long)) == "7"
    assert ConversionRunPlan(r4, typeof(float)) == "7"
    assert ConversionRunPlan(r8, typeof(double)) == "7"
    assert ConversionRunPlan(longToSingle, typeof(float)) == "41"
    assert ConversionRunPlan(singleToDouble, typeof(double)) == "1.5"
    assert i8.Lifecycle == ColumnarCodePlanLifecycle.Consumed
    assert longToSingle.Lifecycle == ColumnarCodePlanLifecycle.Consumed
}

test "schema v3 box plans validate and execute object and interface flows" {
    comparableType := ConversionComparableType()
    objectResult := ConversionBoxPlan(typeof(object))
    interfaceResult := ConversionBoxPlan(comparableType)
    objectCall := ConversionBoxCallPlan(typeof(object), "AcceptObject")

    ColumnarCodePlanExecutor.Validate(objectResult)
    ColumnarCodePlanExecutor.Validate(interfaceResult)
    ColumnarCodePlanExecutor.Validate(objectCall)
    assert ConversionRunPlan(objectResult, typeof(object)) == "8"
    assert ConversionRunPlan(interfaceResult, comparableType) == "8"
    assert ConversionRunPlan(objectCall, typeof(string)) == "object"
}

test "schema v3 castclass plans validate and execute exact reference targets" {
    comparableType := ConversionComparableType()
    casted := ConversionCastclassPlan(comparableType)

    ColumnarCodePlanExecutor.Validate(casted)
    assert ConversionRunPlan(casted, comparableType) == "cast-value"

    badTarget := new ColumnarCodePlan()
    badTarget.PrepareV3()
    badTargetRoot := badTarget.BeginFragment(-1, 1213, 0)
    text := badTarget.AddString("value")
    intType := badTarget.AddType(typeof(int))
    badTarget.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), text)
    badTarget.AppendTypeInstruction(
        ColumnarCodePlanContract.Castclass(), intType)
    badTarget.CompleteFragment(badTargetRoot, typeof(int))
    badTarget.CompleteV3(typeof(int))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(badTarget)
    }

    badSource := new ColumnarCodePlan()
    badSource.PrepareV3()
    badSourceRoot := badSource.BeginFragment(-1, 1214, 0)
    comparableIndex := badSource.AddType(comparableType)
    badSource.AppendInstructionWithoutOperand(
        ColumnarCodePlanContract.LdcI4_1())
    badSource.AppendTypeInstruction(
        ColumnarCodePlanContract.Castclass(), comparableIndex)
    badSource.CompleteFragment(badSourceRoot, comparableType)
    badSource.CompleteV3(comparableType)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(badSource)
    }

    pointerSource := new ColumnarCodePlan()
    pointerSource.PrepareV3()
    pointerSourceRoot := pointerSource.BeginFragment(-1, 1215, 0)
    pointerType := typeof(int).MakePointerType()
    pointerTypeIndex := pointerSource.AddType(pointerType)
    pointerArgument := pointerSource.AddArgument(0, pointerTypeIndex)
    comparablePointerIndex := pointerSource.AddType(comparableType)
    pointerSource.AppendArgumentInstruction(
        ColumnarCodePlanContract.Ldarg(), pointerArgument)
    pointerSource.AppendTypeInstruction(
        ColumnarCodePlanContract.Castclass(), comparablePointerIndex)
    pointerSource.CompleteFragment(pointerSourceRoot, comparableType)
    pointerSource.CompleteV3(comparableType)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(pointerSource)
    }
}

test "schema v3 rejects malformed box rows and incompatible box values before emission" {
    corruptRow := ConversionBoxPlan(typeof(object))
    corruptRow.OperandKinds[1] = ColumnarCodePlanContract.NoOperand()
    corruptRow.OperandIndices[1] = -1
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(corruptRow)
    }

    referenceOperand := new ColumnarCodePlan()
    referenceOperand.PrepareV3()
    referenceRoot := referenceOperand.BeginFragment(-1, 1208, 0)
    stringType := referenceOperand.AddType(typeof(string))
    text := referenceOperand.AddString("value")
    referenceOperand.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), text)
    referenceOperand.AppendTypeInstruction(ColumnarCodePlanContract.Box(), stringType)
    referenceOperand.CompleteFragment(referenceRoot, typeof(object))
    referenceOperand.CompleteV3(typeof(object))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(referenceOperand)
    }

    wrongValue := new ColumnarCodePlan()
    wrongValue.PrepareV3()
    wrongRoot := wrongValue.BeginFragment(-1, 1209, 0)
    longType := wrongValue.AddType(typeof(long))
    wrongValue.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    wrongValue.AppendTypeInstruction(ColumnarCodePlanContract.Box(), longType)
    wrongValue.CompleteFragment(wrongRoot, typeof(object))
    wrongValue.CompleteV3(typeof(object))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(wrongValue)
    }
}

test "schema v3 rejects conversion widening outside the admitted argument set" {
    // decimal is never a conv-opcode operand: it converts through its System.Decimal operator
    // statics. (Numeric scalars such as UInt32 ARE admitted now that explicit casts share these
    // conversion arms; see the companion admit test.)
    decimalToLong := new ColumnarCodePlan()
    decimalToLong.PrepareV3()
    decimalRoot := decimalToLong.BeginFragment(-1, 1210, 0)
    decimalType := decimalToLong.AddType(typeof(decimal))
    decimalArgument := decimalToLong.AddArgument(0, decimalType)
    decimalToLong.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), decimalArgument)

    decimalToLong.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
    decimalToLong.CompleteFragment(decimalRoot, typeof(long))
    decimalToLong.CompleteV3(typeof(long))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(decimalToLong)
    }

    stringToDouble := new ColumnarCodePlan()
    stringToDouble.PrepareV3()
    stringRoot := stringToDouble.BeginFragment(-1, 1211, 0)
    text := stringToDouble.AddString("no")
    stringToDouble.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), text)
    stringToDouble.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
    stringToDouble.CompleteFragment(stringRoot, typeof(double))
    stringToDouble.CompleteV3(typeof(double))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(stringToDouble)
    }
}

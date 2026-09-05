namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit

class ColumnarAddressableDirectCallFixture {
    HolderType: Type
    EnumeratorType: Type
    EnumeratorField: FieldInfo
    GetEnumerator: MethodInfo
    MoveNext: MethodInfo
    CurrentGetter: MethodInfo

    constructor(holderType: Type, enumeratorType: Type, enumeratorField: FieldInfo, getEnumerator: MethodInfo, moveNext: MethodInfo, currentGetter: MethodInfo) {
        HolderType = holderType
        EnumeratorType = enumeratorType
        EnumeratorField = enumeratorField
        GetEnumerator = getEnumerator
        MoveNext = moveNext
        CurrentGetter = currentGetter
    }
}

func AddressableDirectCallFixture(name: string): ColumnarAddressableDirectCallFixture {
    noTypes := new Type[](0)
    getEnumerator := ExecutorRequiredMethod(typeof(List<int>), "GetEnumerator", noTypes)
    enumeratorType := getEnumerator.get_ReturnType()
    moveNext := ExecutorRequiredMethod(enumeratorType, "MoveNext", noTypes)
    currentProperty := enumeratorType.GetProperty("Current")
    if currentProperty == null {
        throw new InvalidOperationException("The addressable direct-call enumerator has no Current property.")
    }

    currentGetter := currentProperty.GetGetMethod()
    if currentGetter == null {
        throw new InvalidOperationException("The addressable direct-call enumerator has no Current getter.")
    }

    builder := TypeOfCreateBuilder(name, "ColumnarAddressableDirectCallTests." + name, 0)

    defaultConstructorTypes := new Type[](1)
    defaultConstructorTypes[0] = typeof(MethodAttributes)
    defineDefaultConstructor := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineDefaultConstructor", defaultConstructorTypes)
    defaultConstructorArguments := new object[](1)
    ExecutorSetObject(defaultConstructorArguments, 0, (MethodAttributes)6)
    TypeOfRequiredInvocation(defineDefaultConstructor, builder, defaultConstructorArguments)

    defineFieldTypes := new Type[](3)
    defineFieldTypes[0] = typeof(string)
    defineFieldTypes[1] = typeof(Type)
    fieldAttributesType := TypeOfRequiredRuntimeType(typeof(TypeBuilder), "System.Reflection.FieldAttributes")
    defineFieldTypes[2] = fieldAttributesType
    defineField := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineField", defineFieldTypes)
    defineFieldArguments := new object[](3)
    ExecutorSetObject(defineFieldArguments, 0, "Enumerator")
    ExecutorSetObject(defineFieldArguments, 1, enumeratorType)
    ExecutorSetObject(defineFieldArguments, 2, TypeOfRequiredStaticField(fieldAttributesType, "Public"))
    fieldValue := TypeOfRequiredInvocation(defineField, builder, defineFieldArguments)
    fieldBuilder := fieldValue as FieldBuilder
    if fieldBuilder == null {
        throw new InvalidOperationException("The addressable direct-call holder field was not defined.")
    }

    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", noTypes)
    bakedValue := TypeOfRequiredInvocation(createType, builder, new object[](0))
    holderType := bakedValue as Type
    if holderType == null {
        throw new InvalidOperationException("The addressable direct-call holder was not baked.")
    }

    field := holderType.GetField("Enumerator")
    if field == null || field.get_FieldType() != enumeratorType || field.get_IsStatic() {
        throw new InvalidOperationException("The baked addressable direct-call field has the wrong signature.")
    }

    return new ColumnarAddressableDirectCallFixture(holderType, enumeratorType, field, getEnumerator, moveNext, currentGetter)
}

func AddressableDirectCallPlan(fixture: ColumnarAddressableDirectCallFixture, loadAddress: bool): ColumnarCodePlan {
    noTypes := new Type[](0)
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1300, 0)
    holderType := plan.AddType(fixture.HolderType)
    holder := plan.AddArgument(0, holderType)
    field := plan.AddFieldWithSignature(fixture.EnumeratorField, fixture.HolderType, fixture.EnumeratorType, false)
    method := plan.AddMethodWithSignature(fixture.MoveNext, fixture.EnumeratorType, noTypes, typeof(bool), false, false)

    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), holder)
    plan.AppendFieldInstruction(loadAddress ? ColumnarCodePlanContract.Ldflda() : ColumnarCodePlanContract.Ldfld(), field)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), method)
    plan.CompleteFragment(root, typeof(bool))
    plan.CompleteV3(typeof(bool))
    return plan
}

func AddressableDirectCallHolder(fixture: ColumnarAddressableDirectCallFixture): object {
    constructorInfo := ExecutorRequiredConstructor(fixture.HolderType, new Type[](0))
    holder := constructorInfo.Invoke(new object[](0))
    if holder == null {
        throw new InvalidOperationException("The addressable direct-call holder was not constructed.")
    }

    values := new List<int>()
    values.Add(42)
    values.Add(43)
    enumerator := TypeOfRequiredInvocation(fixture.GetEnumerator, values, new object[](0))

    AddressableDirectCallSetField(fixture.EnumeratorField, holder, enumerator)
    return holder
}

func AddressableDirectCallSetField(field: FieldInfo, target: object, value: object) {
    setterTypes := new Type[](2)
    setterTypes[0] = typeof(object)
    setterTypes[1] = typeof(object)
    setter := ExecutorRequiredMethod(typeof(FieldInfo), "SetValue", setterTypes)

    wrapperTypes := new Type[](3)
    wrapperTypes[0] = typeof(FieldInfo)
    wrapperTypes[1] = typeof(object)
    wrapperTypes[2] = typeof(object)
    wrapper := BoundDynamicMethod("AddressableDirectCallSetField", typeof(int), wrapperTypes)
    il := wrapper.GetILGenerator()
    il.Emit(OpCodes.Ldarg, (short)0)
    il.Emit(OpCodes.Ldarg, (short)1)
    il.Emit(OpCodes.Ldarg, (short)2)
    il.Emit(OpCodes.Callvirt, setter)
    il.Emit(OpCodes.Ldc_I4, 0)
    il.Emit(OpCodes.Ret)

    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, field)
    ExecutorSetObject(arguments, 1, target)
    ExecutorSetObject(arguments, 2, value)
    if BoundInvokeText(wrapper, arguments) != "0" {
        throw new InvalidOperationException("The addressable direct-call holder field was not initialized.")
    }
}

func AddressableDirectCallCurrent(fixture: ColumnarAddressableDirectCallFixture, holder: object): string {
    getterTypes := new Type[](1)
    getterTypes[0] = typeof(object)
    getValue := ExecutorRequiredMethod(typeof(FieldInfo), "GetValue", getterTypes)
    getterArguments := new object[](1)
    ExecutorSetObject(getterArguments, 0, holder)
    enumerator := TypeOfRequiredInvocation(getValue, fixture.EnumeratorField, getterArguments)

    current := TypeOfRequiredInvocation(fixture.CurrentGetter, enumerator, new object[](0))

    return Convert.ToString(current, CultureInfo.InvariantCulture) ?? ""
}

test "addressable direct-call persisted execution mutates original value field storage" {
    fixture := AddressableDirectCallFixture("AddressableExecutionHolder")
    plan := AddressableDirectCallPlan(fixture, true)
    ColumnarCodePlanExecutor.Validate(plan)

    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldflda()
    assert plan.OperandKinds[1] == ColumnarCodePlanContract.FieldOperand()
    assert plan.FieldUsesDeclaredSignature[0]
    assert plan.FieldDeclaringTypes[0] == fixture.HolderType
    assert plan.FieldValueTypes[0] == fixture.EnumeratorType
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Call()
    assert plan.MethodUsesDeclaredSignature[0]
    assert plan.MethodDeclaringTypes[0] == fixture.EnumeratorType

    holder := AddressableDirectCallHolder(fixture)
    assert AddressableDirectCallCurrent(fixture, holder) == "0"

    parameterTypes := new Type[](1)
    parameterTypes[0] = fixture.HolderType
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, holder)
    assert ExecutorRunRecursivePlan(plan, typeof(bool), parameterTypes, arguments) == "True"

    // A call on an ldfld copy also returns true, but leaves this stored enumerator before its
    // first element. Observing 42 therefore proves the call used the ldflda-managed address.
    assert AddressableDirectCallCurrent(fixture, holder) == "42"
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
}

test "addressable direct-call validation rejects malformed and corrupt ldflda rows purely" {
    fixture := AddressableDirectCallFixture("AddressableValidationHolder")

    copiedReceiver := AddressableDirectCallPlan(fixture, false)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(copiedReceiver)
    }

    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Execute(copiedReceiver, null)
    }

    assert copiedReceiver.Lifecycle == ColumnarCodePlanLifecycle.Sealed

    corruptOperand := AddressableDirectCallPlan(fixture, true)
    corruptOperand.OperandKinds[1] = ColumnarCodePlanContract.MethodOperand()
    corruptOperand.OperandIndices[1] = 0
    assert throws InvalidOperationException {
        corruptOperand.ValidateSealedStructure()
    }

    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Execute(corruptOperand, null)
    }

    assert corruptOperand.Lifecycle == ColumnarCodePlanLifecycle.Sealed

    staticField := new ColumnarCodePlan()
    staticField.PrepareV3()
    staticRoot := staticField.BeginFragment(-1, 1301, 0)
    holderType := staticField.AddType(fixture.HolderType)
    holder := staticField.AddArgument(0, holderType)
    empty := ExecutorRequiredField(typeof(string), "Empty")
    emptyIndex := staticField.AddField(empty)
    staticField.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), holder)
    staticField.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), emptyIndex)
    staticField.CompleteFragment(staticRoot, typeof(string))
    staticField.CompleteV3(typeof(string))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(staticField)
    }

    assert staticField.Lifecycle == ColumnarCodePlanLifecycle.Sealed

    recursive := new ColumnarCodePlan()
    recursive.PrepareV2()
    recursive.BeginFragment(-1, 1302, 0)
    recursiveField := recursive.AddField(fixture.EnumeratorField)
    operationCount := recursive.OperationCount
    assert throws InvalidOperationException {
        recursive.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), recursiveField)
    }

    assert recursive.OperationCount == operationCount
}

test "addressable direct-call checkpoint rollback removes ldflda handles and rows atomically" {
    fixture := AddressableDirectCallFixture("AddressableRollbackHolder")
    noTypes := new Type[](0)
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    root := plan.BeginFragment(-1, 1303, 0)
    holderType := plan.AddType(fixture.HolderType)
    holder := plan.AddArgument(0, holderType)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), holder)
    checkpoint := plan.CreateCheckpoint()

    field := plan.AddFieldWithSignature(fixture.EnumeratorField, fixture.HolderType, fixture.EnumeratorType, false)
    method := plan.AddMethodWithSignature(fixture.MoveNext, fixture.EnumeratorType, noTypes, typeof(bool), false, false)
    plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), field)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), method)

    assert plan.FieldCount == 1
    assert plan.MethodCount == 1
    assert plan.OperationCount == 3

    plan.Rollback(checkpoint)

    assert plan.FieldCount == 0
    assert plan.MethodCount == 0
    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert !plan.FragmentCompleted[root]

    rebuiltField := plan.AddFieldWithSignature(fixture.EnumeratorField, fixture.HolderType, fixture.EnumeratorType, false)
    rebuiltMethod := plan.AddMethodWithSignature(fixture.MoveNext, fixture.EnumeratorType, noTypes, typeof(bool), false, false)
    plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), rebuiltField)
    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), rebuiltMethod)
    plan.CompleteFragment(root, typeof(bool))
    plan.CompleteV3(typeof(bool))
    ColumnarCodePlanExecutor.Validate(plan)

    assert plan.FieldCount == 1
    assert plan.MethodCount == 1
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldflda()
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
}

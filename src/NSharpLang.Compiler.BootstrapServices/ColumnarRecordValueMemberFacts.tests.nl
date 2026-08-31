namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

// 015-B2 STAGE 2 — the rows stage 1 admitted get their consumers.
//
// Stage 1 could only ask whether the emitter's modeled `OpCodes` surface ADMITTED `Ldarg_0..3` and
// `Unbox_Any`; nothing could spell them until the toolset was republished. These blocks are what the
// republish unblocked: the `unbox.any` plan row and its executor arm, the four-way argument narrowing,
// and the three typed-stack gaps that had to close before a synthesized record `Equals` could be
// planned at all (`isinst` was emittable but not TYPED, `pop` was counted but not typed, and
// `brfalse`/`brtrue` refused a reference).
//
// BYTE WIDTH IS NOT PINNED HERE AND THAT IS SAID RATHER THAN GLOSSED: `ILGenerator.ILOffset` is not on
// the modeled surface, so the estate cannot measure how many bytes a row became. The corpus IL
// byte-comparison is the authority for narrowing width; these blocks are the authority for what the
// rows MEAN.

func RecordFactsRequiredConstructor(owner: Type, parameterTypes: Type[]): ConstructorInfo {
    constructorInfo := owner.GetConstructor(parameterTypes)
    if constructorInfo == null {
        throw new InvalidOperationException("Required constructor was not found.")
    }
    return constructorInfo
}

func RecordFactsSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func RecordFactsDynamicMethod(name: string, returnType: Type, parameterTypes: Type[]): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := RecordFactsRequiredConstructor(typeof(DynamicMethod), constructorTypes)
    constructorArguments := new object?[](3)
    RecordFactsSetObject(constructorArguments, 0, name)
    RecordFactsSetObject(constructorArguments, 1, returnType)
    RecordFactsSetObject(constructorArguments, 2, parameterTypes)
    return (DynamicMethod)constructorInfo.Invoke(constructorArguments)
}

func RecordFactsIntParameters(count: int): Type[] {
    parameterTypes := new Type[](count)
    i := 0
    while i < count {
        parameterTypes[i] = typeof(int)
        i = i + 1
    }
    return parameterTypes
}

func RecordFactsOneObjectParameter(): Type[] {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(object)
    return parameterTypes
}

// THE ARGUMENT NARROWING, PROVED BY EXECUTION AT EVERY ORDINAL THE CHAIN DISTINGUISHES.
// Ordinals 0..3 take the short forms the stage-1 widening admitted; ordinal 4 falls through to the
// long form, which is the recorded caveat rather than an oversight. A wrong ordinal returns a
// different argument, so the answer identifies the slot.
test "the argument row narrows every short-form ordinal and still answers at the long-form fallback" {
    ordinal := 0
    while ordinal < 5 {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        intTypeIndex := plan.AddType(typeof(int))
        argument := plan.AddArgument(ordinal, intTypeIndex, false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(int))

        method := RecordFactsDynamicMethod("NSharpB2Narrow", typeof(int), RecordFactsIntParameters(5))
        ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
        arguments := new object?[](5)
        RecordFactsSetObject(arguments, 0, 100)
        RecordFactsSetObject(arguments, 1, 101)
        RecordFactsSetObject(arguments, 2, 102)
        RecordFactsSetObject(arguments, 3, 103)
        RecordFactsSetObject(arguments, 4, 104)
        assert Convert.ToInt32(method.Invoke(null, arguments)) == 100 + ordinal
        ordinal = ordinal + 1
    }
}

// `Ldarga` keeps the long form at EVERY ordinal, because `Ldarga_S` was deliberately not admitted in
// stage 1 — it needs a `System.Byte` emit operand the modeled surface does not carry. The asymmetry
// between the two argument opcodes is a decision, so it is pinned as one.
test "the address-of-argument row never narrows and still loads a usable managed pointer" {
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    intTypeIndex := plan.AddType(typeof(int))
    argument := plan.AddArgument(0, intTypeIndex, false)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarga(), argument)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdindI4())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.CompleteMethodBody(typeof(int))

    method := RecordFactsDynamicMethod("NSharpB2Ldarga", typeof(int), RecordFactsIntParameters(1))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    arguments := new object?[](1)
    RecordFactsSetObject(arguments, 0, 77)
    assert Convert.ToInt32(method.Invoke(null, arguments)) == 77
}

// THE `unbox.any` ROW. 0xA5 = 165, method-body-only, and it EXECUTES over a boxed value.
test "the method-body schema owns unbox.any and the expression fragments refuse it" {
    assert ColumnarCodePlanContract.UnboxAny() == 165

    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    objectTypeIndex := plan.AddType(typeof(object))
    intTypeIndex := plan.AddType(typeof(int))
    argument := plan.AddArgument(0, objectTypeIndex, false)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendTypeInstruction(ColumnarCodePlanContract.UnboxAny(), intTypeIndex)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.CompleteMethodBody(typeof(int))

    method := RecordFactsDynamicMethod("NSharpB2UnboxAny", typeof(int), RecordFactsOneObjectParameter())
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    arguments := new object?[](1)
    RecordFactsSetObject(arguments, 0, 4242)
    assert Convert.ToInt32(method.Invoke(null, arguments)) == 4242

    // The row belongs to the METHOD-BODY schema and to no other: a plan that is not a method body
    // refuses it at the appender rather than discovering it at replay.
    other := new ColumnarCodePlan()
    other.Prepare()
    assert throws InvalidOperationException {
        other.AppendTypeInstruction(ColumnarCodePlanContract.UnboxAny(), 0)
    }
}

// `isinst` narrowing a method-body value into a plan local of the TARGET type. This is the shape PASS
// 0e's `Equals` uses, and nothing pinned it before. The METHOD-BODY validator is a height model, not a
// typed one, so what is proved here is the emitted behaviour rather than a type judgement: the hit
// returns the string and the miss returns null.
test "isinst narrows a method-body value into a plan local of the target type" {
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    objectTypeIndex := plan.AddType(typeof(object))
    stringTypeIndex := plan.AddType(typeof(string))
    argument := plan.AddArgument(0, objectTypeIndex, false)
    narrowed := plan.DeclarePlanLocal(stringTypeIndex)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Isinst(), stringTypeIndex)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), narrowed)
    plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), narrowed)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.CompleteMethodBody(typeof(string))

    method := RecordFactsDynamicMethod("NSharpB2Isinst", typeof(string), RecordFactsOneObjectParameter())
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    hit := new object?[](1)
    RecordFactsSetObject(hit, 0, "record")
    result := method.Invoke(null, hit)
    assert result != null

    miss := new object?[](1)
    RecordFactsSetObject(miss, 0, 5)
    assert method.Invoke(null, miss) == null
}

// THE RECORD-`Equals` SKELETON, END TO END. A null test on a reference is ordinary CIL and the
// method-body validator admits it, but nothing pinned that until now — and the same body proves the
// `dup`/`brtrue`/`pop` idiom and, with it, that a label MERGED AT A NON-EMPTY STACK DEPTH is legal.
test "the record-Equals branch skeleton validates and executes over references" {
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    objectTypeIndex := plan.AddType(typeof(object))
    stringTypeIndex := plan.AddType(typeof(string))
    argument := plan.AddArgument(0, objectTypeIndex, false)
    returnZero := plan.DefineLabel()
    matched := plan.DefineLabel()

    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), returnZero)
    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argument)
    plan.AppendTypeInstruction(ColumnarCodePlanContract.Isinst(), stringTypeIndex)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), matched)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
    plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), returnZero)
    plan.AppendMarkLabel(matched)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.AppendMarkLabel(returnZero)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.CompleteMethodBody(typeof(int))

    method := RecordFactsDynamicMethod("NSharpB2NullTest", typeof(int), RecordFactsOneObjectParameter())
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())

    hit := new object?[](1)
    RecordFactsSetObject(hit, 0, "record")
    assert Convert.ToInt32(method.Invoke(null, hit)) == 1

    wrongType := new object?[](1)
    RecordFactsSetObject(wrongType, 0, 5)
    assert Convert.ToInt32(method.Invoke(null, wrongType)) == 0

    nullArgument := new object?[](1)
    RecordFactsSetObject(nullArgument, 0, null)
    assert Convert.ToInt32(method.Invoke(null, nullArgument)) == 0
}

// `pop` is a method-body row, and the method-body validator is a HEIGHT model: a body that pops an
// empty stack is refused at validation rather than replayed into a faulting method.
test "pop on an empty stack is refused by the method-body height model" {
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    assert throws InvalidOperationException {
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(ColumnarRecordValueMemberFactsVoidType())
        ColumnarCodePlanExecutor.Validate(plan)
    }
}

func ColumnarRecordValueMemberFactsVoidType(): Type {
    voidType := Type.GetType("System.Void")
    if voidType == null {
        throw new InvalidOperationException("System.Void was not found.")
    }
    return voidType
}

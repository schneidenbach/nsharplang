namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

class ColumnarCodePlanStackValueKind {
    public static func Exact(): int { return 0 }
    public static func LiteralI4(): int { return 1 }
    public static func NativeUnsigned(): int { return 2 }
}

class ColumnarCodePlanReflectionContract {
    // System.Reflection.CallingConventions.VarArgs has the stable CLR metadata flag value 2.
    public static func VarArgsCallingConventionFlag(): int { return 2 }
}

// Evaluation-stack nodes are immutable and persistent. Straight-line validation moves a state
// without copying its stack, fragment entry facts retain a node identity, and branches share their
// common tail. Only a genuinely divergent merge walks and rebuilds the divergent prefix.
class ColumnarCodePlanStackNode {
    public ValueType: Type
    public IsAddress: bool
    public ValueKind: int
    public LiteralKnown: bool
    public LiteralValue: int
    public Previous: ColumnarCodePlanStackNode?

    constructor(
        valueType: Type,
        isAddress: bool,
        valueKind: int,
        literalKnown: bool,
        literalValue: int,
        previous: ColumnarCodePlanStackNode?) {
        ValueType = valueType
        IsAddress = isAddress
        ValueKind = valueKind
        LiteralKnown = literalKnown
        LiteralValue = literalValue
        Previous = previous
    }
}

class ColumnarCodePlanStackState {
    public Head: ColumnarCodePlanStackNode?
    public AssignedPlanLocalWords: ulong[]
    public Count: int

    constructor(planLocalCount: int) {
        Head = null
        AssignedPlanLocalWords = new ulong[]((planLocalCount + 63) >> 6)
        Count = 0
    }

    public func Copy(): ColumnarCodePlanStackState {
        result := new ColumnarCodePlanStackState(AssignedPlanLocalWords.Length * 64)
        result.Head = Head
        result.Count = Count
        i := 0
        while i < AssignedPlanLocalWords.Length {
            result.AssignedPlanLocalWords[i] = AssignedPlanLocalWords[i]
            i += 1
        }
        return result
    }

    public func Push(
        valueType: Type,
        isAddress: bool,
        valueKind: int,
        literalKnown: bool,
        literalValue: int) {
        Head = new ColumnarCodePlanStackNode(
            valueType,
            isAddress,
            valueKind,
            literalKnown,
            literalValue,
            Head)
        Count = Count + 1
    }

    public func Pop(): ColumnarCodePlanStackNode {
        value := Head
        if value == null {
            throw new InvalidOperationException("Columnar code-plan evaluation stack underflowed.")
        }
        Head = value.Previous
        Count = Count - 1
        return value
    }

    public func RefineTop(valueType: Type) {
        value := Head
        if value == null {
            throw new InvalidOperationException("Columnar code-plan evaluation stack underflowed.")
        }
        Head = new ColumnarCodePlanStackNode(
            valueType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0,
            value.Previous)
    }

    public func IsPlanLocalAssigned(localIndex: int): bool {
        wordIndex := localIndex >> 6
        bitIndex := localIndex & 63
        mask := (ulong)1 << bitIndex
        return (AssignedPlanLocalWords[wordIndex] & mask) != (ulong)0
    }

    public func MarkPlanLocalAssigned(localIndex: int) {
        wordIndex := localIndex >> 6
        bitIndex := localIndex & 63
        mask := (ulong)1 << bitIndex
        AssignedPlanLocalWords[wordIndex] = AssignedPlanLocalWords[wordIndex] | mask
    }
}

// Schema-v2 validation is deliberately split from execution. Every structural, reflection,
// control-flow, pool-usage, and stack-type fact is proven before the first ILGenerator call.
// Execution then uses a closed, explicit opcode mapping; it never reflects over OpCodes and never
// calls back into the legacy emitter.
public class ColumnarCodePlanExecutor {
    public static func Execute(plan: ColumnarCodePlan, il: ILGenerator) {
        Validate(plan)
        if il == null {
            throw new InvalidOperationException("Columnar code-plan IL generator cannot be null.")
        }

        if plan.SchemaVersion == ColumnarCodePlanContract.CurrentSchemaVersion() {
            ExecuteV1(plan, il)
            return
        }

        ExecuteV2(plan, il)
    }

    public static func Validate(plan: ColumnarCodePlan) {
        if plan == null {
            throw new InvalidOperationException("Columnar code plan cannot be null.")
        }

        plan.ValidateSealedStructure()
        if plan.SchemaVersion == ColumnarCodePlanContract.RecursiveSchemaVersion() {
            ValidateV2Semantics(plan)
        }
    }

    static func ExecuteV1(plan: ColumnarCodePlan, il: ILGenerator) {
        opCodeValue := plan.OpCodeValues[0]
        if opCodeValue == ColumnarCodePlanContract.LdcI4_0() {
            il.Emit(OpCodes.Ldc_I4_0)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_1() {
            il.Emit(OpCodes.Ldc_I4_1)
        }
    }

    static func ExecuteV2(plan: ColumnarCodePlan, il: ILGenerator) {
        // Trusted execution-context boundary: argument ordinals/types and ambient LocalBuilders
        // are captured by the N# planner from this same live method emitter. Public
        // Reflection.Emit exposes neither an ILGenerator target signature nor a LocalBuilder owner,
        // so those two associations cannot be rediscovered here. The plan is exclusively owned by
        // this compiler pipeline from validation through emission; concurrent mutation/replay is
        // outside this internal contract until schema ownership gains a first-class method context.
        // Validation has already completed. Consume before the first ILGenerator mutation so a
        // declaration or emission failure can never make this plan replayable.
        plan.ConsumeV2()

        planLocals := new LocalBuilder[](plan.PlanLocalCount)
        i := 0
        while i < plan.PlanLocalCount {
            planLocals[i] = il.DeclareLocal(plan.Types[plan.PlanLocalTypeIndices[i]])
            i += 1
        }

        labels := new Label[](plan.LabelCount)
        i = 0
        while i < plan.LabelCount {
            labels[i] = il.DefineLabel()
            i += 1
        }

        i = 0
        while i < plan.OperationCount {
            if plan.OperationKinds[i] == ColumnarCodePlanContract.MarkLabelOperation() {
                il.MarkLabel(labels[plan.OperandIndices[i]])
            } else {
                EmitInstruction(plan, il, planLocals, labels, i)
            }
            i += 1
        }
    }

    static func EmitInstruction(
        plan: ColumnarCodePlan,
        il: ILGenerator,
        planLocals: LocalBuilder[],
        labels: Label[],
        operationIndex: int) {
        opCodeValue := plan.OpCodeValues[operationIndex]
        operandKind := plan.OperandKinds[operationIndex]
        operandIndex := plan.OperandIndices[operationIndex]

        if operandKind == ColumnarCodePlanContract.NoOperand() {
            EmitWithoutOperand(il, opCodeValue)
        } else if operandKind == ColumnarCodePlanContract.Int32Operand() {
            il.Emit(OpCodes.Ldc_I4, plan.Int32Values[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.ArgumentOperand() {
            il.Emit(OpCodes.Ldarg, (short)plan.ArgumentOrdinals[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.AmbientLocalOperand() {
            EmitLocal(il, opCodeValue, plan.AmbientLocals[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.PlanLocalOperand() {
            EmitLocal(il, opCodeValue, planLocals[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.MethodOperand() {
            if opCodeValue == ColumnarCodePlanContract.Call() {
                il.Emit(OpCodes.Call, plan.Methods[operandIndex])
            } else {
                il.Emit(OpCodes.Callvirt, plan.Methods[operandIndex])
            }
        } else if operandKind == ColumnarCodePlanContract.ConstructorOperand() {
            il.Emit(OpCodes.Newobj, plan.Constructors[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.FieldOperand() {
            il.Emit(OpCodes.Ldfld, plan.Fields[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.LabelOperand() {
            if opCodeValue == ColumnarCodePlanContract.Br() {
                il.Emit(OpCodes.Br, labels[operandIndex])
            } else {
                il.Emit(OpCodes.Brfalse, labels[operandIndex])
            }
        } else if operandKind == ColumnarCodePlanContract.TypeOperand() {
            il.Emit(OpCodes.Ldelem, plan.Types[operandIndex])
        }
    }

    static func EmitWithoutOperand(il: ILGenerator, opCodeValue: short) {
        if opCodeValue == ColumnarCodePlanContract.LdcI4_M1() {
            il.Emit(OpCodes.Ldc_I4_M1)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_0() {
            il.Emit(OpCodes.Ldc_I4_0)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_1() {
            il.Emit(OpCodes.Ldc_I4_1)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_2() {
            il.Emit(OpCodes.Ldc_I4_2)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_3() {
            il.Emit(OpCodes.Ldc_I4_3)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_4() {
            il.Emit(OpCodes.Ldc_I4_4)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_5() {
            il.Emit(OpCodes.Ldc_I4_5)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_6() {
            il.Emit(OpCodes.Ldc_I4_6)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_7() {
            il.Emit(OpCodes.Ldc_I4_7)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_8() {
            il.Emit(OpCodes.Ldc_I4_8)
        } else if opCodeValue == ColumnarCodePlanContract.ConvI4() {
            il.Emit(OpCodes.Conv_I4)
        } else if opCodeValue == ColumnarCodePlanContract.Ldlen() {
            il.Emit(OpCodes.Ldlen)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemU1() {
            il.Emit(OpCodes.Ldelem_U1)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemU2() {
            il.Emit(OpCodes.Ldelem_U2)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemI4() {
            il.Emit(OpCodes.Ldelem_I4)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemU4() {
            il.Emit(OpCodes.Ldelem_U4)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemI8() {
            il.Emit(OpCodes.Ldelem_I8)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemR4() {
            il.Emit(OpCodes.Ldelem_R4)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemR8() {
            il.Emit(OpCodes.Ldelem_R8)
        } else if opCodeValue == ColumnarCodePlanContract.LdelemRef() {
            il.Emit(OpCodes.Ldelem_Ref)
        }
    }

    static func EmitLocal(il: ILGenerator, opCodeValue: short, local: LocalBuilder) {
        if opCodeValue == ColumnarCodePlanContract.Ldloc() {
            il.Emit(OpCodes.Ldloc, local)
        } else if opCodeValue == ColumnarCodePlanContract.Ldloca() {
            il.Emit(OpCodes.Ldloca, local)
        } else {
            il.Emit(OpCodes.Stloc, local)
        }
    }

    static func ValidateV2Semantics(plan: ColumnarCodePlan) {
        ValidateValuePools(plan)
        // Labels have no backing schema column. Prove their maximum count before allocating any
        // label-indexed validation state: each valid label consumes one mark row and at least one
        // distinct branch row.
        if plan.LabelCount > plan.OperationCount / 2 {
            throw new InvalidOperationException("Schema-v2 label count exceeds its operation-row bound.")
        }

        usedTypes := new bool[](plan.TypeCount)
        usedInt32 := new bool[](plan.Int32Count)
        usedArguments := new bool[](plan.ArgumentCount)
        usedAmbientLocals := new bool[](plan.AmbientLocalCount)
        usedMethods := new bool[](plan.MethodCount)
        usedConstructors := new bool[](plan.ConstructorCount)
        usedFields := new bool[](plan.FieldCount)
        usedPlanLocals := new bool[](plan.PlanLocalCount)
        labelMarkIndices := new int[](plan.LabelCount)
        labelMarkOwners := new int[](plan.LabelCount)
        labelReferenced := new bool[](plan.LabelCount)

        i := 0
        while i < plan.LabelCount {
            labelMarkIndices[i] = -1
            labelMarkOwners[i] = -1
            i += 1
        }
        i = 0
        while i < plan.ArgumentCount {
            usedTypes[plan.ArgumentTypeIndices[i]] = true
            i += 1
        }
        i = 0
        while i < plan.PlanLocalCount {
            usedTypes[plan.PlanLocalTypeIndices[i]] = true
            i += 1
        }

        i = 0
        while i < plan.OperationCount {
            operandKind := plan.OperandKinds[i]
            operandIndex := plan.OperandIndices[i]
            if operandKind == ColumnarCodePlanContract.TypeOperand() {
                usedTypes[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.Int32Operand() {
                usedInt32[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.ArgumentOperand() {
                usedArguments[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.AmbientLocalOperand() {
                usedAmbientLocals[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.MethodOperand() {
                usedMethods[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.ConstructorOperand() {
                usedConstructors[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.FieldOperand() {
                usedFields[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.PlanLocalOperand() {
                usedPlanLocals[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.LabelOperand() {
                if plan.OperationKinds[i] == ColumnarCodePlanContract.MarkLabelOperation() {
                    if labelMarkIndices[operandIndex] >= 0 {
                        throw new InvalidOperationException("A schema-v2 label must be marked exactly once.")
                    }
                    labelMarkIndices[operandIndex] = i
                    labelMarkOwners[operandIndex] = plan.OperationOwnerFragmentIndices[i]
                } else {
                    labelReferenced[operandIndex] = true
                }
            }
            i += 1
        }

        i = 0
        while i < plan.OperationCount {
            if plan.OperandKinds[i] == ColumnarCodePlanContract.LabelOperand()
                && plan.OperationKinds[i] == ColumnarCodePlanContract.EmitInstructionOperation() {
                labelIndex := plan.OperandIndices[i]
                if labelMarkIndices[labelIndex] <= i {
                    throw new InvalidOperationException("Schema-v2 branches must target a forward label.")
                }
                if labelMarkOwners[labelIndex] != plan.OperationOwnerFragmentIndices[i] {
                    throw new InvalidOperationException("Schema-v2 branches and labels must have the same fragment owner.")
                }
            }
            i += 1
        }

        ValidateAllUsed(usedTypes, "type")
        ValidateAllUsed(usedInt32, "Int32")
        ValidateAllUsed(usedArguments, "argument")
        ValidateAllUsed(usedAmbientLocals, "ambient local")
        ValidateAllUsed(usedMethods, "method")
        ValidateAllUsed(usedConstructors, "constructor")
        ValidateAllUsed(usedFields, "field")
        ValidateAllUsed(usedPlanLocals, "plan local")
        i = 0
        while i < plan.LabelCount {
            if labelMarkIndices[i] < 0 || !labelReferenced[i] {
                throw new InvalidOperationException("Every schema-v2 label must be marked once and referenced by a branch.")
            }
            i += 1
        }

        ValidateControlFlowAndFragments(plan, labelMarkIndices)
    }

    static func ValidateValuePools(plan: ColumnarCodePlan) {
        i := 0
        while i < plan.TypeCount {
            ValidateStorableType(plan.Types[i], "type pool")
            i += 1
        }

        maximumArgumentOrdinal := -1
        i = 0
        while i < plan.ArgumentCount {
            if plan.ArgumentOrdinals[i] > maximumArgumentOrdinal {
                maximumArgumentOrdinal = plan.ArgumentOrdinals[i]
            }
            i += 1
        }
        usedArgumentOrdinals := new bool[](maximumArgumentOrdinal + 1)
        i = 0
        while i < plan.ArgumentCount {
            argumentType := plan.Types[plan.ArgumentTypeIndices[i]]
            ValidateStorableType(argumentType, "argument")
            ordinal := plan.ArgumentOrdinals[i]
            if usedArgumentOrdinals[ordinal] {
                throw new InvalidOperationException("Schema-v2 argument ordinals must be unique.")
            }
            usedArgumentOrdinals[ordinal] = true
            i += 1
        }

        i = 0
        while i < plan.AmbientLocalCount {
            localType := plan.AmbientLocals[i].get_LocalType()
            ValidateStorableType(localType, "ambient local")
            i += 1
        }

        i = 0
        while i < plan.PlanLocalCount {
            ValidateStorableType(plan.Types[plan.PlanLocalTypeIndices[i]], "plan local")
            i += 1
        }

        i = 0
        while i < plan.MethodCount {
            ValidateMethod(plan.Methods[i])
            i += 1
        }
        i = 0
        while i < plan.ConstructorCount {
            ValidateConstructor(plan.Constructors[i])
            i += 1
        }
        i = 0
        while i < plan.FieldCount {
            ValidateField(plan.Fields[i])
            i += 1
        }
        i = 0
        while i < plan.FragmentCount {
            ValidateStorableType(plan.FragmentResultTypes[i], "fragment result")
            i += 1
        }
    }

    static func ValidateMethod(method: MethodInfo) {
        if method.get_IsGenericMethodDefinition() {
            throw new InvalidOperationException("Schema-v2 method handles cannot be generic method definitions.")
        }
        if (((int)method.get_CallingConvention())
                & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0 {
            throw new InvalidOperationException("Schema-v2 method handles cannot use the VarArgs calling convention.")
        }
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("Schema-v2 methods must have an exact declaring type.")
        }
        ValidateStorableType(declaringType, "method receiver")
        signatureMethod := GetMethodSignatureDefinition(method)
        genericArguments := method.GetGenericArguments()
        returnType := ResolveMethodSignatureType(
            signatureMethod.get_ReturnType(),
            genericArguments)
        ValidateStorableType(returnType, "method return")
        parameters := signatureMethod.GetParameters()
        i := 0
        while i < parameters.Length {
            parameterType := ResolveMethodSignatureType(
                parameters[i].get_ParameterType(),
                genericArguments)
            ValidateStorableType(parameterType, "method argument")
            i += 1
        }
    }

    static func ValidateConstructor(constructorInfo: ConstructorInfo) {
        declaringType := constructorInfo.get_DeclaringType()
        if declaringType == null
            || constructorInfo.get_IsStatic()
            || declaringType.get_IsAbstract() {
            throw new InvalidOperationException("Schema-v2 constructors must be instance constructors with an exact declaring type.")
        }
        if (((int)constructorInfo.get_CallingConvention())
                & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0 {
            throw new InvalidOperationException("Schema-v2 constructors cannot use the VarArgs calling convention.")
        }
        ValidateStorableType(declaringType, "constructor result")
        parameters := constructorInfo.GetParameters()
        i := 0
        while i < parameters.Length {
            ValidateStorableType(parameters[i].get_ParameterType(), "constructor argument")
            i += 1
        }
    }

    static func ValidateField(field: FieldInfo) {
        declaringType := field.get_DeclaringType()
        if declaringType == null || field.get_IsStatic() {
            throw new InvalidOperationException("Schema-v2 ldfld handles must name instance fields with an exact declaring type.")
        }
        ValidateStorableType(declaringType, "field receiver")
        ValidateStorableType(field.get_FieldType(), "field result")
    }

    static func ValidateStorableType(valueType: Type, role: string) {
        if valueType.FullName == "System.Void" {
            throw new InvalidOperationException("Schema-v2 " + role + " types cannot be void.")
        }
        if valueType.get_IsByRef() {
            throw new InvalidOperationException("Schema-v2 " + role + " types cannot be null, void, or by-reference.")
        }
        if valueType.get_IsGenericTypeDefinition() {
            throw new InvalidOperationException("Schema-v2 " + role + " types cannot be generic type definitions.")
        }
    }

    static func ValidateAllUsed(used: bool[], poolName: string) {
        i := 0
        while i < used.Length {
            if !used[i] {
                throw new InvalidOperationException("Schema-v2 " + poolName + " pool contains hidden unused state.")
            }
            i += 1
        }
    }

    static func ValidateControlFlowAndFragments(plan: ColumnarCodePlan, labelMarkIndices: int[]) {
        stateCapacity := plan.OperationCount + 1
        states := new ColumnarCodePlanStackState[](stateCapacity)
        states[0] = new ColumnarCodePlanStackState(plan.PlanLocalCount)
        startingFragmentHeads := new int[](stateCapacity)
        startingFragmentNext := new int[](plan.FragmentCount)
        endingFragmentHeads := new int[](stateCapacity)
        endingFragmentNext := new int[](plan.FragmentCount)
        fragmentEntryHeads := new ColumnarCodePlanStackNode?[](plan.FragmentCount)
        fragmentEntryCounts := new int[](plan.FragmentCount)
        fragmentEntryCaptured := new bool[](plan.FragmentCount)

        i := 0
        while i < stateCapacity {
            startingFragmentHeads[i] = -1
            endingFragmentHeads[i] = -1
            i += 1
        }
        i = 0
        while i < plan.FragmentCount {
            fragmentStart := plan.FragmentOperationStarts[i]
            fragmentEnd := plan.FragmentOperationStarts[i] + plan.FragmentOperationCounts[i]
            startingFragmentNext[i] = startingFragmentHeads[fragmentStart]
            startingFragmentHeads[fragmentStart] = i
            endingFragmentNext[i] = endingFragmentHeads[fragmentEnd]
            endingFragmentHeads[fragmentEnd] = i
            i += 1
        }

        i = 0
        while i < plan.OperationCount {
            input := states[i]
            if input == null {
                throw new InvalidOperationException("Schema-v2 operation stream contains unreachable instructions.")
            }
            ValidateAndRefineEndingFragments(
                plan,
                states,
                endingFragmentHeads,
                endingFragmentNext,
                fragmentEntryHeads,
                fragmentEntryCounts,
                fragmentEntryCaptured,
                i)
            CaptureStartingFragments(
                input,
                startingFragmentHeads,
                startingFragmentNext,
                fragmentEntryHeads,
                fragmentEntryCounts,
                fragmentEntryCaptured,
                i)

            output := input
            if plan.OperationKinds[i] == ColumnarCodePlanContract.EmitInstructionOperation() {
                ApplyInstruction(plan, i, output)
            }

            opCodeValue := plan.OpCodeValues[i]
            if opCodeValue == ColumnarCodePlanContract.Br() {
                labelIndex := plan.OperandIndices[i]
                MergeState(states, labelMarkIndices[labelIndex], output)
            } else if opCodeValue == ColumnarCodePlanContract.Brfalse() {
                labelIndex := plan.OperandIndices[i]
                MergeState(states, labelMarkIndices[labelIndex], output.Copy())
                MergeState(states, i + 1, output)
            } else {
                MergeState(states, i + 1, output)
            }
            i += 1
        }

        if states[plan.OperationCount] == null {
            throw new InvalidOperationException("Schema-v2 operation stream has no reachable result.")
        }
        ValidateAndRefineEndingFragments(
            plan,
            states,
            endingFragmentHeads,
            endingFragmentNext,
            fragmentEntryHeads,
            fragmentEntryCounts,
            fragmentEntryCaptured,
            plan.OperationCount)

        rootExit := states[plan.OperationCount]
        rootValue := rootExit.Head
        if rootExit.Count != 1
            || rootValue == null
            || rootValue.IsAddress
            || !IsStackCompatible(
                plan.ResultType,
                rootValue.ValueType,
                rootValue.ValueKind,
                rootValue.LiteralKnown,
                rootValue.LiteralValue) {
            throw new InvalidOperationException("Schema-v2 root execution must leave exactly its declared result.")
        }
    }

    static func CaptureStartingFragments(
        state: ColumnarCodePlanStackState,
        startingFragmentHeads: int[],
        startingFragmentNext: int[],
        fragmentEntryHeads: ColumnarCodePlanStackNode?[],
        fragmentEntryCounts: int[],
        fragmentEntryCaptured: bool[],
        boundaryIndex: int) {
        fragmentIndex := startingFragmentHeads[boundaryIndex]
        while fragmentIndex >= 0 {
            fragmentEntryHeads[fragmentIndex] = state.Head
            fragmentEntryCounts[fragmentIndex] = state.Count
            fragmentEntryCaptured[fragmentIndex] = true
            fragmentIndex = startingFragmentNext[fragmentIndex]
        }
    }

    static func ValidateAndRefineEndingFragments(
        plan: ColumnarCodePlan,
        states: ColumnarCodePlanStackState[],
        endingFragmentHeads: int[],
        endingFragmentNext: int[],
        fragmentEntryHeads: ColumnarCodePlanStackNode?[],
        fragmentEntryCounts: int[],
        fragmentEntryCaptured: bool[],
        boundaryIndex: int) {
        fragmentIndex := endingFragmentHeads[boundaryIndex]
        while fragmentIndex >= 0 {
            exitState := states[boundaryIndex]
            if exitState == null {
                throw new InvalidOperationException("Every schema-v2 fragment must have a reachable exit.")
            }
            entryCount := fragmentEntryCounts[fragmentIndex]
            resultValue := exitState.Head
            if !fragmentEntryCaptured[fragmentIndex]
                || resultValue == null
                || exitState.Count != entryCount + 1
                || resultValue.Previous != fragmentEntryHeads[fragmentIndex] {
                throw new InvalidOperationException("Every schema-v2 fragment must add exactly one reachable stack value.")
            }
            resultType := plan.FragmentResultTypes[fragmentIndex]
            if resultValue.IsAddress
                || !IsStackCompatible(
                    resultType,
                    resultValue.ValueType,
                    resultValue.ValueKind,
                    resultValue.LiteralKnown,
                    resultValue.LiteralValue) {
                throw new InvalidOperationException("A schema-v2 fragment result does not match its declared type.")
            }
            // Fragment metadata is the semantic type boundary for literal-I4 values and
            // reference upcasts. Parent operations consume the declared type, never a raw
            // verification-stack category left behind by a child.
            exitState.RefineTop(resultType)
            fragmentIndex = endingFragmentNext[fragmentIndex]
        }
    }

    static func MergeState(
        states: ColumnarCodePlanStackState[],
        targetIndex: int,
        incoming: ColumnarCodePlanStackState) {
        existing := states[targetIndex]
        if existing == null {
            states[targetIndex] = incoming
            return
        }
        if existing.Count != incoming.Count {
            throw new InvalidOperationException("Schema-v2 control-flow stack depths do not merge.")
        }
        MergeStack(existing, incoming)

        i := 0
        while i < existing.AssignedPlanLocalWords.Length {
            existing.AssignedPlanLocalWords[i] =
                existing.AssignedPlanLocalWords[i] & incoming.AssignedPlanLocalWords[i]
            i += 1
        }
    }

    static func MergeStack(
        target: ColumnarCodePlanStackState,
        incoming: ColumnarCodePlanStackState) {
        if target.Head == incoming.Head {
            return
        }

        divergentCount := 0
        left := target.Head
        right := incoming.Head
        while left != right {
            if left == null || right == null {
                throw new InvalidOperationException("Schema-v2 control-flow stack shapes do not merge.")
            }
            divergentCount += 1
            left = left.Previous
            right = right.Previous
        }

        mergedSlots := new ColumnarCodePlanStackNode[](divergentCount)
        left = target.Head
        right = incoming.Head
        slotIndex := 0
        while slotIndex < divergentCount {
            if left == null || right == null {
                throw new InvalidOperationException("Schema-v2 control-flow stack shapes do not merge.")
            }
            mergedSlots[slotIndex] = MergeStackSlot(left, right)
            left = left.Previous
            right = right.Previous
            slotIndex += 1
        }

        mergedHead := left
        slotIndex = divergentCount - 1
        while slotIndex >= 0 {
            slot := mergedSlots[slotIndex]
            mergedHead = new ColumnarCodePlanStackNode(
                slot.ValueType,
                slot.IsAddress,
                slot.ValueKind,
                slot.LiteralKnown,
                slot.LiteralValue,
                mergedHead)
            slotIndex -= 1
        }
        target.Head = mergedHead
    }

    static func MergeStackSlot(
        left: ColumnarCodePlanStackNode,
        right: ColumnarCodePlanStackNode): ColumnarCodePlanStackNode {
        if left.IsAddress != right.IsAddress {
            throw new InvalidOperationException("Schema-v2 control-flow address states do not merge.")
        }
        if left.IsAddress {
            if left.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || right.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || !ExactTypeShapeMatches(left.ValueType, right.ValueType) {
                throw new InvalidOperationException("Schema-v2 control-flow address types do not merge.")
            }
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                true,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }

        if left.ValueKind == right.ValueKind {
            if left.ValueKind == ColumnarCodePlanStackValueKind.Exact() {
                return new ColumnarCodePlanStackNode(
                    MergeExactStackType(left.ValueType, right.ValueType),
                    false,
                    ColumnarCodePlanStackValueKind.Exact(),
                    false,
                    0,
                    null)
            }
            if !ExactTypeShapeMatches(left.ValueType, right.ValueType) {
                throw new InvalidOperationException("Schema-v2 control-flow stack categories do not merge.")
            }
            literalKnown := left.LiteralKnown
                && right.LiteralKnown
                && left.LiteralValue == right.LiteralValue
            literalValue := literalKnown ? left.LiteralValue : 0
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                false,
                left.ValueKind,
                literalKnown,
                literalValue,
                null)
        }

        if left.ValueKind == ColumnarCodePlanStackValueKind.LiteralI4()
            && right.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && IsLiteralI4Destination(
                right.ValueType,
                left.LiteralKnown,
                left.LiteralValue) {
            return new ColumnarCodePlanStackNode(
                right.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }
        if right.ValueKind == ColumnarCodePlanStackValueKind.LiteralI4()
            && left.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && IsLiteralI4Destination(
                left.ValueType,
                right.LiteralKnown,
                right.LiteralValue) {
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }
        throw new InvalidOperationException("Schema-v2 control-flow stack categories do not merge.")
    }

    static func MergeExactStackType(left: Type, right: Type): Type {
        if ExactTypeShapeMatches(left, right) {
            return left
        }
        if !left.get_IsValueType() && !right.get_IsValueType() {
            if left.IsAssignableFrom(right) {
                return left
            }
            if right.IsAssignableFrom(left) {
                return right
            }
        }
        throw new InvalidOperationException("Schema-v2 control-flow value types do not merge.")
    }

    static func ApplyInstruction(
        plan: ColumnarCodePlan,
        operationIndex: int,
        state: ColumnarCodePlanStackState) {
        opCodeValue := plan.OpCodeValues[operationIndex]
        operandIndex := plan.OperandIndices[operationIndex]

        if opCodeValue >= ColumnarCodePlanContract.LdcI4_M1()
            && opCodeValue <= ColumnarCodePlanContract.LdcI4_8() {
            literalValue := -1
            if opCodeValue != ColumnarCodePlanContract.LdcI4_M1() {
                literalValue = (int)opCodeValue - (int)ColumnarCodePlanContract.LdcI4_0()
            }
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.LiteralI4(),
                true,
                literalValue)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4() {
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.LiteralI4(),
                true,
                plan.Int32Values[operandIndex])
        } else if opCodeValue == ColumnarCodePlanContract.Ldarg() {
            argumentType := plan.Types[plan.ArgumentTypeIndices[operandIndex]]
            state.Push(
                argumentType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if ColumnarCodePlanContract.IsLocalOpcode(opCodeValue) {
            localType := LocalType(plan, operationIndex)
            ApplyLocal(plan, operationIndex, opCodeValue, localType, state)
        } else if opCodeValue == ColumnarCodePlanContract.Call()
            || opCodeValue == ColumnarCodePlanContract.Callvirt() {
            ApplyMethodCall(plan.Methods[operandIndex], opCodeValue, state)
        } else if opCodeValue == ColumnarCodePlanContract.Newobj() {
            ApplyConstructor(plan.Constructors[operandIndex], state)
        } else if opCodeValue == ColumnarCodePlanContract.Ldfld() {
            ApplyField(plan.Fields[operandIndex], state)
        } else if opCodeValue == ColumnarCodePlanContract.Br() {
            return
        } else if opCodeValue == ColumnarCodePlanContract.Brfalse() {
            value := state.Pop()
            if value.IsAddress
                || !IsBooleanCondition(
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException("Schema-v2 brfalse requires an exact Boolean condition or literal I4.")
            }
        } else if opCodeValue == ColumnarCodePlanContract.ConvI4() {
            value := state.Pop()
            if value.IsAddress
                || !CanConvertToI4(
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown) {
                throw new InvalidOperationException("Schema-v2 conv.i4 requires literal I4, native length, or exact Int32.")
            }
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ldlen() {
            arrayValue := state.Pop()
            RequireSzArray(arrayValue.ValueType, arrayValue.IsAddress)
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.NativeUnsigned(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ldelem()
            || opCodeValue == ColumnarCodePlanContract.LdelemU1()
            || opCodeValue == ColumnarCodePlanContract.LdelemU2()
            || opCodeValue == ColumnarCodePlanContract.LdelemI4()
            || opCodeValue == ColumnarCodePlanContract.LdelemU4()
            || opCodeValue == ColumnarCodePlanContract.LdelemI8()
            || opCodeValue == ColumnarCodePlanContract.LdelemR4()
            || opCodeValue == ColumnarCodePlanContract.LdelemR8()
            || opCodeValue == ColumnarCodePlanContract.LdelemRef() {
            if opCodeValue == ColumnarCodePlanContract.Ldelem() {
                ApplyArrayElementLoad(opCodeValue, plan.Types[operandIndex], true, state)
            } else {
                ApplyArrayElementLoad(opCodeValue, typeof(object), false, state)
            }
        }
    }

    static func LocalType(plan: ColumnarCodePlan, operationIndex: int): Type {
        operandIndex := plan.OperandIndices[operationIndex]
        if plan.OperandKinds[operationIndex] == ColumnarCodePlanContract.AmbientLocalOperand() {
            return plan.AmbientLocals[operandIndex].get_LocalType()
        }
        return plan.Types[plan.PlanLocalTypeIndices[operandIndex]]
    }

    static func ApplyLocal(
        plan: ColumnarCodePlan,
        operationIndex: int,
        opCodeValue: short,
        localType: Type,
        state: ColumnarCodePlanStackState) {
        isPlanLocal := plan.OperandKinds[operationIndex]
            == ColumnarCodePlanContract.PlanLocalOperand()
        localIndex := plan.OperandIndices[operationIndex]
        if opCodeValue == ColumnarCodePlanContract.Ldloc() {
            if isPlanLocal && !state.IsPlanLocalAssigned(localIndex) {
                throw new InvalidOperationException("Schema-v2 plan locals must be assigned before ldloc.")
            }
            state.Push(
                localType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ldloca() {
            if isPlanLocal && !state.IsPlanLocalAssigned(localIndex) {
                throw new InvalidOperationException("Schema-v2 plan locals must be assigned before ldloca.")
            }
            state.Push(
                localType,
                true,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else {
            value := state.Pop()
            if value.IsAddress
                || !IsStackCompatible(
                    localType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException("Schema-v2 stloc value does not match its local type.")
            }
            if isPlanLocal {
                state.MarkPlanLocalAssigned(localIndex)
            }
        }
    }

    static func ApplyMethodCall(method: MethodInfo, opCodeValue: short, state: ColumnarCodePlanStackState) {
        isStatic := method.get_IsStatic()
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("Schema-v2 call method has no declaring type.")
        }
        if opCodeValue == ColumnarCodePlanContract.Callvirt()
            && (isStatic || declaringType.get_IsValueType()) {
            throw new InvalidOperationException("Schema-v2 callvirt requires a reference-type instance method.")
        }
        if opCodeValue == ColumnarCodePlanContract.Call() && method.get_IsAbstract() {
            throw new InvalidOperationException("Schema-v2 call cannot target an abstract method.")
        }

        signatureMethod := GetMethodSignatureDefinition(method)
        genericArguments := method.GetGenericArguments()
        parameters := signatureMethod.GetParameters()
        parameterIndex := parameters.Length - 1
        while parameterIndex >= 0 {
            value := state.Pop()
            parameterType := ResolveMethodSignatureType(
                parameters[parameterIndex].get_ParameterType(),
                genericArguments)
            if value.IsAddress
                || !IsStackCompatible(
                    parameterType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException("Schema-v2 call argument does not match its exact parameter type.")
            }
            parameterIndex -= 1
        }

        if !isStatic {
            receiver := state.Pop()
            ValidateReceiver(
                declaringType,
                receiver.ValueType,
                receiver.IsAddress,
                receiver.ValueKind)
        }
        state.Push(
            ResolveMethodSignatureType(
                signatureMethod.get_ReturnType(),
                genericArguments),
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func GetMethodSignatureDefinition(method: MethodInfo): MethodInfo {
        if !method.get_IsGenericMethod() {
            return method
        }
        definition := method.GetGenericMethodDefinition()
        definitionArguments := definition.GetGenericArguments()
        constructedArguments := method.GetGenericArguments()
        if !definition.get_IsGenericMethodDefinition()
            || definitionArguments.Length != constructedArguments.Length {
            throw new InvalidOperationException("Schema-v2 constructed generic method identity is invalid.")
        }
        return definition
    }

    // MethodBuilderInstantiation intentionally exposes its generic definition's raw
    // parameter and return shapes when an argument is an unbaked TypeBuilder parameter.
    // Rebuild the signature from that definition and the constructed handle's exact
    // arguments so stack validation never depends on Reflection.Emit wrapper identity.
    static func ResolveMethodSignatureType(
        signatureType: Type,
        methodArguments: Type[]): Type {
        if signatureType.get_IsGenericParameter() {
            if signatureType.get_DeclaringMethod() == null {
                return signatureType
            }
            position := signatureType.get_GenericParameterPosition()
            if position < 0 || position >= methodArguments.Length {
                throw new InvalidOperationException("Schema-v2 method generic parameter position is invalid.")
            }
            return methodArguments[position]
        }
        if signatureType.get_IsSZArray() {
            elementType := signatureType.GetElementType()
            if elementType == null {
                throw new InvalidOperationException("Schema-v2 method array signature has no element type.")
            }
            return ResolveMethodSignatureType(elementType, methodArguments).MakeArrayType()
        }
        if signatureType.get_IsGenericType()
            && !signatureType.get_IsGenericTypeDefinition() {
            definition := signatureType.GetGenericTypeDefinition()
            signatureArguments := signatureType.GetGenericArguments()
            resolvedArguments := new Type[](signatureArguments.Length)
            i := 0
            while i < signatureArguments.Length {
                resolvedArguments[i] = ResolveMethodSignatureType(
                    signatureArguments[i],
                    methodArguments)
                i += 1
            }
            return definition.MakeGenericType(resolvedArguments)
        }
        compoundElement := signatureType.GetElementType()
        if compoundElement != null {
            resolvedElement := ResolveMethodSignatureType(compoundElement, methodArguments)
            if !ExactTypeShapeMatches(compoundElement, resolvedElement) {
                throw new InvalidOperationException("Schema-v2 cannot substitute this compound method signature shape.")
            }
        }
        return signatureType
    }

    static func ApplyConstructor(
        constructorInfo: ConstructorInfo,
        state: ColumnarCodePlanStackState) {
        parameters := constructorInfo.GetParameters()
        parameterIndex := parameters.Length - 1
        while parameterIndex >= 0 {
            value := state.Pop()
            parameterType := parameters[parameterIndex].get_ParameterType()
            if value.IsAddress
                || !IsStackCompatible(
                    parameterType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException("Schema-v2 constructor argument does not match its exact parameter type.")
            }
            parameterIndex -= 1
        }
        declaringType := constructorInfo.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("Schema-v2 constructor has no declaring type.")
        }
        state.Push(
            declaringType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func ApplyField(field: FieldInfo, state: ColumnarCodePlanStackState) {
        receiver := state.Pop()
        declaringType := field.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("Schema-v2 field has no declaring type.")
        }
        ValidateReceiver(
            declaringType,
            receiver.ValueType,
            receiver.IsAddress,
            receiver.ValueKind)
        state.Push(
            field.get_FieldType(),
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func ValidateReceiver(
        expectedType: Type,
        actualType: Type,
        isAddress: bool,
        actualKind: int) {
        if actualKind != ColumnarCodePlanStackValueKind.Exact() {
            throw new InvalidOperationException("Schema-v2 receivers must have an exact semantic type.")
        }
        if expectedType.get_IsValueType() {
            if !isAddress || !ExactTypeShapeMatches(expectedType, actualType) {
                throw new InvalidOperationException("Schema-v2 value-type receivers require an exact managed address.")
            }
        } else if isAddress
            || !IsStackCompatible(expectedType, actualType, actualKind, false, 0) {
            throw new InvalidOperationException("Schema-v2 reference receiver does not match its declaring type.")
        }
    }

    static func ApplyArrayElementLoad(
        opCodeValue: short,
        requestedType: Type,
        hasRequestedType: bool,
        state: ColumnarCodePlanStackState) {
        indexValue := state.Pop()
        if indexValue.IsAddress
            || !IsArrayIndex(
                indexValue.ValueType,
                indexValue.ValueKind,
                indexValue.LiteralKnown) {
            throw new InvalidOperationException("Schema-v2 array element loads require exact Int32 or literal I4 index.")
        }
        arrayValue := state.Pop()
        arrayType := arrayValue.ValueType
        elementType := RequireSzArray(arrayType, arrayValue.IsAddress)

        if opCodeValue == ColumnarCodePlanContract.Ldelem() {
            if !hasRequestedType || !ExactTypeShapeMatches(requestedType, elementType) {
                throw new InvalidOperationException("Schema-v2 ldelem type operands must exactly match the array element type.")
            }
        } else if !TypedElementOpcodeMatches(opCodeValue, elementType) {
            throw new InvalidOperationException("Schema-v2 typed ldelem opcode does not match the array element type.")
        }
        state.Push(
            elementType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func RequireSzArray(arrayType: Type, isAddress: bool): Type {
        if isAddress || arrayType == null || !arrayType.get_IsSZArray() {
            throw new InvalidOperationException("Schema-v2 array operations require a single-dimensional zero-based array value.")
        }
        elementType := arrayType.GetElementType()
        if elementType == null {
            throw new InvalidOperationException("Schema-v2 array type has no element type.")
        }
        ValidateStorableType(elementType, "array element")
        return elementType
    }

    static func TypedElementOpcodeMatches(opCodeValue: short, elementType: Type): bool {
        if opCodeValue == ColumnarCodePlanContract.LdelemU1() {
            return elementType == typeof(bool)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemU2() {
            return elementType == typeof(char)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemI4() {
            return elementType == typeof(int)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemU4() {
            return elementType == typeof(uint)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemI8() {
            return elementType == typeof(long) || elementType == typeof(ulong)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemR4() {
            return elementType == typeof(float)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemR8() {
            return elementType == typeof(double)
        }
        if opCodeValue == ColumnarCodePlanContract.LdelemRef() {
            return !elementType.get_IsValueType()
                && !elementType.get_IsGenericParameter()
        }
        return false
    }

    static func IsStackCompatible(
        expectedType: Type?,
        actualType: Type,
        actualKind: int,
        literalKnown: bool,
        literalValue: int): bool {
        if expectedType == null {
            return false
        }
        if actualKind == ColumnarCodePlanStackValueKind.LiteralI4() {
            return IsLiteralI4Destination(expectedType, literalKnown, literalValue)
        }
        if actualKind != ColumnarCodePlanStackValueKind.Exact() {
            return false
        }
        if ExactTypeShapeMatches(expectedType, actualType) {
            return true
        }
        return !expectedType.get_IsValueType()
            && !actualType.get_IsValueType()
            && expectedType.IsAssignableFrom(actualType)
    }

    // Reflection.Emit creates fresh SymbolType and TypeBuilderInstantiation wrappers
    // around the same unbaked generic arguments. Wrapper shells compare structurally;
    // ordinary types and the generic arguments themselves retain exact identity.
    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        if left == right {
            return true
        }
        if left.get_IsSZArray() && right.get_IsSZArray() {
            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null
                && rightElement != null
                && ExactTypeShapeMatches(leftElement, rightElement)
        }
        if !left.get_IsGenericType()
            || !right.get_IsGenericType()
            || left.get_IsGenericTypeDefinition()
            || right.get_IsGenericTypeDefinition()
            || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }
        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }
        i := 0
        while i < leftArguments.Length {
            if !ExactTypeShapeMatches(leftArguments[i], rightArguments[i]) {
                return false
            }
            i += 1
        }
        return true
    }

    static func IsArrayIndex(valueType: Type, valueKind: int, literalKnown: bool): bool {
        return (valueKind == ColumnarCodePlanStackValueKind.LiteralI4() && literalKnown)
            || (valueKind == ColumnarCodePlanStackValueKind.Exact()
                && valueType == typeof(int))
    }

    static func IsBooleanCondition(
        valueType: Type,
        valueKind: int,
        literalKnown: bool,
        literalValue: int): bool {
        return (valueKind == ColumnarCodePlanStackValueKind.LiteralI4()
                && literalKnown
                && (literalValue == 0 || literalValue == 1))
            || (valueKind == ColumnarCodePlanStackValueKind.Exact()
                && valueType == typeof(bool))
    }

    static func CanConvertToI4(valueType: Type, valueKind: int, literalKnown: bool): bool {
        return (valueKind == ColumnarCodePlanStackValueKind.LiteralI4() && literalKnown)
            || valueKind == ColumnarCodePlanStackValueKind.NativeUnsigned()
            || (valueKind == ColumnarCodePlanStackValueKind.Exact()
                && (valueType == typeof(int)
                    || valueType == typeof(byte)
                    || valueType == typeof(sbyte)
                    || valueType == typeof(short)
                    || valueType == typeof(ushort)
                    || valueType == typeof(char)
                    || (valueType.get_IsEnum()
                        && valueType.GetEnumUnderlyingType() == typeof(int))))
    }

    static func IsLiteralI4Destination(
        valueType: Type,
        literalKnown: bool,
        literalValue: int): bool {
        if valueType == typeof(int) || valueType == typeof(uint) {
            return true
        }
        if valueType.get_IsEnum() {
            return valueType.GetEnumUnderlyingType() == typeof(int)
        }
        if !literalKnown {
            return false
        }
        if valueType == typeof(bool) {
            return literalValue == 0 || literalValue == 1
        }
        if valueType == typeof(byte) {
            return literalValue >= 0 && literalValue <= 255
        }
        if valueType == typeof(sbyte) {
            return literalValue >= -128 && literalValue <= 127
        }
        if valueType == typeof(short) {
            return literalValue >= -32768 && literalValue <= 32767
        }
        if valueType == typeof(ushort) || valueType == typeof(char) {
            return literalValue >= 0 && literalValue <= 65535
        }
        return false
    }
}

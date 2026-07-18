namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

class ColumnarCodePlanStackValueKind {
    public static func Exact(): int { return 0 }
    public static func LiteralI4(): int { return 1 }
    public static func NativeUnsigned(): int { return 2 }
    public static func I8Slot(): int { return 3 }
    public static func BoxedExact(): int { return 4 }
    public static func NullReference(): int { return 5 }
    public static func UnassignedPlanLocalAddress(): int { return 6 }
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
    public DuplicateOf: ColumnarCodePlanStackNode?
    public PlanLocalAddressIndex: int

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
        DuplicateOf = null
        PlanLocalAddressIndex = -1
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

    public func PushPlanLocalAddress(
        valueType: Type,
        valueKind: int,
        literalKnown: bool,
        literalValue: int,
        planLocalAddressIndex: int) {
        node := new ColumnarCodePlanStackNode(
            valueType,
            true,
            valueKind,
            literalKnown,
            literalValue,
            Head)
        node.PlanLocalAddressIndex = planLocalAddressIndex
        Head = node
        Count = Count + 1
    }

    public func PushDuplicate(value: ColumnarCodePlanStackNode) {
        if value != Head {
            throw new InvalidOperationException(
                "Columnar code-plan dup origin must be the current stack head.")
        }
        duplicate := new ColumnarCodePlanStackNode(
            value.ValueType,
            value.IsAddress,
            value.ValueKind,
            value.LiteralKnown,
            value.LiteralValue,
            Head)
        duplicate.DuplicateOf = value
        Head = duplicate
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
        refined := new ColumnarCodePlanStackNode(
            valueType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0,
            value.Previous)
        // A child fragment is a semantic type boundary, not a new evaluation-stack value.
        // Preserve dup provenance across the refinement so initializer stores can still prove
        // that their receiver is the duplicate of the enclosing construction result.
        refined.DuplicateOf = value.DuplicateOf
        Head = refined
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

// Recursive-plan validation is deliberately split from execution. Every structural, reflection,
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
        if plan.SchemaVersion == ColumnarCodePlanContract.RecursiveSchemaVersion() {
            ExecuteV2(plan, il)
            return
        }
        ExecuteV3(plan, il)
    }

    public static func Validate(plan: ColumnarCodePlan) {
        if plan == null {
            throw new InvalidOperationException("Columnar code plan cannot be null.")
        }

        plan.ValidateSealedStructure()
        if plan.SchemaVersion == ColumnarCodePlanContract.RecursiveSchemaVersion() {
            ValidateV2Semantics(plan)
        } else if plan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() {
            ValidateV3Semantics(plan)
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
        ExecuteRecursiveRows(plan, il)
    }

    static func ExecuteV3(plan: ColumnarCodePlan, il: ILGenerator) {
        // Consume at the same pre-emission boundary as schema v2. A failed declaration or emit
        // must never leave a scalar plan replayable.
        plan.ConsumeV3()
        ExecuteRecursiveRows(plan, il)
    }

    static func ExecuteRecursiveRows(plan: ColumnarCodePlan, il: ILGenerator) {

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
        } else if operandKind == ColumnarCodePlanContract.Int64Operand() {
            il.Emit(OpCodes.Ldc_I8, plan.Int64Values[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.SingleOperand() {
            il.Emit(OpCodes.Ldc_R4, plan.SingleValues[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.DoubleOperand() {
            il.Emit(OpCodes.Ldc_R8, plan.DoubleValues[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.StringOperand() {
            il.Emit(OpCodes.Ldstr, plan.StringValues[operandIndex])
        } else if operandKind == ColumnarCodePlanContract.ArgumentOperand() {
            if opCodeValue == ColumnarCodePlanContract.Ldarga() {
                il.Emit(OpCodes.Ldarga, (short)plan.ArgumentOrdinals[operandIndex])
            } else {
                il.Emit(OpCodes.Ldarg, (short)plan.ArgumentOrdinals[operandIndex])
            }
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
            if opCodeValue == ColumnarCodePlanContract.Ldsfld() {
                il.Emit(OpCodes.Ldsfld, plan.Fields[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Ldflda() {
                il.Emit(OpCodes.Ldflda, plan.Fields[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Stfld() {
                il.Emit(OpCodes.Stfld, plan.Fields[operandIndex])
            } else {
                il.Emit(OpCodes.Ldfld, plan.Fields[operandIndex])
            }
        } else if operandKind == ColumnarCodePlanContract.LabelOperand() {
            if opCodeValue == ColumnarCodePlanContract.Br() {
                il.Emit(OpCodes.Br, labels[operandIndex])
            } else {
                il.Emit(OpCodes.Brfalse, labels[operandIndex])
            }
        } else if operandKind == ColumnarCodePlanContract.TypeOperand() {
            if opCodeValue == ColumnarCodePlanContract.Ldtoken() {
                il.Emit(OpCodes.Ldtoken, plan.Types[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Box() {
                il.Emit(OpCodes.Box, plan.Types[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Castclass() {
                il.Emit(OpCodes.Castclass, plan.Types[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Initobj() {
                il.Emit(OpCodes.Initobj, plan.Types[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Newarr() {
                il.Emit(OpCodes.Newarr, plan.Types[operandIndex])
            } else if opCodeValue == ColumnarCodePlanContract.Stelem() {
                il.Emit(OpCodes.Stelem, plan.Types[operandIndex])
            } else {
                il.Emit(OpCodes.Ldelem, plan.Types[operandIndex])
            }
        }
    }

    static func EmitWithoutOperand(il: ILGenerator, opCodeValue: short) {
        if opCodeValue == ColumnarCodePlanContract.Ldnull() {
            il.Emit(OpCodes.Ldnull)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4_M1() {
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
        } else if opCodeValue == ColumnarCodePlanContract.Dup() {
            il.Emit(OpCodes.Dup)
        } else if opCodeValue == ColumnarCodePlanContract.Add() {
            il.Emit(OpCodes.Add)
        } else if opCodeValue == ColumnarCodePlanContract.Neg() {
            il.Emit(OpCodes.Neg)
        } else if opCodeValue == ColumnarCodePlanContract.Not() {
            il.Emit(OpCodes.Not)
        } else if opCodeValue == ColumnarCodePlanContract.Ceq() {
            il.Emit(OpCodes.Ceq)
        } else if opCodeValue == ColumnarCodePlanContract.LdindRef() {
            il.Emit(OpCodes.Ldind_Ref)
        } else if opCodeValue == ColumnarCodePlanContract.ConvI4() {
            il.Emit(OpCodes.Conv_I4)
        } else if opCodeValue == ColumnarCodePlanContract.ConvI8() {
            il.Emit(OpCodes.Conv_I8)
        } else if opCodeValue == ColumnarCodePlanContract.ConvR4() {
            il.Emit(OpCodes.Conv_R4)
        } else if opCodeValue == ColumnarCodePlanContract.ConvR8() {
            il.Emit(OpCodes.Conv_R8)
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
        } else if opCodeValue == ColumnarCodePlanContract.StelemI1() {
            il.Emit(OpCodes.Stelem_I1)
        } else if opCodeValue == ColumnarCodePlanContract.StelemI2() {
            il.Emit(OpCodes.Stelem_I2)
        } else if opCodeValue == ColumnarCodePlanContract.StelemI4() {
            il.Emit(OpCodes.Stelem_I4)
        } else if opCodeValue == ColumnarCodePlanContract.StelemI8() {
            il.Emit(OpCodes.Stelem_I8)
        } else if opCodeValue == ColumnarCodePlanContract.StelemR4() {
            il.Emit(OpCodes.Stelem_R4)
        } else if opCodeValue == ColumnarCodePlanContract.StelemR8() {
            il.Emit(OpCodes.Stelem_R8)
        } else if opCodeValue == ColumnarCodePlanContract.StelemRef() {
            il.Emit(OpCodes.Stelem_Ref)
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
        ValidateRecursiveSemantics(plan, false)
    }

    static func ValidateV3Semantics(plan: ColumnarCodePlan) {
        ValidateRecursiveSemantics(plan, true)
    }

    static func ValidateRecursiveSemantics(plan: ColumnarCodePlan, scalarSchema: bool) {
        schemaName := scalarSchema ? "Schema-v3" : "Schema-v2"
        schemaNameLower := scalarSchema ? "schema-v3" : "schema-v2"
        ValidateValuePools(plan, schemaName, scalarSchema)
        // Labels have no backing schema column. Prove their maximum count before allocating any
        // label-indexed validation state: each valid label consumes one mark row and at least one
        // distinct branch row.
        if plan.LabelCount > plan.OperationCount / 2 {
            throw new InvalidOperationException(
                schemaName + " label count exceeds its operation-row bound.")
        }

        usedTypes := new bool[](plan.TypeCount)
        usedInt32 := new bool[](plan.Int32Count)
        usedInt64 := new bool[](scalarSchema ? plan.Int64Count : 0)
        usedSingle := new bool[](scalarSchema ? plan.SingleCount : 0)
        usedDouble := new bool[](scalarSchema ? plan.DoubleCount : 0)
        usedStrings := new bool[](scalarSchema ? plan.StringCount : 0)
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
            } else if operandKind == ColumnarCodePlanContract.Int64Operand() {
                usedInt64[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.SingleOperand() {
                usedSingle[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.DoubleOperand() {
                usedDouble[operandIndex] = true
            } else if operandKind == ColumnarCodePlanContract.StringOperand() {
                usedStrings[operandIndex] = true
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
                        throw new InvalidOperationException(
                            "A " + schemaNameLower + " label must be marked exactly once.")
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
                    throw new InvalidOperationException(
                        schemaName + " branches must target a forward label.")
                }
                if labelMarkOwners[labelIndex] != plan.OperationOwnerFragmentIndices[i] {
                    throw new InvalidOperationException(
                        schemaName + " branches and labels must have the same fragment owner.")
                }
            }
            i += 1
        }

        ValidateAllUsed(usedTypes, "type", schemaName)
        ValidateAllUsed(usedInt32, "Int32", schemaName)
        ValidateAllUsed(usedInt64, "Int64", schemaName)
        ValidateAllUsed(usedSingle, "Single", schemaName)
        ValidateAllUsed(usedDouble, "Double", schemaName)
        ValidateAllUsed(usedStrings, "String", schemaName)
        ValidateAllUsed(usedArguments, "argument", schemaName)
        ValidateAllUsed(usedAmbientLocals, "ambient local", schemaName)
        ValidateAllUsed(usedMethods, "method", schemaName)
        ValidateAllUsed(usedConstructors, "constructor", schemaName)
        ValidateAllUsed(usedFields, "field", schemaName)
        ValidateAllUsed(usedPlanLocals, "plan local", schemaName)
        i = 0
        while i < plan.LabelCount {
            if labelMarkIndices[i] < 0 || !labelReferenced[i] {
                throw new InvalidOperationException(
                    "Every " + schemaNameLower
                        + " label must be marked once and referenced by a branch.")
            }
            i += 1
        }

        ValidateControlFlowAndFragments(
            plan,
            labelMarkIndices,
            schemaName,
            schemaNameLower)
    }

    static func ValidateValuePools(
        plan: ColumnarCodePlan,
        schemaName: string,
        allowVoidMethodReturns: bool) {
        i := 0
        while i < plan.TypeCount {
            ValidateStorableType(plan.Types[i], "type pool", schemaName)
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
            ValidateStorableType(argumentType, "argument", schemaName)
            ordinal := plan.ArgumentOrdinals[i]
            if usedArgumentOrdinals[ordinal] {
                throw new InvalidOperationException(
                    schemaName + " argument ordinals must be unique.")
            }
            usedArgumentOrdinals[ordinal] = true
            i += 1
        }

        i = 0
        while i < plan.AmbientLocalCount {
            localType := plan.AmbientLocals[i].get_LocalType()
            ValidateStorableType(localType, "ambient local", schemaName)
            i += 1
        }

        i = 0
        while i < plan.PlanLocalCount {
            ValidateStorableType(
                plan.Types[plan.PlanLocalTypeIndices[i]],
                "plan local",
                schemaName)
            i += 1
        }

        i = 0
        while i < plan.MethodCount {
            ValidateMethod(plan, i, schemaName, allowVoidMethodReturns)
            i += 1
        }
        i = 0
        while i < plan.ConstructorCount {
            ValidateConstructor(plan, i, schemaName)
            i += 1
        }
        i = 0
        while i < plan.FieldCount {
            ValidateField(plan, i, schemaName)
            i += 1
        }
        i = 0
        while i < plan.FragmentCount {
            if IsVoidType(plan.FragmentResultTypes[i]) {
                if !allowVoidMethodReturns || i != 0 {
                    throw new InvalidOperationException(
                        schemaName + " only permits void on the root fragment result.")
                }
            } else {
                ValidateStorableType(
                    plan.FragmentResultTypes[i], "fragment result", schemaName)
            }
            i += 1
        }
    }

    static func ValidateMethod(
        plan: ColumnarCodePlan,
        methodIndex: int,
        schemaName: string,
        allowVoidReturn: bool) {
        method := plan.Methods[methodIndex]
        if method.get_IsGenericMethodDefinition() {
            throw new InvalidOperationException(
                schemaName + " method handles cannot be generic method definitions.")
        }
        if (((int)method.get_CallingConvention())
                & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0 {
            throw new InvalidOperationException(
                schemaName + " method handles cannot use the VarArgs calling convention.")
        }
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(
                schemaName + " methods must have an exact declaring type.")
        }
        if plan.MethodUsesDeclaredSignature[methodIndex] {
            declaredType := plan.MethodDeclaringTypes[methodIndex]
            if declaringType != declaredType
                || method.get_IsStatic() != plan.MethodIsStatic[methodIndex]
                || method.get_IsAbstract() != plan.MethodIsAbstract[methodIndex] {
                throw new InvalidOperationException(
                    schemaName + " declared method identity does not match its handle.")
            }
            ValidateStorableType(declaredType, "method receiver", schemaName)
            ValidateMethodReturnType(
                plan.MethodReturnTypes[methodIndex], schemaName, allowVoidReturn)
            declaredParameters := plan.MethodParameterTypes[methodIndex]
            declaredIndex := 0
            while declaredIndex < declaredParameters.Length {
                ValidateStorableType(
                    declaredParameters[declaredIndex],
                    "method argument",
                    schemaName)
                declaredIndex += 1
            }
            ValidateDeclaredMethodSignatureIfAvailable(
                plan, methodIndex, method, schemaName)
            return
        }
        ValidateStorableType(declaringType, "method receiver", schemaName)
        signatureMethod := GetMethodSignatureDefinition(method, schemaName)
        declaringArguments := DeclaringTypeArguments(declaringType)
        genericArguments := method.GetGenericArguments()
        returnType := ResolveMemberSignatureType(
            signatureMethod.get_ReturnType(),
            declaringArguments,
            genericArguments,
            schemaName)
        ValidateMethodReturnType(returnType, schemaName, allowVoidReturn)
        parameters := signatureMethod.GetParameters()
        i := 0
        while i < parameters.Length {
            parameterType := ResolveMemberSignatureType(
                parameters[i].get_ParameterType(),
                declaringArguments,
                genericArguments,
                schemaName)
            ValidateStorableType(parameterType, "method argument", schemaName)
            i += 1
        }
    }

    static func ValidateConstructor(
        plan: ColumnarCodePlan,
        constructorIndex: int,
        schemaName: string) {
        constructorInfo := plan.Constructors[constructorIndex]
        declaringType := constructorInfo.get_DeclaringType()
        if declaringType == null
            || constructorInfo.get_IsStatic()
            || declaringType.get_IsAbstract() {
            throw new InvalidOperationException(
                schemaName
                    + " constructors must be instance constructors with an exact declaring type.")
        }
        if (((int)constructorInfo.get_CallingConvention())
                & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0 {
            throw new InvalidOperationException(
                schemaName + " constructors cannot use the VarArgs calling convention.")
        }

        if plan.ConstructorUsesDeclaredSignature[constructorIndex] {
            declaredType := plan.ConstructorDeclaringTypes[constructorIndex]
            if !ExactTypeShapeMatches(declaringType, declaredType) {
                throw new InvalidOperationException(
                    schemaName
                        + " declared constructor identity does not match its handle.")
            }
            ValidateStorableType(declaredType, "constructor result", schemaName)
            declaredParameters := plan.ConstructorParameterTypes[constructorIndex]
            parameterIndex := 0
            while parameterIndex < declaredParameters.Length {
                ValidateStorableType(
                    declaredParameters[parameterIndex],
                    "constructor argument",
                    schemaName)
                parameterIndex += 1
            }
            ValidateDeclaredConstructorSignatureIfAvailable(
                constructorInfo,
                declaredType,
                declaredParameters,
                schemaName)
            return
        }

        ValidateStorableType(declaringType, "constructor result", schemaName)
        parameters := constructorInfo.GetParameters()
        i := 0
        while i < parameters.Length {
            ValidateStorableType(
                parameters[i].get_ParameterType(),
                "constructor argument",
                schemaName)
            i += 1
        }
    }

    static func ValidateDeclaredConstructorSignatureIfAvailable(
        constructorInfo: ConstructorInfo,
        declaringType: Type,
        declaredParameters: Type[],
        schemaName: string) {
        try {
            actualParameters := constructorInfo.GetParameters()
            if actualParameters.Length != declaredParameters.Length {
                throw new InvalidOperationException(
                    schemaName
                        + " declared constructor arity does not match its inspectable handle.")
            }
            declaringArguments := DeclaringTypeArguments(declaringType)
            noMethodArguments := new Type[](0)
            i := 0
            while i < actualParameters.Length {
                actualParameter := ResolveMemberSignatureType(
                    actualParameters[i].get_ParameterType(),
                    declaringArguments,
                    noMethodArguments,
                    schemaName)
                if !ExactTypeShapeMatches(actualParameter, declaredParameters[i]) {
                    throw new InvalidOperationException(
                        schemaName
                            + " declared constructor parameter does not match its inspectable handle.")
                }
                i += 1
            }
        } catch ex: NotSupportedException {
            // TypeBuilder.GetConstructor and unbaked ConstructorBuilder handles may expose no
            // parameter list. The planner-owned declaration is the exact available signature.
            return
        } catch ex: NotImplementedException {
            return
        }
    }

    static func ValidateDeclaredMethodSignatureIfAvailable(
        plan: ColumnarCodePlan,
        methodIndex: int,
        method: MethodInfo,
        schemaName: string) {
        // ReturnType is available on both an unbaked MethodBuilder and its exact
        // TypeBuilder.GetMethod wrapper. Validate it before GetParameters reaches the
        // documented unbaked reflection boundary, so that boundary can never hide a lie.
        signatureMethod := GetMethodSignatureDefinition(method, schemaName)
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(
                schemaName + " declared method has no declaring type.")
        }
        declaringArguments := DeclaringTypeArguments(declaringType)
        genericArguments := method.GetGenericArguments()
        actualReturn := ResolveMemberSignatureType(
            signatureMethod.get_ReturnType(),
            declaringArguments,
            genericArguments,
            schemaName)
        if !ExactTypeShapeMatches(
            actualReturn, plan.MethodReturnTypes[methodIndex]) {
            throw new InvalidOperationException(
                schemaName
                    + " declared method return does not match its inspectable handle.")
        }
        try {
            actualParameters := signatureMethod.GetParameters()
            declaredParameters := plan.MethodParameterTypes[methodIndex]
            if actualParameters.Length != declaredParameters.Length {
                throw new InvalidOperationException(
                    schemaName
                        + " declared method arity does not match its inspectable handle.")
            }
            i := 0
            while i < actualParameters.Length {
                actualParameter := ResolveMemberSignatureType(
                    actualParameters[i].get_ParameterType(),
                    declaringArguments,
                    genericArguments,
                    schemaName)
                if !ExactTypeShapeMatches(actualParameter, declaredParameters[i]) {
                    throw new InvalidOperationException(
                        schemaName
                            + " declared method parameter does not match its inspectable handle.")
                }
                i += 1
            }
        } catch ex: NotSupportedException {
            // An unbaked MethodBuilder has exact identity but exposes no reflection signature.
            // Its planner-owned declaration is the only available signature source.
            return
        } catch ex: NotImplementedException {
            // Some Reflection.Emit implementations report the same unbaked limitation here.
            return
        }
    }

    static func ValidateField(
        plan: ColumnarCodePlan,
        fieldIndex: int,
        schemaName: string) {
        field := plan.Fields[fieldIndex]
        if field.get_IsLiteral() {
            throw new InvalidOperationException(
                schemaName + " field handles cannot name literal fields without storage.")
        }
        declaringType := field.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(
                schemaName
                    + " field handles must have an exact declaring type.")
        }
        if plan.FieldUsesDeclaredSignature[fieldIndex] {
            declaredType := plan.FieldDeclaringTypes[fieldIndex]
            declaredValueType := plan.FieldValueTypes[fieldIndex]
            if declaringType != declaredType
                || field.get_IsStatic() != plan.FieldIsStatic[fieldIndex] {
                throw new InvalidOperationException(
                    schemaName + " declared field identity does not match its handle.")
            }
            ValidateStorableType(declaredType, "field receiver", schemaName)
            ValidateStorableType(declaredValueType, "field result", schemaName)
            actualValueType := ResolveMemberSignatureType(
                field.get_FieldType(),
                DeclaringTypeArguments(declaredType),
                new Type[](0),
                schemaName)
            if !ExactTypeShapeMatches(actualValueType, declaredValueType) {
                throw new InvalidOperationException(
                    schemaName
                        + " declared field result does not match its inspectable handle.")
            }
            return
        }
        ValidateStorableType(declaringType, "field receiver", schemaName)
        ValidateStorableType(field.get_FieldType(), "field result", schemaName)
    }

    static func ValidateStorableType(valueType: Type, role: string, schemaName: string) {
        if valueType.FullName == "System.Void" {
            throw new InvalidOperationException(
                schemaName + " " + role + " types cannot be void.")
        }
        if valueType.get_IsByRef() {
            throw new InvalidOperationException(
                schemaName + " " + role
                    + " types cannot be null, void, or by-reference.")
        }
        if valueType.get_IsGenericTypeDefinition() {
            throw new InvalidOperationException(
                schemaName + " " + role + " types cannot be generic type definitions.")
        }
    }

    static func ValidateMethodReturnType(
        valueType: Type,
        schemaName: string,
        allowVoidReturn: bool) {
        if IsVoidType(valueType) {
            if !allowVoidReturn {
                throw new InvalidOperationException(
                    schemaName + " method return types cannot be void.")
            }
            return
        }
        ValidateStorableType(valueType, "method return", schemaName)
    }

    static func IsVoidType(valueType: Type): bool {
        return valueType.FullName == "System.Void"
    }

    static func ValidateAllUsed(used: bool[], poolName: string, schemaName: string) {
        i := 0
        while i < used.Length {
            if !used[i] {
                throw new InvalidOperationException(
                    schemaName + " " + poolName + " pool contains hidden unused state.")
            }
            i += 1
        }
    }

    static func ValidateControlFlowAndFragments(
        plan: ColumnarCodePlan,
        labelMarkIndices: int[],
        schemaName: string,
        schemaNameLower: string) {
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
                throw new InvalidOperationException(
                    schemaName + " operation stream contains unreachable instructions.")
            }
            ValidateAndRefineEndingFragments(
                plan,
                states,
                endingFragmentHeads,
                endingFragmentNext,
                fragmentEntryHeads,
                fragmentEntryCounts,
                fragmentEntryCaptured,
                i,
                schemaNameLower)
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
                ApplyInstruction(plan, i, output, schemaName)
            }

            opCodeValue := plan.OpCodeValues[i]
            if opCodeValue == ColumnarCodePlanContract.Br() {
                labelIndex := plan.OperandIndices[i]
                MergeState(states, labelMarkIndices[labelIndex], output, schemaName)
            } else if opCodeValue == ColumnarCodePlanContract.Brfalse() {
                labelIndex := plan.OperandIndices[i]
                MergeState(
                    states,
                    labelMarkIndices[labelIndex],
                    output.Copy(),
                    schemaName)
                MergeState(states, i + 1, output, schemaName)
            } else {
                MergeState(states, i + 1, output, schemaName)
            }
            i += 1
        }

        if states[plan.OperationCount] == null {
            throw new InvalidOperationException(
                schemaName + " operation stream has no reachable result.")
        }
        ValidateAndRefineEndingFragments(
            plan,
            states,
            endingFragmentHeads,
            endingFragmentNext,
            fragmentEntryHeads,
            fragmentEntryCounts,
            fragmentEntryCaptured,
            plan.OperationCount,
            schemaNameLower)

        rootExit := states[plan.OperationCount]
        if IsVoidType(plan.ResultType) {
            if rootExit.Count != 0 || rootExit.Head != null {
                throw new InvalidOperationException(
                    schemaName + " void root execution must leave an empty stack.")
            }
            return
        }

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
            throw new InvalidOperationException(
                schemaName + " root execution must leave exactly its declared result.")
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
        boundaryIndex: int,
        schemaNameLower: string) {
        fragmentIndex := endingFragmentHeads[boundaryIndex]
        while fragmentIndex >= 0 {
            exitState := states[boundaryIndex]
            if exitState == null {
                throw new InvalidOperationException(
                    "Every " + schemaNameLower + " fragment must have a reachable exit.")
            }
            entryCount := fragmentEntryCounts[fragmentIndex]
            resultValue := exitState.Head
            resultType := plan.FragmentResultTypes[fragmentIndex]
            if IsVoidType(resultType) {
                if fragmentIndex != 0
                    || !fragmentEntryCaptured[fragmentIndex]
                    || exitState.Count != entryCount
                    || resultValue != fragmentEntryHeads[fragmentIndex] {
                    throw new InvalidOperationException(
                        "A " + schemaNameLower
                            + " void root fragment must add no stack values.")
                }
                fragmentIndex = endingFragmentNext[fragmentIndex]
                continue
            }
            if !fragmentEntryCaptured[fragmentIndex]
                || resultValue == null
                || exitState.Count != entryCount + 1
                || resultValue.Previous != fragmentEntryHeads[fragmentIndex] {
                throw new InvalidOperationException(
                    "Every " + schemaNameLower
                        + " fragment must add exactly one reachable stack value.")
            }
            if resultValue.IsAddress
                || !IsStackCompatible(
                    resultType,
                    resultValue.ValueType,
                    resultValue.ValueKind,
                    resultValue.LiteralKnown,
                    resultValue.LiteralValue) {
                throw new InvalidOperationException(
                    "A " + schemaNameLower
                        + " fragment result does not match its declared type.")
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
        incoming: ColumnarCodePlanStackState,
        schemaName: string) {
        existing := states[targetIndex]
        if existing == null {
            states[targetIndex] = incoming
            return
        }
        if existing.Count != incoming.Count {
            throw new InvalidOperationException(
                schemaName + " control-flow stack depths do not merge.")
        }
        MergeStack(existing, incoming, schemaName)

        i := 0
        while i < existing.AssignedPlanLocalWords.Length {
            existing.AssignedPlanLocalWords[i] =
                existing.AssignedPlanLocalWords[i] & incoming.AssignedPlanLocalWords[i]
            i += 1
        }
    }

    static func MergeStack(
        target: ColumnarCodePlanStackState,
        incoming: ColumnarCodePlanStackState,
        schemaName: string) {
        if target.Head == incoming.Head {
            return
        }

        divergentCount := 0
        left := target.Head
        right := incoming.Head
        while left != right {
            if left == null || right == null {
                throw new InvalidOperationException(
                    schemaName + " control-flow stack shapes do not merge.")
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
                throw new InvalidOperationException(
                    schemaName + " control-flow stack shapes do not merge.")
            }
            mergedSlots[slotIndex] = MergeStackSlot(left, right, schemaName)
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
        right: ColumnarCodePlanStackNode,
        schemaName: string): ColumnarCodePlanStackNode {
        if left.IsAddress != right.IsAddress {
            throw new InvalidOperationException(
                schemaName + " control-flow address states do not merge.")
        }
        if left.IsAddress {
            if left.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || right.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || !ExactTypeShapeMatches(left.ValueType, right.ValueType) {
                throw new InvalidOperationException(
                    schemaName + " control-flow address types do not merge.")
            }
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                true,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }

        if left.ValueKind == ColumnarCodePlanStackValueKind.NullReference()
            && right.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && !right.ValueType.get_IsValueType()
            && !right.ValueType.get_IsGenericParameter() {
            return new ColumnarCodePlanStackNode(
                right.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }
        if right.ValueKind == ColumnarCodePlanStackValueKind.NullReference()
            && left.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && !left.ValueType.get_IsValueType()
            && !left.ValueType.get_IsGenericParameter() {
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }

        if left.ValueKind == right.ValueKind {
            if left.ValueKind == ColumnarCodePlanStackValueKind.Exact() {
                return new ColumnarCodePlanStackNode(
                    MergeExactStackType(left.ValueType, right.ValueType, schemaName),
                    false,
                    ColumnarCodePlanStackValueKind.Exact(),
                    false,
                    0,
                    null)
            }
            if !ExactTypeShapeMatches(left.ValueType, right.ValueType) {
                throw new InvalidOperationException(
                    schemaName + " control-flow stack categories do not merge.")
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

        if left.ValueKind == ColumnarCodePlanStackValueKind.BoxedExact()
            && right.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && !right.ValueType.get_IsValueType()
            && IsStackCompatible(
                right.ValueType,
                left.ValueType,
                left.ValueKind,
                false,
                0) {
            return new ColumnarCodePlanStackNode(
                right.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }
        if right.ValueKind == ColumnarCodePlanStackValueKind.BoxedExact()
            && left.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && !left.ValueType.get_IsValueType()
            && IsStackCompatible(
                left.ValueType,
                right.ValueType,
                right.ValueKind,
                false,
                0) {
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }

        if left.ValueKind == ColumnarCodePlanStackValueKind.I8Slot()
            && right.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && IsI8Destination(right.ValueType) {
            return new ColumnarCodePlanStackNode(
                right.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
                null)
        }
        if right.ValueKind == ColumnarCodePlanStackValueKind.I8Slot()
            && left.ValueKind == ColumnarCodePlanStackValueKind.Exact()
            && IsI8Destination(left.ValueType) {
            return new ColumnarCodePlanStackNode(
                left.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0,
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
        throw new InvalidOperationException(
            schemaName + " control-flow stack categories do not merge.")
    }

    static func MergeExactStackType(left: Type, right: Type, schemaName: string): Type {
        if ExactTypeShapeMatches(left, right) {
            return left
        }
        if !left.get_IsValueType() && !right.get_IsValueType() {
            if ReferenceAssignableFrom(left, right) {
                return left
            }
            if ReferenceAssignableFrom(right, left) {
                return right
            }
        }
        throw new InvalidOperationException(
            schemaName + " control-flow value types do not merge.")
    }

    static func ApplyInstruction(
        plan: ColumnarCodePlan,
        operationIndex: int,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
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
        } else if opCodeValue == ColumnarCodePlanContract.Ldnull() {
            state.Push(
                typeof(object),
                false,
                ColumnarCodePlanStackValueKind.NullReference(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.LdcI4() {
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.LiteralI4(),
                true,
                plan.Int32Values[operandIndex])
        } else if opCodeValue == ColumnarCodePlanContract.LdcI8() {
            state.Push(
                typeof(long),
                false,
                ColumnarCodePlanStackValueKind.I8Slot(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.LdcR4() {
            state.Push(
                typeof(float),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.LdcR8() {
            state.Push(
                typeof(double),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ldstr() {
            state.Push(
                typeof(string),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Dup() {
            // Do not pop and recreate the original. The duplicate points at the existing head,
            // preserving the persistent tail identity captured by an enclosing fragment.
            value := state.Head
            if value == null {
                throw new InvalidOperationException(
                    schemaName + " dup requires one evaluation-stack value.")
            }
            state.PushDuplicate(value)
        } else if opCodeValue == ColumnarCodePlanContract.Ldarg()
            || opCodeValue == ColumnarCodePlanContract.Ldarga() {
            argumentType := plan.Types[plan.ArgumentTypeIndices[operandIndex]]
            if opCodeValue == ColumnarCodePlanContract.Ldarga()
                && plan.ArgumentIsAddress[operandIndex] {
                throw new InvalidOperationException(
                    schemaName + " ldarga cannot take the address of a by-reference argument slot.")
            }
            isAddress := opCodeValue == ColumnarCodePlanContract.Ldarga()
                || plan.ArgumentIsAddress[operandIndex]
            state.Push(
                argumentType,
                isAddress,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if ColumnarCodePlanContract.IsLocalOpcode(opCodeValue) {
            localType := LocalType(plan, operationIndex)
            ApplyLocal(plan, operationIndex, opCodeValue, localType, state, schemaName)
        } else if opCodeValue == ColumnarCodePlanContract.Call()
            || opCodeValue == ColumnarCodePlanContract.Callvirt() {
            ApplyMethodCall(
                plan, operationIndex, operandIndex, opCodeValue, state, schemaName)
        } else if opCodeValue == ColumnarCodePlanContract.Newobj() {
            ApplyConstructor(plan, operandIndex, state, schemaName)
        } else if opCodeValue == ColumnarCodePlanContract.Ldfld()
            || opCodeValue == ColumnarCodePlanContract.Ldflda() {
            ApplyField(
                plan,
                operandIndex,
                opCodeValue == ColumnarCodePlanContract.Ldflda(),
                state,
                schemaName)
        } else if opCodeValue == ColumnarCodePlanContract.Stfld() {
            ApplyFieldStore(plan, operandIndex, state, schemaName)
        } else if opCodeValue == ColumnarCodePlanContract.Ldsfld() {
            ApplyStaticField(plan, operandIndex, state, schemaName)
        } else if opCodeValue == ColumnarCodePlanContract.Ldtoken() {
            state.Push(
                typeof(RuntimeTypeHandle),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Box() {
            targetType := plan.Types[operandIndex]
            value := state.Pop()
            if (!targetType.get_IsValueType() && !targetType.get_IsGenericParameter())
                || value.IsAddress
                || !IsStackCompatible(
                    targetType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException(
                    schemaName
                        + " box requires a compatible value and an exact value-type operand.")
            }
            state.Push(
                targetType,
                false,
                ColumnarCodePlanStackValueKind.BoxedExact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Castclass() {
            targetType := plan.Types[operandIndex]
            value := state.Pop()
            isReferenceValue := value.ValueKind
                    == ColumnarCodePlanStackValueKind.Exact()
                && !value.ValueType.get_IsValueType()
                && !value.ValueType.get_IsGenericParameter()
                && !value.ValueType.get_IsPointer()
                && !value.ValueType.get_IsFunctionPointer()
                || value.ValueKind
                    == ColumnarCodePlanStackValueKind.BoxedExact()
                || value.ValueKind
                    == ColumnarCodePlanStackValueKind.NullReference()
            if targetType.get_IsValueType()
                || targetType.get_IsGenericParameter()
                || targetType.get_IsByRef()
                || targetType.get_IsPointer()
                || targetType.get_IsFunctionPointer()
                || targetType.get_IsGenericTypeDefinition()
                || value.IsAddress
                || !isReferenceValue {
                throw new InvalidOperationException(
                    schemaName
                        + " castclass requires exact reference source and target types.")
            }
            state.Push(
                targetType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Initobj() {
            targetType := plan.Types[operandIndex]
            address := state.Pop()
            if !targetType.get_IsValueType()
                || targetType.get_IsGenericTypeDefinition()
                || !address.IsAddress
                || (address.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                    && address.ValueKind
                        != ColumnarCodePlanStackValueKind.UnassignedPlanLocalAddress())
                || !ExactTypeShapeMatches(targetType, address.ValueType) {
                throw new InvalidOperationException(
                    schemaName
                        + " initobj requires an exact managed address to its value type.")
            }
            localIndex := address.PlanLocalAddressIndex
            if localIndex < 0 || localIndex >= plan.PlanLocalCount {
                throw new InvalidOperationException(
                    schemaName
                        + " initobj addresses must originate from an exact plan local.")
            }
            if address.ValueKind
                == ColumnarCodePlanStackValueKind.UnassignedPlanLocalAddress() {
                state.MarkPlanLocalAssigned(localIndex)
            }
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
                throw new InvalidOperationException(
                    schemaName
                        + " brfalse requires an exact Boolean condition or literal I4.")
            }
        } else if opCodeValue == ColumnarCodePlanContract.Add() {
            right := state.Pop()
            left := state.Pop()
            resultType := typeof(int)
            if IsIntPromotableAddOperand(left)
                && IsIntPromotableAddOperand(right) {
                resultType = typeof(int)
            } else if IsExactPrimitiveAddOperand(left, typeof(long))
                && IsExactPrimitiveAddOperand(right, typeof(long)) {
                resultType = typeof(long)
            } else if IsExactPrimitiveAddOperand(left, typeof(uint))
                && IsExactPrimitiveAddOperand(right, typeof(uint)) {
                resultType = typeof(uint)
            } else if IsExactPrimitiveAddOperand(left, typeof(ulong))
                && IsExactPrimitiveAddOperand(right, typeof(ulong)) {
                resultType = typeof(ulong)
            } else if IsExactPrimitiveAddOperand(left, typeof(float))
                && IsExactPrimitiveAddOperand(right, typeof(float)) {
                resultType = typeof(float)
            } else if IsExactPrimitiveAddOperand(left, typeof(double))
                && IsExactPrimitiveAddOperand(right, typeof(double)) {
                resultType = typeof(double)
            } else {
                throw new InvalidOperationException(
                    schemaName
                        + " add requires an Int32-promotable pair or exact matching "
                        + "Int64, UInt32, UInt64, Single, or Double operands.")
            }
            state.Push(
                resultType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Neg() {
            value := state.Pop()
            if value.IsAddress
                || value.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || (value.ValueType != typeof(int)
                    && value.ValueType != typeof(long)
                    && value.ValueType != typeof(float)
                    && value.ValueType != typeof(double)) {
                throw new InvalidOperationException(
                    schemaName + " neg requires an exact signed numeric scalar.")
            }
            state.Push(
                value.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Not() {
            value := state.Pop()
            if value.IsAddress
                || value.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || (value.ValueType != typeof(int)
                    && value.ValueType != typeof(long)
                    && value.ValueType != typeof(ulong)) {
                throw new InvalidOperationException(
                    schemaName + " not requires an exact integral scalar.")
            }
            state.Push(
                value.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ceq() {
            right := state.Pop()
            left := state.Pop()
            if left.IsAddress || right.IsAddress
                || left.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || left.ValueType != typeof(bool)
                || right.ValueKind != ColumnarCodePlanStackValueKind.LiteralI4()
                || !right.LiteralKnown
                || right.LiteralValue != 0 {
                throw new InvalidOperationException(
                    schemaName + " ceq requires exact Boolean and literal zero operands.")
            }
            state.Push(
                typeof(bool),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.LdindRef() {
            value := state.Pop()
            if !value.IsAddress
                || value.ValueKind != ColumnarCodePlanStackValueKind.Exact()
                || value.ValueType.get_IsValueType()
                || value.ValueType.get_IsGenericParameter() {
                throw new InvalidOperationException(
                    schemaName
                        + " ldind.ref requires an exact managed address to a reference slot.")
            }
            state.Push(
                value.ValueType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.ConvI4() {
            value := state.Pop()
            if value.IsAddress
                || !CanConvertToI4(
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown) {
                throw new InvalidOperationException(
                    schemaName
                        + " conv.i4 requires literal I4, native length, or exact Int32.")
            }
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.ConvI8() {
            value := state.Pop()
            if value.IsAddress
                || !CanWidenToI8(value.ValueType, value.ValueKind) {
                throw new InvalidOperationException(
                    schemaName
                        + " conv.i8 requires an exact int-promotable scalar.")
            }
            state.Push(
                typeof(long),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.ConvR4() {
            value := state.Pop()
            if value.IsAddress
                || !CanWidenToR4(value.ValueType, value.ValueKind) {
                throw new InvalidOperationException(
                    schemaName
                        + " conv.r4 requires an exact int-promotable or Int64 scalar.")
            }
            state.Push(
                typeof(float),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.ConvR8() {
            value := state.Pop()
            if value.IsAddress
                || !CanWidenToR8(value.ValueType, value.ValueKind) {
                throw new InvalidOperationException(
                    schemaName
                        + " conv.r8 requires an exact int-promotable, Int64, or Single scalar.")
            }
            state.Push(
                typeof(double),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ldlen() {
            arrayValue := state.Pop()
            RequireSzArray(arrayValue.ValueType, arrayValue.IsAddress, schemaName)
            state.Push(
                typeof(int),
                false,
                ColumnarCodePlanStackValueKind.NativeUnsigned(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Newarr() {
            lengthValue := state.Pop()
            if lengthValue.IsAddress
                || !IsArrayIndex(
                    lengthValue.ValueType,
                    lengthValue.ValueKind,
                    lengthValue.LiteralKnown) {
                throw new InvalidOperationException(
                    schemaName
                        + " newarr requires an exact Int32 or literal I4 length.")
            }
            elementType := plan.Types[operandIndex]
            state.Push(
                elementType.MakeArrayType(),
                false,
                ColumnarCodePlanStackValueKind.Exact(),
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
                ApplyArrayElementLoad(
                    opCodeValue,
                    plan.Types[operandIndex],
                    true,
                    state,
                    schemaName)
            } else {
                ApplyArrayElementLoad(
                    opCodeValue,
                    typeof(object),
                    false,
                    state,
                    schemaName)
            }
        } else if opCodeValue == ColumnarCodePlanContract.Stelem()
            || opCodeValue == ColumnarCodePlanContract.StelemI1()
            || opCodeValue == ColumnarCodePlanContract.StelemI2()
            || opCodeValue == ColumnarCodePlanContract.StelemI4()
            || opCodeValue == ColumnarCodePlanContract.StelemI8()
            || opCodeValue == ColumnarCodePlanContract.StelemR4()
            || opCodeValue == ColumnarCodePlanContract.StelemR8()
            || opCodeValue == ColumnarCodePlanContract.StelemRef() {
            if opCodeValue == ColumnarCodePlanContract.Stelem() {
                ApplyArrayElementStore(
                    opCodeValue,
                    plan.Types[operandIndex],
                    true,
                    state,
                    schemaName)
            } else {
                ApplyArrayElementStore(
                    opCodeValue,
                    typeof(object),
                    false,
                    state,
                    schemaName)
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
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        isPlanLocal := plan.OperandKinds[operationIndex]
            == ColumnarCodePlanContract.PlanLocalOperand()
        localIndex := plan.OperandIndices[operationIndex]
        if opCodeValue == ColumnarCodePlanContract.Ldloc() {
            if isPlanLocal && !state.IsPlanLocalAssigned(localIndex) {
                throw new InvalidOperationException(
                    schemaName + " plan locals must be assigned before ldloc.")
            }
            state.Push(
                localType,
                false,
                ColumnarCodePlanStackValueKind.Exact(),
                false,
                0)
        } else if opCodeValue == ColumnarCodePlanContract.Ldloca() {
            if isPlanLocal && !state.IsPlanLocalAssigned(localIndex) {
                state.PushPlanLocalAddress(
                    localType,
                    ColumnarCodePlanStackValueKind.UnassignedPlanLocalAddress(),
                    false,
                    localIndex,
                    localIndex)
                return
            }
            if isPlanLocal {
                state.PushPlanLocalAddress(
                    localType,
                    ColumnarCodePlanStackValueKind.Exact(),
                    false,
                    0,
                    localIndex)
            } else {
                state.Push(
                    localType,
                    true,
                    ColumnarCodePlanStackValueKind.Exact(),
                    false,
                    0)
            }
        } else {
            value := state.Pop()
            if value.IsAddress
                || !IsStackCompatible(
                    localType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException(
                    schemaName + " stloc value does not match its local type.")
            }
            if isPlanLocal {
                state.MarkPlanLocalAssigned(localIndex)
            }
        }
    }

    static func ApplyMethodCall(
        plan: ColumnarCodePlan,
        operationIndex: int,
        methodIndex: int,
        opCodeValue: short,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        method := plan.Methods[methodIndex]
        usesDeclaredSignature := plan.MethodUsesDeclaredSignature[methodIndex]
        isStatic := usesDeclaredSignature
            ? plan.MethodIsStatic[methodIndex]
            : method.get_IsStatic()
        declaringType := usesDeclaredSignature
            ? plan.MethodDeclaringTypes[methodIndex]
            : method.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(schemaName + " call method has no declaring type.")
        }
        if opCodeValue == ColumnarCodePlanContract.Callvirt()
            && (isStatic || declaringType.get_IsValueType()) {
            throw new InvalidOperationException(
                schemaName + " callvirt requires a reference-type instance method.")
        }
        isAbstract := usesDeclaredSignature
            ? plan.MethodIsAbstract[methodIndex]
            : method.get_IsAbstract()
        if opCodeValue == ColumnarCodePlanContract.Call() && isAbstract {
            throw new InvalidOperationException(
                schemaName + " call cannot target an abstract method.")
        }
        receiver: ColumnarCodePlanStackNode? = null

        if usesDeclaredSignature {
            parameters := plan.MethodParameterTypes[methodIndex]
            parameterIndex := parameters.Length - 1
            while parameterIndex >= 0 {
                value := state.Pop()
                parameterType := parameters[parameterIndex]
                if value.IsAddress
                    || !IsStackCompatible(
                        parameterType,
                        value.ValueType,
                        value.ValueKind,
                        value.LiteralKnown,
                        value.LiteralValue) {
                    throw new InvalidOperationException(
                        schemaName
                            + " call argument "
                            + parameterIndex.ToString()
                            + " for '"
                            + method.get_Name()
                            + "' does not match its exact parameter type (expected '"
                            + parameterType.ToString()
                            + "', found '"
                            + value.ValueType.ToString()
                            + "', stack kind "
                            + value.ValueKind.ToString()
                            + ").")
                }
                parameterIndex -= 1
            }

            if !isStatic {
                selectedReceiver := state.Pop()
                receiver = selectedReceiver
                ValidateReceiver(
                    declaringType,
                    selectedReceiver.ValueType,
                    selectedReceiver.IsAddress,
                    selectedReceiver.ValueKind,
                    method.get_Name(),
                    schemaName)
            }
            declaredReturnType := plan.MethodReturnTypes[methodIndex]
            ApplyMethodReturn(
                plan,
                operationIndex,
                declaredReturnType,
                isStatic,
                method.get_Name(),
                parameters.Length,
                method.get_IsSpecialName(),
                receiver,
                state,
                schemaName)
            return
        }

        signatureMethod := GetMethodSignatureDefinition(method, schemaName)
        declaringArguments := DeclaringTypeArguments(declaringType)
        genericArguments := method.GetGenericArguments()
        parameters := signatureMethod.GetParameters()
        parameterIndex := parameters.Length - 1
        while parameterIndex >= 0 {
            value := state.Pop()
            parameterType := ResolveMemberSignatureType(
                parameters[parameterIndex].get_ParameterType(),
                declaringArguments,
                genericArguments,
                schemaName)
            if value.IsAddress
                || !IsStackCompatible(
                    parameterType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException(
                    schemaName
                        + " call argument "
                        + parameterIndex.ToString()
                        + " for '"
                        + method.get_Name()
                        + "' does not match its exact parameter type (expected '"
                        + parameterType.ToString()
                        + "', found '"
                        + value.ValueType.ToString()
                        + "', stack kind "
                        + value.ValueKind.ToString()
                        + ").")
            }
            parameterIndex -= 1
        }

        if !isStatic {
            selectedReceiver := state.Pop()
            receiver = selectedReceiver
            ValidateReceiver(
                declaringType,
                selectedReceiver.ValueType,
                selectedReceiver.IsAddress,
                selectedReceiver.ValueKind,
                method.get_Name(),
                schemaName)
        }
        returnType := ResolveMemberSignatureType(
            signatureMethod.get_ReturnType(),
            declaringArguments,
            genericArguments,
            schemaName)
        ApplyMethodReturn(
            plan,
            operationIndex,
            returnType,
            isStatic,
            method.get_Name(),
            parameters.Length,
            method.get_IsSpecialName(),
            receiver,
            state,
            schemaName)
    }

    static func ApplyMethodReturn(
        plan: ColumnarCodePlan,
        operationIndex: int,
        returnType: Type,
        isStatic: bool,
        methodName: string,
        parameterCount: int,
        isSpecialName: bool,
        receiver: ColumnarCodePlanStackNode?,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        if IsVoidType(returnType) {
            ownerFragment := plan.OperationOwnerFragmentIndices[operationIndex]
            preserved := state.Head
            if preserved != null {
                if isStatic
                    || receiver == null
                    || receiver.IsAddress
                    || receiver.ValueKind
                        != ColumnarCodePlanStackValueKind.Exact()
                    || receiver.DuplicateOf != preserved
                    || !isSpecialName
                    || parameterCount != 1
                    || !methodName.StartsWith(
                        "set_", StringComparison.Ordinal) {
                    throw new InvalidOperationException(
                        schemaName
                            + " residual void calls require an instance setter on an exact duplicated receiver.")
                }
                return
            }
            if ownerFragment != 0
                || !IsVoidType(plan.FragmentResultTypes[ownerFragment]) {
                throw new InvalidOperationException(
                    schemaName
                        + " void calls must be the root result or preserve an enclosing value.")
            }
            return
        }
        state.Push(
            returnType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func GetMethodSignatureDefinition(method: MethodInfo, schemaName: string): MethodInfo {
        if !method.get_IsGenericMethod() {
            return method
        }
        definition := method.GetGenericMethodDefinition()
        definitionArguments := definition.GetGenericArguments()
        constructedArguments := method.GetGenericArguments()
        if !definition.get_IsGenericMethodDefinition()
            || definitionArguments.Length != constructedArguments.Length {
            throw new InvalidOperationException(
                schemaName + " constructed generic method identity is invalid.")
        }
        return definition
    }

    static func DeclaringTypeArguments(declaringType: Type): Type[] {
        if !declaringType.get_IsGenericType() {
            return new Type[](0)
        }
        return declaringType.GetGenericArguments()
    }

    // Reflection.Emit constructed member wrappers can expose the generic definition's raw
    // declaring-type and method-type parameters. Rebuild the exact selected signature from
    // both argument sets so stack validation never depends on wrapper reflection identity.
    static func ResolveMemberSignatureType(
        signatureType: Type,
        declaringArguments: Type[],
        methodArguments: Type[],
        schemaName: string): Type {
        if signatureType.get_IsGenericParameter() {
            position := signatureType.get_GenericParameterPosition()
            if signatureType.get_DeclaringMethod() != null {
                if position < 0 || position >= methodArguments.Length {
                    throw new InvalidOperationException(
                        schemaName + " method generic parameter position is invalid.")
                }
                return methodArguments[position]
            }
            if position < 0 || position >= declaringArguments.Length {
                throw new InvalidOperationException(
                    schemaName + " declaring-type generic parameter position is invalid.")
            }
            return declaringArguments[position]
        }
        if signatureType.get_IsSZArray() {
            elementType := signatureType.GetElementType()
            if elementType == null {
                throw new InvalidOperationException(
                    schemaName + " method array signature has no element type.")
            }
            return ResolveMemberSignatureType(
                elementType,
                declaringArguments,
                methodArguments,
                schemaName).MakeArrayType()
        }
        if signatureType.get_IsGenericType()
            && !signatureType.get_IsGenericTypeDefinition() {
            definition := signatureType.GetGenericTypeDefinition()
            signatureArguments := signatureType.GetGenericArguments()
            resolvedArguments := new Type[](signatureArguments.Length)
            i := 0
            while i < signatureArguments.Length {
                resolvedArguments[i] = ResolveMemberSignatureType(
                    signatureArguments[i],
                    declaringArguments,
                    methodArguments,
                    schemaName)
                i += 1
            }
            return definition.MakeGenericType(resolvedArguments)
        }
        if signatureType.get_HasElementType() {
            compoundElement := signatureType.GetElementType()
            if compoundElement == null {
                throw new InvalidOperationException(
                    schemaName + " compound method signature has no element type.")
            }
            resolvedElement := ResolveMemberSignatureType(
                compoundElement,
                declaringArguments,
                methodArguments,
                schemaName)
            if !ExactTypeShapeMatches(compoundElement, resolvedElement) {
                throw new InvalidOperationException(
                    schemaName + " cannot substitute this compound method signature shape.")
            }
        }
        return signatureType
    }

    static func ApplyConstructor(
        plan: ColumnarCodePlan,
        constructorIndex: int,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        constructorInfo := plan.Constructors[constructorIndex]
        usesDeclaredSignature :=
            plan.ConstructorUsesDeclaredSignature[constructorIndex]
        parameterTypes := usesDeclaredSignature
            ? plan.ConstructorParameterTypes[constructorIndex]
            : ConstructorParameterTypes(constructorInfo)
        parameterIndex := parameterTypes.Length - 1
        while parameterIndex >= 0 {
            value := state.Pop()
            parameterType := parameterTypes[parameterIndex]
            if value.IsAddress
                || !IsStackCompatible(
                    parameterType,
                    value.ValueType,
                    value.ValueKind,
                    value.LiteralKnown,
                    value.LiteralValue) {
                throw new InvalidOperationException(
                    schemaName
                        + " constructor argument does not match its exact parameter type.")
            }
            parameterIndex -= 1
        }
        declaringType := usesDeclaredSignature
            ? plan.ConstructorDeclaringTypes[constructorIndex]
            : constructorInfo.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(
                schemaName + " constructor has no declaring type.")
        }
        state.Push(
            declaringType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func ConstructorParameterTypes(
        constructorInfo: ConstructorInfo): Type[] {
        parameters := constructorInfo.GetParameters()
        result := new Type[](parameters.Length)
        i := 0
        while i < parameters.Length {
            result[i] = parameters[i].get_ParameterType()
            i += 1
        }
        return result
    }

    static func ApplyField(
        plan: ColumnarCodePlan,
        fieldIndex: int,
        loadAddress: bool,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        field := plan.Fields[fieldIndex]
        usesDeclaredSignature := plan.FieldUsesDeclaredSignature[fieldIndex]
        isStatic := usesDeclaredSignature
            ? plan.FieldIsStatic[fieldIndex]
            : field.get_IsStatic()
        if isStatic {
            throw new InvalidOperationException(
                schemaName + " ldfld handles must name instance fields.")
        }
        receiver := state.Pop()
        declaringType := usesDeclaredSignature
            ? plan.FieldDeclaringTypes[fieldIndex]
            : field.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(schemaName + " field has no declaring type.")
        }
        ValidateReceiver(
            declaringType,
            receiver.ValueType,
            receiver.IsAddress,
            receiver.ValueKind,
            "field",
            schemaName)
        state.Push(
            usesDeclaredSignature
                ? plan.FieldValueTypes[fieldIndex]
                : field.get_FieldType(),
            loadAddress,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func ApplyStaticField(
        plan: ColumnarCodePlan,
        fieldIndex: int,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        field := plan.Fields[fieldIndex]
        usesDeclaredSignature := plan.FieldUsesDeclaredSignature[fieldIndex]
        isStatic := usesDeclaredSignature
            ? plan.FieldIsStatic[fieldIndex]
            : field.get_IsStatic()
        if !isStatic || field.get_IsLiteral() {
            throw new InvalidOperationException(
                schemaName + " ldsfld handles must name non-literal static fields.")
        }
        state.Push(
            usesDeclaredSignature
                ? plan.FieldValueTypes[fieldIndex]
                : field.get_FieldType(),
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func ApplyFieldStore(
        plan: ColumnarCodePlan,
        fieldIndex: int,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        field := plan.Fields[fieldIndex]
        if field.get_IsInitOnly() {
            throw new InvalidOperationException(
                schemaName + " stfld handles cannot name init-only fields.")
        }
        usesDeclaredSignature := plan.FieldUsesDeclaredSignature[fieldIndex]
        isStatic := usesDeclaredSignature
            ? plan.FieldIsStatic[fieldIndex]
            : field.get_IsStatic()
        if isStatic {
            throw new InvalidOperationException(
                schemaName + " stfld handles must name instance fields.")
        }

        expectedValueType := usesDeclaredSignature
            ? plan.FieldValueTypes[fieldIndex]
            : field.get_FieldType()
        value := state.Pop()
        if value.IsAddress
            || !IsStackCompatible(
                expectedValueType,
                value.ValueType,
                value.ValueKind,
                value.LiteralKnown,
                value.LiteralValue) {
            throw new InvalidOperationException(
                schemaName + " stfld value does not match its exact field type.")
        }

        declaringType := usesDeclaredSignature
            ? plan.FieldDeclaringTypes[fieldIndex]
            : field.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException(
                schemaName + " stfld field has no declaring type.")
        }
        receiver := state.Pop()
        ValidateReceiver(
            declaringType,
            receiver.ValueType,
            receiver.IsAddress,
            receiver.ValueKind,
            "field",
            schemaName)
        if declaringType.get_IsValueType() {
            if receiver.PlanLocalAddressIndex < 0
                || receiver.PlanLocalAddressIndex >= plan.PlanLocalCount {
                throw new InvalidOperationException(
                    schemaName
                        + " value-type stfld receivers must originate from an exact plan-local address.")
            }
            return
        }

        preserved := state.Head
        if preserved == null || receiver.DuplicateOf != preserved {
            throw new InvalidOperationException(
                schemaName
                    + " reference stfld receivers must duplicate the preserved object-initializer result.")
        }
    }

    static func ValidateReceiver(
        expectedType: Type,
        actualType: Type,
        isAddress: bool,
        actualKind: int,
        memberName: string,
        schemaName: string) {
        if actualKind != ColumnarCodePlanStackValueKind.Exact()
            && actualKind != ColumnarCodePlanStackValueKind.BoxedExact() {
            throw new InvalidOperationException(
                schemaName
                    + " receiver for '"
                    + memberName
                    + "' must have an exact semantic type.")
        }
        if expectedType.get_IsValueType() {
            if actualKind != ColumnarCodePlanStackValueKind.Exact()
                || !isAddress
                || !ExactTypeShapeMatches(expectedType, actualType) {
                throw new InvalidOperationException(
                    schemaName
                        + " value-type receiver for '"
                        + memberName
                        + "' requires an exact managed address.")
            }
        } else if isAddress
            || !IsStackCompatible(expectedType, actualType, actualKind, false, 0) {
            throw new InvalidOperationException(
                schemaName
                    + " reference receiver for '"
                    + memberName
                    + "' does not match its declaring type.")
        }
    }

    static func ApplyArrayElementLoad(
        opCodeValue: short,
        requestedType: Type,
        hasRequestedType: bool,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        indexValue := state.Pop()
        if indexValue.IsAddress
            || !IsArrayIndex(
                indexValue.ValueType,
                indexValue.ValueKind,
                indexValue.LiteralKnown) {
            throw new InvalidOperationException(
                schemaName
                    + " array element loads require exact Int32 or literal I4 index.")
        }
        arrayValue := state.Pop()
        arrayType := arrayValue.ValueType
        elementType := RequireSzArray(arrayType, arrayValue.IsAddress, schemaName)

        if opCodeValue == ColumnarCodePlanContract.Ldelem() {
            if !hasRequestedType || !ExactTypeShapeMatches(requestedType, elementType) {
                throw new InvalidOperationException(
                    schemaName
                        + " ldelem type operands must exactly match the array element type.")
            }
        } else if !TypedElementOpcodeMatches(opCodeValue, elementType) {
            throw new InvalidOperationException(
                schemaName + " typed ldelem opcode does not match the array element type.")
        }
        state.Push(
            elementType,
            false,
            ColumnarCodePlanStackValueKind.Exact(),
            false,
            0)
    }

    static func ApplyArrayElementStore(
        opCodeValue: short,
        requestedType: Type,
        hasRequestedType: bool,
        state: ColumnarCodePlanStackState,
        schemaName: string) {
        value := state.Pop()
        indexValue := state.Pop()
        arrayValue := state.Pop()

        if indexValue.IsAddress
            || !IsArrayIndex(
                indexValue.ValueType,
                indexValue.ValueKind,
                indexValue.LiteralKnown) {
            throw new InvalidOperationException(
                schemaName
                    + " array element stores require exact Int32 or literal I4 index.")
        }
        elementType := RequireSzArray(
            arrayValue.ValueType,
            arrayValue.IsAddress,
            schemaName)

        if opCodeValue == ColumnarCodePlanContract.Stelem() {
            if !hasRequestedType || !ExactTypeShapeMatches(requestedType, elementType) {
                throw new InvalidOperationException(
                    schemaName
                        + " stelem type operands must exactly match the array element type.")
            }
        } else if !TypedStoreOpcodeMatches(opCodeValue, elementType) {
            throw new InvalidOperationException(
                schemaName + " typed stelem opcode does not match the array element type.")
        }

        if value.IsAddress
            || !IsStackCompatible(
                elementType,
                value.ValueType,
                value.ValueKind,
                value.LiteralKnown,
                value.LiteralValue) {
            throw new InvalidOperationException(
                schemaName + " stelem value does not match the array element type.")
        }

        preserved := state.Head
        if preserved == null || arrayValue.DuplicateOf != preserved {
            throw new InvalidOperationException(
                schemaName
                    + " stelem arrays must duplicate the preserved array-construction result.")
        }
    }

    static func RequireSzArray(
        arrayType: Type,
        isAddress: bool,
        schemaName: string): Type {
        if isAddress || arrayType == null || !arrayType.get_IsSZArray() {
            throw new InvalidOperationException(
                schemaName
                    + " array operations require a single-dimensional zero-based array value.")
        }
        elementType := arrayType.GetElementType()
        if elementType == null {
            throw new InvalidOperationException(
                schemaName + " array type has no element type.")
        }
        ValidateStorableType(elementType, "array element", schemaName)
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

    static func TypedStoreOpcodeMatches(opCodeValue: short, elementType: Type): bool {
        if opCodeValue == ColumnarCodePlanContract.StelemI1() {
            return elementType == typeof(bool)
        }
        if opCodeValue == ColumnarCodePlanContract.StelemI2() {
            return elementType == typeof(char)
        }
        if opCodeValue == ColumnarCodePlanContract.StelemI4() {
            return elementType == typeof(int) || elementType == typeof(uint)
        }
        if opCodeValue == ColumnarCodePlanContract.StelemI8() {
            return elementType == typeof(long) || elementType == typeof(ulong)
        }
        if opCodeValue == ColumnarCodePlanContract.StelemR4() {
            return elementType == typeof(float)
        }
        if opCodeValue == ColumnarCodePlanContract.StelemR8() {
            return elementType == typeof(double)
        }
        if opCodeValue == ColumnarCodePlanContract.StelemRef() {
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
        if actualKind == ColumnarCodePlanStackValueKind.I8Slot() {
            return IsI8Destination(expectedType)
        }
        if actualKind == ColumnarCodePlanStackValueKind.NullReference() {
            return !expectedType.get_IsValueType()
                && !expectedType.get_IsGenericParameter()
        }
        if actualKind == ColumnarCodePlanStackValueKind.BoxedExact() {
            if expectedType.get_IsValueType() || expectedType.get_IsGenericParameter() {
                return false
            }
            if expectedType == typeof(object) {
                return true
            }
            return ReferenceAssignableFrom(expectedType, actualType)
        }
        if actualKind != ColumnarCodePlanStackValueKind.Exact() {
            return false
        }
        if ExactTypeShapeMatches(expectedType, actualType) {
            return true
        }
        return !expectedType.get_IsValueType()
            && !actualType.get_IsValueType()
            && ReferenceAssignableFrom(expectedType, actualType)
    }

    static func IsExactPrimitiveAddOperand(
        value: ColumnarCodePlanStackNode,
        expectedType: Type): bool {
        return !value.IsAddress
            && value.ValueType == expectedType
            && value.ValueKind == ColumnarCodePlanStackValueKind.Exact()
    }

    static func IsIntPromotableAddOperand(
        value: ColumnarCodePlanStackNode): bool {
        if value.IsAddress {
            return false
        }
        if value.ValueKind == ColumnarCodePlanStackValueKind.Exact() {
            return ColumnarNumericFacts.IsIntPromotable(value.ValueType)
        }
        return value.ValueType == typeof(int)
            && value.ValueKind == ColumnarCodePlanStackValueKind.LiteralI4()
            && value.LiteralKnown
    }

    static func IsI8Destination(expectedType: Type): bool {
        return expectedType == typeof(long) || expectedType == typeof(ulong)
    }

    // Reflection.Emit creates fresh SymbolType and TypeBuilderInstantiation wrappers
    // around the same unbaked generic arguments. Wrapper shells compare structurally;
    // ordinary types and the generic arguments themselves retain exact identity.
    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        return ColumnarReferenceConversionFacts.ExactTypeShapeMatches(left, right)
    }

    static func ReferenceAssignableFrom(expectedType: Type, actualType: Type): bool {
        if ExactTypeShapeMatches(expectedType, actualType) {
            return true
        }

        if ColumnarReferenceConversionFacts.IsExactKnownUpcast(
            actualType, expectedType) {
            return true
        }

        try {
            return expectedType.IsAssignableFrom(actualType)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
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

    static func CanWidenToI8(valueType: Type, valueKind: int): bool {
        return valueKind == ColumnarCodePlanStackValueKind.LiteralI4()
            || (valueKind == ColumnarCodePlanStackValueKind.Exact()
                && ColumnarNumericFacts.IsIntPromotable(valueType))
    }

    static func CanWidenToR4(valueType: Type, valueKind: int): bool {
        return valueKind == ColumnarCodePlanStackValueKind.LiteralI4()
            || (valueKind == ColumnarCodePlanStackValueKind.Exact()
                && (ColumnarNumericFacts.IsIntPromotable(valueType)
                    || valueType == typeof(long)))
    }

    static func CanWidenToR8(valueType: Type, valueKind: int): bool {
        return valueKind == ColumnarCodePlanStackValueKind.LiteralI4()
            || (valueKind == ColumnarCodePlanStackValueKind.Exact()
                && (ColumnarNumericFacts.IsIntPromotable(valueType)
                    || valueType == typeof(long)
                    || valueType == typeof(float)))
    }

    static func IsLiteralI4Destination(
        valueType: Type,
        literalKnown: bool,
        literalValue: int): bool {
        if valueType == typeof(int) || valueType == typeof(uint) {
            return true
        }
        if valueType.get_IsEnum() {
            return IsLiteralI4Destination(
                valueType.GetEnumUnderlyingType(), literalKnown, literalValue)
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

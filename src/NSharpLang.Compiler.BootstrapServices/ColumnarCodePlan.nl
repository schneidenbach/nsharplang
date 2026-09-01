namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

enum ColumnarFragmentPlanStatus {
    NotOwned = 0,
    Planned = 1
}

enum ColumnarCodePlanLifecycle {
    Empty = 0,
    Building = 1,
    Sealed = 2,
    Consumed = 3
}

class ColumnarCodePlanIdentity {
    Value: int

    constructor() {
        Value = 0
    }
}

// Opcode values are the signed values exposed by System.Reflection.Emit.OpCode.Value.
// They are never positional reflection indices or a second semantic numbering system.
class ColumnarCodePlanContract {

    // Versioned wire identities remain stable across the boolean, recursive, and scalar executors.
    static func CurrentSchemaVersion(): int {
        return 1
    }
    static func RecursiveSchemaVersion(): int {
        return 2
    }
    static func ScalarSchemaVersion(): int {
        return 3
    }
    // Schema v4 is a FULL METHOD BODY: it retains the flat operation stream but drops the
    // single-reachable-result and forward-only-branch invariants of the expression fragment schemas.
    // A method body terminates on every reachable path (Ret/Throw/Leave), permits backward branches
    // (loops), and carries balanced exception regions. It is the wire shape the synchronous iterator
    // state machine (MoveNext/Dispose) lowers into.
    static func MethodBodySchemaVersion(): int {
        return 4
    }

    static func EmitInstructionOperation(): int {
        return 1
    }
    static func MarkLabelOperation(): int {
        return 2
    }
    // Structured exception-region operations (schema v4). They carry no opcode; the executor maps them
    // to the matching ILGenerator region calls. BeginExceptionBlock names a label operand: the executor
    // stores the end label returned by ILGenerator.BeginExceptionBlock() into that label slot so `leave`
    // instructions inside the region can target it. The three handler starters and EndExceptionBlock take
    // no operand. A FAULT handler (runs only on exception, never on a normal `leave`) is what an iterator
    // MoveNext uses to dispose a foreach enumerator without disposing on a `yield return` suspend; a
    // FINALLY handler (runs on every exit including `leave`) backs the generated Dispose() finalizer.
    static func BeginExceptionBlockOperation(): int {
        return 3
    }
    static func BeginFinallyBlockOperation(): int {
        return 4
    }
    static func BeginFaultBlockOperation(): int {
        return 5
    }
    static func EndExceptionBlockOperation(): int {
        return 6
    }
    // Catch handler (schema v4): the operand is the TYPE pool index of the caught exception type; the
    // runtime enters the handler with that exception reference on the evaluation stack.
    static func BeginCatchBlockOperation(): int {
        return 7
    }

    static func NoOperand(): int {
        return 0
    }
    static func Int32Operand(): int {
        return 1
    }
    static func TypeOperand(): int {
        return 2
    }
    static func ArgumentOperand(): int {
        return 3
    }
    static func AmbientLocalOperand(): int {
        return 4
    }
    static func MethodOperand(): int {
        return 5
    }
    static func ConstructorOperand(): int {
        return 6
    }
    static func FieldOperand(): int {
        return 7
    }
    static func PlanLocalOperand(): int {
        return 8
    }
    static func LabelOperand(): int {
        return 9
    }
    static func Int64Operand(): int {
        return 10
    }
    static func SingleOperand(): int {
        return 11
    }
    static func DoubleOperand(): int {
        return 12
    }
    static func StringOperand(): int {
        return 13
    }

    // A private runtime type is the unsealed fragment sentinel because stage-0 cannot lower a
    // null assignment into a Type[] cell. It can never be a language expression result.
    static func UnsealedFragmentResultType(): Type {
        return typeof(ColumnarCodePlanIdentity)
    }

    static func NoOpCode(): short {
        return 0
    }
    static func Ldnull(): short {
        return 20
    }
    static func LdcI4_M1(): short {
        return 21
    }
    static func LdcI4_0(): short {
        return 22
    }
    static func LdcI4_1(): short {
        return 23
    }
    static func LdcI4_2(): short {
        return 24
    }
    static func LdcI4_3(): short {
        return 25
    }
    static func LdcI4_4(): short {
        return 26
    }
    static func LdcI4_5(): short {
        return 27
    }
    static func LdcI4_6(): short {
        return 28
    }
    static func LdcI4_7(): short {
        return 29
    }
    static func LdcI4_8(): short {
        return 30
    }
    static func LdcI4(): short {
        return 32
    }
    static func LdcI8(): short {
        return 33
    }
    static func LdcR4(): short {
        return 34
    }
    static func LdcR8(): short {
        return 35
    }
    static func Dup(): short {
        return 37
    }
    static func Call(): short {
        return 40
    }
    static func Br(): short {
        return 56
    }
    static func Brfalse(): short {
        return 57
    }
    // brtrue (0x3A) is the conditional-branch complement of brfalse (0x39): it pops one Boolean/I4
    // condition and branches when it is non-zero. The short-circuit `||` owner branches to its merge
    // label on a true left operand exactly as the C# emitter's case-12 arm does.
    static func Brtrue(): short {
        return 58
    }
    // Typed byref-dereference opcodes carry their single-byte CIL encodings (ECMA-335 III.3.42):
    // ldind.i1=0x46 through ldind.r8=0x4F, with ldind.i (0x4D, native int) deliberately omitted —
    // the byref-parameter deref family never derefs a native-int slot. ldind.ref (0x50) already
    // sits below with the reference family.
    static func LdindI1(): short {
        return 70
    }
    static func LdindU1(): short {
        return 71
    }
    static func LdindI2(): short {
        return 72
    }
    static func LdindU2(): short {
        return 73
    }
    static func LdindI4(): short {
        return 74
    }
    static func LdindU4(): short {
        return 75
    }
    static func LdindI8(): short {
        return 76
    }
    static func LdindR4(): short {
        return 78
    }
    static func LdindR8(): short {
        return 79
    }
    static func LdindRef(): short {
        return 80
    }
    static func Add(): short {
        return 88
    }
    // Primitive binary arithmetic and bitwise opcodes carry their single-byte CIL encodings.
    static func Sub(): short {
        return 89
    }
    static func Mul(): short {
        return 90
    }
    static func Div(): short {
        return 91
    }
    static func DivUn(): short {
        return 92
    }
    static func Rem(): short {
        return 93
    }
    static func RemUn(): short {
        return 94
    }
    static func And(): short {
        return 95
    }
    static func Or(): short {
        return 96
    }
    static func Xor(): short {
        return 97
    }
    static func Shl(): short {
        return 98
    }
    static func Shr(): short {
        return 99
    }
    static func ShrUn(): short {
        return 100
    }
    static func Neg(): short {
        return 101
    }
    static func Not(): short {
        return 102
    }
    // Explicit numeric-cast conversions carry their single-byte CIL encodings, exactly like the
    // widening conversions the range/index and primitive-binary owners already emit.
    static func ConvI1(): short {
        return 103
    }
    static func ConvI2(): short {
        return 104
    }
    static func ConvI4(): short {
        return 105
    }
    static func ConvI8(): short {
        return 106
    }
    static func ConvR4(): short {
        return 107
    }
    static func ConvR8(): short {
        return 108
    }
    static func ConvU4(): short {
        return 109
    }
    static func ConvU8(): short {
        return 110
    }
    // conv.u2 (0xD1) and conv.u1 (0xD2) are single-byte opcodes whose OpCode.Value stays positive.
    static func ConvU2(): short {
        return 209
    }
    static func ConvU1(): short {
        return 210
    }
    static func Callvirt(): short {
        return 111
    }
    static func Ldstr(): short {
        return 114
    }
    static func Newobj(): short {
        return 115
    }
    static func Castclass(): short {
        return 116
    }
    static func Ldfld(): short {
        return 123
    }
    static func Ldflda(): short {
        return 124
    }
    static func Stfld(): short {
        return 125
    }
    static func Ldsfld(): short {
        return 126
    }
    static func Box(): short {
        return 140
    }
    static func Newarr(): short {
        return 141
    }
    static func Ldlen(): short {
        return 142
    }
    static func LdelemU1(): short {
        return 145
    }
    static func LdelemU2(): short {
        return 147
    }
    static func LdelemI4(): short {
        return 148
    }
    static func LdelemU4(): short {
        return 149
    }
    static func LdelemI8(): short {
        return 150
    }
    static func LdelemR4(): short {
        return 152
    }
    static func LdelemR8(): short {
        return 153
    }
    static func LdelemRef(): short {
        return 154
    }
    static func StelemI1(): short {
        return 156
    }
    static func StelemI2(): short {
        return 157
    }
    static func StelemI4(): short {
        return 158
    }
    static func StelemI8(): short {
        return 159
    }
    static func StelemR4(): short {
        return 160
    }
    static func StelemR8(): short {
        return 161
    }
    static func StelemRef(): short {
        return 162
    }
    static func Ldelem(): short {
        return 163
    }
    static func Stelem(): short {
        return 164
    }
    static func Ldtoken(): short {
        return 208
    }
    // Checked binary arithmetic opcodes carry their single-byte CIL encodings.
    static func AddOvf(): short {
        return 214
    }
    static func AddOvfUn(): short {
        return 215
    }
    static func MulOvf(): short {
        return 216
    }
    static func MulOvfUn(): short {
        return 217
    }
    static func SubOvf(): short {
        return 218
    }
    static func SubOvfUn(): short {
        return 219
    }
    static func Ceq(): short {
        return -511
    }
    // Two-byte FE-prefixed comparison opcodes reinterpret as negative shorts, exactly like Ceq.
    static func Cgt(): short {
        return -510
    }
    static func CgtUn(): short {
        return -509
    }
    static func Clt(): short {
        return -508
    }
    static func CltUn(): short {
        return -507
    }
    static func Initobj(): short {
        return -491
    }

    // Long-form variable opcodes have two-byte ECMA encodings and therefore negative short Values.
    static func Ldarg(): short {
        return -503
    }
    static func Ldarga(): short {
        return -502
    }
    static func Ldloc(): short {
        return -500
    }
    static func Ldloca(): short {
        return -499
    }
    static func Stloc(): short {
        return -498
    }

    // Method-body opcodes (schema v4). Their signed OpCode.Value carries each single-byte CIL encoding,
    // exactly like the expression-fragment opcodes above.
    // ret (0x2A), throw (0x7A), isinst (0x75), stsfld (0x80), and leave (0xDD) stay positive as shorts.
    // ret ends a path (empty stack in a void method, one value otherwise); throw ends a path consuming
    // one reference; leave empties the eval stack and exits an exception region to its end label; isinst
    // pops a reference and pushes a reference-or-null of the operand type; stsfld pops one value.
    static func Ret(): short {
        return 42
    }
    static func Throw(): short {
        return 122
    }
    static func Isinst(): short {
        return 117
    }
    // unbox.any (0xA5) turns a boxed reference into its typed value. It is `box`'s inverse for a value
    // type and behaves as `castclass` for a reference type, which is exactly the pair of arms a
    // synthesized record `Equals` needs: a record STRUCT must unbox its `object` argument before the
    // typed store, and `castclass` cannot express that for a value type.
    static func UnboxAny(): short {
        return 165
    }
    static func Stsfld(): short {
        return 128
    }
    // pop (0x26) discards the top evaluation-stack value. A method body needs it because a body is a
    // STATEMENT sequence: a call whose value the body does not consume must be balanced explicitly,
    // where an expression fragment always has a consumer for its single result.
    static func Pop(): short {
        return 38
    }
    static func Leave(): short {
        return 221
    }

    static func IsBooleanInstructionRow(operationKind: int, opCodeValue: short, operandKind: int): bool {
        return operationKind == EmitInstructionOperation() && operandKind == NoOperand() && (opCodeValue == LdcI4_0() || opCodeValue == LdcI4_1())
    }

    static func IsNoOperandOpcode(opCodeValue: short): bool {
        return (opCodeValue >= LdcI4_M1() && opCodeValue <= LdcI4_8()) || opCodeValue == ConvI4() || opCodeValue == Ldlen() || opCodeValue == LdelemU1() || opCodeValue == LdelemU2() || opCodeValue == LdelemI4() || opCodeValue == LdelemU4() || opCodeValue == LdelemI8() || opCodeValue == LdelemR4() || opCodeValue == LdelemR8() || opCodeValue == LdelemRef()
    }

    static func IsScalarNoOperandOpcode(opCodeValue: short): bool {
        return opCodeValue == Ldnull() || opCodeValue == Dup() || opCodeValue == Add() || opCodeValue == Sub() || opCodeValue == Mul() || opCodeValue == Div() || opCodeValue == DivUn() || opCodeValue == Rem() || opCodeValue == RemUn() || opCodeValue == And() || opCodeValue == Or() || opCodeValue == Xor() || opCodeValue == Shl() || opCodeValue == Shr() || opCodeValue == ShrUn() || opCodeValue == AddOvf() || opCodeValue == AddOvfUn() || opCodeValue == MulOvf() || opCodeValue == MulOvfUn() || opCodeValue == SubOvf() || opCodeValue == SubOvfUn() || opCodeValue == Cgt() || opCodeValue == CgtUn() || opCodeValue == Clt() || opCodeValue == CltUn() || opCodeValue == Neg() || opCodeValue == Not() || opCodeValue == Ceq() || opCodeValue == LdindI1() || opCodeValue == LdindU1() || opCodeValue == LdindI2() || opCodeValue == LdindU2() || opCodeValue == LdindI4() || opCodeValue == LdindU4() || opCodeValue == LdindI8() || opCodeValue == LdindR4() || opCodeValue == LdindR8() || opCodeValue == LdindRef() || opCodeValue == ConvI8() || opCodeValue == ConvR4() || opCodeValue == ConvR8() || opCodeValue == ConvI1() || opCodeValue == ConvI2() || opCodeValue == ConvU4() || opCodeValue == ConvU8() || opCodeValue == ConvU2() || opCodeValue == ConvU1() || opCodeValue == StelemI1() || opCodeValue == StelemI2() || opCodeValue == StelemI4() || opCodeValue == StelemI8() || opCodeValue == StelemR4() || opCodeValue == StelemR8() || opCodeValue == StelemRef()
    }

    static func IsLocalOpcode(opCodeValue: short): bool {
        return opCodeValue == Ldloc() || opCodeValue == Ldloca() || opCodeValue == Stloc()
    }

    // Method-body opcodes (schema v4) that take no operand: ret, throw and pop. Isinst/Stsfld/Leave
    // carry Type/Field/Label operands and are recognized by their respective operand-typed appenders.
    static func IsMethodBodyNoOperandOpcode(opCodeValue: short): bool {
        return opCodeValue == Ret() || opCodeValue == Throw() || opCodeValue == Pop()
    }
}

// A checkpoint is an immutable logical snapshot. Array capacity is deliberately not part of the
// transaction: rollback restores every visible count and the exact open-fragment ancestry.
class ColumnarCodePlanCheckpoint {
    OwnerIdentity: ColumnarCodePlanIdentity
    Generation: int
    SchemaVersion: int
    BranchIndex: int
    OperationCount: int
    TypeCount: int
    Int32Count: int
    Int64Count: int
    SingleCount: int
    DoubleCount: int
    StringCount: int
    ArgumentCount: int
    AmbientLocalCount: int
    MethodCount: int
    ConstructorCount: int
    FieldCount: int
    PlanLocalCount: int
    LabelCount: int
    FragmentCount: int
    OpenFragmentCount: int
    OpenFragmentIndices: int[]

    constructor(ownerIdentity: ColumnarCodePlanIdentity, generation: int, schemaVersion: int, branchIndex: int, operationCount: int, typeCount: int, int32Count: int, int64Count: int, singleCount: int, doubleCount: int, stringCount: int, argumentCount: int, ambientLocalCount: int, methodCount: int, constructorCount: int, fieldCount: int, planLocalCount: int, labelCount: int, fragmentCount: int, openFragmentCount: int, openFragmentIndices: int[]) {
        OwnerIdentity = ownerIdentity
        Generation = generation
        SchemaVersion = schemaVersion
        BranchIndex = branchIndex
        OperationCount = operationCount
        TypeCount = typeCount
        Int32Count = int32Count
        Int64Count = int64Count
        SingleCount = singleCount
        DoubleCount = doubleCount
        StringCount = stringCount
        ArgumentCount = argumentCount
        AmbientLocalCount = ambientLocalCount
        MethodCount = methodCount
        ConstructorCount = constructorCount
        FieldCount = fieldCount
        PlanLocalCount = planLocalCount
        LabelCount = labelCount
        FragmentCount = fragmentCount
        OpenFragmentCount = openFragmentCount
        OpenFragmentIndices = openFragmentIndices
    }
}

// Schema v2 is a callback-free flat payload. Recursive expression ownership is represented by
// nested half-open operation intervals; execution never calls back into a legacy emitter. Schema
// v3 keeps that envelope and adds exact scalar-constant pools and operand contracts.
class ColumnarCodePlan {
    SchemaVersion: int
    Status: ColumnarFragmentPlanStatus
    Lifecycle: ColumnarCodePlanLifecycle
    OperationCount: int
    OperationKinds: int[]
    OpCodeValues: short[]
    OperandKinds: int[]
    OperandIndices: int[]
    OperationOwnerFragmentIndices: int[]
    ResultType: Type?

    TypeCount: int
    Types: Type[]
    Int32Count: int
    Int32Values: int[]
    Int64Count: int
    Int64Values: long[]
    SingleCount: int
    SingleValues: float[]
    DoubleCount: int
    DoubleValues: double[]
    StringCount: int
    StringValues: string[]
    ArgumentCount: int
    ArgumentOrdinals: int[]
    ArgumentTypeIndices: int[]
    // Describes the argument slot itself: true only when ldarg already yields a managed
    // address (a by-reference parameter or value-type instance receiver). It is deliberately
    // false for an ordinary value slot selected by ldarga; the opcode creates that address.
    ArgumentIsAddress: bool[]
    AmbientLocalCount: int
    AmbientLocals: LocalBuilder[]
    MethodCount: int
    Methods: MethodInfo[]
    MethodUsesDeclaredSignature: bool[]
    MethodDeclaringTypes: Type[]
    MethodReturnTypes: Type[]
    MethodParameterTypes: Type[][]
    MethodIsStatic: bool[]
    MethodIsAbstract: bool[]
    ConstructorCount: int
    Constructors: ConstructorInfo[]
    ConstructorUsesDeclaredSignature: bool[]
    ConstructorDeclaringTypes: Type[]
    ConstructorParameterTypes: Type[][]
    FieldCount: int
    Fields: FieldInfo[]
    FieldUsesDeclaredSignature: bool[]
    FieldDeclaringTypes: Type[]
    FieldValueTypes: Type[]
    FieldIsStatic: bool[]

    PlanLocalCount: int
    PlanLocalTypeIndices: int[]
    // 015-B8 — WHICH POOL ENTRIES ARE *MIRRORS* RATHER THAN STORAGE. A mirror is a slot the plan carries
    // so its rows can NAME the enclosing body's local by that body's own pool index, for TYPING only. It
    // is never stored into by this plan, never required to be referenced by it, and never replayed: a
    // mirrored plan is a type-discovery scratch and `ColumnarCodePlanExecutor.Execute` refuses it.
    PlanLocalIsMirror: bool[]
    LabelCount: int

    FragmentCount: int
    FragmentOperationStarts: int[]
    FragmentOperationCounts: int[]
    FragmentParentIndices: int[]
    FragmentKinds: int[]
    FragmentSourceNodeIndices: int[]
    FragmentResultTypes: Type[]
    FragmentCompleted: bool[]

    // The armed mirror VOCABULARY, indexed by the enclosing body's pool index. It is CONFIGURATION rather
    // than state: `Reset` deliberately leaves it alone, so whichever `Prepare*` opens this plan — the
    // scratch site's own, or a callee's — materialises the same vocabulary.
    planLocalMirrorTypes: Type[]

    // The armed NESTED-VALUE FRAME (015-B9) — the second dimension of the same scratch-framing idea, and
    // configuration for the same reason. See `EnableNestedValueFrame`.
    nestedValueFrame: bool

    OpenFragmentCount: int
    OpenFragmentIndices: int[]
    Generation: int
    Identity: ColumnarCodePlanIdentity
    BranchCount: int
    CurrentBranchIndex: int
    BranchParentIndices: int[]

    constructor() {
        SchemaVersion = ColumnarCodePlanContract.CurrentSchemaVersion()
        Status = ColumnarFragmentPlanStatus.NotOwned
        Lifecycle = ColumnarCodePlanLifecycle.Empty
        OperationCount = 0
        OperationKinds = new int[](1)
        OpCodeValues = new short[](1)
        OperandKinds = new int[](1)
        OperandIndices = new int[](1)
        OperationOwnerFragmentIndices = new int[](1)
        OperandIndices[0] = -1
        OperationOwnerFragmentIndices[0] = -1
        ResultType = null

        TypeCount = 0
        Types = new Type[](0)
        Int32Count = 0
        Int32Values = new int[](0)
        Int64Count = 0
        Int64Values = new long[](0)
        SingleCount = 0
        SingleValues = new float[](0)
        DoubleCount = 0
        DoubleValues = new double[](0)
        StringCount = 0
        StringValues = new string[](0)
        ArgumentCount = 0
        ArgumentOrdinals = new int[](0)
        ArgumentTypeIndices = new int[](0)
        ArgumentIsAddress = new bool[](0)
        AmbientLocalCount = 0
        AmbientLocals = new LocalBuilder[](0)
        MethodCount = 0
        Methods = new MethodInfo[](0)
        MethodUsesDeclaredSignature = new bool[](0)
        MethodDeclaringTypes = new Type[](0)
        MethodReturnTypes = new Type[](0)
        MethodParameterTypes = new Type[][](0)
        MethodIsStatic = new bool[](0)
        MethodIsAbstract = new bool[](0)
        ConstructorCount = 0
        Constructors = new ConstructorInfo[](0)
        ConstructorUsesDeclaredSignature = new bool[](0)
        ConstructorDeclaringTypes = new Type[](0)
        ConstructorParameterTypes = new Type[][](0)
        FieldCount = 0
        Fields = new FieldInfo[](0)
        FieldUsesDeclaredSignature = new bool[](0)
        FieldDeclaringTypes = new Type[](0)
        FieldValueTypes = new Type[](0)
        FieldIsStatic = new bool[](0)

        PlanLocalCount = 0
        PlanLocalTypeIndices = new int[](0)
        PlanLocalIsMirror = new bool[](0)
        planLocalMirrorTypes = new Type[](0)
        nestedValueFrame = false
        LabelCount = 0

        FragmentCount = 0
        FragmentOperationStarts = new int[](0)
        FragmentOperationCounts = new int[](0)
        FragmentParentIndices = new int[](0)
        FragmentKinds = new int[](0)
        FragmentSourceNodeIndices = new int[](0)
        FragmentResultTypes = new Type[](0)
        FragmentCompleted = new bool[](0)
        OpenFragmentCount = 0
        OpenFragmentIndices = new int[](0)
        Generation = 0
        Identity = new ColumnarCodePlanIdentity()
        BranchCount = 1
        CurrentBranchIndex = 0
        BranchParentIndices = new int[](1)
        BranchParentIndices[0] = -1
    }

    // Schema-v1 surface retained byte-for-byte at the public call boundary.
    func Prepare() {
        Reset()
        Lifecycle = ColumnarCodePlanLifecycle.Building
        EnsureOperationCapacity(1)
    }

    func AppendInstruction(opCodeValue: short) {
        EnsureV1Building()
        EnsureOperationCapacity(1)
        if OperationCount != 0 {
            throw new InvalidOperationException("Columnar boolean code-plan schema v1 requires exactly one instruction.")
        }
        if opCodeValue != ColumnarCodePlanContract.LdcI4_0() && opCodeValue != ColumnarCodePlanContract.LdcI4_1() {
            throw new InvalidOperationException("Columnar boolean code-plan schema v1 received an unknown opcode value.")
        }

        OperationKinds[0] = ColumnarCodePlanContract.EmitInstructionOperation()
        OpCodeValues[0] = opCodeValue
        OperandKinds[0] = ColumnarCodePlanContract.NoOperand()
        OperandIndices[0] = -1
        OperationOwnerFragmentIndices[0] = -1
        OperationCount = 1
    }

    func CompleteBoolean() {
        EnsureV1Building()
        if !IsV1Structure(false, typeof(bool)) {
            throw new InvalidOperationException("Columnar boolean code-plan schema v1 cannot seal an invalid instruction row.")
        }
        ResultType = typeof(bool)
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    // 015-B8 — ARM THIS PLAN AS A TYPE-DISCOVERY SCRATCH OVER AN ENCLOSING BODY'S LOCAL VOCABULARY.
    //
    // A scratch plan discovers an expression's type by APPENDING that expression into a fresh plan and
    // reading the result back. When the expression reads a local the enclosing body declared, the sole
    // identifier owner appends `ldloc <that body's pool index>` — an index a fresh pool does not have, so
    // the append threw straight out of the compiler. The vocabulary here gives the scratch those indices
    // and their types WITHOUT giving it their storage: the entries are mirrors, and the executor's two
    // plan-local rules exempt them (a mirror need not be referenced, and it enters already assigned,
    // because the enclosing body stored it before this expression could name it).
    //
    // It is armed BEFORE any `Prepare*` on purpose. Two of the four scratch sites hand their plan to a
    // callee that prepares it, so a "mirror right after my own prepare" API could not reach them.
    func EnablePlanLocalMirror(vocabulary: Type[]) {
        if Lifecycle != ColumnarCodePlanLifecycle.Empty || OperationCount != 0 || PlanLocalCount != 0 {
            throw new InvalidOperationException("A plan-local mirror can only be armed on a fresh code plan.")
        }
        if vocabulary == null {
            throw new ArgumentNullException("vocabulary")
        }
        i := 0
        while i < vocabulary.Length {
            if vocabulary[i] == null {
                throw new InvalidOperationException("A plan-local mirror vocabulary cannot carry a null slot type.")
            }
            i = i + 1
        }
        planLocalMirrorTypes = vocabulary
    }

    // True once the armed vocabulary has been materialised into the pool. It is the executor's execution
    // bar: vocabulary is not storage, so a mirrored plan is a scratch and can never be replayed.
    func HasPlanLocalMirror(): bool {
        return planLocalMirrorTypes.Length > 0
    }

    // THE NESTED-VALUE FRAME (015-B9) — the OTHER thing a type-discovery scratch has to say about the
    // enclosing expression, beside the mirror's local vocabulary: WHERE the value it is typing will
    // actually be appended.
    //
    // The value surface asks that question through the sign of the parent fragment
    // (`ColumnarRangeIndexPlanner`'s `allowOrdinaryIntIndex = parentFragment >= 0`), and the rule behind it
    // is about plan ROOTS — an ordinary `arr[0]` at a root belongs to the host, because the facade only
    // owns an index root whose selector may produce `Index`/`Range`. A scratch that plans a call ARGUMENT
    // at `-1` therefore answers a question about a position the value can never occupy, and refuses at the
    // TYPE step exactly what `AppendArguments` would have planned at the APPEND step.
    //
    // ⚠ THE FAITHFUL FIX — open the enclosing fragment in the scratch and nest the value under it — IS NOT
    // EXPRESSIBLE, AND THE PAYLOAD'S OWN RULE IS WHY. `HasValidV2Fragments` refuses a child fragment whose
    // row range equals its parent's (`start == parentStart && end == parentEnd`), and a wrapper around ONE
    // value always spans exactly that value. It was tried first and `CompleteV3` rejected the scratch on
    // the very first corpus target. So the frame is DECLARED rather than fabricated: no rows are invented,
    // the plan's structure is untouched, and the one question the position was a proxy for is answered
    // directly.
    func EnableNestedValueFrame() {
        if Lifecycle != ColumnarCodePlanLifecycle.Empty || OperationCount != 0 || FragmentCount != 0 {
            throw new InvalidOperationException("A nested-value frame can only be armed on a fresh code plan.")
        }
        nestedValueFrame = true
    }

    // Whether this plan types a value whose real home is inside another expression's fragment. It is
    // FALSE on every production plan — only a type-discovery scratch arms it — so a rule that consults it
    // cannot change what an emitted plan does.
    func HasNestedValueFrame(): bool {
        return nestedValueFrame
    }

    func MaterialisePlanLocalMirror() {
        i := 0
        while i < planLocalMirrorTypes.Length {
            typeIndex := AddType(planLocalMirrorTypes[i])
            mirrorIndex := DeclarePlanLocal(typeIndex)
            PlanLocalIsMirror[mirrorIndex] = true
            i = i + 1
        }
    }

    func PrepareV2() {
        Reset()
        SchemaVersion = ColumnarCodePlanContract.RecursiveSchemaVersion()
        Lifecycle = ColumnarCodePlanLifecycle.Building
        EnsureOperationCapacity(4)
        EnsureFragmentCapacity(4)
        EnsureOpenFragmentCapacity(4)
        EnsureBranchCapacity(4)
        MaterialisePlanLocalMirror()
    }

    func PrepareV3() {
        Reset()
        SchemaVersion = ColumnarCodePlanContract.ScalarSchemaVersion()
        Lifecycle = ColumnarCodePlanLifecycle.Building
        EnsureOperationCapacity(4)
        EnsureFragmentCapacity(4)
        EnsureOpenFragmentCapacity(4)
        EnsureBranchCapacity(4)
        EnsureInt64Capacity(4)
        EnsureSingleCapacity(4)
        EnsureDoubleCapacity(4)
        EnsureStringCapacity(4)
        MaterialisePlanLocalMirror()
    }

    // Open a schema-v4 method body for building: a flat operation stream (no fragments) that admits
    // every scalar instruction/pool plus the method-body opcodes and exception regions.
    func PrepareMethodBody() {
        Reset()
        SchemaVersion = ColumnarCodePlanContract.MethodBodySchemaVersion()
        Lifecycle = ColumnarCodePlanLifecycle.Building
        EnsureOperationCapacity(4)
        EnsureBranchCapacity(4)
        EnsureInt64Capacity(4)
        EnsureSingleCapacity(4)
        EnsureDoubleCapacity(4)
        EnsureStringCapacity(4)
        MaterialisePlanLocalMirror()
    }

    func AddType(value: Type): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        EnsureTypeCapacity(TypeCount + 1)
        index := TypeCount
        Types[index] = value
        TypeCount = TypeCount + 1
        return index
    }

    func AddInt32(value: int): int {
        EnsureV2Building()
        EnsureInt32Capacity(Int32Count + 1)
        index := Int32Count
        Int32Values[index] = value
        Int32Count = Int32Count + 1
        return index
    }

    func AddInt64(value: long): int {
        EnsureV3Building()
        EnsureInt64Capacity(Int64Count + 1)
        index := Int64Count
        Int64Values[index] = value
        Int64Count = Int64Count + 1
        return index
    }

    func AddSingle(value: float): int {
        EnsureV3Building()
        EnsureSingleCapacity(SingleCount + 1)
        index := SingleCount
        SingleValues[index] = value
        SingleCount = SingleCount + 1
        return index
    }

    func AddDouble(value: double): int {
        EnsureV3Building()
        EnsureDoubleCapacity(DoubleCount + 1)
        index := DoubleCount
        DoubleValues[index] = value
        DoubleCount = DoubleCount + 1
        return index
    }

    func AddString(value: string): int {
        EnsureV3Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        EnsureStringCapacity(StringCount + 1)
        index := StringCount
        StringValues[index] = value
        StringCount = StringCount + 1
        return index
    }

    func AddArgument(ordinal: int, typeIndex: int): int {
        return AddArgument(ordinal, typeIndex, false)
    }

    func AddArgument(ordinal: int, typeIndex: int, isAddress: bool): int {
        EnsureV2Building()
        if ordinal < 0 || ordinal > 32767 || typeIndex < 0 || typeIndex >= TypeCount {
            throw new ArgumentOutOfRangeException("ordinal")
        }
        EnsureArgumentCapacity(ArgumentCount + 1)
        index := ArgumentCount
        ArgumentOrdinals[index] = ordinal
        ArgumentTypeIndices[index] = typeIndex
        ArgumentIsAddress[index] = isAddress
        ArgumentCount = ArgumentCount + 1
        return index
    }

    func AddAmbientLocal(value: LocalBuilder): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        EnsureAmbientLocalCapacity(AmbientLocalCount + 1)
        index := AmbientLocalCount
        AmbientLocals[index] = value
        AmbientLocalCount = AmbientLocalCount + 1
        return index
    }

    func AddMethod(value: MethodInfo): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        EnsureMethodCapacity(MethodCount + 1)
        index := MethodCount
        Methods[index] = value
        MethodUsesDeclaredSignature[index] = false
        MethodCount = MethodCount + 1
        return index
    }

    // Reflection.Emit MethodBuilder does not expose GetParameters until its owner has been
    // baked. The planner already owns the exact selected signature, so carry that declaration
    // alongside the handle instead of reflecting an unavailable parameter shape.
    func AddMethodWithSignature(value: MethodInfo, declaringType: Type, parameterTypes: Type[], returnType: Type, isStatic: bool, isAbstract: bool): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        if declaringType == null {
            throw new ArgumentNullException("declaringType")
        }
        if parameterTypes == null {
            throw new ArgumentNullException("parameterTypes")
        }
        if returnType == null {
            throw new ArgumentNullException("returnType")
        }
        exactParameterTypes := new Type[](parameterTypes.Length)
        parameterIndex := 0
        while parameterIndex < parameterTypes.Length {
            if parameterTypes[parameterIndex] == null {
                throw new ArgumentNullException("parameterTypes")
            }
            exactParameterTypes[parameterIndex] = parameterTypes[parameterIndex]
            parameterIndex += 1
        }
        EnsureMethodCapacity(MethodCount + 1)
        index := MethodCount
        Methods[index] = value
        MethodUsesDeclaredSignature[index] = true
        MethodDeclaringTypes[index] = declaringType
        MethodReturnTypes[index] = returnType
        MethodParameterTypes[index] = exactParameterTypes
        MethodIsStatic[index] = isStatic
        MethodIsAbstract[index] = isAbstract
        MethodCount = MethodCount + 1
        return index
    }

    func AddConstructor(value: ConstructorInfo): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        EnsureConstructorCapacity(ConstructorCount + 1)
        index := ConstructorCount
        Constructors[index] = value
        ConstructorUsesDeclaredSignature[index] = false
        ConstructorCount = ConstructorCount + 1
        return index
    }

    // A constructor rebound through TypeBuilder.GetConstructor may expose no parameter list
    // until its generic owner is baked. Preserve the selected constructed signature next to the
    // exact handle, just as declared method and field facts do.
    func AddConstructorWithSignature(value: ConstructorInfo, declaringType: Type, parameterTypes: Type[]): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        if declaringType == null {
            throw new ArgumentNullException("declaringType")
        }
        if parameterTypes == null {
            throw new ArgumentNullException("parameterTypes")
        }
        exactParameterTypes := new Type[](parameterTypes.Length)
        parameterIndex := 0
        while parameterIndex < parameterTypes.Length {
            if parameterTypes[parameterIndex] == null {
                throw new ArgumentNullException("parameterTypes")
            }
            exactParameterTypes[parameterIndex] = parameterTypes[parameterIndex]
            parameterIndex += 1
        }
        EnsureConstructorCapacity(ConstructorCount + 1)
        index := ConstructorCount
        Constructors[index] = value
        ConstructorUsesDeclaredSignature[index] = true
        ConstructorDeclaringTypes[index] = declaringType
        ConstructorParameterTypes[index] = exactParameterTypes
        ConstructorCount = ConstructorCount + 1
        return index
    }

    func AddField(value: FieldInfo): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        EnsureFieldCapacity(FieldCount + 1)
        index := FieldCount
        Fields[index] = value
        FieldUsesDeclaredSignature[index] = false
        FieldCount = FieldCount + 1
        return index
    }

    // Reflection.Emit wrappers for fields on a constructed TypeBuilder can expose the open
    // definition's field type. Carry the planner-owned declaring and value types alongside the
    // exact rebound handle so validation and stack simulation use the constructed signature.
    func AddFieldWithSignature(value: FieldInfo, declaringType: Type, valueType: Type, isStatic: bool): int {
        EnsureV2Building()
        if value == null {
            throw new ArgumentNullException("value")
        }
        if declaringType == null {
            throw new ArgumentNullException("declaringType")
        }
        if valueType == null {
            throw new ArgumentNullException("valueType")
        }
        EnsureFieldCapacity(FieldCount + 1)
        index := FieldCount
        Fields[index] = value
        FieldUsesDeclaredSignature[index] = true
        FieldDeclaringTypes[index] = declaringType
        FieldValueTypes[index] = valueType
        FieldIsStatic[index] = isStatic
        FieldCount = FieldCount + 1
        return index
    }

    func DeclarePlanLocal(typeIndex: int): int {
        EnsureV2Building()
        if typeIndex < 0 || typeIndex >= TypeCount {
            throw new ArgumentOutOfRangeException("typeIndex")
        }
        EnsurePlanLocalCapacity(PlanLocalCount + 1)
        index := PlanLocalCount
        PlanLocalTypeIndices[index] = typeIndex
        // Storage by default. `MaterialisePlanLocalMirror` is the ONE writer that flips a slot to mirror,
        // and it does so immediately after declaring it — so a slot rolled back and re-declared is storage
        // again rather than inheriting the flag of whatever occupied that index before it.
        PlanLocalIsMirror[index] = false
        PlanLocalCount = PlanLocalCount + 1
        return index
    }

    func DefineLabel(): int {
        EnsureV2Building()
        index := LabelCount
        LabelCount = LabelCount + 1
        return index
    }

    func BeginFragment(parentIndex: int, fragmentKind: int, sourceNodeIndex: int): int {
        EnsureV2Building()
        if fragmentKind < 0 || sourceNodeIndex < 0 {
            throw new ArgumentOutOfRangeException("fragmentKind")
        }
        // 015-B6 — A METHOD BODY ADMITS MANY ROOT FRAGMENTS; THE EXPRESSION SCHEMAS ADMIT EXACTLY ONE.
        // A body is a sequence of INDEPENDENT expression trees (one per statement, plus the return
        // value), and nothing in the v4 payload gives two of them a parent/child relation:
        // `ValidateMethodBodySemantics` and `ExecuteMethodBodyRows` never read `FragmentCount` or
        // `OperationOwnerFragmentIndices` at all, and `ValidateSealedStructure`'s v4 arm asks only for a
        // result type and a non-empty stream. The alternative — ONE fragment spanning the whole body —
        // was rejected by measurement rather than taste: `CompleteFragment` refuses a `System.Void`
        // result outside a schema-v3 root fragment, so a spanning root is not expressible for the void
        // arity at all, and it would have to invent a result type the body does not have.
        //
        // The relaxation is narrow on purpose. A new root is admitted only BETWEEN trees — nothing may
        // be open — so the nesting rule still governs everything INSIDE one tree, unchanged, on every
        // schema.
        if FragmentCount == 0 {
            if parentIndex != -1 {
                throw new InvalidOperationException("The root code-plan fragment must have no parent.")
            }
        } else if !(IsMethodBodySchema() && parentIndex == -1 && OpenFragmentCount == 0) && (OpenFragmentCount == 0 || parentIndex != OpenFragmentIndices[OpenFragmentCount - 1]) {
            throw new InvalidOperationException("A recursive code-plan fragment must be nested under the current open fragment.")
        }

        EnsureFragmentCapacity(FragmentCount + 1)
        EnsureOpenFragmentCapacity(OpenFragmentCount + 1)
        index := FragmentCount
        FragmentOperationStarts[index] = OperationCount
        FragmentOperationCounts[index] = 0
        FragmentParentIndices[index] = parentIndex
        FragmentKinds[index] = fragmentKind
        FragmentSourceNodeIndices[index] = sourceNodeIndex
        FragmentResultTypes[index] = ColumnarCodePlanContract.UnsealedFragmentResultType()
        FragmentCompleted[index] = false
        FragmentCount = FragmentCount + 1
        OpenFragmentIndices[OpenFragmentCount] = index
        OpenFragmentCount = OpenFragmentCount + 1
        return index
    }

    func CompleteFragment(fragmentIndex: int, resultType: Type) {
        EnsureV2Building()
        if resultType == null {
            throw new ArgumentNullException("resultType")
        }
        if resultType == ColumnarCodePlanContract.UnsealedFragmentResultType() {
            throw new InvalidOperationException("Expression fragments cannot use the unsealed result sentinel.")
        }
        if OpenFragmentCount == 0 || fragmentIndex != OpenFragmentIndices[OpenFragmentCount - 1] || fragmentIndex < 0 || fragmentIndex >= FragmentCount {
            throw new InvalidOperationException("Code-plan fragments must complete in nesting order.")
        }
        if resultType.FullName == "System.Void" {
            if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || fragmentIndex != 0 {
                throw new InvalidOperationException("Only a schema-v3 root code-plan fragment can declare a void result.")
            }
        }

        FragmentOperationCounts[fragmentIndex] = OperationCount - FragmentOperationStarts[fragmentIndex]
        FragmentResultTypes[fragmentIndex] = resultType
        FragmentCompleted[fragmentIndex] = true
        OpenFragmentCount = OpenFragmentCount - 1
    }

    func AppendInstructionWithoutOperand(opCodeValue: short) {
        EnsureV2Building()
        if !ColumnarCodePlanContract.IsNoOperandOpcode(opCodeValue) && !(AllowsScalarOrMethodBodyInstructions() && ColumnarCodePlanContract.IsScalarNoOperandOpcode(opCodeValue)) && !(IsMethodBodySchema() && ColumnarCodePlanContract.IsMethodBodyNoOperandOpcode(opCodeValue)) {
            throw new InvalidOperationException("The opcode does not use an operand-free row.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.NoOperand(), -1)
    }

    func AppendInt32Instruction(opCodeValue: short, int32Index: int) {
        EnsureV2Building()
        if opCodeValue != ColumnarCodePlanContract.LdcI4() || int32Index < 0 || int32Index >= Int32Count {
            throw new InvalidOperationException("The opcode does not use this Int32 pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.Int32Operand(), int32Index)
    }

    func AppendInt64Instruction(opCodeValue: short, int64Index: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.LdcI8() || int64Index < 0 || int64Index >= Int64Count {
            throw new InvalidOperationException("The opcode does not use this Int64 pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.Int64Operand(), int64Index)
    }

    func AppendSingleInstruction(opCodeValue: short, singleIndex: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.LdcR4() || singleIndex < 0 || singleIndex >= SingleCount {
            throw new InvalidOperationException("The opcode does not use this Single pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.SingleOperand(), singleIndex)
    }

    func AppendDoubleInstruction(opCodeValue: short, doubleIndex: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.LdcR8() || doubleIndex < 0 || doubleIndex >= DoubleCount {
            throw new InvalidOperationException("The opcode does not use this Double pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.DoubleOperand(), doubleIndex)
    }

    func AppendStringInstruction(opCodeValue: short, stringIndex: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.Ldstr() || stringIndex < 0 || stringIndex >= StringCount {
            throw new InvalidOperationException("The opcode does not use this String pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.StringOperand(), stringIndex)
    }

    func AppendTypeInstruction(opCodeValue: short, typeIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Ldelem() && (!AllowsScalarOrMethodBodyInstructions() || (opCodeValue != ColumnarCodePlanContract.Ldtoken() && opCodeValue != ColumnarCodePlanContract.Box() && opCodeValue != ColumnarCodePlanContract.Castclass() && opCodeValue != ColumnarCodePlanContract.Initobj() && opCodeValue != ColumnarCodePlanContract.Newarr() && opCodeValue != ColumnarCodePlanContract.Stelem())) && !(IsMethodBodySchema() && (opCodeValue == ColumnarCodePlanContract.Isinst() || opCodeValue == ColumnarCodePlanContract.UnboxAny()))) || typeIndex < 0 || typeIndex >= TypeCount {
            throw new InvalidOperationException("The opcode does not use this type pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.TypeOperand(), typeIndex)
    }

    func AppendArgumentInstruction(opCodeValue: short, argumentIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Ldarg() && opCodeValue != ColumnarCodePlanContract.Ldarga()) || argumentIndex < 0 || argumentIndex >= ArgumentCount || (opCodeValue == ColumnarCodePlanContract.Ldarga() && ArgumentIsAddress[argumentIndex]) {
            throw new InvalidOperationException("The opcode does not use this argument pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.ArgumentOperand(), argumentIndex)
    }

    func AppendAmbientLocalInstruction(opCodeValue: short, ambientLocalIndex: int) {
        EnsureV2Building()
        if !ColumnarCodePlanContract.IsLocalOpcode(opCodeValue) || ambientLocalIndex < 0 || ambientLocalIndex >= AmbientLocalCount {
            throw new InvalidOperationException("The opcode does not use this ambient-local pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.AmbientLocalOperand(), ambientLocalIndex)
    }

    func AppendMethodInstruction(opCodeValue: short, methodIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Call() && opCodeValue != ColumnarCodePlanContract.Callvirt()) || methodIndex < 0 || methodIndex >= MethodCount {
            throw new InvalidOperationException("The opcode does not use this method pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.MethodOperand(), methodIndex)
    }

    func AppendConstructorInstruction(opCodeValue: short, constructorIndex: int) {
        EnsureV2Building()
        if opCodeValue != ColumnarCodePlanContract.Newobj() || constructorIndex < 0 || constructorIndex >= ConstructorCount {
            throw new InvalidOperationException("The opcode does not use this constructor pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.ConstructorOperand(), constructorIndex)
    }

    func AppendFieldInstruction(opCodeValue: short, fieldIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Ldfld() && (!AllowsScalarOrMethodBodyInstructions() || (opCodeValue != ColumnarCodePlanContract.Ldflda() && opCodeValue != ColumnarCodePlanContract.Stfld() && opCodeValue != ColumnarCodePlanContract.Ldsfld())) && !(IsMethodBodySchema() && opCodeValue == ColumnarCodePlanContract.Stsfld())) || fieldIndex < 0 || fieldIndex >= FieldCount {
            throw new InvalidOperationException("The opcode does not use this field pool entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.FieldOperand(), fieldIndex)
    }

    func AppendPlanLocalInstruction(opCodeValue: short, planLocalIndex: int) {
        EnsureV2Building()
        if !ColumnarCodePlanContract.IsLocalOpcode(opCodeValue) || planLocalIndex < 0 || planLocalIndex >= PlanLocalCount {
            throw new InvalidOperationException("The opcode does not use this plan-local entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.PlanLocalOperand(), planLocalIndex)
    }

    func AppendLabelInstruction(opCodeValue: short, labelIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Br() && opCodeValue != ColumnarCodePlanContract.Brfalse() && opCodeValue != ColumnarCodePlanContract.Brtrue() && !(IsMethodBodySchema() && opCodeValue == ColumnarCodePlanContract.Leave())) || labelIndex < 0 || labelIndex >= LabelCount {
            throw new InvalidOperationException("The opcode does not use this label entry.")
        }
        AppendV2Row(ColumnarCodePlanContract.EmitInstructionOperation(), opCodeValue, ColumnarCodePlanContract.LabelOperand(), labelIndex)
    }

    func AppendMarkLabel(labelIndex: int) {
        EnsureV2Building()
        if labelIndex < 0 || labelIndex >= LabelCount {
            throw new InvalidOperationException("The mark-label row references an unknown label.")
        }
        AppendV2Row(ColumnarCodePlanContract.MarkLabelOperation(), ColumnarCodePlanContract.NoOpCode(), ColumnarCodePlanContract.LabelOperand(), labelIndex)
    }

    // Structured exception-region rows (schema v4 only). BeginExceptionBlock names a label operand: the
    // executor writes the end label returned by ILGenerator.BeginExceptionBlock() into that slot, so
    // `leave` rows inside the region target it. The handler starters and EndExceptionBlock take no operand.
    func AppendBeginExceptionBlock(labelIndex: int) {
        EnsureV2Building()
        if !IsMethodBodySchema() {
            throw new InvalidOperationException("Exception regions require the method-body schema.")
        }
        if labelIndex < 0 || labelIndex >= LabelCount {
            throw new InvalidOperationException("The begin-exception-block row references an unknown label.")
        }
        AppendV2Row(ColumnarCodePlanContract.BeginExceptionBlockOperation(), ColumnarCodePlanContract.NoOpCode(), ColumnarCodePlanContract.LabelOperand(), labelIndex)
    }

    func AppendBeginFinallyBlock() {
        AppendRegionMarker(ColumnarCodePlanContract.BeginFinallyBlockOperation())
    }

    // Open a catch handler for the current region. The type-pool operand is the caught exception type;
    // the handler's first row sees that exception reference already on the stack.
    func AppendBeginCatchBlock(typeIndex: int) {
        EnsureV2Building()
        if !IsMethodBodySchema() {
            throw new InvalidOperationException("Exception regions require the method-body schema.")
        }
        if typeIndex < 0 || typeIndex >= TypeCount {
            throw new InvalidOperationException("The begin-catch-block row references an unknown type.")
        }
        AppendV2Row(ColumnarCodePlanContract.BeginCatchBlockOperation(), ColumnarCodePlanContract.NoOpCode(), ColumnarCodePlanContract.TypeOperand(), typeIndex)
    }

    func AppendBeginFaultBlock() {
        AppendRegionMarker(ColumnarCodePlanContract.BeginFaultBlockOperation())
    }

    func AppendEndExceptionBlock() {
        AppendRegionMarker(ColumnarCodePlanContract.EndExceptionBlockOperation())
    }

    func AppendRegionMarker(operationKind: int) {
        EnsureV2Building()
        if !IsMethodBodySchema() {
            throw new InvalidOperationException("Exception regions require the method-body schema.")
        }
        AppendV2Row(operationKind, ColumnarCodePlanContract.NoOpCode(), ColumnarCodePlanContract.NoOperand(), -1)
    }

    func CreateCheckpoint(): ColumnarCodePlanCheckpoint {
        EnsureV2Building()
        checkpointBranchIndex := CreateBranch(CurrentBranchIndex)
        openFragments := new int[](OpenFragmentCount)
        i := 0
        while i < OpenFragmentCount {
            openFragments[i] = OpenFragmentIndices[i]
            i += 1
        }
        return new ColumnarCodePlanCheckpoint(Identity, Generation, SchemaVersion, checkpointBranchIndex, OperationCount, TypeCount, Int32Count, Int64Count, SingleCount, DoubleCount, StringCount, ArgumentCount, AmbientLocalCount, MethodCount, ConstructorCount, FieldCount, PlanLocalCount, LabelCount, FragmentCount, OpenFragmentCount, openFragments)
    }

    func Rollback(checkpoint: ColumnarCodePlanCheckpoint) {
        EnsureV2Building()
        if checkpoint == null {
            throw new InvalidOperationException("The code-plan checkpoint is stale or belongs to another plan.")
        }
        if checkpoint.OwnerIdentity != Identity {
            throw new InvalidOperationException("The code-plan checkpoint is stale or belongs to another plan.")
        }
        if checkpoint.Generation != Generation {
            throw new InvalidOperationException("The code-plan checkpoint is stale or belongs to another plan.")
        }
        if checkpoint.SchemaVersion != SchemaVersion {
            throw new InvalidOperationException("The code-plan checkpoint belongs to another schema version.")
        }
        if !IsActiveCheckpointBranch(checkpoint.BranchIndex) {
            throw new InvalidOperationException("The code-plan checkpoint belongs to a discarded planning branch.")
        }
        if !CheckpointCountsAreValid(checkpoint) {
            throw new InvalidOperationException("The code-plan checkpoint is stale or belongs to another plan.")
        }

        i := 0
        while i < checkpoint.OpenFragmentCount {
            fragmentIndex := checkpoint.OpenFragmentIndices[i]
            if fragmentIndex < 0 || fragmentIndex >= checkpoint.FragmentCount || (i == 0 && FragmentParentIndices[fragmentIndex] != -1) || (i > 0 && FragmentParentIndices[fragmentIndex] != checkpoint.OpenFragmentIndices[i - 1]) {
                throw new InvalidOperationException("The code-plan checkpoint has corrupt fragment ancestry.")
            }
            i += 1
        }

        OperationCount = checkpoint.OperationCount
        TypeCount = checkpoint.TypeCount
        Int32Count = checkpoint.Int32Count
        Int64Count = checkpoint.Int64Count
        SingleCount = checkpoint.SingleCount
        DoubleCount = checkpoint.DoubleCount
        StringCount = checkpoint.StringCount
        ArgumentCount = checkpoint.ArgumentCount
        AmbientLocalCount = checkpoint.AmbientLocalCount
        MethodCount = checkpoint.MethodCount
        ConstructorCount = checkpoint.ConstructorCount
        FieldCount = checkpoint.FieldCount
        PlanLocalCount = checkpoint.PlanLocalCount
        LabelCount = checkpoint.LabelCount
        FragmentCount = checkpoint.FragmentCount
        OpenFragmentCount = checkpoint.OpenFragmentCount
        EnsureOpenFragmentCapacity(OpenFragmentCount)

        i = 0
        while i < OpenFragmentCount {
            fragmentIndex := checkpoint.OpenFragmentIndices[i]
            OpenFragmentIndices[i] = fragmentIndex
            FragmentOperationCounts[fragmentIndex] = 0
            FragmentResultTypes[fragmentIndex] = ColumnarCodePlanContract.UnsealedFragmentResultType()
            FragmentCompleted[fragmentIndex] = false
            i += 1
        }
        ResultType = null
        Status = ColumnarFragmentPlanStatus.NotOwned
        CreateBranch(checkpoint.BranchIndex)
    }

    func CreateBranch(parentIndex: int): int {
        EnsureBranchCapacity(BranchCount + 1)
        branchIndex := BranchCount
        BranchParentIndices[branchIndex] = parentIndex
        BranchCount = BranchCount + 1
        CurrentBranchIndex = branchIndex
        return branchIndex
    }

    func IsActiveCheckpointBranch(branchIndex: int): bool {
        if branchIndex <= 0 || branchIndex >= BranchCount {
            return false
        }
        current := CurrentBranchIndex
        while current >= 0 {
            if current == branchIndex {
                return true
            }
            current = BranchParentIndices[current]
        }
        return false
    }

    func CheckpointCountsAreValid(checkpoint: ColumnarCodePlanCheckpoint): bool {
        if checkpoint.OperationCount < 0 || checkpoint.OperationCount > OperationCount {
            return false
        }
        if checkpoint.TypeCount < 0 || checkpoint.TypeCount > TypeCount {
            return false
        }
        if checkpoint.Int32Count < 0 || checkpoint.Int32Count > Int32Count {
            return false
        }
        if checkpoint.Int64Count < 0 || checkpoint.Int64Count > Int64Count {
            return false
        }
        if checkpoint.SingleCount < 0 || checkpoint.SingleCount > SingleCount {
            return false
        }
        if checkpoint.DoubleCount < 0 || checkpoint.DoubleCount > DoubleCount {
            return false
        }
        if checkpoint.StringCount < 0 || checkpoint.StringCount > StringCount {
            return false
        }
        if checkpoint.ArgumentCount < 0 || checkpoint.ArgumentCount > ArgumentCount {
            return false
        }
        if checkpoint.AmbientLocalCount < 0 || checkpoint.AmbientLocalCount > AmbientLocalCount {
            return false
        }
        if checkpoint.MethodCount < 0 || checkpoint.MethodCount > MethodCount {
            return false
        }
        if checkpoint.ConstructorCount < 0 || checkpoint.ConstructorCount > ConstructorCount {
            return false
        }
        if checkpoint.FieldCount < 0 || checkpoint.FieldCount > FieldCount {
            return false
        }
        if checkpoint.PlanLocalCount < 0 || checkpoint.PlanLocalCount > PlanLocalCount {
            return false
        }
        if checkpoint.LabelCount < 0 || checkpoint.LabelCount > LabelCount {
            return false
        }
        if checkpoint.FragmentCount < 0 || checkpoint.FragmentCount > FragmentCount {
            return false
        }
        return checkpoint.OpenFragmentCount >= 0 && checkpoint.OpenFragmentCount <= checkpoint.FragmentCount && checkpoint.OpenFragmentIndices != null && checkpoint.OpenFragmentIndices.Length >= checkpoint.OpenFragmentCount
    }

    func CompleteV2(resultType: Type) {
        EnsureV2Building()
        if resultType == null || !IsV2Structure(false, resultType) {
            throw new InvalidOperationException("Columnar code-plan schema v2 cannot seal an invalid payload.")
        }
        ResultType = resultType
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    func ConsumeV2() {
        if SchemaVersion != ColumnarCodePlanContract.RecursiveSchemaVersion() || Status != ColumnarFragmentPlanStatus.Planned || Lifecycle != ColumnarCodePlanLifecycle.Sealed || ResultType == null || !IsV2Structure(true, ResultType) {
            throw new InvalidOperationException("Columnar code-plan schema v2 is not ready for one-shot execution.")
        }
        Lifecycle = ColumnarCodePlanLifecycle.Consumed
    }

    func CompleteV3(resultType: Type) {
        EnsureV3Building()
        if resultType == null || !IsV3Structure(false, resultType) {
            throw new InvalidOperationException("Columnar code-plan schema v3 cannot seal an invalid payload.")
        }
        ResultType = resultType
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    func ConsumeV3() {
        if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || Status != ColumnarFragmentPlanStatus.Planned || Lifecycle != ColumnarCodePlanLifecycle.Sealed || ResultType == null || !IsV3Structure(true, ResultType) {
            throw new InvalidOperationException("Columnar code-plan schema v3 is not ready for one-shot execution.")
        }
        Lifecycle = ColumnarCodePlanLifecycle.Consumed
    }

    // Seal a method body. ResultType is the METHOD return type (typeof(void) for a void body); it is the
    // arity the validator checks each `ret` against. There is no single-result invariant: the body
    // terminates on every reachable path. Deep control-flow/stack validation runs in the executor's
    // method-body validator, not here.
    func CompleteMethodBody(resultType: Type) {
        EnsureV2Building()
        if !IsMethodBodySchema() {
            throw new InvalidOperationException("Only a method-body plan can be sealed as a method body.")
        }
        if resultType == null {
            throw new InvalidOperationException("A method-body plan requires a return type (typeof(void) for a void body).")
        }
        if OperationCount == 0 {
            throw new InvalidOperationException("A method-body plan requires at least one operation.")
        }
        ResultType = resultType
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    func ConsumeMethodBody() {
        if !IsMethodBodySchema() || Status != ColumnarFragmentPlanStatus.Planned || Lifecycle != ColumnarCodePlanLifecycle.Sealed || ResultType == null {
            throw new InvalidOperationException("Columnar method-body plan is not ready for one-shot execution.")
        }
        Lifecycle = ColumnarCodePlanLifecycle.Consumed
    }

    // This method is intentionally pure: it never repairs, grows, normalizes, or otherwise mutates
    // a payload. Executors can call it completely before the first Reflection.Emit operation.
    func ValidateSealedStructure() {
        if SchemaVersion == ColumnarCodePlanContract.CurrentSchemaVersion() {
            if !IsV1Structure(true, typeof(bool)) {
                throw new InvalidOperationException("Columnar code-plan schema v1 payload is invalid.")
            }
            return
        }
        if SchemaVersion == ColumnarCodePlanContract.RecursiveSchemaVersion() && ResultType != null && IsV2Structure(true, ResultType) {
            return
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && ResultType != null && IsV3Structure(true, ResultType) {
            return
        }
        // A sealed method body carries a return type and a non-empty flat operation stream. Its control
        // flow and stack discipline are proven by the executor's method-body validator, not by the
        // fragment-structure invariants the expression schemas use.
        if SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion() && ResultType != null && OperationCount > 0 {
            return
        }
        throw new InvalidOperationException("Columnar code-plan payload has an unknown or invalid schema.")
    }

    func Reset() {
        SchemaVersion = ColumnarCodePlanContract.CurrentSchemaVersion()
        Status = ColumnarFragmentPlanStatus.NotOwned
        Lifecycle = ColumnarCodePlanLifecycle.Empty
        OperationCount = 0
        ResultType = null
        TypeCount = 0
        Int32Count = 0
        Int64Count = 0
        SingleCount = 0
        DoubleCount = 0
        StringCount = 0
        ArgumentCount = 0
        AmbientLocalCount = 0
        MethodCount = 0
        ConstructorCount = 0
        FieldCount = 0
        PlanLocalCount = 0
        LabelCount = 0
        FragmentCount = 0
        OpenFragmentCount = 0
        Generation = Generation + 1
        BranchCount = 1
        CurrentBranchIndex = 0
        EnsureBranchCapacity(1)
        BranchParentIndices[0] = -1
    }

    func AppendV2Row(operationKind: int, opCodeValue: short, operandKind: int, operandIndex: int) {
        // A method body (schema v4) is a FLAT operation stream with no fragment tree: its rows carry
        // owner index -1. The recursive expression schemas still require every row to belong to an open
        // fragment.
        fragmentOwner := -1
        if OpenFragmentCount > 0 {
            fragmentOwner = OpenFragmentIndices[OpenFragmentCount - 1]
        } else if !IsMethodBodySchema() {
            throw new InvalidOperationException("Schema-v2 operations must belong to an open fragment.")
        }
        EnsureOperationCapacity(OperationCount + 1)
        OperationKinds[OperationCount] = operationKind
        OpCodeValues[OperationCount] = opCodeValue
        OperandKinds[OperationCount] = operandKind
        OperandIndices[OperationCount] = operandIndex
        OperationOwnerFragmentIndices[OperationCount] = fragmentOwner
        OperationCount = OperationCount + 1
    }

    func EnsureV1Building() {
        if SchemaVersion != ColumnarCodePlanContract.CurrentSchemaVersion() || Status != ColumnarFragmentPlanStatus.NotOwned || Lifecycle == ColumnarCodePlanLifecycle.Sealed {
            throw new InvalidOperationException("Columnar code plan is no longer open for mutation.")
        }
        if Lifecycle == ColumnarCodePlanLifecycle.Empty {
            Lifecycle = ColumnarCodePlanLifecycle.Building
        }
        if Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Columnar code plan is not in its building lifecycle.")
        }
    }

    func EnsureV2Building() {
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() || SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion() {
            EnsureV3Building()
            return
        }
        if SchemaVersion != ColumnarCodePlanContract.RecursiveSchemaVersion() || Status != ColumnarFragmentPlanStatus.NotOwned || Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Columnar code-plan schema v2 is not open for mutation.")
        }
    }

    // Schema v4 (method body) is a superset of v3: it admits every scalar instruction and pool plus the
    // method-body opcodes and exception regions, so it shares the v3 building gate.
    func EnsureV3Building() {
        if (SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || Status != ColumnarFragmentPlanStatus.NotOwned || Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Columnar code-plan schema v3 is not open for mutation.")
        }
    }

    func IsMethodBodySchema(): bool {
        return SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    }

    func AllowsScalarOrMethodBodyInstructions(): bool {
        return SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() || SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    }

    func HasNoV2State(): bool {
        return TypeCount == 0 && Int32Count == 0 && HasNoV3State() && HasValidV3Pools() && ArgumentCount == 0 && AmbientLocalCount == 0 && MethodCount == 0 && ConstructorCount == 0 && FieldCount == 0 && PlanLocalCount == 0 && LabelCount == 0 && FragmentCount == 0 && OpenFragmentCount == 0
    }

    func HasNoV3State(): bool {
        return Int64Count == 0 && SingleCount == 0 && DoubleCount == 0 && StringCount == 0
    }

    func IsV1Structure(sealedPayload: bool, expectedResultType: Type): bool {
        if SchemaVersion != ColumnarCodePlanContract.CurrentSchemaVersion() || OperationCount != 1 || OperationKinds == null || OpCodeValues == null || OperandKinds == null || OperandIndices == null || OperationOwnerFragmentIndices == null || OperationKinds.Length < 1 || OpCodeValues.Length < 1 || OperandKinds.Length < 1 || OperandIndices.Length < 1 || OperationOwnerFragmentIndices.Length < 1 || OperandIndices[0] != -1 || OperationOwnerFragmentIndices[0] != -1 || !HasNoV2State() || !ColumnarCodePlanContract.IsBooleanInstructionRow(OperationKinds[0], OpCodeValues[0], OperandKinds[0]) {
            return false
        }
        if sealedPayload {
            return Status == ColumnarFragmentPlanStatus.Planned && Lifecycle == ColumnarCodePlanLifecycle.Sealed && ResultType == expectedResultType
        }
        return Status == ColumnarFragmentPlanStatus.NotOwned && Lifecycle == ColumnarCodePlanLifecycle.Building && ResultType == null
    }

    func IsV2Structure(sealedPayload: bool, expectedResultType: Type): bool {
        if SchemaVersion != ColumnarCodePlanContract.RecursiveSchemaVersion() || expectedResultType == null || !HasNoV3State() || !HasValidV3Pools() || !HasValidV2ColumnsAndPools() || !HasValidV2Fragments(expectedResultType, false) || !HasValidV2Rows() {
            return false
        }
        if sealedPayload {
            return Status == ColumnarFragmentPlanStatus.Planned && Lifecycle == ColumnarCodePlanLifecycle.Sealed && ResultType == expectedResultType && OpenFragmentCount == 0
        }
        return Status == ColumnarFragmentPlanStatus.NotOwned && Lifecycle == ColumnarCodePlanLifecycle.Building && ResultType == null && OpenFragmentCount == 0
    }

    func IsV3Structure(sealedPayload: bool, expectedResultType: Type): bool {
        if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || expectedResultType == null || !HasValidV3Pools() || !HasValidV2ColumnsAndPools() || !HasValidV2Fragments(expectedResultType, true) || !HasValidV2Rows() {
            return false
        }
        if sealedPayload {
            return Status == ColumnarFragmentPlanStatus.Planned && Lifecycle == ColumnarCodePlanLifecycle.Sealed && ResultType == expectedResultType && OpenFragmentCount == 0
        }
        return Status == ColumnarFragmentPlanStatus.NotOwned && Lifecycle == ColumnarCodePlanLifecycle.Building && ResultType == null && OpenFragmentCount == 0
    }

    func HasValidV3Pools(): bool {
        if Int64Count < 0 || SingleCount < 0 || DoubleCount < 0 || StringCount < 0 || Int64Values == null || Int64Values.Length < Int64Count || SingleValues == null || SingleValues.Length < SingleCount || DoubleValues == null || DoubleValues.Length < DoubleCount || StringValues == null || StringValues.Length < StringCount {
            return false
        }
        i := 0
        while i < StringCount {
            if StringValues[i] == null {
                return false
            }
            i += 1
        }
        return true
    }

    func HasValidV2ColumnsAndPools(): bool {
        if OperationCount <= 0 || TypeCount < 0 || Int32Count < 0 || ArgumentCount < 0 || AmbientLocalCount < 0 || MethodCount < 0 || ConstructorCount < 0 || FieldCount < 0 || PlanLocalCount < 0 || LabelCount < 0 || FragmentCount <= 0 || OperationKinds == null || OpCodeValues == null || OperandKinds == null || OperandIndices == null || OperationOwnerFragmentIndices == null || OperationKinds.Length < OperationCount || OpCodeValues.Length < OperationCount || OperandKinds.Length < OperationCount || OperandIndices.Length < OperationCount || OperationOwnerFragmentIndices.Length < OperationCount || Types == null || Types.Length < TypeCount || Int32Values == null || Int32Values.Length < Int32Count || ArgumentOrdinals == null || ArgumentTypeIndices == null || ArgumentIsAddress == null || ArgumentOrdinals.Length < ArgumentCount || ArgumentTypeIndices.Length < ArgumentCount || ArgumentIsAddress.Length < ArgumentCount || AmbientLocals == null || AmbientLocals.Length < AmbientLocalCount || Methods == null || Methods.Length < MethodCount || MethodUsesDeclaredSignature == null || MethodUsesDeclaredSignature.Length < MethodCount || MethodDeclaringTypes == null || MethodDeclaringTypes.Length < MethodCount || MethodReturnTypes == null || MethodReturnTypes.Length < MethodCount || MethodParameterTypes == null || MethodParameterTypes.Length < MethodCount || MethodIsStatic == null || MethodIsStatic.Length < MethodCount || MethodIsAbstract == null || MethodIsAbstract.Length < MethodCount || Constructors == null || Constructors.Length < ConstructorCount || ConstructorUsesDeclaredSignature == null || ConstructorUsesDeclaredSignature.Length < ConstructorCount || ConstructorDeclaringTypes == null || ConstructorDeclaringTypes.Length < ConstructorCount || ConstructorParameterTypes == null || ConstructorParameterTypes.Length < ConstructorCount || Fields == null || Fields.Length < FieldCount || FieldUsesDeclaredSignature == null || FieldUsesDeclaredSignature.Length < FieldCount || FieldDeclaringTypes == null || FieldDeclaringTypes.Length < FieldCount || FieldValueTypes == null || FieldValueTypes.Length < FieldCount || FieldIsStatic == null || FieldIsStatic.Length < FieldCount || PlanLocalTypeIndices == null || PlanLocalTypeIndices.Length < PlanLocalCount || PlanLocalIsMirror == null || PlanLocalIsMirror.Length < PlanLocalCount {
            return false
        }

        i := 0
        while i < TypeCount {
            if Types[i] == null {
                return false
            }
            i += 1
        }
        i = 0
        while i < ArgumentCount {
            if ArgumentOrdinals[i] < 0 || ArgumentOrdinals[i] > 32767 || ArgumentTypeIndices[i] < 0 || ArgumentTypeIndices[i] >= TypeCount {
                return false
            }
            i += 1
        }
        i = 0
        while i < AmbientLocalCount {
            if AmbientLocals[i] == null {
                return false
            }
            i += 1
        }
        i = 0
        while i < MethodCount {
            if Methods[i] == null {
                return false
            }
            if MethodUsesDeclaredSignature[i] {
                if MethodDeclaringTypes[i] == null || MethodReturnTypes[i] == null || MethodParameterTypes[i] == null {
                    return false
                }
                parameterIndex := 0
                while parameterIndex < MethodParameterTypes[i].Length {
                    if MethodParameterTypes[i][parameterIndex] == null {
                        return false
                    }
                    parameterIndex += 1
                }
            }
            i += 1
        }
        i = 0
        while i < ConstructorCount {
            if Constructors[i] == null {
                return false
            }
            if ConstructorUsesDeclaredSignature[i] {
                if ConstructorDeclaringTypes[i] == null || ConstructorParameterTypes[i] == null {
                    return false
                }
                parameterIndex := 0
                while parameterIndex < ConstructorParameterTypes[i].Length {
                    if ConstructorParameterTypes[i][parameterIndex] == null {
                        return false
                    }
                    parameterIndex += 1
                }
            }
            i += 1
        }
        i = 0
        while i < FieldCount {
            if Fields[i] == null {
                return false
            }
            if FieldUsesDeclaredSignature[i] && (FieldDeclaringTypes[i] == null || FieldValueTypes[i] == null) {
                return false
            }
            i += 1
        }
        i = 0
        while i < PlanLocalCount {
            if PlanLocalTypeIndices[i] < 0 || PlanLocalTypeIndices[i] >= TypeCount {
                return false
            }
            i += 1
        }
        return true
    }

    func HasValidV2Fragments(expectedResultType: Type, allowVoidRoot: bool): bool {
        if FragmentOperationStarts == null || FragmentOperationCounts == null || FragmentParentIndices == null || FragmentKinds == null || FragmentSourceNodeIndices == null || FragmentResultTypes == null || FragmentCompleted == null || FragmentOperationStarts.Length < FragmentCount || FragmentOperationCounts.Length < FragmentCount || FragmentParentIndices.Length < FragmentCount || FragmentKinds.Length < FragmentCount || FragmentSourceNodeIndices.Length < FragmentCount || FragmentResultTypes.Length < FragmentCount || FragmentCompleted.Length < FragmentCount || FragmentParentIndices[0] != -1 || FragmentOperationStarts[0] != 0 || FragmentOperationCounts[0] != OperationCount || FragmentResultTypes[0] != expectedResultType || (expectedResultType.FullName == "System.Void" && !allowVoidRoot) {
            return false
        }

        // Fragments are appended in depth-first planning order. Maintain the active ancestor
        // stack once so validation remains linear even for maximally deep expression trees.
        activeFragments := new int[](FragmentCount)
        activeCount := 0
        i := 0
        previousStart := -1
        while i < FragmentCount {
            start := FragmentOperationStarts[i]
            count := FragmentOperationCounts[i]
            end := start + count
            if !FragmentCompleted[i] || FragmentResultTypes[i] == null || FragmentResultTypes[i] == ColumnarCodePlanContract.UnsealedFragmentResultType() || (FragmentResultTypes[i].FullName == "System.Void" && (!allowVoidRoot || i != 0)) || FragmentKinds[i] < 0 || FragmentSourceNodeIndices[i] < 0 || start < 0 || count <= 0 || end < start || end > OperationCount || start < previousStart {
                return false
            }

            keepPopping := true
            while activeCount > 0 && keepPopping {
                activeIndex := activeFragments[activeCount - 1]
                activeEnd := FragmentOperationStarts[activeIndex] + FragmentOperationCounts[activeIndex]
                if start >= activeEnd {
                    activeCount -= 1
                } else {
                    keepPopping = false
                }
            }

            expectedParent := -1
            if activeCount > 0 {
                expectedParent = activeFragments[activeCount - 1]
            }
            if FragmentParentIndices[i] != expectedParent {
                return false
            }
            if i > 0 {
                if expectedParent < 0 || expectedParent >= i {
                    return false
                }
                parentStart := FragmentOperationStarts[expectedParent]
                parentEnd := parentStart + FragmentOperationCounts[expectedParent]
                if start < parentStart || end > parentEnd || (start == parentStart && end == parentEnd) {
                    return false
                }
            }

            activeFragments[activeCount] = i
            activeCount += 1
            previousStart = start
            i += 1
        }
        return true
    }

    func HasValidV2Rows(): bool {
        activeFragments := new int[](FragmentCount)
        activeCount := 0
        nextFragment := 0
        i := 0
        while i < OperationCount {
            operationKind := OperationKinds[i]
            opCodeValue := OpCodeValues[i]
            operandKind := OperandKinds[i]
            operandIndex := OperandIndices[i]
            ownerFragmentIndex := OperationOwnerFragmentIndices[i]

            while activeCount > 0 {
                activeIndex := activeFragments[activeCount - 1]
                activeEnd := FragmentOperationStarts[activeIndex] + FragmentOperationCounts[activeIndex]
                if activeEnd <= i {
                    activeCount -= 1
                } else {
                    break
                }
            }
            while nextFragment < FragmentCount && FragmentOperationStarts[nextFragment] == i {
                activeFragments[activeCount] = nextFragment
                activeCount += 1
                nextFragment += 1
            }
            if activeCount == 0 || ownerFragmentIndex != activeFragments[activeCount - 1] {
                return false
            }

            if operationKind == ColumnarCodePlanContract.MarkLabelOperation() {
                if opCodeValue != ColumnarCodePlanContract.NoOpCode() || operandKind != ColumnarCodePlanContract.LabelOperand() || operandIndex < 0 || operandIndex >= LabelCount {
                    return false
                }
            } else if operationKind != ColumnarCodePlanContract.EmitInstructionOperation() || !IsValidInstructionOperand(opCodeValue, operandKind, operandIndex) {
                return false
            }
            i += 1
        }
        return true
    }

    func IsValidInstructionOperand(opCodeValue: short, operandKind: int, operandIndex: int): bool {
        if ColumnarCodePlanContract.IsNoOperandOpcode(opCodeValue) || (SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && ColumnarCodePlanContract.IsScalarNoOperandOpcode(opCodeValue)) {
            return operandKind == ColumnarCodePlanContract.NoOperand() && operandIndex == -1
        }
        if opCodeValue == ColumnarCodePlanContract.LdcI4() {
            return operandKind == ColumnarCodePlanContract.Int32Operand() && operandIndex >= 0 && operandIndex < Int32Count
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && opCodeValue == ColumnarCodePlanContract.LdcI8() {
            return operandKind == ColumnarCodePlanContract.Int64Operand() && operandIndex >= 0 && operandIndex < Int64Count
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && opCodeValue == ColumnarCodePlanContract.LdcR4() {
            return operandKind == ColumnarCodePlanContract.SingleOperand() && operandIndex >= 0 && operandIndex < SingleCount
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && opCodeValue == ColumnarCodePlanContract.LdcR8() {
            return operandKind == ColumnarCodePlanContract.DoubleOperand() && operandIndex >= 0 && operandIndex < DoubleCount
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && opCodeValue == ColumnarCodePlanContract.Ldstr() {
            return operandKind == ColumnarCodePlanContract.StringOperand() && operandIndex >= 0 && operandIndex < StringCount
        }
        if opCodeValue == ColumnarCodePlanContract.Ldarg() || opCodeValue == ColumnarCodePlanContract.Ldarga() {
            return operandKind == ColumnarCodePlanContract.ArgumentOperand() && operandIndex >= 0 && operandIndex < ArgumentCount && (opCodeValue != ColumnarCodePlanContract.Ldarga() || !ArgumentIsAddress[operandIndex])
        }
        if ColumnarCodePlanContract.IsLocalOpcode(opCodeValue) {
            return (operandKind == ColumnarCodePlanContract.AmbientLocalOperand() && operandIndex >= 0 && operandIndex < AmbientLocalCount) || (operandKind == ColumnarCodePlanContract.PlanLocalOperand() && operandIndex >= 0 && operandIndex < PlanLocalCount)
        }
        if opCodeValue == ColumnarCodePlanContract.Call() || opCodeValue == ColumnarCodePlanContract.Callvirt() {
            return operandKind == ColumnarCodePlanContract.MethodOperand() && operandIndex >= 0 && operandIndex < MethodCount
        }
        if opCodeValue == ColumnarCodePlanContract.Newobj() {
            return operandKind == ColumnarCodePlanContract.ConstructorOperand() && operandIndex >= 0 && operandIndex < ConstructorCount
        }
        if opCodeValue == ColumnarCodePlanContract.Ldfld() || (SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && (opCodeValue == ColumnarCodePlanContract.Ldflda() || opCodeValue == ColumnarCodePlanContract.Stfld() || opCodeValue == ColumnarCodePlanContract.Ldsfld())) {
            return operandKind == ColumnarCodePlanContract.FieldOperand() && operandIndex >= 0 && operandIndex < FieldCount
        }
        if opCodeValue == ColumnarCodePlanContract.Br() || opCodeValue == ColumnarCodePlanContract.Brfalse() || opCodeValue == ColumnarCodePlanContract.Brtrue() {
            return operandKind == ColumnarCodePlanContract.LabelOperand() && operandIndex >= 0 && operandIndex < LabelCount
        }
        if opCodeValue == ColumnarCodePlanContract.Ldelem() || (SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() && (opCodeValue == ColumnarCodePlanContract.Ldtoken() || opCodeValue == ColumnarCodePlanContract.Box() || opCodeValue == ColumnarCodePlanContract.Castclass() || opCodeValue == ColumnarCodePlanContract.Initobj() || opCodeValue == ColumnarCodePlanContract.Newarr() || opCodeValue == ColumnarCodePlanContract.Stelem())) {
            return operandKind == ColumnarCodePlanContract.TypeOperand() && operandIndex >= 0 && operandIndex < TypeCount
        }
        return false
    }

    func EnsureOperationCapacity(minimum: int) {
        if OperationKinds == null || OperationKinds.Length < minimum || OpCodeValues == null || OpCodeValues.Length < minimum || OperandKinds == null || OperandKinds.Length < minimum || OperandIndices == null || OperandIndices.Length < minimum || OperationOwnerFragmentIndices == null || OperationOwnerFragmentIndices.Length < minimum {
            capacity := NextCapacity(OperationKinds == null ? 0 : OperationKinds.Length, minimum)
            OperationKinds = GrowIntArray(OperationKinds, capacity)
            OpCodeValues = GrowShortArray(OpCodeValues, capacity)
            OperandKinds = GrowIntArray(OperandKinds, capacity)
            oldLength := OperandIndices == null ? 0 : OperandIndices.Length
            OperandIndices = GrowIntArray(OperandIndices, capacity)
            ownerOldLength := OperationOwnerFragmentIndices == null ? 0 : OperationOwnerFragmentIndices.Length
            OperationOwnerFragmentIndices = GrowIntArray(OperationOwnerFragmentIndices, capacity)
            i := oldLength
            while i < capacity {
                OperandIndices[i] = -1
                i += 1
            }
            i = ownerOldLength
            while i < capacity {
                OperationOwnerFragmentIndices[i] = -1
                i += 1
            }
        }
    }

    func EnsureTypeCapacity(minimum: int) {
        if Types == null || Types.Length < minimum {
            Types = GrowTypeArray(Types, NextCapacity(Types == null ? 0 : Types.Length, minimum))
        }
    }

    func EnsureInt32Capacity(minimum: int) {
        if Int32Values == null || Int32Values.Length < minimum {
            Int32Values = GrowIntArray(Int32Values, NextCapacity(Int32Values == null ? 0 : Int32Values.Length, minimum))
        }
    }

    func EnsureInt64Capacity(minimum: int) {
        if Int64Values == null || Int64Values.Length < minimum {
            Int64Values = GrowLongArray(Int64Values, NextCapacity(Int64Values == null ? 0 : Int64Values.Length, minimum))
        }
    }

    func EnsureSingleCapacity(minimum: int) {
        if SingleValues == null || SingleValues.Length < minimum {
            SingleValues = GrowFloatArray(SingleValues, NextCapacity(SingleValues == null ? 0 : SingleValues.Length, minimum))
        }
    }

    func EnsureDoubleCapacity(minimum: int) {
        if DoubleValues == null || DoubleValues.Length < minimum {
            DoubleValues = GrowDoubleArray(DoubleValues, NextCapacity(DoubleValues == null ? 0 : DoubleValues.Length, minimum))
        }
    }

    func EnsureStringCapacity(minimum: int) {
        if StringValues == null || StringValues.Length < minimum {
            StringValues = GrowStringArray(StringValues, NextCapacity(StringValues == null ? 0 : StringValues.Length, minimum))
        }
    }

    func EnsureArgumentCapacity(minimum: int) {
        if ArgumentOrdinals == null || ArgumentOrdinals.Length < minimum || ArgumentTypeIndices == null || ArgumentTypeIndices.Length < minimum || ArgumentIsAddress == null || ArgumentIsAddress.Length < minimum {
            capacity := NextCapacity(ArgumentOrdinals == null ? 0 : ArgumentOrdinals.Length, minimum)
            ArgumentOrdinals = GrowIntArray(ArgumentOrdinals, capacity)
            ArgumentTypeIndices = GrowIntArray(ArgumentTypeIndices, capacity)
            ArgumentIsAddress = GrowBoolArray(ArgumentIsAddress, capacity)
        }
    }

    func EnsureAmbientLocalCapacity(minimum: int) {
        if AmbientLocals == null || AmbientLocals.Length < minimum {
            AmbientLocals = GrowLocalArray(AmbientLocals, NextCapacity(AmbientLocals == null ? 0 : AmbientLocals.Length, minimum))
        }
    }

    func EnsureMethodCapacity(minimum: int) {
        if Methods == null || Methods.Length < minimum || MethodUsesDeclaredSignature == null || MethodUsesDeclaredSignature.Length < minimum || MethodDeclaringTypes == null || MethodDeclaringTypes.Length < minimum || MethodReturnTypes == null || MethodReturnTypes.Length < minimum || MethodParameterTypes == null || MethodParameterTypes.Length < minimum || MethodIsStatic == null || MethodIsStatic.Length < minimum || MethodIsAbstract == null || MethodIsAbstract.Length < minimum {
            capacity := NextCapacity(Methods == null ? 0 : Methods.Length, minimum)
            Methods = GrowMethodArray(Methods, capacity)
            MethodUsesDeclaredSignature = GrowBoolArray(MethodUsesDeclaredSignature, capacity)
            MethodDeclaringTypes = GrowTypeArray(MethodDeclaringTypes, capacity)
            MethodReturnTypes = GrowTypeArray(MethodReturnTypes, capacity)
            MethodParameterTypes = GrowTypeArrayArray(MethodParameterTypes, capacity)
            MethodIsStatic = GrowBoolArray(MethodIsStatic, capacity)
            MethodIsAbstract = GrowBoolArray(MethodIsAbstract, capacity)
        }
    }

    func EnsureConstructorCapacity(minimum: int) {
        if Constructors == null || Constructors.Length < minimum || ConstructorUsesDeclaredSignature == null || ConstructorUsesDeclaredSignature.Length < minimum || ConstructorDeclaringTypes == null || ConstructorDeclaringTypes.Length < minimum || ConstructorParameterTypes == null || ConstructorParameterTypes.Length < minimum {
            capacity := NextCapacity(Constructors == null ? 0 : Constructors.Length, minimum)
            Constructors = GrowConstructorArray(Constructors, capacity)
            ConstructorUsesDeclaredSignature = GrowBoolArray(ConstructorUsesDeclaredSignature, capacity)
            ConstructorDeclaringTypes = GrowTypeArray(ConstructorDeclaringTypes, capacity)
            ConstructorParameterTypes = GrowTypeArrayArray(ConstructorParameterTypes, capacity)
        }
    }

    func EnsureFieldCapacity(minimum: int) {
        if Fields == null || Fields.Length < minimum || FieldUsesDeclaredSignature == null || FieldUsesDeclaredSignature.Length < minimum || FieldDeclaringTypes == null || FieldDeclaringTypes.Length < minimum || FieldValueTypes == null || FieldValueTypes.Length < minimum || FieldIsStatic == null || FieldIsStatic.Length < minimum {
            capacity := NextCapacity(Fields == null ? 0 : Fields.Length, minimum)
            Fields = GrowFieldArray(Fields, capacity)
            FieldUsesDeclaredSignature = GrowBoolArray(FieldUsesDeclaredSignature, capacity)
            FieldDeclaringTypes = GrowTypeArray(FieldDeclaringTypes, capacity)
            FieldValueTypes = GrowTypeArray(FieldValueTypes, capacity)
            FieldIsStatic = GrowBoolArray(FieldIsStatic, capacity)
        }
    }

    func EnsurePlanLocalCapacity(minimum: int) {
        if PlanLocalTypeIndices == null || PlanLocalTypeIndices.Length < minimum || PlanLocalIsMirror == null || PlanLocalIsMirror.Length < minimum {
            capacity := NextCapacity(PlanLocalTypeIndices == null ? 0 : PlanLocalTypeIndices.Length, minimum)
            PlanLocalTypeIndices = GrowIntArray(PlanLocalTypeIndices, capacity)
            PlanLocalIsMirror = GrowBoolArray(PlanLocalIsMirror, capacity)
        }
    }

    func EnsureFragmentCapacity(minimum: int) {
        if FragmentOperationStarts == null || FragmentOperationStarts.Length < minimum || FragmentOperationCounts == null || FragmentOperationCounts.Length < minimum || FragmentParentIndices == null || FragmentParentIndices.Length < minimum || FragmentKinds == null || FragmentKinds.Length < minimum || FragmentSourceNodeIndices == null || FragmentSourceNodeIndices.Length < minimum || FragmentResultTypes == null || FragmentResultTypes.Length < minimum || FragmentCompleted == null || FragmentCompleted.Length < minimum {
            capacity := NextCapacity(FragmentOperationStarts == null ? 0 : FragmentOperationStarts.Length, minimum)
            FragmentOperationStarts = GrowIntArray(FragmentOperationStarts, capacity)
            FragmentOperationCounts = GrowIntArray(FragmentOperationCounts, capacity)
            FragmentParentIndices = GrowIntArray(FragmentParentIndices, capacity)
            FragmentKinds = GrowIntArray(FragmentKinds, capacity)
            FragmentSourceNodeIndices = GrowIntArray(FragmentSourceNodeIndices, capacity)
            FragmentResultTypes = GrowTypeArray(FragmentResultTypes, capacity)
            FragmentCompleted = GrowBoolArray(FragmentCompleted, capacity)
        }
    }

    func EnsureOpenFragmentCapacity(minimum: int) {
        if OpenFragmentIndices == null || OpenFragmentIndices.Length < minimum {
            OpenFragmentIndices = GrowIntArray(OpenFragmentIndices, NextCapacity(OpenFragmentIndices == null ? 0 : OpenFragmentIndices.Length, minimum))
        }
    }

    func EnsureBranchCapacity(minimum: int) {
        if BranchParentIndices == null || BranchParentIndices.Length < minimum {
            oldLength := BranchParentIndices == null ? 0 : BranchParentIndices.Length
            BranchParentIndices = GrowIntArray(BranchParentIndices, NextCapacity(oldLength, minimum))
            i := oldLength
            while i < BranchParentIndices.Length {
                BranchParentIndices[i] = -1
                i += 1
            }
        }
    }

    static func NextCapacity(current: int, minimum: int): int {
        capacity := current
        if capacity < 4 {
            capacity = 4
        }
        while capacity < minimum {
            if capacity > 1073741823 {
                return minimum
            }
            capacity *= 2
        }
        return capacity
    }

    static func GrowIntArray(values: int[], capacity: int): int[] {
        result := new int[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowShortArray(values: short[], capacity: int): short[] {
        result := new short[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowLongArray(values: long[], capacity: int): long[] {
        result := new long[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowFloatArray(values: float[], capacity: int): float[] {
        result := new float[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowDoubleArray(values: double[], capacity: int): double[] {
        result := new double[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowStringArray(values: string[], capacity: int): string[] {
        result := new string[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowBoolArray(values: bool[], capacity: int): bool[] {
        result := new bool[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowTypeArray(values: Type[], capacity: int): Type[] {
        result := new Type[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowTypeArrayArray(values: Type[][], capacity: int): Type[][] {
        result := new Type[][](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowLocalArray(values: LocalBuilder[], capacity: int): LocalBuilder[] {
        result := new LocalBuilder[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowMethodArray(values: MethodInfo[], capacity: int): MethodInfo[] {
        result := new MethodInfo[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowConstructorArray(values: ConstructorInfo[], capacity: int): ConstructorInfo[] {
        result := new ConstructorInfo[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }

    static func GrowFieldArray(values: FieldInfo[], capacity: int): FieldInfo[] {
        result := new FieldInfo[](capacity)
        if values != null {
            count := values.Length < capacity ? values.Length : capacity
            i := 0
            while i < count {
                result[i] = values[i]
                i += 1
            }
        }
        return result
    }
}

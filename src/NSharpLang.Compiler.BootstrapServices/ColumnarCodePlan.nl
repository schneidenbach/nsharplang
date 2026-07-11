namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

public enum ColumnarFragmentPlanStatus {
    NotOwned = 0,
    Planned = 1
}

public enum ColumnarCodePlanLifecycle {
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
public class ColumnarCodePlanContract {
    // Versioned wire identities remain stable across the boolean, recursive, and scalar executors.
    public static func CurrentSchemaVersion(): int { return 1 }
    public static func RecursiveSchemaVersion(): int { return 2 }
    public static func ScalarSchemaVersion(): int { return 3 }

    public static func EmitInstructionOperation(): int { return 1 }
    public static func MarkLabelOperation(): int { return 2 }

    public static func NoOperand(): int { return 0 }
    public static func Int32Operand(): int { return 1 }
    public static func TypeOperand(): int { return 2 }
    public static func ArgumentOperand(): int { return 3 }
    public static func AmbientLocalOperand(): int { return 4 }
    public static func MethodOperand(): int { return 5 }
    public static func ConstructorOperand(): int { return 6 }
    public static func FieldOperand(): int { return 7 }
    public static func PlanLocalOperand(): int { return 8 }
    public static func LabelOperand(): int { return 9 }
    public static func Int64Operand(): int { return 10 }
    public static func SingleOperand(): int { return 11 }
    public static func DoubleOperand(): int { return 12 }
    public static func StringOperand(): int { return 13 }

    // A private runtime type is the unsealed fragment sentinel because stage-0 cannot lower a
    // null assignment into a Type[] cell. It can never be a language expression result.
    public static func UnsealedFragmentResultType(): Type {
        return typeof(ColumnarCodePlanIdentity)
    }

    public static func NoOpCode(): short { return 0 }
    public static func Ldnull(): short { return 20 }
    public static func LdcI4_M1(): short { return 21 }
    public static func LdcI4_0(): short { return 22 }
    public static func LdcI4_1(): short { return 23 }
    public static func LdcI4_2(): short { return 24 }
    public static func LdcI4_3(): short { return 25 }
    public static func LdcI4_4(): short { return 26 }
    public static func LdcI4_5(): short { return 27 }
    public static func LdcI4_6(): short { return 28 }
    public static func LdcI4_7(): short { return 29 }
    public static func LdcI4_8(): short { return 30 }
    public static func LdcI4(): short { return 32 }
    public static func LdcI8(): short { return 33 }
    public static func LdcR4(): short { return 34 }
    public static func LdcR8(): short { return 35 }
    public static func Call(): short { return 40 }
    public static func Br(): short { return 56 }
    public static func Brfalse(): short { return 57 }
    public static func LdindRef(): short { return 80 }
    public static func Neg(): short { return 101 }
    public static func Not(): short { return 102 }
    public static func ConvI4(): short { return 105 }
    public static func ConvI8(): short { return 106 }
    public static func ConvR4(): short { return 107 }
    public static func ConvR8(): short { return 108 }
    public static func Callvirt(): short { return 111 }
    public static func Ldstr(): short { return 114 }
    public static func Newobj(): short { return 115 }
    public static func Ldfld(): short { return 123 }
    public static func Ldflda(): short { return 124 }
    public static func Ldsfld(): short { return 126 }
    public static func Box(): short { return 140 }
    public static func Ldlen(): short { return 142 }
    public static func LdelemU1(): short { return 145 }
    public static func LdelemU2(): short { return 147 }
    public static func LdelemI4(): short { return 148 }
    public static func LdelemU4(): short { return 149 }
    public static func LdelemI8(): short { return 150 }
    public static func LdelemR4(): short { return 152 }
    public static func LdelemR8(): short { return 153 }
    public static func LdelemRef(): short { return 154 }
    public static func Ldelem(): short { return 163 }
    public static func Ldtoken(): short { return 208 }
    public static func Ceq(): short { return -511 }
    public static func Initobj(): short { return -491 }

    // Long-form variable opcodes have two-byte ECMA encodings and therefore negative short Values.
    public static func Ldarg(): short { return -503 }
    public static func Ldarga(): short { return -502 }
    public static func Ldloc(): short { return -500 }
    public static func Ldloca(): short { return -499 }
    public static func Stloc(): short { return -498 }

    public static func IsBooleanInstructionRow(
        operationKind: int,
        opCodeValue: short,
        operandKind: int): bool {
        return operationKind == EmitInstructionOperation()
            && operandKind == NoOperand()
            && (opCodeValue == LdcI4_0() || opCodeValue == LdcI4_1())
    }

    public static func IsNoOperandOpcode(opCodeValue: short): bool {
        return (opCodeValue >= LdcI4_M1() && opCodeValue <= LdcI4_8())
            || opCodeValue == ConvI4()
            || opCodeValue == Ldlen()
            || opCodeValue == LdelemU1()
            || opCodeValue == LdelemU2()
            || opCodeValue == LdelemI4()
            || opCodeValue == LdelemU4()
            || opCodeValue == LdelemI8()
            || opCodeValue == LdelemR4()
            || opCodeValue == LdelemR8()
            || opCodeValue == LdelemRef()
    }

    public static func IsScalarNoOperandOpcode(opCodeValue: short): bool {
        return opCodeValue == Ldnull()
            || opCodeValue == Neg()
            || opCodeValue == Not()
            || opCodeValue == Ceq()
            || opCodeValue == LdindRef()
            || opCodeValue == ConvI8()
            || opCodeValue == ConvR4()
            || opCodeValue == ConvR8()
    }

    public static func IsLocalOpcode(opCodeValue: short): bool {
        return opCodeValue == Ldloc()
            || opCodeValue == Ldloca()
            || opCodeValue == Stloc()
    }
}

// A checkpoint is an immutable logical snapshot. Array capacity is deliberately not part of the
// transaction: rollback restores every visible count and the exact open-fragment ancestry.
public class ColumnarCodePlanCheckpoint {
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

    constructor(
        ownerIdentity: ColumnarCodePlanIdentity,
        generation: int,
        schemaVersion: int,
        branchIndex: int,
        operationCount: int,
        typeCount: int,
        int32Count: int,
        int64Count: int,
        singleCount: int,
        doubleCount: int,
        stringCount: int,
        argumentCount: int,
        ambientLocalCount: int,
        methodCount: int,
        constructorCount: int,
        fieldCount: int,
        planLocalCount: int,
        labelCount: int,
        fragmentCount: int,
        openFragmentCount: int,
        openFragmentIndices: int[]) {
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
public class ColumnarCodePlan {
    public SchemaVersion: int
    public Status: ColumnarFragmentPlanStatus
    public Lifecycle: ColumnarCodePlanLifecycle
    public OperationCount: int
    public OperationKinds: int[]
    public OpCodeValues: short[]
    public OperandKinds: int[]
    public OperandIndices: int[]
    public OperationOwnerFragmentIndices: int[]
    public ResultType: Type?

    public TypeCount: int
    public Types: Type[]
    public Int32Count: int
    public Int32Values: int[]
    public Int64Count: int
    public Int64Values: long[]
    public SingleCount: int
    public SingleValues: float[]
    public DoubleCount: int
    public DoubleValues: double[]
    public StringCount: int
    public StringValues: string[]
    public ArgumentCount: int
    public ArgumentOrdinals: int[]
    public ArgumentTypeIndices: int[]
    // Describes the argument slot itself: true only when ldarg already yields a managed
    // address (a by-reference parameter or value-type instance receiver). It is deliberately
    // false for an ordinary value slot selected by ldarga; the opcode creates that address.
    public ArgumentIsAddress: bool[]
    public AmbientLocalCount: int
    public AmbientLocals: LocalBuilder[]
    public MethodCount: int
    public Methods: MethodInfo[]
    public MethodUsesDeclaredSignature: bool[]
    public MethodDeclaringTypes: Type[]
    public MethodReturnTypes: Type[]
    public MethodParameterTypes: Type[][]
    public MethodIsStatic: bool[]
    public MethodIsAbstract: bool[]
    public ConstructorCount: int
    public Constructors: ConstructorInfo[]
    public ConstructorUsesDeclaredSignature: bool[]
    public ConstructorDeclaringTypes: Type[]
    public ConstructorParameterTypes: Type[][]
    public FieldCount: int
    public Fields: FieldInfo[]
    public FieldUsesDeclaredSignature: bool[]
    public FieldDeclaringTypes: Type[]
    public FieldValueTypes: Type[]
    public FieldIsStatic: bool[]

    public PlanLocalCount: int
    public PlanLocalTypeIndices: int[]
    public LabelCount: int

    public FragmentCount: int
    public FragmentOperationStarts: int[]
    public FragmentOperationCounts: int[]
    public FragmentParentIndices: int[]
    public FragmentKinds: int[]
    public FragmentSourceNodeIndices: int[]
    public FragmentResultTypes: Type[]
    public FragmentCompleted: bool[]

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
    public func Prepare() {
        Reset()
        Lifecycle = ColumnarCodePlanLifecycle.Building
        EnsureOperationCapacity(1)
    }

    public func AppendInstruction(opCodeValue: short) {
        EnsureV1Building()
        EnsureOperationCapacity(1)
        if OperationCount != 0 {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 requires exactly one instruction.")
        }
        if opCodeValue != ColumnarCodePlanContract.LdcI4_0()
            && opCodeValue != ColumnarCodePlanContract.LdcI4_1() {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 received an unknown opcode value.")
        }

        OperationKinds[0] = ColumnarCodePlanContract.EmitInstructionOperation()
        OpCodeValues[0] = opCodeValue
        OperandKinds[0] = ColumnarCodePlanContract.NoOperand()
        OperandIndices[0] = -1
        OperationOwnerFragmentIndices[0] = -1
        OperationCount = 1
    }

    public func CompleteBoolean() {
        EnsureV1Building()
        if !IsV1Structure(false, typeof(bool)) {
            throw new InvalidOperationException(
                "Columnar boolean code-plan schema v1 cannot seal an invalid instruction row.")
        }
        ResultType = typeof(bool)
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    public func PrepareV2() {
        Reset()
        SchemaVersion = ColumnarCodePlanContract.RecursiveSchemaVersion()
        Lifecycle = ColumnarCodePlanLifecycle.Building
        EnsureOperationCapacity(4)
        EnsureFragmentCapacity(4)
        EnsureOpenFragmentCapacity(4)
        EnsureBranchCapacity(4)
    }

    public func PrepareV3() {
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
    }

    public func AddType(value: Type): int {
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

    public func AddInt32(value: int): int {
        EnsureV2Building()
        EnsureInt32Capacity(Int32Count + 1)
        index := Int32Count
        Int32Values[index] = value
        Int32Count = Int32Count + 1
        return index
    }

    public func AddInt64(value: long): int {
        EnsureV3Building()
        EnsureInt64Capacity(Int64Count + 1)
        index := Int64Count
        Int64Values[index] = value
        Int64Count = Int64Count + 1
        return index
    }

    public func AddSingle(value: float): int {
        EnsureV3Building()
        EnsureSingleCapacity(SingleCount + 1)
        index := SingleCount
        SingleValues[index] = value
        SingleCount = SingleCount + 1
        return index
    }

    public func AddDouble(value: double): int {
        EnsureV3Building()
        EnsureDoubleCapacity(DoubleCount + 1)
        index := DoubleCount
        DoubleValues[index] = value
        DoubleCount = DoubleCount + 1
        return index
    }

    public func AddString(value: string): int {
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

    public func AddArgument(ordinal: int, typeIndex: int): int {
        return AddArgument(ordinal, typeIndex, false)
    }

    public func AddArgument(ordinal: int, typeIndex: int, isAddress: bool): int {
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

    public func AddAmbientLocal(value: LocalBuilder): int {
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

    public func AddMethod(value: MethodInfo): int {
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
    public func AddMethodWithSignature(
        value: MethodInfo,
        declaringType: Type,
        parameterTypes: Type[],
        returnType: Type,
        isStatic: bool,
        isAbstract: bool): int {
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

    public func AddConstructor(value: ConstructorInfo): int {
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
    public func AddConstructorWithSignature(
        value: ConstructorInfo,
        declaringType: Type,
        parameterTypes: Type[]): int {
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

    public func AddField(value: FieldInfo): int {
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
    public func AddFieldWithSignature(
        value: FieldInfo,
        declaringType: Type,
        valueType: Type,
        isStatic: bool): int {
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

    public func DeclarePlanLocal(typeIndex: int): int {
        EnsureV2Building()
        if typeIndex < 0 || typeIndex >= TypeCount {
            throw new ArgumentOutOfRangeException("typeIndex")
        }
        EnsurePlanLocalCapacity(PlanLocalCount + 1)
        index := PlanLocalCount
        PlanLocalTypeIndices[index] = typeIndex
        PlanLocalCount = PlanLocalCount + 1
        return index
    }

    public func DefineLabel(): int {
        EnsureV2Building()
        index := LabelCount
        LabelCount = LabelCount + 1
        return index
    }

    public func BeginFragment(parentIndex: int, fragmentKind: int, sourceNodeIndex: int): int {
        EnsureV2Building()
        if fragmentKind < 0 || sourceNodeIndex < 0 {
            throw new ArgumentOutOfRangeException("fragmentKind")
        }
        if FragmentCount == 0 {
            if parentIndex != -1 {
                throw new InvalidOperationException("The root code-plan fragment must have no parent.")
            }
        } else if OpenFragmentCount == 0
            || parentIndex != OpenFragmentIndices[OpenFragmentCount - 1] {
            throw new InvalidOperationException(
                "A recursive code-plan fragment must be nested under the current open fragment.")
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

    public func CompleteFragment(fragmentIndex: int, resultType: Type) {
        EnsureV2Building()
        if resultType == null {
            throw new ArgumentNullException("resultType")
        }
        if resultType == ColumnarCodePlanContract.UnsealedFragmentResultType() {
            throw new InvalidOperationException("Expression fragments cannot use the unsealed result sentinel.")
        }
        if OpenFragmentCount == 0
            || fragmentIndex != OpenFragmentIndices[OpenFragmentCount - 1]
            || fragmentIndex < 0
            || fragmentIndex >= FragmentCount {
            throw new InvalidOperationException("Code-plan fragments must complete in nesting order.")
        }
        if resultType.FullName == "System.Void" {
            if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
                || fragmentIndex != 0 {
                throw new InvalidOperationException(
                    "Only a schema-v3 root code-plan fragment can declare a void result.")
            }
        }

        FragmentOperationCounts[fragmentIndex] =
            OperationCount - FragmentOperationStarts[fragmentIndex]
        FragmentResultTypes[fragmentIndex] = resultType
        FragmentCompleted[fragmentIndex] = true
        OpenFragmentCount = OpenFragmentCount - 1
    }

    public func AppendInstructionWithoutOperand(opCodeValue: short) {
        EnsureV2Building()
        if !ColumnarCodePlanContract.IsNoOperandOpcode(opCodeValue)
            && (SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
                || !ColumnarCodePlanContract.IsScalarNoOperandOpcode(opCodeValue)) {
            throw new InvalidOperationException("The opcode does not use an operand-free row.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.NoOperand(),
            -1)
    }

    public func AppendInt32Instruction(opCodeValue: short, int32Index: int) {
        EnsureV2Building()
        if opCodeValue != ColumnarCodePlanContract.LdcI4()
            || int32Index < 0
            || int32Index >= Int32Count {
            throw new InvalidOperationException("The opcode does not use this Int32 pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.Int32Operand(),
            int32Index)
    }

    public func AppendInt64Instruction(opCodeValue: short, int64Index: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.LdcI8()
            || int64Index < 0
            || int64Index >= Int64Count {
            throw new InvalidOperationException("The opcode does not use this Int64 pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.Int64Operand(),
            int64Index)
    }

    public func AppendSingleInstruction(opCodeValue: short, singleIndex: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.LdcR4()
            || singleIndex < 0
            || singleIndex >= SingleCount {
            throw new InvalidOperationException("The opcode does not use this Single pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.SingleOperand(),
            singleIndex)
    }

    public func AppendDoubleInstruction(opCodeValue: short, doubleIndex: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.LdcR8()
            || doubleIndex < 0
            || doubleIndex >= DoubleCount {
            throw new InvalidOperationException("The opcode does not use this Double pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.DoubleOperand(),
            doubleIndex)
    }

    public func AppendStringInstruction(opCodeValue: short, stringIndex: int) {
        EnsureV3Building()
        if opCodeValue != ColumnarCodePlanContract.Ldstr()
            || stringIndex < 0
            || stringIndex >= StringCount {
            throw new InvalidOperationException("The opcode does not use this String pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.StringOperand(),
            stringIndex)
    }

    public func AppendTypeInstruction(opCodeValue: short, typeIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Ldelem()
                && (SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
                    || (opCodeValue != ColumnarCodePlanContract.Ldtoken()
                        && opCodeValue != ColumnarCodePlanContract.Box()
                        && opCodeValue != ColumnarCodePlanContract.Initobj())))
            || typeIndex < 0
            || typeIndex >= TypeCount {
            throw new InvalidOperationException("The opcode does not use this type pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.TypeOperand(),
            typeIndex)
    }

    public func AppendArgumentInstruction(opCodeValue: short, argumentIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Ldarg()
                && opCodeValue != ColumnarCodePlanContract.Ldarga())
            || argumentIndex < 0
            || argumentIndex >= ArgumentCount
            || (opCodeValue == ColumnarCodePlanContract.Ldarga()
                && ArgumentIsAddress[argumentIndex]) {
            throw new InvalidOperationException("The opcode does not use this argument pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.ArgumentOperand(),
            argumentIndex)
    }

    public func AppendAmbientLocalInstruction(opCodeValue: short, ambientLocalIndex: int) {
        EnsureV2Building()
        if !ColumnarCodePlanContract.IsLocalOpcode(opCodeValue)
            || ambientLocalIndex < 0
            || ambientLocalIndex >= AmbientLocalCount {
            throw new InvalidOperationException("The opcode does not use this ambient-local pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.AmbientLocalOperand(),
            ambientLocalIndex)
    }

    public func AppendMethodInstruction(opCodeValue: short, methodIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Call()
                && opCodeValue != ColumnarCodePlanContract.Callvirt())
            || methodIndex < 0
            || methodIndex >= MethodCount {
            throw new InvalidOperationException("The opcode does not use this method pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.MethodOperand(),
            methodIndex)
    }

    public func AppendConstructorInstruction(opCodeValue: short, constructorIndex: int) {
        EnsureV2Building()
        if opCodeValue != ColumnarCodePlanContract.Newobj()
            || constructorIndex < 0
            || constructorIndex >= ConstructorCount {
            throw new InvalidOperationException("The opcode does not use this constructor pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.ConstructorOperand(),
            constructorIndex)
    }

    public func AppendFieldInstruction(opCodeValue: short, fieldIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Ldfld()
                && (SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
                    || (opCodeValue != ColumnarCodePlanContract.Ldflda()
                        && opCodeValue != ColumnarCodePlanContract.Ldsfld())))
            || fieldIndex < 0
            || fieldIndex >= FieldCount {
            throw new InvalidOperationException("The opcode does not use this field pool entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.FieldOperand(),
            fieldIndex)
    }

    public func AppendPlanLocalInstruction(opCodeValue: short, planLocalIndex: int) {
        EnsureV2Building()
        if !ColumnarCodePlanContract.IsLocalOpcode(opCodeValue)
            || planLocalIndex < 0
            || planLocalIndex >= PlanLocalCount {
            throw new InvalidOperationException("The opcode does not use this plan-local entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.PlanLocalOperand(),
            planLocalIndex)
    }

    public func AppendLabelInstruction(opCodeValue: short, labelIndex: int) {
        EnsureV2Building()
        if (opCodeValue != ColumnarCodePlanContract.Br()
                && opCodeValue != ColumnarCodePlanContract.Brfalse())
            || labelIndex < 0
            || labelIndex >= LabelCount {
            throw new InvalidOperationException("The opcode does not use this label entry.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.EmitInstructionOperation(),
            opCodeValue,
            ColumnarCodePlanContract.LabelOperand(),
            labelIndex)
    }

    public func AppendMarkLabel(labelIndex: int) {
        EnsureV2Building()
        if labelIndex < 0 || labelIndex >= LabelCount {
            throw new InvalidOperationException("The mark-label row references an unknown label.")
        }
        AppendV2Row(
            ColumnarCodePlanContract.MarkLabelOperation(),
            ColumnarCodePlanContract.NoOpCode(),
            ColumnarCodePlanContract.LabelOperand(),
            labelIndex)
    }

    public func CreateCheckpoint(): ColumnarCodePlanCheckpoint {
        EnsureV2Building()
        checkpointBranchIndex := CreateBranch(CurrentBranchIndex)
        openFragments := new int[](OpenFragmentCount)
        i := 0
        while i < OpenFragmentCount {
            openFragments[i] = OpenFragmentIndices[i]
            i += 1
        }
        return new ColumnarCodePlanCheckpoint(
            Identity,
            Generation,
            SchemaVersion,
            checkpointBranchIndex,
            OperationCount,
            TypeCount,
            Int32Count,
            Int64Count,
            SingleCount,
            DoubleCount,
            StringCount,
            ArgumentCount,
            AmbientLocalCount,
            MethodCount,
            ConstructorCount,
            FieldCount,
            PlanLocalCount,
            LabelCount,
            FragmentCount,
            OpenFragmentCount,
            openFragments)
    }

    public func Rollback(checkpoint: ColumnarCodePlanCheckpoint) {
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
            if fragmentIndex < 0 || fragmentIndex >= checkpoint.FragmentCount
                || (i == 0 && FragmentParentIndices[fragmentIndex] != -1)
                || (i > 0
                    && FragmentParentIndices[fragmentIndex]
                        != checkpoint.OpenFragmentIndices[i - 1]) {
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
            FragmentResultTypes[fragmentIndex] =
                ColumnarCodePlanContract.UnsealedFragmentResultType()
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
        if checkpoint.AmbientLocalCount < 0
            || checkpoint.AmbientLocalCount > AmbientLocalCount {
            return false
        }
        if checkpoint.MethodCount < 0 || checkpoint.MethodCount > MethodCount {
            return false
        }
        if checkpoint.ConstructorCount < 0
            || checkpoint.ConstructorCount > ConstructorCount {
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
        return checkpoint.OpenFragmentCount >= 0
            && checkpoint.OpenFragmentCount <= checkpoint.FragmentCount
            && checkpoint.OpenFragmentIndices != null
            && checkpoint.OpenFragmentIndices.Length >= checkpoint.OpenFragmentCount
    }

    public func CompleteV2(resultType: Type) {
        EnsureV2Building()
        if resultType == null || !IsV2Structure(false, resultType) {
            throw new InvalidOperationException("Columnar code-plan schema v2 cannot seal an invalid payload.")
        }
        ResultType = resultType
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    public func ConsumeV2() {
        if SchemaVersion != ColumnarCodePlanContract.RecursiveSchemaVersion()
            || Status != ColumnarFragmentPlanStatus.Planned
            || Lifecycle != ColumnarCodePlanLifecycle.Sealed
            || ResultType == null
            || !IsV2Structure(true, ResultType) {
            throw new InvalidOperationException("Columnar code-plan schema v2 is not ready for one-shot execution.")
        }
        Lifecycle = ColumnarCodePlanLifecycle.Consumed
    }

    public func CompleteV3(resultType: Type) {
        EnsureV3Building()
        if resultType == null || !IsV3Structure(false, resultType) {
            throw new InvalidOperationException("Columnar code-plan schema v3 cannot seal an invalid payload.")
        }
        ResultType = resultType
        Status = ColumnarFragmentPlanStatus.Planned
        Lifecycle = ColumnarCodePlanLifecycle.Sealed
    }

    public func ConsumeV3() {
        if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || Status != ColumnarFragmentPlanStatus.Planned
            || Lifecycle != ColumnarCodePlanLifecycle.Sealed
            || ResultType == null
            || !IsV3Structure(true, ResultType) {
            throw new InvalidOperationException("Columnar code-plan schema v3 is not ready for one-shot execution.")
        }
        Lifecycle = ColumnarCodePlanLifecycle.Consumed
    }

    // This method is intentionally pure: it never repairs, grows, normalizes, or otherwise mutates
    // a payload. Executors can call it completely before the first Reflection.Emit operation.
    public func ValidateSealedStructure() {
        if SchemaVersion == ColumnarCodePlanContract.CurrentSchemaVersion() {
            if !IsV1Structure(true, typeof(bool)) {
                throw new InvalidOperationException("Columnar code-plan schema v1 payload is invalid.")
            }
            return
        }
        if SchemaVersion == ColumnarCodePlanContract.RecursiveSchemaVersion()
            && ResultType != null
            && IsV2Structure(true, ResultType) {
            return
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
            && ResultType != null
            && IsV3Structure(true, ResultType) {
            return
        }
        throw new InvalidOperationException("Columnar code-plan payload has an unknown or invalid schema.")
    }

    public func Reset() {
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

    func AppendV2Row(
        operationKind: int,
        opCodeValue: short,
        operandKind: int,
        operandIndex: int) {
        if OpenFragmentCount == 0 {
            throw new InvalidOperationException("Schema-v2 operations must belong to an open fragment.")
        }
        EnsureOperationCapacity(OperationCount + 1)
        OperationKinds[OperationCount] = operationKind
        OpCodeValues[OperationCount] = opCodeValue
        OperandKinds[OperationCount] = operandKind
        OperandIndices[OperationCount] = operandIndex
        OperationOwnerFragmentIndices[OperationCount] =
            OpenFragmentIndices[OpenFragmentCount - 1]
        OperationCount = OperationCount + 1
    }

    func EnsureV1Building() {
        if SchemaVersion != ColumnarCodePlanContract.CurrentSchemaVersion()
            || Status != ColumnarFragmentPlanStatus.NotOwned
            || Lifecycle == ColumnarCodePlanLifecycle.Sealed {
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
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion() {
            EnsureV3Building()
            return
        }
        if SchemaVersion != ColumnarCodePlanContract.RecursiveSchemaVersion()
            || Status != ColumnarFragmentPlanStatus.NotOwned
            || Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Columnar code-plan schema v2 is not open for mutation.")
        }
    }

    func EnsureV3Building() {
        if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || Status != ColumnarFragmentPlanStatus.NotOwned
            || Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Columnar code-plan schema v3 is not open for mutation.")
        }
    }

    func HasNoV2State(): bool {
        return TypeCount == 0
            && Int32Count == 0
            && HasNoV3State()
            && HasValidV3Pools()
            && ArgumentCount == 0
            && AmbientLocalCount == 0
            && MethodCount == 0
            && ConstructorCount == 0
            && FieldCount == 0
            && PlanLocalCount == 0
            && LabelCount == 0
            && FragmentCount == 0
            && OpenFragmentCount == 0
    }

    func HasNoV3State(): bool {
        return Int64Count == 0
            && SingleCount == 0
            && DoubleCount == 0
            && StringCount == 0
    }

    func IsV1Structure(sealedPayload: bool, expectedResultType: Type): bool {
        if SchemaVersion != ColumnarCodePlanContract.CurrentSchemaVersion()
            || OperationCount != 1
            || OperationKinds == null
            || OpCodeValues == null
            || OperandKinds == null
            || OperandIndices == null
            || OperationOwnerFragmentIndices == null
            || OperationKinds.Length < 1
            || OpCodeValues.Length < 1
            || OperandKinds.Length < 1
            || OperandIndices.Length < 1
            || OperationOwnerFragmentIndices.Length < 1
            || OperandIndices[0] != -1
            || OperationOwnerFragmentIndices[0] != -1
            || !HasNoV2State()
            || !ColumnarCodePlanContract.IsBooleanInstructionRow(
                OperationKinds[0],
                OpCodeValues[0],
                OperandKinds[0]) {
            return false
        }
        if sealedPayload {
            return Status == ColumnarFragmentPlanStatus.Planned
                && Lifecycle == ColumnarCodePlanLifecycle.Sealed
                && ResultType == expectedResultType
        }
        return Status == ColumnarFragmentPlanStatus.NotOwned
            && Lifecycle == ColumnarCodePlanLifecycle.Building
            && ResultType == null
    }

    func IsV2Structure(sealedPayload: bool, expectedResultType: Type): bool {
        if SchemaVersion != ColumnarCodePlanContract.RecursiveSchemaVersion()
            || expectedResultType == null
            || !HasNoV3State()
            || !HasValidV3Pools()
            || !HasValidV2ColumnsAndPools()
            || !HasValidV2Fragments(expectedResultType, false)
            || !HasValidV2Rows() {
            return false
        }
        if sealedPayload {
            return Status == ColumnarFragmentPlanStatus.Planned
                && Lifecycle == ColumnarCodePlanLifecycle.Sealed
                && ResultType == expectedResultType
                && OpenFragmentCount == 0
        }
        return Status == ColumnarFragmentPlanStatus.NotOwned
            && Lifecycle == ColumnarCodePlanLifecycle.Building
            && ResultType == null
            && OpenFragmentCount == 0
    }

    func IsV3Structure(sealedPayload: bool, expectedResultType: Type): bool {
        if SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || expectedResultType == null
            || !HasValidV3Pools()
            || !HasValidV2ColumnsAndPools()
            || !HasValidV2Fragments(expectedResultType, true)
            || !HasValidV2Rows() {
            return false
        }
        if sealedPayload {
            return Status == ColumnarFragmentPlanStatus.Planned
                && Lifecycle == ColumnarCodePlanLifecycle.Sealed
                && ResultType == expectedResultType
                && OpenFragmentCount == 0
        }
        return Status == ColumnarFragmentPlanStatus.NotOwned
            && Lifecycle == ColumnarCodePlanLifecycle.Building
            && ResultType == null
            && OpenFragmentCount == 0
    }

    func HasValidV3Pools(): bool {
        if Int64Count < 0
            || SingleCount < 0
            || DoubleCount < 0
            || StringCount < 0
            || Int64Values == null
            || Int64Values.Length < Int64Count
            || SingleValues == null
            || SingleValues.Length < SingleCount
            || DoubleValues == null
            || DoubleValues.Length < DoubleCount
            || StringValues == null
            || StringValues.Length < StringCount {
            return false
        }
        i := 0
        while i < StringCount {
            if StringValues[i] == null { return false }
            i += 1
        }
        return true
    }

    func HasValidV2ColumnsAndPools(): bool {
        if OperationCount <= 0
            || TypeCount < 0
            || Int32Count < 0
            || ArgumentCount < 0
            || AmbientLocalCount < 0
            || MethodCount < 0
            || ConstructorCount < 0
            || FieldCount < 0
            || PlanLocalCount < 0
            || LabelCount < 0
            || FragmentCount <= 0
            || OperationKinds == null
            || OpCodeValues == null
            || OperandKinds == null
            || OperandIndices == null
            || OperationOwnerFragmentIndices == null
            || OperationKinds.Length < OperationCount
            || OpCodeValues.Length < OperationCount
            || OperandKinds.Length < OperationCount
            || OperandIndices.Length < OperationCount
            || OperationOwnerFragmentIndices.Length < OperationCount
            || Types == null
            || Types.Length < TypeCount
            || Int32Values == null
            || Int32Values.Length < Int32Count
            || ArgumentOrdinals == null
            || ArgumentTypeIndices == null
            || ArgumentIsAddress == null
            || ArgumentOrdinals.Length < ArgumentCount
            || ArgumentTypeIndices.Length < ArgumentCount
            || ArgumentIsAddress.Length < ArgumentCount
            || AmbientLocals == null
            || AmbientLocals.Length < AmbientLocalCount
            || Methods == null
            || Methods.Length < MethodCount
            || MethodUsesDeclaredSignature == null
            || MethodUsesDeclaredSignature.Length < MethodCount
            || MethodDeclaringTypes == null
            || MethodDeclaringTypes.Length < MethodCount
            || MethodReturnTypes == null
            || MethodReturnTypes.Length < MethodCount
            || MethodParameterTypes == null
            || MethodParameterTypes.Length < MethodCount
            || MethodIsStatic == null
            || MethodIsStatic.Length < MethodCount
            || MethodIsAbstract == null
            || MethodIsAbstract.Length < MethodCount
            || Constructors == null
            || Constructors.Length < ConstructorCount
            || ConstructorUsesDeclaredSignature == null
            || ConstructorUsesDeclaredSignature.Length < ConstructorCount
            || ConstructorDeclaringTypes == null
            || ConstructorDeclaringTypes.Length < ConstructorCount
            || ConstructorParameterTypes == null
            || ConstructorParameterTypes.Length < ConstructorCount
            || Fields == null
            || Fields.Length < FieldCount
            || FieldUsesDeclaredSignature == null
            || FieldUsesDeclaredSignature.Length < FieldCount
            || FieldDeclaringTypes == null
            || FieldDeclaringTypes.Length < FieldCount
            || FieldValueTypes == null
            || FieldValueTypes.Length < FieldCount
            || FieldIsStatic == null
            || FieldIsStatic.Length < FieldCount
            || PlanLocalTypeIndices == null
            || PlanLocalTypeIndices.Length < PlanLocalCount {
            return false
        }

        i := 0
        while i < TypeCount {
            if Types[i] == null { return false }
            i += 1
        }
        i = 0
        while i < ArgumentCount {
            if ArgumentOrdinals[i] < 0
                || ArgumentOrdinals[i] > 32767
                || ArgumentTypeIndices[i] < 0
                || ArgumentTypeIndices[i] >= TypeCount {
                return false
            }
            i += 1
        }
        i = 0
        while i < AmbientLocalCount {
            if AmbientLocals[i] == null { return false }
            i += 1
        }
        i = 0
        while i < MethodCount {
            if Methods[i] == null { return false }
            if MethodUsesDeclaredSignature[i] {
                if MethodDeclaringTypes[i] == null
                    || MethodReturnTypes[i] == null
                    || MethodParameterTypes[i] == null {
                    return false
                }
                parameterIndex := 0
                while parameterIndex < MethodParameterTypes[i].Length {
                    if MethodParameterTypes[i][parameterIndex] == null { return false }
                    parameterIndex += 1
                }
            }
            i += 1
        }
        i = 0
        while i < ConstructorCount {
            if Constructors[i] == null { return false }
            if ConstructorUsesDeclaredSignature[i] {
                if ConstructorDeclaringTypes[i] == null
                    || ConstructorParameterTypes[i] == null {
                    return false
                }
                parameterIndex := 0
                while parameterIndex < ConstructorParameterTypes[i].Length {
                    if ConstructorParameterTypes[i][parameterIndex] == null { return false }
                    parameterIndex += 1
                }
            }
            i += 1
        }
        i = 0
        while i < FieldCount {
            if Fields[i] == null { return false }
            if FieldUsesDeclaredSignature[i]
                && (FieldDeclaringTypes[i] == null || FieldValueTypes[i] == null) {
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
        if FragmentOperationStarts == null
            || FragmentOperationCounts == null
            || FragmentParentIndices == null
            || FragmentKinds == null
            || FragmentSourceNodeIndices == null
            || FragmentResultTypes == null
            || FragmentCompleted == null
            || FragmentOperationStarts.Length < FragmentCount
            || FragmentOperationCounts.Length < FragmentCount
            || FragmentParentIndices.Length < FragmentCount
            || FragmentKinds.Length < FragmentCount
            || FragmentSourceNodeIndices.Length < FragmentCount
            || FragmentResultTypes.Length < FragmentCount
            || FragmentCompleted.Length < FragmentCount
            || FragmentParentIndices[0] != -1
            || FragmentOperationStarts[0] != 0
            || FragmentOperationCounts[0] != OperationCount
            || FragmentResultTypes[0] != expectedResultType
            || (expectedResultType.FullName == "System.Void" && !allowVoidRoot) {
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
            if !FragmentCompleted[i]
                || FragmentResultTypes[i] == null
                || FragmentResultTypes[i]
                    == ColumnarCodePlanContract.UnsealedFragmentResultType()
                || (FragmentResultTypes[i].FullName == "System.Void"
                    && (!allowVoidRoot || i != 0))
                || FragmentKinds[i] < 0
                || FragmentSourceNodeIndices[i] < 0
                || start < 0
                || count <= 0
                || end < start
                || end > OperationCount
                || start < previousStart {
                return false
            }

            keepPopping := true
            while activeCount > 0 && keepPopping {
                activeIndex := activeFragments[activeCount - 1]
                activeEnd := FragmentOperationStarts[activeIndex]
                    + FragmentOperationCounts[activeIndex]
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
                if start < parentStart
                    || end > parentEnd
                    || (start == parentStart && end == parentEnd) {
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
                activeEnd := FragmentOperationStarts[activeIndex]
                    + FragmentOperationCounts[activeIndex]
                if activeEnd <= i {
                    activeCount -= 1
                } else {
                    break
                }
            }
            while nextFragment < FragmentCount
                && FragmentOperationStarts[nextFragment] == i {
                activeFragments[activeCount] = nextFragment
                activeCount += 1
                nextFragment += 1
            }
            if activeCount == 0
                || ownerFragmentIndex != activeFragments[activeCount - 1] {
                return false
            }

            if operationKind == ColumnarCodePlanContract.MarkLabelOperation() {
                if opCodeValue != ColumnarCodePlanContract.NoOpCode()
                    || operandKind != ColumnarCodePlanContract.LabelOperand()
                    || operandIndex < 0
                    || operandIndex >= LabelCount {
                    return false
                }
            } else if operationKind != ColumnarCodePlanContract.EmitInstructionOperation()
                || !IsValidInstructionOperand(opCodeValue, operandKind, operandIndex) {
                return false
            }
            i += 1
        }
        return true
    }

    func IsValidInstructionOperand(opCodeValue: short, operandKind: int, operandIndex: int): bool {
        if ColumnarCodePlanContract.IsNoOperandOpcode(opCodeValue)
            || (SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
                && ColumnarCodePlanContract.IsScalarNoOperandOpcode(opCodeValue)) {
            return operandKind == ColumnarCodePlanContract.NoOperand() && operandIndex == -1
        }
        if opCodeValue == ColumnarCodePlanContract.LdcI4() {
            return operandKind == ColumnarCodePlanContract.Int32Operand()
                && operandIndex >= 0
                && operandIndex < Int32Count
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
            && opCodeValue == ColumnarCodePlanContract.LdcI8() {
            return operandKind == ColumnarCodePlanContract.Int64Operand()
                && operandIndex >= 0
                && operandIndex < Int64Count
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
            && opCodeValue == ColumnarCodePlanContract.LdcR4() {
            return operandKind == ColumnarCodePlanContract.SingleOperand()
                && operandIndex >= 0
                && operandIndex < SingleCount
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
            && opCodeValue == ColumnarCodePlanContract.LdcR8() {
            return operandKind == ColumnarCodePlanContract.DoubleOperand()
                && operandIndex >= 0
                && operandIndex < DoubleCount
        }
        if SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
            && opCodeValue == ColumnarCodePlanContract.Ldstr() {
            return operandKind == ColumnarCodePlanContract.StringOperand()
                && operandIndex >= 0
                && operandIndex < StringCount
        }
        if opCodeValue == ColumnarCodePlanContract.Ldarg()
            || opCodeValue == ColumnarCodePlanContract.Ldarga() {
            return operandKind == ColumnarCodePlanContract.ArgumentOperand()
                && operandIndex >= 0
                && operandIndex < ArgumentCount
                && (opCodeValue != ColumnarCodePlanContract.Ldarga()
                    || !ArgumentIsAddress[operandIndex])
        }
        if ColumnarCodePlanContract.IsLocalOpcode(opCodeValue) {
            return (operandKind == ColumnarCodePlanContract.AmbientLocalOperand()
                    && operandIndex >= 0
                    && operandIndex < AmbientLocalCount)
                || (operandKind == ColumnarCodePlanContract.PlanLocalOperand()
                    && operandIndex >= 0
                    && operandIndex < PlanLocalCount)
        }
        if opCodeValue == ColumnarCodePlanContract.Call()
            || opCodeValue == ColumnarCodePlanContract.Callvirt() {
            return operandKind == ColumnarCodePlanContract.MethodOperand()
                && operandIndex >= 0
                && operandIndex < MethodCount
        }
        if opCodeValue == ColumnarCodePlanContract.Newobj() {
            return operandKind == ColumnarCodePlanContract.ConstructorOperand()
                && operandIndex >= 0
                && operandIndex < ConstructorCount
        }
        if opCodeValue == ColumnarCodePlanContract.Ldfld()
            || (SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
                && (opCodeValue == ColumnarCodePlanContract.Ldflda()
                    || opCodeValue == ColumnarCodePlanContract.Ldsfld())) {
            return operandKind == ColumnarCodePlanContract.FieldOperand()
                && operandIndex >= 0
                && operandIndex < FieldCount
        }
        if opCodeValue == ColumnarCodePlanContract.Br()
            || opCodeValue == ColumnarCodePlanContract.Brfalse() {
            return operandKind == ColumnarCodePlanContract.LabelOperand()
                && operandIndex >= 0
                && operandIndex < LabelCount
        }
        if opCodeValue == ColumnarCodePlanContract.Ldelem()
            || (SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
                && (opCodeValue == ColumnarCodePlanContract.Ldtoken()
                    || opCodeValue == ColumnarCodePlanContract.Box()
                    || opCodeValue == ColumnarCodePlanContract.Initobj())) {
            return operandKind == ColumnarCodePlanContract.TypeOperand()
                && operandIndex >= 0
                && operandIndex < TypeCount
        }
        return false
    }

    func EnsureOperationCapacity(minimum: int) {
        if OperationKinds == null || OperationKinds.Length < minimum
            || OpCodeValues == null || OpCodeValues.Length < minimum
            || OperandKinds == null || OperandKinds.Length < minimum
            || OperandIndices == null || OperandIndices.Length < minimum
            || OperationOwnerFragmentIndices == null
            || OperationOwnerFragmentIndices.Length < minimum {
            capacity := NextCapacity(OperationKinds == null ? 0 : OperationKinds.Length, minimum)
            OperationKinds = GrowIntArray(OperationKinds, capacity)
            OpCodeValues = GrowShortArray(OpCodeValues, capacity)
            OperandKinds = GrowIntArray(OperandKinds, capacity)
            oldLength := OperandIndices == null ? 0 : OperandIndices.Length
            OperandIndices = GrowIntArray(OperandIndices, capacity)
            ownerOldLength := OperationOwnerFragmentIndices == null
                ? 0
                : OperationOwnerFragmentIndices.Length
            OperationOwnerFragmentIndices = GrowIntArray(
                OperationOwnerFragmentIndices,
                capacity)
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
            Int32Values = GrowIntArray(
                Int32Values,
                NextCapacity(Int32Values == null ? 0 : Int32Values.Length, minimum))
        }
    }

    func EnsureInt64Capacity(minimum: int) {
        if Int64Values == null || Int64Values.Length < minimum {
            Int64Values = GrowLongArray(
                Int64Values,
                NextCapacity(Int64Values == null ? 0 : Int64Values.Length, minimum))
        }
    }

    func EnsureSingleCapacity(minimum: int) {
        if SingleValues == null || SingleValues.Length < minimum {
            SingleValues = GrowFloatArray(
                SingleValues,
                NextCapacity(SingleValues == null ? 0 : SingleValues.Length, minimum))
        }
    }

    func EnsureDoubleCapacity(minimum: int) {
        if DoubleValues == null || DoubleValues.Length < minimum {
            DoubleValues = GrowDoubleArray(
                DoubleValues,
                NextCapacity(DoubleValues == null ? 0 : DoubleValues.Length, minimum))
        }
    }

    func EnsureStringCapacity(minimum: int) {
        if StringValues == null || StringValues.Length < minimum {
            StringValues = GrowStringArray(
                StringValues,
                NextCapacity(StringValues == null ? 0 : StringValues.Length, minimum))
        }
    }

    func EnsureArgumentCapacity(minimum: int) {
        if ArgumentOrdinals == null || ArgumentOrdinals.Length < minimum
            || ArgumentTypeIndices == null || ArgumentTypeIndices.Length < minimum
            || ArgumentIsAddress == null || ArgumentIsAddress.Length < minimum {
            capacity := NextCapacity(
                ArgumentOrdinals == null ? 0 : ArgumentOrdinals.Length,
                minimum)
            ArgumentOrdinals = GrowIntArray(ArgumentOrdinals, capacity)
            ArgumentTypeIndices = GrowIntArray(ArgumentTypeIndices, capacity)
            ArgumentIsAddress = GrowBoolArray(ArgumentIsAddress, capacity)
        }
    }

    func EnsureAmbientLocalCapacity(minimum: int) {
        if AmbientLocals == null || AmbientLocals.Length < minimum {
            AmbientLocals = GrowLocalArray(
                AmbientLocals,
                NextCapacity(AmbientLocals == null ? 0 : AmbientLocals.Length, minimum))
        }
    }

    func EnsureMethodCapacity(minimum: int) {
        if Methods == null || Methods.Length < minimum
            || MethodUsesDeclaredSignature == null
            || MethodUsesDeclaredSignature.Length < minimum
            || MethodDeclaringTypes == null || MethodDeclaringTypes.Length < minimum
            || MethodReturnTypes == null || MethodReturnTypes.Length < minimum
            || MethodParameterTypes == null || MethodParameterTypes.Length < minimum
            || MethodIsStatic == null || MethodIsStatic.Length < minimum
            || MethodIsAbstract == null || MethodIsAbstract.Length < minimum {
            capacity := NextCapacity(Methods == null ? 0 : Methods.Length, minimum)
            Methods = GrowMethodArray(Methods, capacity)
            MethodUsesDeclaredSignature = GrowBoolArray(
                MethodUsesDeclaredSignature,
                capacity)
            MethodDeclaringTypes = GrowTypeArray(MethodDeclaringTypes, capacity)
            MethodReturnTypes = GrowTypeArray(MethodReturnTypes, capacity)
            MethodParameterTypes = GrowTypeArrayArray(MethodParameterTypes, capacity)
            MethodIsStatic = GrowBoolArray(MethodIsStatic, capacity)
            MethodIsAbstract = GrowBoolArray(MethodIsAbstract, capacity)
        }
    }

    func EnsureConstructorCapacity(minimum: int) {
        if Constructors == null || Constructors.Length < minimum
            || ConstructorUsesDeclaredSignature == null
            || ConstructorUsesDeclaredSignature.Length < minimum
            || ConstructorDeclaringTypes == null
            || ConstructorDeclaringTypes.Length < minimum
            || ConstructorParameterTypes == null
            || ConstructorParameterTypes.Length < minimum {
            capacity := NextCapacity(
                Constructors == null ? 0 : Constructors.Length,
                minimum)
            Constructors = GrowConstructorArray(Constructors, capacity)
            ConstructorUsesDeclaredSignature = GrowBoolArray(
                ConstructorUsesDeclaredSignature,
                capacity)
            ConstructorDeclaringTypes = GrowTypeArray(
                ConstructorDeclaringTypes,
                capacity)
            ConstructorParameterTypes = GrowTypeArrayArray(
                ConstructorParameterTypes,
                capacity)
        }
    }

    func EnsureFieldCapacity(minimum: int) {
        if Fields == null || Fields.Length < minimum
            || FieldUsesDeclaredSignature == null
            || FieldUsesDeclaredSignature.Length < minimum
            || FieldDeclaringTypes == null || FieldDeclaringTypes.Length < minimum
            || FieldValueTypes == null || FieldValueTypes.Length < minimum
            || FieldIsStatic == null || FieldIsStatic.Length < minimum {
            capacity := NextCapacity(Fields == null ? 0 : Fields.Length, minimum)
            Fields = GrowFieldArray(Fields, capacity)
            FieldUsesDeclaredSignature = GrowBoolArray(
                FieldUsesDeclaredSignature,
                capacity)
            FieldDeclaringTypes = GrowTypeArray(FieldDeclaringTypes, capacity)
            FieldValueTypes = GrowTypeArray(FieldValueTypes, capacity)
            FieldIsStatic = GrowBoolArray(FieldIsStatic, capacity)
        }
    }

    func EnsurePlanLocalCapacity(minimum: int) {
        if PlanLocalTypeIndices == null || PlanLocalTypeIndices.Length < minimum {
            PlanLocalTypeIndices = GrowIntArray(
                PlanLocalTypeIndices,
                NextCapacity(PlanLocalTypeIndices == null ? 0 : PlanLocalTypeIndices.Length, minimum))
        }
    }

    func EnsureFragmentCapacity(minimum: int) {
        if FragmentOperationStarts == null || FragmentOperationStarts.Length < minimum
            || FragmentOperationCounts == null || FragmentOperationCounts.Length < minimum
            || FragmentParentIndices == null || FragmentParentIndices.Length < minimum
            || FragmentKinds == null || FragmentKinds.Length < minimum
            || FragmentSourceNodeIndices == null || FragmentSourceNodeIndices.Length < minimum
            || FragmentResultTypes == null || FragmentResultTypes.Length < minimum
            || FragmentCompleted == null || FragmentCompleted.Length < minimum {
            capacity := NextCapacity(
                FragmentOperationStarts == null ? 0 : FragmentOperationStarts.Length,
                minimum)
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
            OpenFragmentIndices = GrowIntArray(
                OpenFragmentIndices,
                NextCapacity(OpenFragmentIndices == null ? 0 : OpenFragmentIndices.Length, minimum))
        }
    }

    func EnsureBranchCapacity(minimum: int) {
        if BranchParentIndices == null || BranchParentIndices.Length < minimum {
            oldLength := BranchParentIndices == null ? 0 : BranchParentIndices.Length
            BranchParentIndices = GrowIntArray(
                BranchParentIndices,
                NextCapacity(oldLength, minimum))
            i := oldLength
            while i < BranchParentIndices.Length {
                BranchParentIndices[i] = -1
                i += 1
            }
        }
    }

    static func NextCapacity(current: int, minimum: int): int {
        capacity := current
        if capacity < 4 { capacity = 4 }
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

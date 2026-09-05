namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler

// THE DECLARATION-ROW IR — THE SECOND HALF OF THE PLAN-ROW IR, WHICH DID NOT EXIST.
//
// `ColumnarCodePlan` describes METHOD BODIES and nothing else. The declaration host — the walk in
// `ColumnarIlEmitter.TryEmitColumnarAssembly` that defines the module, the types, their fields,
// methods, properties, generic parameters and attributes — read `ColumnarProgramInput` directly and
// called Reflection.Emit imperatively, computing the resolved names and the CLR attribute words
// inline as it went. So a SECOND executor over "the same plan rows" had, for every declaration,
// no rows to execute.
//
// This is that table. It grows one declaration family per slice (023/2 S2.1 (a)…(i)), starting with
// (a) — the assembly, the module and the enums. The rule the whole arc follows: anything the
// Reflection.Emit executor COMPUTES is planner work, because a second executor would otherwise have
// to compute it again and the two could disagree. For enums that is exactly two computations —
// the resolved exact type name, and the composed `TypeAttributes` word.
//
// ORDER IS PART OF THE DATA. The host's enum pass runs BEFORE the Program type and before any
// function signature, so a function may use an enum as a parameter, return or local type; that was a
// property of where the loop sat in a C# method. Here it is a property of the rows: the enum rows
// are the first rows, and they are complete before any later family is planned.
// ONE TABLE PER DECLARATION FAMILY. (a) put the assembly, the module and the enums on the plan
// directly; from (b) each family gets its own row table hanging off it, so the plan grows by adding a
// table rather than by growing one constructor to thirty parameters.
class ColumnarTypeDefRows {
    InterfaceCount: int
    InterfaceExactNames: string[]
    InterfaceTypeAttributes: int[]
    StructCount: int
    StructExactNames: string[]
    StructTypeAttributes: int[]
    StructEnclosingExactNames: string[]

    constructor(
        interfaceCount: int,
        interfaceExactNames: string[],
        interfaceTypeAttributes: int[],
        structCount: int,
        structExactNames: string[],
        structTypeAttributes: int[],
        structEnclosingExactNames: string[]
    ) {
        InterfaceCount = interfaceCount
        InterfaceExactNames = interfaceExactNames
        InterfaceTypeAttributes = interfaceTypeAttributes
        StructCount = structCount
        StructExactNames = structExactNames
        StructTypeAttributes = structTypeAttributes
        StructEnclosingExactNames = structEnclosingExactNames
    }
}

// The FIELD family, jagged by declaring struct. `FieldAttributes` (ECMA-335 II.23.1.5) as integers:
// Public 6, Static 16, InitOnly 32.
class ColumnarFieldRows {
    StructCount: int
    FieldNames: string[][]
    FieldAttributeWords: int[][]
    FieldIsStatic: bool[][]
    FieldIsNullable: bool[][]

    constructor(
        structCount: int,
        fieldNames: string[][],
        fieldAttributeWords: int[][],
        fieldIsStatic: bool[][],
        fieldIsNullable: bool[][]
    ) {
        StructCount = structCount
        FieldNames = fieldNames
        FieldAttributeWords = fieldAttributeWords
        FieldIsStatic = fieldIsStatic
        FieldIsNullable = fieldIsNullable
    }
}

// The METHOD family. `MethodAttributes` (ECMA-335 II.23.1.10) as integers: Public 6, Static 16,
// Final 32, Virtual 64, HideBySig 128, NewSlot 256, Abstract 1024, SpecialName 2048, PinvokeImpl 8192.
//
// ONLY THE BASE WORD IS PLANNED. An IMPLEMENTING method is widened to Virtual|Final|NewSlot by
// matching its signature against every interface the type implements, which needs the live registry
// and the resolved signature -- S2.2's work, not this slice's. The host ORs those bits onto the
// planned base, so the two halves stay separable and neither guesses at the other.
class ColumnarMethodRows {
    StructCount: int
    StructMethodAttributeWords: int[][]
    StructMethodIsVoidReturn: bool[][]
    InterfaceCount: int
    InterfaceMethodAttributeWords: int[][]
    FunctionCount: int
    FunctionAttributeWords: int[]
    FunctionIsVoidReturn: bool[]

    constructor(
        structCount: int,
        structMethodAttributeWords: int[][],
        structMethodIsVoidReturn: bool[][],
        interfaceCount: int,
        interfaceMethodAttributeWords: int[][],
        functionCount: int,
        functionAttributeWords: int[],
        functionIsVoidReturn: bool[]
    ) {
        StructCount = structCount
        StructMethodAttributeWords = structMethodAttributeWords
        StructMethodIsVoidReturn = structMethodIsVoidReturn
        InterfaceCount = interfaceCount
        InterfaceMethodAttributeWords = interfaceMethodAttributeWords
        FunctionCount = functionCount
        FunctionAttributeWords = functionAttributeWords
        FunctionIsVoidReturn = functionIsVoidReturn
    }
}

// The PROPERTY family, jagged by declaring struct. A property is not a member the CLR emits directly:
// it is a name plus a pair of ACCESSOR METHODS, so the row carries the accessor word, both accessor
// names and the setter's `value` ordinal.
class ColumnarPropertyRows {
    StructCount: int
    AccessorWords: int[][]
    GetterNames: string[][]
    SetterNames: string[][]
    HasSetter: bool[][]
    ValueOrdinals: int[][]

    constructor(
        structCount: int,
        accessorWords: int[][],
        getterNames: string[][],
        setterNames: string[][],
        hasSetter: bool[][],
        valueOrdinals: int[][]
    ) {
        StructCount = structCount
        AccessorWords = accessorWords
        GetterNames = getterNames
        SetterNames = setterNames
        HasSetter = hasSetter
        ValueOrdinals = valueOrdinals
    }
}

// CUSTOM ATTRIBUTES, IN ATTACHMENT ORDER. Each outer index identifies its source declaration;
// each inner sequence is the complete ordered attachment list for that owner. Empty means absent.
// The first two families bind their sole constructor to IsByRefLike() and IsReadOnly() respectively.
// Test slots bind 0 to Trait(string, string), 1 to Fact(); slot order is data, not executor policy.
// Source lists retain stable ordinals through emission. These rows capture attribute data, not the
// rest of each source declaration; executors treat the resulting arrays as read-only.
// Constructor resolution is still S2.2: missing IsByRefLike declines, missing IsReadOnly is skipped,
// and missing test constructors produce the existing emit.tests.framework decline before any test.
class ColumnarCustomAttributeRows {
    StructByRefLikeBlobs: byte[][][]
    UnionReadOnlyBlobs: byte[][][]
    TestConstructorSlots: int[]
    TestBlobs: byte[][][]

    constructor(structByRefLikeBlobs: byte[][][], unionReadOnlyBlobs: byte[][][], testConstructorSlots: int[], testBlobs: byte[][][]) {
        StructByRefLikeBlobs = structByRefLikeBlobs
        UnionReadOnlyBlobs = unionReadOnlyBlobs
        TestConstructorSlots = testConstructorSlots
        TestBlobs = testBlobs
    }
}

// P/INVOKE declarations retain source struct/method ordinals. A null slot is an ordinary method;
// selected records capture native metadata, including a deferred decline, but no runtime types.
// Signature resolution and shared parameter/default metadata still run at their existing phases.
class ColumnarPInvokeDeclaration {
    IsValid: bool
    DeclineCode: string
    DeclineMessage: string
    DeclineOwnerName: string
    MethodName: string
    LibraryName: string
    EntryPointName: string
    MethodAttributes: int
    ManagedCallingConvention: int
    UnmanagedCallingConvention: int
    CharacterSet: int
    ImplementationFlagsMask: int

    constructor(isValid: bool, declineCode: string, declineMessage: string, declineOwnerName: string, methodName: string, libraryName: string, entryPointName: string, methodAttributes: int, managedCallingConvention: int, unmanagedCallingConvention: int, characterSet: int, implementationFlagsMask: int) {
        IsValid = isValid
        DeclineCode = declineCode
        DeclineMessage = declineMessage
        DeclineOwnerName = declineOwnerName
        MethodName = methodName
        LibraryName = libraryName
        EntryPointName = entryPointName
        MethodAttributes = methodAttributes
        ManagedCallingConvention = managedCallingConvention
        UnmanagedCallingConvention = unmanagedCallingConvention
        CharacterSet = characterSet
        ImplementationFlagsMask = implementationFlagsMask
    }

    func MergeImplementationFlags(currentFlags: int): int {
        return currentFlags | ImplementationFlagsMask
    }
}

class ColumnarPInvokeRows {
    Methods: ColumnarPInvokeDeclaration[][]

    constructor(methods: ColumnarPInvokeDeclaration[][]) {
        Methods = methods
    }
}

class ColumnarDeclarationPlan {
    PInvokes: ColumnarPInvokeRows
    CustomAttributes: ColumnarCustomAttributeRows
    Properties: ColumnarPropertyRows
    Methods: ColumnarMethodRows
    Fields: ColumnarFieldRows
    TypeDefs: ColumnarTypeDefRows
    AssemblyName: string
    ModuleName: string
    EnumCount: int
    EnumExactNames: string[]
    EnumIsStringBacked: bool[]
    EnumTypeAttributes: int[]
    EnumMemberNames: string[][]
    EnumMemberValues: int[][]
    EnumMemberStringValues: string[][]

    constructor(
        pInvokes: ColumnarPInvokeRows,
        customAttributes: ColumnarCustomAttributeRows,
        properties: ColumnarPropertyRows,
        methods: ColumnarMethodRows,
        fields: ColumnarFieldRows,
        typeDefs: ColumnarTypeDefRows,
        assemblyName: string,
        moduleName: string,
        enumCount: int,
        enumExactNames: string[],
        enumIsStringBacked: bool[],
        enumTypeAttributes: int[],
        enumMemberNames: string[][],
        enumMemberValues: int[][],
        enumMemberStringValues: string[][]
    ) {
        PInvokes = pInvokes
        CustomAttributes = customAttributes
        Properties = properties
        Methods = methods
        Fields = fields
        TypeDefs = typeDefs
        AssemblyName = assemblyName
        ModuleName = moduleName
        EnumCount = enumCount
        EnumExactNames = enumExactNames
        EnumIsStringBacked = enumIsStringBacked
        EnumTypeAttributes = enumTypeAttributes
        EnumMemberNames = enumMemberNames
        EnumMemberValues = enumMemberValues
        EnumMemberStringValues = enumMemberStringValues
    }
}

class ColumnarDeclarationPlanner {
    static func IsValidPInvoke(method: ColumnarFunctionInput): bool {
        return ColumnarFunctionInput.HasNativeImportModifier(method.ModifierFlags) && !string.IsNullOrEmpty(method.NativeImportLibraryName) && !string.IsNullOrEmpty(method.NativeImportEntryPoint) && method.TypeParamNames.Length == 0 && !method.IsAsync
    }

    static func BuildPInvokes(program: ColumnarProgramInput, methodRows: ColumnarMethodRows): ColumnarPInvokeRows {
        structs := program.Structs
        rows := new ColumnarPInvokeDeclaration[][](structs.Count)
        index := 0
        while index < structs.Count {
            owner := structs[index]
            methods := owner.Methods
            declarations := new ColumnarPInvokeDeclaration[](methods.Count)
            member := 0
            while member < methods.Count {
                method := methods[member]
                // The native branch exists only in the static-method walk. Do not admit a bodyless
                // instance method here or impose a new restriction on generic declaring types.
                if method.IsStatic && method.IsBodylessNativeImport {
                    valid := IsValidPInvoke(method)
                    declineCode := ""
                    declineMessage := ""
                    if !valid {
                        declineCode = "emit.declaration.native-import"
                        declineMessage = "native import metadata was invalid for '" + owner.Name + "." + method.Name + "'"
                    }
                    // MethodAttributes.PinvokeImpl=8192; CallingConventions.Standard=1;
                    // CallingConvention.Cdecl=2; CharSet.Ansi=2; MethodImplAttributes.PreserveSig=128.
                    declarations[member] = new ColumnarPInvokeDeclaration(
                        valid,
                        declineCode,
                        declineMessage,
                        owner.Name,
                        method.Name,
                        method.NativeImportLibraryName,
                        method.NativeImportEntryPoint,
                        methodRows.StructMethodAttributeWords[index][member] | 8192,
                        1,
                        2,
                        2,
                        128
                    )
                }
                member = member + 1
            }
            rows[index] = declarations
            index = index + 1
        }
        return new ColumnarPInvokeRows(rows)
    }

    static func BuildCustomAttributes(program: ColumnarProgramInput): ColumnarCustomAttributeRows {
        empty := new byte[][](0)
        noArgument: byte[] = null
        marker: byte[][] = null
        structs := program.Structs
        structBlobs := new byte[][][](structs.Count)
        index := 0
        while index < structs.Count {
            structBlobs[index] = empty
            if structs[index].IsRefStruct {
                if marker == null {
                    noArgument = ColumnarAttributeBlobs.NoArgument()
                    marker = new byte[][](1)
                    marker[0] = noArgument
                }
                structBlobs[index] = marker
            }
            index = index + 1
        }

        unions := program.Unions
        unionBlobs := new byte[][][](unions.Count)
        index = 0
        while index < unions.Count {
            unionBlobs[index] = empty
            if unions[index].IsValueStruct {
                if marker == null {
                    noArgument = ColumnarAttributeBlobs.NoArgument()
                    marker = new byte[][](1)
                    marker[0] = noArgument
                }
                unionBlobs[index] = marker
            }
            index = index + 1
        }

        tests := program.Tests
        testCount := 0
        if tests != null {
            testCount = tests.Count
        }
        slots := new int[](0)
        testBlobs := new byte[][][](testCount)
        if tests != null && testCount > 0 {
            slots = new int[](2)
            slots[0] = 0
            slots[1] = 1
            if noArgument == null {
                noArgument = ColumnarAttributeBlobs.NoArgument()
            }
            index = 0
            while index < testCount {
                blobs := new byte[][](2)
                blobs[0] = ColumnarAttributeBlobs.TwoStrings(ColumnarAttributeBlobs.DescriptionTraitKey(), tests[index].Description)
                blobs[1] = noArgument
                testBlobs[index] = blobs
                index = index + 1
            }
        }
        return new ColumnarCustomAttributeRows(structBlobs, unionBlobs, slots, testBlobs)
    }

    // `TypeAttributes` (ECMA-335 II.23.1.15) as integers, for the same reason
    // `ColumnarGenericConstraintPlanner` writes `GenericParameterAttributes` as integers: the bits are
    // CLR-side and the host casts once at the `Define*` call. Public 0x1, Class 0x0, Abstract 0x80,
    // Sealed 0x100.
    static func PublicTypeAttribute(): int {
        return 1
    }

    static func AbstractTypeAttribute(): int {
        return 128
    }

    static func SealedTypeAttribute(): int {
        return 256
    }

    static func InterfaceTypeAttribute(): int {
        return 32
    }

    // An interface is Public|Interface|Abstract; a top-level record is Class|Public (Class is zero);
    // a top-level struct is Sealed|Public.
    static func InterfaceTypeAttributes(): int {
        return PublicTypeAttribute() | InterfaceTypeAttribute() | AbstractTypeAttribute()
    }

    // THE NESTED ASYMMETRY IS LOAD-BEARING AND IS REPRODUCED EXACTLY. A TOP-LEVEL type ORs `Public`;
    // a NESTED one ORs its own `NestedVisibilityAttributes` word INSTEAD -- never both. Folding the
    // two would flip the visibility of every nested type in the estate.
    static func StructTypeAttributesFor(isReference: bool, isNested: bool, nestedVisibilityAttributes: int): int {
        bits := 0
        if !isReference {
            bits = SealedTypeAttribute()
        }

        if isNested {
            return bits | nestedVisibilityAttributes
        }
        return bits | PublicTypeAttribute()
    }

    // A STRING-BACKED enum is not a CLR enum at all — it is an `abstract sealed` class of literal
    // string fields, because the CLR has no string-underlying enum. An INT-backed one goes through
    // `DefineEnum`, which composes the rest of the word itself and is handed only the visibility.
    static func StringBackedEnumTypeAttributes(): int {
        return PublicTypeAttribute() | AbstractTypeAttribute() | SealedTypeAttribute()
    }

    static func IntBackedEnumTypeAttributes(): int {
        return PublicTypeAttribute()
    }

    // A string-backed member whose value was not spelled takes its own NAME as the value. The rule
    // lived in a ternary inside the emit loop and is a planner rule: it decides a stored constant.
    static func EnumMemberStringValueAt(input: ColumnarEnumInput, index: int): string {
        if index < input.MemberStringValues.Length {
            return input.MemberStringValues[index]
        }
        return input.MemberNames[index]
    }

    // A STATIC accessor: Public|Static|HideBySig|SpecialName = 2198. An INSTANCE accessor drops
    // Static: 2182. `SpecialName` is what marks the method as an accessor rather than an ordinary
    // method called `get_X`.
    //
    // 2198 is also what `StaticMethodAttributes(isOperator: true)` produces, because a static
    // operator carries the same four flags. That is an AGREEMENT OF FLAGS, NOT A SHARED RULE -- an
    // operator is SpecialName because its name begins `op_`, an accessor because it is an accessor --
    // so the two are computed separately and must not be unified.
    static func StaticAccessorAttributes(): int {
        return PublicFieldAttribute() | StaticMethodAttribute() | HideBySigMethodAttribute() | SpecialNameMethodAttribute()
    }

    static func InstanceAccessorAttributes(): int {
        return PublicFieldAttribute() | HideBySigMethodAttribute() | SpecialNameMethodAttribute()
    }

    // The CLR spells a property's accessors `get_<Name>` and `set_<Name>`. Four call sites built
    // these by concatenation; the names are metadata, so they are planned.
    static func PropertyGetterName(propertyName: string): string {
        return "get_" + propertyName
    }

    static func PropertySetterName(propertyName: string): string {
        return "set_" + propertyName
    }

    // A setter's `value` IS its parameter zero, so its ordinal is the ordinary parameter rule -- 0 on
    // a static accessor, 1 on an instance one, because `this` takes argument zero there. The rule is
    // REUSED from the method family rather than restated, so the two can never drift apart.
    static func PropertyValueOrdinal(isStatic: bool): int {
        return ParameterOrdinalFor(0, !isStatic)
    }

    static func BuildProperties(program: ColumnarProgramInput): ColumnarPropertyRows {
        structs := program.Structs
        count := structs.Count
        words := new int[][](count)
        getters := new string[][](count)
        setters := new string[][](count)
        hasSetters := new bool[][](count)
        ordinals := new int[][](count)

        index := 0
        while index < count {
            properties := structs[index].Properties
            propertyCount := properties.Count
            propertyWords := new int[](propertyCount)
            propertyGetters := new string[](propertyCount)
            propertySetters := new string[](propertyCount)
            propertyHasSetters := new bool[](propertyCount)
            propertyOrdinals := new int[](propertyCount)
            member := 0
            while member < propertyCount {
                property := properties[member]
                if property.IsStatic {
                    propertyWords[member] = StaticAccessorAttributes()
                } else {
                    propertyWords[member] = InstanceAccessorAttributes()
                }
                propertyGetters[member] = PropertyGetterName(property.Name)
                propertySetters[member] = PropertySetterName(property.Name)
                propertyHasSetters[member] = property.Setter != null
                propertyOrdinals[member] = PropertyValueOrdinal(property.IsStatic)
                member = member + 1
            }
            words[index] = propertyWords
            getters[index] = propertyGetters
            setters[index] = propertySetters
            hasSetters[index] = propertyHasSetters
            ordinals[index] = propertyOrdinals
            index = index + 1
        }

        return new ColumnarPropertyRows(count, words, getters, setters, hasSetters, ordinals)
    }

    static func StaticMethodAttribute(): int {
        return 16
    }

    static func VirtualMethodAttribute(): int {
        return 64
    }

    static func HideBySigMethodAttribute(): int {
        return 128
    }

    static func NewSlotMethodAttribute(): int {
        return 256
    }

    static func AbstractMethodAttribute(): int {
        return 1024
    }

    static func SpecialNameMethodAttribute(): int {
        return 2048
    }

    // `Public` is 6 for a method exactly as it is for a field -- one accessibility encoding, two
    // member kinds -- so the field constant is reused rather than duplicated under a second name.
    // A STATIC method: Public|Static|HideBySig = 150.
    //
    // THE OPERATOR TEST IS A NAME-PREFIX RULE THAT DECIDES METADATA. A method whose name begins
    // `op_` is marked SpecialName (2198), which is what makes the CLR and every consumer treat it as
    // an operator rather than an ordinary static method. Nothing else in the declaration says so.
    static func StaticMethodAttributes(isOperatorName: bool): int {
        bits := PublicFieldAttribute() | StaticMethodAttribute() | HideBySigMethodAttribute()
        if isOperatorName {
            return bits | SpecialNameMethodAttribute()
        }
        return bits
    }

    static func IsOperatorMethodName(name: string): bool {
        return name != null && name.StartsWith("op_", StringComparison.Ordinal)
    }

    // An INSTANCE method: Public|HideBySig = 134, before any implementing-interface widening.
    static func InstanceMethodAttributes(): int {
        return PublicFieldAttribute() | HideBySigMethodAttribute()
    }

    // An INTERFACE member: Public|Virtual|HideBySig|NewSlot = 454, plus Abstract (1478) unless the
    // interface supplies a default body.
    static func InterfaceMethodAttributes(hasDefaultBody: bool): int {
        bits := PublicFieldAttribute() | VirtualMethodAttribute() | HideBySigMethodAttribute() | NewSlotMethodAttribute()
        if hasDefaultBody {
            return bits
        }
        return bits | AbstractMethodAttribute()
    }

    // A FREE FUNCTION is Public|Static = 22 and carries NO HideBySig -- free functions do not
    // overload, so there is no signature to hide by. The difference from a static METHOD (150) is
    // deliberate and is pinned.
    static func FreeFunctionAttributes(): int {
        return PublicFieldAttribute() | StaticMethodAttribute()
    }

    // `this` occupies argument 0 of an instance method, so user parameter ordinals shift by one; a
    // static method's do not. One rule, two call sites, and getting it backwards would misread every
    // argument in every body.
    static func ParameterOrdinalShift(isInstance: bool): int {
        if isInstance {
            return 1
        }
        return 0
    }

    static func ParameterOrdinalFor(index: int, isInstance: bool): int {
        return index + ParameterOrdinalShift(isInstance)
    }

    // The only return canonical with no type to resolve.
    static func IsVoidReturnCanonical(returnCanonical: string): bool {
        return returnCanonical == "void"
    }

    static func BuildMethods(program: ColumnarProgramInput): ColumnarMethodRows {
        structs := program.Structs
        structCount := structs.Count
        structWords := new int[][](structCount)
        structVoids := new bool[][](structCount)
        index := 0
        while index < structCount {
            methods := structs[index].Methods
            methodCount := methods.Count
            words := new int[](methodCount)
            voids := new bool[](methodCount)
            member := 0
            while member < methodCount {
                method := methods[member]
                if method.IsStatic {
                    words[member] = StaticMethodAttributes(IsOperatorMethodName(method.Name))
                } else {
                    words[member] = InstanceMethodAttributes()
                }
                voids[member] = IsVoidReturnCanonical(method.ReturnCanonical)
                member = member + 1
            }
            structWords[index] = words
            structVoids[index] = voids
            index = index + 1
        }

        interfaces := program.Interfaces
        interfaceCount := interfaces.Count
        interfaceWords := new int[][](interfaceCount)
        index = 0
        while index < interfaceCount {
            iface := interfaces[index]
            memberCount := iface.MethodNames.Length
            words := new int[](memberCount)
            member := 0
            while member < memberCount {
                words[member] = InterfaceMethodAttributes(iface.MethodBodies[member] != null)
                member = member + 1
            }
            interfaceWords[index] = words
            index = index + 1
        }

        functions := program.Functions
        functionCount := functions.Count
        functionWords := new int[](functionCount)
        functionVoids := new bool[](functionCount)
        index = 0
        while index < functionCount {
            functionWords[index] = FreeFunctionAttributes()
            functionVoids[index] = IsVoidReturnCanonical(functions[index].ReturnCanonical)
            index = index + 1
        }

        return new ColumnarMethodRows(
            structCount,
            structWords,
            structVoids,
            interfaceCount,
            interfaceWords,
            functionCount,
            functionWords,
            functionVoids
        )
    }

    static func PublicFieldAttribute(): int {
        return 6
    }

    static func StaticFieldAttribute(): int {
        return 16
    }

    static func InitOnlyFieldAttribute(): int {
        return 32
    }

    // Public 6; +Static 16 for a static field; +InitOnly 32 for a readonly one. Four words in all:
    // instance 6, readonly instance 38, static 22, readonly static 54.
    static func FieldAttributesFor(isStatic: bool, isReadonly: bool): int {
        bits := PublicFieldAttribute()
        if isStatic {
            bits = bits | StaticFieldAttribute()
        }

        if isReadonly {
            bits = bits | InitOnlyFieldAttribute()
        }

        return bits
    }

    // THE READONLY FLAG IS BOUNDS-GUARDED AND THAT GUARD IS THE COMPUTATION. `FieldReadonlyFlags` may
    // be SHORTER than `FieldNames` -- a field past its end is simply not readonly -- and reading it
    // unguarded would throw on a shape the emitter accepts today.
    static func FieldIsReadonlyAt(input: ColumnarStructInput, index: int): bool {
        if index < input.FieldReadonlyFlags.Length {
            return input.FieldReadonlyFlags[index]
        }
        return false
    }

    // A NULLABLE FIELD is one whose CANONICAL type text ends in `?`. The emitter records those names
    // on the type definition, so this decides stored state and is planner work.
    static func FieldIsNullableAt(input: ColumnarStructInput, index: int): bool {
        return input.FieldTypeCanonicals[index].EndsWith("?", StringComparison.Ordinal)
    }

    static func BuildFields(program: ColumnarProgramInput): ColumnarFieldRows {
        structs := program.Structs
        count := structs.Count
        names := new string[][](count)
        words := new int[][](count)
        statics := new bool[][](count)
        nullables := new bool[][](count)

        index := 0
        while index < count {
            input := structs[index]
            fieldCount := input.FieldNames.Length
            fieldNames := new string[](fieldCount)
            fieldWords := new int[](fieldCount)
            fieldStatics := new bool[](fieldCount)
            fieldNullables := new bool[](fieldCount)
            field := 0
            while field < fieldCount {
                fieldNames[field] = input.FieldNames[field]
                isStatic := input.FieldStaticFlags[field]
                fieldStatics[field] = isStatic
                fieldWords[field] = FieldAttributesFor(isStatic, FieldIsReadonlyAt(input, field))
                fieldNullables[field] = FieldIsNullableAt(input, field)
                field = field + 1
            }
            names[index] = fieldNames
            words[index] = fieldWords
            statics[index] = fieldStatics
            nullables[index] = fieldNullables
            index = index + 1
        }

        return new ColumnarFieldRows(count, names, words, statics, nullables)
    }

    static func BuildTypeDefs(program: ColumnarProgramInput): ColumnarTypeDefRows {
        interfaces := program.Interfaces
        interfaceCount := interfaces.Count
        interfaceNames := new string[](interfaceCount)
        interfaceAttributes := new int[](interfaceCount)
        index := 0
        while index < interfaceCount {
            iface := interfaces[index]
            interfaceNames[index] = program.ExactTypeNameForFile(iface.Name, iface.SourceFileId)
            interfaceAttributes[index] = InterfaceTypeAttributes()
            index = index + 1
        }

        structs := program.Structs
        structCount := structs.Count
        structNames := new string[](structCount)
        structAttributes := new int[](structCount)
        structEnclosing := new string[](structCount)
        index = 0
        while index < structCount {
            input := structs[index]
            // A STRUCT USES ITS OWN RESOLVER. `ExactStructTypeName` and `ExactTypeNameForFile` are
            // different functions and must not be folded.
            structNames[index] = program.ExactStructTypeName(input)
            isNested := input.EnclosingTypeName.Length > 0
            if isNested {
                structEnclosing[index] = program.ExactRelativeTypeNameForFile(input.EnclosingTypeName, input.SourceFileId)
            } else {
                structEnclosing[index] = ""
            }
            structAttributes[index] = StructTypeAttributesFor(input.IsReference, isNested, input.NestedVisibilityAttributes)
            index = index + 1
        }

        return new ColumnarTypeDefRows(
            interfaceCount,
            interfaceNames,
            interfaceAttributes,
            structCount,
            structNames,
            structAttributes,
            structEnclosing
        )
    }

    static func BuildAssemblyAndEnums(
        program: ColumnarProgramInput,
        assemblyName: string
    ): ColumnarDeclarationPlan {
        if program == null {
            throw new InvalidOperationException("Columnar declaration planning requires a program input.")
        }

        enums := program.Enums
        count := enums.Count
        exactNames := new string[](count)
        isStringBacked := new bool[](count)
        typeAttributes := new int[](count)
        memberNames := new string[][](count)
        memberValues := new int[][](count)
        memberStringValues := new string[][](count)

        index := 0
        while index < count {
            input := enums[index]
            exactNames[index] = program.ExactTypeNameForFile(input.Name, input.SourceFileId)
            isStringBacked[index] = input.IsStringBacked
            if input.IsStringBacked {
                typeAttributes[index] = StringBackedEnumTypeAttributes()
            } else {
                typeAttributes[index] = IntBackedEnumTypeAttributes()
            }

            memberCount := input.MemberNames.Length
            names := new string[](memberCount)
            values := new int[](memberCount)
            stringValues := new string[](memberCount)
            member := 0
            while member < memberCount {
                names[member] = input.MemberNames[member]
                values[member] = input.MemberValues[member]
                stringValues[member] = EnumMemberStringValueAt(input, member)
                member = member + 1
            }
            memberNames[index] = names
            memberValues[index] = values
            memberStringValues[index] = stringValues
            index = index + 1
        }

        customAttributes := BuildCustomAttributes(program)
        properties := BuildProperties(program)
        methods := BuildMethods(program)
        return new ColumnarDeclarationPlan(
            BuildPInvokes(program, methods),
            customAttributes,
            properties,
            methods,
            BuildFields(program),
            BuildTypeDefs(program),
            assemblyName,
            assemblyName,
            count,
            exactNames,
            isStringBacked,
            typeAttributes,
            memberNames,
            memberValues,
            memberStringValues
        )
    }
}

namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

// THE DECLARATION-ROW IR — THE SECOND HALF OF THE PLAN-ROW IR, WHICH DID NOT EXIST.
//
// `ColumnarCodePlan` describes METHOD BODIES and nothing else. The declaration host — the walk in
// `ColumnarIlEmitter.TryEmitColumnarAssembly` that defines the module, the types, their fields,
// methods, properties, generic parameters and attributes — read `ColumnarProgramInput` directly and
// called Reflection.Emit imperatively, computing the resolved names and the CLR attribute words
// inline as it went. So a SECOND executor over "the same plan rows" had, for every declaration,
// no rows to execute.
//
// This is that table. It grows one declaration family per slice (023/2 S2.1 (a)…(i)); this file
// carries (a) — the assembly, the module and the enums. The rule the whole arc follows: anything the
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

class ColumnarDeclarationPlan {
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

        return new ColumnarDeclarationPlan(
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

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
class ColumnarDeclarationPlan {
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

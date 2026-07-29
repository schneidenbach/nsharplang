namespace NSharpLang.Compiler

import System

// The analyzer's conversion/assignability CLASSIFICATION TABLES.
//
// These are the leaf policies the assignability decision consults: the CLR implicit
// numeric-widening table, the reference-vs-value classification that decides whether `null` is
// assignable to a target, and the MetadataLoadContext-safe reflection assignability walk. They are
// exact, total functions of their inputs — no analyzer state, no diagnostics, no recovery.
//
// The numeric table is stated ONCE, over an internal widening code, and reached through two
// vocabularies: N# simple type names (`byte`, `sbyte`, ...) for source-declared TypeInfo values and
// CLR full names (`System.Byte`, ...) for reflection-bound values. Each vocabulary maps only its own
// spellings, so a reflection-spelled name never satisfies the source table and vice versa.

// The participating built-in numeric types, in widening order. `None` is every type that takes no
// part in an implicit numeric conversion in either direction.
enum NumericConversionKind {
    None,
    Byte,
    SByte,
    Short,
    UShort,
    Int,
    UInt,
    Long,
    ULong,
    Char,
    Float,
    Double,
    Decimal
}

public class AnalyzerConversionFacts {

    // CLR implicit numeric conversion over analyzer TypeInfo values. Only the built-in simple types
    // participate; identical names are NOT a conversion (the caller answers identity first).
    public static func IsImplicitNumericConversion(source: TypeInfo, target: TypeInfo): bool {
        sourceSimple := source as SimpleTypeInfo
        targetSimple := target as SimpleTypeInfo
        if sourceSimple == null || targetSimple == null {
            return false
        }

        return IsNumericWidening(
            SourceNumericCode(sourceSimple.Name),
            SourceNumericCode(targetSimple.Name))
    }

    // CLR implicit numeric conversion over reflection types. Identical reflection types short-circuit
    // to true, and a Nullable<T> is read through to T on both sides before the table is consulted.
    public static func IsImplicitNumericReflectionConversion(sourceType: Type, targetType: Type): bool {
        if sourceType == targetType {
            return true
        }

        return IsNumericWidening(
            ClrNumericCode(NumericTypeFullName(sourceType)),
            ClrNumericCode(NumericTypeFullName(targetType)))
    }

    // Returns true when the type is a reference type — that is, when `null` is one of its values.
    // Numeric primitives, bool, char, structs, record structs, enums, byref types and closed generic
    // instantiations are value types.
    public static func IsReferenceType(candidate: TypeInfo): bool {
        simple := candidate as SimpleTypeInfo
        if simple != null {
            name := simple.Name
            if name == "int" || name == "long" || name == "float" || name == "double" || name == "decimal"
                || name == "byte" || name == "sbyte" || name == "short" || name == "ushort"
                || name == "uint" || name == "ulong" || name == "char" || name == "bool"
                || name == "void" || name == "null" || name == "never" {
                return false
            }

            return true
        }

        classType := candidate as ClassTypeInfo
        interfaceType := candidate as InterfaceTypeInfo
        arrayType := candidate as ArrayTypeInfo
        functionType := candidate as FunctionTypeInfo
        unionType := candidate as UnionTypeInfo
        anonymousUnionType := candidate as AnonymousUnionTypeInfo
        if classType != null || interfaceType != null || arrayType != null
            || functionType != null || unionType != null || anonymousUnionType != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return !recordType.IsStruct
        }

        structType := candidate as StructTypeInfo
        enumType := candidate as EnumTypeInfo
        byRefType := candidate as ByRefTypeInfo
        if structType != null || enumType != null || byRefType != null {
            return false
        }

        genericType := candidate as GenericTypeInfo
        if genericType != null {
            return false
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return !reflectionType.Type.get_IsValueType()
        }

        return false
    }

    // Assignability between two reflection types. `Type.IsAssignableFrom` alone is not sufficient
    // inside the analyzer's MetadataLoadContext: types loaded from different assembly identities are
    // not reference-equal, so the exact-identity comparison is applied to the source's interface list
    // and base chain as well.
    public static func IsReflectionAssignableFrom(targetType: Type, sourceType: Type): bool {
        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(targetType, sourceType) {
            return true
        }

        if targetType.IsAssignableFrom(sourceType) {
            return true
        }

        sourceInterfaces := sourceType.GetInterfaces()
        index := 0
        while index < sourceInterfaces.Length {
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(targetType, sourceInterfaces[index]) {
                return true
            }

            index += 1
        }

        baseType := sourceType.get_BaseType()
        while baseType != null {
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(targetType, baseType) {
                return true
            }

            baseType = baseType.get_BaseType()
        }

        return false
    }

    // The widening table, stated once. Kinds are assigned by SourceNumericCode / ClrNumericCode;
    // `None` is every non-participating type and never widens in either direction.
    static func IsNumericWidening(sourceCode: NumericConversionKind, targetCode: NumericConversionKind): bool {
        if sourceCode == NumericConversionKind.None || targetCode == NumericConversionKind.None {
            return false
        }

        if sourceCode == NumericConversionKind.Byte {
            return targetCode == NumericConversionKind.Short || targetCode == NumericConversionKind.UShort
                || targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.UInt
                || targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong
                || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.SByte {
            return targetCode == NumericConversionKind.Short || targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.Long
                || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Short {
            return targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.Long
                || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.UShort {
            return targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.UInt
                || targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong
                || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Int {
            return targetCode == NumericConversionKind.Long || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.UInt {
            return targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong
                || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Long || sourceCode == NumericConversionKind.ULong {
            return IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Char {
            return targetCode == NumericConversionKind.UShort || targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.UInt
                || targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong
                || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Float {
            return targetCode == NumericConversionKind.Double
        }

        return false
    }

    static func IsFloatingOrDecimalCode(code: NumericConversionKind): bool {
        return code == NumericConversionKind.Float || code == NumericConversionKind.Double || code == NumericConversionKind.Decimal
    }

    // N# source spellings. Anything else — including CLR full names — is not a participant.
    static func SourceNumericCode(name: string): NumericConversionKind {
        if name == "byte" { return NumericConversionKind.Byte }
        if name == "sbyte" { return NumericConversionKind.SByte }
        if name == "short" { return NumericConversionKind.Short }
        if name == "ushort" { return NumericConversionKind.UShort }
        if name == "int" { return NumericConversionKind.Int }
        if name == "uint" { return NumericConversionKind.UInt }
        if name == "long" { return NumericConversionKind.Long }
        if name == "ulong" { return NumericConversionKind.ULong }
        if name == "char" { return NumericConversionKind.Char }
        if name == "float" { return NumericConversionKind.Float }
        if name == "double" { return NumericConversionKind.Double }
        if name == "decimal" { return NumericConversionKind.Decimal }
        return NumericConversionKind.None
    }

    // CLR full names. Anything else — including N# source spellings — is not a participant.
    static func ClrNumericCode(fullName: string?): NumericConversionKind {
        if fullName == null { return NumericConversionKind.None }
        if fullName == "System.Byte" { return NumericConversionKind.Byte }
        if fullName == "System.SByte" { return NumericConversionKind.SByte }
        if fullName == "System.Int16" { return NumericConversionKind.Short }
        if fullName == "System.UInt16" { return NumericConversionKind.UShort }
        if fullName == "System.Int32" { return NumericConversionKind.Int }
        if fullName == "System.UInt32" { return NumericConversionKind.UInt }
        if fullName == "System.Int64" { return NumericConversionKind.Long }
        if fullName == "System.UInt64" { return NumericConversionKind.ULong }
        if fullName == "System.Char" { return NumericConversionKind.Char }
        if fullName == "System.Single" { return NumericConversionKind.Float }
        if fullName == "System.Double" { return NumericConversionKind.Double }
        if fullName == "System.Decimal" { return NumericConversionKind.Decimal }
        return NumericConversionKind.None
    }

    static func NumericTypeFullName(candidate: Type): string? {
        underlyingType := Nullable.GetUnderlyingType(candidate)
        if underlyingType != null {
            return underlyingType.FullName
        }

        return candidate.FullName
    }
}

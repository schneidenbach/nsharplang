namespace NSharpLang.Compiler

class NullabilityMetadataCore {
    static func ConvertBuiltInType(fullName: string?): TypeInfo? {
        if fullName == "System.Int32" {
            return BuiltInTypes.Int
        }

        if fullName == "System.Int64" {
            return BuiltInTypes.Long
        }

        if fullName == "System.Single" {
            return BuiltInTypes.Float
        }

        if fullName == "System.Double" {
            return BuiltInTypes.Double
        }

        if fullName == "System.Decimal" {
            return BuiltInTypes.Decimal
        }

        if fullName == "System.Byte" {
            return BuiltInTypes.Byte
        }

        if fullName == "System.SByte" {
            return BuiltInTypes.SByte
        }

        if fullName == "System.Int16" {
            return BuiltInTypes.Short
        }

        if fullName == "System.UInt16" {
            return BuiltInTypes.UShort
        }

        if fullName == "System.UInt32" {
            return BuiltInTypes.UInt
        }

        if fullName == "System.UInt64" {
            return BuiltInTypes.ULong
        }

        if fullName == "System.Char" {
            return BuiltInTypes.Char
        }

        if fullName == "System.Boolean" {
            return BuiltInTypes.Bool
        }

        if fullName == "System.String" {
            return BuiltInTypes.String
        }

        if fullName == "System.Void" {
            return BuiltInTypes.Void
        }

        if fullName == "System.Object" {
            return BuiltInTypes.Object
        }

        return null
    }

    static func FormatTypeInfo(typeInfo: TypeInfo): string {
        return NullabilityTypeDisplay.FormatTypeInfo(typeInfo)
    }

    static func StripMetadata(typeInfo: TypeInfo): TypeInfo {
        return NullabilityTypeDisplay.StripMetadata(typeInfo)
    }

    static func StripClrGenericArity(name: string): string {
        tickIndex := name.IndexOf('`')
        if tickIndex >= 0 {
            return name.Substring(0, tickIndex)
        }

        return name
    }

    static func FormatArrayClrTypeName(elementTypeName: string): string {
        return elementTypeName + "[]"
    }

    static func FormatGenericClrTypeName(name: string, formattedArguments: string[]): string {
        return name + "<" + string.Join(", ", formattedArguments) + ">"
    }

    static func ApplyReadState(
        typeInfo: TypeInfo,
        isNullableValueType: bool,
        canCarryReferenceNullability: bool,
        isNullableReadState: bool,
        isUnknownReadState: bool): TypeInfo {
        if isNullableValueType {
            return typeInfo
        }

        if !canCarryReferenceNullability {
            return typeInfo
        }

        if isNullableReadState {
            return EnsureNullable(typeInfo)
        }

        if isUnknownReadState {
            return EnsureOblivious(typeInfo)
        }

        return typeInfo
    }

    static func FormatParameter(
        isOut: bool,
        isByRef: bool,
        isParams: bool,
        attributePrefix: string,
        typeName: string,
        parameterName: string?): string {
        modifier := ""
        if isOut {
            modifier = "out "
        } else if isByRef {
            modifier = "ref "
        } else if isParams {
            modifier = "params "
        }

        return attributePrefix + modifier + typeName + " " + (parameterName ?? "")
    }

    static func EnsureNullable(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return typeInfo
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return new NullableTypeInfo(oblivious.InnerType)
        }

        return new NullableTypeInfo(typeInfo)
    }

    static func EnsureOblivious(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return typeInfo
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return typeInfo
        }

        return new ObliviousTypeInfo(typeInfo)
    }

    static func EnsureNotNull(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return oblivious.InnerType
        }

        return typeInfo
    }

    static func CanCarryReferenceNullability(typeInfo: TypeInfo): bool {
        simple := typeInfo as SimpleTypeInfo
        if simple != null {
            return !IsNonNullableSimpleType(simple.Name)
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return false
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return CanCarryReferenceNullability(oblivious.InnerType)
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return false
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return false
        }

        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null {
            return false
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return !recordType.IsStruct
        }

        unknown := typeInfo as UnknownTypeInfo
        if unknown != null {
            return false
        }

        return true
    }

    static func FormatSimpleClrTypeName(name: string): string {
        if name == "Boolean" {
            return "bool"
        }

        if name == "Byte" {
            return "byte"
        }

        if name == "SByte" {
            return "sbyte"
        }

        if name == "Int16" {
            return "short"
        }

        if name == "UInt16" {
            return "ushort"
        }

        if name == "Int32" {
            return "int"
        }

        if name == "UInt32" {
            return "uint"
        }

        if name == "Int64" {
            return "long"
        }

        if name == "UInt64" {
            return "ulong"
        }

        if name == "Single" {
            return "float"
        }

        if name == "Double" {
            return "double"
        }

        if name == "Decimal" {
            return "decimal"
        }

        if name == "Char" {
            return "char"
        }

        if name == "String" {
            return "string"
        }

        if name == "Object" {
            return "object"
        }

        if name == "Void" {
            return "void"
        }

        return name
    }

    static func IsNonNullableSimpleType(name: string): bool {
        if name == "int" {
            return true
        }

        if name == "long" {
            return true
        }

        if name == "float" {
            return true
        }

        if name == "double" {
            return true
        }

        if name == "decimal" {
            return true
        }

        if name == "byte" {
            return true
        }

        if name == "sbyte" {
            return true
        }

        if name == "short" {
            return true
        }

        if name == "ushort" {
            return true
        }

        if name == "uint" {
            return true
        }

        if name == "ulong" {
            return true
        }

        if name == "char" {
            return true
        }

        if name == "bool" {
            return true
        }

        if name == "void" {
            return true
        }

        if name == "null" {
            return true
        }

        if name == "never" {
            return true
        }

        return false
    }
}

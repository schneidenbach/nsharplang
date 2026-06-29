namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

public class TypeInfo {
}

public class SimpleTypeInfo: TypeInfo {
    nameValue: string

    Name: string => nameValue

    constructor(name: string) {
        nameValue = name
    }

    override func ToString(): string {
        return nameValue
    }

    override func Equals(value: object): bool {
        other := value as SimpleTypeInfo
        if other == null {
            return false
        }

        return nameValue == other.Name
    }

    override func GetHashCode(): int {
        return nameValue.GetHashCode()
    }
}

public class UnknownTypeInfo: TypeInfo {
    kindValue: UnknownKind

    Kind: UnknownKind => kindValue

    constructor(kind: UnknownKind) {
        kindValue = kind
    }

    override func ToString(): string {
        return "unknown"
    }

    override func Equals(value: object): bool {
        other := value as UnknownTypeInfo
        if other == null {
            return false
        }

        return kindValue == other.Kind
    }

    override func GetHashCode(): int {
        return Convert.ToInt32(kindValue)
    }
}

public class NewtypeInfo: TypeInfo {
    nameValue: string
    underlyingTypeValue: TypeReference

    Name: string => nameValue
    UnderlyingType: TypeReference => underlyingTypeValue

    constructor(name: string, underlyingType: TypeReference) {
        nameValue = name
        underlyingTypeValue = underlyingType
    }

    override func ToString(): string {
        return nameValue
    }
}

public class ExternalTypeInfo: TypeInfo {
    nameValue: string

    Name: string => nameValue

    constructor(name: string) {
        nameValue = name
    }

    override func ToString(): string {
        return nameValue
    }

    override func Equals(value: object): bool {
        other := value as ExternalTypeInfo
        if other == null {
            return false
        }

        return nameValue == other.Name
    }

    override func GetHashCode(): int {
        return nameValue.GetHashCode()
    }
}

public class ReflectionTypeInfo: TypeInfo {
    clrTypeValue: Type

    Type: Type => clrTypeValue

    constructor(clrType: Type) {
        clrTypeValue = clrType
    }

    override func ToString(): string {
        return clrTypeValue.Name
    }
}

public class BuiltInTypes {
    public static Int: SimpleTypeInfo => new SimpleTypeInfo("int")
    public static Long: SimpleTypeInfo => new SimpleTypeInfo("long")
    public static Float: SimpleTypeInfo => new SimpleTypeInfo("float")
    public static Double: SimpleTypeInfo => new SimpleTypeInfo("double")
    public static Decimal: SimpleTypeInfo => new SimpleTypeInfo("decimal")
    public static Byte: SimpleTypeInfo => new SimpleTypeInfo("byte")
    public static SByte: SimpleTypeInfo => new SimpleTypeInfo("sbyte")
    public static Short: SimpleTypeInfo => new SimpleTypeInfo("short")
    public static UShort: SimpleTypeInfo => new SimpleTypeInfo("ushort")
    public static UInt: SimpleTypeInfo => new SimpleTypeInfo("uint")
    public static ULong: SimpleTypeInfo => new SimpleTypeInfo("ulong")
    public static Char: SimpleTypeInfo => new SimpleTypeInfo("char")
    public static Bool: SimpleTypeInfo => new SimpleTypeInfo("bool")
    public static String: SimpleTypeInfo => new SimpleTypeInfo("string")
    public static Void: SimpleTypeInfo => new SimpleTypeInfo("void")
    public static Object: SimpleTypeInfo => new SimpleTypeInfo("object")
    public static Null: SimpleTypeInfo => new SimpleTypeInfo("null")
    public static Never: SimpleTypeInfo => new SimpleTypeInfo("never")
    public static Unknown: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.ErrorRecovery)
    public static InferenceHole: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.InferenceHole)
    public static DeferredExternal: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.DeferredExternal)

    public static func Is(typeInfo: TypeInfo?, builtIn: SimpleTypeInfo): bool {
        if typeInfo == null {
            return false
        }

        simple := typeInfo as SimpleTypeInfo
        if simple == null {
            return false
        }

        return simple.Equals(builtIn)
    }

    public static func IsNot(typeInfo: TypeInfo?, builtIn: SimpleTypeInfo): bool {
        return !Is(typeInfo, builtIn)
    }

    public static func IsUnknown(typeInfo: TypeInfo): bool {
        unknown := typeInfo as UnknownTypeInfo
        return unknown != null
    }
}

public class TupleTypeElementInfo {
    Name: string?
    Type: TypeInfo

    constructor(name: string?, elementType: TypeInfo) {
        Name = name
        Type = elementType
    }
}

public class TupleTypeInfo: TypeInfo {
    Elements: List<TupleTypeElementInfo>

    constructor(elements: List<TupleTypeElementInfo>) {
        Elements = elements
    }
}

public class AliasTypeInfo: TypeInfo {
    aliasedTypeValue: TypeReference

    AliasedType: TypeReference => aliasedTypeValue

    constructor(aliasedType: TypeReference) {
        aliasedTypeValue = aliasedType
    }
}

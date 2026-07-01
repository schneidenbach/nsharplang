namespace NSharpLang.Compiler

import System.Collections.Generic

public class NullabilityTypeDisplay {
    public static func TryFormatTypeInfo(typeInfo: TypeInfo): string? {
        simple := typeInfo as SimpleTypeInfo
        if simple != null {
            return simple.Name
        }

        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return classType.Name
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }

        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null {
            return soaType.Declaration.Name
        }

        rowType := typeInfo as SoaRowTypeInfo
        if rowType != null {
            return rowType.Declaration.Name + ".Row"
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Name
        }

        anonymousUnion := typeInfo as AnonymousUnionTypeInfo
        if anonymousUnion != null {
            return FormatTypeList(anonymousUnion.Arms, " | ")
        }

        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            return unionType.Declaration.Name
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            return generic.Name + "<" + FormatTypeList(generic.TypeArguments, ", ") + ">"
        }

        external := typeInfo as ExternalTypeInfo
        if external != null {
            return external.Name
        }

        unknown := typeInfo as UnknownTypeInfo
        if unknown != null {
            return "unknown"
        }

        function := typeInfo as FunctionTypeInfo
        if function != null {
            return FormatFunctionType(function)
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            elementText := TryFormatTypeInfo(array.ElementType)
            if elementText != null {
                return elementText + "[]"
            }

            return null
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            innerText := TryFormatTypeInfo(nullable.InnerType)
            if innerText != null {
                return innerText + "?"
            }

            return null
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            innerText := TryFormatTypeInfo(oblivious.InnerType)
            if innerText != null {
                return innerText + "!"
            }

            return null
        }

        return null
    }

    public static func FormatTypeInfo(typeInfo: TypeInfo): string {
        formatted := TryFormatTypeInfo(typeInfo)
        if formatted != null {
            return formatted
        }

        typeObject := typeInfo as object
        text := typeObject.ToString()
        if text == null {
            return "unknown"
        }

        return text
    }

    public static func StripMetadata(typeInfo: TypeInfo): TypeInfo {
        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return StripMetadata(oblivious.InnerType)
        }

        return typeInfo
    }

    static func FormatFunctionType(function: FunctionTypeInfo): string {
        if function.ParameterTypes == null || function.ReturnType == null {
            if function.SyntheticName != null {
                return function.SyntheticName
            }

            if function.SourceName != null {
                return function.SourceName
            }

            return "function"
        }

        return "(" + FormatTypeList(function.ParameterTypes, ", ") + ") -> " + FormatTypeInfo(function.ReturnType)
    }

    static func FormatTypeList(types: List<TypeInfo>, separator: string): string {
        result := ""
        i := 0
        while i < types.Count {
            if i > 0 {
                result = result + separator
            }

            result = result + FormatTypeInfo(types[i])
            i = i + 1
        }

        return result
    }
}

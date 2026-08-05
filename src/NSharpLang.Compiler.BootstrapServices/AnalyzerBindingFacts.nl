namespace NSharpLang.Compiler

class AnalyzerBindingFacts {
    static func GetParameterDeclarationPosition(parameterLine: int, parameterColumn: int, fallbackLine: int, fallbackColumn: int): ValueTuple<int, int> {
        line := fallbackLine
        if parameterLine > 0 {
            line = parameterLine
        }

        column := fallbackColumn
        if parameterColumn > 0 {
            column = parameterColumn
        }

        return new ValueTuple<int, int>(line, column)
    }

    static func IsValueBinding(name: string, typeInfo: TypeInfo, hasTypeBinding: bool): bool {
        if name == "this" || name == "value" {
            return false
        }

        if hasTypeBinding {
            return false
        }

        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            return false
        }

        methodGroup := typeInfo as NSharpMethodGroupInfo
        if methodGroup != null {
            return false
        }

        return true
    }

    static func TypeInfoToDeclarationKind(typeInfo: TypeInfo): string {
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return "class"
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return "struct"
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return "record"
        }

        soaRecordType := typeInfo as SoaRecordTypeInfo
        if soaRecordType != null {
            return "soaRecord"
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return "interface"
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return "enum"
        }

        anonymousUnionType := typeInfo as AnonymousUnionTypeInfo
        if anonymousUnionType != null {
            return "union"
        }

        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            return "union"
        }

        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            return "function"
        }

        methodGroup := typeInfo as NSharpMethodGroupInfo
        if methodGroup != null {
            return "function"
        }

        return "variable"
    }

    static func IsTypeDeclarationKind(kind: string): bool {
        if kind == "class" {
            return true
        }
        if kind == "struct" {
            return true
        }
        if kind == "record" {
            return true
        }
        if kind == "soaRecord" {
            return true
        }
        if kind == "interface" {
            return true
        }
        if kind == "enum" {
            return true
        }
        if kind == "union" {
            return true
        }
        if kind == "typeAlias" {
            return true
        }
        if kind == "newtype" {
            return true
        }
        return false
    }
}

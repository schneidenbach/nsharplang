namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast

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

    // WHETHER A DECLARED PARAMETER IS A REFERENCE TO ITS CALLER'S STORAGE, in either spelling.
    static func IsByReferenceParameter(parameter: Parameter): bool {
        modifier := parameter.Modifier
        if modifier == ParameterModifier.Ref || modifier == ParameterModifier.Out || modifier == ParameterModifier.In {
            return true
        }

        return parameter.Type as ByRefTypeReference != null
    }

    // THE TYPE A PARAMETER'S NAME IS BOUND AT INSIDE ITS BODY. A by-reference parameter has two
    // spellings — `ref v: int` and the systems `v: &int` — and on the CLR both are `int&`, so both
    // names are the CALLER'S storage: a read is that storage's value and a write goes through to it
    // (the emitter chooses `ldind`/`stind` from the CLR parameter type, not from the spelling). The
    // `ref` spelling already binds its name at `int`; the `&` spelling resolves to `&int` and binds
    // at the storage's type here, so `v + 1` and `v = x` mean one thing in both. The SIGNATURE keeps
    // the `&T` — only the name inside the body is the storage — and passing the name on by reference
    // is written `ref v`, as it is for every other by-reference argument.
    static func ParameterBindingType(declared: TypeInfo): TypeInfo {
        byRef := declared as ByRefTypeInfo
        if byRef != null {
            return byRef.InnerType
        }

        return declared
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

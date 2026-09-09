namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast

class TaskLikeResultType {
    foundValue: bool
    sourceResultTypeValue: TypeInfo?

    Found: bool => foundValue
    SourceResultType: TypeInfo? => sourceResultTypeValue

    constructor(found: bool, sourceResultType: TypeInfo? = null) {
        foundValue = found
        sourceResultTypeValue = sourceResultType
    }

    static func None(): TaskLikeResultType {
        return new TaskLikeResultType(false)
    }

    static func Source(resultType: TypeInfo): TaskLikeResultType {
        return new TaskLikeResultType(true, resultType)
    }
}

class TaskLikeTypeFacts {
    static func IsUnitTaskLikeType(typeInfo: TypeInfo): bool {
        simple := typeInfo as SimpleTypeInfo
        if simple != null {
            return IsTaskLikeName(simple.Name)
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            return generic.TypeArguments.Count == 0 && IsTaskLikeName(generic.Name)
        }

        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return IsTaskLikeName(classType.Name)
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return IsTaskLikeName(structType.Name)
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return IsTaskLikeName(recordType.Name)
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return IsTaskLikeName(interfaceType.Name)
        }

        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            return IsTaskLikeName(unionType.Declaration.Name)
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return IsTaskLikeName(enumType.Declaration.Name)
        }

        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null {
            return IsTaskLikeName(soaType.Declaration.Name)
        }

        rowType := typeInfo as SoaRowTypeInfo
        if rowType != null {
            return IsTaskLikeName(rowType.Declaration.Name + ".Row")
        }

        external := typeInfo as ExternalTypeInfo
        if external != null {
            return IsTaskLikeName(external.Name)
        }

        return false
    }

    static func IsUnitTaskLikeTypeReference(typeRef: TypeReference?): bool {
        if typeRef == null {
            return false
        }

        simple := typeRef as SimpleTypeReference
        if simple != null {
            return IsTaskLikeName(simple.Name)
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            return generic.TypeArguments.Count == 0 && IsTaskLikeName(generic.Name)
        }

        return false
    }

    static func GetTaskLikeResultType(typeInfo: TypeInfo): TaskLikeResultType {
        generic := typeInfo as GenericTypeInfo
        if generic != null {
            if generic.TypeArguments.Count == 1 && IsTaskLikeName(generic.Name) {
                return TaskLikeResultType.Source(generic.TypeArguments[0])
            }
        }

        return TaskLikeResultType.None()
    }

    static func IsTaskLikeName(name: string): bool {
        if name == "Task" || name == "ValueTask" {
            return true
        }

        if name == "System.Threading.Tasks.Task" || name == "System.Threading.Tasks.ValueTask" {
            return true
        }

        return name.EndsWith(".Task", StringComparison.Ordinal) || name.EndsWith(".ValueTask", StringComparison.Ordinal)
    }
}

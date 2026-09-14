namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// The TEXT a completion shows for a type, and for a function type's parameter list.
//
// ONE RULE RUNS THROUGH THE WHOLE FILE: WHAT THE SOURCE WROTE BEATS WHAT THE BINDER RESOLVED. A
// completion is read beside the source it completes, so the `TypeReference`s the parser produced —
// `SourceReturnType`, `SourceParameterTypes` — answer first, and the resolved `TypeInfo` answers
// only where the source form is absent. That is why this is a policy and not a call to
// `NullabilityMetadataReflection.FormatTypeInfo`: the resolved form is the FALLBACK here, not the
// answer.
class CompletionTypeTextFacts {

    // The type text for a completion item's `Type` field. A function type shows its RETURN type —
    // the source-written one when there is one — and anything else shows itself.
    static func FormatTypeText(typeInfo: TypeInfo): string {
        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            sourceReturnType := functionType.SourceReturnType
            if sourceReturnType != null {
                return TypeReferenceFacts.GetDisplayNameOrVoid(sourceReturnType)
            }

            resolvedReturnType := functionType.ReturnType
            if resolvedReturnType != null {
                return NullabilityMetadataReflection.FormatTypeInfo(resolvedReturnType)
            }
        }

        return NullabilityMetadataReflection.FormatTypeInfo(typeInfo)
    }

    // The type text of one parameter of a function type. `"unknown"` is the answer when neither
    // list reaches the index — the completion still names the parameter, it just cannot type it.
    static func GetFunctionParameterTypeText(functionType: FunctionTypeInfo, index: int): string {
        sourceParameterTypes := functionType.SourceParameterTypes
        if sourceParameterTypes != null && index < sourceParameterTypes.Count {
            return TypeReferenceFacts.GetDisplayNameOrVoid(sourceParameterTypes[index])
        }

        parameterTypes := functionType.ParameterTypes
        if parameterTypes != null && index < parameterTypes.Count {
            return NullabilityMetadataReflection.FormatTypeInfo(parameterTypes[index])
        }

        return "unknown"
    }

    // A function type's parameter list, rendered the way a signature reads. A parameter past the
    // required count carries ` = ...` UNLESS it is the `params` parameter — `params` is variadic,
    // not defaulted, and writing `= ...` after it would be a lie. A function type with no parameter
    // names has no list to render at all, which is `null` and not `"()"`.
    static func FormatFunctionTypeParameters(functionType: FunctionTypeInfo): string? {
        parameterNames := functionType.ParameterNames
        if parameterNames == null {
            return null
        }

        declaredRequiredCount: int? = functionType.RequiredParameterCount
        builder := new StringBuilder()
        builder.Append("(")

        index := 0
        while index < parameterNames.Count {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(parameterNames[index])
            builder.Append(" ")
            builder.Append(GetFunctionParameterTypeText(functionType, index))
            if HasDefaultedFunctionParameter(functionType, declaredRequiredCount, index) {
                builder.Append(" = ...")
            }

            index = index + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    static func HasDefaultedFunctionParameter(functionType: FunctionTypeInfo, declaredRequiredCount: int?, index: int): bool {
        if !declaredRequiredCount.HasValue {
            return false
        }

        if index < declaredRequiredCount.Value {
            return false
        }

        return AnalyzerCallableReferenceFacts.GetFunctionParameterModifier(functionType, index) != ParameterModifier.Params
    }

    // The text a REFLECTED member's type shows. This is deliberately NOT
    // `NullabilityMetadataReflection.FormatClrTypeName`: that one aliases by SIMPLE NAME through
    // `FormatSimpleClrTypeName`, which renders `Byte` as `byte` and `Decimal` as `decimal`. A
    // completion aliases by FULL NAME over exactly these eight, and everything else keeps its CLR
    // name — so `Byte` stays `Byte` here. Two rules, one subject, deliberately not folded.
    static func FormatClrTypeText(clrType: Type): string {
        fullName := clrType.get_FullName()
        if fullName == "System.Void" {
            return "void"
        }
        if fullName == "System.Int32" {
            return "int"
        }
        if fullName == "System.Int64" {
            return "long"
        }
        if fullName == "System.String" {
            return "string"
        }
        if fullName == "System.Boolean" {
            return "bool"
        }
        if fullName == "System.Double" {
            return "double"
        }
        if fullName == "System.Single" {
            return "float"
        }
        if fullName == "System.Object" {
            return "object"
        }

        if clrType.get_IsGenericType() {
            builder := new StringBuilder()
            builder.Append(NullabilityMetadataCore.StripClrGenericArity(clrType.Name))
            builder.Append("<")

            typeArguments := clrType.GetGenericArguments()
            index := 0
            while index < typeArguments.Length {
                if index > 0 {
                    builder.Append(", ")
                }

                builder.Append(FormatClrTypeText(typeArguments[index]))
                index = index + 1
            }

            builder.Append(">")
            return builder.ToString()
        }

        return clrType.Name
    }
}

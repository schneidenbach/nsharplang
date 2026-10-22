namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast

class AnalyzerOverloadSignatureFacts {
    static func HasSourceParameterSignature(function: FunctionTypeInfo): bool {
        return function.SourceParameterTypes != null
    }

    static func HasDistinctParameterSignature(newFunction: FunctionTypeInfo, existingFunctions: IReadOnlyList<FunctionTypeInfo>): bool {
        for existingFunction in existingFunctions {
            if ParameterSignaturesMatch(newFunction, existingFunction) {
                return false
            }
        }

        return true
    }

    static func ParameterSignaturesMatch(a: FunctionTypeInfo, b: FunctionTypeInfo): bool {
        aParameters := a.SourceParameterTypes
        bParameters := b.SourceParameterTypes
        if aParameters == null || bParameters == null {
            return false
        }

        if aParameters.Count != bParameters.Count {
            return false
        }

        index := 0
        while index < aParameters.Count {
            if GetFunctionParameterSignature(a, index, aParameters[index]) != GetFunctionParameterSignature(b, index, bParameters[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // Cross-file duplicates are compared before the other declaration has been materialized as a
    // TypeInfo. Keep this spelling contract identical to the overload-group comparison above.
    static func ParameterSignaturesMatch(a: FunctionTypeInfo, b: FunctionDeclaration): bool {
        aParameters := a.SourceParameterTypes
        if aParameters == null || b == null || aParameters.Count != b.Parameters.Count {
            return false
        }

        index := 0
        while index < aParameters.Count {
            otherType := b.Parameters[index].Type
            if otherType == null || GetFunctionParameterSignature(a, index, aParameters[index]) != GetDeclarationParameterSignature(b.Parameters[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // `in` and by-value parameters have different CLR signatures and can form overloads. The three
    // by-reference directions still share one declaration identity for overload uniqueness, matching
    // C#'s rule that ref/out/in cannot distinguish declarations from one another.
    static func GetFunctionParameterSignature(functionType: FunctionTypeInfo, index: int, typeRef: TypeReference): string {
        modifier := Ast.ParameterModifier.None
        modifiers := functionType.ParameterModifiers
        if modifiers != null && index >= 0 && index < modifiers.Count {
            modifier = modifiers[index]
        }

        return GetParameterSignature(typeRef, modifier)
    }

    static func GetDeclarationParameterSignature(parameter: Parameter): string {
        return GetParameterSignature(parameter.Type, parameter.Modifier)
    }

    static func GetParameterSignature(typeRef: TypeReference, modifier: Ast.ParameterModifier): string {
        signature := GetParameterTypeSignature(typeRef)
        if modifier == Ast.ParameterModifier.Ref || modifier == Ast.ParameterModifier.Out || modifier == Ast.ParameterModifier.In {
            if !signature.StartsWith("&", StringComparison.Ordinal) {
                return "&" + signature
            }
        }

        return signature
    }

    static func GetParameterTypeSignature(typeRef: TypeReference): string {
        simple := typeRef as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        array := typeRef as ArrayTypeReference
        if array != null {
            return GetParameterTypeSignature(array.ElementType) + "[]"
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            genericBuilder := new StringBuilder()
            genericBuilder.Append(generic.Name)
            genericBuilder.Append("<")
            AppendTypeReferenceList(genericBuilder, generic.TypeArguments, ",")
            genericBuilder.Append(">")
            return genericBuilder.ToString()
        }

        nullable := typeRef as NullableTypeReference
        if nullable != null {
            return GetParameterTypeSignature(nullable.InnerType) + "?"
        }

        unionReference := typeRef as UnionTypeReference
        if unionReference != null {
            unionBuilder := new StringBuilder()
            AppendTypeReferenceList(unionBuilder, unionReference.Arms, "|")
            return unionBuilder.ToString()
        }

        tuple := typeRef as TupleTypeReference
        if tuple != null {
            tupleBuilder := new StringBuilder()
            tupleBuilder.Append("(")
            AppendTupleTypeElementList(tupleBuilder, tuple.Elements, ",")
            tupleBuilder.Append(")")
            return tupleBuilder.ToString()
        }

        functionReference := typeRef as FunctionTypeReference
        if functionReference != null {
            functionBuilder := new StringBuilder()
            functionBuilder.Append("(")
            AppendTypeReferenceList(functionBuilder, functionReference.ParameterTypes, ",")
            functionBuilder.Append(")->")
            functionBuilder.Append(GetParameterTypeSignature(functionReference.ReturnType))
            return functionBuilder.ToString()
        }

        byRef := typeRef as ByRefTypeReference
        if byRef != null {
            return "&" + GetParameterTypeSignature(byRef.InnerType)
        }

        typeObject := typeRef as object
        return typeObject.ToString() ?? "<unknown type reference>"
    }

    static func AppendTypeReferenceList(builder: StringBuilder, types: List<TypeReference>, separator: string) {
        index := 0
        while index < types.Count {
            if index > 0 {
                builder.Append(separator)
            }

            builder.Append(GetParameterTypeSignature(types[index]))
            index = index + 1
        }
    }

    static func AppendTupleTypeElementList(builder: StringBuilder, elements: List<TupleTypeElement>, separator: string) {
        index := 0
        while index < elements.Count {
            if index > 0 {
                builder.Append(separator)
            }

            builder.Append(GetParameterTypeSignature(elements[index].Type))
            index = index + 1
        }
    }
}

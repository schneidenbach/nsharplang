namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast

class AnalyzerOverloadSignatureFacts {
    static func HasSourceParameterSignature(function: FunctionTypeInfo): bool {
        return function.SourceParameterTypes != null
    }

    static func HasDistinctParameterSignature(newFunction: FunctionTypeInfo, existingFunctions: IReadOnlyList<FunctionTypeInfo>): bool {
        index := 0
        while index < existingFunctions.Count {
            if ParameterSignaturesMatch(newFunction, existingFunctions[index]) {
                return false
            }

            index = index + 1
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
            if GetParameterTypeSignature(aParameters[index]) != GetParameterTypeSignature(bParameters[index]) {
                return false
            }

            index = index + 1
        }

        return true
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
        return typeObject.ToString()
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

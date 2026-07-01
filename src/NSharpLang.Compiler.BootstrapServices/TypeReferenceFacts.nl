namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast

public class TypeReferenceFacts {
    public static func GetStartSpan(typeRef: TypeReference): SourceSpan {
        if typeRef.Span.IsValid {
            return typeRef.Span
        }

        simple := typeRef as SimpleTypeReference
        if simple != null {
            return SourceSpan.FromStartAndLength(simple.Line, simple.Column, simple.Name.Length)
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            return SourceSpan.FromStartAndLength(generic.Line, generic.Column, generic.Name.Length)
        }

        array := typeRef as ArrayTypeReference
        if array != null {
            return GetStartSpan(array.ElementType)
        }

        nullable := typeRef as NullableTypeReference
        if nullable != null {
            return GetStartSpan(nullable.InnerType)
        }

        unionReference := typeRef as UnionTypeReference
        if unionReference != null {
            if unionReference.Arms.Count > 0 {
                return GetStartSpan(unionReference.Arms[0])
            }

            return SourceSpan.None
        }

        tuple := typeRef as TupleTypeReference
        if tuple != null {
            if tuple.Elements.Count > 0 {
                return GetStartSpan(tuple.Elements[0].Type)
            }

            return SourceSpan.None
        }

        functionReference := typeRef as FunctionTypeReference
        if functionReference != null {
            return GetStartSpan(functionReference.ReturnType)
        }

        byRef := typeRef as ByRefTypeReference
        if byRef != null {
            return GetStartSpan(byRef.InnerType)
        }

        return SourceSpan.None
    }
}

namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Text
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

    public static func IsValidParamsType(typeRef: TypeReference): bool {
        array := typeRef as ArrayTypeReference
        if array != null {
            return true
        }

        generic := typeRef as GenericTypeReference
        if generic == null {
            return false
        }

        typeName := generic.Name
        if typeName == "Span" { return true }
        if typeName == "ReadOnlySpan" { return true }
        if typeName == "IEnumerable" { return true }
        if typeName == "IReadOnlyCollection" { return true }
        if typeName == "IReadOnlyList" { return true }
        if typeName == "ICollection" { return true }
        if typeName == "IList" { return true }
        if typeName == "List" { return true }
        if typeName == "HashSet" { return true }
        if typeName == "Queue" { return true }
        if typeName == "Stack" { return true }
        if typeName == "ArraySegment" { return true }
        if typeName == "Memory" { return true }
        if typeName == "ReadOnlyMemory" { return true }

        return false
    }

    public static func GetDisplayNameOrVoid(typeRef: TypeReference?): string {
        if typeRef == null {
            return "void"
        }

        return GetDisplayName(typeRef)
    }

    public static func GetDisplayName(typeRef: TypeReference): string {
        simple := typeRef as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        array := typeRef as ArrayTypeReference
        if array != null {
            return GetDisplayName(array.ElementType) + "[]"
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            builder := new StringBuilder()
            builder.Append(generic.Name)
            builder.Append("<")
            AppendDisplayNameList(builder, generic.TypeArguments, ", ")
            builder.Append(">")
            return builder.ToString()
        }

        nullable := typeRef as NullableTypeReference
        if nullable != null {
            return GetDisplayName(nullable.InnerType) + "?"
        }

        unionReference := typeRef as UnionTypeReference
        if unionReference != null {
            builder := new StringBuilder()
            AppendDisplayNameList(builder, unionReference.Arms, " | ")
            return builder.ToString()
        }

        tuple := typeRef as TupleTypeReference
        if tuple != null {
            builder := new StringBuilder()
            builder.Append("(")
            AppendTupleElementDisplayNameList(builder, tuple.Elements)
            builder.Append(")")
            return builder.ToString()
        }

        functionReference := typeRef as FunctionTypeReference
        if functionReference != null {
            builder := new StringBuilder()
            builder.Append("(")
            AppendDisplayNameList(builder, functionReference.ParameterTypes, ", ")
            builder.Append(") -> ")
            builder.Append(GetDisplayName(functionReference.ReturnType))
            return builder.ToString()
        }

        byRef := typeRef as ByRefTypeReference
        if byRef != null {
            return "&" + GetDisplayName(byRef.InnerType)
        }

        typeObject := typeRef as object
        return typeObject.ToString()
    }

    static func AppendDisplayNameList(builder: StringBuilder, types: List<TypeReference>, separator: string) {
        index := 0
        while index < types.Count {
            if index > 0 {
                builder.Append(separator)
            }

            builder.Append(GetDisplayName(types[index]))
            index = index + 1
        }
    }

    static func AppendTupleElementDisplayNameList(builder: StringBuilder, elements: List<TupleTypeElement>) {
        index := 0
        while index < elements.Count {
            if index > 0 {
                builder.Append(", ")
            }

            element := elements[index]
            if element.Name != null {
                builder.Append(element.Name)
                builder.Append(": ")
            }

            builder.Append(GetDisplayName(element.Type))
            index = index + 1
        }
    }
}

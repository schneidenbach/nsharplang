namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE WORDS EVERY ANSWER CARRIES — the pure half.
//
// Nine members that turn an AST node, a `TypeReference`, a `TypeInfo` or a modifier mask into the
// text a code-intelligence answer prints. Nothing here resolves anything: no binding map, no
// semantic model, no declaration tree. Every one of them is a total function of its arguments, so
// hover's kind, the outline's type names and the diagnostic's suggestion are all answerable without
// a project at all.
class CodeIntelligenceDisplayText {

    // ── The type-reference display names ─────────────────────────────────
    static func FormatTypeReference(typeRef: TypeReference?): string {
        return TypeReferenceFacts.GetDisplayNameOrVoid(typeRef)
    }

    static func GetTypeReferenceName(typeRef: TypeReference?): string? {
        if typeRef == null {
            return null
        }

        simple := typeRef as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            return generic.Name
        }

        nullable := typeRef as NullableTypeReference
        if nullable != null {
            return GetTypeReferenceName(nullable.InnerType)
        }

        array := typeRef as ArrayTypeReference
        if array != null {
            return GetTypeReferenceName(array.ElementType)
        }

        // The C# spelled this `string.Join(" | ", u.Arms.Select(FormatTypeReference))` — a METHOD
        // GROUP, which is an edge no paren-matching call-graph tool can see. Written out, the arm is
        // a plain loop and the edge is obvious.
        unionReference := typeRef as UnionTypeReference
        if unionReference != null {
            builder := new StringBuilder()
            index := 0
            while index < unionReference.Arms.Count {
                if index > 0 {
                    builder.Append(" | ")
                }

                builder.Append(FormatTypeReference(unionReference.Arms[index]))
                index = index + 1
            }

            return builder.ToString()
        }

        return null
    }

    static func InterfaceNameMatches(typeRef: TypeReference, interfaceName: string): bool {
        simple := typeRef as SimpleTypeReference
        if simple != null {
            return String.Equals(simple.Name, interfaceName, StringComparison.Ordinal)
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            return String.Equals(generic.Name, interfaceName, StringComparison.Ordinal)
        }

        return false
    }

    // ── The type-info display names ──────────────────────────────────────

    static func GetTypeDisplayName(typeInfo: TypeInfo, fallback: string): string {
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

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Name
        }

        // The second method group the C# carried: `u.Arms.Select(FormatTypeInfo)`.
        anonymousUnion := typeInfo as AnonymousUnionTypeInfo
        if anonymousUnion != null {
            builder := new StringBuilder()
            index := 0
            while index < anonymousUnion.Arms.Count {
                if index > 0 {
                    builder.Append(" | ")
                }

                builder.Append(NullabilityMetadataReflection.FormatTypeInfo(anonymousUnion.Arms[index]))
                index = index + 1
            }

            return builder.ToString()
        }

        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            return unionType.Declaration.Name
        }

        reflectionType := typeInfo as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type.get_Name()
        }

        return fallback
    }

    // The kind string every hover and every `query type` answer carries.
    //
    // THE ORDER OF THE LAST TWO REFLECTION TESTS IS LOAD-BEARING: an enum IS a value type, so
    // `IsEnum` must be asked first or every enum reads back as "struct".
    static func TypeInfoToKind(typeInfo: TypeInfo): string {
        if typeInfo as ClassTypeInfo != null {
            return "class"
        }

        if typeInfo as StructTypeInfo != null {
            return "struct"
        }

        if typeInfo as RecordTypeInfo != null {
            return "record"
        }

        if typeInfo as SoaRecordTypeInfo != null {
            return "soaRecord"
        }

        if typeInfo as InterfaceTypeInfo != null {
            return "interface"
        }

        if typeInfo as EnumTypeInfo != null {
            return "enum"
        }

        if typeInfo as AnonymousUnionTypeInfo != null {
            return "union"
        }

        if typeInfo as UnionTypeInfo != null {
            return "union"
        }

        if typeInfo as FunctionTypeInfo != null {
            return "function"
        }

        if typeInfo as GenericTypeInfo != null {
            return "generic"
        }

        if typeInfo as ArrayTypeInfo != null {
            return "array"
        }

        if typeInfo as NullableTypeInfo != null {
            return "nullable"
        }

        if typeInfo as ObliviousTypeInfo != null {
            return "oblivious"
        }

        reflectionType := typeInfo as ReflectionTypeInfo
        if reflectionType != null {
            if reflectionType.Type.get_IsEnum() {
                return "enum"
            }

            if reflectionType.Type.get_IsValueType() {
                return "struct"
            }

            return "class"
        }

        if typeInfo as ReflectionMethodInfo != null {
            return "method"
        }

        if typeInfo as ReflectionMethodGroupInfo != null {
            return "method"
        }

        if typeInfo as SimpleTypeInfo != null {
            return "primitive"
        }

        return "unknown"
    }

    // ── The modifier chips ───────────────────────────────────────────────

    // `Modifiers.HasFlag` does not emit; `VisibilityConventions` already answers this exact enum
    // with `Convert.ToInt32` and a mask, and that is the shape reused here. The ORDER of the eleven
    // tests is the printed order and is asserted as such.
    static func FormatModifiers(modifiers: object): string[]? {
        value := ModifierMask(modifiers)
        if value == 0 {
            return null
        }

        result := new List<string>()
        if HasModifier(value, 1) {
            result.Add("pub")
        }

        if HasModifier(value, 2) {
            result.Add("priv")
        }

        if HasModifier(value, 4) {
            result.Add("internal")
        }

        if HasModifier(value, 8) {
            result.Add("protected")
        }

        if HasModifier(value, 16) {
            result.Add("static")
        }

        if HasModifier(value, 32) {
            result.Add("virtual")
        }

        if HasModifier(value, 64) {
            result.Add("abstract")
        }

        if HasModifier(value, 128) {
            result.Add("sealed")
        }

        if HasModifier(value, 2048) {
            result.Add("async")
        }

        if HasModifier(value, 65536) {
            result.Add("override")
        }

        if HasModifier(value, 512) {
            result.Add("readonly")
        }

        if result.Count == 0 {
            return null
        }

        return result.ToArray()
    }

    static func ModifierMask(modifiers: object): int {
        if modifiers == null {
            return 0
        }

        return Convert.ToInt32(modifiers)
    }

    static func HasModifier(value: int, flag: int): bool {
        return (value & flag) == flag
    }

    // ── The names read off expressions ───────────────────────────────────

    static func ExtractCalleeName(callee: Expression): string? {
        identifier := callee as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := callee as MemberAccessExpression
        if memberAccess != null {
            return memberAccess.MemberName
        }

        return null
    }

    static func GetExpressionQueryName(expr: Expression?): string? {
        if expr == null {
            return null
        }

        identifier := expr as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := expr as MemberAccessExpression
        if memberAccess != null {
            return memberAccess.MemberName
        }

        call := expr as CallExpression
        if call != null {
            return GetExpressionQueryName(call.Callee)
        }

        newExpression := expr as NewExpression
        if newExpression != null {
            if newExpression.Type != null {
                return GetTypeReferenceName(newExpression.Type)
            }

            return null
        }

        withExpression := expr as WithExpression
        if withExpression != null {
            return GetExpressionQueryName(withExpression.Target)
        }

        awaitExpression := expr as AwaitExpression
        if awaitExpression != null {
            return GetExpressionQueryName(awaitExpression.Expression)
        }

        castExpression := expr as CastExpression
        if castExpression != null {
            return GetTypeReferenceName(castExpression.TargetType)
        }

        parenthesized := expr as ParenthesizedExpression
        if parenthesized != null {
            return GetExpressionQueryName(parenthesized.Inner)
        }

        return null
    }

    // ── The suggestion line ──────────────────────────────────────────────

    static func FormatSuggestions(suggestions: List<string>?): string? {
        if suggestions == null {
            return null
        }

        if suggestions.Count == 0 {
            return null
        }

        builder := new StringBuilder()
        index := 0
        while index < suggestions.Count {
            if index > 0 {
                builder.Append("; ")
            }

            builder.Append(suggestions[index])
            index = index + 1
        }

        return builder.ToString()
    }
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import NSharpLang.Compiler.Ast

// WHAT `[MethodImpl(...)]` MEANS, AND WHICH SPELLINGS OF IT THE CLR WILL REFUSE.
//
// `MethodImplAttribute` is a PSEUDO-CUSTOM attribute: it never becomes a custom-attribute row, and
// what it says goes into the method definition row's implementation flags instead. That has two
// consequences this owner exists to state.
//
// FIRST, THE ATTRIBUTE MEANS NOTHING ANYWHERE ELSE. Only a method-like declaration HAS an
// implementation-flags column, so `[MethodImpl]` on a type, a field or an enum has nowhere to go. A
// blob-backed attribute in the wrong place is merely unread metadata; this one is a statement the
// assembly cannot record at all.
//
// SECOND, SOME COMBINATIONS ARE REFUSED BY THE TYPE LOADER RATHER THAN BY THE COMPILER, and a
// refusal at load time is the worst place to learn about it: `Synchronized` on a value type's method
// throws `TypeLoadException: Synchronized Method in Value Type` the first time the type is touched,
// and `InternalCall` on a method that HAS a body throws `TypeLoadException: Internal call method
// '...' with non-zero RVA`. Both are decided entirely by what the source says, so both are said here.
//
// The defined-bit rule is the C# compiler's: a value with bits outside the `MethodImplOptions`
// members is refused rather than written through, because the bit the developer meant is not a bit
// the runtime has.
class MethodImplAttributeFacts {
    static func AttributeFullName(): string {
        return "System.Runtime.CompilerServices.MethodImplAttribute"
    }

    static func CodeTypeMemberName(): string {
        return "MethodCodeType"
    }

    static func IsMethodImplAttributeType(clrType: Type?): bool {
        if clrType == null {
            return false
        }

        resolved: Type = clrType
        return string.Equals(resolved.get_FullName(), AttributeFullName(), StringComparison.Ordinal)
    }

    // `MethodImplOptions` IS READ OFF THE ATTRIBUTE ITSELF rather than looked up by name: the
    // attribute's one-argument enum constructor takes exactly that type, so the reference set the
    // program actually compiles against decides what the enum is.
    static func TryGetOptionsType(attributeType: Type, out optionsType: Type): bool {
        optionsType = null
        for constructor in attributeType.GetConstructors() {
            parameters := constructor.GetParameters()
            if parameters.Length == 1 {
                candidate := parameters[0].get_ParameterType()
                if candidate.get_IsEnum() {
                    optionsType = candidate
                    return true
                }
            }
        }

        return false
    }

    // `MethodCodeType` is a public FIELD of the attribute, so the named argument's enum comes from
    // the field's own type.
    static func TryGetCodeTypeType(attributeType: Type, out codeTypeType: Type): bool {
        codeTypeType = null
        field := attributeType.GetField(CodeTypeMemberName(), BindingFlags.Public | BindingFlags.Instance)
        if field == null {
            return false
        }

        fieldType := field.get_FieldType()
        if !fieldType.get_IsEnum() {
            return false
        }

        codeTypeType = fieldType
        return true
    }

    // EVERY BIT THE ENUM ACTUALLY DEFINES, OR-ed together. Reading the members rather than writing a
    // constant keeps the rule correct on a runtime that adds an option.
    static func DefinedMask(enumType: Type): int {
        mask := 0
        for field in enumType.GetFields(BindingFlags.Public | BindingFlags.Static) {
            if field.get_IsLiteral() {
                mask = mask | Convert.ToInt32(field.GetRawConstantValue(), CultureInfo.InvariantCulture)
            }
        }

        return mask
    }

    static func TryGetMemberValue(enumType: Type, memberName: string, out value: int): bool {
        value = 0
        field := enumType.GetField(memberName, BindingFlags.Public | BindingFlags.Static)
        if field == null || !field.get_IsLiteral() {
            return false
        }

        value = Convert.ToInt32(field.GetRawConstantValue(), CultureInfo.InvariantCulture)
        return true
    }

    // THE CONSTANT AN ARGUMENT EXPRESSION DENOTES, over exactly the four shapes an enum-flags
    // argument has: a member of the enum, a `|` of two of them, a parenthesised one, and an integer
    // literal. Anything else has already been reported as a non-constant by the attribute walk, so
    // answering false here means "do not judge this one", never "this is wrong".
    static func TryEvaluate(expression: Expression, enumType: Type, out value: int): bool {
        value = 0
        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return TryEvaluate(parenthesized.Inner, enumType, out value)
        }

        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            parsed := 0
            if !Int32.TryParse(intLiteral.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed) {
                return false
            }

            value = parsed
            return true
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return TryGetMemberValue(enumType, memberAccess.MemberName, out value)
        }

        binary := expression as BinaryExpression
        if binary != null && binary.Operator == BinaryOperator.BitwiseOr {
            left := 0
            right := 0
            if !TryEvaluate(binary.Left, enumType, out left) || !TryEvaluate(binary.Right, enumType, out right) {
                return false
            }

            value = left | right
            return true
        }

        return false
    }

    // The bits of `value` the enum does not define, rendered as the hex the developer can compare
    // against a reference. Empty when every bit is defined.
    static func DescribeUndefinedBits(value: int, definedMask: int): string {
        // The bits `definedMask` does not cover. Subtracting the covered bits is the same answer as
        // masking with the complement, and says it without a negative intermediate.
        undefined := value - (value & definedMask)
        if undefined == 0 {
            return ""
        }

        return "0x" + undefined.ToString("X", CultureInfo.InvariantCulture)
    }

    // WHICH OPTION THE TYPE LOADER WILL REFUSE FOR THIS MEMBER, or null when it will accept them all.
    // `isValueType` is the ENCLOSING type's kind and `hasBody` is whether the member carries IL of its
    // own; both are decided by the source, which is why the refusal can be stated at compile time.
    static func DescribeClrRefusal(value: int, enumType: Type, isValueType: bool, hasBody: bool): string? {
        synchronized := 0
        if isValueType && TryGetMemberValue(enumType, "Synchronized", out synchronized) && synchronized != 0 && (value & synchronized) == synchronized {
            return "Synchronized"
        }

        internalCall := 0
        if hasBody && TryGetMemberValue(enumType, "InternalCall", out internalCall) && internalCall != 0 && (value & internalCall) == internalCall {
            return "InternalCall"
        }

        unmanaged := 0
        if hasBody && TryGetMemberValue(enumType, "Unmanaged", out unmanaged) && unmanaged != 0 && (value & unmanaged) == unmanaged {
            return "Unmanaged"
        }

        return null
    }

    static func DescribeRefusalReason(option: string): string {
        if option == "Synchronized" {
            return "the CLR takes a monitor on the instance, and a value type has no identity to lock, so the type loader refuses the whole type with 'Synchronized Method in Value Type'"
        }

        if option == "InternalCall" {
            return "the CLR expects the body to live inside the runtime, so a member that has IL of its own is refused with 'Internal call method ... with non-zero RVA'"
        }

        return "the CLR expects the body to live outside this assembly, so a member that has IL of its own cannot carry it"
    }

    static func DescribeRefusalRepair(option: string): string {
        if option == "Synchronized" {
            return "Lock explicitly inside the member, or move it to a class."
        }

        return "Remove the option, or declare the member without a body."
    }
}

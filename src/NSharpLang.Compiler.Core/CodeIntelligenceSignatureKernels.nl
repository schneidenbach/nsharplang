namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Reflection
import System.Text
import NSharpLang.Compiler


// THE ONE LINE A HOVER PRINTS, AND THE TWO WAYS IT IS BUILT.
//
// A symbol the PROJECT declares is named by its kind and its type and nothing else — `field Count:
// int` — because the declaration itself is one click away and the hover's job is to save that click,
// not to restate the file. A symbol METADATA declares has no file to jump to, so the hover is the
// only place its shape is ever shown, and it carries the whole signature: the return type, the
// parameters with their names and their nullability, and the type that declares it.
//
// THAT SECOND HALF IS WHAT IDE DEFECT D2 WAS. It was deleted from the language server on 2026-06-24
// ("Delete hover reflection member fallback") together with its tests, and the CLI never had it at
// all, so both surfaces had been rendering the ANALYZER'S INTERNAL PLACEHOLDER — `ToUpper(...)`, the
// text a method group carries so a diagnostic can name it — as though it were a signature. The
// rendering below is the deleted one, restored in the owner both surfaces share.
//
// EVERY REFLECTED READ IS INSIDE A `try`, AND THE DECLINE IS THE POINT. These members arrive from
// two different type universes — a `MetadataLoadContext` on the CLI, the live runtime in the
// language server — and they do not fail the same way. A hover that throws is a broken editor, so a
// member this file cannot read answers null and the caller falls back to the bare rendering, which
// is always available because it is a function of text alone.
class CodeIntelligenceSignatureKernels {
    static func GetFallbackSignatureText(kind: string, name: string, typeName: string?): string {
        if typeName != null {
            return kind + " " + name + ": " + typeName
        }

        return kind + " " + name
    }

    // The whole line for a reflected member, or null to decline to the fallback above.
    static func GetReflectedMemberLineText(handle: ReflectedMemberHandle): string? {
        signature := GetReflectedMemberSignatureText(handle)
        if signature == null {
            return null
        }

        return GetReflectedMemberKind(handle) + " " + handle.Name + ": " + (signature ?? "")
    }

    // WHICH WORD THE HOVER LEADS WITH. The reflected sorts are three, and `member` is the honest
    // answer for a handle carrying none rather than a guess that reads like a fact.
    static func GetReflectedMemberKind(handle: ReflectedMemberHandle): string {
        if handle.Property != null {
            return "property"
        }

        if handle.Field != null {
            return "field"
        }

        if handle.Method != null {
            return "method"
        }

        return "member"
    }

    static func GetReflectedMemberSignatureText(handle: ReflectedMemberHandle): string? {
        typeOverride := handle.TypeOverride
        try {
            method := handle.Method
            if method != null {
                return GetReflectedMethodText(method, typeOverride) + GetOverloadSuffixText(handle.OverloadCount)
            }

            property := handle.Property
            if property != null {
                return GetReflectedPropertyText(property, typeOverride)
            }

            field := handle.Field
            if field != null {
                return GetReflectedFieldText(field, typeOverride)
            }
        } catch {
            return null
        }

        return null
    }

    // ONE SIGNATURE IS SHOWN AND THE REST ARE COUNTED. Printing five signatures makes the hover a
    // wall the reader has to parse; printing one without saying there are others makes it a claim
    // that is false. The count is free — the resolver already had the list in its hand.
    static func GetOverloadSuffixText(overloadCount: int): string {
        if overloadCount < 2 {
            return ""
        }

        others := overloadCount - 1
        if others == 1 {
            return " (+1 overload)"
        }

        return " (+" + others.ToString() + " overloads)"
    }

    // `string ToUpper()`, `DateTime AddDays(double value)` — the C# spelling, because that is what
    // the metadata says and inventing an N# transliteration would be inventing a fact. The return
    // type and each parameter go through `NullabilityMetadataReflection`, which is the same owner
    // the analyzer's own diagnostics use, so the nullability annotations agree with the errors.
    static func GetReflectedMethodText(method: MethodInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        builder := new StringBuilder()
        builder.Append(NullabilityMetadataReflection.FormatReturnTypeWithOverride(method, typeOverride))
        builder.Append(" ")
        builder.Append(method.get_Name())
        builder.Append("(")

        parameters := method.GetParameters()
        index := 0
        while index < parameters.Length {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(NullabilityMetadataReflection.FormatParameterWithOverride(parameters[index], typeOverride))
            index = index + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    // The accessors are the property's whole remaining shape, and a write-only property is a real
    // thing, so all three combinations are spelled rather than assuming `get`.
    static func GetReflectedPropertyText(property: PropertyInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        accessors := ""
        if property.get_CanRead() && property.get_CanWrite() {
            accessors = " { get; set; }"
        } else if property.get_CanRead() {
            accessors = " { get; }"
        } else if property.get_CanWrite() {
            accessors = " { set; }"
        }

        return NullabilityMetadataReflection.FormatTypeInfo(NullabilityMetadataReflection.ConvertPropertyWithOverride(property, typeOverride)) + accessors
    }

    static func GetReflectedFieldText(field: FieldInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        modifiers := ""
        if field.get_IsStatic() {
            modifiers = "static "
        }

        if field.get_IsInitOnly() {
            modifiers = modifiers + "readonly "
        }

        return modifiers + NullabilityMetadataReflection.FormatTypeInfo(NullabilityMetadataReflection.ConvertFieldWithOverride(field, typeOverride))
    }
}

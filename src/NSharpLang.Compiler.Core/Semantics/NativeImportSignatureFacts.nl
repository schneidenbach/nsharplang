namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT A `[LibraryImport]` SIGNATURE MAY SPELL, AND WHY THE ANSWER IS NARROWER THAN THE LANGUAGE'S.
//
// A native import is not a method the compiler emits a body for. It is a P/Invoke stub, and the CLR's
// INTEROP MARSHALLER — not the emitter, not the analyzer — decides at the first CALL whether the
// signature it was handed can be marshalled at all. When it cannot, the marshaller raises
// `System.Runtime.InteropServices.MarshalDirectiveException` and the process aborts, at the call
// site, before the native library is even looked for. Nothing in a build says a word about it.
//
// THE ONE SHAPE THAT IS CERTAIN, AND IT IS THE ONE THIS OWNER STATES: a GENERIC type can never appear
// in a P/Invoke signature. `Span<T>` and `ReadOnlySpan<T>` are the cases a systems author reaches for
// first and they fail exactly like every other generic — a blittable element does NOT rescue them,
// because the refusal is about the type's GENERICITY and not about its contents. `[LibraryImport]` in
// C# survives spans only because a SOURCE GENERATOR rewrites the declaration into a pinning wrapper
// around a pointer-taking stub; N# emits the P/Invoke directly, so there is no wrapper and no pinning.
// A tuple is the same refusal wearing different syntax: `(int, int)` IS `ValueTuple<int, int>` in
// metadata.
//
// WHAT IS DELIBERATELY NOT STATED. Nullability (`int?` is `Nullable<int>` and would fail; `string?` is
// `string` and would not) cannot be told apart from the written type reference alone, and a rule that
// guessed would refuse marshalable code. This owner answers only what the SPELLING settles, and the
// two families it names are settled: neither a generic name nor a tuple can be anything but generic in
// metadata.
class NativeImportSignatureFacts {

    // `[LibraryImport]`, `[LibraryImportAttribute]` and the fully-qualified spellings are one
    // attribute, exactly as everywhere else in the analyzer. `DllImport` is admitted by the same
    // door: it is the same P/Invoke stub with an older spelling and the same marshaller.
    static func IsNativeImportAttribute(attribute: AttributeNode): bool {
        name := attribute.Name
        lastDot := name.LastIndexOf('.')
        if lastDot >= 0 {
            name = name.Substring(lastDot + 1)
        }

        if name.EndsWith("Attribute", StringComparison.Ordinal) {
            name = name.Substring(0, name.Length - 9)
        }

        return name == "LibraryImport" || name == "DllImport"
    }

    static func HasNativeImportAttribute(attributes: List<AttributeNode>?): bool {
        if attributes == null {
            return false
        }

        for attribute in attributes {
            if IsNativeImportAttribute(attribute) {
                return true
            }
        }

        return false
    }

    static func IsMarshalableType(typeRef: TypeReference?): bool {
        return DescribeRefusal(typeRef) == null
    }

    // The clause that names WHAT the marshaller refuses about this written type, or null when the
    // spelling settles nothing against it. A `void` return (a null reference) is marshalable.
    static func DescribeRefusal(typeRef: TypeReference?): string? {
        if typeRef == null {
            return null
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            return "'" + TypeReferenceFacts.GetDisplayName(typeRef) + "' is a generic type, and the CLR's interop marshaller refuses generic types in a native-import signature"
        }

        tuple := typeRef as TupleTypeReference
        if tuple != null {
            return "'" + TypeReferenceFacts.GetDisplayName(typeRef) + "' is a tuple, which is the generic type 'ValueTuple' in metadata, and the CLR's interop marshaller refuses generic types in a native-import signature"
        }

        return null
    }

    // The repair, and it is written for the type the author actually wrote. A span's repair is its
    // own element array, which marshals as a pinned pointer with no wrapper; everything else is told
    // the family of types the marshaller does accept.
    static func DescribeRepair(typeRef: TypeReference): string {
        generic := typeRef as GenericTypeReference
        if generic != null && generic.TypeArguments.Count == 1 {
            if generic.Name == "Span" || generic.Name == "ReadOnlySpan" {
                elementName := TypeReferenceFacts.GetDisplayName(generic.TypeArguments[0])
                return "Declare it as '" + elementName + "[]' — an array marshals as a pinned pointer. Spans are not marshalled on this emit path: N# emits the P/Invoke directly, with no source-generated pinning wrapper."
            }
        }

        return "Use a non-generic type the marshaller accepts — a primitive, an enum, a struct of blittable fields, an array of those, 'string', or 'nint' for a raw pointer."
    }
}

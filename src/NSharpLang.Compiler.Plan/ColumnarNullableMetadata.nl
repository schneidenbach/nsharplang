namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// REFERENCE-TYPE NULLABILITY, FLATTENED THE WAY `NullableAttribute` SPELLS IT.
//
// Reference-type nullability is NOT in a CLR type. `Dictionary<string, object?>` and
// `Dictionary<string, object>` are the same `Dictionary`2[String, Object]` in metadata, and the
// difference between them lives in a
// `System.Runtime.CompilerServices.NullableAttribute` attached to the POSITION that mentions the
// type -- a return parameter, a parameter, a field, a property. Without it, an N# assembly's public
// surface reads back as OBLIVIOUS, which the analyzer resolves to `!` at every depth: an N# caller
// in another assembly could not pass a `Dictionary<string, object?>` to a parameter whose own source
// declares exactly that, because the metadata no longer said so. Every .NET language that wants its
// annotations to survive the assembly boundary writes this attribute, so N# writes it too, in the
// byte shape the C# compiler writes.
//
// THE FLAG ORDER IS A PRE-ORDER WALK OF THE WRITTEN TYPE, and each node contributes ONE byte:
// 0 oblivious, 1 not annotated, 2 annotated. `Dictionary<string, object?>` is `[1, 1, 2]` -- the
// dictionary itself, then its key, then its value -- and `Dictionary<string, object?>?` is
// `[2, 1, 2]`. An array is a node of its own before its element (`string[]?` is `[2, 1]` and
// `string?[]` is `[1, 2]`), and a type parameter is a node like any other (`T?` is `[2]`).
//
// A VALUE-TYPE NODE IS ALWAYS 0, AND A VALUE TYPE WITH NO TYPE ARGUMENTS CONTRIBUTES NO BYTE AT
// ALL. That asymmetry is not a shortcut, it is what the C# compiler emits and what
// `NullabilityInfoContext` reads back: measured against `csc` output,
// `KeyValuePair<string, object?>` is `[0, 1, 2]` (the struct, its key, its value) while
// `List<int>` is `[1]` and `int?` is `[0]` -- the `int` leaf occupies no slot in either. A reader
// short-circuits on a value type before consuming a byte, so a leaf byte would desynchronise every
// flag after it.
//
// NOTHING ANNOTATABLE MEANS NO ATTRIBUTE. A flag list that is empty or all zeroes describes a
// position that cannot carry reference nullability at all (`int`, `(int, int)?`), and C# writes no
// attribute for one; so does this.
//
// A SHAPE THIS OWNER CANNOT ALIGN DECLINES RATHER THAN GUESSES. The walk reads the CLR type and the
// type AS WRITTEN in lockstep -- the CLR type decides what is a value type and how many arguments
// there are, the written text decides which positions carry a `?` -- and a position whose two halves
// do not line up (an async method's `Task<T>` signature against its written `T`, a tuple long enough
// to nest a `TRest`, a nested generic whose outer arguments the written spelling does not repeat)
// answers "no flags". That position stays oblivious, which is exactly what it was before this owner
// existed; a guess would state something the source never wrote.
class ColumnarNullableMetadata {

    // The three byte values `NullableAttribute` is defined over (Roslyn's own names for them).
    static Oblivious: int => 0
    static NotAnnotated: int => 1
    static Annotated: int => 2

    // How deep the walk follows a written type before giving up. A written type this deep is not a
    // real signature; the bound keeps a malformed canonical from recursing without end.
    static MaxDepth: int => 24

    // The flags for one signature position, or null when the position carries nothing worth saying
    // -- which is both "this is an `int`" and "these two halves did not line up".
    static func TryFlags(clrType: Type?, labeledCanonical: string?): int[]? {
        if clrType == null || labeledCanonical == null || labeledCanonical.Length == 0 {
            return null
        }

        collected := new List<int>()
        if !TryCollect(clrType, labeledCanonical, collected, 0) {
            return null
        }

        if !HasAnnotatableFlag(collected) {
            return null
        }

        return collected.ToArray()
    }

    // True when at least one node said something other than "oblivious". C# omits the attribute
    // entirely otherwise, and so does this owner.
    static func HasAnnotatableFlag(flags: List<int>): bool {
        for flag in flags {
            if flag != ColumnarNullableMetadata.Oblivious {
                return true
            }
        }

        return false
    }

    // True when every flag is the same value, which is the cue for `NullableAttribute(byte)` rather
    // than `NullableAttribute(byte[])`.
    static func IsUniform(flags: int[]): bool {
        index := 1
        while index < flags.Length {
            if flags[index] != flags[0] {
                return false
            }

            index = index + 1
        }

        return flags.Length > 0
    }

    static func TryCollect(clrType: Type, written: string, flags: List<int>, depth: int): bool {
        if depth > ColumnarNullableMetadata.MaxDepth {
            return false
        }

        text := written
        if text == null || text.Length == 0 {
            return false
        }

        // A union's arms are not positions of the emitted type, so there is nothing to align them
        // against; the same reason the tuple-name walk does not descend into one.
        if ColumnarTupleElementNames.HasTopLevelUnionBar(text) {
            return false
        }

        // A `ref`/`out` position's CLR type is `T&` and its written spelling is the bare `T` (the
        // modifier travels in its own column), but a written `&T` is accepted for the callers that
        // carry it. Nullability describes the referent either way.
        effective := clrType
        if effective.IsByRef {
            byRefElement := effective.GetElementType()
            if byRefElement == null {
                return false
            }

            effective = byRefElement
        }

        if text.Length > 1 && text[0] == '&' {
            text = text.Substring(1)
        }

        annotated := false
        if text.Length > 1 && text[text.Length - 1] == '?' {
            annotated = true
            text = text.Substring(0, text.Length - 1)
        }

        if text.Length == 0 {
            return false
        }

        if effective.IsGenericParameter {
            flags.Add(AnnotationFlag(annotated))
            return true
        }

        if effective.IsArray {
            arrayElementType := effective.GetElementType()
            arrayElementText := ColumnarTupleElementNames.ArrayElementText(text)
            if arrayElementType == null || arrayElementText == null {
                return false
            }

            flags.Add(AnnotationFlag(annotated))
            return TryCollect(arrayElementType, arrayElementText, flags, depth + 1)
        }

        isValueType := effective.IsValueType
        if !effective.IsGenericType {
            // A value-type leaf occupies no slot; a reference leaf is one byte.
            if isValueType {
                return true
            }

            flags.Add(AnnotationFlag(annotated))
            return true
        }

        arguments := effective.GetGenericArguments()

        // `int?` IS `Nullable<int>` IN METADATA AND `int?` IN SOURCE, so the `?` that was just
        // stripped IS the shell rather than an annotation, and the underlying type is the whole
        // remaining text rather than a written type argument. A source that spells `Nullable<int>`
        // out reaches the same place with a real argument list, so both spellings are read.
        if IsNullableValueTypeShape(effective) {
            if arguments.Length != 1 {
                return false
            }

            underlyingText := text
            spelledArguments := ColumnarTupleElementNames.TopLevelGenericArguments(text)
            if spelledArguments != null && spelledArguments.Count == 1 {
                underlyingText = spelledArguments[0]
            }

            flags.Add(ColumnarNullableMetadata.Oblivious)
            return TryCollect(arguments[0], underlyingText, flags, depth + 1)
        }

        writtenArguments := TryWrittenArguments(text, arguments.Length)
        if writtenArguments == null {
            return false
        }

        if isValueType {
            flags.Add(ColumnarNullableMetadata.Oblivious)
        } else {
            flags.Add(AnnotationFlag(annotated))
        }

        index := 0
        while index < arguments.Length {
            if !TryCollect(arguments[index], writtenArguments[index], flags, depth + 1) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func AnnotationFlag(annotated: bool): int {
        if annotated {
            return ColumnarNullableMetadata.Annotated
        }

        return ColumnarNullableMetadata.NotAnnotated
    }

    // THE WRITTEN TYPE ARGUMENTS OF A CONSTRUCTED GENERIC, in the CLR's own argument order, or null
    // when the written spelling does not offer exactly that many. A named tuple is written
    // `(Min:int,Max:int)` and constructed as `ValueTuple<int,int>`, so its elements are its
    // arguments with the labels removed; everything else is the ordinary `Name<A,B>` split. A count
    // that disagrees is a shape the walk cannot align -- a tuple whose eighth element nests a
    // `TRest`, or a nested generic whose spelling does not repeat the outer arguments -- and it
    // declines rather than pairing positions by guess.
    static func TryWrittenArguments(text: string, expected: int): List<string>? {
        if text.Length >= 2 && text[0] == '(' && text[text.Length - 1] == ')' {
            elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(text.Substring(1, text.Length - 2))
            if elements.Count != expected {
                return null
            }

            stripped := new List<string>()
            for element in elements {
                stripped.Add(ColumnarTupleElementNames.ElementTypeText(element))
            }

            return stripped
        }

        arguments := ColumnarTupleElementNames.TopLevelGenericArguments(text)
        if arguments == null || arguments.Count != expected {
            return null
        }

        return arguments
    }

    // `Nullable`1`, asked by NAME. `Nullable.GetUnderlyingType` is `typeof(Nullable<>)`-based and the
    // emitter's types are builders and reference-universe types rather than this process's own, so
    // the identity comparison answers false for exactly the constructed shells this walk must
    // recognise. The name is the same in every universe.
    static func IsNullableValueTypeShape(clrType: Type): bool {
        if !clrType.IsValueType {
            return false
        }

        return string.Equals(clrType.Name, "Nullable`1", StringComparison.Ordinal) && string.Equals(clrType.Namespace, "System", StringComparison.Ordinal)
    }
}

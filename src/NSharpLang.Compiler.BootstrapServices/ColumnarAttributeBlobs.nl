namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// CUSTOM-ATTRIBUTE BLOBS, WRITTEN DIRECTLY (ECMA-335 II.23.3), BECAUSE THE BUILDER CANNOT BE
// CONSTRUCTED UNDER NativeAOT. `new CustomAttributeBuilder(ctor, args)` throws
// `PlatformNotSupportedException: Dynamic code generation is not supported on this platform.` in the
// BUILDER'S CONSTRUCTOR, in both type universes and for every argument shape, so an AOT `nlc` would
// silently lose the ref-struct and readonly-struct attributes and every emitted test attribute. The
// substitute the emit host uses instead is `SetCustomAttribute(ConstructorInfo, byte[])`, which needs
// the blob spelled here.
//
// The blob is: the two-byte PROLOG 0x0001, then each FIXED argument in constructor-parameter order,
// then a two-byte little-endian NAMED-argument count. The emit host writes only two shapes -- an
// attribute with no arguments, and one with two string arguments -- and both are pinned byte-for-byte
// against what `CustomAttributeBuilder` produced, so the conversion moves no emitted byte.
class ColumnarAttributeBlobs {
    static func DescriptionTraitKey(): string {
        return "NSharpDescription"
    }

    // The temporary Reflection.Emit executor applies planned rows whose data does not depend on
    // builders. Binding constructors stays with the current host until S2.2; no selection or
    // attachment-order policy stays there. An empty sequence performs no attachment.
    static func ApplyToType(target: TypeBuilder, attributeConstructor: ConstructorInfo, blobs: byte[][]) {
        index := 0
        while index < blobs.Length {
            target.SetCustomAttribute(attributeConstructor, blobs[index])
            index = index + 1
        }
    }

    // Generated rows have one blob for each valid constructor slot. Like the other declaration
    // columns, both arrays are read-only after planning; this executor does not accept source data.
    static func ApplyToTestMethod(target: MethodBuilder, traitConstructor: ConstructorInfo, factConstructor: ConstructorInfo, constructorSlots: int[], blobs: byte[][]) {
        index := 0
        while index < constructorSlots.Length {
            target.SetCustomAttribute(TestConstructorForSlot(constructorSlots[index], traitConstructor, factConstructor), blobs[index])
            index = index + 1
        }
    }

    static func TestConstructorForSlot(slot: int, traitConstructor: ConstructorInfo, factConstructor: ConstructorInfo): ConstructorInfo {
        if slot == 0 {
            return traitConstructor
        }
        if slot == 1 {
            return factConstructor
        }
        throw new InvalidOperationException("Unknown custom test attribute constructor slot.")
    }

    // `[IsByRefLike]`, `[IsReadOnly]`, `[Fact]`: prolog, no fixed arguments, no named arguments.
    static func NoArgument(): byte[] {
        blob := new List<byte>()
        WritePrologue(blob)
        WriteNamedArgumentCount(blob, 0)
        return blob.ToArray()
    }

    // `[Trait("NSharpDescription", <description>)]`: prolog, two SerString fixed arguments, no named
    // arguments. A null argument is legal and writes the single-byte null form.
    static func TwoStrings(first: string, second: string): byte[] {
        blob := new List<byte>()
        WritePrologue(blob)
        WriteSerString(blob, first)
        WriteSerString(blob, second)
        WriteNamedArgumentCount(blob, 0)
        return blob.ToArray()
    }

    static func WritePrologue(blob: List<byte>) {
        Append(blob, 1)
        Append(blob, 0)
    }

    // NumNamed is a plain UInt16, little-endian -- not a compressed integer.
    static func WriteNamedArgumentCount(blob: List<byte>, count: int) {
        low := count % 256
        high := count / 256
        Append(blob, low)
        Append(blob, high)
    }

    // SerString (II.23.3): a NULL string is the single byte 0xFF, an empty string is a zero length,
    // and anything else is a PackedLen count of UTF-8 BYTES followed by those bytes. The count is the
    // byte count, never the character count -- which is why the UTF-8 encoding happens first.
    static func WriteSerString(blob: List<byte>, value: string) {
        if value == null {
            Append(blob, 255)
            return
        }

        bytes := Utf8Bytes(value)
        WriteCompressedUInt32(blob, bytes.Count)
        index := 0
        while index < bytes.Count {
            blob.Add(bytes[index])
            index = index + 1
        }
    }

    // PackedLen (II.23.2), all three branches: one byte below 0x80, two bytes below 0x4000 with the
    // high bits 10, four bytes below 0x20000000 with the high bits 110. A test description long enough
    // to reach the two-byte branch is ordinary, so the branch is not theoretical.
    static func WriteCompressedUInt32(blob: List<byte>, value: int) {
        if value <= 127 {
            Append(blob, value)
            return
        }

        if value <= 16383 {
            Append(blob, 128 + (value / 256))
            Append(blob, value % 256)
            return
        }

        Append(blob, 192 + (value / 16777216))
        Append(blob, (value / 65536) % 256)
        Append(blob, (value / 256) % 256)
        Append(blob, value % 256)
    }

    // UTF-8 from the string's UTF-16 code units. A surrogate PAIR is one code point and encodes as four
    // bytes; an unpaired surrogate keeps the three-byte form the code unit alone describes, which is
    // what the framework encoder's replacement-free path would also have to decide. The masks are
    // written as `/` and `%` rather than shifts because the UTF-8 lead-byte patterns never overlap the
    // payload bits, so addition and bit-or agree exactly.
    static func Utf8Bytes(value: string): List<byte> {
        bytes := new List<byte>()
        index := 0
        while index < value.Length {
            unit := value[index]
            code := Convert.ToInt32(unit)
            if code >= 55296 && code <= 56319 {
                nextIndex := index + 1
                if nextIndex < value.Length {
                    lowUnit := value[nextIndex]
                    low := Convert.ToInt32(lowUnit)
                    if low >= 56320 && low <= 57343 {
                        code = 65536 + ((code - 55296) * 1024) + (low - 56320)
                        index = nextIndex
                    }
                }
            }

            AppendCodePoint(bytes, code)
            index = index + 1
        }

        return bytes
    }

    static func AppendCodePoint(bytes: List<byte>, code: int) {
        if code < 128 {
            Append(bytes, code)
            return
        }

        if code < 2048 {
            Append(bytes, 192 + (code / 64))
            Append(bytes, 128 + (code % 64))
            return
        }

        if code < 65536 {
            Append(bytes, 224 + (code / 4096))
            Append(bytes, 128 + ((code / 64) % 64))
            Append(bytes, 128 + (code % 64))
            return
        }

        Append(bytes, 240 + (code / 262144))
        Append(bytes, 128 + ((code / 4096) % 64))
        Append(bytes, 128 + ((code / 64) % 64))
        Append(bytes, 128 + (code % 64))
    }

    static func Append(bytes: List<byte>, value: int) {
        bytes.Add(Convert.ToByte(value))
    }
}

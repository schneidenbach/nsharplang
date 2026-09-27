namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

// THE EXPECTED FLAG LISTS ARE NOT DERIVED HERE. Each one was read out of an assembly the C# compiler
// produced for the SAME written type with `<Nullable>enable</Nullable>`, through
// `CustomAttributeData` on the emitted position, and is pinned so the N# walk cannot drift away from
// the encoding every other reader expects.
func NullableFlagText(flags: int[]?): string {
    if flags == null {
        return "<none>"
    }

    text := ""
    index := 0
    while index < flags.Length {
        if index > 0 {
            text = text + ","
        }

        text = text + flags[index].ToString()
        index = index + 1
    }

    return text
}

func NullableBlobText(blob: byte[]): string {
    text := ""
    index := 0
    while index < blob.Length {
        if index > 0 {
            text = text + "-"
        }

        text = text + Convert.ToInt32(blob[index]).ToString()
        index = index + 1
    }

    return text
}

func NullableFlagsFor(clrType: Type, written: string): string {
    return NullableFlagText(ColumnarNullableMetadata.TryFlags(clrType, written))
}

test "a plain reference position is one flag, annotated or not" {
    assert NullableFlagsFor(typeof(string), "string") == "1"
    assert NullableFlagsFor(typeof(string), "string?") == "2"
}

test "a value-type position carries no attribute at all" {
    assert NullableFlagsFor(typeof(int), "int") == "<none>"
    assert NullableFlagsFor(typeof(int?), "int?") == "<none>"
    assert NullableFlagsFor(typeof(DateTime), "DateTime") == "<none>"
}

test "a constructed generic contributes its own flag and then its arguments' in order" {
    assert NullableFlagsFor(typeof(Dictionary<string, object>), "Dictionary<string,object?>") == "1,1,2"
    assert NullableFlagsFor(typeof(Dictionary<string, object>), "Dictionary<string,object?>?") == "2,1,2"
    assert NullableFlagsFor(typeof(Dictionary<string, object>), "Dictionary<string,object>") == "1,1,1"
}

// `List<int>` is `[1]` and NOT `[1, 0]`: a reader short-circuits on a value type before it consumes
// a byte, so a byte for the `int` leaf would desynchronise every flag after it.
test "a value-type leaf occupies no slot inside a generic argument list" {
    assert NullableFlagsFor(typeof(List<int>), "List<int>") == "1"
    assert NullableFlagsFor(typeof(List<int>), "List<int>?") == "2"
    assert NullableFlagsFor(typeof(Dictionary<int, string>), "Dictionary<int,string?>") == "1,2"
}

// A GENERIC value type still contributes its own zero, which is the asymmetry `csc` emits:
// `KeyValuePair<string, object?>` is `[0, 1, 2]` while `int?` is `[0]` alone.
test "a generic value type contributes an oblivious flag and then its arguments" {
    assert NullableFlagsFor(typeof(KeyValuePair<string, object>), "KeyValuePair<string,object?>") == "0,1,2"
    assert NullableFlagsFor(typeof(KeyValuePair<int, int>), "KeyValuePair<int,int>") == "<none>"
    assert NullableFlagsFor(typeof(List<KeyValuePair<string, object>>), "List<KeyValuePair<string,object?>>") == "1,0,1,2"
}

test "an array is a node in front of its element" {
    assert NullableFlagsFor(typeof(string[]), "string[]?") == "2,1"
    assert NullableFlagsFor(typeof(string[]), "string?[]") == "1,2"
    assert NullableFlagsFor(typeof(int[]), "int[]?") == "2"
    assert NullableFlagsFor(typeof(List<int[]>), "List<int[]>?") == "2,1"
}

// A named tuple's ELEMENTS are its `ValueTuple` type arguments, and the labels the written spelling
// carries are not part of the alignment.
test "a named tuple aligns its elements with the value tuple's arguments" {
    assert NullableFlagsFor(typeof(ValueTuple<int, string>), "(Min:int,Max:string?)") == "0,2"
    assert NullableFlagsFor(typeof(ValueTuple<string, int>), "(Min:string?,Max:int)") == "0,2"
    assert NullableFlagsFor(typeof(ValueTuple<int, int>), "(Min:int,Max:int)") == "<none>"
    assert NullableFlagsFor(typeof(List<ValueTuple<int, string>>), "List<(X:int,Y:string?)>") == "1,0,2"
}

test "a nullable value type is the shell's zero followed by its underlying type" {
    assert NullableFlagsFor(typeof(int?), "int?") == "<none>"
    assert NullableFlagsFor(typeof(KeyValuePair<string, object>?), "KeyValuePair<string,object?>?") == "0,0,1,2"
}

// A position whose two halves do not line up says nothing rather than guessing. An `async` method's
// signature return is `Task<T>` while its written return is the bare `T`, which is exactly this
// shape; the position stays oblivious, as it was before these flags existed.
test "a written type that cannot be aligned with the clr type declines" {
    assert NullableFlagsFor(typeof(System.Threading.Tasks.Task<string>), "string?") == "<none>"
    assert NullableFlagsFor(typeof(Dictionary<string, object>), "Dictionary<string>") == "<none>"
    assert NullableFlagsFor(typeof(string), "A|B") == "<none>"
    assert ColumnarNullableMetadata.TryFlags(typeof(string), null) == null
    assert ColumnarNullableMetadata.TryFlags(null, "string?") == null
}

test "the uniform test picks the single-byte constructor only for a list that says one thing" {
    assert ColumnarNullableMetadata.IsUniform([2])
    assert ColumnarNullableMetadata.IsUniform([1, 1, 1])
    assert !ColumnarNullableMetadata.IsUniform([1, 1, 2])
    assert !ColumnarNullableMetadata.IsUniform(new int[](0))
}

// The blob bytes are the ones `CustomAttributeBuilder` writes for the same arguments: the 0x0001
// prologue, the fixed argument, and the two-byte named-argument count.
test "the nullable attribute blobs are the prologue, the argument and an empty named count" {
    assert NullableBlobText(ColumnarAttributeBlobs.OneByte(2)) == "1-0-2-0-0"
    assert NullableBlobText(ColumnarAttributeBlobs.ByteArray([1, 1, 2])) == "1-0-3-0-0-0-1-1-2-0-0"
}

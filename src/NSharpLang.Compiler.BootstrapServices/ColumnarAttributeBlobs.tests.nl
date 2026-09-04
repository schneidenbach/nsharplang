namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// The expected blobs are not derived here -- they are the bytes `CustomAttributeBuilder` itself wrote,
// read back out of the `#Blob` heap of an assembly built both ways in one process and compared
// (`BLOB_COUNT builder=4 raw=4`, `BLOBS_IDENTICAL=True`). Pinning them keeps the conversion honest.
func BlobText(blob: byte[]): string {
    text := ""
    index := 0
    while index < blob.Length {
        value := Convert.ToInt32(blob[index])
        if index > 0 {
            text = text + "-"
        }

        text = text + value.ToString()
        index = index + 1
    }

    return text
}

func RepeatedText(unit: string, count: int): string {
    text := ""
    index := 0
    while index < count {
        text = text + unit
        index = index + 1
    }

    return text
}

test "the custom attribute executor selects only declared constructor slots" {
    firstOwner := typeof(object)
    secondOwner := typeof(InvalidOperationException)
    parameterTypes := new Type[](0)
    first := firstOwner.GetConstructor(parameterTypes)
    second := secondOwner.GetConstructor(parameterTypes)
    assert first != null
    assert second != null
    assert Object.ReferenceEquals(ColumnarAttributeBlobs.TestConstructorForSlot(0, first, second), first)
    assert Object.ReferenceEquals(ColumnarAttributeBlobs.TestConstructorForSlot(1, first, second), second)
    assert throws InvalidOperationException {
        ColumnarAttributeBlobs.TestConstructorForSlot(-1, first, second)
    }
    assert throws InvalidOperationException {
        ColumnarAttributeBlobs.TestConstructorForSlot(2, first, second)
    }
}

test "a no-argument attribute blob is the prologue and a zero named count" {
    blob := ColumnarAttributeBlobs.NoArgument()
    assert blob.Length == 4
    assert BlobText(blob) == "1-0-0-0"
}

test "two string arguments write a length-prefixed UTF-8 run each" {
    blob := ColumnarAttributeBlobs.TwoStrings("ab", "c")
    assert BlobText(blob) == "1-0-2-97-98-1-99-0-0"
}

test "the xunit Trait shape matches the bytes CustomAttributeBuilder wrote" {
    assert ColumnarAttributeBlobs.DescriptionTraitKey() == "NSharpDescription"
    blob := ColumnarAttributeBlobs.TwoStrings(ColumnarAttributeBlobs.DescriptionTraitKey(), "a description")
    assert BlobText(blob) == "1-0-17-78-83-104-97-114-112-68-101-115-99-114-105-112-116-105-111-110-13-97-32-100-101-115-99-114-105-112-116-105-111-110-0-0"
}

test "a non-ASCII description is counted in BYTES, not characters" {
    blob := ColumnarAttributeBlobs.TwoStrings("e", "é")
    assert BlobText(blob) == "1-0-1-101-2-195-169-0-0"
}

test "an empty argument writes a zero length and a null argument writes 0xFF" {
    empty := ColumnarAttributeBlobs.TwoStrings("", "")
    assert BlobText(empty) == "1-0-0-0-0-0"
    nulls := ColumnarAttributeBlobs.TwoStrings(null, null)
    assert BlobText(nulls) == "1-0-255-255-0-0"
}

test "a description of 128 bytes or more takes the two-byte PackedLen branch" {
    long := RepeatedText("a", 128)
    blob := ColumnarAttributeBlobs.TwoStrings("", long)
    assert blob.Length == 135
    assert Convert.ToInt32(blob[3]) == 128
    assert Convert.ToInt32(blob[4]) == 128
    assert Convert.ToInt32(blob[5]) == 97
    assert Convert.ToInt32(blob[132]) == 97
}

test "the two-byte PackedLen branch carries the high bits into the first byte" {
    long := RepeatedText("a", 300)
    blob := ColumnarAttributeBlobs.TwoStrings("", long)
    assert Convert.ToInt32(blob[3]) == 129
    assert Convert.ToInt32(blob[4]) == 44
    assert blob.Length == 307
}

test "a surrogate pair encodes as one four-byte code point" {
    pair := ColumnarAttributeBlobs.Utf8Bytes("😀")
    assert pair.Count == 4
    assert Convert.ToInt32(pair[0]) == 240
    assert Convert.ToInt32(pair[1]) == 159
    assert Convert.ToInt32(pair[2]) == 152
    assert Convert.ToInt32(pair[3]) == 128
}

test "a three-byte code point and an unpaired surrogate both keep the three-byte form" {
    threeByte := ColumnarAttributeBlobs.Utf8Bytes("€")
    assert threeByte.Count == 3
    assert Convert.ToInt32(threeByte[0]) == 226
    assert Convert.ToInt32(threeByte[1]) == 130
    assert Convert.ToInt32(threeByte[2]) == 172
    // The lone surrogate is TAKEN FROM a real pair rather than spelled as an escape: N# has no
    // `\uXXXX` escape, so `"\ud83d"` is six ASCII characters and would measure nothing.
    pair := "😀"
    lone := ColumnarAttributeBlobs.Utf8Bytes(pair.Substring(0, 1))
    assert lone.Count == 3
    assert Convert.ToInt32(lone[0]) == 237
    assert Convert.ToInt32(lone[1]) == 160
    assert Convert.ToInt32(lone[2]) == 189
}

test "the compressed integer writer spells all three PackedLen branches" {
    one := new List<byte>()
    ColumnarAttributeBlobs.WriteCompressedUInt32(one, 127)
    assert one.Count == 1
    assert Convert.ToInt32(one[0]) == 127
    two := new List<byte>()
    ColumnarAttributeBlobs.WriteCompressedUInt32(two, 16383)
    assert two.Count == 2
    assert Convert.ToInt32(two[0]) == 191
    assert Convert.ToInt32(two[1]) == 255
    four := new List<byte>()
    ColumnarAttributeBlobs.WriteCompressedUInt32(four, 16384)
    assert four.Count == 4
    assert Convert.ToInt32(four[0]) == 192
    assert Convert.ToInt32(four[1]) == 0
    assert Convert.ToInt32(four[2]) == 64
    assert Convert.ToInt32(four[3]) == 0
}

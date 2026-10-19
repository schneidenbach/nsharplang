namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

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

test "the two test slots are named, so the fact slot can be identified rather than counted" {
    assert ColumnarAttributeBlobs.TraitConstructorSlot() == 0
    assert ColumnarAttributeBlobs.FactConstructorSlot() == 1
    assert ColumnarAttributeBlobs.TraitConstructorSlot() != ColumnarAttributeBlobs.FactConstructorSlot()
}

func CabDefineSettableProperty(owner: TypeBuilder, name: string, propertyType: Type) {
    field := owner.DefineField("_" + name, propertyType, FieldAttributes.Private)
    getter := owner.DefineMethod("get_" + name, MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig, propertyType, Type.EmptyTypes)
    getterIl := getter.GetILGenerator()
    getterIl.Emit(OpCodes.Ldarg_0)
    getterIl.Emit(OpCodes.Ldfld, field)
    getterIl.Emit(OpCodes.Ret)

    setter := owner.DefineMethod("set_" + name, MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig, typeof(void), [propertyType])
    setterIl := setter.GetILGenerator()
    setterIl.Emit(OpCodes.Ldarg_0)
    setterIl.Emit(OpCodes.Ldarg_1)
    setterIl.Emit(OpCodes.Stfld, field)
    setterIl.Emit(OpCodes.Ret)

    property := owner.DefineProperty(name, PropertyAttributes.None, propertyType, Type.EmptyTypes)
    property.SetGetMethod(getter)
    property.SetSetMethod(setter)
}

func CabHiddenAttributeType(): Type {
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("ColumnarAttributeHidden" + Guid.NewGuid().ToString("N")), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule("Fixture")
    baseBuilder := module.DefineType("BaseAttribute", TypeAttributes.Public | TypeAttributes.Class, typeof(Attribute))
    baseBuilder.DefineDefaultConstructor(MethodAttributes.Public)
    CabDefineSettableProperty(baseBuilder, "Marker", typeof(object))
    baseType := baseBuilder.CreateType() ?? typeof(Attribute)
    derivedBuilder := module.DefineType("DerivedAttribute", TypeAttributes.Public | TypeAttributes.Class, baseType)
    derivedBuilder.DefineDefaultConstructor(MethodAttributes.Public)
    CabDefineSettableProperty(derivedBuilder, "Marker", typeof(string))
    return derivedBuilder.CreateType() ?? typeof(Attribute)
}

test "a source attribute blob lookup writes the derived hidden metadata property value" {
    attributeType := CabHiddenAttributeType()
    lookupOutcome := "no exception"
    try {
        attributeType.GetProperty("Marker", BindingFlags.Public | BindingFlags.Instance)
    } catch ex: AmbiguousMatchException {
        lookupOutcome = "ambiguous"
    }
    assert lookupOutcome == "ambiguous"

    memberType := typeof(object)
    isField := true
    assert NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.TryResolveMetadataNamedMember(attributeType, "Marker", out memberType, out isField)
    assert !isField
    assert memberType == typeof(string)

    instance := Activator.CreateInstance(attributeType)
    property := ReflectedMemberLookup.FindProperty(attributeType, "Marker", BindingFlags.Public | BindingFlags.Instance)
    assert property != null
    property.SetValue(instance, "derived")
    assert property.GetValue(instance).ToString() == "derived"
}

test "a fact-derived attribute walk crosses from a built type to a reference-loaded base" {
    // The same walk `DerivesFromAttribute` is, asked about a different base. It compares FULL NAMES
    // because a type being built and the reference-loaded type it derives from are two different
    // `Type` instances for one type, so identity answers no about a chain that plainly reaches it.
    assert NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.DerivesFromFullName(typeof(InvalidOperationException), "System.Exception")
    assert NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.DerivesFromFullName(typeof(InvalidOperationException), "System.InvalidOperationException")
    assert !NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.DerivesFromFullName(typeof(InvalidOperationException), "System.ArgumentException")
    assert !NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.DerivesFromFullName(null, "System.Exception")

    // And the rule it serves: `DerivesFromAttribute` IS this walk with `System.Attribute` in it.
    assert NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.DerivesFromFullName(typeof(ObsoleteAttribute), "System.Attribute")
    assert NSharpLang.Compiler.Columnar.ColumnarSourceAttributeBinder.DerivesFromAttribute(typeof(ObsoleteAttribute))
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

test "a string argument with one named string property writes the PROPERTY marker, the string type, then name and value" {
    // `[DebuggerDisplay("x", Type = "T")]`: prolog, SerString "x", NumNamed 1, 0x54 PROPERTY, 0x0E
    // STRING, SerString "Type", SerString "T" -- the shape C# writes for an anonymous type's display.
    blob := ColumnarAttributeBlobs.StringWithNamedStringProperty("x", "Type", "T")
    assert BlobText(blob) == "1-0-1-120-1-0-84-14-4-84-121-112-101-1-84"
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

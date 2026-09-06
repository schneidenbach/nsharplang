namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Reflection

class StaticInitializerOrderState {
    static Next: int = 0
}

func StaticInitializerTakeNext(): int {
    StaticInitializerOrderState.Next = StaticInitializerOrderState.Next + 1
    return StaticInitializerOrderState.Next
}

class StaticInitializerClass {
    static First: int = StaticInitializerTakeNext()
    static Second: int = StaticInitializerTakeNext()
    static SameType: int = SameTypeSeed()
    static Text: string = "line\nquote\""
    static Letter: char = '\n'
    static Ratio: double = 1_234.5
    static NarrowRatio: float = 1.5f
    static Enabled: bool = true
    static Disabled: bool = false
    static Wide: long = 9000L
    static Bits: ulong = 18446744073709551615UL

    static func SameTypeSeed(): int {
        return 17
    }
}

struct StaticInitializerStruct {
    Value: int
    static Seed: int = 23
}

record StaticInitializerRecord {
    Value: int
    static Start: int = 7
    static Label: string = "rc"
}

func StaticInitializerRequiredField(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing static initializer field '" + owner.get_Name() + "." + name + "'.")
    }
    return field
}

test "declared class static initializers retain literals calls and declaration order" {
    assert StaticInitializerClass.First == 1
    assert StaticInitializerClass.Second == 2
    assert StaticInitializerClass.SameType == 17
    assert StaticInitializerClass.Text == "line\nquote\""
    assert StaticInitializerClass.Text.Length == 11
    assert (int)StaticInitializerClass.Letter == 10
    assert StaticInitializerClass.Ratio == 1234.5
    assert StaticInitializerClass.NarrowRatio == 1.5f
    assert StaticInitializerClass.Enabled
    assert !StaticInitializerClass.Disabled
    assert StaticInitializerClass.Wide == 9000L
    assert StaticInitializerClass.Bits == 18446744073709551615UL
    assert StaticInitializerOrderState.Next == 2
}

test "declared class struct and record static fields retain CLR metadata" {
    classField := StaticInitializerRequiredField(typeof(StaticInitializerClass), "First")
    structField := StaticInitializerRequiredField(typeof(StaticInitializerStruct), "Seed")
    recordField := StaticInitializerRequiredField(typeof(StaticInitializerRecord), "Label")

    assert classField.get_IsStatic()
    assert classField.get_FieldType() == typeof(int)
    assert structField.get_IsStatic()
    assert structField.get_FieldType() == typeof(int)
    assert recordField.get_IsStatic()
    assert recordField.get_FieldType() == typeof(string)
}

test "declared struct and record static initializers run through their type initializers" {
    assert StaticInitializerStruct.Seed == 23
    assert StaticInitializerRecord.Start == 7
    assert StaticInitializerRecord.Label == "rc"
}

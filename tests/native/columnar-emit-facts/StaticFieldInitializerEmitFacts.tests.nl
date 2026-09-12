namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections.Generic
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

class StaticInitializerArgumentClass {
    static readonly TupleField: FieldInfo = ResolveTupleField("Item1")
    static readonly EmptyField: FieldInfo = ResolveStringField(nameof(System.String.Empty))

    static func ResolveTupleField(name: string): FieldInfo {
        field := typeof(ValueTuple<int, int>).GetField(name)
        if field == null {
            throw new InvalidOperationException("ValueTuple<int,int>." + name + " was not found.")
        }
        return field
    }

    static func ResolveStringField(name: string): FieldInfo {
        field := typeof(string).GetField(name)
        if field == null {
            throw new InvalidOperationException("System.String." + name + " was not found.")
        }
        return field
    }
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

test "declared static helper initializers pass string and qualified nameof arguments" {
    tupleSlot := StaticInitializerRequiredField(typeof(StaticInitializerArgumentClass), "TupleField")
    emptySlot := StaticInitializerRequiredField(typeof(StaticInitializerArgumentClass), "EmptyField")
    assert tupleSlot.get_IsInitOnly()
    assert emptySlot.get_IsInitOnly()

    tupleField := StaticInitializerArgumentClass.TupleField
    emptyField := StaticInitializerArgumentClass.EmptyField
    expectedTupleField := typeof(ValueTuple<int, int>).GetField("Item1")
    expectedEmptyField := typeof(string).GetField("Empty")
    assert Object.ReferenceEquals(tupleField, expectedTupleField)
    assert Object.ReferenceEquals(emptyField, expectedEmptyField)
    assert tupleField.get_Name() == "Item1"
    assert emptyField.get_Name() == "Empty"
    assert tupleField.get_FieldType() == typeof(int)
    assert emptyField.get_FieldType() == typeof(string)
}

// A STATIC FIELD IS A VALUE, AND ITS OWN INSTANCE MEMBERS ARE REACHABLE THROUGH IT.
//
// `Catalog.Codes.TryGetValue(code, out value)` is a static-field READ followed by an ordinary
// instance call, not a static call on a type named `Catalog.Codes`. The direct-call planner used to
// claim the spelling as a source static owner, fail to find such a type, and reject the whole
// subtree terminally — which took `TryGetValue` (and `ContainsKey`, and every other member of a
// static field's own type) away from the owner that emits it.
//
// The `out` local is the shape that made the loss visible: a by-ref argument only began reaching
// overload resolution once by-ref arguments were typed, and the claim-and-reject verdict came with
// it.
class StaticReceiverCatalog {
    static Codes: Dictionary<int, int> = StaticReceiverBuildCodes()
    static Label: string = "systems"
}

func StaticReceiverBuildCodes(): Dictionary<int, int> {
    map := new Dictionary<int, int>()
    map[1] = 100
    map[2] = 200
    return map
}

func StaticReceiverLookup(code: int): int {
    value := 0
    if StaticReceiverCatalog.Codes.TryGetValue(code, out value) {
        return value
    }
    return -1
}

test "a static field receiver reaches its own instance members including a by-ref out argument" {
    assert StaticReceiverLookup(1) == 100
    assert StaticReceiverLookup(2) == 200
    assert StaticReceiverLookup(3) == -1

    // The same receiver with no by-ref argument at all, which the terminal claim also swallowed.
    assert StaticReceiverCatalog.Codes.ContainsKey(1)
    assert !StaticReceiverCatalog.Codes.ContainsKey(9)
    assert StaticReceiverCatalog.Codes.Count == 2
    assert StaticReceiverCatalog.Label.StartsWith("sys")
}

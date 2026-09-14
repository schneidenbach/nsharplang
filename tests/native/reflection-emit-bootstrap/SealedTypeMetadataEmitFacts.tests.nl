namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection

func SealedTypeMetadataRequiredNestedType(owner: Type, name: string): Type {
    nestedTypes := owner.GetNestedTypes(BindingFlags.NonPublic)
    for nestedType in nestedTypes {
        if nestedType.get_Name() == name {
            return nestedType
        }
    }
    throw new InvalidOperationException("Required nested type was not found: " + name)
}

func SealedTypeMetadataVisibility(candidate: Type): int {
    return (int)candidate.get_Attributes() & 7
}

test "sealed top-level source classes emit CLR sealed metadata" {
    owner := typeof(SealedTypeMetadataEmitFacts)
    assert owner.get_IsSealed(), "top-level sealed class must report Type.IsSealed"
    assert SealedTypeMetadataVisibility(owner) == 1, "top-level sealed class must remain public"
}

test "private nested sealed source classes retain sealed and nesting metadata" {
    owner := typeof(SealedTypeMetadataEmitFacts)
    nestedClass := SealedTypeMetadataRequiredNestedType(owner, "NestedClass")
    assert nestedClass.get_IsSealed(), "private nested sealed class must report Type.IsSealed"
    assert SealedTypeMetadataVisibility(nestedClass) == 3, "private nested sealed class must remain NestedPrivate"
    assert nestedClass.get_DeclaringType() == owner, "private nested sealed class must retain its declaring type"
}

test "private nested sealed source records retain sealed and nesting metadata" {
    owner := typeof(SealedTypeMetadataEmitFacts)
    nestedRecord := SealedTypeMetadataRequiredNestedType(owner, "NestedRecord")
    assert nestedRecord.get_IsSealed(), "private nested sealed record must report Type.IsSealed"
    assert SealedTypeMetadataVisibility(nestedRecord) == 3, "private nested sealed record must remain NestedPrivate"
    assert nestedRecord.get_DeclaringType() == owner, "private nested sealed record must retain its declaring type"
}

test "ordinary classes remain open while CLR value types remain sealed" {
    openClass := typeof(OpenTypeMetadataEmitControl)
    assert !openClass.get_IsSealed(), "ordinary class control must remain open"
    assert SealedTypeMetadataVisibility(openClass) == 1, "ordinary class control must remain public"

    valueType := typeof(ValueTypeMetadataEmitControl)
    assert valueType.get_IsValueType(), "value type control must remain a value type"
    assert valueType.get_IsSealed(), "CLR value type control must remain sealed"
    assert SealedTypeMetadataVisibility(valueType) == 1, "value type control must remain public"
}

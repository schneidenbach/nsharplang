namespace NSharpLang.ColumnarEmitFacts.Tests

import System

// `System.Type.EmptyTypes` is a non-literal static field. The field plan must retain its exact
// declaring/value identities and emit ldsfld; this oracle reaches the same BCL singleton without
// relying on the generic Array.Empty<T>() source-call surface.
func TypeEmptyTypesOracle(): object? {
    definition := typeof(Array).GetMethod("Empty")
    if definition == null {
        throw new InvalidOperationException("System.Array.Empty<T>() was not found.")
    }

    typeArguments := new Type[](1)
    typeArguments[0] = typeof(Type)
    closed := definition.MakeGenericMethod(typeArguments)
    noArguments := new object?[](0)
    value := closed.Invoke(null, noArguments)
    if value == null {
        throw new InvalidOperationException("System.Array.Empty<Type>() did not return Type[].")
    }
    return value
}

func TypeEmptyTypesShortRead(): Type[] {
    return Type.EmptyTypes
}

func TypeEmptyTypesQualifiedRead(): Type[] {
    return System.Type.EmptyTypes
}

func TypeEmptyTypesLocalRead(): Type[] {
    captured := Type.EmptyTypes
    return captured
}

func TypeEmptyTypesOutRead(out result: Type[]) {
    captured: Type[] = System.Type.EmptyTypes
    result = captured
}

test "Type.EmptyTypes emits the BCL empty Type array field exactly" {
    expected := TypeEmptyTypesOracle()
    shortValue := TypeEmptyTypesShortRead()
    qualifiedValue := TypeEmptyTypesQualifiedRead()
    localValue := TypeEmptyTypesLocalRead()
    outValue: Type[] = new Type[](1)
    TypeEmptyTypesOutRead(out outValue)

    assert expected != null
    assert shortValue.Length == 0
    assert qualifiedValue.Length == 0
    assert localValue.Length == 0
    assert outValue.Length == 0
    assert Object.ReferenceEquals(shortValue, expected)
    assert Object.ReferenceEquals(qualifiedValue, expected)
    assert Object.ReferenceEquals(localValue, expected)
    assert Object.ReferenceEquals(outValue, expected)
}

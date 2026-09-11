namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System

test "Array Empty generic call returns the exact shared string array singleton" {
    first := Array.Empty<string>()
    second := Array.Empty<string>()

    assert first.Length == 0
    assert second.Length == 0
    assert Object.ReferenceEquals(first, second)
    assert first.GetType() == typeof(string[])
}

test "Array Empty generic call returns the exact shared Int32 array singleton" {
    first := Array.Empty<int>()
    second := Array.Empty<int>()

    assert first.Length == 0
    assert second.Length == 0
    assert Object.ReferenceEquals(first, second)
    assert first.GetType() == typeof(int[])
}

test "Array Empty generic call returns the exact shared emitter array singletons" {
    firstBytes := Array.Empty<byte>()
    secondBytes := Array.Empty<byte>()
    firstTypes := Array.Empty<Type>()
    secondTypes := Array.Empty<Type>()
    firstTypeArrays := Array.Empty<Type[]>()
    secondTypeArrays := Array.Empty<Type[]>()

    assert firstBytes.Length == 0
    assert secondBytes.Length == 0
    assert Object.ReferenceEquals(firstBytes, secondBytes)
    assert firstBytes.GetType() == typeof(byte[])

    assert firstTypes.Length == 0
    assert secondTypes.Length == 0
    assert Object.ReferenceEquals(firstTypes, secondTypes)
    assert firstTypes.GetType() == typeof(Type[])

    assert firstTypeArrays.Length == 0
    assert secondTypeArrays.Length == 0
    assert Object.ReferenceEquals(firstTypeArrays, secondTypeArrays)
    assert firstTypeArrays.GetType() == typeof(Type[][])
}

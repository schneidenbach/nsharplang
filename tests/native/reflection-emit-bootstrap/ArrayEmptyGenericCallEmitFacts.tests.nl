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

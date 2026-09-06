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

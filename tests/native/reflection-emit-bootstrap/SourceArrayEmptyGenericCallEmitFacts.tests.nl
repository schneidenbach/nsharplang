namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System

class SourceArrayEmptyElement {
}

test "Array Empty generic call returns the exact shared source-class array singleton" {
    first := Array.Empty<SourceArrayEmptyElement>()
    second := Array.Empty<SourceArrayEmptyElement>()
    firstObject := first as object
    secondObject := second as object

    assert first.Length == 0
    assert second.Length == 0
    assert Object.ReferenceEquals(firstObject, secondObject)
}

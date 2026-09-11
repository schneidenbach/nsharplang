namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System.Globalization


// Parameter-default ownership needs this exact BCL overload: explicit NumberStyles.Integer,
// invariant culture, and a mutable Int32 out slot.
class StyledInt32TryParseEmitProbe {
    static func TryParse(text: string, out value: int): bool {
        return Int32.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value)
    }
}

test "N# binds styled invariant Int32 TryParse and preserves BCL out writes" {
    value := 0
    assert StyledInt32TryParseEmitProbe.TryParse("2147483647", out value)
    assert value == 2147483647
    assert StyledInt32TryParseEmitProbe.TryParse("-2147483648", out value)
    assert value == -2147483647 - 1
    assert StyledInt32TryParseEmitProbe.TryParse("  +17  ", out value)
    assert value == 17

    value = 99
    assert !StyledInt32TryParseEmitProbe.TryParse("2147483648", out value)
    assert value == 0
    value = 99
    assert !StyledInt32TryParseEmitProbe.TryParse("1,234", out value)
    assert value == 0
}

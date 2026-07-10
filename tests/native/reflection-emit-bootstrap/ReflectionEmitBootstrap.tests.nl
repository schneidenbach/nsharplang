namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "N# owns the direct Reflection.Emit bootstrap surface" {
    assert ReflectionEmitBootstrapProbe.ContractVersion() == 12
    assert ReflectionEmitBootstrapProbe.HasRangeHandleSurface()
}

test "N# owns exact static parse calls and by-reference results" {
    assert ReflectionEmitBootstrapProbe.ParseInt32("2147483647") == 2147483647

    integer := 0
    assert ReflectionEmitBootstrapProbe.TryParseInt32("-42", out integer)
    assert integer == -42
    integer = 99
    assert !ReflectionEmitBootstrapProbe.TryParseInt32("not-an-integer", out integer)
    assert integer == 0

    assert ReflectionEmitBootstrapProbe.ParseDoubleInvariant("1.25e2") == 125.0
    assert ReflectionEmitBootstrapProbe.ParseDoubleInvariant("1,234.5") == 1234.5

    floating := 0.0
    assert ReflectionEmitBootstrapProbe.TryParseDoubleInvariant("-6.25E-1", out floating)
    assert floating == -0.625
    floating = 99.0
    assert !ReflectionEmitBootstrapProbe.TryParseDoubleInvariant("not-a-double", out floating)
    assert floating == 0.0
}

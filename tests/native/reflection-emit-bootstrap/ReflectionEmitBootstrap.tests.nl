namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "N# owns the direct Reflection.Emit bootstrap surface" {
    assert ReflectionEmitBootstrapProbe.ContractVersion() == 4
    assert ReflectionEmitBootstrapProbe.HasRangeHandleSurface()
}

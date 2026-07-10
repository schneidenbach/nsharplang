namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "N# owns the direct Reflection.Emit bootstrap surface" {
    assert ReflectionEmitBootstrapProbe.ContractVersion() == 7
    assert ReflectionEmitBootstrapProbe.HasRangeHandleSurface()
}

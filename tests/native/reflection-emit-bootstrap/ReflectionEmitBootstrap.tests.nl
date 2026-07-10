namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "N# owns the direct Reflection.Emit bootstrap surface" {
    assert ReflectionEmitBootstrapProbe.ContractVersion() == 9
    assert ReflectionEmitBootstrapProbe.HasRangeHandleSurface()
}

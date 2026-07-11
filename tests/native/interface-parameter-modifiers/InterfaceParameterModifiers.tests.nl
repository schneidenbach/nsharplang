namespace NSharpLang.InterfaceParameterModifiers.Tests

test "params interface declarations preserve exact-array excluded calls" {
    service: IModifierService = new ModifierService()

    assert CountThroughInterface(service) == 4
}

test "ref and out interface declarations stay on by-reference ownership" {
    service: IModifierService = new ModifierService()

    assert MutateThroughInterface(service) == 1523
}

namespace NSharpLang.InterfaceParameterModifiers.Tests

test "params interface declarations preserve exact-array excluded calls" {
    service: IModifierService = new ModifierService()

    assert CountThroughInterface(service) == 4
}

test "ref and out interface declarations stay on by-reference ownership" {
    service: IModifierService = new ModifierService()

    assert MutateThroughInterface(service) == 1523
}

test "byref parameter reads plan inside binary expressions" {
    service: IModifierService = new ModifierService()

    // 16 * 2 + (100 - 16) = 116 — the byref deref rides both binary operand orders.
    assert ReadThroughInterface(service) == 116
}

namespace NSharpLang.Compiler.Columnar

test "expanded params elements map back to their one declared slot beside an in parameter" {
    declaredKinds := new int[](3)
    declaredKinds[0] = 4
    declaredKinds[1] = 5
    declaredKinds[2] = 3

    expandedKinds := ColumnarParamsExpansion.ExpandedParameterModifierKindsOrNull(declaredKinds, 1, 1, 4)

    assert expandedKinds != null
    assert expandedKinds.Length == 4
    assert expandedKinds[0] == 5
    assert expandedKinds[1] == 3
    assert expandedKinds[2] == 3
    assert expandedKinds[3] == 3
}

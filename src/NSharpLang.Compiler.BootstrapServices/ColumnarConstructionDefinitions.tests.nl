namespace NSharpLang.Compiler.Columnar

import System

test "source constructor definitions atomically retain exact normalized signatures" {
    definition := SourceCallDefinition("ConstructionDefinitionProbe", true)
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(string)

    builder := definition.DefineUserConstructor(
        parameterTypes,
        new int[](0),
        new string[](0))

    assert definition.Constructors.Count == 1
    retained := definition.Constructors[0]
    assert ColumnarConstructionPlanner.SameObject(
        retained.Builder, builder)
    assert ColumnarConstructionPlanner.SameObject(
        builder.get_DeclaringType(), definition.Builder)
    assert retained.ParamTypes.Length == 2
    assert retained.ParamTypes[0] == typeof(int)
    assert retained.ParamTypes[1] == typeof(string)
    assert retained.DefaultKinds.Length == 2
    assert retained.DefaultKinds[0] == -1
    assert retained.DefaultKinds[1] == -1
    assert retained.DefaultTexts.Length == 2
    assert retained.DefaultTexts[0] == ""
    assert retained.DefaultTexts[1] == ""

    parameterTypes[0] = typeof(bool)
    assert retained.ParamTypes[0] == typeof(int)
}

test "source constructor definitions copy explicit default columns" {
    definition := SourceCallDefinition("ConstructionDefaultProbe", true)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    defaultKinds := new int[](1)
    defaultKinds[0] = 1
    defaultTexts := new string[](1)
    defaultTexts[0] = "41"

    definition.DefineUserConstructor(
        parameterTypes,
        defaultKinds,
        defaultTexts)

    retained := definition.Constructors[0]
    defaultKinds[0] = -1
    defaultTexts[0] = ""
    assert retained.DefaultKinds[0] == 1
    assert retained.DefaultTexts[0] == "41"
}

test "source constructor definition corruption leaves no partial registration" {
    definition := SourceCallDefinition("ConstructionCorruptionProbe", true)
    oneType := new Type[](1)
    oneType[0] = typeof(int)

    assert throws InvalidOperationException {
        definition.DefineUserConstructor(
            oneType,
            new int[](1),
            new string[](0))
    }
    assert definition.Constructors.Count == 0

}

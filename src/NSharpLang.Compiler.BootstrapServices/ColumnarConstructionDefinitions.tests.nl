namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

test "source property factory establishes CLR accessor identity" {
    definition := SourceCallDefinition(
        "ConstructionPropertyDefinitionProbe", true)
    property := ColumnarPropertyDef.Define(
        definition.Builder,
        "get_Value",
        MethodAttributes.Public,
        typeof(int),
        "set_Value",
        MethodAttributes.Public)

    assert property.Getter.get_IsSpecialName()
    setter := property.Setter
    if setter == null {
        throw new InvalidOperationException(
            "The property factory omitted its requested setter.")
    }
    assert setter.get_IsSpecialName()
    assert ColumnarConstructionPlanner.SameObject(
        property.Getter.get_DeclaringType(), definition.Builder)
    assert ColumnarConstructionPlanner.SameObject(
        setter.get_DeclaringType(), definition.Builder)
}

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

test "source constructor enum defaults retain exact declaration identity" {
    rightStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    rightStrings["Value"] = "right"
    right := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        rightStrings,
        "Right.Selection")
    canonical := ""
    claimed := false
    assert ColumnarConstructorDefaultBinder.TryCanonicalizeSourceEnumMember(
        typeof(string),
        "Alias.Selection.Value",
        right,
        right,
        out canonical,
        out claimed)
    assert claimed
    assert canonical == "Right.Selection.Value"

    definition := SourceCallDefinition(
        "ConstructionExactDefaultProbe", true)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    defaultKinds := new int[](1)
    defaultKinds[0] = 1000
    defaultTexts := new string[](1)
    defaultTexts[0] = canonical
    definition.DefineUserConstructor(
        parameterTypes, defaultKinds, defaultTexts)
    assert definition.Constructors[0].DefaultTexts[0]
        == "Right.Selection.Value"
}

test "source constructor enum default rejects erased identity mismatch" {
    leftStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    leftStrings["Value"] = "left"
    left := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        leftStrings,
        "Left.Selection")
    rightStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    rightStrings["Value"] = "right"
    right := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        rightStrings,
        "Right.Selection")
    canonical := ""
    claimed := false
    assert !ColumnarConstructorDefaultBinder.TryCanonicalizeSourceEnumMember(
        typeof(string),
        "Alias.Selection.Value",
        right,
        left,
        out canonical,
        out claimed)
    assert claimed
}

test "constructor default binder canonicalizes complete source and runtime enum columns" {
    sourceStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    sourceStrings["Value"] = "right"
    sourceEnum := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        sourceStrings,
        "Right.Selection")
    sourceEnums := SemanticEmptyEnums()
    sourceEnums[sourceEnum.DeclaredTypeName] = sourceEnum
    sourceSources := new string[](1)
    sourceFileNames := new string[](1)
    sourceSources[0] = "namespace Right\nenum Selection: string { Value = \"right\" }\n"
    sourceFileNames[0] = "constructor-defaults/source.nl"
    sourceResolution := SemanticTypeResolution(
        ExactTypeProgram(sourceSources, sourceFileNames),
        0,
        sourceEnums,
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        "")

    sourceParameterTypes := new Type[](1)
    sourceParameterTypes[0] = typeof(string)
    sourceParameterCanonicals := new string[](1)
    sourceParameterCanonicals[0] = "Selection"
    sourceDefaultKinds := new int[](1)
    sourceDefaultKinds[0] = 1000
    sourceDefaultTexts := new string[](1)
    sourceDefaultTexts[0] = "Selection.Value"
    canonicalSourceDefaults := new string[](0)
    assert ColumnarConstructorDefaultBinder.TryCanonicalizeDefaults(
        sourceParameterTypes,
        sourceParameterCanonicals,
        sourceDefaultKinds,
        sourceDefaultTexts,
        sourceResolution.Enums,
        out canonicalSourceDefaults)
    assert canonicalSourceDefaults.Length == 1
    assert canonicalSourceDefaults[0] == "Right.Selection.Value"

    runtimeSources := new string[](1)
    runtimeFileNames := new string[](1)
    runtimeSources[0] = "import System\n"
    runtimeFileNames[0] = "constructor-defaults/runtime.nl"
    runtimeResolution := SemanticTypeResolution(
        ExactTypeProgram(runtimeSources, runtimeFileNames),
        0,
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        "")
    runtimeParameterTypes := new Type[](1)
    runtimeDayType := Type.GetType("System.DayOfWeek")
    if runtimeDayType == null {
        throw new InvalidOperationException(
            "System.DayOfWeek runtime type was not found.")
    }
    runtimeParameterTypes[0] = runtimeDayType
    runtimeParameterCanonicals := new string[](1)
    runtimeParameterCanonicals[0] = "System.DayOfWeek"
    runtimeDefaultKinds := new int[](1)
    runtimeDefaultKinds[0] = 1000
    runtimeDefaultTexts := new string[](1)
    runtimeDefaultTexts[0] = "System.DayOfWeek.Friday"
    canonicalRuntimeDefaults := new string[](0)
    assert ColumnarConstructorDefaultBinder.TryCanonicalizeDefaults(
        runtimeParameterTypes,
        runtimeParameterCanonicals,
        runtimeDefaultKinds,
        runtimeDefaultTexts,
        runtimeResolution.Enums,
        out canonicalRuntimeDefaults)
    assert canonicalRuntimeDefaults.Length == 1
    assert canonicalRuntimeDefaults[0] == "System.DayOfWeek.Friday"
}

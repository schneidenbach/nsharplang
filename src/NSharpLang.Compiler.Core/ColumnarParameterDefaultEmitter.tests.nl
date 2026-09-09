namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Text.Json

// The production owner receives a semantic enum registry, rather than a plain dictionary.  Keep
// the controls at that boundary so source definitions and BCL enum fallbacks take the same lookup
// route as declaration emission.
func ParameterDefaultRegistry(
    definitions: Dictionary<string, ColumnarEnumDef>
): ColumnarSemanticRegistry<ColumnarEnumDef> {
    sources := new string[](1)
    names := new string[](1)
    sources[0] = "import System\nimport System.Text.Json\n"
    names[0] = "parameter-default-controls/defaults.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, names),
        0,
        definitions,
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )
    return resolution.Enums
}

func ParameterDefaultEmptyRegistry(): ColumnarSemanticRegistry<ColumnarEnumDef> {
    return ParameterDefaultRegistry(
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    )
}

func ParameterDefaultEmitObjectConstructor(constructorBuilder: ConstructorBuilder) {
    noParameters := new Type[](0)
    objectConstructor := ExecutorRequiredConstructor(typeof(object), noParameters)
    il := constructorBuilder.GetILGenerator()
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Call, objectConstructor)
    il.Emit(OpCodes.Ret)
}

func ParameterDefaultSourceRegistry(): ColumnarSemanticRegistry<ColumnarEnumDef> {
    textConstants := new Dictionary<string, string>(StringComparer.Ordinal)
    textConstants["Ready"] = "source-ready"
    numberConstants := new Dictionary<string, int>(StringComparer.Ordinal)
    numberConstants["Friday"] = 5
    definitions := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    definitions["TextState"] = new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        textConstants,
        "TextState"
    )
    definitions["DayOfWeek"] = new ColumnarEnumDef(
        typeof(DayOfWeek),
        numberConstants,
        null,
        "DayOfWeek"
    )
    return ParameterDefaultRegistry(definitions)
}

test "parameter-default emitter defines method rows with exact metadata and source enum constants" {
    owner := TypeOfCreateBuilder(
        "ParameterDefaultMethodMetadata",
        "ColumnarParameterDefaultControls.MethodMetadata",
        0
    )
    parameterTypes := new Type[](7)
    parameterTypes[0] = typeof(bool)
    parameterTypes[1] = typeof(int)
    parameterTypes[2] = typeof(string)
    parameterTypes[3] = typeof(string)
    parameterTypes[4] = typeof(string)
    parameterTypes[5] = typeof(DayOfWeek)
    parameterTypes[6] = typeof(int).MakeByRefType()
    method := owner.DefineMethod(
        "Apply",
        (MethodAttributes)22,
        ExecutorVoidType(),
        parameterTypes
    )

    names := new string[](7)
    names[0] = "enabled"
    names[1] = "count"
    names[2] = "text"
    names[3] = "nil"
    names[4] = "state"
    names[5] = "number"
    names[6] = "result"
    modifiers := new int[](7)
    modifiers[6] = 2
    defaultKinds := new int[](6)
    defaultKinds[0] = 44
    defaultKinds[1] = 1
    defaultKinds[2] = 4
    defaultKinds[3] = 4
    defaultKinds[4] = ColumnarParameterDefaultEmitter.MemberAccessKind
    defaultKinds[5] = ColumnarParameterDefaultEmitter.MemberAccessKind
    defaultTexts := new string[](6)
    defaultTexts[0] = "true"
    defaultTexts[1] = "19"
    defaultTexts[2] = "\"line\\nvalue\""
    defaultTexts[3] = null
    defaultTexts[4] = "TextState.Ready"
    defaultTexts[5] = "DayOfWeek.Friday"

    assert ColumnarParameterDefaultEmitter.MemberAccessKind == 1000
    assert ColumnarParameterDefaultEmitter.DefineMethodParameterMetadata(
        method,
        parameterTypes,
        names,
        modifiers,
        defaultKinds,
        defaultTexts,
        ParameterDefaultSourceRegistry()
    ), "method metadata application unexpectedly declined"
    TypeOfMethodBuilderIL(method).Emit(OpCodes.Ret)

    baked := IdentityBake(owner)
    emitted := baked.GetMethod("Apply")
    if emitted == null {
        throw new InvalidOperationException("The parameter-default method was not baked.")
    }
    parameters := emitted.GetParameters()
    assert parameters.Length == 7

    enabled := parameters[0]
    count := parameters[1]
    text := parameters[2]
    nil := parameters[3]
    state := parameters[4]
    number := parameters[5]
    result := parameters[6]
    assert enabled.get_Name() == "enabled"
    assert enabled.get_Position() == 0
    assert Convert.ToInt32(enabled.get_Attributes()) == 4112
    assert enabled.get_IsOptional()
    assert enabled.get_HasDefaultValue()
    assert Convert.ToBoolean(enabled.get_RawDefaultValue())
    assert count.get_Name() == "count"
    assert count.get_Position() == 1
    assert Convert.ToInt32(count.get_RawDefaultValue()) == 19
    assert text.get_Name() == "text"
    assert text.get_Position() == 2
    assert Convert.ToString(text.get_RawDefaultValue()) == "line\nvalue"
    assert nil.get_Name() == "nil"
    assert nil.get_Position() == 3
    assert nil.get_HasDefaultValue()
    // A null string is null metadata.  Constructor-call emission deliberately has a different
    // rule and emits String.Empty, covered below.
    assert nil.get_RawDefaultValue() == null
    assert state.get_Name() == "state"
    assert Convert.ToString(state.get_RawDefaultValue()) == "source-ready"
    assert number.get_Name() == "number"
    assert Convert.ToInt32(number.get_RawDefaultValue()) == 5
    assert result.get_Name() == "result"
    assert result.get_Position() == 6
    assert result.get_IsOut()
    assert !result.get_IsOptional()
    assert !result.get_HasDefaultValue()
    assert Convert.ToInt32(result.get_Attributes()) == 2
}

test "parameter-default emitter defines constructor rows with bool and null metadata" {
    owner := TypeOfCreateBuilder(
        "ParameterDefaultConstructorMetadata",
        "ColumnarParameterDefaultControls.ConstructorMetadata",
        0
    )
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(bool)
    parameterTypes[1] = typeof(string)
    constructorBuilder := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        parameterTypes
    )
    names := new string[](2)
    names[0] = "enabled"
    names[1] = "label"
    kinds := new int[](2)
    kinds[0] = 45
    kinds[1] = 4
    texts := new string[](2)
    texts[0] = "false"
    texts[1] = null

    assert ColumnarParameterDefaultEmitter.DefineConstructorParameterMetadata(
        constructorBuilder,
        parameterTypes,
        names,
        new int[](0),
        kinds,
        texts,
        ParameterDefaultEmptyRegistry()
    )
    ParameterDefaultEmitObjectConstructor(constructorBuilder)

    baked := IdentityBake(owner)
    emitted := ExecutorRequiredConstructor(baked, parameterTypes)
    parameters := emitted.GetParameters()
    assert parameters.Length == 2
    assert parameters[0].get_Name() == "enabled"
    assert parameters[0].get_Position() == 0
    assert Convert.ToInt32(parameters[0].get_Attributes()) == 4112
    assert !Convert.ToBoolean(parameters[0].get_RawDefaultValue())
    assert parameters[1].get_Name() == "label"
    assert parameters[1].get_Position() == 1
    assert parameters[1].get_HasDefaultValue()
    assert parameters[1].get_RawDefaultValue() == null
}

test "parameter-default emitter bounds default columns uses object fallback and retains earlier method and constructor rows on failure" {
    registry := ParameterDefaultSourceRegistry()
    owner := TypeOfCreateBuilder(
        "ParameterDefaultPartialFailure",
        "ColumnarParameterDefaultControls.PartialFailure",
        0
    )
    declaredTypes := new Type[](3)
    declaredTypes[0] = typeof(bool)
    declaredTypes[1] = typeof(DayOfWeek)
    declaredTypes[2] = typeof(int)
    method := owner.DefineMethod(
        "Partial",
        (MethodAttributes)22,
        ExecutorVoidType(),
        declaredTypes
    )
    suppliedTypes := new Type[](1)
    suppliedTypes[0] = typeof(bool)
    names := new string[](3)
    names[0] = "first"
    names[1] = "fallback"
    names[2] = "later"
    modifiers := new int[](1)
    modifiers[0] = 2
    kinds := new int[](2)
    kinds[0] = 44
    kinds[1] = ColumnarParameterDefaultEmitter.MemberAccessKind
    texts := new string[](2)
    texts[0] = "true"
    texts[1] = "DayOfWeek.Friday"

    assert ColumnarParameterDefaultEmitter.HasParameterDefault(kinds, texts, 0)
    assert ColumnarParameterDefaultEmitter.HasParameterDefault(kinds, texts, 1)
    assert !ColumnarParameterDefaultEmitter.HasParameterDefault(kinds, texts, -1)
    assert !ColumnarParameterDefaultEmitter.HasParameterDefault(kinds, texts, 2)
    assert !ColumnarParameterDefaultEmitter.HasParameterDefault(
        kinds,
        new string[](1),
        1
    )

    // The second declared signature is an eligible source enum, but its row has no supplied type.
    // The C# owner falls back to object and declines after DefineParameter has already committed the
    // first row and the failing optional row; baking normalizes that unset row by clearing HasDefault.
    // It must not synthesize a third row.
    assert !ColumnarParameterDefaultEmitter.DefineMethodParameterMetadata(
        method,
        suppliedTypes,
        names,
        modifiers,
        kinds,
        texts,
        registry
    ), "method fallback row unexpectedly accepted"
    TypeOfMethodBuilderIL(method).Emit(OpCodes.Ret)

    baked := IdentityBake(owner)
    emitted := baked.GetMethod("Partial")
    if emitted == null {
        throw new InvalidOperationException("The partial parameter-default method was not baked.")
    }
    parameters := emitted.GetParameters()
    assert parameters.Length == 3
    assert parameters[0].get_Name() == "first"
    assert Convert.ToInt32(parameters[0].get_Attributes()) == 4114
    assert Convert.ToBoolean(parameters[0].get_RawDefaultValue())
    assert parameters[1].get_Name() == "fallback"
    assert Convert.ToInt32(parameters[1].get_Attributes()) == 16
    assert parameters[1].get_IsOptional()
    assert !parameters[1].get_HasDefaultValue()
    assert parameters[2].get_Name() == null
    assert !parameters[2].get_IsOptional()
    assert !parameters[2].get_HasDefaultValue()

    constructorOwner := TypeOfCreateBuilder(
        "ParameterDefaultConstructorPartialFailure",
        "ColumnarParameterDefaultControls.ConstructorPartialFailure",
        0
    )
    constructorBuilder := constructorOwner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        declaredTypes
    )
    assert !ColumnarParameterDefaultEmitter.DefineConstructorParameterMetadata(
        constructorBuilder,
        suppliedTypes,
        names,
        modifiers,
        kinds,
        texts,
        registry
    ), "constructor fallback row unexpectedly accepted"
    ParameterDefaultEmitObjectConstructor(constructorBuilder)
    bakedConstructorOwner := IdentityBake(constructorOwner)
    emittedConstructor := ExecutorRequiredConstructor(
        bakedConstructorOwner,
        declaredTypes
    )
    constructorParameters := emittedConstructor.GetParameters()
    assert constructorParameters.Length == 3
    assert constructorParameters[0].get_Name() == "first"
    assert Convert.ToInt32(constructorParameters[0].get_Attributes()) == 4114
    assert Convert.ToBoolean(constructorParameters[0].get_RawDefaultValue())
    assert constructorParameters[1].get_Name() == "fallback"
    assert Convert.ToInt32(constructorParameters[1].get_Attributes()) == 16
    assert constructorParameters[1].get_IsOptional()
    assert !constructorParameters[1].get_HasDefaultValue()
    assert constructorParameters[2].get_Name() == null
    assert !constructorParameters[2].get_IsOptional()
    assert !constructorParameters[2].get_HasDefaultValue()
}

test "parameter-default emitter gives source string and numeric definitions precedence and clears failed out slots" {
    strings := new Dictionary<string, string>(StringComparer.Ordinal)
    strings["Ready"] = "registry-string"
    sourceNumbers := new Dictionary<string, int>(StringComparer.Ordinal)
    sourceNumbers["Friday"] = 91
    definitions := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    definitions["TextState"] = new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        strings,
        "TextState"
    )
    // The source entry intentionally disagrees with the BCL DayOfWeek.Friday value (5).  A 91
    // outcome proves the source-registry lookup happens before the runtime enum fallback.
    definitions["DayOfWeek"] = new ColumnarEnumDef(
        typeof(DayOfWeek),
        sourceNumbers,
        null,
        "DayOfWeek"
    )
    registry := ParameterDefaultRegistry(definitions)

    text := "sentinel"
    assert ColumnarParameterDefaultEmitter.TryResolveStringEnumParameterDefault(
        typeof(string),
        "TextState.Ready",
        registry,
        out text
    )
    assert text == "registry-string"
    text = "sentinel"
    assert !ColumnarParameterDefaultEmitter.TryResolveStringEnumParameterDefault(
        typeof(string),
        "TextState.Missing",
        registry,
        out text
    )
    assert text == ""

    number := -1
    assert ColumnarParameterDefaultEmitter.TryResolveEnumParameterDefault(
        typeof(DayOfWeek),
        "DayOfWeek.Friday",
        registry,
        out number
    )
    assert number == 91
    number = -1
    assert !ColumnarParameterDefaultEmitter.TryResolveEnumParameterDefault(
        typeof(DayOfWeek),
        "DayOfWeek.Missing",
        registry,
        out number
    )
    assert number == 0
}

test "parameter-default emitter admits only int-backed external enums by short or full name" {
    registry := ParameterDefaultEmptyRegistry()
    shortValue := -1
    assert ColumnarParameterDefaultEmitter.TryResolveEnumParameterDefault(
        typeof(DayOfWeek),
        "DayOfWeek.Friday",
        registry,
        out shortValue
    )
    assert shortValue == 5
    fullValue := -1
    assert ColumnarParameterDefaultEmitter.TryResolveEnumParameterDefault(
        typeof(DayOfWeek),
        "System.DayOfWeek.Friday",
        registry,
        out fullValue
    )
    assert fullValue == 5

    assert Enum.GetUnderlyingType(typeof(JsonValueKind)) == typeof(byte)
    ineligible := -1
    assert !ColumnarParameterDefaultEmitter.TryResolveEnumParameterDefault(
        typeof(JsonValueKind),
        "JsonValueKind.True",
        registry,
        out ineligible
    )
    assert ineligible == 0
    malformed := -1
    assert !ColumnarParameterDefaultEmitter.TryResolveEnumParameterDefault(
        typeof(DayOfWeek),
        "System.DayOfWeek.",
        registry,
        out malformed
    )
    assert malformed == 0
}

test "parameter-default emitter checks constructor default eligibility at the exact bounded type rules" {
    registry := ParameterDefaultSourceRegistry()
    kinds := new int[](7)
    kinds[0] = 46
    kinds[1] = 44
    kinds[2] = 45
    kinds[3] = 1
    kinds[4] = 4
    kinds[5] = ColumnarParameterDefaultEmitter.MemberAccessKind
    kinds[6] = 1
    texts := new string[](7)
    texts[0] = null
    texts[1] = "true"
    texts[2] = "false"
    texts[3] = "-27"
    texts[4] = null
    texts[5] = "TextState.Ready"
    texts[6] = "not-an-int"

    assert ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(string),
        kinds,
        texts,
        0,
        registry
    )
    assert !ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(int),
        kinds,
        texts,
        0,
        registry
    )
    assert ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(bool),
        kinds,
        texts,
        1,
        registry
    )
    assert ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(bool),
        kinds,
        texts,
        2,
        registry
    )
    assert ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(int),
        kinds,
        texts,
        3,
        registry
    )
    assert ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(string),
        kinds,
        texts,
        4,
        registry
    )
    assert ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(string),
        kinds,
        texts,
        5,
        registry
    )
    assert !ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(string),
        kinds,
        texts,
        6,
        registry
    )
    assert !ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(int),
        kinds,
        texts,
        6,
        registry
    )
    assert !ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(int),
        kinds,
        texts,
        -1,
        registry
    )
    assert !ColumnarParameterDefaultEmitter.CanUseConstructorDefaultAs(
        typeof(int),
        kinds,
        new string[](2),
        3,
        registry
    )
}

test "parameter-default emitter emits executable call defaults and leaves a null result type on decline" {
    noParameters := new Type[](0)
    registry := ParameterDefaultSourceRegistry()

    nullMethod := BoundDynamicMethod(
        "ParameterDefaultNullCall",
        typeof(string),
        noParameters
    )
    nullType: Type? = typeof(object)
    nullIl := nullMethod.GetILGenerator()
    assert ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        nullIl,
        typeof(string),
        46,
        null,
        registry,
        out nullType
    )
    assert nullType == typeof(string)
    nullIl.Emit(OpCodes.Ret)
    nullValue := nullMethod.Invoke(null, new object[](0))
    assert nullValue == null

    boolMethod := BoundDynamicMethod(
        "ParameterDefaultBoolCall",
        typeof(bool),
        noParameters
    )
    boolType: Type? = typeof(object)
    boolIl := boolMethod.GetILGenerator()
    assert ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        boolIl,
        typeof(bool),
        45,
        "false",
        registry,
        out boolType
    )
    assert boolType == typeof(bool)
    boolIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(boolMethod, new object[](0)) == "False"

    intMethod := BoundDynamicMethod(
        "ParameterDefaultIntCall",
        typeof(int),
        noParameters
    )
    intType: Type? = typeof(object)
    intIl := intMethod.GetILGenerator()
    assert ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        intIl,
        typeof(int),
        1,
        "-27",
        registry,
        out intType
    )
    assert intType == typeof(int)
    intIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(intMethod, new object[](0)) == "-27"

    // Kind 4 preserves null in parameter metadata above, but omitted constructor arguments are
    // emitted as an empty runtime string by the original compiler contract.
    stringMethod := BoundDynamicMethod(
        "ParameterDefaultStringCall",
        typeof(string),
        noParameters
    )
    stringType: Type? = typeof(object)
    stringIl := stringMethod.GetILGenerator()
    assert ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        stringIl,
        typeof(string),
        4,
        null,
        registry,
        out stringType
    )
    assert stringType == typeof(string)
    stringIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(stringMethod, new object[](0)) == ""

    sourceMethod := BoundDynamicMethod(
        "ParameterDefaultSourceStringCall",
        typeof(string),
        noParameters
    )
    sourceType: Type? = typeof(object)
    sourceIl := sourceMethod.GetILGenerator()
    assert ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        sourceIl,
        typeof(string),
        ColumnarParameterDefaultEmitter.MemberAccessKind,
        "TextState.Ready",
        registry,
        out sourceType
    )
    assert sourceType == typeof(string)
    sourceIl.Emit(OpCodes.Ret)
    assert BoundInvokeText(sourceMethod, new object[](0)) == "source-ready"

    invalidInteger := BoundDynamicMethod(
        "ParameterDefaultInvalidIntegerCall",
        ExecutorVoidType(),
        noParameters
    )
    invalidIntegerType: Type? = typeof(string)
    assert !ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        invalidInteger.GetILGenerator(),
        typeof(int),
        1,
        "not-an-int",
        registry,
        out invalidIntegerType
    )
    assert invalidIntegerType == null

    rejected := BoundDynamicMethod(
        "ParameterDefaultRejectedCall",
        ExecutorVoidType(),
        noParameters
    )
    rejectedType: Type? = typeof(string)
    assert !ColumnarParameterDefaultEmitter.TryEmitConstructorDefaultArgument(
        rejected.GetILGenerator(),
        typeof(int),
        4,
        "\"wrong\"",
        registry,
        out rejectedType
    )
    assert rejectedType == null
}

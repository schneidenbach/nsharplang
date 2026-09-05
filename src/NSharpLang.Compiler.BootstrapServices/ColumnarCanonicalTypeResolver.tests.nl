namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit
import System.Threading.Tasks


// These tests stay at the resolver boundary: they build a real semantic catalog and call the
// canonical owner's Type-out and selected-reference surfaces directly.
func CanonicalResolverBaselineResolution(): ColumnarSemanticTypeResolution {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "import System\nimport System.Collections.Generic\ntype CanonicalResolverE = System.DayOfWeek\nfunc CanonicalResolverAnchor(): int { return 0 }\n"
    fileNames[0] = "canonical-resolver/baseline.nl"
    return SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )
}

func CanonicalResolverThrowsArgumentException(
    canonical: string,
    resolution: ColumnarSemanticTypeResolution
): bool {
    resolved := typeof(string)
    try {
        ignored := ColumnarCanonicalTypeResolver.TryResolveType(
            canonical,
            resolution.Enums,
            resolution.Structs,
            resolution.Unions,
            out resolved
        )
        _ = ignored
    } catch ex: Exception {
        return ex as ArgumentException != null
    }
    return false
}

func CanonicalResolverSelectedKey(
    canonical: string,
    resolution: ColumnarSemanticTypeResolution,
    expectedType: Type
): ColumnarStructuralTypeKey {
    selected := ColumnarSelectedTypeReference.Missing(
        resolution.Structs.StructuralTypeReferences
    )
    if !ColumnarCanonicalTypeResolver.TrySelectRuntimeType(
        canonical,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out selected
    ) {
        throw new InvalidOperationException("Expected canonical resolution to succeed.")
    }
    if selected.RuntimeType != expectedType {
        throw new InvalidOperationException("Canonical resolution selected the wrong runtime type.")
    }
    key := selected.Key
    if key == null {
        throw new InvalidOperationException("Successful canonical resolution did not select a structural key.")
    }
    return key
}

func CanonicalResolverAssertExternalGenericOne(
    key: ColumnarStructuralTypeKey,
    argumentPrimitiveName: string
) {
    assert key.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert key.ChildCount == 2
    assert key.Child(0).Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert key.Child(1).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert key.Child(1).PrimitiveName == argumentPrimitiveName
}

func CanonicalResolverAssertExternalGenericTwo(
    key: ColumnarStructuralTypeKey,
    firstPrimitiveName: string,
    secondPrimitiveName: string
) {
    assert key.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert key.ChildCount == 3
    assert key.Child(0).Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition
    assert key.Child(1).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert key.Child(1).PrimitiveName == firstPrimitiveName
    assert key.Child(2).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert key.Child(2).PrimitiveName == secondPrimitiveName
}

func CanonicalResolverExpectedResultType(): Type {
    definition := typeof(object)
    if !ColumnarTypeOfPlanner.TryResolveRuntimeGenericDefinition(
        "NSharpLang.Runtime.Result`2",
        "NSharpLang.Runtime",
        out definition
    ) {
        throw new InvalidOperationException("The Result runtime generic definition was not found.")
    }
    arguments := new Type[](2)
    arguments[0] = typeof(int)
    arguments[1] = typeof(string)
    return definition.MakeGenericType(arguments)
}

// The pinned estate compiler does not admit every closed generic through its `typeof` surface.
// These expected values are therefore constructed from the same runtime metadata definitions that
// the resolver is required to select.
func CanonicalResolverRuntimeGenericDefinition(fullName: string): Type {
    definition := Type.GetType(fullName + ", System.Private.CoreLib")
    if definition == null || !definition.get_IsGenericTypeDefinition() {
        throw new InvalidOperationException("The runtime generic definition '" + fullName + "' was not found.")
    }
    return definition
}

func CanonicalResolverRuntimeType(fullName: string): Type {
    resolved := Type.GetType(fullName + ", System.Private.CoreLib")
    if resolved == null {
        throw new InvalidOperationException("The runtime type '" + fullName + "' was not found.")
    }
    return resolved
}

func CanonicalResolverClosedOne(fullName: string, first: Type): Type {
    arguments := new Type[](1)
    arguments[0] = first
    return CanonicalResolverRuntimeGenericDefinition(fullName).MakeGenericType(arguments)
}

func CanonicalResolverClosedTwo(fullName: string, first: Type, second: Type): Type {
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return CanonicalResolverRuntimeGenericDefinition(fullName).MakeGenericType(arguments)
}

test "canonical resolver preserves scalar success and an unclaimed null miss" {
    resolution := CanonicalResolverBaselineResolution()

    resolved := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "int",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    assert resolved == typeof(int)

    resolved = typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "MissingCanonicalResolverType",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    assert resolved == null
}

test "canonical resolver keeps named tuples and explicit ValueTuple admission distinct" {
    resolution := CanonicalResolverBaselineResolution()
    expected := CanonicalResolverClosedTwo(
        "System.ValueTuple`2",
        CanonicalResolverRuntimeType("System.DayOfWeek"),
        typeof(int)
    )

    named := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "(left:CanonicalResolverE,right:int)",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out named
    )
    assert named == expected

    explicitTuple := typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "ValueTuple<CanonicalResolverE,int>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out explicitTuple
    )
    assert explicitTuple == expected

    selected := ColumnarSelectedTypeReference.Missing(
        resolution.Structs.StructuralTypeReferences
    )
    assert !ColumnarCanonicalTypeResolver.TrySelectRuntimeType(
        "ValueTuple<CanonicalResolverE,int>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out selected
    )
    assert selected.HasRuntimeType
    assert selected.RuntimeType == expected
    assert selected.Key == null
}

test "canonical resolver preserves the generic manual-family fence and exact-map precedence" {
    resolution := CanonicalResolverBaselineResolution()
    ordinary := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "IReadOnlyList<int>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out ordinary
    )
    assert ordinary == CanonicalResolverClosedOne(
        "System.Collections.Generic.IReadOnlyList`1",
        typeof(int)
    )

    emptyMap := new Dictionary<string, Type>(StringComparer.Ordinal)
    generic := typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "IReadOnlyList<int>",
        emptyMap,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out generic
    )
    assert generic == null

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "type CanonicalResolverSelected = int\n"
    fileNames[0] = "canonical-resolver/map-precedence.nl"
    exactResolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )
    supplied := new Dictionary<string, Type>(StringComparer.Ordinal)
    supplied["CanonicalResolverSelected"] = typeof(string)
    exact := typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
        "CanonicalResolverSelected",
        supplied,
        exactResolution.Enums,
        exactResolution.Structs,
        exactResolution.Unions,
        out exact
    )
    assert exact == typeof(int)
}

test "canonical resolver retains byref and generic construction throw boundaries" {
    resolution := CanonicalResolverBaselineResolution()

    byRef := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveType(
        "&int",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out byRef
    )
    assert byRef == typeof(int).MakeByRefType()

    rejectedByRef := typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "&&int",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out rejectedByRef
    )
    assert rejectedByRef == null

    assert CanonicalResolverThrowsArgumentException("(&int,int)", resolution)

    wrongListArity := typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "List<int,(&int,int)>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out wrongListArity
    )
    assert wrongListArity == null

    wrongTupleArity := typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "ValueTuple<(&int,int)>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out wrongTupleArity
    )
    assert wrongTupleArity == null
}

test "canonical resolver resolves Func returns before parameter failure and arity rejection" {
    resolution := CanonicalResolverBaselineResolution()

    assert CanonicalResolverThrowsArgumentException(
        "Func<MissingCanonicalResolverType,(&int,int)>",
        resolution
    )

    missingParameter := typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveType(
        "Func<(&int,int),MissingCanonicalResolverType>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out missingParameter
    )
    assert missingParameter == null
}

test "canonical resolver composes closed source generic identities from the selected definition" {
    builder := TypeOfCreateSourceBuilder("CanonicalResolver.SourceBox", true)
    definition := ExactTypeDefinition(builder, "CanonicalResolver.SourceBox")
    structs := SemanticEmptyStructs()
    structs[definition.DeclaredTypeName] = definition

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "namespace CanonicalResolver\nclass SourceBox<T> {}\n"
    fileNames[0] = "canonical-resolver/source-generic.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        ""
    )

    selected := ColumnarSelectedTypeReference.Missing(
        resolution.Structs.StructuralTypeReferences
    )
    assert ColumnarCanonicalTypeResolver.TrySelectRuntimeType(
        "SourceBox<int>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out selected
    )
    assert selected.HasRuntimeType
    assert selected.RuntimeType.get_IsGenericType()
    assert ColumnarConstructionPlanner.SameObject(
        selected.RuntimeType.GetGenericTypeDefinition(),
        builder
    )
    selectedArguments := selected.RuntimeType.GetGenericArguments()
    assert selectedArguments.Length == 1
    assert selectedArguments[0] == typeof(int)
    key := selected.Key
    assert key != null
    if key == null {
        throw new InvalidOperationException("Closed source generic selection did not produce a structural key.")
    }
    assert key.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric
    assert key.ChildCount == 2
    definitionKey := key.Child(0)
    assert definitionKey.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition
    assert definitionKey.SourceDeclarationName == "CanonicalResolver.SourceBox"
    argumentKey := key.Child(1)
    assert argumentKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert argumentKey.PrimitiveName == "int32"
    assert resolution.Structs.StructuralTypeReferences.ValidatePair(
        selected,
        selected.RuntimeType
    )
}

test "canonical resolver selected references retain source provenance for erased string enums" {
    strings := new Dictionary<string, string>(StringComparer.Ordinal)
    strings["Ready"] = "ready"
    stringEnum := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        strings,
        "CanonicalResolver.StringTag"
    )
    otherStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    otherStrings["Ready"] = "other-ready"
    otherStringEnum := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        otherStrings,
        "CanonicalResolver.OtherStringTag"
    )
    enums := SemanticEmptyEnums()
    enums[stringEnum.DeclaredTypeName] = stringEnum
    enums[otherStringEnum.DeclaredTypeName] = otherStringEnum
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace CanonicalResolver\nenum StringTag: string { Ready = \"ready\" }\nenum OtherStringTag: string { Ready = \"other-ready\" }\n"
    sources[1] = "namespace CanonicalResolver.Caller\nimport CanonicalResolver\n"
    fileNames[0] = "canonical-resolver/string-tag.nl"
    fileNames[1] = "canonical-resolver/string-tag-caller.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        1,
        enums,
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )

    selected := ColumnarSelectedTypeReference.Missing(
        resolution.Structs.StructuralTypeReferences
    )
    assert ColumnarCanonicalTypeResolver.TrySelectRuntimeType(
        "StringTag",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out selected
    )
    assert selected.RuntimeType == typeof(string)
    assert selected.SourceProvenanceName == "CanonicalResolver.StringTag"
    key := selected.Key
    assert key != null
    if key == null {
        throw new InvalidOperationException("Erased source enum selection did not produce a structural key.")
    }
    assert key.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert key.PrimitiveName == "string"
    assert key.ChildCount == 0

    otherSelected := ColumnarSelectedTypeReference.Missing(
        resolution.Structs.StructuralTypeReferences
    )
    assert ColumnarCanonicalTypeResolver.TrySelectRuntimeType(
        "OtherStringTag",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out otherSelected
    )
    assert otherSelected.RuntimeType == typeof(string)
    assert otherSelected.SourceProvenanceName == "CanonicalResolver.OtherStringTag"
    otherKey := otherSelected.Key
    assert otherKey != null
    if otherKey == null {
        throw new InvalidOperationException("Second erased source enum selection did not produce a structural key.")
    }
    assert otherKey.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert otherKey.PrimitiveName == "string"
    assert otherKey.ChildCount == 0
    assert Object.ReferenceEquals(key, otherKey)
    assert selected.SourceProvenanceName != otherSelected.SourceProvenanceName
}

test "canonical resolver successful selections retain ordered structural shapes" {
    resolution := CanonicalResolverBaselineResolution()

    arrayKey := CanonicalResolverSelectedKey(
        "int[]",
        resolution,
        typeof(int).MakeArrayType()
    )
    assert arrayKey.Kind == ColumnarStructuralTypeReferenceKind.SzArray
    assert arrayKey.ChildCount == 1
    assert arrayKey.Child(0).Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert arrayKey.Child(0).PrimitiveName == "int32"

    nullableKey := CanonicalResolverSelectedKey(
        "int?",
        resolution,
        CanonicalResolverClosedOne("System.Nullable`1", typeof(int))
    )
    CanonicalResolverAssertExternalGenericOne(nullableKey, "int32")

    tupleKey := CanonicalResolverSelectedKey(
        "(left:string,right:int)",
        resolution,
        CanonicalResolverClosedTwo(
            "System.ValueTuple`2",
            typeof(string),
            typeof(int)
        )
    )
    CanonicalResolverAssertExternalGenericTwo(tupleKey, "string", "int32")

    funcKey := CanonicalResolverSelectedKey(
        "Func<int,string>",
        resolution,
        CanonicalResolverClosedTwo(
            "System.Func`2",
            typeof(int),
            typeof(string)
        )
    )
    CanonicalResolverAssertExternalGenericTwo(funcKey, "int32", "string")

    actionKey := CanonicalResolverSelectedKey(
        "Action<int>",
        resolution,
        CanonicalResolverClosedOne("System.Action`1", typeof(int))
    )
    CanonicalResolverAssertExternalGenericOne(actionKey, "int32")

    listKey := CanonicalResolverSelectedKey(
        "List<int>",
        resolution,
        CanonicalResolverClosedOne(
            "System.Collections.Generic.List`1",
            typeof(int)
        )
    )
    CanonicalResolverAssertExternalGenericOne(listKey, "int32")

    dictionaryKey := CanonicalResolverSelectedKey(
        "Dictionary<string,int>",
        resolution,
        CanonicalResolverClosedTwo(
            "System.Collections.Generic.Dictionary`2",
            typeof(string),
            typeof(int)
        )
    )
    CanonicalResolverAssertExternalGenericTwo(dictionaryKey, "string", "int32")

    taskKey := CanonicalResolverSelectedKey(
        "Task<int>",
        resolution,
        CanonicalResolverClosedOne(
            "System.Threading.Tasks.Task`1",
            typeof(int)
        )
    )
    CanonicalResolverAssertExternalGenericOne(taskKey, "int32")

    resultKey := CanonicalResolverSelectedKey(
        "Result<int,string>",
        resolution,
        CanonicalResolverExpectedResultType()
    )
    CanonicalResolverAssertExternalGenericTwo(resultKey, "int32", "string")
}

test "canonical resolver member and exact-runtime compatibility surfaces preserve their branches" {
    resolution := CanonicalResolverBaselineResolution()
    owner := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("CanonicalResolver.MemberOwner", false),
        "CanonicalResolver.MemberOwner"
    )
    parameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameters["T"] = typeof(int)
    owner.GenericParameters = parameters

    resolved := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveMemberType(
        "T",
        owner,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    assert resolved == typeof(int)

    owner.GenericParameters = null
    resolved = typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveMemberType(
        "int",
        owner,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out resolved
    )
    assert resolved == typeof(int)

    resolved = typeof(object)
    assert ColumnarCanonicalTypeResolver.TryResolveExactRuntimeType(
        "System.String",
        out resolved
    )
    assert resolved == typeof(string)
    resolved = typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveExactRuntimeType(
        "CanonicalResolver.MissingRuntimeType",
        out resolved
    )
    assert resolved == null
}

test "canonical resolver leaf maps preserve their false null contract and YAML identity" {
    builtin := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBuiltin("nint", out builtin)
    assert builtin == typeof(IntPtr)
    builtin = typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveBuiltin("Int32", out builtin)
    assert builtin == null

    exceptionType := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBclExceptionType(
        "System.ArgumentException",
        out exceptionType
    )
    assert exceptionType == typeof(ArgumentException)
    exceptionType = typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveBclExceptionType(
        "IOException",
        out exceptionType
    )
    assert exceptionType == null

    yaml := Type.GetType("YamlDotNet.Core.YamlException, YamlDotNet")
    assert yaml != null
    exceptionType = typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBclExceptionType(
        "YamlException",
        out exceptionType
    )
    assert exceptionType == yaml
}

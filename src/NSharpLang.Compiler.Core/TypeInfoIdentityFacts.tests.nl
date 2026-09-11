namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Text.Json
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

func IdentityTypeList(first: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(first)
    return result
}

func IdentityTypePair(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(first)
    result.Add(second)
    return result
}

func IdentityTuple(name: string?, elementType: TypeInfo): TupleTypeInfo {
    elements := new List<TupleTypeElementInfo>()
    elements.Add(new TupleTypeElementInfo(name, elementType))
    return new TupleTypeInfo(elements)
}

func IdentityFunction(parameterType: TypeInfo, returnType: TypeInfo): FunctionTypeInfo {
    result := new FunctionTypeInfo()
    result.ParameterTypes = IdentityTypeList(parameterType)
    result.ReturnType = returnType
    return result
}

func IdentityFunctionWithModifier(
    modifier: ParameterModifier,
    hasParams: bool
): FunctionTypeInfo {
    result := IdentityFunction(BuiltInTypes.Int, BuiltInTypes.String)
    modifiers := new List<ParameterModifier>()
    modifiers.Add(modifier)
    result.ParameterModifiers = modifiers
    result.HasParamsParameter = hasParams
    return result
}

func IdentityClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
}

func IdentityBake(builder: TypeBuilder): Type {
    createType := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "CreateType",
        new Type[](0)
    )
    value := TypeOfRequiredInvocation(
        createType,
        builder,
        new object[](0)
    )
    baked := value as Type
    if baked == null {
        throw new InvalidOperationException(
            "The identity fixture did not produce a runtime type."
        )
    }
    return baked
}

func IdentityRankedArrayType(elementType: Type, rank: int): Type {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    makeArrayType := ExecutorRequiredMethod(
        typeof(Type),
        "MakeArrayType",
        parameterTypes
    )
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, rank)
    value := TypeOfRequiredInvocation(
        makeArrayType,
        elementType,
        arguments
    )
    arrayType := value as Type
    if arrayType == null {
        throw new InvalidOperationException(
            "The identity fixture did not produce a ranked array type."
        )
    }
    return arrayType
}

func IdentityByRefType(elementType: Type): Type {
    makeByRefType := ExecutorRequiredMethod(
        typeof(Type),
        "MakeByRefType",
        new Type[](0)
    )
    value := TypeOfRequiredInvocation(
        makeByRefType,
        elementType,
        new object[](0)
    )
    byRefType := value as Type
    if byRefType == null {
        throw new InvalidOperationException(
            "The identity fixture did not produce a by-reference type."
        )
    }
    return byRefType
}

func IdentityRequiredRuntimeType(identity: string): Type {
    runtimeType := Type.GetType(identity)
    if runtimeType == null {
        throw new InvalidOperationException(
            "The identity fixture could not resolve runtime type '" + identity + "'."
        )
    }
    return runtimeType
}

func IdentityRuntimeGeneric(name: string, definition: Type): GenericTypeInfo {
    return new GenericTypeInfo(
        name,
        IdentityTypeList(BuiltInTypes.Int),
        new ReflectionTypeInfo(definition)
    )
}

func IdentityRuntimeGenericOf(
    name: string,
    definition: Type,
    elementType: TypeInfo
): GenericTypeInfo {
    return new GenericTypeInfo(
        name,
        IdentityTypeList(elementType),
        new ReflectionTypeInfo(definition)
    )
}

// The two-argument spelling the dictionary heads carry. `HasKnownRuntimeGenericDefinition` reads the
// DEFINITION rather than the argument count, but a one-argument fixture over a `` `2 `` definition
// would state something no real program can produce.
func IdentityRuntimeGenericPair(name: string, definition: Type): GenericTypeInfo {
    return new GenericTypeInfo(
        name,
        IdentityTypePair(BuiltInTypes.String, BuiltInTypes.Int),
        new ReflectionTypeInfo(definition)
    )
}

test "type info identity compares recursive structural shapes exactly" {
    assert TypeInfoIdentityFacts.AreEqual(
        new SimpleTypeInfo("int"),
        new SimpleTypeInfo("int")
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        new SimpleTypeInfo("int"),
        new SimpleTypeInfo("Int")
    )
    assert TypeInfoIdentityFacts.AreEqual(
        new ByRefTypeInfo(new ArrayTypeInfo(new SimpleTypeInfo("int"))),
        new ByRefTypeInfo(new ArrayTypeInfo(new SimpleTypeInfo("int")))
    )
    assert TypeInfoIdentityFacts.AreEqual(
        new NullableTypeInfo(new ObliviousTypeInfo(new SimpleTypeInfo("string"))),
        new NullableTypeInfo(new ObliviousTypeInfo(new SimpleTypeInfo("string")))
    )

    leftGeneric := new GenericTypeInfo(
        "Box",
        IdentityTypeList(new SimpleTypeInfo("int"))
    )
    rightGeneric := new GenericTypeInfo(
        "Box",
        IdentityTypeList(new SimpleTypeInfo("int"))
    )
    assert TypeInfoIdentityFacts.AreEqual(leftGeneric, rightGeneric)
    assert !TypeInfoIdentityFacts.AreEqual(
        leftGeneric,
        new GenericTypeInfo(
            "box",
            IdentityTypeList(new SimpleTypeInfo("int"))
        )
    )

    assert TypeInfoIdentityFacts.AreEqual(
        IdentityTuple("Value", new SimpleTypeInfo("int")),
        IdentityTuple("Value", new SimpleTypeInfo("int"))
    )
    assert TypeInfoIdentityFacts.AreEqual(
        IdentityTuple("Value", new SimpleTypeInfo("int")),
        IdentityTuple("value", new SimpleTypeInfo("int"))
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        IdentityTuple("Value", new SimpleTypeInfo("int")),
        IdentityTuple("Value", new SimpleTypeInfo("string"))
    )
    assert TypeInfoIdentityFacts.AreEqual(
        new AnonymousUnionTypeInfo(IdentityTypePair(
            new SimpleTypeInfo("int"),
            new SimpleTypeInfo("string")
        )),
        new AnonymousUnionTypeInfo(IdentityTypePair(
            new SimpleTypeInfo("int"),
            new SimpleTypeInfo("string")
        ))
    )
    assert TypeInfoIdentityFacts.AreEqual(
        IdentityFunction(new SimpleTypeInfo("int"), new SimpleTypeInfo("string")),
        IdentityFunction(new SimpleTypeInfo("int"), new SimpleTypeInfo("string"))
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        IdentityFunctionWithModifier(ParameterModifier.Ref, false),
        IdentityFunctionWithModifier(ParameterModifier.Out, false)
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        IdentityFunctionWithModifier(ParameterModifier.None, false),
        IdentityFunctionWithModifier(ParameterModifier.Params, false)
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        IdentityFunctionWithModifier(ParameterModifier.Params, false),
        IdentityFunctionWithModifier(ParameterModifier.Params, true)
    )
}

test "type info identity recognizes only exact admitted runtime generic definitions" {
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "IEnumerable",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.IEnumerable`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "IQueryable",
            IdentityRequiredRuntimeType(
                "System.Linq.IQueryable`1, System.Linq.Expressions"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "ICollection",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.ICollection`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "IList",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.IList`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "IReadOnlyCollection",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.IReadOnlyCollection`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "IReadOnlyList",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.IReadOnlyList`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "List",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.List`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "HashSet",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.HashSet`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "Queue",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.Queue`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "Stack",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.Stack`1, System.Collections"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "LinkedList",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.LinkedList`1, System.Collections"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "ISet",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.ISet`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "SortedSet",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.SortedSet`1, System.Collections"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "Collection",
            IdentityRequiredRuntimeType(
                "System.Collections.ObjectModel.Collection`1, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "ObservableCollection",
            IdentityRequiredRuntimeType(
                "System.Collections.ObjectModel.ObservableCollection`1, System.ObjectModel"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "System.Collections.Generic.List",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.List`1, System.Private.CoreLib"
            )
        )
    )

    // The three TWO-ARGUMENT heads. They are admitted here so the conversion row above them can be
    // reached at all: `IsKnownGenericConversion` already answers
    // `IReadOnlyDictionary` <- `Dictionary`/`SortedDictionary`, and the columnar emitter already
    // carries the matching upcast, but a conversion is never consulted until BOTH sides name a
    // definition this table knows. `SortedDictionary` lives in `System.Collections`, not in CoreLib.
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGenericPair(
            "Dictionary",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.Dictionary`2, System.Private.CoreLib"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGenericPair(
            "SortedDictionary",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.SortedDictionary`2, System.Collections"
            )
        )
    )
    assert TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGenericPair(
            "IReadOnlyDictionary",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.IReadOnlyDictionary`2, System.Private.CoreLib"
            )
        )
    )

    // `IDictionary<K, V>` is the head the table still does NOT carry, and it is the honest successor
    // to the `Dictionary` negative this contract used to state: no published conversion row names
    // it, so admitting it would publish a relation nothing implements.
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGenericPair(
            "IDictionary",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.IDictionary`2, System.Private.CoreLib"
            )
        )
    )
    // A dictionary head against the WRONG runtime definition is still refused: the table is an
    // identity check, not a name check.
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGenericPair(
            "Dictionary",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.SortedDictionary`2, System.Collections"
            )
        )
    )
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGenericPair(
            "IReadOnlyDictionary",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.Dictionary`2, System.Private.CoreLib"
            )
        )
    )
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        new GenericTypeInfo(
            "Dictionary",
            IdentityTypePair(BuiltInTypes.String, BuiltInTypes.Int)
        )
    )
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        IdentityRuntimeGeneric(
            "List",
            IdentityRequiredRuntimeType(
                "System.Collections.Generic.Queue`1, System.Private.CoreLib"
            )
        )
    )
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        new GenericTypeInfo("List", IdentityTypeList(BuiltInTypes.Int))
    )
    assert !TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition(
        new GenericTypeInfo(
            "List",
            IdentityTypeList(BuiltInTypes.Int),
            IdentityClass("List")
        )
    )
}

test "type info identity recognizes runtime and metadata delegate definitions exactly" {
    assert TypeInfoIdentityFacts.IsRuntimeDelegateDefinition(
        IdentityRuntimeGeneric(
            "Action",
            typeof(Action<int>).GetGenericTypeDefinition()
        )
    )
    assert TypeInfoIdentityFacts.IsRuntimeDelegateDefinition(
        IdentityRuntimeGeneric(
            "Func",
            typeof(Func<int>).GetGenericTypeDefinition()
        )
    )
    assert !TypeInfoIdentityFacts.IsRuntimeDelegateDefinition(
        IdentityRuntimeGeneric(
            "Action",
            typeof(List<int>).GetGenericTypeDefinition()
        )
    )

    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        core := context.LoadFromAssemblyName("System.Private.CoreLib")
        metadataAction := core.GetType("System.Action`1")
        assert metadataAction != null
        assert TypeInfoIdentityFacts.IsRuntimeDelegateDefinition(
            IdentityRuntimeGeneric("Action", metadataAction)
        )
    } finally {
        scan.Dispose()
    }
}

test "type info identity admits only the exact Span widening conversion" {
    runtimeSpan := typeof(Span<int>).GetGenericTypeDefinition()
    runtimeReadOnlySpan := typeof(ReadOnlySpan<int>).GetGenericTypeDefinition()
    spanInt := IdentityRuntimeGenericOf(
        "Span",
        runtimeSpan,
        BuiltInTypes.Int
    )
    readOnlySpanInt := IdentityRuntimeGenericOf(
        "ReadOnlySpan",
        runtimeReadOnlySpan,
        BuiltInTypes.Int
    )
    readOnlySpanString := IdentityRuntimeGenericOf(
        "ReadOnlySpan",
        runtimeReadOnlySpan,
        BuiltInTypes.String
    )

    assert TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(
        readOnlySpanInt,
        spanInt
    )
    assert !TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(
        spanInt,
        readOnlySpanInt
    )
    assert !TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(
        readOnlySpanString,
        spanInt
    )
    assert !TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(
        IdentityRuntimeGenericOf(
            "ReadOnlySpan",
            typeof(List<int>).GetGenericTypeDefinition(),
            BuiltInTypes.Int
        ),
        spanInt
    )
    assert !TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(
        readOnlySpanInt,
        IdentityRuntimeGenericOf(
            "Span",
            typeof(List<int>).GetGenericTypeDefinition(),
            BuiltInTypes.Int
        )
    )

    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        core := context.LoadFromAssemblyName("System.Private.CoreLib")
        metadataSpan := core.GetType("System.Span`1")
        metadataReadOnlySpan := core.GetType("System.ReadOnlySpan`1")
        assert metadataSpan != null
        assert metadataReadOnlySpan != null
        assert TypeInfoIdentityFacts.IsRuntimeSpanToReadOnlySpanConversion(
            IdentityRuntimeGenericOf(
                "ReadOnlySpan",
                metadataReadOnlySpan,
                BuiltInTypes.Int
            ),
            IdentityRuntimeGenericOf(
                "Span",
                metadataSpan,
                BuiltInTypes.Int
            )
        )
    } finally {
        scan.Dispose()
    }
}

test "type info identity admits only Int32-backed runtime enums" {
    assert TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(
        IdentityRequiredRuntimeType("System.AttributeTargets, System.Private.CoreLib")
    )
    assert !TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(typeof(JsonValueKind))
    assert !TypeInfoIdentityFacts.IsInt32BackedRuntimeEnum(typeof(int))
}

test "type info identity preserves canonical nominal declaration handles" {
    canonical := IdentityClass("Widget")
    sameDisplay := IdentityClass("Widget")
    assert TypeInfoIdentityFacts.AreEqual(canonical, canonical)
    assert !TypeInfoIdentityFacts.AreEqual(canonical, sameDisplay)

    canonicalBox := new GenericTypeInfo(
        "Box",
        IdentityTypeList(new SimpleTypeInfo("int")),
        canonical
    )
    sameDefinitionBox := new GenericTypeInfo(
        "Box",
        IdentityTypeList(new SimpleTypeInfo("int")),
        canonical
    )
    differentDefinitionBox := new GenericTypeInfo(
        "Box",
        IdentityTypeList(new SimpleTypeInfo("int")),
        sameDisplay
    )
    assert TypeInfoIdentityFacts.AreEqual(canonicalBox, sameDefinitionBox)
    assert !TypeInfoIdentityFacts.AreEqual(canonicalBox, differentDefinitionBox)
    assert TypeInfoIdentityFacts.AreEqual(
        new ExternalTypeInfo("Models.Widget"),
        new ExternalTypeInfo("Models.Widget")
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        new ExternalTypeInfo("Models.Widget"),
        new ExternalTypeInfo("models.Widget")
    )
    assert TypeInfoIdentityFacts.AreEqual(
        new UnknownTypeInfo(UnknownKind.ErrorRecovery),
        new UnknownTypeInfo(UnknownKind.ErrorRecovery)
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        new UnknownTypeInfo(UnknownKind.ErrorRecovery),
        new UnknownTypeInfo(UnknownKind.InferenceHole)
    )
    assert !TypeInfoIdentityFacts.AreEqual(
        new AliasTypeInfo(new SimpleTypeReference("int")),
        new AliasTypeInfo(new SimpleTypeReference("int"))
    )
}

test "type info identity compares recursive CLR identities" {
    leftArray := typeof(int).MakeArrayType()
    rightArray := typeof(int).MakeArrayType()
    assert TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftArray,
        rightArray
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftArray,
        typeof(string).MakeArrayType()
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftArray,
        IdentityRankedArrayType(typeof(int), 1)
    )

    leftByRef := IdentityByRefType(typeof(int))
    rightByRef := IdentityByRefType(typeof(int))
    assert TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftByRef,
        rightByRef
    )

    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    listInt := typeof(List<int>)
    listString := typeof(List<string>)
    assert TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        listInt,
        typeof(List<int>)
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        listInt,
        listString
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        listDefinition,
        listInt
    )
    assert TypeInfoIdentityFacts.AreEqual(
        new ReflectionTypeInfo(listInt),
        new ReflectionTypeInfo(typeof(List<int>))
    )

    listParameter := typeof(List<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    enumerableParameter := typeof(IEnumerable<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        listParameter,
        enumerableParameter
    )

    arrayEmpty := typeof(Array).GetMethod("Empty")
    arrayEmptyAgain := typeof(Array).GetMethod("Empty")
    convertAll := typeof(Array).GetMethod("ConvertAll")
    assert arrayEmpty != null
    assert arrayEmptyAgain != null
    assert convertAll != null
    arrayMethodParameter := arrayEmpty.GetGenericArguments()[0]
    sameArrayMethodParameter := arrayEmptyAgain.GetGenericArguments()[0]
    foreignMethodParameter := convertAll.GetGenericArguments()[0]
    assert TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        arrayMethodParameter,
        sameArrayMethodParameter
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        arrayMethodParameter,
        foreignMethodParameter
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        listParameter,
        arrayMethodParameter
    )

    leftBuilder := TypeOfCreateBuilder(
        "IdentityShape",
        "NSharpLang.Identity.Dynamic",
        1
    )
    rightBuilder := TypeOfCreateBuilder(
        "IdentityShape",
        "NSharpLang.Identity.Dynamic",
        1
    )
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftBuilder,
        rightBuilder
    )
    leftBuilderParameter := leftBuilder.GetGenericArguments()[0]
    rightBuilderParameter := rightBuilder.GetGenericArguments()[0]
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftBuilderParameter,
        rightBuilderParameter
    )

    leftBakedBuilder := TypeOfCreateBuilder(
        "IdentityBakedShape",
        "NSharpLang.Identity.BakedDynamic",
        0
    )
    rightBakedBuilder := TypeOfCreateBuilder(
        "IdentityBakedShape",
        "NSharpLang.Identity.BakedDynamic",
        0
    )
    leftBaked := IdentityBake(leftBakedBuilder)
    rightBaked := IdentityBake(rightBakedBuilder)
    assert !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
        leftBaked,
        rightBaked
    )
}

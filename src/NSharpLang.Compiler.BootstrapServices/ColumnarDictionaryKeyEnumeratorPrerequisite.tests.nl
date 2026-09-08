namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

func DictionaryKeyEnumeratorControlKeysType(key: Type, value: Type): Type {
    dictionary := DictionaryValueEnumeratorControlClosedDictionary(
        typeof(string),
        typeof(ColumnarStructDef)
    )
    keys := dictionary.GetProperty("Keys")
    if keys == null {
        throw new InvalidOperationException("Dictionary Keys property was not found.")
    }

    definition := keys.get_PropertyType().GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return definition.MakeGenericType(arguments)
}

func DictionaryKeyEnumeratorControlExactType(key: Type, value: Type): Type {
    keys := DictionaryKeyEnumeratorControlKeysType(
        typeof(string),
        typeof(ColumnarStructDef)
    )
    noTypes := new Type[](0)
    getEnumerator := keys.GetMethod("GetEnumerator", noTypes)
    if getEnumerator == null {
        throw new InvalidOperationException("Dictionary Keys.GetEnumerator was not found.")
    }

    definition := getEnumerator.get_ReturnType().GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return definition.MakeGenericType(arguments)
}

func DictionaryKeyEnumeratorControlForeignSameName(key: Type, value: Type): Type {
    dictionary := TypeOfCreateBuilder(
        "System.Collections.Generic.Dictionary`2",
        "ColumnarDictionaryKeyEnumeratorControls.Foreign",
        2
    )
    keys := DictionaryValueEnumeratorControlDefineNested(
        dictionary,
        "KeyCollection",
        2
    )
    enumerator := DictionaryValueEnumeratorControlDefineNested(
        keys,
        "Enumerator",
        2
    )
    foreignOpen := IdentityBake(enumerator)
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return foreignOpen.MakeGenericType(arguments)
}

test "dictionary Keys concrete enumerator admission requires the exact closed BCL shape" {
    sourceBuilder := TypeOfCreateBuilder(
        "DictionaryKeyEnumeratorControls.Source",
        "ColumnarDictionaryKeyEnumeratorControls.Source",
        0
    )
    exact := DictionaryKeyEnumeratorControlExactType(typeof(string), sourceBuilder)
    open := exact.GetGenericTypeDefinition()
    requiredDefinition := ColumnarTypeOfPlanner.RequiredDictionaryKeyEnumeratorDefinition()

    assert exact.get_IsGenericType()
    assert !exact.get_IsGenericTypeDefinition()
    assert open == requiredDefinition
    assert exact.GetGenericArguments().Length == 2
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(exact)
    assert ColumnarTypeOfPlanner.IsSupportedDictionaryKeyEnumeratorType(exact)
    assert ColumnarTypeOfPlanner.IsSupportedType(exact)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyEnumeratorType(open)
}

test "dictionary Keys concrete enumerator rejects foreign identity and sibling shapes" {
    sourceBuilder := TypeOfCreateBuilder(
        "DictionaryKeyEnumeratorControls.ForeignSource",
        "ColumnarDictionaryKeyEnumeratorControls.ForeignSource",
        0
    )
    requiredDefinition := ColumnarTypeOfPlanner.RequiredDictionaryKeyEnumeratorDefinition()
    keys := DictionaryKeyEnumeratorControlKeysType(typeof(string), sourceBuilder)
    sibling := DictionaryValueEnumeratorControlExactType(typeof(string), sourceBuilder)
    foreign := DictionaryKeyEnumeratorControlForeignSameName(typeof(string), sourceBuilder)

    foreignName := foreign.GetGenericTypeDefinition().get_FullName() ?? ""
    requiredName := requiredDefinition.get_FullName() ?? ""
    foreignAssembly := foreign.get_Assembly()
    requiredAssembly := requiredDefinition.get_Assembly()
    assert foreignName == requiredName
    assert !Object.ReferenceEquals(foreignAssembly, requiredAssembly)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyEnumeratorType(keys)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyEnumeratorType(sibling)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyEnumeratorType(foreign)
}

test "dictionary Keys concrete enumerator retains the collection element boundary" {
    sourceBuilder := TypeOfCreateBuilder(
        "DictionaryKeyEnumeratorControls.RejectedSource",
        "ColumnarDictionaryKeyEnumeratorControls.RejectedSource",
        0
    )
    sourceArray := sourceBuilder.MakeArrayType()
    rejected := DictionaryKeyEnumeratorControlExactType(
        typeof(string),
        sourceArray
    )

    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryKeyEnumeratorType(rejected)
    assert !ColumnarTypeOfPlanner.IsSupportedType(rejected)
}

test "dictionary Keys concrete enumerator selects exact acquisition movement Current and disposal" {
    sourceBuilder := TypeOfCreateBuilder(
        "DictionaryKeyEnumeratorControls.RouteSource",
        "ColumnarDictionaryKeyEnumeratorControls.RouteSource",
        0
    )
    keys := DictionaryKeyEnumeratorControlKeysType(typeof(string), sourceBuilder)
    enumerator := DictionaryKeyEnumeratorControlExactType(typeof(string), sourceBuilder)
    noArguments := new Type[](0)

    acquisition := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        keys,
        "GetEnumerator",
        noArguments,
        false
    )
    assert acquisition.IsSelected
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(
        acquisition.LookupType,
        keys
    )
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(
        acquisition.DeclaringType,
        keys
    )
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(
        acquisition.ReturnType,
        enumerator
    )
    assert acquisition.ReceiverIsReference
    assert acquisition.UsesCallVirtual

    movement := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "MoveNext",
        noArguments,
        false
    )
    assert movement.IsSelected
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(
        movement.DeclaringType,
        enumerator
    )
    assert movement.ReturnType == typeof(bool)
    assert !movement.ReceiverIsReference
    assert !movement.UsesCallVirtual

    current := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(
        enumerator,
        "Current",
        out current
    )
    getter := current.Getter
    if getter == null {
        throw new InvalidOperationException("Dictionary Keys enumerator Current getter was not selected.")
    }
    assert !current.IsField
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(
        current.DeclaringType,
        enumerator
    )
    assert current.ResultType == typeof(string)
    assert getter.get_Name() == "get_Current"
    assert getter.get_IsPublic()
    assert !getter.get_IsStatic()
    assert !current.ReceiverIsReference

    disposal := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "Dispose",
        noArguments,
        false
    )
    assert disposal.IsSelected
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(
        disposal.DeclaringType,
        enumerator
    )
    assert disposal.ReturnType == ColumnarTypeOfPlanner.RequiredVoidType()
    assert !disposal.ReceiverIsReference
    assert !disposal.UsesCallVirtual

    rejected := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(
        enumerator,
        "Value",
        out rejected
    )
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        enumerator,
        "Reset",
        noArguments,
        false
    ).IsNotFound
    wrongArity := new Type[](1)
    wrongArity[0] = typeof(int)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        keys,
        "GetEnumerator",
        wrongArity,
        false
    ).IsNotFound
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        keys,
        "GetEnumerator",
        noArguments,
        true
    ).IsNotFound
}

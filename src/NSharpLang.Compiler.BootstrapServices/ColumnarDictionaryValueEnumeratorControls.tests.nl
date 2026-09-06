namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// Construct the exact nested concrete enumerator through the public Dictionary Values property.
// The control never keeps a ValueCollection local: the l1 source form must acquire the enumerator
// directly from Values, just as the entry-point fallback does.
func DictionaryValueEnumeratorControlClosedDictionary(
    key: Type,
    value: Type
): Type {
    definition := typeof(Dictionary<string, ColumnarStructDef>).GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return definition.MakeGenericType(arguments)
}

func DictionaryValueEnumeratorControlValuesType(
    key: Type,
    value: Type
): Type {
    dictionary := DictionaryValueEnumeratorControlClosedDictionary(key, value)
    values := dictionary.GetProperty("Values")
    if values == null {
        throw new InvalidOperationException("Dictionary Values property was not found.")
    }

    return values.get_PropertyType()
}

func DictionaryValueEnumeratorControlExactType(
    key: Type,
    value: Type
): Type {
    // Discover the genuine nested BCL definition from a runtime-closed Dictionary once. A
    // Dictionary closed over a source TypeBuilder can reject GetProperty/GetMethod reflection,
    // but the exact definition can still be constructed with the intended arguments.
    valuesType := DictionaryValueEnumeratorControlValuesType(
        typeof(string),
        typeof(ColumnarStructDef)
    )
    noTypes := new Type[](0)
    getEnumerator := valuesType.GetMethod("GetEnumerator", noTypes)
    if getEnumerator == null {
        throw new InvalidOperationException("Dictionary Values.GetEnumerator was not found.")
    }
    definition := getEnumerator.get_ReturnType().GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return definition.MakeGenericType(arguments)
}

func DictionaryValueEnumeratorControlDefineNested(
    enclosing: TypeBuilder,
    name: string,
    genericParameterCount: int
): TypeBuilder {
    attributesType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder),
        "System.Reflection.TypeAttributes"
    )
    nestedSignature := new Type[](2)
    nestedSignature[0] = typeof(string)
    nestedSignature[1] = attributesType
    defineNested := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "DefineNestedType",
        nestedSignature
    )
    nestedArguments := new object[](2)
    ExecutorSetObject(nestedArguments, 0, name)
    ExecutorSetObject(
        nestedArguments,
        1,
        TypeOfRequiredStaticField(attributesType, "NestedPublic")
    )
    nestedValue := TypeOfRequiredInvocation(
        defineNested,
        enclosing,
        nestedArguments
    )
    nested := nestedValue as TypeBuilder
    if nested == null {
        throw new InvalidOperationException("Reflection.Emit did not return a nested TypeBuilder.")
    }

    if genericParameterCount > 0 {
        parameterSignature := new Type[](1)
        parameterSignature[0] = typeof(string[])
        defineParameters := ExecutorRequiredMethod(
            typeof(TypeBuilder),
            "DefineGenericParameters",
            parameterSignature
        )
        names := new string[](genericParameterCount)
        index := 0
        while index < names.Length {
            names[index] = "T" + index.ToString()
            index += 1
        }
        parameterArguments := new object[](1)
        ExecutorSetObject(parameterArguments, 0, names)
        TypeOfRequiredInvocation(defineParameters, nested, parameterArguments)
    }

    return nested
}

func DictionaryValueEnumeratorControlForeignSameName(
    key: Type,
    value: Type
): Type {
    // This is a real baked generic nested hierarchy with the BCL enumerator's FullName and arity,
    // but it belongs to a different assembly. A name-only predicate would accept its final node.
    dictionary := TypeOfCreateBuilder(
        "System.Collections.Generic.Dictionary`2",
        "ColumnarDictionaryValueEnumeratorControls.Foreign",
        2
    )
    values := DictionaryValueEnumeratorControlDefineNested(
        dictionary,
        "ValueCollection",
        2
    )
    enumerator := DictionaryValueEnumeratorControlDefineNested(
        values,
        "Enumerator",
        2
    )
    foreignOpen := IdentityBake(enumerator)
    arguments := new Type[](2)
    arguments[0] = key
    arguments[1] = value
    return foreignOpen.MakeGenericType(arguments)
}

test "dictionary Values enumerator admission requires the exact BCL nested definition" {
    exact := DictionaryValueEnumeratorControlExactType(
        typeof(string),
        typeof(ColumnarStructDef)
    )
    open := exact.GetGenericTypeDefinition()
    values := DictionaryValueEnumeratorControlValuesType(
        typeof(string),
        typeof(ColumnarStructDef)
    )
    foreign := DictionaryValueEnumeratorControlForeignSameName(
        typeof(string),
        typeof(ColumnarStructDef)
    )

    assert exact.get_IsGenericType()
    assert !exact.get_IsGenericTypeDefinition()
    assert exact.GetGenericArguments().Length == 2
    assert open.get_IsGenericTypeDefinition()
    foreignName := foreign.GetGenericTypeDefinition().get_FullName() ?? ""
    openName := open.get_FullName() ?? ""
    if foreignName != openName {
        throw new InvalidOperationException(
            "Foreign nested enumerator identity shape differed: expected " + openName + "; actual " + foreignName
        )
    }
    assert !Object.ReferenceEquals(foreign.get_Assembly(), open.get_Assembly())

    assert ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(exact)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(open)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(values)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(foreign)
}

test "dictionary Values enumerator admission retains dictionary argument and sibling-shape boundaries" {
    sourceBuilder := TypeOfCreateBuilder(
        "DictionaryValueEnumeratorControls.Source",
        "ColumnarDictionaryValueEnumeratorControls.Source",
        0
    )
    valueAllowed := DictionaryValueEnumeratorControlExactType(
        typeof(string),
        sourceBuilder
    )
    keyRejected := DictionaryValueEnumeratorControlExactType(
        sourceBuilder,
        typeof(ColumnarStructDef)
    )
    keyRejectedDictionary := DictionaryValueEnumeratorControlClosedDictionary(
        sourceBuilder,
        typeof(ColumnarStructDef)
    )
    valueRejected := DictionaryValueEnumeratorControlExactType(
        typeof(string),
        sourceBuilder.MakeArrayType()
    )
    genericOwner := TypeOfCreateBuilder(
        "DictionaryValueEnumeratorControls.Generic",
        "ColumnarDictionaryValueEnumeratorControls.Generic",
        1
    )
    parameters := genericOwner.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("Expected one generic-parameter key.")
    }
    genericKey := DictionaryValueEnumeratorControlExactType(
        parameters[0],
        sourceBuilder
    )
    openList := typeof(List<int>).GetGenericTypeDefinition()
    nestedOpenArguments := new Type[](1)
    nestedOpenArguments[0] = openList
    nestedOpenValue := openList.MakeGenericType(nestedOpenArguments)
    openKey := DictionaryValueEnumeratorControlExactType(openList, sourceBuilder)
    nestedOpenValueEnumerator := DictionaryValueEnumeratorControlExactType(
        typeof(string),
        nestedOpenValue
    )
    rankTwoKey := DictionaryValueEnumeratorControlExactType(
        typeof(string).MakeArrayType(2),
        sourceBuilder
    )
    runtimeDictionary := DictionaryValueEnumeratorControlClosedDictionary(
        typeof(string),
        typeof(ColumnarStructDef)
    )
    noTypes := new Type[](0)
    pairEnumerator := runtimeDictionary.GetMethod("GetEnumerator", noTypes)
    values := runtimeDictionary.GetProperty("Values")
    keys := runtimeDictionary.GetProperty("Keys")
    listEnumerator := typeof(List<ColumnarStructDef>).GetMethod(
        "GetEnumerator",
        noTypes
    )
    if pairEnumerator == null || values == null || keys == null || listEnumerator == null {
        throw new InvalidOperationException("Required BCL sibling enumerator surface was not found.")
    }
    valuesEnumerator := values.get_PropertyType().GetMethod(
        "GetEnumerator",
        noTypes
    )
    keysEnumerator := keys.get_PropertyType().GetMethod(
        "GetEnumerator",
        noTypes
    )
    if valuesEnumerator == null || keysEnumerator == null {
        throw new InvalidOperationException("Required Dictionary collection enumerator was not found.")
    }

    // The new exact predicate reuses Dictionary's key/value policy: source builders remain valid
    // VALUES, while a non-enum source builder is not a Dictionary KEY.
    assert ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(valueAllowed)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(keyRejected)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(valueRejected)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(genericKey)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(openKey)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(
        nestedOpenValueEnumerator
    )
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(rankTwoKey)
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(
        pairEnumerator.get_ReturnType()
    )
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(
        keysEnumerator.get_ReturnType()
    )
    assert !ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(
        listEnumerator.get_ReturnType()
    )

    // The broad storable-type question is different: a closed Dictionary can already be accepted
    // by an existing collection/catalog route.  This must not be used as evidence for the exact
    // concrete-enumerator predicate above.
    assert ColumnarTypeOfPlanner.IsSupportedType(keyRejectedDictionary)
}

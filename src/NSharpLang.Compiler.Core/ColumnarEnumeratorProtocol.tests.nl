namespace NSharpLang.Compiler.Columnar

import System

func EnumeratorProtocolRequiredType(fullName: string): Type {
    valueType := Type.GetType(fullName)
    if valueType == null {
        throw new InvalidOperationException("Required source-discovery protocol type was not found: " + fullName)
    }
    return valueType
}

func EnumeratorProtocolClosed1(fullName: string, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return EnumeratorProtocolRequiredType(fullName).MakeGenericType(arguments)
}

test "exact typed enumerators are admitted only as storable protocol state" {
    sourceReference := TypeOfCreateBuilder(
        "Contoso.SourceDiscovery.Row",
        "ColumnarSourceDiscoveryEnumeratorAdmission",
        0
    )
    sourceReferenceType: Type = sourceReference
    sourceValue := TypeOfCreateBuilder(
        "Contoso.SourceDiscovery.Value",
        "ColumnarSourceDiscoveryValueEnumeratorAdmission",
        0
    )
    sourceValueType: Type = sourceValue
    ConstructionSetParent(
        sourceValue,
        EnumeratorProtocolRequiredType("System.ValueType")
    )
    enumerator := EnumeratorProtocolClosed1(
        "System.Collections.Generic.IEnumerator`1",
        sourceReferenceType
    )
    valueEnumerator := EnumeratorProtocolClosed1(
        "System.Collections.Generic.IEnumerator`1",
        sourceValueType
    )
    enumerable := EnumeratorProtocolClosed1(
        "System.Collections.Generic.IEnumerable`1",
        sourceReferenceType
    )

    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(enumerator)
    assert ColumnarTypeOfPlanner.IsSupportedEnumeratorType(enumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(enumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(enumerator)
    assert ColumnarTypeOfPlanner.IsSupportedEnumeratorType(valueEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(valueEnumerator)

    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(enumerable)
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(enumerable)
    assert ColumnarTypeOfPlanner.IsSupportedType(enumerable)
    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(
        EnumeratorProtocolRequiredType("System.Collections.Generic.IEnumerator`1")
    )

    unsupportedDefinition := TypeOfCreateBuilder(
        "Contoso.SourceDiscovery.Box`1",
        "ColumnarSourceDiscoveryUnsupportedEnumeratorAdmission",
        1
    )
    unsupportedDefinitionType: Type = unsupportedDefinition
    unsupportedArguments := new Type[](1)
    unsupportedArguments[0] = typeof(int)
    unsupportedElement := unsupportedDefinitionType.MakeGenericType(unsupportedArguments)
    unsupportedEnumerator := EnumeratorProtocolClosed1(
        "System.Collections.Generic.IEnumerator`1",
        unsupportedElement
    )
    // THE PROTOCOL QUESTION AND THE STORAGE QUESTION ARE DIFFERENT QUESTIONS, and only the first
    // one is this predicate's. `IEnumerator<Box<int>>` over a closed SOURCE generic stores like any
    // other interface reference — the general external-construction arm says so — but the
    // enumerator PROTOCOL (acquire, MoveNext, typed Current, dispose) is driven by lowerings whose
    // element rule is `IsAdmissibleCollectionElement`, and that rule still refuses this element.
    // A foreach or a `for-in` over it therefore still declines at the site that would drive it.
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(unsupportedEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(unsupportedEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(unsupportedEnumerator)
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(unsupportedElement)

    foreignDefinition := IdentityBake(
        TypeOfCreateBuilder(
            "System.Collections.Generic.IEnumerator`1",
            "ColumnarSourceDiscoveryForeignEnumerator",
            1
        )
    )
    foreignArguments := new Type[](1)
    foreignArguments[0] = sourceReferenceType
    foreignEnumerator := foreignDefinition.MakeGenericType(foreignArguments)
    assert foreignEnumerator.GetGenericTypeDefinition().FullName == enumerator.GetGenericTypeDefinition().FullName
    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(foreignEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedType(foreignEnumerator)
}

test "the exact dictionary value enumerator retains a source value argument" {
    sourceReference := TypeOfCreateBuilder(
        "Contoso.EntryPoint.Definition",
        "ColumnarEntryPointDictionaryValueEnumeratorAdmission",
        0
    )
    sourceReferenceType: Type = sourceReference
    concreteEnumerator := AdmissibilityClosed2(
        "System.Collections.Generic.Dictionary`2+ValueCollection+Enumerator",
        typeof(string),
        sourceReferenceType
    )

    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(concreteEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedDictionaryValueEnumeratorType(concreteEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(concreteEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(concreteEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedCollectionType(concreteEnumerator)
}

test "IEnumerator admits the already-owned closed KeyValuePair shell with a source class value" {
    sourceReference := TypeOfCreateBuilder(
        "Contoso.Compilation.Unit",
        "ColumnarReadOnlyDictionaryEnumeratorAdmission",
        0
    )
    sourceReferenceType: Type = sourceReference
    pairArguments := new Type[](2)
    pairArguments[0] = typeof(string)
    pairArguments[1] = sourceReferenceType
    pairType := typeof(System.Collections.Generic.KeyValuePair<int, int>).GetGenericTypeDefinition().MakeGenericType(pairArguments)
    enumerator := EnumeratorProtocolClosed1(
        "System.Collections.Generic.IEnumerator`1",
        pairType
    )

    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(pairType)
    assert ColumnarTypeOfPlanner.IsSupportedKeyValuePairType(pairType)
    assert ColumnarTypeOfPlanner.IsSupportedEnumeratorType(enumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(enumerator)

    dictionaryArguments := new Type[](2)
    dictionaryArguments[0] = typeof(string)
    dictionaryArguments[1] = sourceReferenceType
    readOnlyDictionary := typeof(IReadOnlyDictionary<string, string>).GetGenericTypeDefinition().MakeGenericType(dictionaryArguments)
    acquisition := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        readOnlyDictionary,
        "GetEnumerator",
        new Type[](0),
        false
    )
    sequenceArguments := new Type[](1)
    sequenceArguments[0] = pairType
    sequence := typeof(IEnumerable<int>).GetGenericTypeDefinition().MakeGenericType(sequenceArguments)
    if !acquisition.IsSelected {
        throw new InvalidOperationException("The inherited IReadOnlyDictionary GetEnumerator selector was not selected.")
    }
    if acquisition.LookupType != readOnlyDictionary {
        throw new InvalidOperationException("The inherited IReadOnlyDictionary GetEnumerator selector lost its lookup type.")
    }
    if !ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(acquisition.DeclaringType, sequence) {
        throw new InvalidOperationException("The inherited IReadOnlyDictionary GetEnumerator selector lost its declaring sequence.")
    }
    if !ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(acquisition.ReturnType, enumerator) {
        throw new InvalidOperationException("The inherited IReadOnlyDictionary GetEnumerator selector returned the wrong enumerator.")
    }
    if !acquisition.UsesCallVirtual {
        throw new InvalidOperationException("The inherited IReadOnlyDictionary GetEnumerator selector lost virtual dispatch.")
    }
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        readOnlyDictionary,
        "Reset",
        new Type[](0),
        false
    ).IsNotFound
    wrongArityArguments := new Type[](1)
    wrongArityArguments[0] = typeof(int)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        readOnlyDictionary,
        "GetEnumerator",
        wrongArityArguments,
        false
    ).IsNotFound
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        readOnlyDictionary,
        "GetEnumerator",
        new Type[](0),
        true
    ).IsNotFound

    wrongKeyArguments := new Type[](2)
    wrongKeyArguments[0] = typeof(int)
    wrongKeyArguments[1] = sourceReferenceType
    wrongKeyDictionary := typeof(IReadOnlyDictionary<string, string>).GetGenericTypeDefinition().MakeGenericType(wrongKeyArguments)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        wrongKeyDictionary,
        "GetEnumerator",
        new Type[](0),
        false
    ).IsNotFound

    sourceValueDefinition := SourceCallDefinition(
        "ColumnarReadOnlyDictionaryEnumeratorAdmission.Value",
        false
    )
    sourceValueType: Type = sourceValueDefinition.Builder
    sourceValueArguments := new Type[](2)
    sourceValueArguments[0] = typeof(string)
    sourceValueArguments[1] = sourceValueType
    sourceValueDictionary := typeof(IReadOnlyDictionary<string, string>).GetGenericTypeDefinition().MakeGenericType(sourceValueArguments)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        sourceValueDictionary,
        "GetEnumerator",
        new Type[](0),
        false
    ).IsNotFound

    sourceArrayArguments := new Type[](2)
    sourceArrayArguments[0] = typeof(string)
    sourceArrayArguments[1] = sourceReferenceType.MakeArrayType()
    sourceArrayDictionary := typeof(IReadOnlyDictionary<string, string>).GetGenericTypeDefinition().MakeGenericType(sourceArrayArguments)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        sourceArrayDictionary,
        "GetEnumerator",
        new Type[](0),
        false
    ).IsNotFound

    sourceGenericDefinition := TypeOfCreateBuilder(
        "Contoso.Compilation.GenericUnit",
        "ColumnarReadOnlyDictionaryGenericEnumeratorAdmission",
        1
    )
    sourceGenericArguments := new Type[](1)
    sourceGenericArguments[0] = typeof(int)
    sourceGenericDefinitionType: Type = sourceGenericDefinition
    closedSourceGeneric := sourceGenericDefinitionType.MakeGenericType(sourceGenericArguments)
    closedSourceArguments := new Type[](2)
    closedSourceArguments[0] = typeof(string)
    closedSourceArguments[1] = closedSourceGeneric
    closedSourceDictionary := typeof(IReadOnlyDictionary<string, string>).GetGenericTypeDefinition().MakeGenericType(closedSourceArguments)
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        closedSourceDictionary,
        "GetEnumerator",
        new Type[](0),
        false
    ).IsNotFound
    // A DICTIONARY WITH NO BUILDER IN IT reaches the ordinary lookup, whose candidate sweep now
    // walks the base interfaces: `IReadOnlyDictionary<string, string>` inherits `GetEnumerator` from
    // `IEnumerable<KeyValuePair<string, string>>`, so it resolves like any other inherited interface
    // member. The rebinding arm above still owns the BUILDER-bound shapes, which reflection cannot
    // answer for at all.
    plainDictionaryAcquisition := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        typeof(IReadOnlyDictionary<string, string>),
        "GetEnumerator",
        new Type[](0),
        false
    )
    assert plainDictionaryAcquisition.IsSelected
    assert plainDictionaryAcquisition.LookupType == typeof(IReadOnlyDictionary<string, string>)
    assert plainDictionaryAcquisition.DeclaringType == typeof(IEnumerable<KeyValuePair<string, string>>)
    assert plainDictionaryAcquisition.UsesCallVirtual

    unsupportedArguments := new Type[](1)
    unsupportedArguments[0] = sourceReferenceType
    unsupportedElement := EnumeratorProtocolRequiredType("System.Tuple`1").MakeGenericType(unsupportedArguments)
    unsupportedEnumerator := EnumeratorProtocolClosed1(
        "System.Collections.Generic.IEnumerator`1",
        unsupportedElement
    )
    // `Tuple<SourceClass>` is not a key/value pair and is not a collection element, so this
    // enumerator is not storable PROTOCOL state and no enumeration lowering will drive it. It is
    // still an ordinary interface reference that a local or field may hold, which is all
    // `IsSupportedType` answers.
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(unsupportedEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedKeyValuePairType(unsupportedElement)
    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(unsupportedEnumerator)
    assert ColumnarTypeOfPlanner.IsSupportedType(unsupportedEnumerator)
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(unsupportedElement)

    // THE INHERITED-ENUMERATOR SELECTOR IS UNMOVED BY ANY OF THIS. Its rule is the receiver's exact
    // shape — a string key and one direct source-CLASS value — and not the admissibility of what it
    // would return, so every shape it already refused it still refuses.
    assert ColumnarTypeOfPlanner.IsSupportedType(
        EnumeratorProtocolClosed1(
            "System.Collections.Generic.IEnumerator`1",
            typeof(KeyValuePair<string, int>).GetGenericTypeDefinition().MakeGenericType(sourceValueArguments)
        )
    )
    assert ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(
        sourceValueDictionary,
        "GetEnumerator",
        new Type[](0),
        false
    ).IsNotFound
}

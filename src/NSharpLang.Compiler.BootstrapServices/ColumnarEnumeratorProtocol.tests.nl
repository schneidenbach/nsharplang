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
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(unsupportedEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedEnumeratorType(unsupportedEnumerator)
    assert !ColumnarTypeOfPlanner.IsSupportedType(unsupportedEnumerator)

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

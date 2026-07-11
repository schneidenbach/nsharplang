namespace NSharpLang.Compiler.Columnar

import System

func ReferenceConversionClosedType(definition: Type, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

test "structural reference facts admit every exact TypeBuilder-backed BCL interface edge" {
    element := SourceCallDefinition("ReferenceConversionElement", true)
    elementType: Type = element.Builder

    listType := ReferenceConversionClosedType(
        typeof(List<int>).GetGenericTypeDefinition(), elementType)
    hashSetType := ReferenceConversionClosedType(
        typeof(HashSet<int>).GetGenericTypeDefinition(), elementType)
    stackType := ReferenceConversionClosedType(
        typeof(Stack<int>).GetGenericTypeDefinition(), elementType)
    readOnlyListType := ReferenceConversionClosedType(
        typeof(IReadOnlyList<int>).GetGenericTypeDefinition(), elementType)
    readOnlySetType := ReferenceConversionClosedType(
        typeof(IReadOnlySet<int>).GetGenericTypeDefinition(), elementType)
    readOnlyCollectionType := ReferenceConversionClosedType(
        typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition(), elementType)
    enumerableType := ReferenceConversionClosedType(
        typeof(IEnumerable<int>).GetGenericTypeDefinition(), elementType)
    arrayType := elementType.MakeArrayType()

    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType, readOnlyListType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType, readOnlyCollectionType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType, enumerableType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        hashSetType, readOnlySetType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        hashSetType, readOnlyCollectionType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        hashSetType, enumerableType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlyListType, readOnlyCollectionType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlySetType, readOnlyCollectionType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        stackType, enumerableType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        arrayType, readOnlyListType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        arrayType, readOnlyCollectionType)
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        arrayType, enumerableType)
}

test "structural reference facts reject variance reversal unrelated shells and unequal arguments" {
    element := SourceCallDefinition("ReferenceConversionNearMissElement", true)
    elementType: Type = element.Builder

    listType := ReferenceConversionClosedType(
        typeof(List<int>).GetGenericTypeDefinition(), elementType)
    readOnlyListType := ReferenceConversionClosedType(
        typeof(IReadOnlyList<int>).GetGenericTypeDefinition(), elementType)
    readOnlySetType := ReferenceConversionClosedType(
        typeof(IReadOnlySet<int>).GetGenericTypeDefinition(), elementType)
    stringReadOnlyListType := ReferenceConversionClosedType(
        typeof(IReadOnlyList<int>).GetGenericTypeDefinition(), typeof(string))
    stringEnumerableType := ReferenceConversionClosedType(
        typeof(IEnumerable<int>).GetGenericTypeDefinition(), typeof(string))

    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlyListType, listType)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType, readOnlySetType)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType, stringReadOnlyListType)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        elementType.MakeArrayType(), stringEnumerableType)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType, listType)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        typeof(List<int>).GetGenericTypeDefinition(), readOnlyListType)
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        typeof(string), typeof(object))
}

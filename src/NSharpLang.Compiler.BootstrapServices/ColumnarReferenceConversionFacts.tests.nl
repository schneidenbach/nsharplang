namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

func ReferenceConversionClosedType(definition: Type, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

test "structural reference facts classify exact source interface edges and boxing" {
    target := SourceCallInterfaceDefinition(
        "ReferenceConversionSourceTarget"
    )
    derived := SourceCallInterfaceDefinition(
        "ReferenceConversionSourceDerived"
    )
    derived.InterfaceBases.Add(target)

    referenceImplementer := SourceCallDefinition(
        "ReferenceConversionSourceClass",
        true
    )
    referenceImplementer.ImplementedInterfaces.Add(target)
    inheritedImplementer := SourceCallDefinition(
        "ReferenceConversionInheritedClass",
        true
    )
    inheritedImplementer.ImplementedInterfaces.Add(derived)
    baseImplementer := SourceCallDefinition(
        "ReferenceConversionBaseClass",
        true
    )
    baseImplementer.ImplementedInterfaces.Add(target)
    derivedClass := SourceCallDefinition(
        "ReferenceConversionDerivedClass",
        true
    )
    derivedClass.BaseDef = baseImplementer
    valueImplementer := SourceCallDefinition(
        "ReferenceConversionSourceStruct",
        false
    )
    valueImplementer.ImplementedInterfaces.Add(target)

    definitions := new ColumnarStructDef[](7)
    definitions[0] = target
    definitions[1] = derived
    definitions[2] = referenceImplementer
    definitions[3] = inheritedImplementer
    definitions[4] = baseImplementer
    definitions[5] = derivedClass
    definitions[6] = valueImplementer

    sourceIsReference := false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        referenceImplementer.Builder,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        inheritedImplementer.Builder,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        derived.Builder,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        derivedClass.Builder,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = true
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        valueImplementer.Builder,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert !sourceIsReference
}

test "structural reference facts classify exact external interfaces through source hierarchies" {
    disposableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.IDisposable"
    )
    collectionType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.Collections.IList"
    )
    enumerableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.Collections.IEnumerable"
    )
    externalBase := SourceCallInterfaceDefinition(
        "ReferenceConversionExternalBase"
    )
    externalBase.ExternalInterfaces.Add(disposableType)
    externalBase.Builder.AddInterfaceImplementation(disposableType)
    derivedInterface := SourceCallInterfaceDefinition(
        "ReferenceConversionExternalDerived"
    )
    derivedInterface.InterfaceBases.Add(externalBase)
    derivedInterface.Builder.AddInterfaceImplementation(externalBase.Builder)

    directClass := SourceCallDefinition(
        "ReferenceConversionExternalClass",
        true
    )
    directClass.ExternalInterfaces.Add(disposableType)
    directClass.Builder.AddInterfaceImplementation(disposableType)
    directStruct := SourceCallDefinition(
        "ReferenceConversionExternalStruct",
        false
    )
    directStruct.ExternalInterfaces.Add(disposableType)
    directStruct.Builder.AddInterfaceImplementation(disposableType)
    interfaceClass := SourceCallDefinition(
        "ReferenceConversionExternalInterfaceClass",
        true
    )
    interfaceClass.ImplementedInterfaces.Add(derivedInterface)
    interfaceClass.Builder.AddInterfaceImplementation(
        derivedInterface.Builder
    )
    baseClass := SourceCallDefinition(
        "ReferenceConversionExternalBaseClass",
        true
    )
    baseClass.ExternalInterfaces.Add(disposableType)
    baseClass.Builder.AddInterfaceImplementation(disposableType)
    derivedClass := SourceCallDefinition(
        "ReferenceConversionExternalDerivedClass",
        true
    )
    derivedClass.BaseDef = baseClass

    collectionClass := SourceCallDefinition(
        "ReferenceConversionExternalCollectionClass",
        true
    )
    collectionClass.ExternalInterfaces.Add(collectionType)
    collectionClass.Builder.AddInterfaceImplementation(
        collectionType
    )

    definitions := new ColumnarStructDef[](8)
    definitions[0] = externalBase
    definitions[1] = derivedInterface
    definitions[2] = directClass
    definitions[3] = directStruct
    definitions[4] = interfaceClass
    definitions[5] = baseClass
    definitions[6] = derivedClass
    definitions[7] = collectionClass

    sourceIsReference := false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        directClass.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = true
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        directStruct.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert !sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        interfaceClass.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        derivedClass.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        derivedInterface.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference

    sourceIsReference = false
    assert ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        collectionClass.Builder,
        enumerableType,
        definitions,
        out sourceIsReference
    )
    assert sourceIsReference
}

test "structural reference facts reject same-spelled and unsupported external interface near misses" {
    disposableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.IDisposable"
    )
    comparableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.IComparable"
    )
    objectType := typeof(object)
    enumerableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.Collections.IEnumerable"
    )
    sameSpelled := SourceCallInterfaceDefinition(
        "ReferenceConversionExternalSameSpelled"
    )
    sameSpelled.DeclaredTypeName = "IDisposable"
    sameSpelledImplementer := SourceCallDefinition(
        "ReferenceConversionExternalSameSpelledClass",
        true
    )
    sameSpelledImplementer.ImplementedInterfaces.Add(sameSpelled)
    sameSpelledImplementer.Builder.AddInterfaceImplementation(
        sameSpelled.Builder
    )

    unrelated := SourceCallDefinition(
        "ReferenceConversionExternalUnrelatedClass",
        true
    )
    unrelated.ExternalInterfaces.Add(comparableType)
    unrelated.Builder.AddInterfaceImplementation(comparableType)
    exact := SourceCallDefinition(
        "ReferenceConversionExternalExactClass",
        true
    )
    exact.ExternalInterfaces.Add(disposableType)
    exact.Builder.AddInterfaceImplementation(disposableType)
    unregistered := SourceCallDefinition(
        "ReferenceConversionExternalUnregisteredClass",
        true
    )
    unregistered.Builder.AddInterfaceImplementation(disposableType)

    definitions := new ColumnarStructDef[](5)
    definitions[0] = sameSpelled
    definitions[1] = sameSpelledImplementer
    definitions[2] = unrelated
    definitions[3] = exact
    definitions[4] = unregistered

    sourceIsReference := true
    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        sameSpelledImplementer.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert !sourceIsReference

    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        unrelated.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        exact.Builder,
        comparableType,
        definitions,
        out sourceIsReference
    )
    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        exact.Builder,
        objectType,
        definitions,
        out sourceIsReference
    )
    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        exact.Builder,
        enumerableType,
        definitions,
        out sourceIsReference
    )
    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        unregistered.Builder,
        disposableType,
        definitions,
        out sourceIsReference
    )
}

test "structural reference facts reject same-spelled source interface near misses" {
    comparableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.IComparable"
    )
    target := SourceCallInterfaceDefinition(
        "ReferenceConversionExactTarget"
    )
    nearMiss := SourceCallInterfaceDefinition(
        "ReferenceConversionNearMissTarget"
    )
    target.DeclaredTypeName = "INotifier"
    nearMiss.DeclaredTypeName = "INotifier"

    implementer := SourceCallDefinition(
        "ReferenceConversionNearMissImplementer",
        true
    )
    implementer.ImplementedInterfaces.Add(nearMiss)

    definitions := new ColumnarStructDef[](3)
    definitions[0] = target
    definitions[1] = nearMiss
    definitions[2] = implementer

    sourceIsReference := true
    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        implementer.Builder,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert !sourceIsReference

    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        implementer.Builder,
        comparableType,
        definitions,
        out sourceIsReference
    )
}

test "structural reference facts exclude closed source interface shapes without substituted facts" {
    target := SourceCallInterfaceDefinition(
        "ReferenceConversionClosedSourceTarget"
    )
    genericTarget := SourceCallInterfaceDefinition(
        "ReferenceConversionClosedGenericTarget"
    )
    defineParameterTypes := new Type[](1)
    defineParameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "DefineGenericParameters",
        defineParameterTypes
    )
    parameterNames := new string[](1)
    parameterNames[0] = "T"
    defineArguments := new object[](1)
    ExecutorSetObject(defineArguments, 0, parameterNames)
    TypeOfRequiredInvocation(
        defineParameters,
        genericTarget.Builder,
        defineArguments
    )

    genericImplementer := SourceCallGenericDefinition(
        "ReferenceConversionClosedSourceImplementer"
    )
    genericImplementer.ImplementedInterfaces.Add(target)
    exactImplementer := SourceCallDefinition(
        "ReferenceConversionClosedTargetImplementer",
        true
    )
    exactImplementer.ImplementedInterfaces.Add(genericTarget)

    definitions := new ColumnarStructDef[](4)
    definitions[0] = target
    definitions[1] = genericTarget
    definitions[2] = genericImplementer
    definitions[3] = exactImplementer

    arguments := new Type[](1)
    arguments[0] = typeof(int)
    genericImplementerType: Type = genericImplementer.Builder
    genericTargetType: Type = genericTarget.Builder
    closedImplementer := genericImplementerType.MakeGenericType(arguments)
    closedTarget := genericTargetType.MakeGenericType(arguments)
    sourceIsReference := true

    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        closedImplementer,
        target.Builder,
        definitions,
        out sourceIsReference
    )
    assert !sourceIsReference

    assert !ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
        exactImplementer.Builder,
        closedTarget,
        definitions,
        out sourceIsReference
    )
}

test "structural reference facts admit every exact TypeBuilder-backed BCL interface edge" {
    element := SourceCallDefinition("ReferenceConversionElement", true)
    elementType: Type = element.Builder

    listType := ReferenceConversionClosedType(
        typeof(List<int>).GetGenericTypeDefinition(),
        elementType
    )
    hashSetType := ReferenceConversionClosedType(
        typeof(HashSet<int>).GetGenericTypeDefinition(),
        elementType
    )
    stackType := ReferenceConversionClosedType(
        typeof(Stack<int>).GetGenericTypeDefinition(),
        elementType
    )
    readOnlyListType := ReferenceConversionClosedType(
        typeof(IReadOnlyList<int>).GetGenericTypeDefinition(),
        elementType
    )
    readOnlySetType := ReferenceConversionClosedType(
        typeof(IReadOnlySet<int>).GetGenericTypeDefinition(),
        elementType
    )
    readOnlyCollectionType := ReferenceConversionClosedType(
        typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition(),
        elementType
    )
    enumerableType := ReferenceConversionClosedType(
        typeof(IEnumerable<int>).GetGenericTypeDefinition(),
        elementType
    )
    arrayType := elementType.MakeArrayType()

    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType,
        readOnlyListType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType,
        readOnlyCollectionType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType,
        enumerableType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        hashSetType,
        readOnlySetType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        hashSetType,
        readOnlyCollectionType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        hashSetType,
        enumerableType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlyListType,
        readOnlyCollectionType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlySetType,
        readOnlyCollectionType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlyListType,
        enumerableType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlySetType,
        enumerableType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlyCollectionType,
        enumerableType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        stackType,
        readOnlyCollectionType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        stackType,
        enumerableType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        arrayType,
        readOnlyListType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        arrayType,
        readOnlyCollectionType
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        arrayType,
        enumerableType
    )
}

test "structural reference facts reject variance reversal unrelated shells and unequal arguments" {
    element := SourceCallDefinition("ReferenceConversionNearMissElement", true)
    elementType: Type = element.Builder

    listType := ReferenceConversionClosedType(
        typeof(List<int>).GetGenericTypeDefinition(),
        elementType
    )
    readOnlyListType := ReferenceConversionClosedType(
        typeof(IReadOnlyList<int>).GetGenericTypeDefinition(),
        elementType
    )
    readOnlySetType := ReferenceConversionClosedType(
        typeof(IReadOnlySet<int>).GetGenericTypeDefinition(),
        elementType
    )
    stringReadOnlyListType := ReferenceConversionClosedType(
        typeof(IReadOnlyList<int>).GetGenericTypeDefinition(),
        typeof(string)
    )
    stringEnumerableType := ReferenceConversionClosedType(
        typeof(IEnumerable<int>).GetGenericTypeDefinition(),
        typeof(string)
    )

    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        readOnlyListType,
        listType
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType,
        readOnlySetType
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType,
        stringReadOnlyListType
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        elementType.MakeArrayType(),
        stringEnumerableType
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        listType,
        listType
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        typeof(List<int>).GetGenericTypeDefinition(),
        readOnlyListType
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        typeof(string),
        typeof(object)
    )
}

test "structural reference facts follow exact reordered dynamic generic base chains" {
    baseBuilder := TypeOfCreateBuilder(
        "ReferenceConversionMappedBase",
        "ColumnarReferenceConversionTests.ReferenceConversionMappedBase",
        2
    )
    baseType: Type = baseBuilder

    middleBuilder := TypeOfCreateBuilder(
        "ReferenceConversionMappedMiddle",
        "ColumnarReferenceConversionTests.ReferenceConversionMappedMiddle",
        1
    )
    middleType: Type = middleBuilder
    middleArguments := middleBuilder.GetGenericArguments()
    openBaseArguments := new Type[](2)
    openBaseArguments[0] = typeof(string)
    openBaseArguments[1] = middleArguments[0]
    ConstructionSetParent(
        middleBuilder,
        baseType.MakeGenericType(openBaseArguments)
    )

    derivedBuilder := TypeOfCreateBuilder(
        "ReferenceConversionMappedDerived",
        "ColumnarReferenceConversionTests.ReferenceConversionMappedDerived",
        2
    )
    derivedType: Type = derivedBuilder
    derivedArguments := derivedBuilder.GetGenericArguments()
    openMiddleArguments := new Type[](1)
    openMiddleArguments[0] = derivedArguments[1]
    ConstructionSetParent(
        derivedBuilder,
        middleType.MakeGenericType(openMiddleArguments)
    )

    closedDerivedArguments := new Type[](2)
    closedDerivedArguments[0] = typeof(int)
    closedDerivedArguments[1] = typeof(long)
    closedDerived := derivedType.MakeGenericType(closedDerivedArguments)
    closedMiddle := ReferenceConversionClosedType(
        middleType,
        typeof(long)
    )
    closedBaseArguments := new Type[](2)
    closedBaseArguments[0] = typeof(string)
    closedBaseArguments[1] = typeof(long)
    closedBase := baseType.MakeGenericType(closedBaseArguments)
    wrongBaseArguments := new Type[](2)
    wrongBaseArguments[0] = typeof(int)
    wrongBaseArguments[1] = typeof(long)
    wrongBase := baseType.MakeGenericType(wrongBaseArguments)

    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        closedDerived,
        closedMiddle
    )
    assert ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        closedDerived,
        closedBase
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        closedDerived,
        wrongBase
    )
    assert !ColumnarReferenceConversionFacts.IsExactKnownUpcast(
        closedBase,
        closedDerived
    )
}

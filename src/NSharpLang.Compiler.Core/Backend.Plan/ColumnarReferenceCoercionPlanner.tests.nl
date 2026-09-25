namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ReferenceCoercionRegistry(
    definitions: ColumnarStructDef[]
): Dictionary<string, ColumnarStructDef> {
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    index := 0
    while index < definitions.Length {
        definition := definitions[index]
        registry.Add(definition.DeclaredTypeName, definition)
        index += 1
    }
    return registry
}

func ReferenceCoercionIl(name: string): ILGenerator {
    method := BoundDynamicMethod(name, typeof(int), new Type[](0))
    return method.GetILGenerator()
}

func ReferenceCoercionBuilderIl(
    owner: TypeBuilder,
    name: string
): ILGenerator {
    method := owner.DefineMethod(
        name,
        (MethodAttributes)22,
        typeof(int),
        new Type[](0)
    )
    return method.GetILGenerator()
}

func ReferenceCoercionIlOffset(il: ILGenerator): int {
    return StructuralPoolRequiredIntProperty(il, "ILOffset")
}

func ReferenceCoercionGenericParameter(
    name: string,
    attributes: int
): Type {
    owner := TypeOfCreateBuilder(
        name,
        "ColumnarReferenceCoercionTests." + name,
        1
    )
    parameters := owner.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException(
            "The reference-coercion fixture did not define its generic parameter."
        )
    }
    parameterBuilder := parameters[0] as GenericTypeParameterBuilder
    if parameterBuilder == null {
        throw new InvalidOperationException(
            "The reference-coercion fixture did not expose a GenericTypeParameterBuilder."
        )
    }
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(GenericParameterAttributes)
    setter := ExecutorRequiredMethod(
        typeof(GenericTypeParameterBuilder),
        "SetGenericParameterAttributes",
        parameterTypes
    )
    arguments := new object[](1)
    ExecutorSetObject(
        arguments,
        0,
        (GenericParameterAttributes)attributes
    )
    setter.Invoke(parameterBuilder, arguments)
    return parameters[0]
}

test "reference coercion keeps exact source interface identities and boxes only value implementers" {
    target := SourceCallInterfaceDefinition(
        "ReferenceCoercionSourceTarget"
    )
    derived := SourceCallInterfaceDefinition(
        "ReferenceCoercionSourceDerived"
    )
    derived.InterfaceBases.Add(target)

    referenceImplementer := SourceCallDefinition(
        "ReferenceCoercionSourceClass",
        true
    )
    referenceImplementer.ImplementedInterfaces.Add(target)
    valueImplementer := SourceCallDefinition(
        "ReferenceCoercionSourceStruct",
        false
    )
    valueImplementer.ImplementedInterfaces.Add(derived)
    nearMiss := SourceCallInterfaceDefinition(
        "ReferenceCoercionSourceNearMiss"
    )
    nearMissImplementer := SourceCallDefinition(
        "ReferenceCoercionSourceNearMissClass",
        true
    )
    nearMissImplementer.ImplementedInterfaces.Add(nearMiss)
    unregistered := SourceCallDefinition(
        "ReferenceCoercionSourceUnregistered",
        true
    )
    unregistered.ImplementedInterfaces.Add(target)

    definitions := new ColumnarStructDef[](6)
    definitions[0] = target
    definitions[1] = derived
    definitions[2] = referenceImplementer
    definitions[3] = valueImplementer
    definitions[4] = nearMiss
    definitions[5] = nearMissImplementer
    registry := ReferenceCoercionRegistry(definitions)

    assert ColumnarReferenceCoercionPlanner.CanUseInterfaceUpcast(
        referenceImplementer.Builder,
        target.Builder,
        registry
    )
    assert ColumnarReferenceCoercionPlanner.CanUseInterfaceUpcast(
        valueImplementer.Builder,
        target.Builder,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseInterfaceUpcast(
        nearMissImplementer.Builder,
        target.Builder,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseInterfaceUpcast(
        unregistered.Builder,
        target.Builder,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseInterfaceUpcast(
        referenceImplementer.Builder,
        nearMiss.Builder,
        ReferenceCoercionRegistry(
            new ColumnarStructDef[](0)
        )
    )

    referenceIl := ReferenceCoercionIl(
        "ReferenceCoercionSourceReference"
    )
    referenceOffset := ReferenceCoercionIlOffset(referenceIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitInterfaceUpcast(
        referenceImplementer.Builder,
        target.Builder,
        registry,
        referenceIl
    )
    assert ReferenceCoercionIlOffset(referenceIl) == referenceOffset

    valueIl := ReferenceCoercionBuilderIl(
        valueImplementer.Builder,
        "ReferenceCoercionSourceValue"
    )
    valueOffset := ReferenceCoercionIlOffset(valueIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitInterfaceUpcast(
        valueImplementer.Builder,
        target.Builder,
        registry,
        valueIl
    )
    assert ReferenceCoercionIlOffset(valueIl) > valueOffset

    rejectedIl := ReferenceCoercionIl(
        "ReferenceCoercionSourceRejected"
    )
    rejectedOffset := ReferenceCoercionIlOffset(rejectedIl)
    assert !ColumnarReferenceCoercionPlanner.TryEmitInterfaceUpcast(
        nearMissImplementer.Builder,
        target.Builder,
        registry,
        rejectedIl
    )
    assert ReferenceCoercionIlOffset(rejectedIl) == rejectedOffset
}

test "reference coercion repeats exact external interface classification and value boxing" {
    disposableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.IDisposable"
    )
    listInterface := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.Collections.IList"
    )
    enumerableInterface := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.Collections.IEnumerable"
    )
    comparableType := TypeOfRequiredRuntimeType(
        typeof(Type),
        "System.IComparable"
    )

    referenceImplementer := SourceCallDefinition(
        "ReferenceCoercionExternalClass",
        true
    )
    referenceImplementer.ExternalInterfaces.Add(disposableType)
    valueImplementer := SourceCallDefinition(
        "ReferenceCoercionExternalStruct",
        false
    )
    valueImplementer.ExternalInterfaces.Add(disposableType)
    inheritedImplementer := SourceCallDefinition(
        "ReferenceCoercionExternalInherited",
        true
    )
    inheritedImplementer.ExternalInterfaces.Add(listInterface)

    definitions := new ColumnarStructDef[](3)
    definitions[0] = referenceImplementer
    definitions[1] = valueImplementer
    definitions[2] = inheritedImplementer
    registry := ReferenceCoercionRegistry(definitions)

    assert ColumnarReferenceCoercionPlanner.CanUseExternalInterfaceUpcast(
        referenceImplementer.Builder,
        disposableType,
        registry
    )
    assert ColumnarReferenceCoercionPlanner.CanUseExternalInterfaceUpcast(
        inheritedImplementer.Builder,
        enumerableInterface,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseExternalInterfaceUpcast(
        referenceImplementer.Builder,
        comparableType,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseExternalInterfaceUpcast(
        referenceImplementer.Builder,
        typeof(object),
        registry
    )

    referenceIl := ReferenceCoercionIl(
        "ReferenceCoercionExternalReference"
    )
    referenceOffset := ReferenceCoercionIlOffset(referenceIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast(
        referenceImplementer.Builder,
        disposableType,
        registry,
        referenceIl
    )
    assert ReferenceCoercionIlOffset(referenceIl) == referenceOffset

    inheritedIl := ReferenceCoercionIl(
        "ReferenceCoercionExternalInherited"
    )
    inheritedOffset := ReferenceCoercionIlOffset(inheritedIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast(
        inheritedImplementer.Builder,
        enumerableInterface,
        registry,
        inheritedIl
    )
    assert ReferenceCoercionIlOffset(inheritedIl) == inheritedOffset

    valueIl := ReferenceCoercionBuilderIl(
        valueImplementer.Builder,
        "ReferenceCoercionExternalValue"
    )
    valueOffset := ReferenceCoercionIlOffset(valueIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast(
        valueImplementer.Builder,
        disposableType,
        registry,
        valueIl
    )
    assert ReferenceCoercionIlOffset(valueIl) > valueOffset

    rejectedIl := ReferenceCoercionIl(
        "ReferenceCoercionExternalRejected"
    )
    rejectedOffset := ReferenceCoercionIlOffset(rejectedIl)
    assert !ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast(
        referenceImplementer.Builder,
        comparableType,
        registry,
        rejectedIl
    )
    assert ReferenceCoercionIlOffset(rejectedIl) == rejectedOffset
}

test "reference coercion object conversion preserves void rejection pass-through and required boxing" {
    referenceDefinition := SourceCallDefinition(
        "ReferenceCoercionObjectClass",
        true
    )
    valueDefinition := SourceCallDefinition(
        "ReferenceCoercionObjectStruct",
        false
    )
    definitions := new ColumnarStructDef[](2)
    definitions[0] = referenceDefinition
    definitions[1] = valueDefinition
    registry := ReferenceCoercionRegistry(definitions)
    unknownBuilder := TypeOfCreateBuilder(
        "ReferenceCoercionObjectUnknown",
        "ColumnarReferenceCoercionTests.ObjectUnknown",
        0
    )
    assert ColumnarReferenceCoercionPlanner.CanUseObjectConversion(
        typeof(string),
        typeof(object)
    )
    assert ColumnarReferenceCoercionPlanner.CanUseObjectConversion(
        typeof(int),
        typeof(object)
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseObjectConversion(
        ColumnarTypeOfPlanner.RequiredVoidType(),
        typeof(object)
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseObjectConversion(
        typeof(string),
        typeof(string)
    )

    referenceIl := ReferenceCoercionIl(
        "ReferenceCoercionObjectReference"
    )
    referenceOffset := ReferenceCoercionIlOffset(referenceIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        referenceDefinition.Builder,
        typeof(object),
        registry,
        referenceIl
    )
    assert ReferenceCoercionIlOffset(referenceIl) == referenceOffset

    objectIl := ReferenceCoercionIl("ReferenceCoercionObjectExact")
    objectOffset := ReferenceCoercionIlOffset(objectIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        typeof(object),
        typeof(object),
        registry,
        objectIl
    )
    assert ReferenceCoercionIlOffset(objectIl) == objectOffset

    unknownIl := ReferenceCoercionIl("ReferenceCoercionObjectUnknown")
    unknownOffset := ReferenceCoercionIlOffset(unknownIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        unknownBuilder,
        typeof(object),
        registry,
        unknownIl
    )
    assert ReferenceCoercionIlOffset(unknownIl) == unknownOffset

    valueIl := ReferenceCoercionBuilderIl(
        valueDefinition.Builder,
        "ReferenceCoercionObjectValue"
    )
    valueOffset := ReferenceCoercionIlOffset(valueIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        valueDefinition.Builder,
        typeof(object),
        registry,
        valueIl
    )
    assert ReferenceCoercionIlOffset(valueIl) > valueOffset

    integerIl := ReferenceCoercionIl("ReferenceCoercionObjectInteger")
    integerOffset := ReferenceCoercionIlOffset(integerIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        typeof(int),
        typeof(object),
        registry,
        integerIl
    )
    assert ReferenceCoercionIlOffset(integerIl) > integerOffset

    enumIl := ReferenceCoercionIl("ReferenceCoercionObjectEnum")
    enumOffset := ReferenceCoercionIlOffset(enumIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        typeof(DayOfWeek),
        typeof(object),
        registry,
        enumIl
    )
    assert ReferenceCoercionIlOffset(enumIl) > enumOffset

    rejectedIl := ReferenceCoercionIl("ReferenceCoercionObjectRejected")
    rejectedOffset := ReferenceCoercionIlOffset(rejectedIl)
    assert !ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        typeof(int),
        typeof(string),
        registry,
        rejectedIl
    )
    assert ReferenceCoercionIlOffset(rejectedIl) == rejectedOffset
}

test "reference coercion tests box value shapes and unconstrained parameters but retain class constraints" {
    referenceDefinition := SourceCallDefinition(
        "ReferenceCoercionTestClass",
        true
    )
    valueDefinition := SourceCallDefinition(
        "ReferenceCoercionTestStruct",
        false
    )
    definitions := new ColumnarStructDef[](2)
    definitions[0] = referenceDefinition
    definitions[1] = valueDefinition
    registry := ReferenceCoercionRegistry(definitions)
    unknownBuilder := TypeOfCreateBuilder(
        "ReferenceCoercionTestUnknown",
        "ColumnarReferenceCoercionTests.TestUnknown",
        0
    )
    enumBuilder := AdmissibilityEnumBuilder()
    unconstrained := ReferenceCoercionGenericParameter(
        "ReferenceCoercionUnconstrained",
        0
    )
    classConstrained := ReferenceCoercionGenericParameter(
        "ReferenceCoercionClassConstrained",
        4
    )

    assert !ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        referenceDefinition.Builder,
        registry
    )
    assert ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        valueDefinition.Builder,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        unknownBuilder,
        registry
    )
    assert ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        enumBuilder,
        registry
    )
    assert ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        typeof(int),
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        typeof(string),
        registry
    )
    assert ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        unconstrained,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.RequiresBoxBeforeReferenceTest(
        classConstrained,
        registry
    )

    genericOwner := TypeOfCreateBuilder(
        "ReferenceCoercionGenericBoxOwner",
        "ColumnarReferenceCoercionTests.GenericBoxOwner",
        1
    )
    genericParameters := genericOwner.GetGenericArguments()
    methodParameters := new Type[](1)
    methodParameters[0] = genericParameters[0]
    boxMethod := genericOwner.DefineMethod(
        "Box",
        (MethodAttributes)22,
        typeof(object),
        methodParameters
    )
    boxIl := boxMethod.GetILGenerator()
    boxIl.Emit(OpCodes.Ldarg_0)
    beforeBox := ReferenceCoercionIlOffset(boxIl)
    assert ColumnarReferenceCoercionPlanner.TryEmitObjectConversion(
        genericParameters[0],
        typeof(object),
        registry,
        boxIl
    )
    assert ReferenceCoercionIlOffset(boxIl) > beforeBox
    boxIl.Emit(OpCodes.Ret)
}

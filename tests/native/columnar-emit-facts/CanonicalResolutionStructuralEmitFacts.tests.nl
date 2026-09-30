namespace NSharpLang.ColumnarEmitFacts.Tests.CanonicalResolution

import System
import System.Reflection


// These declarations exercise canonical type selection through production metadata positions and
// through the typeof -> keyed type pool -> ldtoken route. The assertions derive expected runtime
// identities from constructed values so a shared spelling mistake cannot make both sides pass.
class CanonicalResolutionPayload {
}

class CanonicalResolutionBox<T> {
    Value: T
}

type CanonicalResolutionPayloadAlias = CanonicalResolutionPayload
type CanonicalResolutionClosedAlias = CanonicalResolutionBox<CanonicalResolutionPayload>

class CanonicalResolutionSignatures<T> {
    PayloadField: CanonicalResolutionPayloadAlias
    ClosedField: CanonicalResolutionClosedAlias
    TypeParameterField: T
    TypeParameterArrayField: T[]
    RuntimeListField: System.Collections.Generic.List<T>

    func ClosedRoundTrip(value: CanonicalResolutionClosedAlias): CanonicalResolutionClosedAlias {
        return value
    }

    func TypeParameterRoundTrip(value: T): T {
        return value
    }

    func TypeParameterType(): Type {
        return typeof(T)
    }

    func TypeParameterArrayType(): Type {
        return typeof(T[])
    }

    func OpenConstructedType(): Type {
        return typeof(CanonicalResolutionBox<T>)
    }
}

func CanonicalResolutionMethodParameterType<T>(): Type {
    return typeof(T)
}

func CanonicalResolutionRootType(): Type {
    return typeof(CanonicalResolutionPayload)
}

func CanonicalResolutionClosedType(): Type {
    return typeof(CanonicalResolutionBox<CanonicalResolutionPayload>)
}

func CanonicalResolutionAliasType(): Type {
    return typeof(CanonicalResolutionClosedAlias)
}

func CanonicalResolutionNestedArrayType(): Type {
    return typeof(CanonicalResolutionBox<CanonicalResolutionPayload>[])
}

func CanonicalResolutionComposedName(): string {
    return typeof(CanonicalResolutionBox<CanonicalResolutionPayload>).Name
}

func CanonicalResolutionBodyLocalType(): Type {
    selected := typeof(CanonicalResolutionBox<CanonicalResolutionPayload>)
    return selected
}

func CanonicalResolutionRequiredField(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing canonical-resolution field " + name)
    }
    return field
}

func CanonicalResolutionRuntimeType(value: object): Type {
    return value.GetType()
}

func CanonicalResolutionRequiredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Missing canonical-resolution method " + name)
    }
    return method
}

test "canonical resolution writes exact field return and parameter signatures" {
    payload := new CanonicalResolutionPayload()
    payloadRuntime := CanonicalResolutionRuntimeType(payload)
    closed := new CanonicalResolutionBox<CanonicalResolutionPayload>()
    closedRuntime := CanonicalResolutionRuntimeType(closed)
    runtimeListValue := new System.Collections.Generic.List<int>()
    runtimeList := CanonicalResolutionRuntimeType(runtimeListValue)
    carrier := new CanonicalResolutionSignatures<int>()
    carrierRuntime := CanonicalResolutionRuntimeType(carrier)

    assert CanonicalResolutionRequiredField(carrierRuntime, "PayloadField").get_FieldType() == payloadRuntime
    assert CanonicalResolutionRequiredField(carrierRuntime, "ClosedField").get_FieldType() == closedRuntime
    assert CanonicalResolutionRequiredField(carrierRuntime, "TypeParameterField").get_FieldType() == typeof(int)
    assert CanonicalResolutionRequiredField(carrierRuntime, "TypeParameterArrayField").get_FieldType() == typeof(int[])
    assert CanonicalResolutionRequiredField(carrierRuntime, "RuntimeListField").get_FieldType() == runtimeList

    closedMethod := CanonicalResolutionRequiredMethod(carrierRuntime, "ClosedRoundTrip")
    closedParameters := closedMethod.GetParameters()
    assert closedParameters.Length == 1
    assert closedMethod.get_ReturnType() == closedRuntime
    assert closedParameters[0].get_ParameterType() == closedRuntime

    genericMethod := CanonicalResolutionRequiredMethod(carrierRuntime, "TypeParameterRoundTrip")
    genericParameters := genericMethod.GetParameters()
    assert genericParameters.Length == 1
    assert genericMethod.get_ReturnType() == typeof(int)
    assert genericParameters[0].get_ParameterType() == typeof(int)
}

test "canonical typeof selection survives root composed and body-local positions" {
    payload := new CanonicalResolutionPayload()
    payloadRuntime := CanonicalResolutionRuntimeType(payload)
    closed := new CanonicalResolutionBox<CanonicalResolutionPayload>()
    closedRuntime := CanonicalResolutionRuntimeType(closed)
    closedArrayRuntime := closedRuntime.MakeArrayType()

    assert CanonicalResolutionRootType() == payloadRuntime
    assert CanonicalResolutionClosedType() == closedRuntime
    assert CanonicalResolutionAliasType() == closedRuntime
    assert CanonicalResolutionNestedArrayType() == closedArrayRuntime
    assert CanonicalResolutionComposedName() == closedRuntime.Name
    assert CanonicalResolutionBodyLocalType() == closedRuntime
}

test "canonical typeof selection keeps type and method generic owners distinct" {
    carrier := new CanonicalResolutionSignatures<int>()
    box := new CanonicalResolutionBox<int>()
    boxRuntime := CanonicalResolutionRuntimeType(box)

    assert carrier.TypeParameterType() == typeof(int)
    assert carrier.TypeParameterArrayType() == typeof(int[])
    assert carrier.OpenConstructedType() == boxRuntime
    assert CanonicalResolutionMethodParameterType<string>() == typeof(string)
    assert CanonicalResolutionMethodParameterType<int>() == typeof(int)
}

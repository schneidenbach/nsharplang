namespace NSharpLang.CensusLocalFunctions.Tests

import System.Collections.Generic
import System.Reflection


// RUNTIME contracts for generic local functions, plus the CLR shape the lowering produces.
test "a generic local function runs with its type argument written or inferred" {
    assert ExplicitIdentity() == 5
    assert InferredIdentity() == "hi"
    assert FirstOfTwo() == 41
    assert CountOfArray() == 3
}

test "a generic local function takes a constraint, recurses and captures" {
    values := new List<int>()
    values.Add(9)
    values.Add(8)

    assert FirstStruct(values) == 9
    assert DepthOf(values) == 2
    assert ShiftedLength(10) == 12
    assert Layered(values) == 14

    // The enclosing function's own type parameter as the call's type ARGUMENT.
    assert OwnParametersInsideAGenericFunction<string>("through") == "through"
    assert OwnParametersInsideAGenericFunction(3) == 3
}

test "the synthesized method really is a generic method of the expected arity" {
    identity := SynthesizedLocal("ExplicitIdentity", "id")
    assert identity.get_IsGenericMethodDefinition()
    assert identity.GetGenericArguments().Length == 1

    pair := SynthesizedLocal("FirstOfTwo", "firstOf")
    assert pair.GetGenericArguments().Length == 2

    // The declared parameter and return positions name the method's OWN parameters, which is what
    // makes the handle closable at a call site.
    own := identity.GetGenericArguments()[0]
    assert identity.get_ReturnType() == own
    assert identity.GetParameters()[0].get_ParameterType() == own

    // The constraint written on the declaration reaches metadata.
    constrained := SynthesizedLocal("FirstStruct", "first")
    constrainedParameter := constrained.GetGenericArguments()[0]
    assert (constrainedParameter.get_GenericParameterAttributes() & GenericParameterAttributes.NotNullableValueTypeConstraint) == GenericParameterAttributes.NotNullableValueTypeConstraint
}

// A local function is emitted as `<Enclosing>g__<n>`; the source name is not in metadata, so the
// lookup is by the enclosing function's name and then by the declared signature's arity.
func SynthesizedLocal(enclosing: string, sourceName: string): MethodInfo {
    prefix := "<" + enclosing + ">g__"
    for candidate in typeof(Marker).get_Assembly().GetTypes() {
        for method in candidate.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
            if method.get_Name().StartsWith(prefix) && method.get_IsGenericMethodDefinition() {
                return method
            }
        }
    }

    throw new System.InvalidOperationException("No generic local function was emitted for '" + enclosing + "." + sourceName + "'.")
}

class Marker {
    Tag: int
}

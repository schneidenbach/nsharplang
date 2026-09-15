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
    assert NoCaptureEnclosingType<int>(42) == 42
    assert NoCaptureEnclosingType<string>("outer") == "outer"
    assert CaptureEnclosingType<string>("captured") == "captured"
    marked := new GenericLocalMarked()
    marked.Value = "interface captured"
    assert CaptureEnclosingInterface<GenericLocalMarked>(marked).Value == "interface captured"
    derived := new GenericLocalDerived()
    derived.Value = "dependent"
    assert NoCaptureDependent<GenericLocalDerived, GenericLocalBase>(derived).Value == "dependent"
    assert CaptureEnclosingBase<GenericLocalDerived>(derived).Value == "dependent"
    assert NoCaptureNew<GenericLocalCreated>(new GenericLocalCreated()) != null
    assert LocalConstraintNamesEnclosing<string>("dependent local") == "dependent local"
    owner := new GenericLocalMemberOwner()
    assert owner.NoCapture<int>(84) == 84
    assert owner.NoCapture<string>("member outer") == "member outer"
    assert owner.Capture<string>("member captured") == "member captured"
}

test "enclosing and local type parameters retain their exact CLR owners and constraints" {
    captureFree := SynthesizedLocal("NoCaptureEnclosingType", "choose")
    copied := captureFree.GetGenericArguments()
    assert captureFree.get_IsStatic()
    assert copied.Length == 2
    assert copied[0].get_IsGenericMethodParameter()
    assert copied[1].get_IsGenericMethodParameter()
    assert captureFree.get_ReturnType() == copied[0]
    assert captureFree.GetParameters()[0].get_ParameterType() == copied[0]
    assert captureFree.GetParameters()[1].get_ParameterType() == copied[1]

    capturing := SynthesizedLocal("CaptureEnclosingType", "choose")
    owner := must capturing.get_DeclaringType()
    ownerParameters := owner.GetGenericArguments()
    ownParameters := capturing.GetGenericArguments()
    assert !capturing.get_IsStatic()
    assert owner.get_IsGenericTypeDefinition()
    assert ownerParameters.Length == 1
    assert ownParameters.Length == 1
    assert ownerParameters[0].get_IsGenericTypeParameter()
    assert ownParameters[0].get_IsGenericMethodParameter()
    assert ownerParameters[0].get_GenericParameterPosition() == 0
    assert ownParameters[0].get_GenericParameterPosition() == 0
    assert capturing.get_ReturnType() == ownerParameters[0]
    assert capturing.GetParameters()[0].get_ParameterType() == ownParameters[0]
    assert (ownerParameters[0].get_GenericParameterAttributes() & GenericParameterAttributes.ReferenceTypeConstraint) == GenericParameterAttributes.ReferenceTypeConstraint
    assert (ownParameters[0].get_GenericParameterAttributes() & GenericParameterAttributes.NotNullableValueTypeConstraint) == GenericParameterAttributes.NotNullableValueTypeConstraint

    interfaceCapturing := SynthesizedLocal("CaptureEnclosingInterface", "choose")
    interfaceOwner := must interfaceCapturing.get_DeclaringType()
    interfaceOwnerParameter := interfaceOwner.GetGenericArguments()[0]
    interfaceConstraints := interfaceOwnerParameter.GetGenericParameterConstraints()
    assert interfaceConstraints.Length == 1
    assert interfaceConstraints[0] == typeof(GenericLocalMarker)

    dependent := SynthesizedLocal("NoCaptureDependent", "choose")
    dependentParameters := dependent.GetGenericArguments()
    assert dependentParameters.Length == 3
    dependentConstraints := dependentParameters[0].GetGenericParameterConstraints()
    assert dependentConstraints.Length == 1
    assert dependentConstraints[0] == dependentParameters[1]
    assert (dependentParameters[1].get_GenericParameterAttributes() & GenericParameterAttributes.ReferenceTypeConstraint) == GenericParameterAttributes.ReferenceTypeConstraint

    baseCapturing := SynthesizedLocal("CaptureEnclosingBase", "choose")
    baseOwner := must baseCapturing.get_DeclaringType()
    baseConstraints := baseOwner.GetGenericArguments()[0].GetGenericParameterConstraints()
    assert baseConstraints.Length == 1
    assert baseConstraints[0] == typeof(GenericLocalBase)

    constructed := SynthesizedLocal("NoCaptureNew", "choose")
    constructedParameters := constructed.GetGenericArguments()
    assert constructedParameters.Length == 2
    assert (constructedParameters[0].get_GenericParameterAttributes() & GenericParameterAttributes.DefaultConstructorConstraint) == GenericParameterAttributes.DefaultConstructorConstraint

    localDependent := SynthesizedLocal("LocalConstraintNamesEnclosing", "choose")
    localDependentParameters := localDependent.GetGenericArguments()
    assert localDependentParameters.Length == 2
    localDependentConstraints := localDependentParameters[1].GetGenericParameterConstraints()
    assert localDependentConstraints.Length == 1
    assert localDependentConstraints[0] == localDependentParameters[0]

    memberCaptureFree := SynthesizedLocal("NoCapture", "choose")
    memberCopied := memberCaptureFree.GetGenericArguments()
    assert memberCopied.Length == 2
    assert memberCaptureFree.get_ReturnType() == memberCopied[0]
    assert memberCaptureFree.GetParameters()[1].get_ParameterType() == memberCopied[1]

    memberCapturing := SynthesizedLocal("Capture", "choose")
    memberOwner := must memberCapturing.get_DeclaringType()
    memberOwnerParameters := memberOwner.GetGenericArguments()
    memberOwnParameters := memberCapturing.GetGenericArguments()
    assert memberOwnerParameters.Length == 1
    assert memberOwnParameters.Length == 1
    assert memberCapturing.get_ReturnType() == memberOwnerParameters[0]
    assert memberCapturing.GetParameters()[0].get_ParameterType() == memberOwnParameters[0]
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

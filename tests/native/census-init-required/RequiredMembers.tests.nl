namespace NSharpLang.CensusInitRequired.Tests

import System.Collections.Generic
import System.Reflection


// RUNTIME: a creation that names every demanded member produces the values it named.
test "a creation that sets every required member carries those values" {
    user := new User {
        Id: "u-1",
        Name: "Alice"
    }

    assert user.Id == "u-1"
    assert user.Name == "Alice"
    assert user.Email == ""
}

test "a required property is written through its own accessor" {
    endpoint := new Endpoint {
        Host: "localhost",
        Port: 8080
    }

    assert endpoint.Host == "localhost"
    assert endpoint.Port == 8080
}

test "a constructor that promises to set the required members sets them" {
    preset := new Preset("fast")
    assert preset.Kind == "fast"
    assert preset.Describe() == "fast"
    assert preset.Weight == 0
}

test "required-member exemption follows ordinary reference and numeric constructor specificity" {
    specific := new SpecificPreset(new Poodle())
    numeric := new NumericPreset(1)
    assert specific.Kind == "dog"
    assert numeric.Kind == "long"
}

test "annotated generic struct and record constructors discharge their required members" {
    packet := new RequiredPacket<int>(7)
    receipt := new RequiredReceipt("r-1")
    assert packet.Value == 7
    assert receipt.Code == "r-1"
}

test "a required member declared by a base type is set through the derived creation" {
    leaf := new Leaf {
        Key: "k",
        Payload: 3
    }

    assert leaf.Key == "k"
    assert leaf.Payload == 3
}

test "a required member on a value type carries the value the creation gave it" {
    sample := new Sample {
        Value: 5,
        Weight: 2
    }

    assert sample.Value == 5
    assert sample.Weight == 2
}

test "an init-only member may also be required" {
    credentials := new Credentials {
        User: "root"
    }

    assert credentials.User == "root"
    assert credentials.Realm == "local"
}

// CLR METADATA: the attributes are the contract, and they are what a C# caller reads.
test "a required field carries RequiredMemberAttribute and so does its type" {
    field := typeof(User).GetField("Id")
    assert field != null
    assert MemberHasAttribute(field.GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")

    optional := typeof(User).GetField("Email")
    assert optional != null
    assert !MemberHasAttribute(optional.GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")

    assert MemberHasAttribute(typeof(User).GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")
}

test "a required property carries RequiredMemberAttribute on the property row" {
    property := typeof(Endpoint).GetProperty("Host")
    assert property != null
    assert MemberHasAttribute(property.GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")

    assert MemberHasAttribute(typeof(Endpoint).GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")
}

test "every constructor of a demanding type is guarded by CompilerFeatureRequired" {
    constructors := typeof(User).GetConstructors()
    assert constructors.Length == 1
    assert ConstructorRequiresRequiredMembersFeature(constructors[0])

    presetConstructors := typeof(Preset).GetConstructors()
    assert presetConstructors.Length == 1
    assert ConstructorRequiresRequiredMembersFeature(presetConstructors[0])
    assert MemberHasAttribute(presetConstructors[0].GetCustomAttributesData(), "System.Diagnostics.CodeAnalysis.SetsRequiredMembersAttribute")
}

test "a type that demands nothing carries no required-member metadata" {
    assert !MemberHasAttribute(typeof(Configuration).GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")

    constructors := typeof(Configuration).GetConstructors()
    assert constructors.Length == 1
    assert !ConstructorRequiresRequiredMembersFeature(constructors[0])
}

test "an init-only required member carries both markers" {
    property := typeof(Credentials).GetProperty("User")
    assert property != null
    assert MemberHasAttribute(property.GetCustomAttributesData(), "System.Runtime.CompilerServices.RequiredMemberAttribute")

    setter := property.SetMethod
    assert setter != null
    assert setter.ReturnParameter.GetRequiredCustomModifiers()[0].FullName == "System.Runtime.CompilerServices.IsExternalInit"
}

func MemberHasAttribute(attributes: IList<CustomAttributeData>, fullName: string): bool {
    for attribute in attributes {
        if attribute.AttributeType.FullName == fullName {
            return true
        }
    }

    return false
}

// `[CompilerFeatureRequired("RequiredMembers")]` is the guard that stops a compiler which does not
// understand the feature from constructing the type at all; the FEATURE NAME is the payload that
// makes it mean this feature rather than some other one.
func ConstructorRequiresRequiredMembersFeature(constructor: ConstructorInfo): bool {
    for attribute in constructor.GetCustomAttributesData() {
        if attribute.AttributeType.FullName == "System.Runtime.CompilerServices.CompilerFeatureRequiredAttribute" {
            arguments := attribute.ConstructorArguments
            if arguments.Count == 1 && (arguments[0].Value as string) == "RequiredMembers" {
                return true
            }
        }
    }

    return false
}

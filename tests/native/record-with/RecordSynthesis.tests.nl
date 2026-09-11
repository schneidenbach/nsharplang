namespace NSharpLang.RecordWith.Tests

import System
import System.Collections.Generic
import System.Reflection

// These fixtures cover the record-value-member driver rather than the existing `with` lowering
// controls.  The class and struct each have one baked primitive field, while the final two records
// see an unbaked source builder directly and inside an external constructed collection.
record RecordSynthesisReference {
    Value: int
}

record struct RecordSynthesisValue {
    Value: int
}

record RecordSynthesisUserOwned {
    Value: int

    override func Equals(_value: object): bool {
        return true
    }

    override func GetHashCode(): int {
        return 777
    }
}

class RecordSynthesisNested {
    Id: int
}

record RecordSynthesisBuilderField {
    Child: RecordSynthesisNested
}

record RecordSynthesisNestedCollection {
    Children: List<RecordSynthesisNested>
}

func RecordSynthesisNoParameters(): Type[] {
    return new Type[](0)
}

func RecordSynthesisObjectParameter(): Type[] {
    parameters := new Type[](1)
    parameters[0] = typeof(object)
    return parameters
}

func RecordSynthesisRequiredMethod(owner: Type, name: string, parameters: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameters)
    if method == null {
        throw new InvalidOperationException("Missing record synthesis member '" + name + "'.")
    }
    return method
}

func RecordSynthesisRequiredOwner(method: MethodInfo): Type {
    owner := method.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("A record synthesis member had no declaring type.")
    }
    return owner
}

// The precise one-field hash values are the current synthesized body: 17 * 23 + Value.  This
// simultaneously executes the generated Equals/GetHashCode bodies and distinguishes reference and
// value receivers from an inherited Object implementation.
test "record synthesis emits executable reference and value Equals and GetHashCode members" {
    reference := new RecordSynthesisReference { Value: 5 }
    sameReference := new RecordSynthesisReference { Value: 5 }
    differentReference := new RecordSynthesisReference { Value: 6 }
    assert reference.Equals(sameReference)
    assert !reference.Equals(differentReference)
    assert reference.GetHashCode() == 396

    value := new RecordSynthesisValue { Value: 8 }
    sameValue := new RecordSynthesisValue { Value: 8 }
    differentValue := new RecordSynthesisValue { Value: 9 }
    assert value.Equals(sameValue)
    assert !value.Equals(differentValue)
    assert value.GetHashCode() == 399

    referenceEquals := RecordSynthesisRequiredMethod(typeof(RecordSynthesisReference), "Equals", RecordSynthesisObjectParameter())
    referenceHash := RecordSynthesisRequiredMethod(typeof(RecordSynthesisReference), "GetHashCode", RecordSynthesisNoParameters())
    valueEquals := RecordSynthesisRequiredMethod(typeof(RecordSynthesisValue), "Equals", RecordSynthesisObjectParameter())
    valueHash := RecordSynthesisRequiredMethod(typeof(RecordSynthesisValue), "GetHashCode", RecordSynthesisNoParameters())
    assert RecordSynthesisRequiredOwner(referenceEquals) == typeof(RecordSynthesisReference)
    assert RecordSynthesisRequiredOwner(referenceHash) == typeof(RecordSynthesisReference)
    assert RecordSynthesisRequiredOwner(valueEquals) == typeof(RecordSynthesisValue)
    assert RecordSynthesisRequiredOwner(valueHash) == typeof(RecordSynthesisValue)
    assert Convert.ToInt32(referenceEquals.get_Attributes()) == 198
    assert Convert.ToInt32(referenceHash.get_Attributes()) == 198
    assert Convert.ToInt32(valueEquals.get_Attributes()) == 198
    assert Convert.ToInt32(valueHash.get_Attributes()) == 198
}

// User declarations have already claimed the two method slots, so the driver must leave their exact
// behavior and declaring identity intact while still synthesizing the independent reference clone.
test "record synthesis preserves user Equals and GetHashCode ownership while retaining clone synthesis" {
    left := new RecordSynthesisUserOwned { Value: 1 }
    right := new RecordSynthesisUserOwned { Value: 2 }
    changed := left with { Value: 3 }
    assert left.Equals(right)
    assert left.GetHashCode() == 777
    assert !Object.ReferenceEquals(left, changed)
    assert left.Value == 1
    assert changed.Value == 3

    equals := RecordSynthesisRequiredMethod(typeof(RecordSynthesisUserOwned), "Equals", RecordSynthesisObjectParameter())
    hash := RecordSynthesisRequiredMethod(typeof(RecordSynthesisUserOwned), "GetHashCode", RecordSynthesisNoParameters())
    clone := RecordSynthesisRequiredMethod(typeof(RecordSynthesisUserOwned), "<Clone>$", RecordSynthesisNoParameters())
    assert RecordSynthesisRequiredOwner(equals) == typeof(RecordSynthesisUserOwned)
    assert RecordSynthesisRequiredOwner(hash) == typeof(RecordSynthesisUserOwned)
    assert RecordSynthesisRequiredOwner(clone) == typeof(RecordSynthesisUserOwned)
    assert equals.get_ReturnType() == typeof(bool)
    assert hash.get_ReturnType() == typeof(int)
    assert clone.get_ReturnType() == typeof(RecordSynthesisUserOwned)
    assert Convert.ToInt32(clone.get_Attributes()) == 134
}

// Source builders remain unbaked when the record driver runs.  A direct source field and a source
// builder nested under List<T> both suppress the field-sensitive Equals/Hash bodies, yet their
// reference records still get an executable shallow clone because it has no field-type dependency.
test "builder-bound direct and nested collection fields skip value members but retain clone behavior" {
    originalChild := new RecordSynthesisNested { Id: 1 }
    original := new RecordSynthesisBuilderField { Child: originalChild }
    changed := original with { Child: new RecordSynthesisNested { Id: 2 } }
    assert !Object.ReferenceEquals(original, changed)
    assert original.Child.Id == 1
    assert changed.Child.Id == 2

    children := new List<RecordSynthesisNested>()
    nested := new RecordSynthesisNestedCollection { Children: children }
    nestedCopy := nested with { Children: children }
    assert nested.Children.Count == 0
    assert !Object.ReferenceEquals(nested, nestedCopy)
    originalChildren: object = nested.Children
    copiedChildren: object = nestedCopy.Children
    assert Object.ReferenceEquals(originalChildren, copiedChildren)

    builderEquals := RecordSynthesisRequiredMethod(typeof(RecordSynthesisBuilderField), "Equals", RecordSynthesisObjectParameter())
    builderHash := RecordSynthesisRequiredMethod(typeof(RecordSynthesisBuilderField), "GetHashCode", RecordSynthesisNoParameters())
    builderClone := RecordSynthesisRequiredMethod(typeof(RecordSynthesisBuilderField), "<Clone>$", RecordSynthesisNoParameters())
    assert RecordSynthesisRequiredOwner(builderEquals) == typeof(object)
    assert RecordSynthesisRequiredOwner(builderHash) == typeof(object)
    assert RecordSynthesisRequiredOwner(builderClone) == typeof(RecordSynthesisBuilderField)
    assert builderClone.get_ReturnType() == typeof(RecordSynthesisBuilderField)
    assert Convert.ToInt32(builderClone.get_Attributes()) == 134

    nestedEquals := RecordSynthesisRequiredMethod(typeof(RecordSynthesisNestedCollection), "Equals", RecordSynthesisObjectParameter())
    nestedHash := RecordSynthesisRequiredMethod(typeof(RecordSynthesisNestedCollection), "GetHashCode", RecordSynthesisNoParameters())
    nestedCloneMethod := RecordSynthesisRequiredMethod(typeof(RecordSynthesisNestedCollection), "<Clone>$", RecordSynthesisNoParameters())
    assert RecordSynthesisRequiredOwner(nestedEquals) == typeof(object)
    assert RecordSynthesisRequiredOwner(nestedHash) == typeof(object)
    assert RecordSynthesisRequiredOwner(nestedCloneMethod) == typeof(RecordSynthesisNestedCollection)
    assert nestedCloneMethod.get_ReturnType() == typeof(RecordSynthesisNestedCollection)
    assert Convert.ToInt32(nestedCloneMethod.get_Attributes()) == 134
}

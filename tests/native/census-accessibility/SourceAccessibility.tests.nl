namespace NSharpLang.CensusAccessibility.Tests

import System
import System.Reflection

func AccessibilityInstanceFlags(): BindingFlags {
    return BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
}

func AccessibilityFieldNamed(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name, AccessibilityInstanceFlags())
    if field == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no field named " + name + ".")
    }

    return field
}

func AccessibilityMethodOf(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name, AccessibilityInstanceFlags())
    if method == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no method named " + name + ".")
    }

    return method
}

test "a derived type reads its base's protected state through this, a bare name and base" {
    value := new AccessDerived()
    assert value.SeedThroughThis() == 3
    assert value.SeedThroughBareName() == 3
    assert value.SeedThroughBase() == 3
    assert value.DoubleThroughThis(4) == 8
    assert value.DoubleThroughBareName(4) == 8
    assert value.DoubleThroughBase(4) == 8
}

test "a derived type reads and writes a protected field of a sibling of its own type" {
    // The RECEIVER half of the protected rule, on its allowed side: the receiver is a value of the
    // accessing type, so the read is legal and returns the base's state.
    first := new AccessDerived()
    second := new AccessDerived()
    assert first.SeedOfSibling(second) == 3
    assert second.WriteSeed(21) == 21
    assert first.SeedOfSibling(second) == 21
    assert first.SeedThroughThis() == 3
}

test "protected reaches down the whole chain, not just one link" {
    grandchild := new AccessGrandchild()
    assert grandchild.SeedFromGrandchild() == 9
    assert grandchild.DescribeFromGrandchild() == "base/grandchild"
    assert grandchild.SeedThroughBase() == 3
}

test "a private member is readable from its own declaring type and emits as CLR private" {
    value := new AccessBase()
    assert value.RevealSecret() == 9
    assert value.TripleThroughPrivate(5) == 15

    owner := typeof(AccessBase)
    secret := AccessibilityFieldNamed(owner, "secretCount")
    assert secret.IsPrivate
    assert !secret.IsPublic
    assert !secret.IsFamily

    triple := AccessibilityMethodOf(owner, "PrivateTriple")
    assert triple.IsPrivate
    assert !triple.IsPublic
}

test "a protected member emits family accessibility, and protected internal emits family-or-assembly" {
    owner := typeof(AccessBase)
    seed := AccessibilityFieldNamed(owner, "Seed")
    assert seed.IsFamily
    assert !seed.IsPublic
    assert !seed.IsPrivate
    assert !seed.IsAssembly

    doubler := AccessibilityMethodOf(owner, "ProtectedDouble")
    assert doubler.IsFamily
    assert !doubler.IsPublic

    shared := AccessibilityFieldNamed(owner, "Shared")
    assert shared.IsFamilyOrAssembly
    assert !shared.IsPublic
    assert !shared.IsFamily

    open := AccessibilityFieldNamed(owner, "Open")
    assert open.IsPublic
}

test "protected internal and an unmarked member are readable from outside every type" {
    value := new AccessBase()
    assert SharedFromOutsideEveryType(value) == 5
    assert OpenFromOutsideEveryType(value) == 7
}

test "a second derived type has its own protected state, reached through its own this" {
    other := new AccessOtherDerived()
    assert other.SeedThroughThis() == 103
}

test "base. is a non-virtual call to the base body, observed through an override that counts" {
    counted := new Counted()
    assert counted.Calls == 0

    // Virtual dispatch reaches the override.
    assert counted.DescribeVirtually() == "counted"
    assert counted.Calls == 1

    // `base.` must NOT reach it: the base body runs and the counter does not move.
    assert counted.DescribeThroughBase() == "base"
    assert counted.Calls == 1
}

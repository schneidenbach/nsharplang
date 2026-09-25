namespace NSharpLang.CensusExplicitInterfaceImplementation.Tests

import System.Collections
import System.Collections.Generic
import System.Reflection


// WHAT THE EMITTED ASSEMBLY CARRIES, READ BACK OUT OF IT.
//
// The run-time rows beside this file prove the right method is CALLED. These prove the metadata is
// the metadata every other .NET language expects — which is a different claim, and the one a C#
// consumer of an N# assembly depends on. Each name below was measured against the BCL's own
// assemblies first: `List<T>` carries `System.Collections.IEnumerable.GetEnumerator`, and
// `Dictionary<TKey, TValue>` carries
// `System.Collections.Generic.ICollection<System.Collections.Generic.KeyValuePair<TKey,TValue>>.Add`.
func ShapeMembers(): BindingFlags {
    return BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic
}

test "the explicit member's CLR name is the interface spelled out, and the implicit one keeps its own" {
    bagType := typeof(Bag)

    explicitMethod := bagType.GetMethod("System.Collections.IEnumerable.GetEnumerator", ShapeMembers())
    assert explicitMethod != null

    implicitMethod := bagType.GetMethod("GetEnumerator", ShapeMembers())
    assert implicitMethod != null

    // TWO MEMBERS, TWO NAMES, ONE SIMPLE NAME. Without the qualification the second would collide
    // with the first, which is why an interface whose slots differ only in return type was
    // unimplementable before.
    assert explicitMethod.ReturnType == typeof(IEnumerator)
    assert implicitMethod.ReturnType == typeof(IEnumerator<string>)
}

test "an explicit member is private, final, virtual and newslot — and an implicit one is none of those" {
    bagType := typeof(Bag)
    explicitMethod := bagType.GetMethod("System.Collections.IEnumerable.GetEnumerator", ShapeMembers())
    assert explicitMethod != null
    assert explicitMethod.IsPrivate
    assert explicitMethod.IsFinal
    assert explicitMethod.IsVirtual
    assert (explicitMethod.Attributes & MethodAttributes.NewSlot) == MethodAttributes.NewSlot
    assert (explicitMethod.Attributes & MethodAttributes.HideBySig) == MethodAttributes.HideBySig

    // THE CONTROL, AND IT IS ABOUT ACCESSIBILITY RATHER THAN ABOUT THE SLOT BITS. An IMPLICIT member
    // that fills an interface slot is `virtual final newslot` too — it has to be, or interface
    // dispatch could not find it — so those three bits do not tell the two forms apart. What does is
    // `private` against `public`: the explicit member is not on the type's surface and the implicit
    // one is, which is the entire reachability rule in one metadata bit.
    implicitMethod := bagType.GetMethod("GetEnumerator", ShapeMembers())
    assert implicitMethod != null
    assert implicitMethod.IsPublic
    assert !implicitMethod.IsPrivate
    assert explicitMethod.IsPrivate
    assert !explicitMethod.IsPublic

    // And an ordinary member that fills NO slot carries none of the three, so the bits are not simply
    // on everything.
    add := bagType.GetMethod("Add", ShapeMembers())
    assert add != null
    assert !add.IsVirtual
    assert !add.IsFinal
}

test "the interface map names the explicit member for the slot it was written for" {
    bagType := typeof(Bag)

    untypedMap := bagType.GetInterfaceMap(typeof(IEnumerable))
    assert untypedMap.TargetMethods.Length == 1
    assert untypedMap.TargetMethods[0].Name == "System.Collections.IEnumerable.GetEnumerator"

    // AND THE GENERIC SLOT STILL GOES TO THE IMPLICIT MEMBER, which is what makes the pair meaningful.
    genericMap := bagType.GetInterfaceMap(typeof(IEnumerable<string>))
    assert genericMap.TargetMethods.Length == 1
    assert genericMap.TargetMethods[0].Name == "GetEnumerator"
}

test "two interfaces declaring one name produce two differently named members" {
    duplexType := typeof(Duplex)

    readerMethod := duplexType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.IReader.Read", ShapeMembers())
    scannerMethod := duplexType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.IScanner.Read", ShapeMembers())
    assert readerMethod != null
    assert scannerMethod != null

    // AND NOTHING IS CALLED `Read` ON THE TYPE. The whole point is that the name is not on the type's
    // own surface: a caller with a `Duplex` in hand has to say which interface it means.
    assert duplexType.GetMethod("Read", ShapeMembers()) == null
}

test "a value member's accessor carries the prefix INSIDE the qualification" {
    hiddenType := typeof(Hidden)

    getter := hiddenType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.ILabeled.get_Label", ShapeMembers())
    assert getter != null
    assert getter.IsPrivate
    assert getter.IsFinal
    assert getter.IsVirtual

    // `get_Namespace.ILabeled.Label` is the name this would carry if the prefix went on the outside,
    // and it is a name no consumer looks for.
    assert hiddenType.GetMethod("get_NSharpLang.CensusExplicitInterfaceImplementation.Tests.ILabeled.Label", ShapeMembers()) == null
    assert hiddenType.GetMethod("get_Label", ShapeMembers()) == null

    property := hiddenType.GetProperty("NSharpLang.CensusExplicitInterfaceImplementation.Tests.ILabeled.Label", ShapeMembers())
    assert property != null
    assert hiddenType.GetProperty("Label", ShapeMembers()) == null
}

test "a closed generic interface is spelled with its arguments, as Roslyn spells it" {
    boxType := typeof(StringBox)

    unwrap := boxType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.IBox<System.String>.Unwrap", ShapeMembers())
    assert unwrap != null
    assert unwrap.IsPrivate

    getter := boxType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.IBox<System.String>.get_Item", ShapeMembers())
    assert getter != null

    // The open spelling names nothing: a generic interface has one slot set per instantiation.
    assert boxType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.IBox.Unwrap", ShapeMembers()) == null
}

test "a type whose only implementation is explicit exposes nothing of that name" {
    silentType := typeof(Silent)

    assert silentType.GetMethod("Tick", ShapeMembers()) == null
    assert silentType.GetMethod("NSharpLang.CensusExplicitInterfaceImplementation.Tests.ICounter.Tick", ShapeMembers()) != null

    // The type's ordinary member is unaffected, so "nothing of that name" is not "nothing at all".
    assert silentType.GetMethod("Describe", ShapeMembers()) != null
}

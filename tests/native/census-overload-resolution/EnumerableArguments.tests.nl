namespace NSharpLang.CensusOverloadResolution.Tests

import Census.OverloadResolution.Library

// Every assertion is the VALUE the call produced: a chosen overload is only chosen if the IL calls
// it, and the packed `params object?[]` overload answers the argument's type name instead.
test "a static field read by its bare name joins its elements, whatever the element type" {
    Catalog.Reset()
    assert Catalog.JoinNames() == "x,y"
    assert Catalog.JoinCodes() == "a,b,c"
    assert Catalog.JoinNumbers() == "1,2"
    assert Catalog.JoinSequence() == "1,2"
    assert Catalog.JoinItems() == "tag:red,tag:blue"
    assert Catalog.JoinProperty() == "x,y"
    assert Catalog.QualifiedNumbers() == "1,2"
    assert new Catalog().FromInstanceBody() == "1;2"
}

test "a char separator and string.Concat bind the sequence overloads too" {
    Catalog.Reset()
    assert Catalog.JoinWithChar() == "x|y"
    assert Catalog.ConcatNames() == "xy"
    assert Catalog.ConcatNumbers() == "12"
}

test "an instance call on a static field's value binds the generic sequence overload" {
    Catalog.Reset()
    assert Catalog.AppendNumbers() == "1+2"
}

test "the same calls over locals agree, and a params call still packs" {
    results := JoinLocalShapes()
    assert results[0] == "p,q"
    assert results[1] == "r,s"
    assert results[2] == "4,5"
    assert results[3] == "tag:green"
    assert results[4] == "o,6"
    assert results[5] == "only"
    assert results[6] == "one,two"
}

test "a referenced assembly's static enumerables join, qualified and bare from a derived class" {
    Registry.Reset()
    qualified := JoinReferencedQualified()
    assert qualified[0] == "north,south"
    assert qualified[1] == "3,5"
    assert qualified[2] == "entry:first,entry:second"
    assert qualified[3] == "north,south"
    assert RegistryView.BareNames() == "north,south"
    assert RegistryView.BareNumbers() == "3,5"
    assert RegistryView.BareEntries() == "entry:first,entry:second"
    assert RegistryView.BareLabels() == "north,south"
}

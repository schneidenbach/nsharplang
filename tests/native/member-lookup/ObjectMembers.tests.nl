namespace NSharpLang.MemberLookup.Tests

import System.Collections.Generic

test "ToString on an interface-typed value reaches object's member" {
    items: IList<int> = new List<int>()
    assert listText(items) == "System.Collections.Generic.List`1[System.Int32]"
}

test "GetType on an interface-typed value answers the runtime type" {
    items: IList<int> = new List<int>()
    assert listTypeName(items) == "List`1"
    sequence: IEnumerable<string> = new string[](0)
    assert sequenceTypeName(sequence) == "String[]"
}

test "GetHashCode and Equals on an interface-typed value dispatch to the runtime object" {
    items: IList<int> = new List<int>()
    same: object = items
    assert listHash(items) == (items as object).GetHashCode()
    assert listEquals(items, same)
    assert !listEquals(items, new List<int>())
}

test "an interface that declares its own ToString overload keeps object's ToString beside it" {
    assert formattedDefault(255) == "255"
    assert formattedHex(255) == "FF"
}

test "a type parameter constrained to an interface reaches object's members" {
    items := new List<int>()
    assert constrainedText(items) == "System.Collections.Generic.List`1[System.Int32]"
    assert constrainedTypeName(items) == "List`1"
}

test "a source interface keeps answering object's members" {
    assert shapeText(new Square()) == "square"
}

namespace NSharpLang.CensusFlowRules.Tests

test "a reference stores into an object array element without a workaround" {
    values := StoreReferenceIntoObjectArray("head")

    assert values.Length == 2
    assert (string)values[0] == "head"
    assert (string)values[1] == "literal"
}

test "a value stores into an object array element by boxing" {
    values := StoreValueIntoObjectArray(7)

    assert values[0].GetType() == typeof(int)
    assert (int)values[0] == 7
    assert values[1].GetType() == typeof(bool)
}

test "a derived reference stores into an interface-typed array element" {
    values := StoreDerivedIntoInterfaceArray("ada")

    assert values.Length == 1
    assert values[0].ReadName() == "ada"
}

test "the exact-match array element store is unchanged" {
    values := StoreIntoIntArray(3)

    assert values[0] == 3
    assert values[1] == 65
}

test "a cast to object emits, alone and inside an array literal" {
    assert (string)CastReferenceToObject("cast") == "cast"

    values := CastInsideArrayLiteral("both")
    assert values.Length == 2
    assert (string)values[0] == "both"
    assert (string)values[1] == "both"
}

test "a cast of a value to object inside an array literal boxes it" {
    values := CastValueToObjectInsideArrayLiteral(11)

    assert values.Length == 2
    assert values[0].GetType() == typeof(int)
    assert (int)values[0] == 11
    assert (string)values[1] == "tail"
}

test "a cast to an implemented interface emits" {
    assert CastToImplementedInterface("grace").ReadName() == "grace"
}

test "the downcast from object is unchanged" {
    boxed: object = "down"

    assert CastObjectBackToString(boxed) == "down"
}

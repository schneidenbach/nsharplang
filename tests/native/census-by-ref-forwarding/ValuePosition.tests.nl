namespace NSharpLang.CensusByRefForwarding.Tests

test "a &int parameter reads as its value and writes through to the caller" {
    slot := 1
    IncInt(ref slot)
    assert slot == 2
}

test "the & and ref spellings of one body do the same thing" {
    viaAmpersand := 10
    viaRef := 10
    IncInt(ref viaAmpersand)
    IncIntRef(ref viaRef)
    assert viaAmpersand == viaRef
    assert viaAmpersand == 11
}

test "compound assignment and increment write through a &int parameter" {
    slot := 1
    AddCompound(ref slot, 5)
    assert slot == 6
    PostIncrement(ref slot)
    assert slot == 7
}

test "compound assignment and decrement write through a &long parameter" {
    slot: long = 10
    CountDown(ref slot, 3)
    assert slot == 6
}

test "compound assignment and increment write through a ref parameter too" {
    slot := 1
    AddCompoundRef(ref slot, 5)
    assert slot == 7
}

test "compound string concatenation writes through a &string parameter" {
    text := "why"
    AppendQuestion(ref text)
    assert text == "why?"
}

test "a class REFERENCE is rebound through a &T parameter" {
    node := new Node("a")
    original := node
    RebindNode(ref node)
    assert node.Name == "x"
    assert original.Name == "a"
}

test "a struct is replaced whole through a &T parameter" {
    point := new Point { X: 1, Y: 2 }
    Replace(ref point)
    assert point.X == 2
    assert point.Y == 1
}

test "a &string parameter is read and rebound" {
    text := "hi"
    Exclaim(ref text)
    assert text == "hi!"
}

test "a generic swap through two &T parameters infers T from the arguments' storage" {
    a := 1
    b := 2
    Swap(ref a, ref b)
    assert a == 2
    assert b == 1

    first := "first"
    second := "second"
    Swap(ref first, ref second)
    assert first == "second"
    assert second == "first"

    // A STRUCT WIDER THAN A POINTER goes through the generic `&T` whole: the element is moved with
    // `ldobj`/`stobj !!T`, never as a pointer-sized reference, which would tear it.
    left := new Point { X: 1, Y: 2 }
    right := new Point { X: 3, Y: 4 }
    Swap(ref left, ref right)
    assert left.X == 3
    assert left.Y == 4
    assert right.X == 1
    assert right.Y == 2

    // `T` is inferred from the STORAGE each argument names, `string?`, not from a narrowed read.
    present: string? = "present"
    absent: string? = null
    Swap(ref present, ref absent)
    assert present == null
    assert absent == "present"
}

test "a read through a &int parameter is a copy that a later write does not reach" {
    slot := 5
    assert ReadThenOverwrite(ref slot) == 5
    assert slot == 100
}

test "a &int parameter's value is passed on by value" {
    slot := 4
    DoubleInPlace(ref slot)
    assert slot == 8
    other := 3
    assert Larger(ref slot, ref other) == 8
}

test "a &int parameter is compared and conditionally written" {
    negative := -3
    assert ClampToZero(ref negative)
    assert negative == 0

    positive := 3
    assert !ClampToZero(ref positive)
    assert positive == 3
}

test "a constructor's &int parameter is read and written through" {
    next := 1
    first := new Ticket(ref next)
    second := new Ticket(ref next)
    assert first.Number == 1
    assert second.Number == 2
    assert next == 3
}

test "a narrowed string? is passed by reference as its string? storage and sees the callee's null" {
    assert ClearedLength(true) == -1
    assert ClearedLength(false) == -1
    assert ExchangedLength() == 9
}

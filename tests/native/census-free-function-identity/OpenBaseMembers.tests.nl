namespace Census.FreeFunctionIdentity.OpenBase

import System.Collections.Generic


test "a bare call to a CLOSED external base's method is typed like its `this.` spelling" {
    names := new Names()
    names.Put("first")
    names.Put("second")

    assert names.FirstThis() == "first"
    assert names.FirstBare() == "first"
    assert names.SizeBare() == 2
}

test "`class Mid<U>: List<U>` reaches its open base's members through `this.` and bare, over a reference argument" {
    words := new Mid<string>()
    words.PutThis("a")
    words.PutBare("b")

    assert words.FirstThis() == "a"
    assert words.FirstBare() == "a"
    assert words.LastThis() == "b"
    assert words.SizeThis() == 2
    assert words.SizeBare() == 2
}

test "`class Mid<U>: List<U>` reaches its open base's members over a VALUE argument" {
    // A value `U` is where a wrong instantiation shows: `object` in the slot would box, and an
    // open `T` in the signature would not verify. The sum is only right if both reads return `int`.
    numbers := new Mid<int>()
    numbers.PutBare(40)
    numbers.PutThis(2)

    assert numbers.FirstThis() + numbers.LastThis() == 42
    assert numbers.FirstBare() == 40
    assert numbers.SizeBare() == 2
}

test "a member of `List<U>` over a FUNCTION's type parameter is typed with the spelled `U`" {
    words := new List<string>()
    words.Add("p")
    words.Add("q")
    numbers := new List<int>()
    numbers.Add(7)

    assert FirstOf(words) == "p"
    assert CountOf(words) == 2
    assert FirstOf(numbers) + CountOf(numbers) == 8
}

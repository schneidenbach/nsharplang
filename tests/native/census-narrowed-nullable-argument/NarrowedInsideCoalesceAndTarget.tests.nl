namespace NSharpLang.CensusNarrowedNullableArgument.Tests

// Read through a call: the flow keeps `kennel.Count = 4` as a fact about the path across the call
// that clears it, as C# keeps a property's null state across a method call.
func countOf(kennel: Kennel): int? {
    return kennel.Count
}

test "a narrowed reference passed inside the left operand of `??` reaches the call" {
    assert Narrowed.DescribeOrEmpty(new Dog("rex")) == "rex"
    assert Narrowed.DescribeOrEmpty(null) == "none"
    assert Narrowed.ParenthesizedOrEmpty(new Dog("fido")) == "fido"
    assert Narrowed.ParenthesizedOrEmpty(null) == "none"
}

test "a narrowed member path passed inside the left operand of `??` reaches the call" {
    kennel := new Kennel()
    assert Narrowed.ResidentOrEmpty(kennel) == "vacant"
    kennel.Resident = new Dog("max")
    assert Narrowed.ResidentOrEmpty(kennel) == "max"
}

test "a narrowed value nullable passed inside the left operand of `??` keeps the fallback live" {
    assert Narrowed.HalvedOrMinusOne(8) == 4
    assert Narrowed.HalvedOrMinusOne(7) == -1
    assert Narrowed.HalvedOrMinusOne(null) == -2
}

test "the operand itself keeps its nullable" {
    kennel := new Kennel()
    assert Narrowed.CountOrZero(kennel) == 0
    kennel.Count = 3
    assert Narrowed.CountOrZero(kennel) == 3
}

test "a narrowed name inside a write target indexes, and a compound write reads the same slot" {
    kennel := new Kennel()
    Narrowed.MarkSlot(kennel, new Dog("rex"))
    assert kennel.Slots[2] == 8
    Narrowed.MarkSlot(kennel, null)
    assert kennel.Slots[2] == 8

    kennel.Resident = new Dog("fido")
    Narrowed.MarkResidentSlot(kennel)
    assert kennel.Slots[3] == 5
}

test "a narrowed value nullable used as an index inside a write target or a `??` operand reads as its value" {
    kennel := new Kennel()
    Narrowed.MarkAt(kennel, 1)
    assert kennel.Slots[1] == 7
    Narrowed.MarkAt(kennel, null)
    assert kennel.Slots[0] == 0

    names: string?[] = ["ada", null]
    assert Narrowed.NameAtOrEmpty(names, 0) == "ada"
    assert Narrowed.NameAtOrEmpty(names, 1) == ""
    assert Narrowed.NameAtOrEmpty(names, null) == "none"
}

test "a narrowed name inside a write target's receiver, and a narrowed target assigned null" {
    grid: int[][] = [new int[1], new int[1], new int[1]]
    Narrowed.MarkRow(grid, new Dog("rex"))
    assert grid[2][0] == 9
    assert grid[1][0] == 0
    Narrowed.MarkRow(grid, null)
    assert grid[1][0] == 0

    dog := new Dog("max")
    kennel := new Kennel()
    kennel.Resident = dog
    Narrowed.Evict(kennel)
    assert kennel.Resident == null

    kennel.Count = 4
    Narrowed.ClearCount(kennel)
    assert countOf(kennel) == null
}

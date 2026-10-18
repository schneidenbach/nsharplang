namespace NSharpLang.NullableConversions.Tests

import System

test "a nullable coalesce into a nullable typed local keeps the nullable result" {
    assert CoalesceLocal(null, 2.5) == 2.5
    assert CoalesceLocal(1.5, 2.5) == 1.5
    assert CoalesceLocal(null, null) == null
}

test "a nullable coalesce returned from a nullable function keeps the nullable result" {
    assert CoalesceReturn(null, 2.5) == 2.5
    assert CoalesceReturn(1.5, 2.5) == 1.5
    assert CoalesceReturn(null, null) == null
}

test "a chained nullable coalesce yields the first present operand" {
    assert CoalesceChain(null, null, 3) == 3
    assert CoalesceChain(null, 2, 3) == 2
    assert CoalesceChain(1, 2, 3) == 1
    assert CoalesceChain(null, null, null) == null
}

test "an expression-bodied coalesce over DateTime? operands" {
    moment := new DateTime(2024, 1, 2)
    other := new DateTime(2025, 3, 4)
    assert CoalesceBody(null, moment) == moment
    assert CoalesceBody(other, moment) == other
    assert CoalesceBody(null, null) == null
}

test "a nullable coalesce unwrapped by a further coalesce" {
    assert CoalesceToValue(null, null) == -1.0
    assert CoalesceToValue(null, 4.0) == 4.0
    assert CoalesceToValue(2.0, 4.0) == 2.0
}

test "a coalesce with a plain right operand still unwraps" {
    assert CoalesceUnwrapped(null) == 0.5
    assert CoalesceUnwrapped(9.0) == 9.0
}

test "an int widens to long and lifts into a long? typed local" {
    assert WidenLocal(5) == 5L
    assert WidenLocal(-7) == -7L
}

test "an int widens to long and lifts on return" {
    assert WidenReturn(2147483647) == 2147483647L
}

test "an int? widens to long? preserving presence" {
    assert WidenNullable(null) == null
    assert WidenNullable(8) == 8L
}

test "an int widens to long and lifts into a long? member" {
    assert WidenField(11) == 11L
}

test "a conditional with a null arm takes the DateTime? member type" {
    moment := new DateTime(2024, 1, 2)
    assert MakeStamped(true, moment).When == moment
    assert MakeStamped(false, moment).When == null
    assert MakeStampedInverted(true, moment).When == null
    assert MakeStampedInverted(false, moment).When == moment
}

test "a conditional with a null arm assigned to a DateTime? member" {
    moment := new DateTime(2024, 1, 2)
    assert StampedByAssignment(true, moment).When == moment
    assert StampedByAssignment(false, moment).When == null
}

test "a (string, int) tuple converts to (string?, int?) element by element" {
    result := LiftedTuple()
    assert result.Item1 == "a"
    assert result.Item2 == 1
}

test "a tuple literal of plain values builds a (string?, int?) tuple" {
    result := LiftedTupleLocal("x", 7)
    assert result.Item1 == "x"
    assert result.Item2 == 7
}

test "a with replaces a nullable reference member with null" {
    named := new Airport { Latitude: 1.5, Name: "x", Opened: null }
    cleared := ClearName(named)
    assert cleared.Name == null
    assert cleared.Latitude == 1.5
    assert named.Name == "x"
}

test "a with can set a member to the nullable coalesce of two nullable values" {
    absent := new Airport { Latitude: null, Name: "a", Opened: null }
    present := new Airport { Latitude: 1.5, Name: "b", Opened: null }
    assert FillLatitude(absent, present).Latitude == 1.5
    assert FillLatitude(present, absent).Latitude == 1.5
    assert FillLatitude(absent, absent).Latitude == null
    assert FillLatitude(absent, present).Name == "a"
}

test "a with can set a nullable member from a conditional with a null arm" {
    moment := new DateTime(2024, 1, 2)
    start := new Airport { Latitude: null, Name: "a", Opened: null }
    assert SetOpened(start, true, moment).Opened == moment
    assert SetOpened(start, false, moment).Opened == null
}

test "a with lifts a plain value into a nullable member" {
    start := new Airport { Latitude: null, Name: "a", Opened: null }
    assert SetLatitude(start, 4.0).Latitude == 4.0
    assert WidenLatitude(start, 3).Latitude == 3.0
}

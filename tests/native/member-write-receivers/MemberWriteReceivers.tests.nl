namespace NSharpLang.MemberWriteReceivers.Tests

import System
import System.Collections.Generic

// ---- reference-typed receivers ------------------------------------------------------------------
test "a field write through a reference-typed array element changes the shared object" {
    d := new Dog()
    roster: Dog[] = [new Dog(), d]
    RenameFirst(roster, "max")
    assert roster[0].Name == "max"
    assert roster[1].Name == "rex"
}

test "a field write through a reference-typed call result changes the object the call returned" {
    d := new Dog()
    RenameThroughCall(d, "bo")
    assert d.Name == "bo"
}

test "a field write through a list indexer result changes the element the list holds" {
    dogs := new List<Dog>()
    dogs.Add(new Dog())
    RenameThroughList(dogs, "lulu")
    assert dogs[0].Name == "lulu"
}

test "parentheses around the receiver are transparent" {
    roster: Dog[] = [new Dog()]
    RenameThroughParens(roster, "paren")
    assert roster[0].Name == "paren"
}

test "a property setter runs through both receiver shapes" {
    d := new Dog()
    roster: Dog[] = [d]
    NicknameFirst(roster, "maxie")
    assert d.Nickname == "maxie"
    NicknameThroughCall(d, "bobo")
    assert d.Nickname == "bobo"
}

test "compound and postfix writes read and write the same object" {
    d := new Dog()
    roster: Dog[] = [d]
    AgeUpFirst(roster, 10)
    assert d.Age == 11
    BirthdayThroughCall(d)
    assert d.Age == 12
}

test "a value-typed field of a reference-typed receiver is written in place" {
    d := new Dog()
    roster: Dog[] = [d]
    MoveSpotFirst(roster, 3)
    MoveSpotThroughCall(d, 4)
    assert d.Spot.X == 3
    assert d.Spot.Y == 4
}

// ---- value-typed array elements -----------------------------------------------------------------

test "a field write to a value-typed array element changes the array's own slot" {
    points := new Point[](3)
    SetX(points, 1, 7)
    assert points[1].X == 7
    assert points[0].X == 0
    assert points[2].X == 0
}

test "a copy taken before the write keeps the old value" {
    points := new Point[](2)
    before := points[1]
    SetX(points, 1, 9)
    assert before.X == 0
    assert points[1].X == 9
}

test "compound and postfix writes to a value-typed array element land in the slot" {
    points := new Point[](2)
    AddToY(points, 1, 5)
    StepY(points, 1)
    assert points[1].Y == 6
}

test "a nested value-typed field of an array element is written through both addresses" {
    segments := new Segment[](2)
    SetEndX(segments, 1, 9)
    assert segments[1].End.X == 9
    assert segments[1].Start.X == 0
    assert segments[0].End.X == 0
}

test "a ref argument reaches a value-typed array element's field and a call result's field" {
    points := new Point[](1)
    BumpX(points, 0)
    assert points[0].X == 100
    d := new Dog()
    BumpAgeThroughCall(d)
    assert d.Age == 101
}

test "a ref argument to a reference-typed field passes the field's slot, not the object it holds" {
    d := new Dog()
    SwapName(d)
    assert d.Name == "swapped:rex"
    roster: Dog[] = [d]
    SwapNameFirst(roster)
    assert d.Name == "swapped:swapped:rex"
    SwapNameThroughCall(d)
    assert d.Name == "swapped:swapped:swapped:rex"
}

// ---- evaluation order ---------------------------------------------------------------------------

test "an array element's index is evaluated before the assigned value" {
    trace := new Trace()
    points := new Point[](3)
    TracedElementWrite(trace, points, 2, 11)
    assert trace.Text() == "index,value"
    assert points[2].X == 11
}

test "a call receiver is evaluated before the assigned value" {
    trace := new Trace()
    d := new Dog()
    TracedCallWrite(trace, d, 3)
    assert trace.Text() == "receiver,value"
    assert d.Age == 3
}

test "a compound write evaluates its call receiver exactly once" {
    trace := new Trace()
    d := new Dog()
    TracedCallCompound(trace, d, 4)
    assert trace.Text() == "receiver,value"
    assert d.Age == 5
}

test "an out-of-range element index throws before the assigned value is evaluated" {
    trace := new Trace()
    points := new Point[](1)
    assert throws IndexOutOfRangeException {
        TracedElementWrite(trace, points, 5, 1)
    }
    assert trace.Text() == "index"
}

test "a null reference-typed element throws after the assigned value is evaluated, as in C#" {
    trace := new Trace()
    roster := new Dog[](1)
    assert throws NullReferenceException {
        TracedNullElementWrite(trace, roster, 1)
    }
    assert trace.Text() == "value"
}

// ---- receivers rooted at the instance's own fields ---------------------------------------------

test "an element of the instance's own array field is written through both spellings" {
    kennel := new Kennel()
    kennel.Rename(1, "bo")
    kennel.RenameExplicit(0, "max")
    assert kennel.NameAt(0) == "max"
    assert kennel.NameAt(1) == "bo"
}

test "a value-typed element of the instance's own array field is written in place" {
    kennel := new Kennel()
    kennel.Place(1, 40)
    kennel.Place(1, 2)
    assert kennel.SpotAt(1).X == 2
    assert kennel.SpotAt(1).Y == 42
}

test "a field write through an instance method's call result changes the returned object" {
    kennel := new Kennel()
    kennel.RenameFirstThroughCall("first")
    assert kennel.NameAt(0) == "first"
}

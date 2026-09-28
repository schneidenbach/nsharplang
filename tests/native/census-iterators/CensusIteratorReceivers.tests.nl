namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// EXECUTED PROOFS FOR A BARE `this` INSIDE A GENERATOR BODY, AND FOR THE ORDINARY MEMBER BODIES THAT
// SHARE ITS OWNER.
test "a generator passes this to a free function" {
    widget := new ReceiverWidget()
    seen := new List<string>()
    for text in widget.Described() {
        seen.Add(text)
    }
    assert seen.Count == 1
    assert seen[0] == "widget t"
}

test "a generator yields this as its element" {
    widget := new ReceiverWidget()
    count := 0
    for element in widget.Selves() {
        assert object.ReferenceEquals(element, widget)
        count = count + 1
    }
    assert count == 2
}

test "a generator passes this to another receiver's method and to a BCL call" {
    widget := new ReceiverWidget()
    other := new ReceiverWidget()
    seen := new List<bool>()
    for answer in widget.Recognized(widget) {
        seen.Add(answer)
    }
    for answer in widget.Recognized(other) {
        seen.Add(answer)
    }
    assert seen.Count == 4
    assert seen[0]
    assert seen[1]
    assert !seen[2]
    assert seen[3]
}

test "this.Tag in a generator reads the object's field and a member access continues from it" {
    widget := new ReceiverWidget()
    seen := new List<int>()
    for length in widget.TagLengths() {
        seen.Add(length)
    }
    assert seen.Count == 2
    assert seen[0] == 1
    assert seen[1] == 6
    assert widget.Tag == "longer"
}

test "a lambda in a generator reads this through the captured receiver" {
    widget := new ReceiverWidget()
    widget.Tag = "lambda"
    seen := new List<string>()
    for text in widget.Deferred() {
        seen.Add(text)
    }
    assert seen.Count == 1
    assert seen[0] == "widget lambda"
}

test "a per-iteration display reads this through its own copy of the receiver" {
    widget := new ReceiverWidget()
    callbacks := new List<Func<string>>()
    for callback in widget.PerIteration() {
        callbacks.Add(callback)
    }
    widget.Tag = "later"
    assert callbacks.Count == 2
    assert callbacks[0]() == "widget later1"
    assert callbacks[1]() == "widget later2"
}

test "an ordinary member body returns, stores and captures this" {
    widget := new ReceiverWidget()
    assert object.ReferenceEquals(widget.Itself(), widget)
    assert widget.DescribedNow() == "widget t"
    widget.Tag = "captured"
    assert widget.DescribedLater()() == "widget captured"
    assert widget.DescribedTwoLambdasDeep()()() == "widget captured"
}

test "a struct generator captures a copy of this when it is called" {
    point := new ReceiverPoint()
    point.X = 3
    selves := point.Selves()
    xs := point.Xs()
    point.X = 9
    seenX := new List<int>()
    for copy in selves {
        seenX.Add(copy.X)
    }
    for x in xs {
        seenX.Add(x)
    }
    assert seenX.Count == 3
    assert seenX[0] == 3
    assert seenX[1] == 3
    assert seenX[2] == 3
}

test "a struct member body's this is a copy of the receiver" {
    point := new ReceiverPoint()
    point.X = 4
    assert point.Copied().X == 4
    assert point.BumpedCopy() == 405
    assert point.X == 4
}

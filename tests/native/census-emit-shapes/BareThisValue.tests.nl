namespace NSharpLang.CensusEmitShapes.Tests

import System

test "a bare `this` returned from a reference type is the receiver itself" {
    node := new Node("root")
    assert Object.ReferenceEquals(node.Self(), node)
}

test "a bare `this` passed as a call argument reaches the callee as the receiver" {
    node := new Node("alpha")
    assert node.Describe() == "alpha"
    assert node.SelfThroughLocal() == "alpha"
}

test "a bare `this` widens into an object parameter without losing identity" {
    node := new Node("beta")
    assert Object.ReferenceEquals(node.AsObject(), node)
}

test "a bare `this` inside a lambda body is the enclosing receiver, not the display class" {
    node := new Node("gamma")
    assert node.LabelThroughLambda() == "gamma"
}

test "a method that returns `this` chains" {
    head := new Node("head")
    tail := new Node("tail")
    assert Object.ReferenceEquals(head.LinkTo(tail), head)
    assert head.Next != null
    assert Object.ReferenceEquals(head.Next, tail)
}

test "a bare `this` in a struct body produces a copy, not an alias" {
    tally := new Tally()
    tally.Count = 7
    snapshot := tally.Snapshot()
    assert snapshot.Count == 7
    tally.Count = 9
    assert snapshot.Count == 7
    assert tally.Bumped().Count == 10
    assert tally.Count == 9
}

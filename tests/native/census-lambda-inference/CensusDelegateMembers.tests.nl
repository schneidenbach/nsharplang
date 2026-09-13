namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic


// ── invoking a delegate-typed MEMBER through its owner ────────────────────────────────────────
test "a delegate FIELD is invoked through its receiver, and the value it holds is the one called" {
    sink := new List<int>()
    handlers := NewHandlers(sink)

    assert handlers.Load() == 7
    assert handlers.Map(4) == 12
    handlers.Sink(9)
    assert sink.Count == 1
    assert sink[0] == 9
}

test "a delegate PROPERTY is invoked the same way, through its getter" {
    sink := new List<int>()
    handlers := NewHandlers(sink)

    // `Doubled` is an expression-bodied property returning the same delegate the field holds.
    assert handlers.Doubled(2) == 6

    // 7 + 12 + 6 = 25, and the sink saw the total.
    assert TotalThrough(handlers) == 25
    assert sink[sink.Count - 1] == 25
}

test "the receiver of a delegate member may itself be a member read" {
    sink := new List<int>()
    box := new HandlerBox(NewHandlers(sink))
    assert ThroughBox(box) == 15
}

test "a delegate member REASSIGNED is called at its current value, not the one it was built with" {
    sink := new List<int>()
    handlers := NewHandlers(sink)
    assert handlers.Map(2) == 6

    handlers.Map = value => value + 100
    assert handlers.Map(2) == 102
    assert handlers.Doubled(2) == 102
}

// ── a method group named through an instance RECEIVER ─────────────────────────────────────────
test "a method group on an instance receiver builds a delegate BOUND to that receiver" {
    first := new Loader("hi ")
    second := new Loader("yo ")

    greeting := GreeterDelegate(first)
    assert greeting.GetType() == typeof(Func<string, string>)
    assert greeting("bob") == "hi bob"

    // A SECOND receiver gives a SECOND delegate; the target is the value, not the type.
    secondGreeting := GreeterDelegate(second)
    assert secondGreeting("bob") == "yo bob"

    // Changing the receiver's own state afterwards is visible through the delegate, which is what
    // "bound to the receiver" means: the target is the object, not a copy of its fields.
    first.Prefix = "hey "
    assert greeting("bob") == "hey bob"
}

test "two methods of one receiver are two different delegates" {
    loader := new Loader("hi ")
    greeting := GreeterDelegate(loader)
    shouting := ShoutDelegate(loader)
    assert greeting("ann") == "hi ann"
    assert shouting("ann") == "hi ANN"
}

test "a receiver-bound method group is accepted in ARGUMENT position too" {
    names := new List<string>()
    names.Add("ann")
    names.Add("bob")

    mapped := MappedThrough(new Loader("> "), names)
    assert mapped.GetType() == typeof(List<string>)
    assert mapped[0] == "> ann"
    assert mapped[1] == "> bob"
}

// A VIRTUAL method reached through a base-typed receiver must call the DERIVED override, which is
// the whole reason the conversion emits `ldvirtftn` rather than `ldftn`.
test "a virtual method group binds the method the receiver actually has" {
    derived: Base = new Derived()
    derivedName := NameDelegate(derived)
    baseName := NameDelegate(new Base())
    assert derivedName() == "Derived"
    assert baseName() == "Base"

    // A non-virtual method on the same receiver keeps its own binding.
    describe := DescribeDelegate(derived)
    assert describe() == "base"
}

test "a method group on a receiver from a REFERENCED assembly converts by the same rule" {
    builder := new System.Text.StringBuilder()
    append := BuilderAppend(builder)
    assert append.GetType() == typeof(Func<string, System.Text.StringBuilder>)

    append("one")
    append("-two")
    assert builder.ToString() == "one-two"
}

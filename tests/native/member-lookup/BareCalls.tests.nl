namespace NSharpLang.MemberLookup.Tests

test "a bare static call fills an omitted default like the qualified call" {
    assert Svc.Twice("x") == "x-x!"
    assert Svc.Qualified("y") == "y-"
    assert Svc.Show("z") == "z-"
}

test "a bare static call fills several defaults, skipping the middle one by name" {
    assert Svc.AllDefaults("a") == "aB3"
    assert Svc.SkipMiddle("a") == "aB9"
    assert Svc.Named("a") == "an"
}

test "a bare instance call fills an omitted default" {
    svc := new Svc("p:")
    assert svc.Both("a") == "p:a.p:a!p:a."
    assert svc.Chain("a") == "p:a2."
}

test "a bare instance call to a static with a default fills it" {
    assert new Svc("p:").FromInstance("a") == "a-"
}

test "a bare call with an omitted default works inside a lambda" {
    mapped := new Svc("p:").Mapped(["a", "b"])
    assert mapped.Length == 2
    assert mapped[0] == "p:a."
    assert mapped[1] == "p:b."
}

test "a bare call on a generic type fills its default" {
    assert new Box<int>("n").Run(5) == "n:5!"
    assert Box<string>.Make("v") == "box/v"
}

test "an exact-arity overload still wins over a fillable one" {
    assert Overloaded.Call() == "one1"
    assert Overloaded.CallWide() == "two3"
}

test "a better conversion beats an exact-arity overload before optional parameters are compared" {
    assert BetterOptionalOverload.Call() == "string:x"
    assert BetterOptionalOverload.CallNamed() == "string:named"
}

test "the overload whose argument fits is the one filled" {
    assert Overloaded.CallFill() == "s5int76"
}

test "a free function bare call keeps filling its default" {
    assert freeTwice("f") == "f-f!"
}

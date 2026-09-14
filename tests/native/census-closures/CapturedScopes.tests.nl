namespace NSharpLang.CensusClosures.Tests

import System.Reflection


// RUNTIME contracts for what a display reaches, plus the CLR shape the lowering produces.
test "a lambda capturing both the instance and a local reads through the captured receiver" {
    scaler := new Scaler(3, "n=")
    make := scaler.Make(10)
    assert make(2) == 16
    assert make(0) == 10

    // A second instance's delegate reads ITS receiver; the first one is unmoved.
    other := new Scaler(5, "m=")
    otherMake := other.Make(1)
    assert otherMake(2) == 11
    assert make(2) == 16

    assert scaler.MakeThroughLocal(4)(2) == 14
    assert scaler.MakeExplicit(10)(2) == 16
}

test "the captured receiver serves a bare call and a bare member read alike" {
    scaler := new Scaler(3, "n=")
    narrate := scaler.Narrate("!")
    assert narrate(7) == "n=7!"

    fromProperty := scaler.MakeFromProperty(1)
    assert fromProperty(2) == 13
}

test "a constructor's `this`-capturing lambda binds the object under construction" {
    scaler := new Scaler(3, "n=", 10)
    scaled := scaler.Scaled
    assert scaled(2) == 16

    // The field the lambda reads is the one the object still has, not a copy taken in the
    // constructor: writing it afterwards changes what the delegate answers.
    scaler.Factor = 5
    assert scaled(2) == 20
}

test "a lambda nested in a lambda reaches every enclosing scope" {
    over10 := Curried(10)
    over15 := over10(5)
    assert over15(16)
    assert !over15(15)

    // A second outer call is a second display, so the two inner delegates disagree.
    over0 := over10(0)
    assert over0(11)
    assert !over0(10)

    three := ThreeDeep(100)
    level2 := three(1)
    level3 := level2(2)
    assert level3(3) == 106

    blocks := CurriedBlocks(100)
    blockInner := blocks(1)
    assert blockInner(2) == 103

    plain := InnerCapturesOuterOnly()
    plainInner := plain(40)
    assert plainInner(2) == 42
}

test "a nested lambda inside an instance method reaches the instance too" {
    composer := new Composer(2)
    curry := composer.Curry(5)
    inner := curry(1)
    assert inner(2) == 16

    other := new Composer(10)
    otherInner := other.Curry(0)(1)
    assert otherInner(2) == 30
    assert inner(2) == 16
}

test "a capture written from inside a nested lambda is one storage location" {
    counter := SharedCounter()
    addFive := counter(5)
    assert addFive(1) == 6
    assert addFive(2) == 13

    // A second outer call rebinds `a`, and the SAME `total` box keeps counting.
    addTen := counter(10)
    assert addTen(0) == 23
}

test "a written loop binding is captured once per iteration" {
    adders := WrittenPerIterationAdders(3)
    assert adders.Count == 3
    first := adders[0]
    second := adders[1]
    third := adders[2]
    assert first() == 10
    assert second() == 20
    assert third() == 30
}

test "a display that captured its enclosing scope holds exactly one receiver field for it" {
    assembly := typeof(Scaler).get_Assembly()
    displaysWithReceiver := 0
    for candidate in assembly.GetTypes() {
        if !candidate.get_Name().StartsWith("<>c__DisplayClass") {
            continue
        }

        receiverFields := 0
        for field in candidate.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance) {
            if field.get_Name() == "<>4__this" {
                receiverFields = receiverFields + 1
                // The receiver a display captured is a REFERENCE — a value type's `this` is a
                // pointer into its own storage and is never captured at all.
                assert !field.get_FieldType().get_IsValueType()
            }
        }

        assert receiverFields <= 1
        if receiverFields == 1 {
            displaysWithReceiver = displaysWithReceiver + 1
        }
    }

    // Every capturing scope in CapturedScopes.nl whose body reaches an enclosing receiver, and no
    // other: Scaler's five member lambdas and its three-argument constructor, Composer.Curry's outer
    // lambda (six instance receivers), plus the inner lambdas of Curried, ThreeDeep's two inner
    // levels, CurriedBlocks and Composer.Curry (five parent displays).
    //
    // A scope whose body reaches NOTHING outside its own captures gets no receiver field at all:
    // Curried's and CurriedBlocks' OUTER lambdas capture only a function parameter,
    // InnerCapturesOuterOnly's inner lambda captures only the outer lambda's parameter, and both of
    // SharedCounter's levels reach `total` through its shared box rather than through a receiver.
    assert displaysWithReceiver == 12
}

test "a nested lambda's display points at the display of the scope that made it" {
    assembly := typeof(Scaler).get_Assembly()
    nestedDisplays := 0
    instanceDisplays := 0
    for candidate in assembly.GetTypes() {
        if !candidate.get_Name().StartsWith("<>c__DisplayClass") {
            continue
        }

        for field in candidate.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance) {
            if field.get_Name() != "<>4__this" {
                continue
            }

            if field.get_FieldType().get_Name().StartsWith("<>c__DisplayClass") {
                nestedDisplays = nestedDisplays + 1
            } else {
                instanceDisplays = instanceDisplays + 1
            }
        }
    }

    // Curried's inner lambda, ThreeDeep's two inner levels, CurriedBlocks' inner lambda and
    // Composer.Curry's inner lambda each point at the display the scope above them made — which is
    // the link a read walks when it reaches past its own captures.
    assert nestedDisplays == 5
    // Scaler's five member lambdas, its three-argument constructor, and Composer.Curry's outer
    // lambda point at the declaring type's instance.
    assert instanceDisplays == 7
}

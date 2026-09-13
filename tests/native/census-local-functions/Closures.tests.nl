namespace NSharpLang.CensusLocalFunctions.Tests

import System.Collections.Generic
import System.Reflection


// RUNTIME contracts for a local function's capture, plus the CLR shape the lowering produces.
//
// The assertions below run the emitted IL, so they see what the closure actually stores rather than
// what the analyzer accepted. The reflection tests read the same assembly's metadata to pin the
// shape: one display class for a capturing scope, and none for a capture-free local function.
test "a local function reads and writes the locals its body declares" {
    items := new List<string>()
    items.Add("abc")
    assert Walk(items) == 6

    repeated := new List<string>()
    repeated.Add("abc")
    repeated.Add("abc")
    // The second "abc" is refused by the captured `seen`, so the total does not move.
    assert Walk(repeated) == 6

    assert Walk(new List<string>()) == 0
}

test "mutually recursive local functions share one captured counter" {
    // Four steps down to zero, plus the call that sees zero.
    assert CountSteps(4) == 5
    assert CountSteps(0) == 1
    assert CountSteps(3) == 0 - 4
}

test "a capture is one storage location, not a copy taken at the declaration" {
    // seed 5 -> the body writes 6 -> the local function doubles it -> the body reads 12.
    assert SharedStorage(5) == 12
    assert SharedStorage(0) == 2
}

test "a captured parameter is written through by the local function" {
    assert BumpParameter(1) == 21
    assert BumpParameter(0) == 20
}

test "a local function that calls a capturing sibling reaches both scopes" {
    assert TwoScopes(2) == 106
    assert TwoScopes(0) == 100
}

test "a capture-free local function still runs" {
    assert Doubled(21) == 42
}

test "a capturing local function converted to a delegate keeps the same storage" {
    adder := MakeAdder(10)
    assert adder(5) == 15
    assert adder(0) == 10

    assert AddThroughLocalVariable(7, 5) == 12

    values := new List<int>()
    values.Add(1)
    values.Add(2)
    mapped := MapThroughArgument(values, 100)
    assert mapped.Count == 2
    assert mapped[0] == 101
    assert mapped[1] == 102
}

test "a binding declared inside a loop is captured once per iteration" {
    adders := PerIterationAdders(3)
    assert adders.Count == 3
    first := adders[0]
    second := adders[1]
    third := adders[2]
    assert first() == 0
    assert second() == 10
    assert third() == 20
}

test "a local function's parameter may reuse the name a nested block binds" {
    items := new List<string>()
    items.Add("ab")
    items.Add("cde")
    assert TotalLengths(items) == 5
}

test "a local function that captures only `this` writes the instance it was called on" {
    walker := new Walker()
    items := new List<string>()
    items.Add("ab")
    items.Add("cde")
    walker.Run(items)
    assert walker.Count == 5

    other := new Walker()
    other.Run(items)
    assert other.Count == 5
    assert walker.Count == 5

    walker.Reset()
    assert walker.Count == 0
    assert other.Count == 5
}

test "a local function that captures `this` and a local reaches both" {
    scaler := new Scaler()
    scaler.Factor = 3
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    // (1*3 + 10) + (2*3 + 10)
    assert scaler.Scale(values, 10) == 29
}

test "a struct's capturing local function reads the receiver it was called on" {
    reading := new Reading()
    reading.Value = 40
    assert reading.PlusOffset(2) == 42
}

test "a capturing scope gets exactly one display class and a capture-free local gets none" {
    assembly := typeof(Walker).get_Assembly()
    displayCount := 0
    for candidate in assembly.GetTypes() {
        name := candidate.get_Name()
        if name.StartsWith("<>c__DisplayClass") {
            displayCount = displayCount + 1
        }
    }

    // One per capturing scope in Closures.nl: Walk, CountSteps, SharedStorage, BumpParameter,
    // TwoScopes, MakeAdder, AddThroughLocalVariable, MapThroughArgument, TotalLengths and
    // Scaler.Scale, plus the one the lambda in PerIterationAdders gets — the same lowering.
    assert displayCount == 11

    // CountSteps declares two mutually recursive capturing local functions. They share ONE display,
    // which is the whole reason each sees the other's writes to the captured counter.
    stepsOwners := new List<string>()
    for candidate in assembly.GetTypes() {
        for method in candidate.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
            if method.get_Name().StartsWith("<CountSteps>g__") {
                stepsOwner := must method.get_DeclaringType()
                if !stepsOwners.Contains(stepsOwner.get_Name()) {
                    stepsOwners.Add(stepsOwner.get_Name())
                }
            }
        }
    }

    assert stepsOwners.Count == 1

    doubledDisplays := 0
    for candidate in assembly.GetTypes() {
        for method in candidate.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
            if method.get_Name().StartsWith("<Doubled>g__") {
                doubledDisplays = doubledDisplays + 1
                // `twice` captures nothing, so it stays a static and never lands on a display.
                assert method.get_IsStatic()
                staticOwner := must method.get_DeclaringType()
                assert !staticOwner.get_Name().StartsWith("<>c__DisplayClass")
            }
        }
    }

    assert doubledDisplays == 1
}

test "a capturing local function is an instance method of a display that holds its captures" {
    assembly := typeof(Walker).get_Assembly()
    found := 0
    for candidate in assembly.GetTypes() {
        for method in candidate.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
            if method.get_Name().StartsWith("<SharedStorage>g__") {
                found = found + 1
                assert !method.get_IsStatic()
                owner := must method.get_DeclaringType()
                assert owner.get_Name().StartsWith("<>c__DisplayClass")
                // The capture rides a shared box on the display, which is what makes the write the
                // local function performs visible to the body that called it.
                captureFields := owner.GetFields(BindingFlags.Public | BindingFlags.Instance)
                assert captureFields.Length == 1
                assert captureFields[0].get_Name() == "value"
                captureFieldType := captureFields[0].get_FieldType()
                assert captureFieldType.get_Name().StartsWith("StrongBox")
            }
        }
    }

    assert found == 1
}

test "a local function capturing only `this` is an instance method of the declaring type" {
    walkerType := typeof(Walker)
    found := 0
    for method in walkerType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static) {
        if method.get_Name().StartsWith("<Run>g__") {
            found = found + 1
            assert !method.get_IsStatic()
            assert method.get_DeclaringType() == walkerType
        }
    }

    assert found == 1
}

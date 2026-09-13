namespace NSharpLang.PatternForeach.Tests

import System
import System.Collections.Generic
import System.Reflection

func UserShapesUnderTest(): UserShapes {
    return new UserShapes()
}

func SampleWords(): string[] {
    words := new string[](3)
    words[0] = "al"
    words[1] = "be"
    words[2] = "ga"
    return words
}

func SampleNumbers(): NumberBag {
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    values.Add(3)
    return new NumberBag(values)
}

// A user type that implements NOTHING iterates through the pattern alone — the shape the old rule
// rejected as "collection must be enumerable".
test "a user collection with only a GetEnumerator iterates" {
    shapes := UserShapesUnderTest()
    cursor := new CountdownCursor(3)
    assert shapes.SumCountdown(new Countdown(cursor)) == 6
}

// THE STRUCT ENUMERATOR IS STEPPED IN PLACE. The guard breaks the loop at 17 iterations, so a
// boxed-per-call enumerator — which never advances — would report 17 steps rather than 3.
test "a struct enumerator advances instead of being copied" {
    shapes := UserShapesUnderTest()
    cursor := new CountdownCursor(3)
    assert shapes.CountCountdownSteps(new Countdown(cursor)) == 3
}

test "a disposable struct enumerator is disposed exactly once" {
    shapes := UserShapesUnderTest()
    cursor := new CountdownCursor(3)
    shapes.SumCountdown(new Countdown(cursor))
    assert cursor.Disposals == 1
}

test "a disposable reference enumerator is disposed on every way out of the loop" {
    shapes := UserShapesUnderTest()

    exhausted := new CountdownCursor(0)
    assert UserShapesUnderTest().JoinWords(new WordBag(SampleWords(), exhausted)) == "albega"
    assert exhausted.Disposals == 1

    broken := new CountdownCursor(0)
    assert shapes.JoinWordsUntil(new WordBag(SampleWords(), broken), "be") == "al"
    assert broken.Disposals == 1

    returned := new CountdownCursor(0)
    assert shapes.FirstWordOrEmpty(new WordBag(SampleWords(), returned)) == "al"
    assert returned.Disposals == 1
}

// The `finally` runs when the body throws, which is the whole reason disposal is a protected region
// rather than a statement after the loop.
test "an enumerator is disposed when the loop body throws" {
    shapes := UserShapesUnderTest()
    thrown := new CountdownCursor(0)
    bag := new WordBag(SampleWords(), thrown)

    assert throws InvalidOperationException {
        shapes.ThrowOnWord(bag, "be")
    }

    assert thrown.Disposals == 1
}

test "a user collection iterates through the sequence interface it declares" {
    shapes := UserShapesUnderTest()
    assert shapes.SumNumberBag(SampleNumbers()) == 6
    assert shapes.CountPairs(SampleNumbers(), SampleNumbers()) == 3
}

// THE HIDDEN ENUMERATOR LOCAL IS THE STRUCT'S OWN TYPE, not the interface it also implements. That
// is what makes a `foreach` over a list allocation-free, and it is visible in the emitted metadata
// rather than only in the timing.
test "the emitted loop declares the struct enumerator as its own local" {
    body := must (must typeof(BclShapes).GetMethod("SumList")).GetMethodBody()

    sawStructEnumerator := false
    sawInterfaceEnumerator := false
    for local in body.LocalVariables {
        localType := local.LocalType
        if localType.Name == "Enumerator" && localType.get_IsValueType() {
            sawStructEnumerator = true
        }

        if localType.Name == "IEnumerator`1" {
            sawInterfaceEnumerator = true
        }
    }

    assert sawStructEnumerator
    assert !sawInterfaceEnumerator
}

// A collection whose static type is an INTERFACE has no struct enumerator to bind, so the loop's
// hidden local is the interface's own enumerator — the other half of the same rule.
test "an interface collection declares the interface enumerator as its local" {
    body := must (must typeof(BclShapes).GetMethod("SumSequence")).GetMethodBody()

    sawInterfaceEnumerator := false
    for local in body.LocalVariables {
        if local.LocalType.Name == "IEnumerator`1" {
            sawInterfaceEnumerator = true
        }
    }

    assert sawInterfaceEnumerator
}

// A span carries no disposal, so its loop carries no protected region at all.
test "a span loop emits no exception handling and a list loop does" {
    spanBody := must (must typeof(BclShapes).GetMethod("SumSpan")).GetMethodBody()
    assert spanBody.ExceptionHandlingClauses.Count == 0

    arrayBody := must (must typeof(BclShapes).GetMethod("SumArray")).GetMethodBody()
    assert arrayBody.ExceptionHandlingClauses.Count == 0

    listBody := must (must typeof(BclShapes).GetMethod("SumList")).GetMethodBody()
    assert listBody.ExceptionHandlingClauses.Count == 1
}

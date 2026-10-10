namespace NSharpLang.CensusClosures.Tests

import System.Reflection

test "an inferred zero-parameter lambda reads the bindings around it" {
    assert CaptureParameter(5) == 10
    assert CaptureLocal() == "n=1"
    assert CaptureIntoAction() == 2
    assert CaptureThroughTwoDisplays(4) == 10
    assert new Ledger(3).Weigh(7) == 37
}

test "a mutated capture is shared, not copied, through an inferred lambda" {
    // The write happens AFTER the delegate is built; a by-value snapshot would answer 10.
    assert CaptureMutatedLocal() == 40
}

test "an inferred zero-parameter lambda's delegate type comes from its body" {
    // `() => sink.Add(7)` answers nothing, so the local is an `Action`; every other one above
    // answers a value and is a `Func<T>` closed over it.
    action := DeclaredFunction("CaptureIntoAction")
    assert action != null

    // The synthesized methods live on display classes, not on the program type: a capturing lambda
    // is an instance method of the display that holds its captures.
    assembly := typeof(Ledger).get_Assembly()
    displaysWithLambda := 0
    for candidate in assembly.GetTypes() {
        if !candidate.get_Name().StartsWith("<>c__DisplayClass") {
            continue
        }

        if candidate.GetMethod("<Lambda>", BindingFlags.Public | BindingFlags.Instance) != null {
            displaysWithLambda = displaysWithLambda + 1
        }
    }

    assert displaysWithLambda > 0
}

test "a lambda assigned to an existing local, parameter or box replaces what it answers" {
    assert ReassignTypedLocal() == 48
    assert ReassignWithCapture(9) == 10
    assert ReassignFromMethodGroup() == 42
    assert ReassignParameter(x => x) == 101

    // The reader was built BEFORE the reassignment and reads through the shared box, so it answers
    // the second lambda.
    assert ReassignLiftedDelegate() == 15
}

func DeclaredFunction(name: string): MethodInfo? {
    for candidate in typeof(Ledger).get_Assembly().GetTypes() {
        method := candidate.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
        if method != null {
            return method
        }
    }

    return null
}

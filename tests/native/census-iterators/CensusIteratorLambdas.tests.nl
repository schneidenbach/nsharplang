namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic
import System.Reflection


// EXECUTED PROOFS FOR A LAMBDA INSIDE A GENERATOR BODY.
test "a lambda captures a hoisted local and a captured parameter" {
    seen := new List<int>()
    for v in ScaledByCapture(1) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 7
    assert seen[1] == 16
}

test "a lambda built inside a generator is invoked by a BCL call" {
    items := new List<string>()
    items.Add("a")
    items.Add("bc")
    items.Add("def")
    seen := new List<int>()
    for v in MatchesAtLeast(items, 3) {
        seen.Add(v)
    }
    assert seen.Count == 1
    assert seen[0] == 1
}

test "a lambda in an instance generator reads the enclosing type through the captured receiver" {
    tally := new CensusTally(10)
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    seen := new List<int>()
    for v in tally.Scaled(values) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 11
    assert seen[1] == 12
}

test "a lambda inside a generator is a method on the machine itself, not a separate display class" {
    sequence: object = ScaledByCapture(1)
    machine := sequence.GetType()
    lambda := machine.GetMethod("<>__lambda0", BindingFlags.NonPublic | BindingFlags.Instance)
    assert lambda != null
    assert !lambda.IsStatic
    assert lambda.ReturnType == typeof(int)
    parameters := lambda.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].ParameterType == typeof(int)
}

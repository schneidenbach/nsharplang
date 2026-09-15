namespace NSharpLang.CensusIterators.Tests

import System
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

test "a loop capture gets a fresh mutable cell per iteration and keeps outside captures shared" {
    callbacks := new List<Func<int>>()
    for callback in PerIterationCallbacks([1, 2, 3]) {
        callbacks.Add(callback)
    }
    assert callbacks.Count == 3
    assert callbacks[0]() == 1
    assert callbacks[1]() == 2
    assert callbacks[2]() == 3
    assert !Object.ReferenceEquals(callbacks[0].Target, callbacks[1].Target)
    assert !Object.ReferenceEquals(callbacks[1].Target, callbacks[2].Target)

    shared := new List<Func<int>>()
    for callback in SharedIterationCallbacks() {
        shared.Add(callback)
    }
    assert shared.Count == 2
    assert shared[0]() == 113
    assert shared[1]() == 114
}

test "a loop-capturing lambda method and box live on its per-iteration display" {
    callbacks := new List<Func<int>>()
    for callback in PerIterationCallbacks([7]) {
        callbacks.Add(callback)
    }
    callback := callbacks[0]
    target := callback.Target
    assert target != null
    display := target.GetType()
    assert callback.Method.DeclaringType == display
    assert callback.Method.IsAssembly
    assert display.GetField("<>__machine", BindingFlags.Public | BindingFlags.Instance) != null
    captured := display.GetField("value", BindingFlags.Public | BindingFlags.Instance)
    assert captured != null
    assert captured.FieldType == typeof(System.Runtime.CompilerServices.StrongBox<int>)
}

test "callbacks created in one iteration share that iteration cell and lambda writes flow through it" {
    callbacks := new List<Func<int>>()
    for callback in SameIterationCallbacks() {
        callbacks.Add(callback)
    }
    assert callbacks.Count == 2
    assert callbacks[0]() == 2
    assert callbacks[1]() == 2
}

test "counted while and enumerable loops each allocate fresh cells for body locals" {
    counted := new List<Func<int>>()
    for callback in CountedIterationCallbacks() {
        counted.Add(callback)
    }
    assert counted[0]() == 0
    assert counted[1]() == 1

    initializer := new List<Func<int>>()
    for callback in CountedInitializerCallbacks() {
        initializer.Add(callback)
    }
    assert initializer[0]() == 2
    assert initializer[1]() == 2

    whileCallbacks := new List<Func<int>>()
    for callback in WhileIterationCallbacks() {
        whileCallbacks.Add(callback)
    }
    assert whileCallbacks[0]() == 0
    assert whileCallbacks[1]() == 1

    values := new List<int>()
    values.Add(4)
    values.Add(5)
    enumerable := new List<Func<int>>()
    for callback in EnumerableIterationCallbacks(values) {
        enumerable.Add(callback)
    }
    assert enumerable[0]() == 4
    assert enumerable[1]() == 5
}

test "a member suffix matching a loop local does not create an iteration capture" {
    callbacks := new List<Func<int>>()
    for callback in MemberSuffixCallbacks([1], [10, 20, 30]) {
        callbacks.Add(callback)
    }
    assert callbacks[0]() == 3
    target := callbacks[0].Target
    assert target != null
    assert target.GetType().GetField("<>__machine", BindingFlags.Public | BindingFlags.Instance) == null
    assert callbacks[0].Method.DeclaringType == target.GetType()
}

test "a generic loop display preserves dependent interface reference and constructor constraints" {
    values := [new LoopValue()]
    callbacks := new List<Func<object>>()
    for item in ConstrainedIterationCallbacks<LoopBase, LoopValue>(values[0]) {
        callbacks.Add((Func<object>)item)
    }
    assert (LoopValue)callbacks[0]() == values[0]

    display := callbacks[0].Target.GetType().GetGenericTypeDefinition()
    parameters := display.GetGenericArguments()
    assert parameters.Length == 2
    assert (parameters[0].get_GenericParameterAttributes() & GenericParameterAttributes.ReferenceTypeConstraint) == GenericParameterAttributes.ReferenceTypeConstraint
    expected := GenericParameterAttributes.DefaultConstructorConstraint
    assert (parameters[1].get_GenericParameterAttributes() & expected) == expected
    constraints := parameters[1].GetGenericParameterConstraints()
    assert constraints.Length == 2
    assert constraints[0] == parameters[0]
    assert constraints[1] == typeof(ILoopMarker)
}

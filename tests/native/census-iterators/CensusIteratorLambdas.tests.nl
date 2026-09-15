namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Reflection
import System.Threading.Tasks


// EXECUTED PROOFS FOR A LAMBDA INSIDE A GENERATOR BODY.
test "ordinary async lambda fallback remains intact when recursive await is disabled" {
    assert await OrdinaryAsyncCallback(40)() == 40
}

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

test "async lambdas inside a generator preserve capture await and task faults" {
    callbacks := new List<Func<Task<int>>>()
    for callback in AsyncCallbacks(40) {
        callbacks.Add(callback)
    }
    assert callbacks.Count == 7

    first := callbacks[0]()
    firstDelegate: Delegate = callbacks[0]
    assert firstDelegate.Method.ReturnType == typeof(Task<int>)
    assert first.IsCompletedSuccessfully
    assert await first == 41

    second := callbacks[1]()
    assert second.IsCompletedSuccessfully
    assert await second == 42

    faulted := callbacks[2]()
    assert faulted.IsFaulted
    failure := faulted.Exception
    assert failure != null
    assert failure.InnerException is InvalidOperationException
    assert failure.InnerException.Message == "generator async lambda failure"

    blockResult := callbacks[3]()
    assert await blockResult == 43

    // These awaits are operands of a larger binary and a call. They still belong to the synthesized
    // lambda method and preserve ordinary expression evaluation; neither consumes an iterator state.
    assert await callbacks[4]() == 42
    assert await callbacks[5]() == 40

    awaitedFault := callbacks[6]()
    assert awaitedFault.IsFaulted
    assert awaitedFault.Exception != null
    assert awaitedFault.Exception.InnerException is InvalidOperationException
    assert awaitedFault.Exception.InnerException.Message == "awaited generator async lambda failure"
}

test "generator async lambdas preserve all four task families" {
    taskLog := new List<string>()
    taskCallbacks := new List<Func<Task>>()
    for callback in AsyncUnitCallbacks(taskLog) {
        taskCallbacks.Add(callback)
    }
    task := taskCallbacks[0]()
    taskCallback: Delegate = taskCallbacks[0]
    assert taskCallback.Method.ReturnType == typeof(Task)
    await task
    assert taskLog.Count == 1
    assert taskLog[0] == "task"

    valueCallbacks := new List<Func<ValueTask<int>>>()
    for callback in AsyncValueTaskCallbacks(40) {
        valueCallbacks.Add(callback)
    }
    assert await valueCallbacks[0]() == 43
    valueCallback: Delegate = valueCallbacks[0]
    assert valueCallback.Method.ReturnType == typeof(ValueTask<int>)
    faultedValueTask := valueCallbacks[1]().AsTask()
    assert faultedValueTask.IsFaulted
    assert faultedValueTask.Exception != null
    assert faultedValueTask.Exception.InnerException is InvalidOperationException

    valueTaskLog := new List<string>()
    unitValueCallbacks := new List<Func<ValueTask>>()
    for callback in AsyncUnitValueTaskCallbacks(valueTaskLog) {
        unitValueCallbacks.Add(callback)
    }
    unitValueCallback: Delegate = unitValueCallbacks[0]
    assert unitValueCallback.Method.ReturnType == typeof(ValueTask)
    await unitValueCallbacks[0]()
    assert valueTaskLog.Count == 1
    assert valueTaskLog[0] == "value task"
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

test "async generator lambdas preserve the selected iteration cells across awaits" {
    callbacks := new List<Func<Task<int>>>()
    for callback in SharedAsyncIterationCallbacks() {
        callbacks.Add(callback)
    }
    assert callbacks.Count == 2
    first := await callbacks[0]()
    second := await callbacks[1]()
    assert first == 113
    assert second == 114
    assert !Object.ReferenceEquals(callbacks[0].Target, callbacks[1].Target)
}

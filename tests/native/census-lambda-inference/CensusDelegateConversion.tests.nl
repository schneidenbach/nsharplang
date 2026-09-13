namespace NSharpLang.CensusLambdaInference.Tests

import System


// ── a lambda reaches every delegate type, not only Func and Action ────────────────────────────
test "a lambda written at a non-Func delegate type builds THAT delegate" {
    ordering := DescendingComparison()
    assert RuntimeTypeOf(ordering) == typeof(Comparison<int>)

    predicate := LongerThanTwo()
    assert RuntimeTypeOf(predicate) == typeof(Predicate<string>)

    converter := TextOfInt()
    assert RuntimeTypeOf(converter) == typeof(Converter<int, string>)

    // The event-handler family is the census's own shape. Its `Invoke` is `(object, T) -> void`,
    // and nothing about the name `ConsoleCancelEventHandler` is consulted to know that.
    cancelHandler := CancelHandler()
    assert RuntimeTypeOf(cancelHandler) == typeof(ConsoleCancelEventHandler)
}

test "the delegate a lambda builds really runs, through the framework method that takes it" {
    values: int[] = [3, 1, 2]
    Array.Sort(values, DescendingComparison())
    assert values[0] == 3
    assert values[1] == 2
    assert values[2] == 1

    words: string[] = ["be", "alpha"]
    assert Array.FindIndex(words, LongerThanTwo()) == 1

    numbers: int[] = [7, 8]
    text := Array.ConvertAll(numbers, TextOfInt())
    assert RuntimeTypeOf(text) == typeof(string[])
    assert text[0] == "7"
    assert text[1] == "8"
}

test "a lambda written INLINE at a delegate-typed parameter converts there too" {
    values: int[] = [1, 3, 2]
    sorted := SortedDescending(values)
    assert sorted[0] == 3
    assert sorted[2] == 1

    assert CountMatching(Words(), value => value.Length > 2) == 2
    assert CountMatching(Words(), value => value.Length == 2) == 1

    assert Words().Find(value => value.Length == 2) == "be"
    assert Words().RemoveAll(value => value.Length > 4) == 2
}

test "a METHOD GROUP converts to the same delegate types by the same rule" {
    predicate := ShortPredicate()
    assert RuntimeTypeOf(predicate) == typeof(Predicate<string>)
    assert predicate("be")
    assert !predicate("alpha")

    ordering := DescendingGroup()
    assert RuntimeTypeOf(ordering) == typeof(Comparison<int>)

    values: int[] = [2, 5, 1]
    sorted := SortedThrough(values, ordering)
    assert sorted[0] == 5
    assert sorted[2] == 1
}

// ── the delegate's own metadata is what the conversion produced ───────────────────────────────
test "the built delegate's Invoke signature is the delegate type's own, in CLR metadata" {
    cancelHandler := CancelHandler()
    handlerType := RuntimeTypeOf(cancelHandler)
    invoke := must handlerType.GetMethod("Invoke")

    invokeParameters := invoke.GetParameters()
    assert invokeParameters.Length == 2
    assert invokeParameters[0].ParameterType == typeof(object)
    assert invokeParameters[1].ParameterType == typeof(ConsoleCancelEventArgs)
    assert invoke.ReturnType.FullName == "System.Void"

    // The delegate is bound to a real method, and that method's signature is the one the delegate
    // declares — which is what the `ldftn`/`newobj` pair the emitter writes guarantees.
    target := cancelHandler.Method
    assert target.GetParameters().Length == 2
}

// ── an external type's settable property is an assignment target ──────────────────────────────
test "a property of a referenced assembly's type can be ASSIGNED, not only read" {
    builder := new System.Text.StringBuilder()
    builder.Capacity = 64
    assert builder.Capacity >= 64

    // The census's own shape: the handler's body writes a property of the event-args it was handed.
    // Reaching it needed the assignment to stop being a list of five approved APIs.
    assert RuntimeTypeOf(CancelHandler()) == typeof(ConsoleCancelEventHandler)
}

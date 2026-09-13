namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic

func NullabilityWords(): List<string> {
    words := new List<string>()
    words.Add("alpha")
    words.Add("be")
    words.Add("gamma")
    return words
}

test "a property whose type is a class type parameter is not maybe-null" {
    // `Lazy<T>.Value`, `Task<T>.Result` and `Tuple<T1, T2>.Item1` are all declared with a bare `T`,
    // and `NullabilityInfoContext` calls every one of them Nullable. Dereferencing them without a
    // guard reported NL905, so this compiling at all is the contract.
    assert LazyValueLength(NullabilityLazyText()) == 4
    assert TaskResultLength(NullabilityCompletedText("abc")) == 3
    assert TupleItemLength(NullabilityPair("ab", 1)) == 2
}

test "a method whose return is a class type parameter is not maybe-null" {
    items := new Stack<string>()
    items.Push("abcde")

    assert StackPeekLength(items) == 5
    assert ListIndexerLength(NullabilityWords()) == 5
}

test "a dictionary indexer's value type is the argument, not the argument made nullable" {
    lookup := new Dictionary<string, string>()
    lookup["key"] = "abc"

    assert DictionaryIndexerLength(lookup) == 3
}

test "a delegate parameter that is a class type parameter is not maybe-null" {
    // `Predicate<T>.Invoke(T)` is the shape that made every `xs.Find(s => ...)` lambda parameter
    // read as maybe-null inside the lambda body.
    assert CountNonEmpty(NullabilityWords()) == 3
}

test "a value type argument substitutes without acquiring a nullable shell" {
    assert LazyIntValue(NullabilityLazyNumber()) == 7
}

test "a `T?` return annotated on the position stays maybe-null after substitution" {
    // `List<T>.Find` is `T?` (a `NullableAttribute(2)` on the return), so the guard in `FindOrEmpty`
    // is required — and it is what makes the empty answer reachable.
    assert FindOrEmpty(NullabilityWords()) == "alpha"
    assert FindOrEmpty(new List<string>()) == ""
}

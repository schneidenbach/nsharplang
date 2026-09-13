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

// ── `T?` on an unconstrained parameter erases for a value argument ──────────────────────────────

func NullabilityMoments(): List<System.DateTime> {
    moments := new List<System.DateTime>()
    moments.Add(new System.DateTime(2019, 5, 4))
    moments.Add(new System.DateTime(2021, 7, 9))
    return moments
}

func NullabilityTimes(): Dictionary<string, System.DateTime> {
    times := new Dictionary<string, System.DateTime>()
    times["late"] = new System.DateTime(2024, 1, 1)
    times["early"] = new System.DateTime(2005, 3, 2)
    return times
}

test "a LINQ default-answering call over a value element is the element, not a lifted one" {
    // The census site: `.Value` here is the PAIR's own property, which it could only be once the
    // result stopped reading as `KeyValuePair<string, DateTime>?`.
    assert EarliestEntryYear(NullabilityTimes()) == 2005

    assert FirstMomentYear(NullabilityMoments()) == 2019
    assert LastMomentYear(NullabilityMoments()) == 2021
    assert FoundMomentYear(NullabilityMoments()) == 2019
}

test "the erased answer for an EMPTY sequence is the element's own default" {
    empty := new List<System.DateTime>()

    // `default(DateTime)` is `DateTime.MinValue`, whose year is 1 — there is no absent value to
    // test for, which is exactly what makes the erasure sound.
    assert FirstMomentYear(empty) == 1
    assert LastMomentYear(empty) == 1
    assert OnlyMomentYear(empty) == 1
    assert FoundMomentYear(empty) == 1
}

test "a REFERENCE element keeps the annotation, so the same call still needs its guard" {
    words := NullabilityWords()
    assert FirstWordOrEmpty(words) == "alpha"
    assert FirstWordOrEmpty(new List<string>()) == ""
}

test "a SOURCE generic's `T?` erases for a value argument and survives for a reference one" {
    numbers: int[] = [4, 9]
    assert FirstNumber(numbers) == 4

    empty: int[] = []
    assert FirstNumber(empty) == 0

    words: string[] = ["alpha"]
    assert FirstWord(words) == "alpha"
    assert FirstWord(new string[](0)) == "<none>"
}

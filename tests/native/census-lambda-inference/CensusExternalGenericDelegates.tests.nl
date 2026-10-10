namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic


// ── a delegate argument to an external generic closed over a source type ──────────────────────
test "a static method group in a static field initializer builds its delegate" {
    // The initializer runs as the type's real initializer, and the method it names is declared
    // AFTER it in the same class — order is no part of the rule.
    assert Holder.Current.Path == "feed"

    // Read twice: a `Lazy<T>` builds its value once, which is what proves the factory delegate was
    // stored rather than an already-evaluated value.
    first := Holder.Current
    second := Holder.Current
    assert first == second
}

test "a method group and a lambda both reach an external generic's constructor" {
    fromGroup := LazyFromGroup()
    assert fromGroup.GetType() == typeof(Lazy<Query>)
    assert fromGroup.Value.Lookup("a") == "aq"

    fromLambda := LazyFromLambda()
    assert fromLambda.Value.Text == "q"

    // The same shape closed over an EXTERNAL argument has always worked, and still answers the same.
    assert LazyOfInt().Value == 7
}

test "a member read off an external generic closed over a source type" {
    holder := LazyFromLambda()

    // A property, then a CALL through what it returned: the read path and the call path agree.
    assert holder.Value.Text == "q"
    assert holder.Value.Lookup("x") == "xq"
    assert holder.IsValueCreated
}

// ── a method group naming a method of the enclosing type ──────────────────────────────────────
test "a class's own static method is a method group where a delegate is expected" {
    names := new List<string>()
    names.Add("alpha")
    names.Add("be")

    formatted := Symbols.FormatAll(names)
    assert formatted.Count == 2
    assert formatted[0] == "<alpha>"
    assert formatted[1] == "<be>"
}

test "an INSTANCE method is a method group where this exists, and it closes over the receiver" {
    names := new List<string>()
    names.Add("one")

    symbols := new Symbols()
    symbols.Prefix = "["
    decorated := symbols.DecorateAll(names)
    assert decorated[0] == "[one"

    other := new Symbols()
    assert other.DecorateAll(names)[0] == "<one"
}

test "two overloads of one name are settled by the delegate the position wants" {
    fromInt := Symbols.WidenFromInt()
    assert fromInt.GetType() == typeof(Func<int, string>)
    assert fromInt(11) == "11"

    fromText := Symbols.WidenFromText()
    assert fromText.GetType() == typeof(Func<string, string>)
    assert fromText("be") == "be"
}

test "the CALLED method's overload set is searched too, and the group picks one arm of it" {
    values := new List<string>()
    values.Add("a")
    values.Add("b")

    // `Select` declares `(TSource) -> TResult` and `(TSource, int) -> TResult`; a two-parameter
    // method group is applicable to exactly the second.
    indexed := Symbols.IndexedAll(values)
    assert indexed.Count == 2
    assert indexed[0] == "0a"
    assert indexed[1] == "1b"
}

// ── output inference through IEnumerable<TResult> ─────────────────────────────────────────────
test "a selector whose result is itself a sequence flattens and emits" {
    first := new Fix()
    first.Edits.Add("x")
    first.Edits.Add("y")
    second := new Fix()
    second.Edits.Add("z")

    fixes := new List<Fix>()
    fixes.Add(first)
    fixes.Add(second)

    flattened := FlattenEdits(fixes)
    assert flattened.GetType() == typeof(List<string>)
    assert flattened.Count == 3
    assert flattened[0] == "x"
    assert flattened[2] == "z"
}

test "GroupBy with a result selector, Zip, and Aggregate with a seed all emit" {
    words := new List<string>()
    words.Add("alpha")
    words.Add("gamma")
    words.Add("be")

    grouped := GroupedByLength(words)
    assert grouped.Count == 2
    assert grouped[0] == "5:2"
    assert grouped[1] == "2:1"

    left := new List<int>()
    left.Add(1)
    left.Add(2)
    right := new List<int>()
    right.Add(10)
    right.Add(20)

    zipped := Zipped(left, right)
    assert zipped.Count == 2
    assert zipped[0] == 10
    assert zipped[1] == 40

    assert AggregatedFrom(100, left) == 103
}

// ── a type parameter's constraint is its member surface ───────────────────────────────────────
test "a constrained type parameter types a LAMBDA argument at the same call" {
    words := new List<string>()
    words.Add("alpha")
    words.Add("be")
    words.Add("gamma")

    assert WidestOf(words) == 5
    assert LongCountOf(words) == 2
    assert UpperJoined(words) == "ALPHA,BE,GAMMA"

    // The no-argument form the constraint already reached keeps working, and an ARRAY satisfies the
    // same constraint as a list does.
    assert CountOfConstrained(words) == 3
    assert WidestOf(WordArray()) == 5
    assert CountOfConstrained(WordArray()) == 3
}

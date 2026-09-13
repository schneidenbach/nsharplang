namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Linq


// ── §11 the lambda parameter every generic method must be able to type ────────────────────────
test "a property that cannot be called does not hide the extension of the same name" {
    values := Words()

    // `List<T>.Count` is an int PROPERTY. It answers when the name is READ and steps aside when the
    // name is CALLED, which is the whole of C#'s must-be-invocable-if-member rule.
    assert values.Count == 3
    assert values.Count() == 3
    assert values.Count(word => word.Length > 3) == 2
}

test "the whole LINQ predicate surface types its lambda parameter" {
    values := Words()

    assert values.Any(word => word.Length > 4)
    assert !values.All(word => word.Length > 4)
    assert values.Where(word => word.Length > 3).Count() == 2
    assert values.First(word => word.Length == 2) == "be"
    assert values.FirstOrDefault(word => word.Length == 99) == null
    assert values.TakeWhile(word => word.Length > 1).Count() == 3
}

test "a selector lambda's RESULT fixes the method's second type parameter" {
    values := Words()

    assert values.Sum(word => word.Length) == 12
    assert values.Max(word => word.Length) == 5
    assert values.Select(word => word.Length).Sum() == 12
    assert values.SelectMany(word => word.ToCharArray()).Count() == 12

    // The result is an int sequence because the lambda returns an int, and the runtime type says so.
    projected := values.Select(word => word.Length).ToList()
    assert projected.GetType() == typeof(List<int>)
    assert projected[0] == 5
}

test "an ordering key lambda and its ThenBy chain both infer" {
    values := Words()

    ordered := values.OrderBy(word => word.Length).ThenBy(word => word).ToList()
    assert ordered[0] == "be"
    assert ordered[1] == "alpha"
    assert ordered[2] == "gamma"
}

test "a grouping key lambda infers the group's own key type" {
    values := Words()

    // Two lengths among three words, so two groups — and the key is an `int` because the lambda
    // says so, which is what makes the sum below compile at all.
    groups := values.GroupBy(word => word.Length).ToList()
    assert groups.Count == 2
    total := 0
    for group in groups {
        total = total + group.Key * group.Count()
    }

    assert total == 12
}

test "TWO lambdas fix TWO different type parameters, each from its own position" {
    values := Words()

    // THE §12 BASELINE. The second lambda used to be handed the FIRST lambda's result, so this
    // answered `Dictionary<string, string>` and every declared interface rejected it.
    byLength := values.ToDictionary(word => word, word => word.Length)
    assert RuntimeTypeOf(byLength) == typeof(Dictionary<string, int>)
    assert byLength["alpha"] == 5
    assert byLength["be"] == 2
}

test "a two-parameter lambda infers both of its parameters" {
    words := Words()
    lengths := Lengths()

    zipped := words.Zip(lengths, (word, count) => word + count.ToString()).ToList()
    assert zipped[0] == "alpha3"
    assert zipped[1] == "be1"

    indexed := words.Select((word, index) => word.Length + index).ToList()
    assert indexed[0] == 5
    assert indexed[1] == 3
    assert indexed[2] == 7
}

test "an accumulator lambda takes its first parameter from a NON-lambda argument" {
    values := Words()

    joined := values.Aggregate("", (accumulated, word) => accumulated + word)
    assert joined == "alphabegamma"
}

test "a USER generic function infers exactly as the framework's own do" {
    values := Words()

    // Nothing in the compiler knows this function. `T` comes from `values`, `R` from the lambda's
    // body, and the call's own result type follows from both.
    mapped := Apply(values, word => word.Length)
    assert mapped.GetType() == typeof(List<int>)
    assert mapped.Count == 3
    assert mapped[0] == 5

    text := Apply(Lengths(), count => count.ToString())
    assert text.GetType() == typeof(List<string>)
    assert text[0] == "3"
}

test "a non-LINQ generic method taking a delegate infers the same way" {
    words := new string[](3)
    words[0] = "alpha"
    words[1] = "be"
    words[2] = "gamma"

    assert Array.FindIndex(words, word => word.Length == 2) == 1

    converted := Array.ConvertAll(words, word => word.Length)
    assert converted.GetType() == typeof(int[])
    assert converted[0] == 5

    values := Words()
    assert values.RemoveAll(word => word.Length == 2) == 1
    assert values.Count == 2
}

// ── method groups: the same inference, a different spelling ───────────────────────────────────

test "a METHOD GROUP passed where a delegate is expected binds through the same inference" {
    values := Words()

    assert values.Count(IsLong) == 2
    assert values.Any(IsLong)
    assert values.Where(IsLong).Count() == 2

    projected := values.Select(LengthOf).ToList()
    assert projected.GetType() == typeof(List<int>)
    assert projected[0] == 5

    mapped := Apply(values, LengthOf)
    assert mapped.GetType() == typeof(List<int>)
    assert mapped[1] == 2
}

test "a method group selector's result widens into an argument exactly as a lambda's does" {
    values := Words()

    collected := new List<int>()
    collected.AddRange(values.Select(LengthOf))
    assert collected.Count == 3
    assert collected[2] == 5

    words := new string[](2)
    words[0] = "alpha"
    words[1] = "be"
    assert Array.FindIndex(words, IsLong) == 0
}

// ── §12 an extension call's result is an expression of its declared return type ───────────────

test "a concrete result widens to every interface it implements, in every position" {
    values := Words()

    byLength := AsReadOnlyDictionary(values)
    assert byLength.Count == 3
    assert byLength["gamma"] == 5

    // The DECLARED type is the interface; the RUNTIME type is still what the call produced, which
    // is what proves the widening is an ordinary conversion and not a rebuild.
    assert RuntimeTypeOf(byLength) == typeof(Dictionary<string, int>)

    sequence := AsSequence(values)
    assert RuntimeTypeOf(sequence) == typeof(List<string>)

    readOnly := AsReadOnlyList(values)
    assert readOnly.Count == 3
    assert RuntimeTypeOf(readOnly) == typeof(List<string>)

    fromArray := ArrayAsSequence(values)
    assert RuntimeTypeOf(fromArray) == typeof(string[])

    assert WidenedThroughArgument(values) == 3
    assert WidenedThroughLocal(values) == 3
}

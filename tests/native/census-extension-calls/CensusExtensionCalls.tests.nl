namespace NSharpLang.CensusExtensionCalls.Tests

import System.Collections
import System.Collections.Generic
import System.Linq
import System.Text.Json


// ── the receiver the census actually wrote: a sequence of a type THIS compilation declares ────
test "an extension call over a sequence of a source class binds and executes" {
    items := Queries()

    assert items.Any()
    assert items.Count() == 3
    assert items.First().Name == "alpha"
    assert items.Last().Name == "gamma"
    assert items.First().Describe("q-") == "q-alpha"
}

test "an extension whose RESULT is a source class carries that exact type at runtime" {
    items := Queries()

    found := items.FirstOrDefault()
    assert found != null
    assert RuntimeTypeOf(found) == typeof(Query)
    assert found.Describe("q-") == "q-alpha"
}

test "a lambda over a sequence of a source class types its parameter from the element" {
    items := Queries()

    assert items.Single(item => item.Weight == 1).Name == "be"
    assert items.Where(item => item.Weight > 1).Count() == 2
    assert items.Sum(item => item.Weight) == 6
    assert items.Select(item => item.Name).First() == "alpha"

    ordered := items.OrderBy(item => item.Weight).ToList()
    assert ordered[0].Name == "be"
    assert ordered[2].Name == "alpha"
}

test "a projection INTO a source class carries the source type through the sequence" {
    names := Words()

    projected := names.Select(name => new Query(name, name.Length)).ToList()
    assert RuntimeTypeOf(projected) == typeof(List<Query>)
    assert projected.Count == 3
    assert projected[1].Name == "be"
    assert projected[1].Weight == 2
}

test "an array of a source class is a sequence of it" {
    items := QueryArray()

    assert items.Count() == 2
    assert items.First().Name == "alpha"
    assert items.Any(item => item.Weight == 1)
}

// ── the receiver shapes: array, string, list, dictionary, interface, value element ────────────
test "an array receiver reaches extension resolution instead of an instance member" {
    words := WordArray()

    assert words.First() == "alpha"
    assert words.Last() == "gamma"
    assert words.Count() == 3
    assert words.Where(word => word.Length > 3).Count() == 2
}

test "a string is a sequence of its characters" {
    text := "alpha"

    assert text.Count() == 5
    assert text.First() == 'a'
    assert text.Count(letter => letter == 'a') == 2
}

test "a dictionary is a sequence of its pairs" {
    map := WeightsByName()

    assert map.Count() == 2
    assert map.Sum(pair => pair.Value) == 4
    assert map.Keys.Count() == 2
    assert map.Values.Max() == 3
}

test "a sequence of a value type boxes its receiver into the interface slot" {
    numbers := new List<int>()
    numbers.Add(4)
    numbers.Add(9)

    assert numbers.Sum() == 13
    assert numbers.Max() == 9

    points := Points()
    assert points.Count() == 2
    assert points.Sum(point => point.X + point.Y) == 10
}

test "an interface-typed receiver binds the same extension its concrete type does" {
    let sequence: IEnumerable<string> = Words()

    assert sequence.Count() == 3
    assert sequence.First() == "alpha"
    assert sequence.Any(word => word.Length == 2)
}

// ── the same answers a plain loop gives, so the SELECTION is proved and not merely the arity ──
test "every LINQ answer matches the loop that computes it by hand" {
    items := Queries()

    manualCount := 0
    manualWeight := 0
    manualFirst := ""
    for item in items {
        if manualCount == 0 {
            manualFirst = item.Name
        }

        manualCount = manualCount + 1
        manualWeight = manualWeight + item.Weight
    }

    assert items.Count() == manualCount
    assert items.Sum(item => item.Weight) == manualWeight
    assert items.First().Name == manualFirst
}

// ── a call that WROTE its type arguments: inference is skipped, arity must match ──────────────
test "an extension call written with explicit type arguments binds the candidate of that arity" {
    let values: IEnumerable = Words()

    // `Cast<T>` and `OfType<T>` declare a NON-GENERIC `IEnumerable` receiver, which is the shape a
    // per-member table used to hard-code. They resolve here out of the ordinary extension index.
    cast := values.Cast<string>().ToList()
    assert cast.Count == 3
    assert cast[0] == "alpha"
    assert RuntimeTypeOf(cast) == typeof(List<string>)

    let mixed: IEnumerable = MixedValues()
    strings := mixed.OfType<string>()
    numbers := mixed.OfType<int>()
    assert strings.Count() == 2
    assert numbers.Count() == 1
}

test "an explicitly closed extension over a sequence of a source class carries that type" {
    let values: IEnumerable = Queries()

    typed := values.Cast<Query>().ToList()
    assert RuntimeTypeOf(typed) == typeof(List<Query>)
    assert typed[0].Name == "alpha"
    assert typed.Count() == 3
}

test "an explicitly closed extension over a VALUE-type receiver loads the receiver by value" {
    document := JsonDocument.Parse("{\"Name\":\"alpha\",\"Weight\":7}")

    // `JsonSerializer.Deserialize<TValue>(this JsonElement, JsonSerializerOptions?)` is declared on a
    // STRUCT receiver, and its type argument is only in the RETURN — nothing to infer it from, so the
    // site has to write it.
    element := document.RootElement
    nameElement := element.GetProperty("Name")
    assert nameElement.Deserialize<string>(NoOptions()) == "alpha"

    // The trailing optional is filled from the callee's own metadata default when it is omitted.
    weightElement := element.GetProperty("Weight")
    assert weightElement.Deserialize<int>() == 7
}

// ── a lambda in every ARGUMENT position ───────────────────────────────────────────────────────
test "a lambda is a constructor argument, including into a generic closed over a source class" {
    number := new Lazy<int>(() => 1)
    assert number.Value == 1

    // A lambda whose BODY builds a class this project declares, captured into a constructor argument.
    name := new Lazy<string>(() => new Query("alpha", 3).Name)
    assert name.Value == "alpha"

    // The type argument itself may be a class this project declares: `Lazy<Query>` is an
    // instantiation whose constructor table reflection refuses to report, and the definition's own
    // constructors answer instead. (Reading `.Value` back off such an instantiation is a separate
    // limit — see website/docs/types.md — so the assertion is on the constructed object.)
    made := new Lazy<Query>(() => new Query("alpha", 3))
    assert made != null
    assert RuntimeTypeOf(made) == typeof(Lazy<Query>)
}

test "a method group is a constructor argument wherever a lambda is" {
    weight := new Lazy<int>(MakeWeight)
    assert weight.Value == 9

    // And through the same path when the delegate takes an argument.
    lengths := new List<string>()
    lengths.Add("alpha")
    lengths.Add("be")
    assert lengths.FindIndex(IsShort) == 1
}

test "a lambda reaches an indexer argument, an initializer value and a literal element" {
    // An indexer argument.
    map := new Dictionary<string, Func<int, int>>()
    map["double"] = value => value * 2
    doubler := map["double"]
    assert doubler(21) == 42

    // An object-initializer value — the member's declared type is what shapes the lambda, and a
    // delegate FIELD is written `?` whenever it has no initializer.
    holder := new Holder { Transform: value => value + 1 }
    assert holder.Transform != null
    transform := must holder.Transform
    assert transform(41) == 42

    // An array literal element.
    transforms: Func<int, int>[] = [value => value * 3, value => value - 1]
    triple := transforms[0]
    decrement := transforms[1]
    assert triple(14) == 42
    assert decrement(43) == 42
}

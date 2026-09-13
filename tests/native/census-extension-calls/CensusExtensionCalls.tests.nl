namespace NSharpLang.CensusExtensionCalls.Tests

import System.Collections.Generic
import System.Linq


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

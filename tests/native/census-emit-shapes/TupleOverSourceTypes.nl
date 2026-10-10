namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic
import System.Linq


// A TUPLE OVER A TYPE THIS COMPILATION IS STILL BUILDING, AND A TUPLE AS A LAMBDA'S RESULT.
//
// Two separate walls stood between a tuple literal and the corpus that writes them. A closed
// `ValueTuple` over a source type is a `TypeBuilderInstantiation`, whose `GetConstructor` throws —
// so the literal arm refused a builder-bound element outright and the typed-local arm reached that
// throw and took the compiler down with it. And a tuple literal had no PREFLIGHT type at all, so a
// lambda whose body is one had no inferable return type and `xs.Select(d => (d.Code, d.Line))`
// declined at the extension call while `xs.Select(d => d.Code)` emitted.
//
// The converter writes C# anonymous objects as named tuples, which is why both shapes are ordinary
// in the converted corpus rather than exotic.
class Item {
    Name: string
}

class Diag {
    Code: string
    Line: int
}

// A tuple whose FIRST element is a source class: the census shape, written as the assignment that
// reaches an already-declared local.
func GroupSizes(items: List<Item>): int {
    groups := new Dictionary<string, (Entry: Item, Ranges: List<int>)>()
    for item in items {
        let group: (Entry: Item, Ranges: List<int>) = default
        if !groups.TryGetValue(item.Name, out group) {
            group = (item, new List<int>())
            groups[item.Name] = group
        }
        group.Ranges.Add(1)
        groups[item.Name] = group
    }
    total := 0
    for name in groups.Keys {
        let entry: (Entry: Item, Ranges: List<int>) = groups[name]
        total = total + entry.Ranges.Count
    }
    return total
}

// The same tuple as a typed local's INITIALIZER — the arm that used to reach the throw.
func PairedName(item: Item): string {
    let pair: (Entry: Item, Ranges: List<int>) = (item, new List<int>())
    pair.Ranges.Add(7)
    return pair.Entry.Name + ":" + pair.Ranges.Count.ToString()
}

// A lambda whose body is a tuple literal, at a generic extension position whose result type is
// inferred from it. Element names are metadata; the declared return type carries them.
func Pairs(diagnostics: List<Diag>): List<(Code: string, Line: int)> {
    return diagnostics.Select(d => (Code: d.Code, Line: d.Line)).ToList()
}

func PositionalPairs(diagnostics: List<Diag>): List<(string, int)> {
    return diagnostics.Select(d => (d.Code, d.Line)).ToList()
}

func FirstCode(diagnostics: List<Diag>): string {
    for pair in Pairs(diagnostics) {
        return pair.Code
    }
    return ""
}

func TotalLines(diagnostics: List<Diag>): int {
    total := 0
    for pair in Pairs(diagnostics) {
        total = total + pair.Line
    }
    return total
}

// The same lambda at a grouping position, where the tuple becomes the KEY type.
func GroupCount(diagnostics: List<Diag>): int {
    return diagnostics.GroupBy(d => (d.Code, d.Line)).ToList().Count
}

func FirstGroupKeyCode(diagnostics: List<Diag>): string {
    for group in diagnostics.GroupBy(d => (d.Code, d.Line)).ToList() {
        return group.Key.Item1
    }
    return ""
}

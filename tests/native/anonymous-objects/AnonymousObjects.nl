namespace NSharpLang.AnonymousObjects.Tests

import System.Collections.Generic
import System.Linq

// THE SHAPES AN ANONYMOUS OBJECT HAS TO SURVIVE OUTSIDE THE BODY THAT CREATED IT.
//
// Every function here hands an anonymous object across a boundary the emitter has to model on its
// own: a generic parameter that closes over the synthesized type, an `object` slot, a method of a
// source class, a lambda, a LINQ projection and a `with` copy. The tests call them and read the
// values back.
func Echo<T>(value: T): T {
    return value
}

// A value of a TYPE PARAMETER inside an anonymous object is why the synthesized type is generic: a
// non-generic class could not hold `T`.
func Boxed<T>(value: T): object {
    return new { Value: value }
}

func Describe(value: object): string {
    return value.ToString() ?? ""
}

func Person(name: string, age: int): object {
    return new { Name: name, Age: age }
}

func Squares(count: int): List<int> {
    rows := Enumerable.Range(1, count).Select(n => new { N: n, Square: n * n }).ToList()
    return rows.Where(row => row.Square % 2 == 0).Select(row => row.N).ToList()
}

func LetterCounts(words: string[]): string {
    counts := words.GroupBy(word => word[0]).Select(group => new { Letter: group.Key, Count: group.Count() })
    text := ""
    for item in counts {
        text = text + item.Letter.ToString() + "=" + item.Count.ToString() + ";"
    }
    return text
}

func Older(): string {
    alice := new { Name: "Alice", Age: 30 }
    older := alice with { Age: 31 }
    return alice.ToString() + " -> " + older.ToString()
}

func Classify(age: int): string {
    person := new { Name: "Bea", Age: age }
    return match person {
        { Age: 30, Name: n } => n + " is thirty",
        _ => "other"
    }
}

class Inventory {
    Label: string

    constructor(label: string) {
        Label = label
    }

    func Summary(): string {
        summary := new { Label: Label, Length: Label.Length }
        return summary.ToString()
    }
}

namespace NSharpLang.CensusOverloadResolution.Tests

import System.Collections.Generic
import System.Text
import Census.OverloadResolution.Library

// `string.Join` OVER AN ENUMERABLE, WHEREVER THE ENUMERABLE COMES FROM.
//
// The call has seven two-argument overloads with a `string` separator, and three of them take a
// sequence: `Join(string, IEnumerable<string>)`, `Join<T>(string, IEnumerable<T>)` and the `params`
// pair `Join(string, params string?[])` / `Join(string, params object?[])`. C# binds the sequence
// overloads for every argument here (§12.6.4.5: `IEnumerable<T>` is the better conversion target than
// `object`), so the answer is the JOINED ELEMENTS. The wrong one packs the argument into an
// `object?[]` of one and prints its `ToString()` — `System.Collections.Generic.List`1[System.Int32]`.
//
// The planner's ladder already had that order for a local argument. A STATIC FIELD read by its bare
// name inside its own type was the argument nothing could type before emitting it, so the call fell
// to the emitter's own ladder — which had no generic tier and went from the non-generic candidates
// straight to the packed `params` one — or declined outright as not modeled.
class Catalog {
    static Names: List<string> = new List<string>()
    static Codes: string[] = ["a", "b", "c"]
    static Numbers: List<int> = new List<int>()
    static Sequence: IEnumerable<int> = new List<int>()
    static Items: List<Tag> = new List<Tag>()
    static Labels: List<string> => Names

    static func Reset() {
        Names.Clear()
        Names.Add("x")
        Names.Add("y")
        Numbers.Clear()
        Numbers.Add(1)
        Numbers.Add(2)
        Sequence = Numbers
        Items.Clear()
        Items.Add(new Tag("red"))
        Items.Add(new Tag("blue"))
    }

    static func JoinNames(): string => string.Join(",", Names)
    static func JoinCodes(): string => string.Join(",", Codes)
    static func JoinNumbers(): string => string.Join(",", Numbers)
    static func JoinSequence(): string => string.Join(",", Sequence)
    static func JoinItems(): string => string.Join(",", Items)
    static func JoinProperty(): string => string.Join(",", Labels)
    static func JoinWithChar(): string => string.Join('|', Names)
    static func ConcatNames(): string => string.Concat(Names)
    static func ConcatNumbers(): string => string.Concat(Numbers)
    static func QualifiedNumbers(): string => string.Join(",", Catalog.Numbers)

    static func AppendNumbers(): string {
        builder := new StringBuilder()
        builder.AppendJoin("+", Numbers)
        return builder.ToString()
    }

    func FromInstanceBody(): string => string.Join(";", Numbers)
}

class Tag {
    Name: string

    constructor(name: string) {
        Name = name
    }

    override func ToString(): string => "tag:" + Name
}

// The same overloads over locals, which the planner has always owned: the two ladders must agree.
func JoinLocalShapes(): List<string> {
    list := new List<string>()
    list.Add("p")
    list.Add("q")
    array: string[] = ["r", "s"]
    numbers: IEnumerable<int> = [4, 5]
    tags := new List<Tag>()
    tags.Add(new Tag("green"))
    objects: object[] = ["o", 6]
    results := new List<string>()
    results.Add(string.Join(",", list))
    results.Add(string.Join(",", array))
    results.Add(string.Join(",", numbers))
    results.Add(string.Join(",", tags))
    results.Add(string.Join(",", objects))
    results.Add(string.Join(",", "only"))
    results.Add(string.Join(",", "one", "two"))
    return results
}

// A REFERENCED ASSEMBLY'S STATIC STATE: qualified, and bare from a class deriving from its owner.
class RegistryView: Registry {
    static func BareNames(): string => string.Join(",", Names)
    static func BareNumbers(): string => string.Join(",", Numbers)
    static func BareEntries(): string => string.Join(",", Entries)
    static func BareLabels(): string => string.Join(",", Labels)
}

func JoinReferencedQualified(): List<string> {
    results := new List<string>()
    results.Add(string.Join(",", Registry.Names))
    results.Add(string.Join(",", Registry.Numbers))
    results.Add(string.Join(",", Registry.Entries))
    results.Add(string.Join(",", Registry.Labels))
    return results
}

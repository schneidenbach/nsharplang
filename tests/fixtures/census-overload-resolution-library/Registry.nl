namespace Census.OverloadResolution.Library

import System.Collections.Generic

// THE STATIC STATE `tests/native/census-overload-resolution` PASSES TO `string.Join` FROM ANOTHER
// ASSEMBLY.
//
// Each field is an enumerable of a different element: `string` (the non-generic
// `Join(string, IEnumerable<string>)`), `int` (only `Join<T>` reads it as a sequence) and a class
// this assembly declares (`Join<T>` over a type the consumer did not write). The consumer reads them
// qualified, as `Registry.Names`, and bare from inside a class deriving from `Registry`, where a
// static member the base declares is a name in scope.
class Entry {
    Name: string

    constructor(name: string) {
        Name = name
    }

    override func ToString(): string => "entry:" + Name
}

class Registry {
    static Names: List<string> = new List<string>()
    static Numbers: List<int> = new List<int>()
    static Entries: List<Entry> = new List<Entry>()
    static Labels: IEnumerable<string> => Names

    static func Reset() {
        Names.Clear()
        Numbers.Clear()
        Entries.Clear()
        Names.Add("north")
        Names.Add("south")
        Numbers.Add(3)
        Numbers.Add(5)
        Entries.Add(new Entry("first"))
        Entries.Add(new Entry("second"))
    }
}

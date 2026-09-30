namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic
import System.Text


// A GENERATOR WRITES THROUGH THE SAME TARGETS A PLAIN FUNCTION DOES.
//
// An assignment whose target is an indexer or a member is an ordinary store: the member a name
// selects, the `set_Item` an index list selects and the conversion the stored value takes are the
// answers the identical statement gets outside a `func*`. Each generator below is enumerated beside
// this file and the OBJECT IT WROTE INTO is asserted afterwards, so the store is observed rather than
// inspected.
class CensusBox {
    Value: int
    Label: string

    constructor() {
        Value = 0
        Label = ""
    }
}

// A settable member of an instance the generator captured.
func* StoresIntoBox(box: CensusBox): IEnumerable<int> {
    box.Value = 5
    box.Label = "set"
    yield box.Value
    label := box.Label
    yield label.Length
}

// A `Dictionary<K, V>` indexer, written and read back, including a compound read-modify-write spelled
// out as a store of a value the generator computed.
func* StoresIntoDictionary(table: Dictionary<string, int>): IEnumerable<int> {
    table["a"] = 1
    yield table["a"]
    table["a"] = table["a"] + 10
    yield table["a"]
}

// A `List<T>` indexer: the same `set_Item` resolution over a different overload set.
func* StoresIntoList(values: List<int>): IEnumerable<int> {
    values[0] = 42
    yield values[0]
}

// An ARRAY element: `stelem` with the element conversion an assignment takes.
func* StoresIntoArray(values: int[]): IEnumerable<int> {
    values[1] = 9
    yield values[1]
}

// A settable BCL PROPERTY, paired with the getter the read side selects.
func* StoresIntoProperty(builder: StringBuilder): IEnumerable<int> {
    builder.Append("abcd")
    builder.Length = 2
    yield builder.Length
}

// An INSTANCE generator writing its enclosing type's own members through the receiver it captured.
class CensusCounter {
    Total: int
    Tag: string

    constructor() {
        Total = 0
        Tag = ""
    }

    func* Count(n: int): IEnumerable<int> {
        i := 0
        while i < n {
            Total = Total + i
            Tag = "seen"
            yield Total
            i = i + 1
        }
    }
}

namespace NSharpLang.CensusSourceTypedGenericReceiver.Tests

import System.Collections.Generic


// CENSUS — A MEMBER AN EXTERNAL GENERIC INTERFACE INHERITS, REACHED THROUGH A RECEIVER CLOSED OVER A
// TYPE THIS COMPILATION IS WRITING.
//
// `IList<Row>` for a source class `Row` is a `TypeBuilderInstantiation`: it answers no member query
// and no interface list of its own, so both resolvers read what they need off the open DEFINITION.
// Both read only what the definition DECLARES, and an interface declares almost nothing —
// `IList<T>`'s `Add`, `Count`, `Contains`, `Clear` and `IsReadOnly` are all `ICollection<T>`'s. So
// every one of them declined while the identical call on `IList<string>` bound, which is the same
// defect `ILogger<TheHandler>.IsEnabled` has: `ILogger<out TCategoryName>` declares nothing and
// `ILogger` declares everything.
//
// The definition's own interface list IS reachable, and closing it over this instantiation's
// arguments names exactly the interfaces the receiver has. The rows below run.
class Row {
    label: string

    constructor(label: string) {
        this.label = label
    }

    Label: string => label
}

class SourceTypedGenericReceiver {

    // `Add` and `Contains` are `ICollection<T>`'s; `IsReadOnly` and `Count` are too. The parameter
    // and the element are the source type, so the substitution has to close them as well.
    static func AddAndCount(rows: IList<Row>, row: Row): string {
        rows.Add(row)
        return rows.Count.ToString() + ":" + rows.Contains(row).ToString() + ":" + rows.IsReadOnly.ToString()
    }

    // `IndexOf` and the indexer ARE `IList<T>`'s own, so this row is the control that says the
    // definition's own declarations still bind.
    static func IndexOfLabel(rows: IList<Row>, row: Row): string {
        index := rows.IndexOf(row)
        if index < 0 {
            return "missing"
        }
        return index.ToString() + ":" + rows[index].Label
    }

    // `Clear` is `ICollection<T>`'s, reached through `IList<T>`.
    static func ClearedCount(rows: IList<Row>): int {
        rows.Clear()
        return rows.Count
    }

    // Two hops of interface inheritance: `IReadOnlyList<T>` declares only its indexer, `Count` is
    // `IReadOnlyCollection<T>`'s.
    static func ReadOnlyCount(rows: IReadOnlyList<Row>): int {
        return rows.Count
    }

    // A TWO-PARAMETER instantiation, one argument of which is the source type, reaching a member
    // declared on `ICollection<KeyValuePair<TKey, TValue>>` — a base whose own argument is built out
    // of the instantiation's arguments rather than being one of them.
    static func DictionaryClearedCount(rows: IDictionary<string, Row>, row: Row): string {
        rows.Add(row.Label, row)
        before := rows.Count.ToString() + ":" + rows.ContainsKey(row.Label).ToString()
        rows.Clear()
        return before + ":" + rows.Count.ToString()
    }

    // THE CONTROL. The identical reads over a non-source argument always bound; they must keep
    // binding, and to the same answers.
    static func AddAndCountText(rows: IList<string>, text: string): string {
        rows.Add(text)
        return rows.Count.ToString() + ":" + rows.Contains(text).ToString() + ":" + rows.IsReadOnly.ToString()
    }
}

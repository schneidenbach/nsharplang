namespace NSharpLang.ReadOnlyDictionaryWidening.Tests

import System
import System.Collections.Generic

// REFERENCE COVARIANCE THROUGH A COVARIANT INTERFACE SLOT.
//
// `IReadOnlyList<out T>` says a `List<Item>` IS an `IReadOnlyList<object>` whenever `Item` is a
// reference type, and the conversion costs no IL: it is the same object. Both of the emitter's
// argument-equivalence predicates compared the slots for IDENTITY, so the whole collection upcast
// family refused every widening element and `rows: IReadOnlyList<object> = items` declined at
// `emit.typed-local.type-mismatch`. The element type here is one THIS COMPILATION declares, which
// is the case reflection cannot answer for itself.
class WideningItem {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

func WideningItems(): List<WideningItem> {
    items := new List<WideningItem>()
    items.Add(new WideningItem("a"))
    items.Add(new WideningItem("b"))
    return items
}

func WideningCount(rows: IReadOnlyList<object>): int {
    return rows.Count
}

func WideningFirstName(rows: IReadOnlyList<object>): string {
    first := rows[0] as WideningItem
    if first == null {
        return ""
    }

    return first.Name
}

func WideningEnumerated(values: IEnumerable<object>): int {
    total := 0
    for value in values {
        _ = value
        total = total + 1
    }

    return total
}

test "a List over a source type widens to IReadOnlyList of object" {
    items := WideningItems()
    rows: IReadOnlyList<object> = items
    assert rows.Count == 2

    // The widened view is the SAME object, so the elements are the very items that went in.
    first := rows[0] as WideningItem
    assert first != null
    assert (first ?? new WideningItem("")).Name == "a"
}

test "the widened view reaches the collection and enumerable slots too" {
    items := WideningItems()
    collection: IReadOnlyCollection<object> = items
    assert collection.Count == 2

    values: IEnumerable<object> = items
    assert WideningEnumerated(values) == 2
}

test "the widening also applies at an argument position" {
    items := WideningItems()
    assert WideningCount(items) == 2
    assert WideningFirstName(items) == "a"
    assert WideningEnumerated(items) == 2
}

test "a List over an external reference type widens the same way" {
    texts := new List<string>()
    texts.Add("x")
    texts.Add("y")
    texts.Add("z")

    rows: IReadOnlyList<object> = texts
    assert rows.Count == 3
    assert (rows[1] as string) == "y"
    assert WideningEnumerated(texts) == 3

    // An intermediate base, not only `object`.
    comparables: IEnumerable<IComparable> = texts
    total := 0
    for value in comparables {
        _ = value
        total = total + 1
    }
    assert total == 3
}

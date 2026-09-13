namespace NSharpLang.CensusAccessibility.Tests

test "a source type calls its generic external base's protected methods through this and base" {
    collection := new GuardedCollection()
    collection.Add("a")
    collection.Add("b")
    assert collection.Count == 2

    // `Collection<T>.SetItem` is `protected virtual`: named through `this`, it replaces the element.
    collection.ReplaceThroughThis(1, "y")
    assert collection[1] == "y"
    assert collection.Count == 2

    // `base.InsertItem` is the same member reached through `base`, emitted as a non-virtual call.
    collection.InsertThroughBase(0, "first")
    assert collection.Count == 3
    assert collection[0] == "first"

    collection.ClearThroughBase()
    assert collection.Count == 0
}

test "a protected method of a non-generic external base is callable through this and base" {
    // `TextWriter.Dispose(bool)` is protected; both receiver forms reach it and the writer closes.
    throughThis := new LineAwareWriter()
    throughThis.Write("kept")
    assert throughThis.ToString() == "kept"
    throughThis.ReleaseThroughThis()

    throughBase := new LineAwareWriter()
    throughBase.Write("also kept")
    assert throughBase.ToString() == "also kept"
    throughBase.ReleaseThroughBase()
}

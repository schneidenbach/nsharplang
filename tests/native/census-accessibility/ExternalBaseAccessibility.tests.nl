namespace NSharpLang.CensusAccessibility.Tests

import System

test "a source type calls its generic external base's protected methods through this and base" {
    collection := new GuardedCollection()
    collection.Add("a")
    collection.Add("b")
    assert collection.Count == 2

    // `Collection<T>.SetItem` is `protected virtual`: named through `this`, it replaces the element.
    collection.ReplaceThroughThis(1, "y")
    assert collection[1] == "y"
    assert collection.Count == 2

    // ...and named with no receiver, which is the same `this.SetItem` written without the word.
    collection.ReplaceWithoutReceiver(0, "x")
    assert collection[0] == "x"
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

test "a protected property of a generic external base is read through this, base and no receiver" {
    collection := new ReadingCollection()
    collection.Add("alpha")
    collection.Add("beta")

    assert collection.ItemCountThroughThis() == 2
    assert collection.ItemCountThroughBase() == 2
    assert collection.FirstItem() == "alpha"

    // The read is the base's own storage, not a copy: removing through the public surface moves it.
    collection.RemoveAt(0)
    assert collection.ItemCountThroughThis() == 1
    assert collection.FirstItem() == "beta"
}

test "a protected field of a non-generic external base is read at its own array type" {
    writer := new ReadingWriter()

    assert writer.NewLineLengthThroughThis() == Environment.NewLine.Length
    assert writer.NewLineLengthThroughBase() == Environment.NewLine.Length
    assert writer.NewLineFirst() == Environment.NewLine[0]

    // It is the FIELD, so writing the base's own property is observed by the read.
    writer.UseBangTerminator()
    assert writer.NewLineLengthThroughThis() == 1
    assert writer.NewLineFirst() == '!'
}

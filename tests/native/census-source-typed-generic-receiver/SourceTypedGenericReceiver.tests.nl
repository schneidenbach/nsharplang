namespace NSharpLang.CensusSourceTypedGenericReceiver.Tests

import System.Collections.Generic

test "an inherited ICollection member binds through an IList closed over a source type" {
    rows := new List<Row>()
    assert SourceTypedGenericReceiver.AddAndCount(rows, new Row("a")) == "1:True:False"
    assert SourceTypedGenericReceiver.AddAndCount(rows, new Row("b")) == "2:True:False"
    assert rows.Count == 2
}

test "the interface's own declarations still bind beside the inherited ones" {
    first := new Row("a")
    rows := new List<Row>()
    rows.Add(first)
    rows.Add(new Row("b"))
    assert SourceTypedGenericReceiver.IndexOfLabel(rows, first) == "0:a"
    assert SourceTypedGenericReceiver.IndexOfLabel(rows, new Row("z")) == "missing"
}

test "an inherited Clear runs on the receiver it was called on" {
    rows := new List<Row>()
    rows.Add(new Row("a"))
    assert SourceTypedGenericReceiver.ClearedCount(rows) == 0
    assert rows.Count == 0
}

test "Count reached two interfaces up answers on a read-only list of a source type" {
    rows := new List<Row>()
    rows.Add(new Row("a"))
    rows.Add(new Row("b"))
    rows.Add(new Row("c"))
    assert SourceTypedGenericReceiver.ReadOnlyCount(rows) == 3
}

test "a two-argument instantiation reaches a base whose own argument is built from both" {
    rows := new Dictionary<string, Row>()
    assert SourceTypedGenericReceiver.DictionaryClearedCount(rows, new Row("k")) == "1:True:0"
    assert rows.Count == 0
}

test "the same reads over a non-source argument still answer the same way" {
    rows := new List<string>()
    assert SourceTypedGenericReceiver.AddAndCountText(rows, "a") == "1:True:False"
    assert SourceTypedGenericReceiver.AddAndCountText(rows, "b") == "2:True:False"
}

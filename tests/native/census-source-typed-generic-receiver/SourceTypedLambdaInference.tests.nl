namespace NSharpLang.CensusSourceTypedGenericReceiver.Tests

import System.Collections.Generic

test "ConvertAll infers its output from a lambda over a local list of a source type" {
    assert SourceTypedLambdaInference.LocalLabels() == "zy"
}

test "ConvertAll over a source-typed list closes to a value-type output" {
    rows := new List<Row>()
    rows.Add(new Row("abcd"))
    assert SourceTypedLambdaInference.LocalLengths(rows) == 4
}

test "ConvertAll over a source-typed list can output the source type itself" {
    rows := new List<Row>()
    rows.Add(new Row("ab"))
    assert SourceTypedLambdaInference.LocalRoundTrip(rows) == "abab"
}

test "a bare ConvertAll inside a class inheriting a source-typed list runs on this" {
    rows := new RowLabels()
    rows.Add(new Row("a"))
    rows.Add(new Row("b"))
    labels := rows.Bare()
    assert labels.Count == 2
    assert labels[0] == "a"
    assert labels[1] == "b"
}

test "this.ConvertAll inside a class inheriting a source-typed list runs on this" {
    rows := new RowLabels()
    rows.Add(new Row("a"))
    assert rows.ThroughThis()[0] == "a!"
}

test "ConvertAll through a derived receiver from outside reaches the inherited member" {
    rows := new RowLabels()
    rows.Add(new Row("low"))
    assert SourceTypedLambdaInference.OutsideDerived(rows) == "LOW"
}

test "the same inference over a non-source argument still answers the same way" {
    texts := new List<string>()
    texts.Add("three")
    assert SourceTypedLambdaInference.TextLengths(texts) == 5
}

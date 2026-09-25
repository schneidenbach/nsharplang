namespace NSharpLang.CensusGenericCalleeReceiver.Tests

import System.Collections.Generic
import System.Linq

test "an explicit generic extension binds over a CALL receiver" {
    Source.Reset()

    strings := Source.Mixed().OfType<string>().ToList()

    assert strings.Count == 2
    assert strings[0] == "alpha"
    assert strings[1] == "gamma"
    // The receiver ran ONCE. The text reading this replaced walked the receiver twice — once to
    // type it and once to load it — and refused a call outright rather than evaluate it twice.
    assert Source.Calls == 1
}

test "a chain of explicit generic extensions binds at every link" {
    Source.Reset()

    boxed := Source.Mixed().OfType<string>().Cast<object>().ToList()

    assert boxed.Count == 2
    assert boxed[0].ToString() == "alpha"
    assert Source.Calls == 1
}

test "a three-link chain types its middles as well as its ends" {
    Source.Reset()

    round := Source.Mixed().OfType<string>().Cast<object>().OfType<string>().ToList()

    assert round.Count == 2
    assert round[1] == "gamma"
    assert Source.Calls == 1
}

test "the plain-name receiver still binds, unchanged" {
    Source.Reset()

    values := Source.Mixed()
    nodes := values.OfType<Node>().ToList()

    assert nodes.Count == 1
    assert nodes[0].Describe() == "delta:4"
    assert Source.Calls == 1
}

test "a source type's generic instance method chains on its own call result" {
    registry := new Registry()

    chained := registry.Add<string>().Add<int>().Add<Node>()

    assert chained.Count() == 3
    assert registry.Entries[0] == "String"
    assert registry.Entries[1] == "Int32"
    assert registry.Entries[2] == "Node"
    // The chain returns `this`, so the same instance came back out of the last link.
    assert chained.Count() == registry.Count()
}

test "the chain's receiver may itself be a bare sibling call" {
    chained := MakeRegistry().Add<string>().Add<int>()

    assert chained.Count() == 2
    assert chained.Entries[0] == "String"
}

test "an explicit generic chain inside a lambda captures its enclosing receiver" {
    Source.Reset()

    values := Source.Mixed()
    project: System.Func<int> = () => values.OfType<string>().Cast<object>().Count()

    assert project() == 2
    assert Source.Calls == 1
}

test "an explicit generic chain is an ordinary argument and an ordinary foreach source" {
    Source.Reset()

    joined := string.Join(",", Source.Mixed().OfType<string>().ToArray())
    assert joined == "alpha,gamma"

    seen := new List<string>()
    for item in Source.Mixed().OfType<string>().Cast<string>() {
        seen.Add(item)
    }

    assert seen.Count == 2
    assert seen[0] == "alpha"
    // Two written receivers, two evaluations — the fix does not cache, it stops re-walking.
    assert Source.Calls == 2
}

test "the type argument still decides the member, not the receiver's spelling" {
    Source.Reset()

    nodes := Source.Mixed().OfType<Node>().ToList()
    integers := Source.Mixed().OfType<int>().ToList()

    assert nodes.Count == 1
    assert integers.Count == 1
    assert integers[0] == 3
    assert Source.Calls == 2
}

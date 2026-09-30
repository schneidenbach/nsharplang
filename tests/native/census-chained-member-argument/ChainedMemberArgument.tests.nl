namespace NSharpLang.CensusChainedMemberArgument.Tests

import System
import System.Collections.Generic
import System.Numerics

test "a two-hop source chain is typable in argument position, and one hop already was" {
    root := NewRoot("alpha", 7)
    assert HashTwoHops(root) == HashOneHop(root.Mid)
}

test "a three-hop chain ending in a value field reaches the argument" {
    assert ThreeHopValue(NewRoot("alpha", 7)) == "7"
}

test "an element hop and a dictionary hop both compose with the member read after them" {
    root := NewRoot("beta", 2)
    assert ElementHopTag(root) == "beta"
    assert MapHopTag(root) == "beta"
}

test "a call hop in the middle and a call at the end of two hops both reach the argument" {
    root := NewRoot("gamma", 3)
    assert CallOverTwoHops(root) == "gamma:3"
    expected := new HashCode()
    expected.Add(CallOverTwoHops(root).Length)
    assert CallHopLength(root) == expected.ToHashCode()
}

test "a value-type hop in the middle of the chain is read through its address" {
    assert ValueTypeHopYear(NewRoot("delta", 1)) == "2026"
}

test "the same shapes over referenced types only" {
    root := new Uri("https://example.com/a/b")
    assert ExternalTwoHops(root) == "example.com"
    pair := new KeyValuePair<string, Uri>("k", root)
    assert ExternalChainHost(pair) == "example.com"
    assert ExternalChainSegmentCount(pair) == "3"
}

test "a chained argument evaluates left to right, after the call's receiver, once per hop" {
    steps := RecordedOrder()
    assert steps.Count == 3
    assert steps[0] == "receiver"
    assert steps[1] == "outer"
    assert steps[2] == "inner"
    assert OuterHopReadCount() == 1
}

test "a hop through a referenced type's own indexer reaches the argument, by name and by number" {
    assert NamedGroupWordCount("colors=red green blue") == 3
    assert NumberedGroupWordCount("colors=red green blue") == 3
}

test "two indexers in one chain, and an overload chosen by the indexed member's bool" {
    assert SecondPairKey("a=1;b=2") == "b!"
    assert GroupMatched("a=1", "key") == "True"
    assert GroupMatched("a=1", "missing") == "False"
}

test "a value-type receiver's indexer reaches the argument through its address" {
    values := new int[](Vector<int>.Count)
    index := 0
    while index < values.Length {
        values[index] = index * 10
        index = index + 1
    }
    assert LaneOrFloor(values, 1, 5) == 10
    assert LaneOrFloor(values, 0, 5) == 5
}

test "an indexer hop evaluates its receiver, then its selector, for reference and value receivers" {
    steps := IndexerOrder(new OrderLog(), "k=v")
    assert steps.Count == 4
    assert steps[0] == "groups"
    assert steps[1] == "name"
    assert steps[2] == "vector"
    assert steps[3] == "lane"
}

test "a generator yields through a referenced type's indexer, for reference and value receivers" {
    keys := new List<string>(PairKeys("a=1;bb=2"))
    assert keys.Count == 2
    assert keys[0] == "a"
    assert keys[1] == "bb"

    values := new int[](Vector<int>.Count)
    values[1] = 42
    log := new OrderLog()
    lanes := new List<int>(LanesThenOrder(log, values))
    assert lanes.Count == 2
    assert lanes[0] == 42
    assert lanes[1] == 3
    assert log.Steps.Count == 2
    assert log.Steps[0] == "vector"
    assert log.Steps[1] == "lane"
}

test "a source constructor takes its arguments through a referenced type's indexer" {
    leaf := LeafFromPair("key=four")
    assert leaf.Tag == "key"
    assert leaf.Size == 4
}

test "a lambda whose body is a referenced type's indexer read infers its delegate from it" {
    names := new List<string>()
    names.Add("value")
    names.Add("key")
    groups := GroupsNamed("id=seven", names)
    assert groups.Count == 2
    assert groups[0].Value == "seven"
    assert groups[1].Value == "id"
}

test "a generator reads an indexer its receiver inherits from a referenced base" {
    tags := new Tags()
    tags.Add("first")
    tags.Add("last")
    read := new List<string>(TagsThenLast(tags))
    assert read.Count == 2
    assert read[0] == "first"
    assert read[1] == "last!"
}

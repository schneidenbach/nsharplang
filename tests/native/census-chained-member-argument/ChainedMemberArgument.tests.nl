namespace NSharpLang.CensusChainedMemberArgument.Tests

import System
import System.Collections.Generic

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

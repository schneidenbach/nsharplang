namespace NSharpLang.SourceTypedExplicitGenericExtension.Tests

import System.Collections
import System.Collections.Generic
import System.Linq


// ── the exact shape Compiler.Core writes: a property receiver, a source type argument, no args ──
test "an explicit OfType over a source-typed property receiver binds with zero arguments" {
    unit := MakeUnit()

    nodes := unit.Items.OfType<Node>().ToList()
    assert nodes.Count == 2
    assert nodes[0].Name == "alpha"
    assert nodes[1].Name == "gamma"
    assert RuntimeTypeOf(nodes) == typeof(List<Node>)
    assert RuntimeTypeOf(nodes[0]) == typeof(Node)
}

test "the same call drives a foreach directly, with no intermediate local" {
    unit := MakeUnit()

    described := new List<string>()
    for item in unit.Items.OfType<Node>() {
        described.Add(item.Describe())
    }

    assert described.Count == 2
    assert described[0] == "alpha:3"
    assert described[1] == "gamma:2"
}

test "a foreach over an explicitly closed extension types its loop variable from the type argument" {
    values := MixedList()

    total := 0
    for node in values.OfType<Node>() {
        // `node` is a `Node` — a member of the SOURCE class, not of `object`.
        total = total + node.Weight
    }

    assert total == 5
}

test "OfType filters a source element out of a mixed sequence and a struct element in" {
    values := MixedList()

    assert values.OfType<Node>().Count() == 2
    assert values.OfType<Tag>().Count() == 1
    assert values.OfType<Tag>().First().Value == 4
    assert values.OfType<Leaf>().Count() == 0
}

test "a local whose declared type is a source-element list is the same receiver shape" {
    let nodes: List<Node> = NodeList()

    // The receiver's own element is already `Node`; the explicit argument still has to bind.
    assert nodes.OfType<Node>().Count() == 2
    assert nodes.OfType<Node>().First().Name == "alpha"
}

test "an array of a source class is a receiver for an explicitly closed extension" {
    items := NodeArray()

    assert items.OfType<Node>().Count() == 2
    assert items.Cast<Node>().ToList()[1].Name == "be"
}

test "Cast over a source-typed receiver carries the source type at runtime" {
    unit := MakeUnit()

    cast := unit.Nodes.Cast<Node>().ToList()
    assert RuntimeTypeOf(cast) == typeof(List<Node>)
    assert cast.Count == 2
    assert cast[0].Name == "one"
}

// ── the relation must still answer for receivers that hold no source type at all ─────────────
test "an explicitly closed extension over a framework-typed receiver is unchanged" {
    let names: IEnumerable = MakeUnit().Names

    assert names.OfType<string>().Count() == 2
    assert names.Cast<string>().First() == "alpha"
}

test "an explicitly closed extension over a source-typed receiver of framework elements binds" {
    words := new List<string>()
    words.Add("alpha")
    words.Add("be")

    assert words.OfType<string>().Count() == 2

    lengths := new List<int>()
    for word in words.OfType<string>() {
        lengths.Add(word.Length)
    }
    assert lengths[0] == 5
    assert lengths[1] == 2
}

namespace NSharpLang.PatternForeach.Tests

import System
import System.Collections.Generic

func ShapesUnderTest(): BclShapes {
    return new BclShapes()
}

func SampleList(): List<int> {
    values := new List<int>()
    values.Add(2)
    values.Add(3)
    values.Add(5)
    return values
}

func SampleMap(): Dictionary<string, int> {
    map := new Dictionary<string, int>()
    map["ab"] = 10
    map["cde"] = 20
    return map
}

test "a generic collection iterates through its own struct enumerator" {
    shapes := ShapesUnderTest()
    assert shapes.SumList(SampleList()) == 10
    assert shapes.SumList(new List<int>()) == 0
}

test "an array and a string iterate as index loops" {
    shapes := ShapesUnderTest()
    values := new int[](3)
    values[0] = 4
    values[1] = 5
    values[2] = 6
    assert shapes.SumArray(values) == 15
    assert shapes.SumArray(new int[](0)) == 0
    assert shapes.CountCharacters("a b c") == 3
    assert shapes.CountCharacters("") == 0
}

test "a mutable span iterates without a protected region" {
    shapes := ShapesUnderTest()
    values := new int[](4)
    values[0] = 1
    values[1] = 2
    values[2] = 3
    values[3] = 4
    assert shapes.SumSpan(new Span<int>(values)) == 10
}

test "a read-only span iterates without a protected region" {
    shapes := ShapesUnderTest()
    assert shapes.CountVowels("sequence".AsSpan()) == 4
}

test "a dictionary iterates its pairs, its keys and its values" {
    shapes := ShapesUnderTest()
    map := SampleMap()
    assert shapes.SumPairs(map) == 35
    assert shapes.JoinKeys(map) == "abcde"
    assert shapes.SumValues(map) == 30
}

test "the collections no name table listed iterate" {
    shapes := ShapesUnderTest()

    stack := new Stack<int>()
    stack.Push(1)
    stack.Push(2)
    assert shapes.SumStack(stack) == 3

    queue := new Queue<int>()
    queue.Enqueue(7)
    queue.Enqueue(8)
    assert shapes.SumQueue(queue) == 15

    set := new HashSet<int>()
    set.Add(4)
    set.Add(9)
    assert shapes.SumSet(set) == 13
}

test "a sequence interface iterates through the interface enumerator" {
    shapes := ShapesUnderTest()
    assert shapes.SumSequence(SampleList()) == 10
    assert shapes.SumReadOnlyList(SampleList()) == 10
    assert shapes.CountUntyped(SampleList()) == 3
}

test "a struct enumerator from a referenced assembly iterates in place" {
    shapes := ShapesUnderTest()
    assert shapes.SumJsonLengths("[[1,2],[3],[]]") == 3
    assert shapes.SumJsonLengths("[]") == 0
    assert shapes.JoinJsonPropertyNames("{\"a\":1,\"b\":2}") == "ab"
}

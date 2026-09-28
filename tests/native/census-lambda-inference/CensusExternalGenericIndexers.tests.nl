namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Numerics


// ── a lambda body reading a constructed external generic's indexer ─────────────────────────────
test "Select over a Vector<int> lane read fixes TResult as int" {
    lanes := new int[](Vector<int>.Count)
    index := 0
    while index < lanes.Length {
        lanes[index] = index * 10
        index = index + 1
    }

    v := new Vector<int>(lanes)
    names := new List<string>()
    names.Add("a")
    names.Add("ab")

    values := LaneValues(v, names)
    assert values.Count == 2
    assert values[0] == 10
    assert values[1] == 20
    assert FirstLane(v, names) == 10
}

test "an ArraySegment over a source record answers the record, so its members resolve" {
    tags: Tag[] = [new Tag { Name: "zero" }, new Tag { Name: "one" }, new Tag { Name: "two" }]
    segment := new ArraySegment<Tag>(tags, 1, 2)
    positions := new List<int>()
    positions.Add(1)
    positions.Add(0)

    names := TagNames(segment, positions)
    assert names.Count == 2
    assert names[0] == "two"
    assert names[1] == "one"
}

namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic

test "a for-in body that always returns takes the first element" {
    values := new List<int>()
    values.Add(7)
    values.Add(9)

    assert FirstOrFallback(values) == 7
}

test "the same loop over an empty collection runs the trailing return" {
    assert FirstOrFallback(new List<int>()) == -1
}

test "an array for-in body that always returns takes the first element" {
    assert FirstArrayOrFallback([4, 5, 6]) == 4

    empty: int[] = []
    assert FirstArrayOrFallback(empty) == -1
}

test "a string for-in body that always returns takes the first character" {
    assert FirstCharOrFallback("nlc") == 'n'
    assert FirstCharOrFallback("") == '?'
}

test "a counted for body that always returns takes the first element" {
    assert FirstCountedOrFallback([11, 12]) == 11

    empty: int[] = []
    assert FirstCountedOrFallback(empty) == -1
}

test "a scan loop whose every path returns or continues still iterates" {
    values := new List<int>()
    values.Add(3)
    values.Add(5)
    values.Add(8)
    values.Add(10)

    assert FirstEvenOrFallback(values) == 8
}

test "a scan loop that finds nothing runs the trailing return" {
    values := new List<int>()
    values.Add(1)
    values.Add(3)

    assert FirstEvenOrFallback(values) == -1
}

test "a disposable enumerator loop disposes and returns through the body tail" {
    values := new List<int>()
    values.Add(-2)
    values.Add(6)

    assert FirstPositiveOrFallback(values) == 6
    assert FirstPositiveOrFallback(new List<int>()) == -1
}

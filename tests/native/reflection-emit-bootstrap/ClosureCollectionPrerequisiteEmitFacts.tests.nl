namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Collections.Generic

class ClosureCollectionPrerequisiteEmitFacts {
    static func SortedWords(values: SortedSet<string>): string {
        enumerator := values.GetEnumerator()
        result := ""
        try {
            while enumerator.MoveNext() {
                if result.Length > 0 {
                    result = result + "|"
                }
                result = result + enumerator.get_Current()
            }
        } finally {
            enumerator.Dispose()
        }
        return result
    }

    static func AdvanceAfterMutation(values: SortedSet<string>): bool {
        enumerator := values.GetEnumerator()
        advanced := false
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The mutation control requires an initial value.")
            }
            if !values.Add("late") {
                throw new InvalidOperationException("The mutation control requires a new value.")
            }
            advanced = enumerator.MoveNext()
        } finally {
            enumerator.Dispose()
        }
        return advanced
    }
}

test "packaged collection constructors preserve comparer order and duplicate semantics" {
    source := new HashSet<string>(StringComparer.Ordinal)
    assert source.Add("b")
    assert source.Add("A")
    assert source.Add("a")

    ordinalHash := new HashSet<string>(source, StringComparer.Ordinal)
    ignoreCaseHash := new HashSet<string>(source, StringComparer.OrdinalIgnoreCase)
    assert ordinalHash.get_Count() == 3
    assert ignoreCaseHash.get_Count() == 2
    assert !ignoreCaseHash.Add("a")

    copiedSorted := new SortedSet<string>(source, StringComparer.Ordinal)
    assert copiedSorted.get_Count() == 3
    assert !copiedSorted.Add("a")
    assert ClosureCollectionPrerequisiteEmitFacts.SortedWords(copiedSorted) == "A|a|b"

    directSorted := new SortedSet<string>(StringComparer.OrdinalIgnoreCase)
    assert directSorted.Add("b")
    assert directSorted.Add("A")
    assert !directSorted.Add("a")
    assert ClosureCollectionPrerequisiteEmitFacts.SortedWords(directSorted) == "A|b"

    assert throws InvalidOperationException {
        ClosureCollectionPrerequisiteEmitFacts.AdvanceAfterMutation(copiedSorted)
    }
    assert copiedSorted.Contains("late")
}

test "packaged Dictionary Keys remain live through copy and union operations" {
    values := new Dictionary<string, int>(StringComparer.Ordinal)
    liveKeys := values.Keys
    values["first"] = 1

    copied := new HashSet<string>(liveKeys, StringComparer.Ordinal)
    assert copied.get_Count() == 1
    assert copied.Contains("first")

    values["second"] = 2
    copied.UnionWith(liveKeys)
    assert copied.get_Count() == 2
    assert copied.Contains("second")
}

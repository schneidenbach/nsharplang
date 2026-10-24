namespace NSharpLang.ConstructionArrays.Tests

// A COLLECTION TARGET IS ITS TYPE, NOT ITS SPELLING. Every declaration here names a runtime collection
// written out in full, never through `import System.Collections.Generic`,
// so each literal below is target-typed only because the compiler read the head the definition
// proved. These spellings were `NL202` ("but the value is 'string[]'" / "'unknown[]'") before.
class QualifiedCollectionHolder {
    Items: System.Collections.Generic.List<string>
    Tags: System.Collections.Generic.HashSet<int>
    Defaulted: System.Collections.Generic.List<string> = ["seed"]
    Counts: System.Collections.Generic.IReadOnlyList<int> = [4, 5]
}

func QualifiedCount(values: System.Collections.Generic.List<string>): int {
    return values.Count
}

func QualifiedReadOnlyCount(values: System.Collections.Generic.IReadOnlyList<int>): int {
    return values.Count
}

func QualifiedSequenceLength(values: System.Collections.Generic.IEnumerable<string>): int {
    total := 0
    for value in values {
        total = total + value.Length
    }

    return total
}

func QualifiedEmptyList(): System.Collections.Generic.List<string> {
    return []
}

func QualifiedPair(): System.Collections.Generic.List<string> {
    return ["left", "right"]
}

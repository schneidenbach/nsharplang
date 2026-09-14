namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.IO


// ── a method group a referenced assembly declares ─────────────────────────────────────────────
test "a reflected method group fills a declared delegate local and a return" {
    isEmpty := EmptyPredicate()
    assert isEmpty("")
    assert !isEmpty("alpha")

    // A group with MANY overloads picks the one the delegate's signature names.
    parse := ParsePicked()
    assert parse("41") == 41
}

test "a reflected method group is an argument where a delegate is expected" {
    values: string[] = ["", "alpha", "", "be"]

    empties := EmptyOnes(values)
    assert empties.Length == 2
    assert empties[0] == ""

    kept := NonEmpty(values)
    assert kept.Length == 2
    assert kept[0] == "alpha"
    assert kept[1] == "be"

    parsed := ParsedAll(["1", "2", "3"])
    assert parsed.Length == 3
    assert parsed[2] == 3
}

test "a group whose parameter admits null does not widen the sequence's element type" {
    // `IsNullOrEmpty(string? value)` is a `Func<string, bool>` here, and the chain stays a sequence
    // of `string`: the receiver fixed the element type and a delegate's PARAMETER position is
    // contravariant, so it cannot widen what the receiver already decided. If it did, this call's
    // result would be `string?[]` and the `.Length` below would not compile.
    empties := EmptyOnes(["", "alpha"])
    assert empties[0].Length == 0
}

test "the census's own chain: a method group in the first link keeps the chain typed" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-census-lambda3-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    kept := Path.Combine(root, "kept.txt")
    skipped := Path.Combine(root, "gone.skip")
    File.WriteAllText(kept, "a")
    File.WriteAllText(skipped, "b")

    extra := Path.Combine(Path.GetTempPath(), "nsharp-census-lambda3-extra-" + Guid.NewGuid().ToString("N") + ".txt")
    File.WriteAllText(extra, "c")

    try {
        found := FilesUnder([root, Path.Combine(root, "missing")], [extra, Path.Combine(root, "absent.txt")])
        assert found.Length == 2
        assert found[0] == kept
        assert found[1] == extra
    } finally {
        File.Delete(extra)
        Directory.Delete(root, true)
    }
}

test "a source type's static group is reachable through its type name" {
    widened := DoubledAll([1, 2, 3])
    assert widened.Length == 3
    assert widened[0] == 2
    assert widened[2] == 6
}

test "a reflected group reaches a delegate type that is neither Func nor Action" {
    sorted := SortedByLength(["ccc", "a", "bb"])
    assert sorted.Length == 3
    assert sorted[0] == "a"
    assert sorted[1] == "bb"
    assert sorted[2] == "ccc"
}

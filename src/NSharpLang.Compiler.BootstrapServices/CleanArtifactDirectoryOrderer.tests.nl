namespace NSharpLang.Cli.Commands

import System.Collections.Generic

// THE DELETION ORDER `nlc clean` WALKS.
//
// This replaces `CleanArtifactDirectoryOrderer_OrdersArtifactDirectories`, deleted whole from
// `tests/CliCommandTests.cs`. The C# made ONE `Assert.Equal` over a six-element array, which is
// the WHOLE of what it could see; the answer is produced by four separable decisions and is
// pinned as four here.
//
// THE ORDER IS BY PATH LENGTH, DESCENDING — NOT BY DEPTH, AND NOT BY KIND. That is worth stating
// plainly because the deleted expectation READS like a depth-then-kind order: `.nlc` lands before
// `bin` at every level. It does not. `Order` runs a selection sort on `selected[i].Length`, and
// `/repo/deep/nested/.nlc` (22 characters) merely happens to be one character longer than
// `/repo/deep/nested/bin` (21). Rename the directory and the pair swaps.
//
// LENGTH-DESCENDING IS NEVERTHELESS SOUND FOR THE JOB, and this is the reason: `Directory.Delete`
// must reach a nested artifact before its ancestor, and a nested path is ALWAYS strictly longer
// than the ancestor it nests under. So the property the command actually needs — child before
// parent — falls out of the length order for every pair where it matters, while unrelated
// directories are ordered arbitrarily but harmlessly.
//
// THE KIND RANK IS A FILTER, NOT A SORT KEY. `GetArtifactDirectoryKindRank` returns 1 for `bin`,
// 2 for `obj`, 3 for `.nlc` and 0 for everything else, and `Order` consults it only as
// `rank > 0`. The three nonzero values are never compared against one another.

func CleanDirectoryList(): List<string> {
    directories := new List<string>()
    directories.Add("/repo/bin")
    directories.Add("/repo/src/obj")
    directories.Add("/repo/src/tmp")
    directories.Add("/repo/src/.nlc")
    directories.Add("/repo/node_modules/pkg/bin")
    directories.Add("/repo/src/obj")
    directories.Add("/repo/deep/nested/bin")
    directories.Add("/repo/deep/nested/.nlc")
    directories.Add("/repo/obj")
    return directories
}

test "artifact directories come back longest-path-first, deduplicated, nine in and six out" {
    ordered := CleanArtifactDirectoryOrderer.Order(CleanDirectoryList())

    assert ordered.Length == 6
    assert ordered[0] == "/repo/deep/nested/.nlc"
    assert ordered[1] == "/repo/deep/nested/bin"
    assert ordered[2] == "/repo/src/.nlc"
    assert ordered[3] == "/repo/src/obj"
    assert ordered[4] == "/repo/bin"
    assert ordered[5] == "/repo/obj"
}

test "the answer is sorted by length descending, which is the mechanism and not a coincidence" {
    ordered := CleanArtifactDirectoryOrderer.Order(CleanDirectoryList())

    assert ordered[0].Length == 22
    assert ordered[1].Length == 21
    assert ordered[2].Length == 14
    assert ordered[3].Length == 13
    assert ordered[4].Length == 9
    assert ordered[5].Length == 9

    index := 1
    while index < ordered.Length {
        assert ordered[index - 1].Length >= ordered[index].Length
        index = index + 1
    }
}

test "equal-length paths keep the order they were first seen in" {
    // `/repo/bin` and `/repo/obj` are both nine characters. The selection sort takes a new best
    // only on a STRICT `>`, so the earlier index wins and input order survives the tie.
    ordered := CleanArtifactDirectoryOrderer.Order(CleanDirectoryList())

    assert ordered[4] == "/repo/bin"
    assert ordered[5] == "/repo/obj"
}

test "a directory whose name is not an N# artifact is dropped rather than deleted" {
    // `/repo/src/tmp` is in the input and NOT in the answer: rank 0 fails the `rank > 0` filter,
    // and `nlc clean` must never remove a directory it does not own.
    ordered := CleanArtifactDirectoryOrderer.Order(CleanDirectoryList())

    index := 0
    while index < ordered.Length {
        assert ordered[index] != "/repo/src/tmp"
        index = index + 1
    }
}

test "anything under node_modules is excluded, however artifact-shaped its own name is" {
    ordered := CleanArtifactDirectoryOrderer.Order(CleanDirectoryList())

    index := 0
    while index < ordered.Length {
        assert ordered[index] != "/repo/node_modules/pkg/bin"
        index = index + 1
    }

    assert CleanArtifactDirectoryOrderer.IsUnderNodeModulesDirectory("/repo/node_modules/pkg/bin")
    assert !CleanArtifactDirectoryOrderer.IsUnderNodeModulesDirectory("/repo/src/bin")
}

test "the kind rank is a three-valued filter and every other name answers zero" {
    assert CleanArtifactDirectoryOrderer.GetArtifactDirectoryKindRank("/repo/src/bin") == 1
    assert CleanArtifactDirectoryOrderer.GetArtifactDirectoryKindRank("/repo/src/obj") == 2
    assert CleanArtifactDirectoryOrderer.GetArtifactDirectoryKindRank("/repo/src/.nlc") == 3
    assert CleanArtifactDirectoryOrderer.GetArtifactDirectoryKindRank("/repo/src/tmp") == 0
    assert CleanArtifactDirectoryOrderer.GetArtifactDirectoryKindRank("/repo/src/binary") == 0
}

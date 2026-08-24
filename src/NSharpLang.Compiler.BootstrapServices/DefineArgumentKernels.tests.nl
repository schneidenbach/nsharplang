namespace NSharpLang.Cli

// THE `--define` / `-d` EXTRACTOR EVERY BUILD-SHAPED COMMAND SHARES.
//
// This replaces `DefineArgumentKernels_ExtractsDefinesAndRemainingArgs`, deleted whole from
// `tests/CliCommandTests.cs`, which made two `Assert.Equal`s over the extraction's two arrays.
//
// FOUR SPELLINGS REACH ONE LIST, AND THE SEPARATORS ARE TWO. `--define X`, `-d X`, `--define=X`
// and `-d=X` all add symbols, and within a value both `,` and `;` separate them while surrounding
// space is trimmed. The deleted body exercised all of that in ONE call and one assertion; the rows
// below name each rule so a regression says which one moved.
//
// DUPLICATES COLLAPSE AND ORDER IS FIRST-SEEN. The deleted input contained `FEATURE_X` twice and
// `SECOND` twice, and expected `FEATURE_X, SECOND, THIRD` — deduplicated, in the order the symbols
// first appeared, not sorted.

test "the extractor splits a value on commas and semicolons, trims it, and deduplicates" {
    extraction := DefineArgumentKernels.Extract([
        "--define",
        " FEATURE_X , SECOND ; FEATURE_X ",
        "--backend",
        "il",
        "-o",
        "dist",
        "-d=THIRD; SECOND",
        "Program.nl"])

    assert extraction.Defines.Length == 3
    assert extraction.Defines[0] == "FEATURE_X"
    assert extraction.Defines[1] == "SECOND"
    assert extraction.Defines[2] == "THIRD"

    assert extraction.RemainingArgs.Length == 5
    assert extraction.RemainingArgs[0] == "--backend"
    assert extraction.RemainingArgs[1] == "il"
    assert extraction.RemainingArgs[2] == "-o"
    assert extraction.RemainingArgs[3] == "dist"
    assert extraction.RemainingArgs[4] == "Program.nl"
}

test "all four spellings of the option reach the same list" {
    assert DefineArgumentKernels.Extract(["--define", "A"]).Defines[0] == "A"
    assert DefineArgumentKernels.Extract(["-d", "A"]).Defines[0] == "A"
    assert DefineArgumentKernels.Extract(["--define=A"]).Defines[0] == "A"
    assert DefineArgumentKernels.Extract(["-d=A"]).Defines[0] == "A"
}

test "the equals spellings are recognised by an exact prefix length, and nothing else is" {
    assert DefineArgumentKernels.DefineEqualsPrefixLength("--define=A") == 9
    assert DefineArgumentKernels.DefineEqualsPrefixLength("-d=A") == 3
    assert DefineArgumentKernels.DefineEqualsPrefixLength("--defineA") == 0
    assert DefineArgumentKernels.DefineEqualsPrefixLength("--backend=il") == 0
    assert DefineArgumentKernels.DefineEqualsPrefixLength("-o") == 0
}

test "a trailing --define with no value adds nothing and leaves nothing behind" {
    extraction := DefineArgumentKernels.Extract(["Program.nl", "--define"])

    assert extraction.Defines.Length == 0
    assert extraction.RemainingArgs.Length == 1
    assert extraction.RemainingArgs[0] == "Program.nl"
}

test "an argument list with no defines passes through unchanged" {
    extraction := DefineArgumentKernels.Extract(["--backend", "il", "Program.nl"])

    assert extraction.Defines.Length == 0
    assert extraction.RemainingArgs.Length == 3
    assert extraction.RemainingArgs[0] == "--backend"
    assert extraction.RemainingArgs[1] == "il"
    assert extraction.RemainingArgs[2] == "Program.nl"
}

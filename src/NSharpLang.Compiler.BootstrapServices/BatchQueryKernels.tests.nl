namespace NSharpLang.Cli

import System.Collections.Generic

// THE `nlc query batch` MESSAGE, DUPLICATE-ID AND PACKED-SUCCESS KERNELS.
//
// These replace `BatchQueryKernels_ShapesMessages` (deleted whole) and the kernel rows of
// `BatchCommand_DuplicateRequestIds_AreRejectedInOrdinalOrder`, from `tests/CliCommandTests.cs`.
// The rows those bodies made about the CLI's own batch ENVELOPE stay with their subject: the
// envelope is written by `src/NSharpLang.Cli/Commands/QueryCommand.cs`, which is still C#.
//
// THE DUPLICATE REPORT IS ORDINAL-SORTED AND CASE-SENSITIVE, AND BOTH HALVES MATTER. Six requests
// whose ids are `zeta, alpha, " ", zeta, Alpha, alpha` report `alpha, zeta` — sorted, so the
// message is stable whatever order the user wrote them in; case-sensitive, so `Alpha` is a
// DIFFERENT id from `alpha` and is not a duplicate of it; and whitespace-only ids are ignored
// entirely rather than colliding with one another.
//
// `CountResultSuccesses` IS A POPCOUNT OVER A PACKED BITSET, AND ITS LAST WORD IS MASKED. The
// deleted body passed one word with bits 0, 2, 5 and 63 set and asked for six items, expecting 3 —
// which is only correct if bit 63 is masked OFF because it is past the item count. That masking is
// the whole subtlety of the kernel, so it is pinned here directly rather than inferred from a
// summary count, and the two refusals either side of it are pinned as throws.

test "every batch message is spelled by a kernel, character for character" {
    assert BatchQueryKernels.GetRequestsFileNotFoundMessage("/tmp/requests.json")
        == "Requests file not found: /tmp/requests.json"
    assert BatchQueryKernels.GetPayloadShapeMessage()
        == "Batch requests must be a JSON array or an object with a 'requests' array."
    assert BatchQueryKernels.GetRequestObjectRequiredMessage() == "Each batch request must be a JSON object."
    assert BatchQueryKernels.GetRequestDeserializeFailedMessage() == "Failed to deserialize a batch request."
    assert BatchQueryKernels.GetDuplicateRequestIdsMessage("alpha, zeta")
        == "Duplicate batch request ids are not allowed: alpha, zeta"
    assert BatchQueryKernels.GetUnsupportedCommandMessage("unknown") == "Unsupported batch query command 'unknown'."
    assert BatchQueryKernels.GetOutlineFileRequiredMessage() == "file is required for outline requests."
    assert BatchQueryKernels.GetDocQueryRequiredMessage() == "query is required for doc requests."
    assert BatchQueryKernels.GetFileAndPosRequiredMessage() == "file and pos are required."
    assert BatchQueryKernels.GetInvalidPositionMessage("bad") == "Invalid position format 'bad'. Expected <line>:<col>."
}

// ── the packed success count ──────────────────────────────────────────────────

func BatchOkWords(word: ulong): ulong[] {
    words := new ulong[](1)
    words[0] = word
    return words
}

// Bits 0, 2, 5 and 63, written as one literal: 1 + 4 + 32 + 2^63.
func BatchLowThreeAndHighBit(): ulong {
    return 9223372036854775845UL
}

test "the packed success count masks every bit past the item count" {
    // Six items means bits 0..5 are in scope, so bit 63 must NOT be counted — 3, not 4. This is
    // the row the deleted C# made, and the one that proves the mask.
    assert BatchQueryKernels.CountResultSuccesses(BatchOkWords(BatchLowThreeAndHighBit()), 6) == 3
}

test "the same word counted to its full width counts the high bit too" {
    // The control the deleted body did not have: ask for all 64 items and bit 63 IS in scope.
    // Without it, a kernel that ignored the item count entirely would pass the row above.
    assert BatchQueryKernels.CountResultSuccesses(BatchOkWords(BatchLowThreeAndHighBit()), 64) == 4
}

test "an empty batch counts zero successes from zero words" {
    assert BatchQueryKernels.CountResultSuccesses(new ulong[](0), 0) == 0
}

test "the success count refuses a negative item count and refuses too few packed words" {
    negativeThrew := false
    try {
        BatchQueryKernels.CountResultSuccesses(BatchOkWords(0UL), -1)
    } catch ex: Exception {
        negativeThrew = ex.Message == "N# batch success-count kernel received a negative item count."
    }
    assert negativeThrew

    shortThrew := false
    try {
        BatchQueryKernels.CountResultSuccesses(BatchOkWords(0UL), 65)
    } catch ex: Exception {
        shortThrew = ex.Message == "N# batch success-count kernel received too few packed words."
    }
    assert shortThrew
}

test "the execution summary derives its failure count from the same popcount" {
    // Bits 0, 2 and 5: three of six succeeded.
    summary := BatchQueryKernels.SummarizeExecutionResults(BatchOkWords(37UL), 6)

    assert summary.SuccessCount == 3
    assert summary.FailureCount == 3
    assert !summary.Ok
}

test "a batch in which every item succeeded reports ok" {
    // Bits 0..5 all set.
    summary := BatchQueryKernels.SummarizeExecutionResults(BatchOkWords(63UL), 6)

    assert summary.SuccessCount == 6
    assert summary.FailureCount == 0
    assert summary.Ok
}

// ── the command-kind normaliser ───────────────────────────────────────────────

test "the batch command kind is case-insensitive and answers Unknown for a stranger" {
    assert BatchQueryKernels.GetCommandKind("symbols") == BatchQueryCommandKind.Symbols
    assert BatchQueryKernels.GetCommandKind("OUTLINE") == BatchQueryCommandKind.Outline
    assert BatchQueryKernels.GetCommandKind("Diagnostics") == BatchQueryCommandKind.Diagnostics
    assert BatchQueryKernels.GetCommandKind("type") == BatchQueryCommandKind.Type
    assert BatchQueryKernels.GetCommandKind("inspect") == BatchQueryCommandKind.Inspect
    assert BatchQueryKernels.GetCommandKind("definition") == BatchQueryCommandKind.Definition
    assert BatchQueryKernels.GetCommandKind("references") == BatchQueryCommandKind.References
    assert BatchQueryKernels.GetCommandKind("completions") == BatchQueryCommandKind.Completions
    assert BatchQueryKernels.GetCommandKind("doc") == BatchQueryCommandKind.Doc
    assert BatchQueryKernels.GetCommandKind("unknown") == BatchQueryCommandKind.Unknown
    assert BatchQueryKernels.GetCommandKind(null) == BatchQueryCommandKind.Unknown
}

test "the normaliser trims, lowercases, and expands the two shorthand command names" {
    // `def` and `refs` are aliases the deleted C# never exercised. They are the only two rewrites
    // `NormalizeCommand` performs, and without them a batch file written in the same shorthand a
    // user types at the shell would answer Unknown.
    assert BatchQueryKernels.NormalizeCommand("  Inspect  ") == "inspect"
    assert BatchQueryKernels.NormalizeCommand("def") == "definition"
    assert BatchQueryKernels.NormalizeCommand("refs") == "references"
    assert BatchQueryKernels.NormalizeCommand(null) == ""
    assert BatchQueryKernels.GetCommandKind(" DEF ") == BatchQueryCommandKind.Definition
    assert BatchQueryKernels.GetCommandKind("Refs") == BatchQueryCommandKind.References
}

// ── the duplicate-id detector itself ──────────────────────────────────────────
//
// ADDED BY THE FINISHER SLICE, AND IT CLOSES A GAP THIS FILE'S OWN HEADER DESCRIBES. The header
// above states the ordinal, case-sensitive, blank-ignoring rule in prose and pins only the
// popcount half of the body it came from — because `FindDuplicateRequestIds` takes
// `IReadOnlyList<object>` and reads each element's `Id` through REFLECTION, and the only carrier
// the deleted C# had was `BatchQueryRequest`, a record in `src/NSharpLang.Cli/`. The carriers
// below are declared here, so the reflection CONTRACT is what is pinned rather than one C# type
// that happens to satisfy it: a PROPERTY named `Id`, then a FIELD named `Id`, then nothing.

class IdCarryingProperty {
    Id: string?

    constructor(id: string?) {
        Id = id
    }
}

class IdCarryingField {
    Id: string?
}

class NoIdAtAll {
    Name: string?
}

test "duplicate ids are reported once each, in ordinal order" {
    requests := new List<object>()
    requests.Add(new IdCarryingProperty("zeta"))
    requests.Add(new IdCarryingProperty("alpha"))
    requests.Add(new IdCarryingProperty(" "))
    requests.Add(new IdCarryingProperty("zeta"))
    requests.Add(new IdCarryingProperty("Alpha"))
    requests.Add(new IdCarryingProperty("alpha"))

    duplicates := BatchQueryKernels.FindDuplicateRequestIds(requests)

    assert duplicates.Length == 2
    assert duplicates[0] == "alpha"
    assert duplicates[1] == "zeta"
}

test "ordinal order puts uppercase FIRST, which is why Alpha is not a duplicate of alpha" {
    // THE CLAIM THE DELETED BODY'S NAME PROMISED AND ITS ONE ASSERTION DID NOT MAKE. It carried
    // `Alpha` and `alpha` and asserted `["alpha", "zeta"]`, so a case-INSENSITIVE detector would
    // have failed on the count without ever saying that case is the point. Here BOTH casings are
    // duplicated, both are reported, and `Alpha` comes first — ordinal, not alphabetical.
    requests := new List<object>()
    requests.Add(new IdCarryingProperty("alpha"))
    requests.Add(new IdCarryingProperty("Alpha"))
    requests.Add(new IdCarryingProperty("alpha"))
    requests.Add(new IdCarryingProperty("Alpha"))

    duplicates := BatchQueryKernels.FindDuplicateRequestIds(requests)

    assert duplicates.Length == 2
    assert duplicates[0] == "Alpha"
    assert duplicates[1] == "alpha"
}

test "a blank, empty or absent id is never a duplicate, however often it repeats" {
    // The deleted body carried ONE `" "` entry, so a detector that counted blanks would still have
    // answered `["alpha", "zeta"]`. Five ignorable ids make the claim.
    requests := new List<object>()
    requests.Add(new IdCarryingProperty(" "))
    requests.Add(new IdCarryingProperty(" "))
    requests.Add(new IdCarryingProperty(""))
    requests.Add(new IdCarryingProperty(null))
    requests.Add(new IdCarryingProperty(null))

    duplicates := BatchQueryKernels.FindDuplicateRequestIds(requests)

    assert duplicates.Length == 0
}

test "the id is read from a FIELD as well as a property, and an element with neither is skipped" {
    fields := new IdCarryingField()
    fields.Id = "shared"
    moreFields := new IdCarryingField()
    moreFields.Id = "shared"

    fieldCarriers := new List<object>()
    fieldCarriers.Add(fields)
    fieldCarriers.Add(moreFields)

    duplicates := BatchQueryKernels.FindDuplicateRequestIds(fieldCarriers)
    assert duplicates.Length == 1
    assert duplicates[0] == "shared"

    idlessCarriers := new List<object>()
    idlessCarriers.Add(new NoIdAtAll())
    idlessCarriers.Add(new NoIdAtAll())
    assert BatchQueryKernels.FindDuplicateRequestIds(idlessCarriers).Length == 0
}

test "distinct ids answer an empty array, so the detector is not simply reporting everything" {
    requests := new List<object>()
    requests.Add(new IdCarryingProperty("one"))
    requests.Add(new IdCarryingProperty("two"))
    requests.Add(new IdCarryingProperty("three"))

    assert BatchQueryKernels.FindDuplicateRequestIds(requests).Length == 0
}

// ── two more controls the finisher slice adds ─────────────────────────────────

test "the popcount walks WHOLE words too, not only the truncated tail" {
    // Every existing row above passes ONE word, so a kernel that read only `okWords[fullWordCount]`
    // would pass all of them. Sixty-four set bits in word 0 and two in word 1 catch it.
    words := new ulong[](2)
    words[0] = 18446744073709551615UL
    words[1] = 3UL

    assert BatchQueryKernels.CountResultSuccesses(words, 64) == 64
    assert BatchQueryKernels.CountResultSuccesses(words, 65) == 65
    assert BatchQueryKernels.CountResultSuccesses(words, 66) == 66
}

test "the BATCH invalid-position sentence is NOT the query command's one" {
    // A DIFFERENCE THE DELETED BODIES COULD NOT SHOW. `BatchCommand_PositionParsingUsesQueryKernelSemantics`
    // asserted each envelope message against a live call to the same kernel that produced it, so
    // the two sides agreed by construction. The two shipped paths word the same refusal
    // differently, and a reader of the deleted body would have had no way to know.
    batch := BatchQueryKernels.GetInvalidPositionMessage("1_000:2")
    direct := QueryCommandKernels.GetInvalidPositionMessage("1_000:2")

    assert batch == "Invalid position format '1_000:2'. Expected <line>:<col>."
    assert direct == "Invalid position format: 1_000:2. Expected <line>:<col> (e.g. 5:12)"
    assert batch != direct
}

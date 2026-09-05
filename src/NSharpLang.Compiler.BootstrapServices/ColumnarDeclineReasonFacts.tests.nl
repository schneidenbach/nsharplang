namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler


// THE CANONICAL CONTRACTS FOR `ColumnarDeclineReasonFacts`, IN N#.
//
// These replace `tests/ColumnarDeclineReasonFactsTests.cs`, the last canonical C# assertion layer
// over `ColumnarDeclineReasons.nl` and the emission-error factories in
// `ColumnarEmissionDiagnostics.nl`. The subject turns an emit decline — a site id, a message and a
// SPAN INTO THE MERGED SOURCE — back into a place a human can open: a file, a line and a column.
// Every `NL103` a developer ever sees is rendered by these functions.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. `MapMergedOffsetFileIndex` and `LineFromOffset`
// take primitives and DO emit from a `tests/native` project — slice 3's probes A and B proved it —
// but `new ColumnarDeclineReason(…)` is a constructed dependency-assembly object and declines at
// `emit.local.initializer` there, and `FormatDetail` / `FormatTraceLine` / the emission-error
// factories all take one. Splitting the cluster across two estates would leave the halves unable to
// share a fixture, so the whole cluster lands here.
//
// THE COVERAGE ADDS THE TWO RESOLVE GATES AND THE OTHER THREE FACTORIES, WHICH THE C# NEVER
// TOUCHED. The deleted file covered six of the eight `ColumnarDeclineReasonFacts` entry points and
// one of the four `ColumnarEmissionDiagnostics` factories.
//
// THE FIVE THINGS IT IS EASY TO GET WRONG:
//
// (1) THE SEPARATOR IS A HOLE, NOT A BOUNDARY. Files are merged with a separator between them, and
// an offset that lands INSIDE that separator belongs to no file: with lengths 5/3/4 and a
// two-character separator, offsets 5, 6, 10 and 11 all answer `-1` for BOTH the file index and the
// local offset. Rounding them into the neighbouring file would point the diagnostic at the wrong
// line of the wrong file.
//
// (2) A NEGATIVE OFFSET IS `-1`, AND SO IS AN OFFSET PAST THE END. The walk answers `-1` rather
// than clamping, and `MapMergedOffsetLocalOffset` inherits that answer by asking the index question
// first.
//
// (3) LINES AND COLUMNS ARE ONE-BASED AND CRLF IS ONE LINE BREAK, NOT TWO. `\r\n` advances the line
// once and the column resets after the pair; a lone `\r` is also a break. An out-of-range offset
// answers `0`, which is not a valid line or column, and that is how the caller knows.
//
// (4) THE TWO RENDERINGS ARE DIFFERENT PRODUCTS WITH DIFFERENT AUDIENCES. `FormatDetail` writes an
// English sentence ending in a period; `FormatTraceLine` writes one machine-readable line of
// `key=value` pairs with quoted strings and no trailing period. Both drop the member and the
// location clauses when they are absent, rather than emitting empty ones.
//
// (5) A REQUIRED-EMISSION ERROR KEEPS ITS FIRST SENTENCE AND APPENDS THE DETAIL. The four factories
// differ ONLY in that first sentence and in the explanation behind it, so a caller that reads
// `Message` sees a stable prefix and a decline-specific tail.
func DeclineFactsReason(siteId: string, message: string, memberName: string): ColumnarDeclineReason {
    return new ColumnarDeclineReason(siteId, message, 42, 6, memberName)
}

// ---- the merged-offset walk ----------------------------------------------------------------------

// Successor to MergedOffsetMapping_AccountsForSeparators — all nine of its rows, expanded out of
// the `[Theory]`, both questions per row.
test "columnar decline reason facts map merged offsets across separators" {
    fileLengths := [5, 3, 4]

    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 0) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 0) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 4) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 4) == 4
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 5) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 5) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 6) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 6) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 7) == 1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 7) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 9) == 1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 9) == 2
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 10) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 10) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 11) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 11) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 12) == 2
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 12) == 0
}

// Successor to MergedOffsetMapping_SingleFileUsesIdentityOffsets — all four of its assertions.
test "columnar decline reason facts use identity offsets for a single file" {
    fileLengths := [5]

    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 3) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 3) == 3
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 5) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, -1) == -1

    // Not in the deleted file: past the end and before the start, on both questions.
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, -1) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 99) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 99) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 2, 4) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 2, 4) == 4
}

// NOT IN THE DELETED FILE. A zero-length separator makes the files contiguous, which is the shape
// the merged buffer takes when the separator is empty — and there is then no hole to fall into.
test "columnar decline reason facts map contiguous files without a separator" {
    fileLengths := [2, 2]

    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 0, 0) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 0, 1) == 0
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 0, 2) == 1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 0, 3) == 1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetFileIndex(fileLengths, 0, 4) == -1
    assert ColumnarDeclineReasonFacts.MapMergedOffsetLocalOffset(fileLengths, 0, 3) == 1
}

// NOT IN THE DELETED FILE. The two RESOLVE gates are what production actually calls: when the
// decline carries a source file id, that id wins and the offset is already local; otherwise both
// questions fall through to the merged walk. An out-of-range id does NOT win.
test "columnar decline reason facts prefer a carried source file id over the merged walk" {
    fileLengths := [5, 3, 4]

    assert ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, 7, 2, true) == 2
    assert ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, 7, 2, true) == 7

    assert ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, 7, 2, false) == 1
    assert ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, 7, 2, false) == 0

    assert ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, 7, 3, true) == 1
    assert ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, 7, 3, true) == 0
    assert ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, 7, -1, true) == 1
    assert ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, 7, -1, true) == 0

    assert ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, 0, 0, true) == 0
    assert ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, 0, 0, true) == 0
}

// ---- the line and column walk --------------------------------------------------------------------

// Successor to LineAndColumnFromOffset_HandleLfAndCrLf — all six of its rows, both questions.
test "columnar decline reason facts count lines and columns through lf and crlf" {
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\ntwo\nthree", 0) == 1
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\ntwo\nthree", 0) == 1
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\ntwo\nthree", 4) == 2
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\ntwo\nthree", 4) == 1
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\ntwo\nthree", 6) == 2
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\ntwo\nthree", 6) == 3
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\r\ntwo\r\nthree", 5) == 2
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\r\ntwo\r\nthree", 5) == 1
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\r\ntwo\r\nthree", 8) == 2
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\r\ntwo\r\nthree", 8) == 4
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\r\ntwo\r\nthree", 10) == 3
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\r\ntwo\r\nthree", 10) == 1
}

// NOT IN THE DELETED FILE. The out-of-range answer is `0` on both questions, a lone `\r` is a
// break, and an offset exactly at the end of the text is still in range.
test "columnar decline reason facts answer zero outside the text and break on a bare cr" {
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\ntwo", -1) == 0
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\ntwo", -1) == 0
    assert ColumnarDeclineReasonFacts.LineFromOffset("one\ntwo", 99) == 0
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\ntwo", 99) == 0

    assert ColumnarDeclineReasonFacts.LineFromOffset("one\ntwo", 7) == 2
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\ntwo", 7) == 4

    assert ColumnarDeclineReasonFacts.LineFromOffset("one\rtwo", 4) == 2
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("one\rtwo", 4) == 1

    assert ColumnarDeclineReasonFacts.LineFromOffset("", 0) == 1
    assert ColumnarDeclineReasonFacts.ColumnFromOffset("", 0) == 1
}

// ---- the two renderings --------------------------------------------------------------------------

// Successor to FormatDetail_IncludesSiteMessageMemberAndLocation.
test "columnar decline reason facts render the human detail sentence" {
    reason := new ColumnarDeclineReason(
        "emit.statement.unhandled-kind",
        "unsupported statement (node kind 29)",
        42,
        6,
        "Main"
    )

    assert ColumnarDeclineReasonFacts.FormatDetail(reason, "Program.nl", 15, 5) == "Declined at emit.statement.unhandled-kind: unsupported statement (node kind 29) in 'Main' (Program.nl:15:5)."
}

// NOT IN THE DELETED FILE. Both optional clauses drop out when they are absent, and an incomplete
// location — a name without a line, or a line without a column — drops the whole location clause
// rather than emitting half of one.
test "columnar decline reason facts drop the absent detail clauses" {
    named := DeclineFactsReason("emit.site", "message", "Main")
    anonymous := DeclineFactsReason("emit.site", "message", "")

    assert ColumnarDeclineReasonFacts.FormatDetail(named, null, 0, 0) == "Declined at emit.site: message in 'Main'."
    assert ColumnarDeclineReasonFacts.FormatDetail(anonymous, null, 0, 0) == "Declined at emit.site: message."
    assert ColumnarDeclineReasonFacts.FormatDetail(anonymous, "Program.nl", 15, 5) == "Declined at emit.site: message (Program.nl:15:5)."
    assert ColumnarDeclineReasonFacts.FormatDetail(named, "", 15, 5) == "Declined at emit.site: message in 'Main'."
    assert ColumnarDeclineReasonFacts.FormatDetail(named, "Program.nl", 0, 5) == "Declined at emit.site: message in 'Main'."
    assert ColumnarDeclineReasonFacts.FormatDetail(named, "Program.nl", 15, 0) == "Declined at emit.site: message in 'Main'."
}

// Successor to FormatTraceLine_IsSingleLineMachineReadableText.
test "columnar decline reason facts render the machine readable trace line" {
    reason := new ColumnarDeclineReason(
        "emit.call.instance-member-unmodeled",
        "string.CompareTo with 1 argument is not modeled",
        91,
        19,
        "Main"
    )

    assert ColumnarDeclineReasonFacts.FormatTraceLine(reason, "Program.nl", 15, 5) == "decline site=emit.call.instance-member-unmodeled message=\"string.CompareTo with 1 argument is not modeled\" span=91:19 member=\"Main\" location=Program.nl:15:5"
}

// NOT IN THE DELETED FILE. The trace line's optional clauses drop the same way, and the span is
// always present — it is the one field a decline can never be missing.
test "columnar decline reason facts drop the absent trace clauses" {
    named := DeclineFactsReason("emit.site", "message", "Main")
    anonymous := DeclineFactsReason("emit.site", "message", "")

    assert ColumnarDeclineReasonFacts.FormatTraceLine(named, null, 0, 0) == "decline site=emit.site message=\"message\" span=42:6 member=\"Main\""
    assert ColumnarDeclineReasonFacts.FormatTraceLine(anonymous, null, 0, 0) == "decline site=emit.site message=\"message\" span=42:6"
    assert ColumnarDeclineReasonFacts.FormatTraceLine(anonymous, "Program.nl", 15, 5) == "decline site=emit.site message=\"message\" span=42:6 location=Program.nl:15:5"
    assert ColumnarDeclineReasonFacts.FormatTraceLine(named, "Program.nl", 0, 5) == "decline site=emit.site message=\"message\" span=42:6 member=\"Main\""
}

// NOT IN THE DELETED FILE. The carrier's own accessors, including the two the merged-offset resolve
// gates read.
test "columnar decline reason carries its site span member and file id" {
    plain := new ColumnarDeclineReason("emit.site", "message", 42, 6, "Main")
    identified := new ColumnarDeclineReason("emit.site", "message", 42, 6, "Main", 3, true)

    assert plain.SiteId == "emit.site"
    assert plain.Message == "message"
    assert plain.SpanStart == 42
    assert plain.SpanLength == 6
    assert plain.MemberName == "Main"
    assert plain.SourceFileId == 0
    assert !plain.HasSourceFileId

    assert identified.SourceFileId == 3
    assert identified.HasSourceFileId
}

// ---- the emission-error factories ----------------------------------------------------------------

// Successor to EmissionDiagnosticFactories_PreserveFirstSentenceAndAttachLocation — all six of its
// assertions.
test "columnar emission diagnostics preserve the first sentence and attach the location" {
    emissionError := ColumnarEmissionDiagnostics.RequiredEmissionError(
        "Hello",
        "Declined at emit.expression.unhandled-kind: unsupported expression.",
        "Program.nl",
        3,
        9,
        4
    )

    assert emissionError.Message.StartsWith("Columnar emission is required for 'Hello', but the columnar backend declined.", StringComparison.Ordinal)
    assert emissionError.Message.EndsWith(" Declined at emit.expression.unhandled-kind: unsupported expression.", StringComparison.Ordinal)
    assert emissionError.FileName == "Program.nl"
    assert emissionError.Line == 3
    assert emissionError.Column == 9
    assert emissionError.Length == 4
}

// NOT IN THE DELETED FILE. The other three factories, and the router that chooses between all four.
// They differ only in the first sentence, which is exactly the thing a caller matches on.
test "columnar emission diagnostics distinguish their four first sentences" {
    plain := ColumnarEmissionDiagnostics.RequiredEmissionError("Hello", null, null, 0, 0, 1)
    emitOnly := ColumnarEmissionDiagnostics.RequiredEmitOnlyEmissionError("Hello", null, null, 0, 0, 1)
    soa := ColumnarEmissionDiagnostics.RequiredSoaEmissionError("Hello", null, null, 0, 0, 1)
    aot := ColumnarEmissionDiagnostics.RequiredAotEmissionError("Hello", null, null, 0, 0, 1)

    assert plain.Message == "Columnar emission is required for 'Hello', but the columnar backend declined."
    assert emitOnly.Message == "Columnar emission is required for 'Hello', but the columnar backend declined."
    assert soa.Message == "Columnar SoA emission is required for 'Hello', but the columnar backend declined."
    assert aot.Message == "Columnar AOT emission is required for 'Hello', but the columnar backend declined."

    // The explanation is what actually separates the plain and emit-only arms.
    assert plain.HumanExplanation == "This product path requires successful N# columnar emission after analysis passes."
    assert emitOnly.HumanExplanation == "This emit-only path bypasses the legacy C# AST/Analyzer and requires successful N# columnar emission."
}

// NOT IN THE DELETED FILE. The router's precedence: emit-only wins over AOT, AOT wins over SoA, and
// plain is the fallback.
test "columnar emission diagnostics route emit only before aot before soa" {
    assert ColumnarEmissionDiagnostics.RequiredEmissionErrorFor("Hello", true, true, true, null, null, 0, 0, 1).HumanExplanation == "This emit-only path bypasses the legacy C# AST/Analyzer and requires successful N# columnar emission."
    assert ColumnarEmissionDiagnostics.RequiredEmissionErrorFor("Hello", true, true, false, null, null, 0, 0, 1).Message == "Columnar AOT emission is required for 'Hello', but the columnar backend declined."
    assert ColumnarEmissionDiagnostics.RequiredEmissionErrorFor("Hello", false, true, false, null, null, 0, 0, 1).Message == "Columnar SoA emission is required for 'Hello', but the columnar backend declined."
    assert ColumnarEmissionDiagnostics.RequiredEmissionErrorFor("Hello", false, false, false, null, null, 0, 0, 1).Message == "Columnar emission is required for 'Hello', but the columnar backend declined."
}

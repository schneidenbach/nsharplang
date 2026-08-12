namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler

// Native contracts for THE SYSTEMS FINDING SINK — what a systems finding IS, what severity it ends
// up carrying, which policy label it wears, and the order the report is read in.
//
// This was 119 lines over seven extents inside `SystemsAnalyzer.cs`, reached from 63 call sites in
// 15 members, and EVERY `NSYS*` diagnostic the product emits is constructed here. That makes the
// existing fixture estate direct regression cover, and it makes these contracts the pinning of the
// things a corpus CANNOT show: the audit downgrade (no corpus target runs in audit), the type-finding
// asymmetry, the call-path compositions, and the stability of the report order.
//
// EIGHT THINGS THIS SINK IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) TWO DOWNGRADES, IN ORDER. Boundary-not-hot turns an error into a warning; audit then turns
// EVERYTHING into a warning. Audit is last, so it also downgrades a preferred WARNING's error
// sibling and cannot be undone by the boundary arm.
//
// (2) A TYPE FINDING IS NOT A FUNCTION FINDING. It has no preferred severity, no boundary arm, and
// its policy label has NO `[hot]` arm — a type is not hot.
//
// (3) THE POLICY LABEL IS THREE-VALUED AND `[hot]` OUTRANKS THE PROJECT'S MODE.
//
// (4) THE DEFAULT CALL PATH IS ONE ELEMENT — the reporting function's own name — and not empty. The
// renderer turns an empty path into no hint at all, so an empty default would silently drop the
// `effect path:` line from every finding in the product.
//
// (5) THE HOT GATE IS SILENCE, NOT A DOWNGRADE. A cold function hears nothing from `AddWhenHot`.
//
// (6) THE POLICY FORK IS A PRECEDENCE. Allowed silences it entirely; boundary answers WARNING
// conclusively — even for a function that is also `[hot]`, which is the OPPOSITE precedence to the
// allocation rule.
//
// (7) AUDIT MODE IS A SYSTEMS-PROFILE MODE. A default-profile project whose systems mode reads
// `audit` is not in audit.
//
// (8) THE ORDER IS FILE (CASE-INSENSITIVE ORDINAL), LINE, COLUMN — AND STABLE. Two findings at one
// position are read in the order the walk met them.

func SfsConfig(profile: string, mode: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("finding-sink-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    return config
}

func SfsSink(profile: string, mode: string): SystemsFindingSink {
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(SfsConfig(profile, mode))
    return sink
}

func SfsStrict(): SystemsFindingSink {
    return SfsSink("systems", "strict")
}

func SfsAudit(): SystemsFindingSink {
    return SfsSink("systems", "audit")
}

func SfsLocal(): SystemsFindingSink {
    return SfsSink("default", "strict")
}

// One finding through the default-call-path door, reported against a function whose hotness and
// boundary-ness the caller states.
func SfsAdd(sink: SystemsFindingSink, isHot: bool, isBoundary: bool, preferredSeverity: ErrorSeverity) {
    sink.AddForFunction("NSYS010", "allocation", "message", 7, 3, 4, "a.nl", "Fn", isHot, isBoundary, preferredSeverity, "fix it")
}

func SfsOnly(sink: SystemsFindingSink): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[0]
}

// Field readers, one per field this owner decides. They exist because a property read chained onto
// a call result does not emit — the recorded chained-read decline — and binding the finding to a
// local in every contract would bury the assertion it is making.
func SfsSeverity(sink: SystemsFindingSink): string {
    finding := SfsOnly(sink)
    return finding.Severity
}

func SfsPolicy(sink: SystemsFindingSink): string? {
    finding := SfsOnly(sink)
    return finding.Policy
}

func SfsLength(sink: SystemsFindingSink): int {
    finding := SfsOnly(sink)
    return finding.Length
}

func SfsSuggestion(sink: SystemsFindingSink): string? {
    finding := SfsOnly(sink)
    return finding.Suggestion
}

func SfsSummarySource(sink: SystemsFindingSink): string? {
    finding := SfsOnly(sink)
    return finding.SummarySource
}

func SfsOrderedCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

test "EVERY FIELD OF A FUNCTION FINDING HAS A STATED PROVENANCE" {
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    finding := SfsOnly(sink)
    assert finding.Code == "NSYS010"
    assert finding.Severity == "error"
    assert finding.Effect == "allocation"
    assert finding.Message == "message"
    assert finding.File == "a.nl"
    assert finding.Line == 7
    assert finding.Column == 3
    assert finding.Length == 4
    assert finding.Function == "Fn"
    assert finding.Policy == "systems:strict"
    assert finding.SummarySource == "sourceInferred"
    assert finding.Suggestion == "fix it"
    assert finding.CallPath.Count == 1
    assert finding.CallPath[0] == "Fn"
}

test "THE PROVENANCE IS THE SAME ONE THE HOT-SUMMARY OWNER ALREADY NAMES" {
    // The literal was written three times in C#; it is read from the owner that names it, so a
    // rename cannot leave the sink behind.
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    assert SfsSummarySource(sink) == HotSummarySource.SourceInferred
}

test "A BOUNDARY THAT IS NOT HOT DOWNGRADES AN ERROR TO A WARNING" {
    sink := SfsStrict()
    SfsAdd(sink, false, true, ErrorSeverity.Error)
    assert SfsSeverity(sink) == "warning"
}

test "A FUNCTION THAT IS BOTH HOT AND BOUNDARY KEEPS THE ERROR" {
    sink := SfsStrict()
    SfsAdd(sink, true, true, ErrorSeverity.Error)
    assert SfsSeverity(sink) == "error"
}

test "THE BOUNDARY DOWNGRADE ONLY APPLIES TO A PREFERRED ERROR" {
    // A preferred warning at a boundary is still a warning; the arm is a downgrade, not a rewrite.
    sink := SfsStrict()
    SfsAdd(sink, false, true, ErrorSeverity.Warning)
    assert SfsSeverity(sink) == "warning"
}

test "A PLAIN FUNCTION KEEPS THE SEVERITY THE CALLER PREFERRED" {
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Warning)
    assert SfsSeverity(sink) == "warning"
}

test "AUDIT MODE DOWNGRADES EVERY ERROR, INCLUDING A HOT ONE THE BOUNDARY ARM WOULD HAVE KEPT" {
    sink := SfsAudit()
    SfsAdd(sink, true, true, ErrorSeverity.Error)
    assert SfsSeverity(sink) == "warning"
}

test "AUDIT MODE DOWNGRADES A HOT FUNCTION THAT IS NOT A BOUNDARY AT ALL" {
    sink := SfsAudit()
    SfsAdd(sink, true, false, ErrorSeverity.Error)
    assert SfsSeverity(sink) == "warning"
}

test "THE POLICY LABEL IS THREE-VALUED AND HOT OUTRANKS THE PROJECT MODE" {
    hot := SfsStrict()
    SfsAdd(hot, true, false, ErrorSeverity.Error)
    assert SfsPolicy(hot) == "[hot]"

    strict := SfsStrict()
    SfsAdd(strict, false, false, ErrorSeverity.Error)
    assert SfsPolicy(strict) == "systems:strict"

    local := SfsLocal()
    SfsAdd(local, false, false, ErrorSeverity.Error)
    assert SfsPolicy(local) == "local"
}

test "THE POLICY LABEL CARRIES THE PROJECT'S OWN MODE, NOT THE WORD STRICT" {
    sink := SfsAudit()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    assert SfsPolicy(sink) == "systems:audit"
}

test "A HOT FINDING IN AUDIT MODE IS STILL LABELLED HOT EVEN THOUGH ITS SEVERITY WAS DOWNGRADED" {
    // The label says which promise was broken; the severity says what the project does about it.
    sink := SfsAudit()
    SfsAdd(sink, true, false, ErrorSeverity.Error)
    finding := SfsOnly(sink)
    assert finding.Policy == "[hot]"
    assert finding.Severity == "warning"
}

test "AUDIT IS A SYSTEMS-PROFILE MODE: A DEFAULT PROFILE WITH MODE AUDIT IS NOT IN AUDIT" {
    sink := SfsSink("default", "audit")
    assert !sink.IsAuditMode
    assert !sink.IsSystemsProfile
    assert sink.EffectiveMode == "strict"
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    assert SfsSeverity(sink) == "error"
}

test "THE PROFILE AND MODE TESTS ARE CASE-INSENSITIVE, BECAUSE A PROJECT FILE IS WRITTEN BY HAND" {
    sink := SfsSink("SYSTEMS", "AUDIT")
    assert sink.IsSystemsProfile
    assert sink.IsAuditMode
    assert sink.EffectiveMode == "AUDIT"
}

test "A NON-SYSTEMS PROJECT REPORTS MODE STRICT WHATEVER ITS SYSTEMS BLOCK SAYS" {
    sink := SfsSink("default", "relaxed")
    assert sink.EffectiveMode == "strict"
}

test "A LENGTH BELOW ONE IS CLAMPED, SO NO FINDING UNDERLINES NOTHING" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "m", 1, 1, 0, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    assert SfsLength(sink) == 1
}

test "A NULL SUGGESTION SURVIVES AS NULL RATHER THAN BECOMING AN EMPTY SENTENCE" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "m", 1, 1, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    assert SfsSuggestion(sink) == null
}

test "AN EXPLICIT CALL PATH IS KEPT WHOLE, WHICH IS WHAT MAKES THE EFFECT PATH READABLE" {
    sink := SfsStrict()
    callPath := new string[](2)
    callPath[0] = "Caller"
    callPath[1] = "Callee"
    sink.Add("NSYS010", "allocation", "m", 1, 1, 1, "a.nl", "Caller", true, false, ErrorSeverity.Error, null, callPath)
    finding := SfsOnly(sink)
    assert finding.CallPath.Count == 2
    assert finding.CallPath[0] == "Caller"
    assert finding.CallPath[1] == "Callee"
    assert SystemsFindingDiagnostics.CallPathHint(finding.CallPath) == "effect path: Caller -> Callee"
}

test "THE DEFAULT CALL PATH IS ONE ELEMENT AND THE RENDERER STILL PRINTS A HINT FOR IT" {
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    finding := SfsOnly(sink)
    assert finding.CallPath.Count == 1
    assert SystemsFindingDiagnostics.CallPathHint(finding.CallPath) == "effect path: Fn"
}

test "THE HOT GATE IS SILENCE, NOT A DOWNGRADE" {
    sink := SfsStrict()
    sink.AddWhenHot("NSYS120", "throw", "m", 5, 2, "a.nl", "Cold", false, false)
    assert sink.Count == 0
}

test "A HOT FINDING THROUGH THE HOT GATE IS AN ERROR AT LENGTH ONE WITH NO SUGGESTION" {
    sink := SfsStrict()
    sink.AddWhenHot("NSYS120", "throw", "m", 5, 2, "a.nl", "Hot", true, false)
    finding := SfsOnly(sink)
    assert finding.Severity == "error"
    assert finding.Length == 1
    assert finding.Suggestion == null
    assert finding.Policy == "[hot]"
    assert finding.CallPath.Count == 1
}

test "A HOT BOUNDARY REPORTED THROUGH THE HOT GATE IS STILL AN ERROR" {
    // The boundary downgrade needs `!isHot`, and the hot gate only fires when `isHot`.
    sink := SfsStrict()
    sink.AddWhenHot("NSYS120", "throw", "m", 5, 2, "a.nl", "Both", true, true)
    assert SfsSeverity(sink) == "error"
}

test "AN ALLOWED EFFECT SILENCES THE POLICY FORK ENTIRELY, ON EVERY ARM" {
    hot := SfsStrict()
    hot.AddForPolicy("NSYS120", "throw", "m", 1, 1, true, "a.nl", "Fn", true, false, "fix")
    assert hot.Count == 0

    boundary := SfsStrict()
    boundary.AddForPolicy("NSYS120", "throw", "m", 1, 1, true, "a.nl", "Fn", false, true, "fix")
    assert boundary.Count == 0
}

test "THE POLICY FORK ANSWERS BOUNDARY BEFORE HOT, WHICH IS THE OPPOSITE OF THE ALLOCATION RULE" {
    sink := SfsStrict()
    sink.AddForPolicy("NSYS120", "throw", "m", 1, 1, false, "a.nl", "Fn", true, true, "fix")
    assert SfsSeverity(sink) == "warning"
}

test "THE POLICY FORK REPORTS AN ERROR FOR A HOT FUNCTION AND FOR ANY SYSTEMS FUNCTION" {
    hot := SfsLocal()
    hot.AddForPolicy("NSYS120", "throw", "m", 1, 1, false, "a.nl", "Fn", true, false, "fix")
    assert SfsSeverity(hot) == "error"

    systems := SfsStrict()
    systems.AddForPolicy("NSYS120", "throw", "m", 1, 1, false, "a.nl", "Fn", false, false, "fix")
    assert SfsSeverity(systems) == "error"
}

test "THE POLICY FORK IS SILENT FOR A COLD FUNCTION IN A NON-SYSTEMS PROJECT" {
    sink := SfsLocal()
    sink.AddForPolicy("NSYS120", "throw", "m", 1, 1, false, "a.nl", "Fn", false, false, "fix")
    assert sink.Count == 0
}

test "THE POLICY FORK KEEPS ITS SUGGESTION ON BOTH REPORTING ARMS" {
    boundary := SfsStrict()
    boundary.AddForPolicy("NSYS120", "throw", "m", 1, 1, false, "a.nl", "Fn", false, true, "fix")
    assert SfsSuggestion(boundary) == "fix"

    reported := SfsStrict()
    reported.AddForPolicy("NSYS120", "throw", "m", 1, 1, false, "a.nl", "Fn", true, false, "fix")
    assert SfsSuggestion(reported) == "fix"
}

test "EVERY FIELD OF A TYPE FINDING HAS A STATED PROVENANCE, AND THE TYPE'S NAME IS THREE OF THEM" {
    sink := SfsStrict()
    sink.AddForType("NSYS080", "lifetime", "message", "b.nl", 4, 9, 6, "Buffer", "fix it")
    finding := SfsOnly(sink)
    assert finding.Code == "NSYS080"
    assert finding.Severity == "error"
    assert finding.Effect == "lifetime"
    assert finding.Message == "message"
    assert finding.File == "b.nl"
    assert finding.Line == 4
    assert finding.Column == 9
    assert finding.Length == 6
    assert finding.Function == "Buffer"
    assert finding.Policy == "systems:strict"
    assert finding.SummarySource == "sourceInferred"
    assert finding.Suggestion == "fix it"
    assert finding.CallPath.Count == 1
    assert finding.CallPath[0] == "Buffer"
}

test "A TYPE FINDING'S POLICY LABEL HAS NO HOT ARM, BECAUSE A TYPE IS NOT HOT" {
    local := SfsLocal()
    local.AddForType("NSYS080", "lifetime", "m", "b.nl", 1, 1, 1, "Buffer", null)
    assert SfsPolicy(local) == "local"

    audit := SfsAudit()
    audit.AddForType("NSYS080", "lifetime", "m", "b.nl", 1, 1, 1, "Buffer", null)
    assert SfsPolicy(audit) == "systems:audit"
}

test "A TYPE FINDING IS AN ERROR UNLESS THE PROJECT IS IN AUDIT, AND HAS NO OTHER SEVERITY ARM" {
    strict := SfsStrict()
    strict.AddForType("NSYS080", "lifetime", "m", "b.nl", 1, 1, 1, "Buffer", null)
    assert SfsSeverity(strict) == "error"

    audit := SfsAudit()
    audit.AddForType("NSYS080", "lifetime", "m", "b.nl", 1, 1, 1, "Buffer", null)
    assert SfsSeverity(audit) == "warning"

    local := SfsLocal()
    local.AddForType("NSYS080", "lifetime", "m", "b.nl", 1, 1, 1, "Buffer", null)
    assert SfsSeverity(local) == "error"
}

test "A TYPE FINDING'S LENGTH IS CLAMPED THE SAME WAY A FUNCTION FINDING'S IS" {
    sink := SfsStrict()
    sink.AddForType("NSYS080", "lifetime", "m", "b.nl", 1, 1, 0, "Buffer", null)
    assert SfsLength(sink) == 1
}

test "THE COUNTS ARE OVER THE EMITTED SEVERITY, NOT THE PREFERRED ONE" {
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    SfsAdd(sink, false, true, ErrorSeverity.Error)
    SfsAdd(sink, false, false, ErrorSeverity.Warning)
    assert sink.Count == 3
    assert sink.ErrorCount == 1
    assert sink.WarningCount == 2
}

test "AUDIT MODE MOVES EVERY COUNT INTO THE WARNING COLUMN" {
    sink := SfsAudit()
    SfsAdd(sink, true, false, ErrorSeverity.Error)
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    assert sink.ErrorCount == 0
    assert sink.WarningCount == 2
}

test "THE AOT VERDICT FAILS ONLY ON AN NSYS060 THAT IS STILL AN ERROR" {
    clean := SfsStrict()
    SfsAdd(clean, false, false, ErrorSeverity.Error)
    assert clean.AotAnalysis() == "pass"

    failed := SfsStrict()
    failed.AddForFunction("NSYS060", "aot", "m", 1, 1, 1, "a.nl", "Fn", true, false, ErrorSeverity.Error, null)
    assert failed.AotAnalysis() == "fail"
}

test "AN NSYS060 DOWNGRADED BY A BOUNDARY DOES NOT FAIL THE AOT VERDICT" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS060", "aot", "m", 1, 1, 1, "a.nl", "Fn", false, true, ErrorSeverity.Error, null)
    assert sink.Count == 1
    assert sink.AotAnalysis() == "pass"
}

test "AN NSYS060 DOWNGRADED BY AUDIT MODE DOES NOT FAIL THE AOT VERDICT EITHER" {
    sink := SfsAudit()
    sink.AddForFunction("NSYS060", "aot", "m", 1, 1, 1, "a.nl", "Fn", true, false, ErrorSeverity.Error, null)
    assert sink.AotAnalysis() == "pass"
}

test "AN EMPTY SINK PASSES AOT AND COUNTS NOTHING" {
    sink := SfsStrict()
    assert sink.Count == 0
    assert sink.ErrorCount == 0
    assert sink.WarningCount == 0
    assert sink.AotAnalysis() == "pass"
    assert SfsOrderedCount(sink) == 0
}

test "BeginAnalysis CLEARS THE LIST, SO ONE PROJECT'S FINDINGS CANNOT BE REPORTED FOR ANOTHER" {
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    assert sink.Count == 1
    sink.BeginAnalysis(SfsConfig("systems", "strict"))
    assert sink.Count == 0
}

test "THE REPORT ORDER IS FILE, THEN LINE, THEN COLUMN" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "d", 1, 1, 1, "b.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS010", "allocation", "c", 9, 1, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS010", "allocation", "b", 2, 8, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS010", "allocation", "a", 2, 3, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    ordered := sink.Ordered()
    assert ordered.Length == 4
    assert ordered[0].Message == "a"
    assert ordered[1].Message == "b"
    assert ordered[2].Message == "c"
    assert ordered[3].Message == "d"
}

test "THE ORDER IS STABLE: TWO FINDINGS AT ONE POSITION KEEP THE ORDER THE WALK MET THEM" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "first", 3, 3, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS020", "boxing", "second", 3, 3, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS030", "delegate", "third", 3, 3, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    ordered := sink.Ordered()
    assert ordered[0].Message == "first"
    assert ordered[1].Message == "second"
    assert ordered[2].Message == "third"
}

test "THE FILE ORDER IS CASE-INSENSITIVE, SO TWO SPELLINGS OF ONE PATH SORT TOGETHER" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "upper", 1, 1, 1, "B.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS010", "allocation", "lower", 1, 1, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    ordered := sink.Ordered()
    assert ordered[0].Message == "lower"
    assert ordered[1].Message == "upper"
}

test "A CASE-INSENSITIVE TIE ON THE FILE FALLS THROUGH TO LINE, IT DOES NOT REORDER BY CASE" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "later", 9, 1, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS010", "allocation", "earlier", 2, 1, 1, "A.nl", "Fn", false, false, ErrorSeverity.Error, null)
    ordered := sink.Ordered()
    assert ordered[0].Message == "earlier"
    assert ordered[1].Message == "later"
}

test "A SHORTER PATH SORTS BEFORE A LONGER ONE IT IS A PREFIX OF" {
    sink := SfsStrict()
    sink.AddForFunction("NSYS010", "allocation", "long", 1, 1, 1, "a.nl.bak", "Fn", false, false, ErrorSeverity.Error, null)
    sink.AddForFunction("NSYS010", "allocation", "short", 1, 1, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    ordered := sink.Ordered()
    assert ordered[0].Message == "short"
    assert ordered[1].Message == "long"
}

test "Ordered DOES NOT CONSUME THE LIST, SO THE COUNTS STILL ANSWER AFTERWARDS" {
    sink := SfsStrict()
    SfsAdd(sink, false, false, ErrorSeverity.Error)
    assert SfsOrderedCount(sink) == 1
    assert SfsOrderedCount(sink) == 1
    assert sink.Count == 1
}

test "A FUNCTION FINDING AND A TYPE FINDING SHARE ONE ORDERED LIST" {
    // They reach the list by different doors and must not reach it in different orders.
    sink := SfsStrict()
    sink.AddForType("NSYS080", "lifetime", "type", "a.nl", 5, 1, 1, "Buffer", null)
    sink.AddForFunction("NSYS010", "allocation", "function", 2, 1, 1, "a.nl", "Fn", false, false, ErrorSeverity.Error, null)
    ordered := sink.Ordered()
    assert ordered.Length == 2
    assert ordered[0].Message == "function"
    assert ordered[1].Message == "type"
    assert sink.ErrorCount == 2
}

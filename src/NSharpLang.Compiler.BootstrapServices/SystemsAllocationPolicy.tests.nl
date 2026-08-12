namespace NSharpLang.Compiler.Performance

import NSharpLang.Compiler

// Native contracts for WHETHER AN ALLOCATION IS ALLOWED WHERE IT HAPPENS.
//
// This rule was 53 lines inside `SystemsAnalyzer.cs` and it is the FIRST member of the type-policy
// neighbourhood that reports rather than classifies. Its NSYS001 error arm is one of only three
// codes the 71-target systems corpus fires at all (9 findings), so a regression here is visible
// end to end — but the corpus never reaches NSYS010 and never reaches the boundary WARNING arm, so
// these contracts are the direct pinning of both.
//
// FOUR THINGS THIS RULE IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE ARMS ARE A PRECEDENCE, NOT THREE INDEPENDENT TESTS. `[hot]` and `[alloc(none)]` answer
// FIRST and CONCLUSIVELY: a function that is both `[hot]` and `[boundary]` reports the ban, never
// the handoff warning, and — because the arm returns either way — an ALLOWED `[hot]` allocation
// reports nothing at all rather than falling through to the strict-profile arm.
//
// (2) THE TWO BANNED SENTENCES ARE DIFFERENT AND `[hot]` WINS. A developer needs to be told which
// promise the allocation broke.
//
// (3) THE BOUNDARY ARM IS A WARNING AND THE OTHER TWO ARE ERRORS. Severity is part of what the rule
// decided, which is why this family's violation record carries it and the stackalloc rule's does not.
//
// (4) THE STRICT-PROFILE ARM ONLY APPLIES TO A SYSTEMS PROFILE AND ONLY TO AN UNSPELLED ALLOCATION.
// `alloc new` / an `alloc` zone silences it; a non-systems profile never reaches it.

func SapAlloc(isHot: bool, allocNone: bool, isBoundary: bool, allocAllowed: bool, isSystemsProfile: bool, explicitAllocation: bool): SystemsAllocationViolation? {
    return SystemsAllocationPolicy.Violation(isHot, allocNone, isBoundary, allocAllowed, isSystemsProfile, explicitAllocation)
}

test "A HOT FUNCTION MAY NOT ALLOCATE, AND THE SENTENCE NAMES THE ATTRIBUTE IT BROKE" {
    violation := SapAlloc(true, false, false, false, true, false)
    assert violation != null
    assert violation.Code == "NSYS010"
    assert violation.Effect == "allocation"
    assert violation.Message == "allocation not allowed in [hot] function"
    assert violation.Severity == ErrorSeverity.Error
    assert violation.Suggestion == "Move allocation behind a [boundary], return caller-provided storage, or use a narrow allow(alloc) only for a cold path."
}

test "AN ALLOC(NONE) FUNCTION GETS THE SAME CODE AND A DIFFERENT SENTENCE" {
    violation := SapAlloc(false, true, false, false, true, false)
    assert violation != null
    assert violation.Code == "NSYS010"
    assert violation.Message == "allocation not allowed in [alloc(none)] function"
    assert violation.Severity == ErrorSeverity.Error
}

test "HOT WINS THE SENTENCE WHEN A FUNCTION IS BOTH HOT AND ALLOC(NONE)" {
    violation := SapAlloc(true, true, false, false, true, false)
    assert violation != null
    assert violation.Message == "allocation not allowed in [hot] function"
}

test "A NARROW ALLOW(ALLOC) SILENCES THE BAN, AND IT SILENCES THE WHOLE RULE" {
    // The ban arm returns either way, so an ALLOWED hot allocation never falls through to the
    // strict-profile arm below it — even in a systems project with an unspelled allocation.
    assert SapAlloc(true, false, false, true, true, false) == null
    assert SapAlloc(false, true, false, true, true, false) == null
}

test "THE BAN OUTRANKS THE BOUNDARY REPORT, SO A HOT BOUNDARY REPORTS THE BAN" {
    violation := SapAlloc(true, false, true, false, true, false)
    assert violation != null
    assert violation.Code == "NSYS010"
    assert violation.Severity == ErrorSeverity.Error
}

test "A BOUNDARY ALLOCATION IS REPORTED FOR REVIEW AS A WARNING, NOT REFUSED" {
    violation := SapAlloc(false, false, true, false, true, false)
    assert violation != null
    assert violation.Code == "NSYS001"
    assert violation.Effect == "allocation"
    assert violation.Message == "boundary allocation reported for systems handoff review"
    assert violation.Severity == ErrorSeverity.Warning
    assert violation.Suggestion == "Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>."
}

test "THE BOUNDARY ARM IS REACHED IN EVERY PROFILE AND IS INDIFFERENT TO THE ALLOC KEYWORD" {
    // It answers conclusively, so neither the profile nor an explicit `alloc` changes it.
    first := SapAlloc(false, false, true, false, false, true)
    assert first != null
    assert first.Code == "NSYS001"
    assert first.Severity == ErrorSeverity.Warning
    second := SapAlloc(false, false, true, true, true, true)
    assert second != null
    assert second.Severity == ErrorSeverity.Warning
}

test "A SYSTEMS PROFILE REQUIRES EVERY PLAIN ALLOCATION TO BE SPELLED" {
    violation := SapAlloc(false, false, false, false, true, false)
    assert violation != null
    assert violation.Code == "NSYS001"
    assert violation.Message == "heap allocation in systems strict must be marked with alloc"
    assert violation.Severity == ErrorSeverity.Error
    assert violation.Suggestion == "Write alloc new/alloc [...]/alloc $\"...\" or move this work into a [boundary]."
}

test "AN EXPLICIT ALLOC OR AN ALLOC ZONE SATISFIES THE STRICT-PROFILE ARM" {
    assert SapAlloc(false, false, false, false, true, true) == null
}

test "A NON-SYSTEMS PROFILE NEVER REACHES THE STRICT ARM, SO A PLAIN ALLOCATION IS SILENT" {
    assert SapAlloc(false, false, false, false, false, false) == null
    assert SapAlloc(false, false, false, true, false, false) == null
}

test "THE TWO NSYS001 ARMS SHARE A CODE AND AGREE ON NOTHING ELSE" {
    boundary := SapAlloc(false, false, true, false, true, false)
    strict := SapAlloc(false, false, false, false, true, false)
    assert boundary != null
    assert strict != null
    assert boundary.Code == strict.Code
    assert boundary.Message != strict.Message
    assert boundary.Severity != strict.Severity
    assert boundary.Suggestion != strict.Suggestion
}

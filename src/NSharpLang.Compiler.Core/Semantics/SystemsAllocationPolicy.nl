namespace NSharpLang.Compiler.Performance

import NSharpLang.Compiler


// One violation of the allocation rule, stated by the owner rather than by its caller. Unlike the
// stackalloc rule's record this one carries its own SEVERITY, because the same subject is an error on
// two arms and a warning on the third, and which it is belongs to the rule that decided it.
record SystemsAllocationViolation(Code: string, Effect: string, Message: string, Severity: ErrorSeverity, Suggestion: string) {
}

// WHETHER AN ALLOCATION IS ALLOWED WHERE IT HAPPENS.
//
// Four expression shapes reach the heap in Systems N# — a `new`, an array literal, an interpolated
// string and a `with` copy — and this rule is asked about every one of them. It answers with at most
// one finding, and the interesting part is the ORDER of its three arms, because they are not
// independent tests: they are a precedence.
//
// A BAN OUTRANKS A REPORT. `[hot]` and `[alloc(none)]` are the same answer here — allocation is
// forbidden — and they are checked FIRST and answered CONCLUSIVELY: a `[hot]` function that also
// carries `[boundary]` reports the ban, never the handoff warning. A narrow `allow(alloc)`, whether
// written on the function or on an enclosing block, silences that arm and, because the arm returns
// either way, silences the rule entirely for that function.
//
// A BOUNDARY REPORTS RATHER THAN REFUSES. `[boundary]` is where a systems program is allowed to meet
// the managed world, so its allocations are a warning for review and not an error, and it too answers
// conclusively.
//
// THE STRICT-PROFILE ARM IS THE ONE THAT ASKS FOR THE `alloc` KEYWORD. Outside `[hot]`,
// `[alloc(none)]` and `[boundary]`, a systems project still requires every heap allocation to be
// SPELLED — `alloc new`, `alloc [...]`, `alloc $"..."` — or to sit inside an `alloc` zone. Its
// `!isBoundary` conjunct is unreachable, because the arm above it returns on exactly that condition;
// it is PRESERVED as the original wrote it rather than tidied, since removing a redundant guard is a
// behaviour-neutral edit only for as long as the arm above it keeps returning.
//
// THE SUMMARY WRITE IS NOT PART OF THE RULE. `Summary.Allocates = true` happens unconditionally at
// every one of the four sites, before any of this is asked, so it stays with the walk: it records
// what the function DID, while this owner decides what it is allowed to do.
class SystemsAllocationPolicy {
    static func Violation(isHot: bool, allocNone: bool, isBoundary: bool, allocAllowed: bool, isSystemsProfile: bool, explicitAllocation: bool): SystemsAllocationViolation? {
        if isHot || allocNone {
            if !allocAllowed {
                return new SystemsAllocationViolation("NSYS010", "allocation", BannedAllocationMessage(isHot), ErrorSeverity.Error, "Move allocation behind a [boundary], return caller-provided storage, or use a narrow allow(alloc) only for a cold path.")
            }

            return null
        }

        if isBoundary {
            return new SystemsAllocationViolation("NSYS001", "allocation", "boundary allocation reported for systems handoff review", ErrorSeverity.Warning, "Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>.")
        }

        if isSystemsProfile && !isBoundary && !explicitAllocation {
            return new SystemsAllocationViolation("NSYS001", "allocation", "heap allocation in systems strict must be marked with alloc", ErrorSeverity.Error, "Write alloc new/alloc [...]/alloc $\"...\" or move this work into a [boundary].")
        }

        return null
    }

    // The two attributes share the code and the fix but not the sentence: a developer needs to be
    // told WHICH promise the allocation broke, and `[hot]` wins when a function carries both.
    static func BannedAllocationMessage(isHot: bool): string {
        if isHot {
            return "allocation not allowed in [hot] function"
        }

        return "allocation not allowed in [alloc(none)] function"
    }
}

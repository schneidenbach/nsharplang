namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler


// THE SYSTEMS ANALYZER'S FINDING SINK: the single authority for what a systems finding IS, what
// severity it ends up carrying, and which policy label it wears — and the owner of the ordered list
// every `NSYS*` diagnostic in the product reaches the user through.
//
// THE LIST IS OWNED HERE RATHER THAN HANDED IN, and that is a deliberate difference from
// `AnalyzerDiagnosticSink`, which takes its `List<CompilerError>` by argument. That sink shares one
// ordered list with producers that have not moved yet, so a report's position among its neighbours
// must not depend on which side of the boundary made it. This one has NO other producer: every
// systems finding in the compiler is constructed by `Add` or `AddForType` below, so the list, the
// counts and the AOT verdict are all one owner's answer and nothing outside may scan them. The
// report ORDER is the one thing that is NOT decided here: `SystemsReportOrder` owns the position of
// every systems-report row — findings, trusted sites, function rows and call lists alike — so that
// four arrays a user reads side by side cannot be ordered by four different rules. `Ordered()`
// below is this sink's door onto that owner.
//
// THE SUBJECT TRAVELS WITH EACH REPORT rather than being held as analysis state. Holding the current
// function's file, name and hotness the way this sink holds the profile facts would shorten every
// door, and it would be WRONG: the analyzer's function walk is re-entrant — resolving a call analyses the
// callee mid-walk and then reports against the outer CALLER — so a scalar "current subject" would
// silently attribute a caller's finding to its callee.
//
// TWO DOWNGRADES, IN THIS ORDER. A `[boundary]` that is not also `[hot]` turns an error into a
// warning, because a boundary is where a systems program is allowed to meet the managed world and its
// findings are for review. AUDIT MODE then turns EVERY error into a warning, and it wins over the
// first because it is the whole project saying "report, do not fail". The order is only observable
// through the fact that audit is last, which is why it is written that way rather than as one
// combined test.
//
// A TYPE FINDING IS NOT A FUNCTION FINDING, AND THE ASYMMETRY IS THE RULE. A finding about a type
// declaration has no preferred severity to downgrade and no `[boundary]` to downgrade from — it is an
// error unless the project is in audit — and its policy label has no `[hot]` arm at all, because a
// type is not hot. Its call path is the type's own name, exactly as a function finding's default is
// the function's.
class SystemsFindingSink {
    findingsValue: List<SystemsFinding>
    isSystemsProfileValue: bool
    effectiveModeValue: string
    isAuditModeValue: bool

    constructor() {
        findingsValue = new List<SystemsFinding>()
        isSystemsProfileValue = false
        effectiveModeValue = "strict"
        isAuditModeValue = false
    }

    // WHETHER THIS PROJECT IS A SYSTEMS PROJECT, and in which mode. Both are read once per analysis
    // rather than at each decision, for the reason the stackalloc budget is: a project's
    // configuration cannot change mid-analysis, and reading it once is what makes it visible in this
    // owner's own contracts. The analyzer's own three properties route here rather than spelling the
    // same three tests a second time.
    IsSystemsProfile: bool => isSystemsProfileValue

    EffectiveMode: string => effectiveModeValue

    // AUDIT MODE IS A SYSTEMS-PROFILE MODE. A default-profile project whose systems mode happens to
    // read `audit` is NOT in audit: the profile gate comes first, and `EffectiveMode` is already
    // `strict` for it.
    IsAuditMode: bool => isAuditModeValue

    Count: int => findingsValue.Count

    ErrorCount: int => CountWithSeverity("error")

    WarningCount: int => CountWithSeverity("warning")

    // One call per analysis, from the analyzer's own reset block, and once more at construction so
    // that the routed profile questions answer correctly before any analysis has run.
    func BeginAnalysis(config: ProjectConfig) {
        findingsValue.Clear()
        isSystemsProfileValue = string.Equals(config.Language.Profile, "systems", StringComparison.OrdinalIgnoreCase)
        effectiveModeValue = "strict"
        if isSystemsProfileValue {
            effectiveModeValue = config.Language.Systems.Mode
        }

        isAuditModeValue = isSystemsProfileValue && string.Equals(effectiveModeValue, "audit", StringComparison.OrdinalIgnoreCase)
    }

    // THE ONE DOOR EVERY FUNCTION FINDING GOES THROUGH. The caller supplies the sentence, the
    // position and the severity it would PREFER; this decides the severity the user actually sees,
    // the policy label, and the `sourceInferred` provenance every systems finding carries.
    func Add(code: string, effect: string, message: string, line: int, column: int, length: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool, preferredSeverity: ErrorSeverity, suggestion: string?, callPath: IReadOnlyList<string>) {
        severity := EffectiveSeverity(preferredSeverity, isHot, isBoundary)
        finding := new SystemsFinding(code, SeverityText(severity), effect, message, filePath, line, column, Math.Max(1, length), functionName, FunctionPolicy(isHot), HotSummarySource.SourceInferred, suggestion, callPath)
        findingsValue.Add(finding)
    }

    // THE DEFAULT CALL PATH IS THE REPORTING FUNCTION'S OWN NAME, and it is a one-element path rather
    // than an empty one: the renderer turns a path into `effect path: a -> b`, and a finding about a
    // function is a path of length one through that function. Only the callee-policy family supplies
    // a longer one.
    func AddForFunction(code: string, effect: string, message: string, line: int, column: int, length: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool, preferredSeverity: ErrorSeverity, suggestion: string?) {
        callPath := new string[](1)
        callPath[0] = functionName
        Add(code, effect, message, line, column, length, filePath, functionName, isHot, isBoundary, preferredSeverity, suggestion, callPath)
    }

    // REPORTED ONLY INSIDE `[hot]`. The rules that use this door describe things that are merely
    // undesirable elsewhere and forbidden in a hot function, so a cold function hears nothing at all
    // — not a warning. Length is 1 because the caller has a node, not a name.
    func AddWhenHot(code: string, effect: string, message: string, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if !isHot {
            return
        }

        AddForFunction(code, effect, message, line, column, 1, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, null)
    }

    // REPORTED UNLESS THE EFFECT IS ALLOWED, AND THE ARMS ARE A PRECEDENCE. A narrow `allow(effect)`
    // — on the function or on an enclosing block — silences the rule entirely. A `[boundary]` reports
    // a WARNING and answers conclusively, so a function carrying both `[boundary]` and `[hot]` gets
    // the warning; that is the opposite precedence to the allocation rule, and it is the original's,
    // preserved rather than harmonised. Outside both, only `[hot]` or a systems-profile project
    // reports at all — a default-profile cold function is silent.
    func AddForPolicy(code: string, effect: string, message: string, line: int, column: int, effectAllowed: bool, filePath: string, functionName: string, isHot: bool, isBoundary: bool, suggestion: string?) {
        if effectAllowed {
            return
        }

        if isBoundary {
            AddForFunction(code, effect, message, line, column, 1, filePath, functionName, isHot, isBoundary, ErrorSeverity.Warning, suggestion)
            return
        }

        if isHot || isSystemsProfileValue {
            AddForFunction(code, effect, message, line, column, 1, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, suggestion)
        }
    }

    // A FINDING ABOUT A TYPE DECLARATION, which has no function summary behind it: the file and the
    // type's name arrive directly, the type's name IS the reported "function" and the whole call
    // path, and there is no hotness to label or to downgrade from.
    func AddForType(code: string, effect: string, message: string, filePath: string, line: int, column: int, length: int, typeName: string, suggestion: string?) {
        callPath := new string[](1)
        callPath[0] = typeName
        finding := new SystemsFinding(code, SeverityText(TypeSeverity()), effect, message, filePath, line, column, Math.Max(1, length), typeName, ProfilePolicy(), HotSummarySource.SourceInferred, suggestion, callPath)
        findingsValue.Add(finding)
    }

    func EffectiveSeverity(preferredSeverity: ErrorSeverity, isHot: bool, isBoundary: bool): ErrorSeverity {
        downgraded := preferredSeverity
        if isBoundary && !isHot && preferredSeverity == ErrorSeverity.Error {
            downgraded = ErrorSeverity.Warning
        }

        if isAuditModeValue {
            return ErrorSeverity.Warning
        }

        return downgraded
    }

    func TypeSeverity(): ErrorSeverity {
        if isAuditModeValue {
            return ErrorSeverity.Warning
        }

        return ErrorSeverity.Error
    }

    static func SeverityText(severity: ErrorSeverity): string {
        if severity == ErrorSeverity.Error {
            return "error"
        }

        return "warning"
    }

    // THE POLICY LABEL A READER SEES as "Systems policy 'X' rejected the 'Y' effect". `[hot]`
    // outranks the project's own mode, because a hot function's promise is stricter than the
    // project's.
    func FunctionPolicy(isHot: bool): string {
        if isHot {
            return "[hot]"
        }

        return ProfilePolicy()
    }

    // The label when hotness does not apply: the project's systems mode, or `local` for a project
    // that is not a systems project at all.
    func ProfilePolicy(): string {
        if isSystemsProfileValue {
            return "systems:" + effectiveModeValue
        }

        return "local"
    }

    func CountWithSeverity(severity: string): int {
        matched := 0
        index := 0
        while index < findingsValue.Count {
            if findingsValue[index].Severity == severity {
                matched = matched + 1
            }

            index = index + 1
        }

        return matched
    }

    // AOT ANALYSIS FAILS ON ONE FINDING AND ONE SEVERITY. An NSYS060 that was downgraded — by a
    // boundary or by audit mode — does NOT fail the AOT verdict, which is why this reads the emitted
    // severity rather than asking whether an NSYS060 was reported at all.
    func AotAnalysis(): string {
        index := 0
        while index < findingsValue.Count {
            finding := findingsValue[index]
            if finding.Code == "NSYS060" && finding.Severity == "error" {
                return "fail"
            }

            index = index + 1
        }

        return "pass"
    }

    // THE ORDERED LIST, AND THE ONE DOOR THAT HANDS IT OUT. The LIST is owned here — nothing
    // outside may scan `findingsValue` — but the ORDER is not: `SystemsReportOrder` owns the order
    // of every row a systems report shows, so that a finding's position among its neighbours is
    // decided by the same rule that decides a trusted site's, in one place, once.
    func Ordered(): SystemsFinding[] {
        return SystemsReportOrder.OrderedFindings(findingsValue)
    }
}

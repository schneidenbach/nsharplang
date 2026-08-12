namespace NSharpLang.Compiler.Performance

import System
import NSharpLang.Compiler


// WHAT A DECLARED FACT COSTS THE FUNCTION THAT TRUSTS IT.
//
// The analyzer cannot see inside a compiled BCL method, so a HotSummary entry stands in for the body
// it could not read. This owner decides whether such an entry may be trusted at all, and — once it
// is — what its declared effects cost the caller. It is the LAST family in the file that turns a
// fact into a diagnostic, and it names ELEVEN codes, more than any other systems owner.
//
// A SIDECAR IS NOT A COMPILER FACT, AND THE TWO GATES SAY WHY. A summary shipped beside a project
// asserts things about code the compiler never analysed, so a `[hot]` function is not allowed to be
// satisfied by one unless the project has explicitly said it audited them
// (`language.systems.allowHotSidecars`) — and even then, a sidecar with no body identity and no
// package version cannot be re-checked when the code behind it changes, so its facts cannot be
// audited for drift at all. Both gates ANSWER CONCLUSIVELY: an entry that fails either one
// contributes an unknown-external-call and NOTHING else, because its remaining claims are exactly
// the claims that are not trustworthy. The BCL pack always passes both, because it is not a sidecar.
//
// THE GATES ARE ORDERED AND THE ORDER IS OBSERVABLE. The `[hot]`-policy gate runs first, so a hot
// function using an unaudited sidecar with no identity hears NSYS050 about project policy rather
// than NSYS150 about drift; a COLD function using the same entry hears NSYS150, because the first
// gate only applies to `[hot]`.
//
// THE EFFECT DELTA COMES BACK AS `SystemsEffectFacts` RATHER THAN BEING WRITTEN THROUGH. The bits it
// raises live on the analyzer's own mutable summary, which has not moved, so the rule returns what it
// decided and the walk merges it with the same 14-bit `MergeEffectsFrom` the callee merge uses — one
// mechanical door, no policy at the site. Every record this owner returns satisfies the estate's
// invariant `AotSafe == !UsesDynamicCode && !UsesReflection`.
//
// TWO BITS ARE RAISED BY THIS RULE AND NOT BY THE ENTRY. `RequiresWarmup` is raised only when the
// entry needs warmup AND the project configured none — a project that lists its warmup functions has
// already answered — and `UsesReflection` is raised when the entry is not AOT/trim safe for the
// project's target, because an unproven-AOT call is exactly as blocking as a reflective one.
//
// THE PROJECT'S THREE SETTINGS ARE READ ONCE PER ANALYSIS, the `SystemsStackallocPolicy` precedent:
// a project's configuration cannot change mid-analysis, and reading it once is what makes it visible
// in this owner's own contracts.
//
// ONLY A `[hot]` OR `alloc(none)` CALLER IS TOLD WHAT A SUMMARISED CALL COSTS, and the six arms
// behind that gate are not mutually exclusive — one entry that allocates AND boxes AND throws
// produces three findings at the same position, in the order written here.
class SystemsHotSummaryPolicy {
    sinkValue: SystemsFindingSink
    allowHotSidecarsValue: bool
    hasWarmupValue: bool
    aotTargetValue: string

    constructor(sink: SystemsFindingSink) {
        sinkValue = sink
        allowHotSidecarsValue = false
        hasWarmupValue = false
        aotTargetValue = ""
    }

    // One call per analysis, from the analyzer's own reset block. See the header for why the three
    // settings are read here and not at each summarised call.
    func BeginAnalysis(config: ProjectConfig) {
        allowHotSidecarsValue = config.Language.Systems.AllowHotSidecars
        hasWarmupValue = config.Language.Systems.Warmup.Count > 0
        aotTargetValue = config.Language.Systems.AotTarget
    }

    // `Buffer.MemoryCopy` IS THE ONE CALL THE SYSTEMS PROFILE REQUIRES A SYNTACTIC CAGE FOR. It reads
    // and writes raw memory with no bounds check of any kind, so the profile insists the call sit
    // inside an `unsafe` block where a reader can see the proof obligation, and reports it under the
    // memory-safety policy — which means a narrow `allow(memorySafety)` silences it and a
    // `[boundary]` downgrades it, exactly like every other policy finding.
    func ReportBufferMemoryCopy(inUnsafeBlock: bool, memorySafetyAllowed: bool, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if inUnsafeBlock {
            return
        }

        sinkValue.AddForPolicy("NSYS100", "memorySafety", "Buffer.MemoryCopy must be isolated inside an unsafe block", line, column, memorySafetyAllowed, filePath, functionName, isHot, isBoundary, "Wrap Buffer.MemoryCopy in a small [trusted] [memory(safe)] function and document the bounds proof.")
    }

    // WHAT A RESOLVED HOTSUMMARY ENTRY COSTS ITS CALLER. Returns the effect bits the caller's summary
    // must take on; see the header for the two conclusive gates, the two bits this rule raises
    // itself, and why the delta travels as a record.
    func ApplyHotSummary(target: string, entry: HotSummaryEntry, aotAllowed: bool, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool, allocNone: bool): SystemsEffectFacts {
        length := Math.Max(1, SystemsTypeNames.SimpleName(target).Length)
        if entry.IsSidecar && isHot && !allowHotSidecarsValue {
            sinkValue.AddForFunction("NSYS050", "unknownExternalCall", "sidecar HotSummary for '" + target + "' is not allowed to satisfy [hot] by project policy", line, column, length, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Set language.systems.allowHotSidecars only after auditing the sidecar identity and body hash, or move the call behind a [boundary].")
            return UnknownExternalCallOnly()
        }

        if entry.IsSidecar && string.IsNullOrWhiteSpace(entry.BodyIdentity) && string.IsNullOrWhiteSpace(entry.PackageVersion) {
            sinkValue.AddForFunction("NSYS150", "effectDrift", "sidecar HotSummary for '" + target + "' is missing body identity or package version, so per-fact drift cannot be audited", line, column, length, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Key sidecar facts by MVID/body hash, source hash, or package version plus metadata identity.")
            return UnknownExternalCallOnly()
        }

        effects := entry.Effects
        requiresWarmup := effects.RequiresWarmup && !hasWarmupValue
        if requiresWarmup {
            sinkValue.AddWhenHot("NSYS110", "hotReadiness", "HotSummary for '" + target + "' requires warmup before [hot] use", line, column, filePath, functionName, isHot, isBoundary)
        }

        aotUnsafe := !effects.TrimSafe || !entry.IsAotSafeFor(aotTargetValue)
        if aotUnsafe {
            sinkValue.AddForPolicy("NSYS060", "aot", "HotSummary for '" + target + "' is not AOT/trim safe for " + aotTargetValue, line, column, aotAllowed, filePath, functionName, isHot, isBoundary, "Use a target-qualified summary or move the call behind a [boundary].")
        }

        if isHot || allocNone {
            ReportHotArms(target, effects, line, column, filePath, functionName, isHot, isBoundary)
        }

        usesReflection := effects.UsesReflection || aotUnsafe
        aotSafe := !effects.UsesDynamicCode && !usesReflection
        return new SystemsEffectFacts(effects.Allocates, effects.Boxes, effects.ConstructsDelegate, effects.CapturesClosure, effects.UsesRuntimeDispatch, usesReflection, effects.UsesDynamicCode, effects.Throws, effects.HasImplicitTrapObligation, effects.UsesUnknownExternalCall, effects.UsesResource, effects.UsesPool, effects.UsesConcurrencyPrimitive, requiresWarmup, aotSafe)
    }

    // THE SIX ARMS A HOT OR `alloc(none)` CALLER HEARS. Every one is reported only inside `[hot]` —
    // the `AddWhenHot` door — so an `alloc(none)` COLD caller reaches this and hears nothing, which is
    // the original's behaviour and not an accident: the gate above admits it, the door below does not.
    //
    // NSYS030 IS ONE FINDING FOR TWO BITS and NSYS120 IS ONE FINDING FOR TWO BITS WITH TWO NAMES:
    // a delegate and a closure are the same cost, while a throw and an implicit trap are different
    // obligations that share a code, so the EFFECT label switches between them and `throw` wins when
    // both are declared.
    func ReportHotArms(target: string, effects: HotSummaryEffects, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if effects.Allocates {
            sinkValue.AddWhenHot("NSYS010", "allocation", "HotSummary for '" + target + "' allocates", line, column, filePath, functionName, isHot, isBoundary)
        }

        if effects.Boxes {
            sinkValue.AddWhenHot("NSYS020", "boxing", "HotSummary for '" + target + "' boxes", line, column, filePath, functionName, isHot, isBoundary)
        }

        if effects.ConstructsDelegate || effects.CapturesClosure {
            sinkValue.AddWhenHot("NSYS030", "delegate", "HotSummary for '" + target + "' constructs a delegate or closure", line, column, filePath, functionName, isHot, isBoundary)
        }

        if effects.UsesRuntimeDispatch {
            sinkValue.AddWhenHot("NSYS040", "dispatch", "HotSummary for '" + target + "' uses runtime dispatch", line, column, filePath, functionName, isHot, isBoundary)
        }

        if effects.Throws || effects.HasImplicitTrapObligation {
            sinkValue.AddWhenHot("NSYS120", TrapEffectName(effects), "HotSummary for '" + target + "' has a throwing/trap obligation", line, column, filePath, functionName, isHot, isBoundary)
        }

        if effects.UsesResource {
            sinkValue.AddWhenHot("NSYS090", "resource", "HotSummary for '" + target + "' uses a disposable resource", line, column, filePath, functionName, isHot, isBoundary)
        }
    }

    static func TrapEffectName(effects: HotSummaryEffects): string {
        if effects.Throws {
            return "throw"
        }

        return "implicitTrap"
    }

    // AN UNTRUSTED ENTRY CONTRIBUTES EXACTLY ONE BIT. See the header: the remaining claims of an entry
    // that failed a gate are precisely the claims that cannot be trusted, so none of them travels.
    static func UnknownExternalCallOnly(): SystemsEffectFacts {
        return new SystemsEffectFacts(false, false, false, false, false, false, false, false, false, true, false, false, false, false, true)
    }
}

namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler

// Native contracts for WHAT A DECLARED FACT COSTS THE FUNCTION THAT TRUSTS IT.
//
// These two members were 104 lines inside `SystemsAnalyzer.cs` and they name ELEVEN codes — more
// than any other systems owner. NSYS150 is corpus-silent, NSYS100 fires only on `Buffer.MemoryCopy`,
// and the six hot arms need a resolved HotSummary entry, so these contracts are the direct pinning
// for most of that surface.
//
// NINE THINGS THIS FAMILY IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE TWO SIDECAR GATES ANSWER CONCLUSIVELY. An entry that fails either one contributes an
// unknown-external-call and NOTHING else — none of its declared effects travels, because those are
// exactly the claims that are not trustworthy.
//
// (2) THE GATES ARE ORDERED AND THE ORDER IS OBSERVABLE. The `[hot]`-policy gate runs first, so the
// same untrusted, unidentified sidecar reports NSYS050 from a hot caller and NSYS150 from a cold one.
//
// (3) THE FIRST GATE IS ABOUT `[hot]` ONLY. A cold caller may be satisfied by an unaudited sidecar.
//
// (4) THE SECOND GATE NEEDS BOTH IDENTIFIERS TO BE ABSENT. A body identity OR a package version is
// enough to make drift auditable.
//
// (5) NEITHER GATE APPLIES TO A NON-SIDECAR ENTRY. The BCL pack is not a sidecar and always passes.
//
// (6) `RequiresWarmup` IS RAISED BY THE RULE, NOT BY THE ENTRY — only when the entry needs warmup AND
// the project configured none.
//
// (7) AN AOT-UNSAFE ENTRY RAISES `UsesReflection` EVEN WHEN THE FINDING IS WAIVED. `allow(aot)`
// silences the diagnostic; it does not make the call AOT-safe.
//
// (8) THE SIX HOT ARMS ARE GATED ON `[hot]` OR `alloc(none)` BUT REPORTED ONLY WHEN HOT, so a cold
// `alloc(none)` caller passes the gate and still hears nothing. That is the original's behaviour.
//
// (9) EVERY RECORD THIS OWNER RETURNS SATISFIES `AotSafe == !UsesDynamicCode && !UsesReflection`.

func ShpConfig(profile: string, mode: string, allowSidecars: bool, warmup: bool, aotTarget: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("hot-summary-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    systems.AllowHotSidecars = allowSidecars
    systems.AotTarget = aotTarget
    if warmup {
        systems.Warmup.Add("Warm")
    }

    return config
}

func ShpSink(profile: string, mode: string): SystemsFindingSink {
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(ShpConfig(profile, mode, false, false, "linux-x64"))
    return sink
}

func ShpPolicy(sink: SystemsFindingSink, allowSidecars: bool, warmup: bool, aotTarget: string): SystemsHotSummaryPolicy {
    policy := new SystemsHotSummaryPolicy(sink)
    policy.BeginAnalysis(ShpConfig("systems", "strict", allowSidecars, warmup, aotTarget))
    return policy
}

func ShpEffects(): HotSummaryEffects {
    return new HotSummaryEffects()
}

func ShpEntry(source: string, effects: HotSummaryEffects): HotSummaryEntry {
    entry := new HotSummaryEntry()
    entry.Method = "Codec.Encode"
    entry.Source = source
    entry.Effects = effects
    return entry
}

func ShpSidecar(effects: HotSummaryEffects): HotSummaryEntry {
    return ShpEntry(HotSummarySource.Sidecar, effects)
}

func ShpIdentifiedSidecar(effects: HotSummaryEffects): HotSummaryEntry {
    entry := ShpSidecar(effects)
    entry.BodyIdentity = "mvid:1"
    return entry
}

func ShpPack(effects: HotSummaryEffects): HotSummaryEntry {
    return ShpEntry(HotSummarySource.BclPack, effects)
}

// Field readers, one per field a contract asserts on.
func ShpCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

func ShpAt(sink: SystemsFindingSink, index: int): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[index]
}

func ShpCode(sink: SystemsFindingSink, index: int): string {
    finding := ShpAt(sink, index)
    return finding.Code
}

func ShpEffectName(sink: SystemsFindingSink, index: int): string {
    finding := ShpAt(sink, index)
    return finding.Effect
}

func ShpSeverity(sink: SystemsFindingSink, index: int): string {
    finding := ShpAt(sink, index)
    return finding.Severity
}

func ShpMessage(sink: SystemsFindingSink, index: int): string {
    finding := ShpAt(sink, index)
    return finding.Message
}

func ShpLength(sink: SystemsFindingSink, index: int): int {
    finding := ShpAt(sink, index)
    return finding.Length
}

// One summarised call, from a caller the contract describes.
func ShpApply(policy: SystemsHotSummaryPolicy, entry: HotSummaryEntry, aotAllowed: bool, isHot: bool, isBoundary: bool, allocNone: bool): SystemsEffectFacts {
    return policy.ApplyHotSummary("Codec.Encode", entry, aotAllowed, 12, 5, "hot.nl", "Owner.Run", isHot, isBoundary, allocNone)
}

func ShpAotSafeHolds(facts: SystemsEffectFacts): bool {
    expected := !facts.UsesDynamicCode && !facts.UsesReflection
    return facts.AotSafe == expected
}

test "AN UNAUDITED SIDECAR CANNOT SATISFY A HOT CALLER, AND NOTHING ELSE TRAVELS" {
    effects := ShpEffects()
    effects.Allocates = true
    effects.UsesPool = true
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpIdentifiedSidecar(effects), false, true, false, false)
    assert ShpCount(sink) == 1
    assert ShpCode(sink, 0) == "NSYS050"
    assert ShpEffectName(sink, 0) == "unknownExternalCall"
    assert ShpSeverity(sink, 0) == "error"
    assert ShpMessage(sink, 0) == "sidecar HotSummary for 'Codec.Encode' is not allowed to satisfy [hot] by project policy"
    assert facts.UsesUnknownExternalCall
    assert !facts.Allocates
    assert !facts.UsesPool
    assert ShpAotSafeHolds(facts)
}

test "THE UNDERLINE IS THE TARGET'S SIMPLE NAME" {
    sink := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpIdentifiedSidecar(ShpEffects()), false, true, false, false)
    assert ShpLength(sink, 0) == 6
}

test "AN AUDITED SIDECAR MAY SATISFY A HOT CALLER" {
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, true, false, "linux-x64"), ShpIdentifiedSidecar(ShpEffects()), false, true, false, false)
    assert ShpCount(sink) == 0
    assert !facts.UsesUnknownExternalCall
}

test "THE FIRST GATE IS ABOUT HOT ONLY, SO A COLD CALLER PASSES IT" {
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpIdentifiedSidecar(ShpEffects()), false, false, false, false)
    assert ShpCount(sink) == 0
    assert !facts.UsesUnknownExternalCall
}

test "A SIDECAR WITH NO IDENTITY AND NO PACKAGE VERSION CANNOT BE AUDITED FOR DRIFT" {
    effects := ShpEffects()
    effects.Allocates = true
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, true, false, "linux-x64"), ShpSidecar(effects), false, false, false, false)
    assert ShpCount(sink) == 1
    assert ShpCode(sink, 0) == "NSYS150"
    assert ShpEffectName(sink, 0) == "effectDrift"
    assert ShpMessage(sink, 0) == "sidecar HotSummary for 'Codec.Encode' is missing body identity or package version, so per-fact drift cannot be audited"
    assert facts.UsesUnknownExternalCall
    assert !facts.Allocates
    assert ShpAotSafeHolds(facts)
}

test "EITHER IDENTIFIER IS ENOUGH TO MAKE DRIFT AUDITABLE" {
    byBody := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(byBody, true, false, "linux-x64"), ShpIdentifiedSidecar(ShpEffects()), false, false, false, false)
    assert ShpCount(byBody) == 0

    versioned := ShpSidecar(ShpEffects())
    versioned.PackageVersion = "1.2.3"
    byVersion := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(byVersion, true, false, "linux-x64"), versioned, false, false, false, false)
    assert ShpCount(byVersion) == 0
}

test "THE GATE ORDER IS OBSERVABLE: HOT HEARS POLICY, COLD HEARS DRIFT" {
    hot := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(hot, false, false, "linux-x64"), ShpSidecar(ShpEffects()), false, true, false, false)
    assert ShpCode(hot, 0) == "NSYS050"

    cold := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(cold, false, false, "linux-x64"), ShpSidecar(ShpEffects()), false, false, false, false)
    assert ShpCode(cold, 0) == "NSYS150"
}

test "NEITHER GATE APPLIES TO A NON-SIDECAR ENTRY" {
    effects := ShpEffects()
    effects.Allocates = true
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, true, false, false)
    assert facts.Allocates
    assert !facts.UsesUnknownExternalCall
}

test "A TRUSTED ENTRY'S THIRTEEN DECLARED BITS ALL TRAVEL" {
    effects := ShpEffects()
    effects.Allocates = true
    effects.Boxes = true
    effects.ConstructsDelegate = true
    effects.CapturesClosure = true
    effects.UsesRuntimeDispatch = true
    effects.UsesReflection = true
    effects.UsesDynamicCode = true
    effects.Throws = true
    effects.HasImplicitTrapObligation = true
    effects.UsesUnknownExternalCall = true
    effects.UsesResource = true
    effects.UsesPool = true
    effects.UsesConcurrencyPrimitive = true
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), true, false, false, false)
    assert facts.Allocates
    assert facts.Boxes
    assert facts.ConstructsDelegate
    assert facts.CapturesClosure
    assert facts.UsesRuntimeDispatch
    assert facts.UsesReflection
    assert facts.UsesDynamicCode
    assert facts.Throws
    assert facts.HasImplicitTrapObligation
    assert facts.UsesUnknownExternalCall
    assert facts.UsesResource
    assert facts.UsesPool
    assert facts.UsesConcurrencyPrimitive
    assert ShpAotSafeHolds(facts)
}

test "AN ENTRY WITH NO DECLARED EFFECTS COSTS NOTHING" {
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(ShpEffects()), false, true, false, false)
    assert ShpCount(sink) == 0
    assert !facts.Allocates
    assert !facts.RequiresWarmup
    assert facts.AotSafe
}

test "WARMUP IS RAISED ONLY WHEN THE PROJECT CONFIGURED NONE" {
    effects := ShpEffects()
    effects.RequiresWarmup = true
    unwarmed := ShpSink("systems", "strict")
    unwarmedFacts := ShpApply(ShpPolicy(unwarmed, false, false, "linux-x64"), ShpPack(effects), false, true, false, false)
    assert unwarmedFacts.RequiresWarmup
    assert ShpCount(unwarmed) == 1
    assert ShpCode(unwarmed, 0) == "NSYS110"
    assert ShpEffectName(unwarmed, 0) == "hotReadiness"
    assert ShpMessage(unwarmed, 0) == "HotSummary for 'Codec.Encode' requires warmup before [hot] use"

    warmed := ShpSink("systems", "strict")
    warmedFacts := ShpApply(ShpPolicy(warmed, false, true, "linux-x64"), ShpPack(effects), false, true, false, false)
    assert !warmedFacts.RequiresWarmup
    assert ShpCount(warmed) == 0
}

test "THE WARMUP FINDING IS HEARD ONLY INSIDE HOT" {
    effects := ShpEffects()
    effects.RequiresWarmup = true
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, false, false, false)
    assert ShpCount(sink) == 0
    // The BIT is still raised; only the report is hot-only.
    assert facts.RequiresWarmup
}

test "AN ENTRY THAT IS NOT TRIM SAFE IS AN AOT FINDING AND RAISES REFLECTION" {
    effects := ShpEffects()
    effects.TrimSafe = false
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, false, false, false)
    assert ShpCount(sink) == 1
    assert ShpCode(sink, 0) == "NSYS060"
    assert ShpEffectName(sink, 0) == "aot"
    assert ShpMessage(sink, 0) == "HotSummary for 'Codec.Encode' is not AOT/trim safe for linux-x64"
    assert facts.UsesReflection
    assert !facts.AotSafe
}

test "AN ENTRY THAT IS AOT SAFE FOR A DIFFERENT TARGET IS NOT AOT SAFE HERE" {
    effects := ShpEffects()
    effects.AotSafeTargets.Add("win-x64")
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, false, false, false)
    assert ShpCount(sink) == 1
    assert facts.UsesReflection

    matched := ShpSink("systems", "strict")
    matchedFacts := ShpApply(ShpPolicy(matched, false, false, "win-x64"), ShpPack(effects), false, false, false, false)
    assert ShpCount(matched) == 0
    assert !matchedFacts.UsesReflection
}

test "allow(aot) SILENCES THE FINDING BUT DOES NOT MAKE THE CALL AOT SAFE" {
    effects := ShpEffects()
    effects.TrimSafe = false
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), true, false, false, false)
    assert ShpCount(sink) == 0
    assert facts.UsesReflection
    assert !facts.AotSafe
}

test "THE SIX HOT ARMS FIRE TOGETHER AND IN A WRITTEN ORDER" {
    effects := ShpEffects()
    effects.Allocates = true
    effects.Boxes = true
    effects.CapturesClosure = true
    effects.UsesRuntimeDispatch = true
    effects.HasImplicitTrapObligation = true
    effects.UsesResource = true
    sink := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, true, false, false)
    assert ShpCount(sink) == 6
    assert ShpCode(sink, 0) == "NSYS010"
    assert ShpCode(sink, 1) == "NSYS020"
    assert ShpCode(sink, 2) == "NSYS030"
    assert ShpCode(sink, 3) == "NSYS040"
    assert ShpCode(sink, 4) == "NSYS120"
    assert ShpCode(sink, 5) == "NSYS090"
    assert ShpMessage(sink, 0) == "HotSummary for 'Codec.Encode' allocates"
    assert ShpMessage(sink, 2) == "HotSummary for 'Codec.Encode' constructs a delegate or closure"
    assert ShpMessage(sink, 5) == "HotSummary for 'Codec.Encode' uses a disposable resource"
}

test "A DELEGATE AND A CLOSURE ARE ONE FINDING" {
    effects := ShpEffects()
    effects.ConstructsDelegate = true
    effects.CapturesClosure = true
    sink := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, true, false, false)
    assert ShpCount(sink) == 1
    assert ShpCode(sink, 0) == "NSYS030"
}

test "NSYS120 IS ONE CODE WITH TWO EFFECT NAMES AND throw WINS" {
    trap := ShpEffects()
    trap.HasImplicitTrapObligation = true
    trapSink := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(trapSink, false, false, "linux-x64"), ShpPack(trap), false, true, false, false)
    assert ShpEffectName(trapSink, 0) == "implicitTrap"

    both := ShpEffects()
    both.Throws = true
    both.HasImplicitTrapObligation = true
    bothSink := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(bothSink, false, false, "linux-x64"), ShpPack(both), false, true, false, false)
    assert ShpCount(bothSink) == 1
    assert ShpEffectName(bothSink, 0) == "throw"
}

test "A COLD alloc(none) CALLER PASSES THE GATE AND STILL HEARS NOTHING" {
    effects := ShpEffects()
    effects.Allocates = true
    sink := ShpSink("systems", "strict")
    facts := ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, false, false, true)
    assert ShpCount(sink) == 0
    assert facts.Allocates
}

test "A PLAIN COLD CALLER IS NOT ASKED AT ALL" {
    effects := ShpEffects()
    effects.Allocates = true
    effects.UsesResource = true
    sink := ShpSink("systems", "strict")
    ShpApply(ShpPolicy(sink, false, false, "linux-x64"), ShpPack(effects), false, false, false, false)
    assert ShpCount(sink) == 0
}

test "Buffer.MemoryCopy INSIDE AN UNSAFE BLOCK IS SILENT" {
    sink := ShpSink("systems", "strict")
    policy := ShpPolicy(sink, false, false, "linux-x64")
    policy.ReportBufferMemoryCopy(true, false, 9, 4, "copy.nl", "Owner.Copy", true, false)
    assert ShpCount(sink) == 0
}

test "Buffer.MemoryCopy OUTSIDE AN UNSAFE BLOCK IS A MEMORY-SAFETY FINDING" {
    sink := ShpSink("systems", "strict")
    policy := ShpPolicy(sink, false, false, "linux-x64")
    policy.ReportBufferMemoryCopy(false, false, 9, 4, "copy.nl", "Owner.Copy", true, false)
    assert ShpCount(sink) == 1
    assert ShpCode(sink, 0) == "NSYS100"
    assert ShpEffectName(sink, 0) == "memorySafety"
    assert ShpSeverity(sink, 0) == "error"
    assert ShpMessage(sink, 0) == "Buffer.MemoryCopy must be isolated inside an unsafe block"
}

test "A NARROW allow(memorySafety) SILENCES IT AND A BOUNDARY DOWNGRADES IT" {
    allowed := ShpSink("systems", "strict")
    ShpPolicy(allowed, false, false, "linux-x64").ReportBufferMemoryCopy(false, true, 9, 4, "copy.nl", "Owner.Copy", true, false)
    assert ShpCount(allowed) == 0

    boundary := ShpSink("systems", "strict")
    ShpPolicy(boundary, false, false, "linux-x64").ReportBufferMemoryCopy(false, false, 9, 4, "copy.nl", "Owner.Copy", false, true)
    assert ShpSeverity(boundary, 0) == "warning"
}

test "A COLD CALLER IN A DEFAULT-PROFILE PROJECT HEARS NOTHING ABOUT Buffer.MemoryCopy" {
    sink := ShpSink("default", "strict")
    policy := new SystemsHotSummaryPolicy(sink)
    policy.BeginAnalysis(ShpConfig("default", "strict", false, false, "linux-x64"))
    policy.ReportBufferMemoryCopy(false, false, 9, 4, "copy.nl", "Owner.Copy", false, false)
    assert ShpCount(sink) == 0
}

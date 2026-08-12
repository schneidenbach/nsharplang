namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A CALL COSTS ITS CALLER.
//
// These three rules were 99 lines inside `SystemsAnalyzer.cs` — `CheckIgnoredResult` (22),
// `ReportCalleePolicyViolations` (26) and `AddUnknownExternalCall` (51) — reached from five sites in
// the statement walk, the expression walk, the call walk and the callee merge. NSYS050 is the single
// most-fired code in the estate, and the ten codes the callee rule carries plus NSYS160 are silent in
// the whole corpus, so these contracts and the purpose-built caller/callee fixtures are the direct
// pinning for everything except NSYS050.
//
// NINE THINGS THIS FAMILY IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE THREE UNRESOLVED-CALL ARMS ARE A PRECEDENCE, NOT A SET. A function that is BOTH `[hot]` and
// `[boundary]` gets the hot ERROR, and the project's setting is never consulted for it.
//
// (2) THE PROJECT SETTING IS ONLY REACHED BY A FUNCTION THAT IS NEITHER, IN A SYSTEMS PROJECT. A
// default-profile cold function is silent no matter what the setting says — including `error`.
//
// (3) `allow` IS SILENCE, `error` FAILS, AND EVERYTHING ELSE WARNS. The else arm is load-bearing: a
// hand-built config that never went through `ProjectFileParser` must warn rather than throw.
//
// (4) THE SETTING IS READ ONCE PER ANALYSIS. Changing the config object after `BeginAnalysis` does not
// change what the rule decides, which is the whole point of reading it there.
//
// (5) THE UNDERLINE IS THE TARGET'S SIMPLE NAME. `Console.WriteLine` underlines nine columns, not
// seventeen.
//
// (6) ONLY A `[hot]` OR `alloc(none)` CALLER IS TOLD WHAT ITS CALLEES COST — and `[boundary]` alone
// does NOT open that gate, which is the opposite of what the boundary arm of the unresolved-call rule
// does.
//
// (7) THE CALLER'S ALLOW TEST IS AN EXACT FUNCTION-LEVEL SET MEMBERSHIP, and it silences exactly two
// of the ten arms — allocation and pool — and nothing else.
//
// (8) THE ARMS ARE NOT MUTUALLY EXCLUSIVE. One callee that allocates and boxes and reflects produces
// three findings at the same position, in the rule's own order.
//
// (9) A CALLEE FINDING NAMES TWO FUNCTIONS. Its call path is caller then callee, which is what the
// renderer turns into `effect path: a -> b`; every other systems finding names one.

func ScpConfig(profile: string, mode: string, unknownExternalCalls: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("callee-policy-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    systems.UnknownExternalCalls = unknownExternalCalls
    return config
}

func ScpSink(profile: string, mode: string): SystemsFindingSink {
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(ScpConfig(profile, mode, "warn"))
    return sink
}

func ScpPolicy(sink: SystemsFindingSink, profile: string, mode: string, unknownExternalCalls: string): SystemsCalleePolicy {
    policy := new SystemsCalleePolicy(new SystemsTypePolicy(), sink)
    policy.BeginAnalysis(ScpConfig(profile, mode, unknownExternalCalls))
    return policy
}

// Field readers, one per field a contract asserts on: a property read chained onto a call result does
// not emit.
func ScpCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

func ScpAt(sink: SystemsFindingSink, index: int): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[index]
}

func ScpCode(sink: SystemsFindingSink): string {
    finding := ScpAt(sink, 0)
    return finding.Code
}

func ScpCodeAt(sink: SystemsFindingSink, index: int): string {
    finding := ScpAt(sink, index)
    return finding.Code
}

func ScpEffect(sink: SystemsFindingSink): string {
    finding := ScpAt(sink, 0)
    return finding.Effect
}

func ScpSeverity(sink: SystemsFindingSink): string {
    finding := ScpAt(sink, 0)
    return finding.Severity
}

func ScpMessage(sink: SystemsFindingSink): string {
    finding := ScpAt(sink, 0)
    return finding.Message
}

func ScpMessageAt(sink: SystemsFindingSink, index: int): string {
    finding := ScpAt(sink, index)
    return finding.Message
}

func ScpSuggestion(sink: SystemsFindingSink): string? {
    finding := ScpAt(sink, 0)
    return finding.Suggestion
}

func ScpLine(sink: SystemsFindingSink): int {
    finding := ScpAt(sink, 0)
    return finding.Line
}

func ScpColumn(sink: SystemsFindingSink): int {
    finding := ScpAt(sink, 0)
    return finding.Column
}

func ScpLength(sink: SystemsFindingSink): int {
    finding := ScpAt(sink, 0)
    return finding.Length
}

func ScpFunctionName(sink: SystemsFindingSink): string? {
    finding := ScpAt(sink, 0)
    return finding.Function
}

func ScpPolicyLabel(sink: SystemsFindingSink): string? {
    finding := ScpAt(sink, 0)
    return finding.Policy
}

func ScpCallPathLength(sink: SystemsFindingSink): int {
    finding := ScpAt(sink, 0)
    path := finding.CallPath
    return path.Count
}

func ScpCallPathAt(sink: SystemsFindingSink, index: int): string {
    finding := ScpAt(sink, 0)
    path := finding.CallPath
    return path[index]
}

// An effect record with every bit clear; each contract turns on exactly the bits it is about.
func ScpNoEffects(): SystemsEffectFacts {
    return new SystemsEffectFacts(false, false, false, false, false, false, false, false, false, false, false, false, false, false, true)
}

func ScpEffects(allocates: bool, boxes: bool, constructsDelegate: bool, capturesClosure: bool, usesRuntimeDispatch: bool, usesReflection: bool, usesDynamicCode: bool, hasImplicitTrap: bool, usesUnknownExternalCall: bool, usesResource: bool, usesPool: bool, requiresWarmup: bool): SystemsEffectFacts {
    aotSafe := !usesDynamicCode && !usesReflection
    return new SystemsEffectFacts(allocates, boxes, constructsDelegate, capturesClosure, usesRuntimeDispatch, usesReflection, usesDynamicCode, false, hasImplicitTrap, usesUnknownExternalCall, usesResource, usesPool, false, requiresWarmup, aotSafe)
}

func ScpAllocatingCallee(): SystemsEffectFacts {
    return ScpEffects(true, false, false, false, false, false, false, false, false, false, false, false)
}

func ScpPoolCallee(): SystemsEffectFacts {
    return ScpEffects(false, false, false, false, false, false, false, false, false, false, true, false)
}

// One resolved callee reported against one caller, under the caller's own promise.
func ScpReport(policy: SystemsCalleePolicy, callee: SystemsEffectFacts, allowsAlloc: bool, allowsPool: bool, callerIsHot: bool, callerIsBoundary: bool, callerAllocNone: bool) {
    policy.ReportCalleePolicyViolations(callee, "Codec.Encode", allowsAlloc, allowsPool, 61, 17, 6, "caller.nl", "Pipeline.Run", callerIsHot, callerIsBoundary, callerAllocNone)
}

func ScpResultType(): TypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("int", 1, 1))
    arguments.Add(new SimpleTypeReference("string", 1, 1))
    return new GenericTypeReference("Result", arguments, 1, 1)
}

func ScpOptionType(): TypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("int", 1, 1))
    return new GenericTypeReference("Option", arguments, 1, 1)
}

func ScpCheckIgnored(policy: SystemsCalleePolicy, returnType: TypeReference?, isHot: bool, isBoundary: bool) {
    policy.CheckIgnoredResult(returnType, "Reader.Next", "Next", 30, 5, "reader.nl", "Pipeline.Run", isHot, isBoundary)
}

test "AN UNRESOLVED CALL IN A HOT FUNCTION IS AN ERROR AND NAMES THE HOT PROMISE" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "hot.nl", "Pipeline.Run", true, false)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS050"
    assert ScpEffect(sink) == "unknownExternalCall"
    assert ScpSeverity(sink) == "error"
    assert ScpMessage(sink) == "unknown external call 'Vendor.Encode' is not callable from [hot]"
    assert ScpSuggestion(sink) == "Add a compiler/HotSummary entry, make the callee [hot], or move this call behind a [boundary]."
    assert ScpPolicyLabel(sink) == "[hot]"
}

test "A HOT BOUNDARY GETS THE HOT ARM: THE THREE ARMS ARE A PRECEDENCE" {
    // Both promises are made; the stricter one answers, and the boundary sentence is never composed.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "hot.nl", "Pipeline.Run", true, true)
    assert ScpCount(sink) == 1
    assert ScpMessage(sink) == "unknown external call 'Vendor.Encode' is not callable from [hot]"
    assert ScpSeverity(sink) == "error"
}

test "A BOUNDARY CALL IS A WARNING FOR REVIEW AND SAYS SO IN ITS OWN SENTENCE" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "error")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "edge.nl", "Pipeline.Edge", false, true)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "warning"
    assert ScpMessage(sink) == "boundary external call 'Vendor.Encode' reported for systems handoff review"
    assert ScpSuggestion(sink) == "Keep unknown external work inside the [boundary] and expose a systems-safe result."
}

test "A COLD FUNCTION IN A DEFAULT PROJECT IS SILENT EVEN WHEN THE SETTING SAYS ERROR" {
    // The profile gate comes before the setting; a non-systems project never hears this rule.
    sink := ScpSink("default", "strict")
    policy := ScpPolicy(sink, "default", "strict", "error")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "plain.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 0
}

test "A COLD FUNCTION IN A SYSTEMS PROJECT WARNS BY DEFAULT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "cold.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "warning"
    assert ScpMessage(sink) == "unknown external call 'Vendor.Encode' has no systems summary"
    assert ScpSuggestion(sink) == "Add a sidecar HotSummary or put the call in a [boundary]."
    assert ScpPolicyLabel(sink) == "systems:strict"
}

test "THE SETTING ERROR MAKES THE COLD SYSTEMS ARM AN ERROR" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "error")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "cold.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "error"
}

test "THE SETTING ALLOW SILENCES THE COLD SYSTEMS ARM AND ONLY THAT ARM" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "allow")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "cold.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 0
    policy.ReportUnknownExternalCall("Vendor.Encode", 13, 9, "cold.nl", "Pipeline.Run", true, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "error"
}

test "AN UNRECOGNISED SETTING WARNS RATHER THAN THROWING" {
    // ProjectFileParser rejects a fourth value, but an analyzer can be built from a config that never
    // went through it, and such a project must still be told something.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "shout")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "cold.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "warning"
}

test "A POLICY THAT NEVER SAW A CONFIG WARNS" {
    sink := ScpSink("systems", "strict")
    policy := new SystemsCalleePolicy(new SystemsTypePolicy(), sink)
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "cold.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "warning"
}

test "THE SETTING IS READ ONCE PER ANALYSIS AND NOT AT THE CALL" {
    sink := ScpSink("systems", "strict")
    config := ScpConfig("systems", "strict", "error")
    policy := new SystemsCalleePolicy(new SystemsTypePolicy(), sink)
    policy.BeginAnalysis(config)
    systems := config.Language.Systems
    systems.UnknownExternalCalls = "allow"
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "cold.nl", "Pipeline.Run", false, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "error"
}

test "THE UNDERLINE IS THE TARGET'S SIMPLE NAME, NOT ITS QUALIFIED TEXT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    policy.ReportUnknownExternalCall("Console.WriteLine", 7, 9, "hot.nl", "Pipeline.Run", true, false)
    assert ScpLength(sink) == 9
    assert ScpLine(sink) == 7
    assert ScpColumn(sink) == 9
    assert ScpFunctionName(sink) == "Pipeline.Run"
}

test "AN UNRESOLVED CALL NAMES ONE FUNCTION IN ITS CALL PATH" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    policy.ReportUnknownExternalCall("Vendor.Encode", 12, 9, "hot.nl", "Pipeline.Run", true, false)
    assert ScpCallPathLength(sink) == 1
    assert ScpCallPathAt(sink, 0) == "Pipeline.Run"
}

test "A COLD PLAIN CALLER IS NOT TOLD WHAT ITS CALLEES COST" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, false, false, false)
    assert ScpCount(sink) == 0
}

test "A BOUNDARY ALONE DOES NOT OPEN THE CALLEE GATE" {
    // The opposite of the unresolved-call rule, where a boundary is exactly what reports.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, false, true, false)
    assert ScpCount(sink) == 0
}

test "AN ALLOC NONE CALLER IS ASKED EVEN THOUGH IT IS NOT HOT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, false, false, true)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS010"
    assert ScpMessage(sink) == "callee 'Codec.Encode' allocates on a hot/alloc(none) path"
}

test "A CALLEE FINDING REPORTS AT THE CALL AND WEARS THE CALLER'S SUBJECT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, true, false, false)
    assert ScpCount(sink) == 1
    assert ScpLine(sink) == 61
    assert ScpColumn(sink) == 17
    assert ScpLength(sink) == 6
    assert ScpFunctionName(sink) == "Pipeline.Run"
    assert ScpPolicyLabel(sink) == "[hot]"
}

test "A CALLEE FINDING NAMES THE CALLER AND THEN THE CALLEE" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, true, false, false)
    assert ScpCallPathLength(sink) == 2
    assert ScpCallPathAt(sink, 0) == "Pipeline.Run"
    assert ScpCallPathAt(sink, 1) == "Codec.Encode"
}

test "A FUNCTION LEVEL ALLOW ALLOC SILENCES THE ALLOCATION ARM" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), true, false, true, false, false)
    assert ScpCount(sink) == 0
}

test "A FUNCTION LEVEL ALLOW POOL SILENCES THE POOL ARM" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpPoolCallee(), false, true, true, false, false)
    assert ScpCount(sink) == 0
}

test "AN ALLOW ALLOC DOES NOT SILENCE THE POOL ARM" {
    // Exactly two of the ten arms are waivable and each answers to its own effect.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpPoolCallee(), true, false, true, false, false)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS130"
}

test "AN ALLOW SILENCES NEITHER OF THE OTHER EIGHT ARMS" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpEffects(false, true, false, false, false, false, false, false, false, false, false, false), true, true, true, false, false)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS020"
}

test "EACH OF THE TEN ARMS REPORTS UNDER ITS OWN CODE AND SENTENCE" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpEffects(true, true, true, true, true, true, true, true, true, true, true, true), false, false, true, false, false)
    assert ScpCount(sink) == 10
    assert ScpCodeAt(sink, 0) == "NSYS010"
    assert ScpCodeAt(sink, 1) == "NSYS020"
    assert ScpCodeAt(sink, 2) == "NSYS030"
    assert ScpCodeAt(sink, 3) == "NSYS040"
    assert ScpCodeAt(sink, 4) == "NSYS050"
    assert ScpCodeAt(sink, 5) == "NSYS060"
    assert ScpCodeAt(sink, 6) == "NSYS120"
    assert ScpCodeAt(sink, 7) == "NSYS090"
    assert ScpCodeAt(sink, 8) == "NSYS130"
    assert ScpCodeAt(sink, 9) == "NSYS110"
    assert ScpMessageAt(sink, 1) == "callee 'Codec.Encode' boxes a value on a hot path"
    assert ScpMessageAt(sink, 2) == "callee 'Codec.Encode' constructs a delegate or closure on a hot path"
    assert ScpMessageAt(sink, 3) == "callee 'Codec.Encode' uses runtime dispatch on a hot path"
    assert ScpMessageAt(sink, 4) == "callee 'Codec.Encode' reaches an unknown external call"
    assert ScpMessageAt(sink, 5) == "callee 'Codec.Encode' blocks AOT/trimming facts"
    assert ScpMessageAt(sink, 6) == "callee 'Codec.Encode' has unproven implicit trap obligations"
    assert ScpMessageAt(sink, 7) == "callee 'Codec.Encode' creates or owns a disposable resource"
    assert ScpMessageAt(sink, 8) == "callee 'Codec.Encode' rents from a pool without a hot-ready pool precondition"
    assert ScpMessageAt(sink, 9) == "callee 'Codec.Encode' requires warmup before the hot path is warm-ready"
}

test "A CLOSURE ALONE REPORTS THE DELEGATE ARM" {
    // The delegate arm is a disjunction; either bit is enough and neither doubles the finding.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpEffects(false, false, false, true, false, false, false, false, false, false, false, false), false, false, true, false, false)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS030"
}

test "DYNAMIC CODE ALONE REPORTS THE AOT ARM" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpEffects(false, false, false, false, false, false, true, false, false, false, false, false), false, false, true, false, false)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS060"
}

test "A CALLEE THAT ONLY THROWS COSTS ITS CALLER NOTHING HERE" {
    // Three of the fifteen effect fields are carried and not read: Throws, ConcurrencyPrimitive and
    // AotSafe. The AOT arm reads the two bits behind AotSafe, not the verdict.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, new SystemsEffectFacts(false, false, false, false, false, false, false, true, false, false, false, false, true, false, false), false, false, true, false, false)
    assert ScpCount(sink) == 0
}

test "EVERY CALLEE ARM PREFERS ERROR AND THE BOUNDARY DOWNGRADE IS THE SINK'S" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, false, true, true)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "warning"
    assert ScpPolicyLabel(sink) == "systems:strict"
}

test "AUDIT MODE DOWNGRADES A CALLEE FINDING AND AN UNRESOLVED CALL ALIKE" {
    sink := ScpSink("systems", "audit")
    policy := ScpPolicy(sink, "systems", "audit", "warn")
    ScpReport(policy, ScpAllocatingCallee(), false, false, true, false, false)
    policy.ReportUnknownExternalCall("Vendor.Encode", 62, 9, "caller.nl", "Pipeline.Run", true, false)
    assert ScpCount(sink) == 2
    assert ScpSeverity(sink) == "warning"
    assert ScpPolicyLabel(sink) == "[hot]"
}

test "A DISCARDED RESULT IS A WARNING IN A COLD DEFAULT PROJECT" {
    sink := ScpSink("default", "strict")
    policy := ScpPolicy(sink, "default", "strict", "warn")
    ScpCheckIgnored(policy, ScpResultType(), false, false)
    assert ScpCount(sink) == 1
    assert ScpCode(sink) == "NSYS160"
    assert ScpEffect(sink) == "resultMustUse"
    assert ScpSeverity(sink) == "warning"
    assert ScpMessage(sink) == "Result returned by 'Reader.Next' is ignored"
    assert ScpSuggestion(sink) == "Bind the Result, return it, or explicitly inspect IsOk/IsErr so the error path is handled."
    assert ScpPolicyLabel(sink) == "local"
}

test "A DISCARDED RESULT IS AN ERROR IN A HOT FUNCTION" {
    sink := ScpSink("default", "strict")
    policy := ScpPolicy(sink, "default", "strict", "warn")
    ScpCheckIgnored(policy, ScpResultType(), true, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "error"
}

test "A DISCARDED RESULT IS AN ERROR IN A SYSTEMS PROJECT EVEN WHEN COLD" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpCheckIgnored(policy, ScpResultType(), false, false)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "error"
}

test "THE DISCARDED RESULT FINDING NAMES THE CALLEE QUALIFIED AND UNDERLINES IT SIMPLE" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpCheckIgnored(policy, ScpResultType(), false, false)
    assert ScpLine(sink) == 30
    assert ScpColumn(sink) == 5
    assert ScpLength(sink) == 4
    assert ScpFunctionName(sink) == "Pipeline.Run"
    assert ScpCallPathLength(sink) == 1
    assert ScpCallPathAt(sink, 0) == "Pipeline.Run"
}

test "A CALLEE WITH NO WRITTEN RETURN TYPE IS SILENT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpCheckIgnored(policy, null, true, false)
    assert ScpCount(sink) == 0
}

test "A DISCARDED NON RESULT GENERIC IS SILENT" {
    // The arity-two Result guard is the rule, and a one-argument generic is not it.
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpCheckIgnored(policy, ScpOptionType(), true, false)
    assert ScpCount(sink) == 0
}

test "A DISCARDED PLAIN TYPE IS SILENT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpCheckIgnored(policy, new SimpleTypeReference("int", 1, 1), true, false)
    assert ScpCount(sink) == 0
}

test "A BOUNDARY DOWNGRADES A DISCARDED RESULT THAT IS NOT HOT" {
    sink := ScpSink("systems", "strict")
    policy := ScpPolicy(sink, "systems", "strict", "warn")
    ScpCheckIgnored(policy, ScpResultType(), false, true)
    assert ScpCount(sink) == 1
    assert ScpSeverity(sink) == "warning"
}

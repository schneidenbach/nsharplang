namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler

// Native contracts for WHAT A FUNCTION STILL OWES WHEN IT ENDS.
//
// These two rules were 38 lines inside `SystemsAnalyzer.cs` — `CheckPoolBalance` (19) and
// `CheckResourceBalance` (19) — each reached from exactly one site at the end of the function walk.
// Both of their codes, NSYS090 and NSYS130, are corpus-silent, so these contracts and the
// purpose-built fixtures are the direct pinning.
//
// SEVEN THINGS THIS PAIR IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE GATE IS HOT **OR** THE SYSTEMS PROFILE — not `[boundary]`. A cold function in a
// default-profile project may leak a rental and hear nothing; the same function in a systems project
// is asked.
//
// (2) THE TWO RULES PREFER DIFFERENT SEVERITIES. A pool rental prefers Error in hot and Warning
// outside it; a resource prefers Error EVERYWHERE, hot or not.
//
// (3) A DISCHARGED OBLIGATION IS SILENT, AND DISCHARGE IS A FLAG ON THE LEDGER ENTRY the call policy
// sets during the walk. These rules never re-derive it.
//
// (4) THE FINDING IS REPORTED WHERE THE OBLIGATION WAS OPENED, not where the function ends, and it
// underlines the VARIABLE's name.
//
// (5) THE RESOURCE SENTENCE NAMES THE KIND the ledger recorded, so two resources opened differently
// read differently.
//
// (6) BOTH RULES REPORT EVERY OUTSTANDING ENTRY, in ledger order — not the first one.
//
// (7) THE SINK STILL DOWNGRADES ON TOP. A `[boundary]` that is not hot turns the resource rule's
// flat Error into a warning, and audit mode turns everything into one; neither changes what the rule
// preferred.
func SbpConfig(profile: string, mode: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("balance-policy-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    return config
}

func SbpSink(profile: string, mode: string): SystemsFindingSink {
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(SbpConfig(profile, mode))
    return sink
}

func SbpPolicy(sink: SystemsFindingSink): SystemsBalancePolicy {
    return new SystemsBalancePolicy(sink)
}

func SbpRents(): Dictionary<string, PoolRent> {
    return new Dictionary<string, PoolRent>()
}

func SbpRent(rents: Dictionary<string, PoolRent>, name: string, line: int, column: int, returned: bool) {
    rent := new PoolRent(name, line, column)
    rent.Returned = returned
    rents[name] = rent
}

func SbpResources(): Dictionary<string, ResourceLocal> {
    return new Dictionary<string, ResourceLocal>()
}

func SbpResource(resources: Dictionary<string, ResourceLocal>, name: string, kind: string, line: int, column: int, disposed: bool) {
    resource := new ResourceLocal(name, kind, line, column)
    resource.Disposed = disposed
    resources[name] = resource
}

// Field readers, one per field a contract asserts on: a property read chained onto a call result does
// not emit.
func SbpCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

func SbpAt(sink: SystemsFindingSink, index: int): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[index]
}

func SbpCode(sink: SystemsFindingSink): string {
    finding := SbpAt(sink, 0)
    return finding.Code
}

func SbpEffect(sink: SystemsFindingSink): string {
    finding := SbpAt(sink, 0)
    return finding.Effect
}

func SbpSeverity(sink: SystemsFindingSink): string {
    finding := SbpAt(sink, 0)
    return finding.Severity
}

func SbpMessage(sink: SystemsFindingSink): string {
    finding := SbpAt(sink, 0)
    return finding.Message
}

func SbpMessageAt(sink: SystemsFindingSink, index: int): string {
    finding := SbpAt(sink, index)
    return finding.Message
}

func SbpLine(sink: SystemsFindingSink): int {
    finding := SbpAt(sink, 0)
    return finding.Line
}

func SbpColumn(sink: SystemsFindingSink): int {
    finding := SbpAt(sink, 0)
    return finding.Column
}

func SbpLength(sink: SystemsFindingSink): int {
    finding := SbpAt(sink, 0)
    return finding.Length
}

func SbpFunctionName(sink: SystemsFindingSink): string? {
    finding := SbpAt(sink, 0)
    return finding.Function
}

func SbpPolicyLabel(sink: SystemsFindingSink): string? {
    finding := SbpAt(sink, 0)
    return finding.Policy
}

// One outstanding rental, checked under the hotness and boundary-ness the caller states.
func SbpCheckOpenRent(sink: SystemsFindingSink, isHot: bool, isBoundary: bool) {
    rents := SbpRents()
    SbpRent(rents, "scratch", 41, 13, false)
    policy := SbpPolicy(sink)
    policy.CheckPoolBalance(rents, "pool.nl", "Buf.Fill", isHot, isBoundary)
}

func SbpCheckOpenResource(sink: SystemsFindingSink, isHot: bool, isBoundary: bool) {
    resources := SbpResources()
    SbpResource(resources, "handle", "File.OpenRead", 44, 9, false)
    policy := SbpPolicy(sink)
    policy.CheckResourceBalance(resources, "res.nl", "Buf.Load", isHot, isBoundary)
}

test "A COLD FUNCTION IN A DEFAULT PROJECT IS NOT ASKED ABOUT ITS OBLIGATIONS" {
    sink := SbpSink("default", "strict")
    SbpCheckOpenRent(sink, false, false)
    assert SbpCount(sink) == 0
}

test "A COLD FUNCTION IN A SYSTEMS PROJECT IS ASKED" {
    sink := SbpSink("systems", "strict")
    SbpCheckOpenRent(sink, false, false)
    assert SbpCount(sink) == 1
}

test "A HOT FUNCTION IN A DEFAULT PROJECT IS ASKED" {
    // Hotness alone opens the gate: the profile is the other half of an OR, not a precondition.
    sink := SbpSink("default", "strict")
    SbpCheckOpenRent(sink, true, false)
    assert SbpCount(sink) == 1
}

test "A BOUNDARY DOES NOT OPEN THE GATE BY ITSELF" {
    sink := SbpSink("default", "strict")
    SbpCheckOpenRent(sink, false, true)
    assert SbpCount(sink) == 0
}

test "AN UNRETURNED RENTAL IS AN ERROR IN A HOT FUNCTION" {
    sink := SbpSink("systems", "strict")
    SbpCheckOpenRent(sink, true, false)
    assert SbpCode(sink) == "NSYS130"
    assert SbpEffect(sink) == "pool"
    assert SbpSeverity(sink) == "error"
    assert SbpMessage(sink) == "pooled buffer 'scratch' rented here is not returned on an obvious lexical path"
}

test "AN UNRETURNED RENTAL IS ONLY A WARNING OUTSIDE A HOT FUNCTION" {
    sink := SbpSink("systems", "strict")
    SbpCheckOpenRent(sink, false, false)
    assert SbpSeverity(sink) == "warning"
}

test "THE RENTAL FINDING IS REPORTED WHERE THE RENTAL WAS OPENED AND UNDERLINES THE VARIABLE" {
    sink := SbpSink("systems", "strict")
    SbpCheckOpenRent(sink, true, false)
    assert SbpLine(sink) == 41
    assert SbpColumn(sink) == 13
    assert SbpLength(sink) == 7
    assert SbpFunctionName(sink) == "Buf.Fill"
}

test "A RETURNED RENTAL IS SILENT" {
    sink := SbpSink("systems", "strict")
    rents := SbpRents()
    SbpRent(rents, "scratch", 41, 13, true)
    policy := SbpPolicy(sink)
    policy.CheckPoolBalance(rents, "pool.nl", "Buf.Fill", true, false)
    assert SbpCount(sink) == 0
}

test "AN EMPTY LEDGER IS SILENT EVEN IN A HOT FUNCTION" {
    sink := SbpSink("systems", "strict")
    policy := SbpPolicy(sink)
    policy.CheckPoolBalance(SbpRents(), "pool.nl", "Buf.Fill", true, false)
    assert SbpCount(sink) == 0
}

test "EVERY OUTSTANDING RENTAL REPORTS, IN LEDGER ORDER, AND THE DISCHARGED ONE IS SKIPPED" {
    sink := SbpSink("systems", "strict")
    rents := SbpRents()
    SbpRent(rents, "first", 41, 13, false)
    SbpRent(rents, "settled", 42, 13, true)
    SbpRent(rents, "second", 43, 13, false)
    policy := SbpPolicy(sink)
    policy.CheckPoolBalance(rents, "pool.nl", "Buf.Fill", true, false)
    assert SbpCount(sink) == 2
    assert SbpMessageAt(sink, 0) == "pooled buffer 'first' rented here is not returned on an obvious lexical path"
    assert SbpMessageAt(sink, 1) == "pooled buffer 'second' rented here is not returned on an obvious lexical path"
}

test "AN UNDISPOSED RESOURCE IS AN ERROR EVEN OUTSIDE A HOT FUNCTION" {
    // The disagreement with the pool rule: a leaked handle is a correctness bug at any temperature.
    sink := SbpSink("systems", "strict")
    SbpCheckOpenResource(sink, false, false)
    assert SbpCount(sink) == 1
    assert SbpCode(sink) == "NSYS090"
    assert SbpEffect(sink) == "resource"
    assert SbpSeverity(sink) == "error"
}

test "THE RESOURCE SENTENCE NAMES THE KIND THE LEDGER RECORDED" {
    sink := SbpSink("systems", "strict")
    SbpCheckOpenResource(sink, true, false)
    assert SbpMessage(sink) == "disposable resource 'handle' created as File.OpenRead is not disposed on an obvious lexical path"
    assert SbpLine(sink) == 44
    assert SbpColumn(sink) == 9
    assert SbpLength(sink) == 6
}

test "A DISPOSED RESOURCE IS SILENT" {
    sink := SbpSink("systems", "strict")
    resources := SbpResources()
    SbpResource(resources, "handle", "File.OpenRead", 44, 9, true)
    policy := SbpPolicy(sink)
    policy.CheckResourceBalance(resources, "res.nl", "Buf.Load", true, false)
    assert SbpCount(sink) == 0
}

test "EVERY OUTSTANDING RESOURCE REPORTS AND EACH NAMES ITS OWN KIND" {
    sink := SbpSink("systems", "strict")
    resources := SbpResources()
    SbpResource(resources, "reader", "File.OpenRead", 44, 9, false)
    SbpResource(resources, "writer", "new StreamWriter", 45, 9, false)
    policy := SbpPolicy(sink)
    policy.CheckResourceBalance(resources, "res.nl", "Buf.Load", true, false)
    assert SbpCount(sink) == 2
    assert SbpMessageAt(sink, 0) == "disposable resource 'reader' created as File.OpenRead is not disposed on an obvious lexical path"
    assert SbpMessageAt(sink, 1) == "disposable resource 'writer' created as new StreamWriter is not disposed on an obvious lexical path"
}

test "A BOUNDARY THAT IS NOT HOT HAS THE RESOURCE ERROR DOWNGRADED BY THE SINK" {
    // The rule still prefers Error; the sink is what a reader sees.
    sink := SbpSink("systems", "strict")
    SbpCheckOpenResource(sink, false, true)
    assert SbpCount(sink) == 1
    assert SbpSeverity(sink) == "warning"
    assert SbpPolicyLabel(sink) == "systems:strict"
}

test "AUDIT MODE DOWNGRADES BOTH RULES" {
    sink := SbpSink("systems", "audit")
    SbpCheckOpenRent(sink, true, false)
    SbpCheckOpenResource(sink, true, false)
    assert SbpCount(sink) == 2
    assert SbpSeverity(sink) == "warning"
    assert SbpPolicyLabel(sink) == "[hot]"
}

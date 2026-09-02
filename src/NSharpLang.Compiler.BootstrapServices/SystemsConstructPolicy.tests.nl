namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A CONSTRUCT COSTS BY BEING WRITTEN.
//
// These thirteen reporting arms were arms INSIDE `SystemsAnalyzer.cs`'s statement and expression
// walks — not members, which is why the seventeen-family inventory never named them — and they carry
// six of the eleven codes F18 moved: NSYS010, NSYS020, NSYS030, NSYS060, NSYS090 and NSYS120. Four
// of the six are corpus-silent, so these contracts and the purpose-built fixtures are the direct
// pinning.
//
// EIGHT THINGS THIS FAMILY IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) FOUR ARMS ARE `[hot]`-ONLY AND FOUR ARE POLICY ARMS, AND THE SPLIT IS NOT A SEVERITY CHOICE. A
// cold systems function hears NOTHING from `yield`, `await`, `await foreach` or `using` — not a
// warning — and hears the policy sentence from `throw`, `try`, a lambda, a cast and `typeof`.
//
// (2) THE HOT ARM OF `throw`/`try` IS A DIFFERENT SENTENCE, NOT A LOUDER ONE. It goes through the
// hot-only door, which no `allow(throw)` waives. Folding the fork would make `allow(throw)` legal
// inside `[hot]`.
//
// (3) `throw` AS A STATEMENT AND AS AN EXPRESSION ARE ONE RULE. The original wrote the same code,
// effect, two sentences and fix at both sites; one door serves both and the contracts assert the
// sentences rather than the site.
//
// (4) `try`'s COLD SENTENCE IS DELIBERATELY NOT `throw`'s. "reported on systems paths" against "must
// translate", with different fixes; they share a code and an effect and nothing else.
//
// (5) THE CAST RULE ANSWERS ABOUT THE TARGET TYPE, NOT ABOUT THE FINDING. It returns TRUE for a
// waived or downgraded cast too, because the boxing HAPPENED and the caller inherits it.
//
// (6) BOTH SPELLINGS OF THE TARGET ANSWER — `object` and `System.Object` — and nothing else does,
// including `Object` with a capital and `object[]`.
//
// (7) EVERY POLICY ARM READS ITS OWN EFFECT NAME OFF THE ALLOW STACK. `allow(boxing)` silences the
// cast and leaves the lambda alone; getting one effect name wrong silences the wrong rule.
//
// (8) A `[boundary]` DOWNGRADES A POLICY ARM AND SILENCES NOTHING, while it leaves a hot-only arm
// exactly as loud as it was, because that arm never consulted the boundary in the first place.
func SxpConfig(profile: string, mode: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("construct-policy-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    return config
}

func SxpSink(profile: string, mode: string): SystemsFindingSink {
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(SxpConfig(profile, mode))
    return sink
}

func SxpSystemsSink(): SystemsFindingSink {
    return SxpSink("systems", "strict")
}

func SxpNoAllows(): SystemsAllowStack {
    return new SystemsAllowStack(new HashSet<string>(StringComparer.OrdinalIgnoreCase))
}

func SxpAllowing(effect: string): SystemsAllowStack {
    effects := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    effects.Add(effect)
    return new SystemsAllowStack(effects)
}

func SxpSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

// Field readers, one per field a contract asserts on: a property read chained onto a call result does
// not emit.
func SxpCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

func SxpAt(sink: SystemsFindingSink, index: int): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[index]
}

func SxpCode(sink: SystemsFindingSink, index: int): string {
    finding := SxpAt(sink, index)
    return finding.Code
}

func SxpEffectName(sink: SystemsFindingSink, index: int): string {
    finding := SxpAt(sink, index)
    return finding.Effect
}

func SxpSeverity(sink: SystemsFindingSink, index: int): string {
    finding := SxpAt(sink, index)
    return finding.Severity
}

func SxpMessage(sink: SystemsFindingSink, index: int): string {
    finding := SxpAt(sink, index)
    return finding.Message
}

func SxpSuggestion(sink: SystemsFindingSink, index: int): string? {
    finding := SxpAt(sink, index)
    return finding.Suggestion
}

func SxpLength(sink: SystemsFindingSink, index: int): int {
    finding := SxpAt(sink, index)
    return finding.Length
}

func SxpLine(sink: SystemsFindingSink, index: int): int {
    finding := SxpAt(sink, index)
    return finding.Line
}

func SxpColumn(sink: SystemsFindingSink, index: int): int {
    finding := SxpAt(sink, index)
    return finding.Column
}

test "THE FOUR HOT-ONLY ARMS SAY NOTHING AT ALL IN A COLD SYSTEMS FUNCTION" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportYield(3, 5, "a.nl", "cold", false, false)
    policy.ReportAwait(3, 5, "a.nl", "cold", false, false)
    policy.ReportAwaitForEach(3, 5, "a.nl", "cold", false, false)
    policy.ReportUsing(3, 5, "a.nl", "cold", false, false)
    assert SxpCount(sink) == 0
}

test "A [boundary] DOES NOT MAKE A HOT-ONLY ARM SPEAK EITHER" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportYield(3, 5, "a.nl", "edge", false, true)
    policy.ReportUsing(3, 5, "a.nl", "edge", false, true)
    assert SxpCount(sink) == 0
}

test "THE FOUR HOT-ONLY ARMS FIRE IN [hot] WITH THEIR OWN CODES, EFFECTS AND SENTENCES" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportYield(1, 1, "a.nl", "hot", true, false)
    policy.ReportAwait(2, 1, "a.nl", "hot", true, false)
    policy.ReportAwaitForEach(3, 1, "a.nl", "hot", true, false)
    policy.ReportUsing(4, 1, "a.nl", "hot", true, false)
    assert SxpCount(sink) == 4
    assert SxpCode(sink, 0) == "NSYS010"
    assert SxpEffectName(sink, 0) == "allocation"
    assert SxpMessage(sink, 0) == "[hot] cannot allocate iterator state machines"
    assert SxpCode(sink, 1) == "NSYS090"
    assert SxpEffectName(sink, 1) == "resource"
    assert SxpMessage(sink, 1) == "[hot] async work is deferred in Systems N# v1"
    assert SxpCode(sink, 2) == "NSYS090"
    assert SxpMessage(sink, 2) == "[hot] cannot be an async iterator or await foreach boundary"
    assert SxpCode(sink, 3) == "NSYS090"
    assert SxpMessage(sink, 3) == "[hot] cannot create or open disposable resources"
}

test "A HOT-ONLY ARM UNDERLINES ONE COLUMN, CARRIES NO FIX, AND IS AN ERROR" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportYield(7, 9, "a.nl", "hot", true, false)
    assert SxpLength(sink, 0) == 1
    assert SxpLine(sink, 0) == 7
    assert SxpColumn(sink, 0) == 9
    assert SxpSeverity(sink, 0) == "error"
    assert SxpSuggestion(sink, 0) == null
}

test "THE [hot] THROW SENTENCE IS A REFUSAL AND NO allow(throw) WAIVES IT" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportThrow(SxpAllowing("throw"), 2, 2, "a.nl", "hot", true, false)
    assert SxpCount(sink) == 1
    assert SxpCode(sink, 0) == "NSYS120"
    assert SxpEffectName(sink, 0) == "throw"
    assert SxpMessage(sink, 0) == "[hot] cannot throw exceptions"
    assert SxpSuggestion(sink, 0) == null
}

test "THE COLD THROW SENTENCE IS THE POLICY ONE AND allow(throw) SILENCES IT" {
    loud := SxpSystemsSink()
    policyLoud := new SystemsConstructPolicy(loud)
    policyLoud.ReportThrow(SxpNoAllows(), 2, 2, "a.nl", "cold", false, false)
    assert SxpCount(loud) == 1
    assert SxpMessage(loud, 0) == "systems code must translate exception control flow into explicit Result/error values"
    assert SxpSuggestion(loud, 0) == "Catch exceptions at a [boundary] and return Result<T,E> or another explicit error value."
    quiet := SxpSystemsSink()
    policyQuiet := new SystemsConstructPolicy(quiet)
    policyQuiet.ReportThrow(SxpAllowing("throw"), 2, 2, "a.nl", "cold", false, false)
    assert SxpCount(quiet) == 0
}

test "THE THROW ARM AND THE TRY ARM SHARE A CODE AND AN EFFECT AND DISAGREE ON EVERY SENTENCE" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportThrow(SxpNoAllows(), 1, 1, "a.nl", "cold", false, false)
    policy.ReportTry(SxpNoAllows(), 2, 1, "a.nl", "cold", false, false)
    assert SxpCode(sink, 0) == SxpCode(sink, 1)
    assert SxpEffectName(sink, 0) == SxpEffectName(sink, 1)
    assert SxpMessage(sink, 1) == "exception control flow is reported on systems paths"
    assert SxpMessage(sink, 0) != SxpMessage(sink, 1)
    assert SxpSuggestion(sink, 1) == "Keep try/catch inside a [boundary] and translate failures into explicit Result/error values."
    assert SxpSuggestion(sink, 0) != SxpSuggestion(sink, 1)
}

test "THE [hot] TRY SENTENCE IS ITS OWN AND IS NOT THE THROW ONE" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportTry(SxpAllowing("throw"), 1, 1, "a.nl", "hot", true, false)
    assert SxpCount(sink) == 1
    assert SxpMessage(sink, 0) == "[hot] cannot use exception control flow"
}

test "A [boundary] DOWNGRADES A POLICY ARM RATHER THAN SILENCING IT" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportTry(SxpNoAllows(), 1, 1, "a.nl", "edge", false, true)
    assert SxpCount(sink) == 1
    assert SxpSeverity(sink, 0) == "warning"
}

test "A DEFAULT-PROFILE COLD FUNCTION HEARS NO POLICY ARM AT ALL" {
    sink := SxpSink("default", "strict")
    policy := new SystemsConstructPolicy(sink)
    policy.ReportTry(SxpNoAllows(), 1, 1, "a.nl", "cold", false, false)
    policy.ReportLambda(SxpNoAllows(), 2, 1, "a.nl", "cold", false, false)
    policy.ReportTypeOf(SxpNoAllows(), 3, 1, "a.nl", "cold", false, false)
    assert SxpCount(sink) == 0
}

test "THE LAMBDA ARM IS THE DELEGATE EFFECT AND allow(delegate) SILENCES IT" {
    loud := SxpSystemsSink()
    policyLoud := new SystemsConstructPolicy(loud)
    policyLoud.ReportLambda(SxpNoAllows(), 4, 6, "a.nl", "cold", false, false)
    assert SxpCount(loud) == 1
    assert SxpCode(loud, 0) == "NSYS030"
    assert SxpEffectName(loud, 0) == "delegate"
    assert SxpMessage(loud, 0) == "delegate or closure construction is not allowed here"
    assert SxpSuggestion(loud, 0) == "Move delegate construction behind a [boundary] or use a direct call."
    quiet := SxpSystemsSink()
    policyQuiet := new SystemsConstructPolicy(quiet)
    policyQuiet.ReportLambda(SxpAllowing("delegate"), 4, 6, "a.nl", "cold", false, false)
    assert SxpCount(quiet) == 0
}

test "THE TYPEOF ARM WEARS THE aot EFFECT, WHICH IS WHAT THE AOT VERDICT READS" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportTypeOf(SxpNoAllows(), 1, 1, "a.nl", "cold", false, false)
    assert SxpCode(sink, 0) == "NSYS060"
    assert SxpEffectName(sink, 0) == "aot"
    assert SxpMessage(sink, 0) == "typeof requires metadata and may block trimming/AOT facts"
    assert SxpSuggestion(sink, 0) == "Move reflection to a [boundary] or add an audited target-qualified summary."
    assert sink.AotAnalysis() == "fail"
}

test "A DOWNGRADED TYPEOF DOES NOT FAIL THE AOT VERDICT" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportTypeOf(SxpNoAllows(), 1, 1, "a.nl", "edge", false, true)
    assert SxpCount(sink) == 1
    assert SxpSeverity(sink, 0) == "warning"
    assert sink.AotAnalysis() == "pass"
}

test "allow(aot) SILENCES THE TYPEOF ARM AND allow(boxing) DOES NOT" {
    quiet := SxpSystemsSink()
    policyQuiet := new SystemsConstructPolicy(quiet)
    policyQuiet.ReportTypeOf(SxpAllowing("aot"), 1, 1, "a.nl", "cold", false, false)
    assert SxpCount(quiet) == 0
    loud := SxpSystemsSink()
    policyLoud := new SystemsConstructPolicy(loud)
    policyLoud.ReportTypeOf(SxpAllowing("boxing"), 1, 1, "a.nl", "cold", false, false)
    assert SxpCount(loud) == 1
}

test "BOTH SPELLINGS OF THE CAST TARGET BOX AND NOTHING ELSE DOES" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    assert policy.ReportCastToObject(SxpSimple("object"), SxpNoAllows(), 1, 1, "a.nl", "cold", false, false)
    assert policy.ReportCastToObject(SxpSimple("System.Object"), SxpNoAllows(), 2, 1, "a.nl", "cold", false, false)
    assert !policy.ReportCastToObject(SxpSimple("Object"), SxpNoAllows(), 3, 1, "a.nl", "cold", false, false)
    assert !policy.ReportCastToObject(SxpSimple("int"), SxpNoAllows(), 4, 1, "a.nl", "cold", false, false)
    assert SxpCount(sink) == 2
    assert SxpCode(sink, 0) == "NSYS020"
    assert SxpEffectName(sink, 0) == "boxing"
    assert SxpMessage(sink, 0) == "cast to object may box a value on systems paths"
    assert SxpSuggestion(sink, 0) == "Keep values concrete or use a generic/constrained API."
}

test "AN ARRAY OF OBJECT IS NOT A CAST TO OBJECT" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    arrayType := new ArrayTypeReference(SxpSimple("object"))
    assert !policy.ReportCastToObject(arrayType, SxpNoAllows(), 1, 1, "a.nl", "cold", false, false)
    assert SxpCount(sink) == 0
}

test "A WAIVED CAST STILL BOXES, AND SO DOES A CAST IN A SILENT DEFAULT-PROFILE FUNCTION" {
    waived := SxpSystemsSink()
    policyWaived := new SystemsConstructPolicy(waived)
    assert policyWaived.ReportCastToObject(SxpSimple("object"), SxpAllowing("boxing"), 1, 1, "a.nl", "cold", false, false)
    assert SxpCount(waived) == 0
    silent := SxpSink("default", "strict")
    policySilent := new SystemsConstructPolicy(silent)
    assert policySilent.ReportCastToObject(SxpSimple("object"), SxpNoAllows(), 1, 1, "a.nl", "cold", false, false)
    assert SxpCount(silent) == 0
}

test "AUDIT MODE TURNS EVERY ARM THAT SPEAKS INTO A WARNING, HOT-ONLY ARMS INCLUDED" {
    sink := SxpSink("systems", "audit")
    policy := new SystemsConstructPolicy(sink)
    policy.ReportYield(1, 1, "a.nl", "hot", true, false)
    policy.ReportTypeOf(SxpNoAllows(), 2, 1, "a.nl", "cold", false, false)
    assert SxpCount(sink) == 2
    assert SxpSeverity(sink, 0) == "warning"
    assert SxpSeverity(sink, 1) == "warning"
    assert sink.AotAnalysis() == "pass"
}

test "EACH POLICY ARM READS ITS OWN EFFECT NAME AND NO OTHER" {
    sink := SxpSystemsSink()
    policy := new SystemsConstructPolicy(sink)
    policy.ReportLambda(SxpAllowing("throw"), 1, 1, "a.nl", "cold", false, false)
    policy.ReportTry(SxpAllowing("delegate"), 2, 1, "a.nl", "cold", false, false)
    policy.ReportTypeOf(SxpAllowing("throw"), 3, 1, "a.nl", "cold", false, false)
    assert SxpCount(sink) == 3
}

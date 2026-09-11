namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHAT A CALL COSTS ITS CALLER.
//
// Seven rules, one subject seen from several sides. A call the analyzer could NOT resolve costs the
// caller an unknown-external-call finding. A call it could not resolve but DID classify — an
// unsupported concurrency primitive, runtime dispatch, a pool rent, reflection — costs the caller
// that classification's own sentence. A call it COULD resolve costs the caller whatever the callee's
// effects are, reported at the call and named for both ends. And a resolved callee that hands back a
// `Result` nobody binds costs the caller the error path it silently dropped. Every one of them
// reports at the CALL's position and about the CALLER's promise, which is why they are one owner.
//
// THIS IS NOT `SystemsCallPolicy`. That one classifies call TARGETS — is this a pool rent, a
// reflection call, a resource factory — and answers about the callee in isolation. This one prices
// what the answer costs the function doing the calling.
//
// THE UNRESOLVED CALL HAS THREE ARMS AND THEY ARE A PRECEDENCE, NOT A SET. `[hot]` answers first and
// conclusively: a hot function that reaches something the analyzer cannot see has broken its promise,
// so it is an error and the other two arms are never consulted. `[boundary]` answers next with a
// warning, because a boundary is exactly where unknown work is allowed to live and the finding is
// there for review. Only a function that is neither reaches the project's own setting, and a
// default-profile project is silent even then.
//
// THE PROJECT'S `unknownExternalCalls` SETTING IS READ ONCE PER ANALYSIS, not at each call, for the
// reason the stackalloc budget is: a project's configuration cannot change mid-analysis, and reading
// it once is what makes it visible in this owner's own contracts. It is three values — `allow` says
// nothing at all, `error` fails the build, anything else warns — and the ELSE arm is load-bearing:
// `ProjectFileParser` rejects a fourth value, but a `SystemsAnalyzer` can be constructed with a
// config that never went through the parser, and such a project must warn rather than throw.
//
// THE CALLEE'S EFFECTS ARRIVE AS `SystemsEffectFacts`, THE RECORD THE REPORT ALREADY PUBLISHES. The
// twelve bits these rules read are twelve of that record's fifteen fields, so the callee travels as
// the same fact the analyzer's own summary carries rather than as twelve loose booleans or as a
// mutable walk object that would drag the whole callee-resolution family behind it.
//
// ONLY A `[hot]` OR `alloc(none)` CALLER IS TOLD WHAT ITS CALLEES COST, and that gate lives here
// rather than at the walk that drives it: "which callers are asked" is the rule's own first
// sentence, and a driver that decided it would be deciding policy.
//
// THE CALLER'S ALLOW TEST IS NOT THE WALK'S. Two of the ten arms are silenced by a function-level
// `allow(alloc)` / `allow(pool)` — an EXACT set membership on the function's own attribute, with no
// `alloc:`-prefix widening and no block-level allow stack. That is deliberately narrower than the
// `IsAllowed` every in-body rule uses: a block-level waiver covers the statements the author wrote
// inside it, not the transitive cost of everything those statements call.
//
// A CALL PATH OF TWO IS THIS FAMILY'S ALONE. Every other systems finding names one function; a callee
// finding names the caller and then the callee, which the renderer shows as `effect path: a -> b`,
// because the position it reports at belongs to the caller while the sentence is about the callee.
class SystemsCalleePolicy {
    typePolicyValue: SystemsTypePolicy
    sinkValue: SystemsFindingSink
    unknownExternalCallsValue: string

    constructor(typePolicy: SystemsTypePolicy, sink: SystemsFindingSink) {
        typePolicyValue = typePolicy
        sinkValue = sink
        unknownExternalCallsValue = "warn"
    }

    // One call per analysis, from the analyzer's own reset block. See the header for why the setting
    // is read here and not at each unresolved call.
    func BeginAnalysis(config: ProjectConfig) {
        unknownExternalCallsValue = config.Language.Systems.UnknownExternalCalls
    }

    // A CALL THE ANALYZER COULD NOT RESOLVE. The caller has already recorded the effect on its own
    // summary; this decides only what the developer is told, and the three arms are the precedence
    // described in the header.
    //
    // THE UNDERLINE IS THE TARGET'S SIMPLE NAME, not the qualified text: `Console.WriteLine` reports
    // under `WriteLine`, because that is the width of the thing at the reported column.
    func ReportUnknownExternalCall(target: string, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        length := Math.Max(1, SystemsTypeNames.SimpleName(target).Length)
        if isHot {
            sinkValue.AddForFunction("NSYS050", "unknownExternalCall", "unknown external call '" + target + "' is not callable from [hot]", line, column, length, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Add a compiler/HotSummary entry, make the callee [hot], or move this call behind a [boundary].")
            return
        }

        if isBoundary {
            sinkValue.AddForFunction("NSYS050", "unknownExternalCall", "boundary external call '" + target + "' reported for systems handoff review", line, column, length, filePath, functionName, isHot, isBoundary, ErrorSeverity.Warning, "Keep unknown external work inside the [boundary] and expose a systems-safe result.")
            return
        }

        if !sinkValue.IsSystemsProfile {
            return
        }

        if unknownExternalCallsValue == "allow" {
            return
        }

        sinkValue.AddForFunction("NSYS050", "unknownExternalCall", "unknown external call '" + target + "' has no systems summary", line, column, length, filePath, functionName, isHot, isBoundary, UnknownExternalCallSeverity(), "Add a sidecar HotSummary or put the call in a [boundary].")
    }

    // WHAT A RESOLVED CALLEE'S EFFECTS COST ITS CALLER. Every arm reports at the CALL SITE — its line,
    // its column, the width of the call's own text — while the file, the name, the hotness and the
    // policy label are the CALLER's, because the promise that was broken is the caller's promise.
    //
    // TEN ARMS, EVERY ONE PREFERRING `Error`. A hot or `alloc(none)` caller is making an absolute
    // claim, so the rule never prefers a warning; the sink still downgrades at a `[boundary]` and in
    // audit mode, which is the only reason a callee finding is ever anything else.
    //
    // THE ARMS ARE NOT MUTUALLY EXCLUSIVE and there is no `return` between them: one callee that
    // allocates AND boxes AND reflects produces three findings at the same position, in this order.
    func ReportCalleePolicyViolations(callee: SystemsEffectFacts, calleeName: string, callerAllowsAlloc: bool, callerAllowsPool: bool, line: int, column: int, length: int, callerFile: string, callerName: string, callerIsHot: bool, callerIsBoundary: bool, callerAllocNone: bool) {
        if !callerIsHot && !callerAllocNone {
            return
        }

        callPath := new string[](2)
        callPath[0] = callerName
        callPath[1] = calleeName
        if callee.Allocates && !callerAllowsAlloc {
            Report("NSYS010", "allocation", "callee '" + calleeName + "' allocates on a hot/alloc(none) path", "Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.Boxes {
            Report("NSYS020", "boxing", "callee '" + calleeName + "' boxes a value on a hot path", "Use concrete generic/value-type APIs or add a HotSummary that proves constrained dispatch.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.ConstructsDelegate || callee.CapturesClosure {
            Report("NSYS030", "delegate", "callee '" + calleeName + "' constructs a delegate or closure on a hot path", "Use direct calls or move delegate construction behind a [boundary].", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.UsesRuntimeDispatch {
            Report("NSYS040", "dispatch", "callee '" + calleeName + "' uses runtime dispatch on a hot path", "Use a concrete receiver, constrained generic call, or summarized dispatch-free wrapper.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.UsesUnknownExternalCall {
            Report("NSYS050", "unknownExternalCall", "callee '" + calleeName + "' reaches an unknown external call", "Add a HotSummary, make the callee hot-checkable, or isolate the call behind a [boundary].", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.UsesReflection || callee.UsesDynamicCode {
            Report("NSYS060", "aot", "callee '" + calleeName + "' blocks AOT/trimming facts", "Move reflection/dynamic code behind a [boundary] or add an audited target-qualified summary.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.HasImplicitTrapObligation {
            Report("NSYS120", "implicitTrap", "callee '" + calleeName + "' has unproven implicit trap obligations", "Prove bounds/null/divide/overflow locally or use a narrow allow(trap).", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.UsesResource {
            Report("NSYS090", "resource", "callee '" + calleeName + "' creates or owns a disposable resource", "Open resources at a [boundary] and pass explicit handles or spans to hot code.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.UsesPool && !callerAllowsPool {
            Report("NSYS130", "pool", "callee '" + calleeName + "' rents from a pool without a hot-ready pool precondition", "Return pooled buffers in the same lexical path or configure/warm the pool explicitly.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }

        if callee.RequiresWarmup {
            Report("NSYS110", "hotReadiness", "callee '" + calleeName + "' requires warmup before the hot path is warm-ready", "Add the required warmup function to language.systems.warmup or remove first-use work.", line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, callPath)
        }
    }

    // WHAT AN UNRESOLVED TARGET COSTS ITS CALLER, IN FOUR SENTENCES. `SystemsCallPolicy` classifies
    // the target — is it a pool rent, a reflection call, a threading primitive — and these four price
    // the answer against the caller's promise. They are the same subject as `ReportUnknownExternalCall`
    // above seen one classification later: a target the analyzer DID recognise, and recognised as
    // something a systems path must be told about.
    //
    // ALL FOUR REPORT AT THE CALL and name the target inside the sentence, because the reader needs to
    // know which call in the line it is. THREE OF THE FOUR ARE POLICY FINDINGS — a narrow `allow(...)`
    // on the effect silences them and a `[boundary]` downgrades them — and the fourth, the hot pool
    // rent, is `[hot]`-only, because renting from a pool is ordinary work everywhere else.

    // A CONCURRENCY PRIMITIVE WITH NO v1 SEMANTICS. The call family knows a small set the profile can
    // reason about — volatile reads and writes, the interlocked operations, an explicit memory
    // barrier — and everything else in the threading surface is a primitive whose cost the profile
    // cannot state. Reported rather than silently accepted, because a primitive the analyzer cannot
    // price is exactly the thing a hot path must not reach by accident.
    func ReportUnsupportedConcurrencyPrimitive(target: string, allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddForPolicy("NSYS140", "concurrency", "concurrency primitive '" + target + "' has no v1 HotSummary semantics", line, column, allows.IsAllowed("concurrency"), filePath, functionName, isHot, isBoundary, "Use Volatile.Read/Write, Interlocked.Exchange/CompareExchange/Increment/Decrement/Add, or Thread.MemoryBarrier.")
    }

    // RUNTIME DISPATCH, OR AN INTERFACE-SHAPED API WITH NO SUMMARY. Both reach a method the analyzer
    // cannot see through, and both cost the caller the same thing, which is why they are one sentence
    // and not two.
    func ReportRuntimeDispatch(target: string, allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddForPolicy("NSYS040", "dispatch", "call to '" + target + "' uses runtime dispatch or an unsummarized interface-shaped API", line, column, allows.IsAllowed("dispatch"), filePath, functionName, isHot, isBoundary, "Use a concrete receiver, constrained generic call, or HotSummary-covered wrapper.")
    }

    // A POOL RENT INSIDE `[hot]`. Renting is ordinary work; renting on a hot path without a warm pool
    // is a first-use stall, so the rule is `[hot]`-only and `allow(pool)` waives it. THE CALLER
    // DECIDES WHETHER THIS CALL IS A RENT — `SystemsCallPolicy` owns that classification and the walk
    // needs the same answer again for the warmup bit, so it is asked once and handed over.
    func ReportHotPoolRent(isPoolRent: bool, allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if !isPoolRent || allows.IsAllowed("pool") {
            return
        }

        sinkValue.AddWhenHot("NSYS130", "pool", "[hot] pool rent requires a hot-ready pool precondition or allow(pool)", line, column, filePath, functionName, isHot, isBoundary)
    }

    // REFLECTION OR RUNTIME CODE GENERATION. The finding is about the TARGET-QUALIFIED AOT facts the
    // call destroys, not about the call being slow, which is why it wears the `aot` effect and why the
    // sink's AOT verdict reads it: an NSYS060 that survives at `error` is what turns the report's AOT
    // analysis from `pass` to `fail`.
    func ReportReflectionOrDynamicCall(target: string, allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddForPolicy("NSYS060", "aot", "call to '" + target + "' blocks target-qualified AOT/trimming facts", line, column, allows.IsAllowed("aot"), filePath, functionName, isHot, isBoundary, "Move reflection/dynamic code behind a [boundary] or add an audited target-qualified summary.")
    }

    // A `Result` NOBODY BOUND. The caller has resolved the call to a declared function and hands over
    // that function's WRITTEN return type; a call with no resolved declaration and a callee with no
    // written return type are both silent here, because a rule about a discarded error path cannot be
    // stated about a callee whose contract the analyzer never read.
    //
    // ERROR IN A `[hot]` FUNCTION OR IN A SYSTEMS PROJECT, WARNING OTHERWISE — the same shape the
    // allocation rule uses, and the reason a default-profile program can ignore a `Result` with a
    // nudge rather than a failure.
    //
    // THE FINDING NAMES THE CALLEE QUALIFIED AND UNDERLINES IT SIMPLE, for the reason the surface
    // rules pass both: `Reader.Next` tells the reader where to look and `Next` is the width of the
    // text at the reported column.
    func CheckIgnoredResult(returnType: TypeReference?, calleeQualifiedName: string, calleeName: string, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if returnType == null || !typePolicyValue.IsResultType(returnType) {
            return
        }

        sinkValue.AddForFunction("NSYS160", "resultMustUse", "Result returned by '" + calleeQualifiedName + "' is ignored", line, column, Math.Max(1, calleeName.Length), filePath, functionName, isHot, isBoundary, IgnoredResultSeverity(isHot), "Bind the Result, return it, or explicitly inspect IsOk/IsErr so the error path is handled.")
    }

    // `error` fails, `allow` never reaches here, and everything else — including the `warn` default
    // and any value a hand-built config carries — warns.
    func UnknownExternalCallSeverity(): ErrorSeverity {
        if unknownExternalCallsValue == "error" {
            return ErrorSeverity.Error
        }

        return ErrorSeverity.Warning
    }

    func IgnoredResultSeverity(isHot: bool): ErrorSeverity {
        if isHot || sinkValue.IsSystemsProfile {
            return ErrorSeverity.Error
        }

        return ErrorSeverity.Warning
    }

    // The ten arms differ in their code, their effect, their sentence and their fix and in nothing
    // else, so the position, the subject and the two-element path are written once.
    func Report(code: string, effect: string, message: string, suggestion: string, line: int, column: int, length: int, callerFile: string, callerName: string, callerIsHot: bool, callerIsBoundary: bool, callPath: IReadOnlyList<string>) {
        sinkValue.Add(code, effect, message, line, column, length, callerFile, callerName, callerIsHot, callerIsBoundary, ErrorSeverity.Error, suggestion, callPath)
    }
}

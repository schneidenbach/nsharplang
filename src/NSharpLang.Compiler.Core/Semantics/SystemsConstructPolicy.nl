namespace NSharpLang.Compiler.Performance

import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHAT A CONSTRUCT COSTS BY BEING WRITTEN.
//
// Six language constructs cost a systems path something the moment they appear, and the cost is
// decided by the construct alone: `yield` allocates a state machine, `await`/`await foreach`/`using`
// take on a resource, `throw`/`try` are exception control flow, a lambda constructs a delegate and
// captures, a cast to `object` boxes, and `typeof` demands metadata. NOTHING ELSE IS CONSULTED —
// no configuration, no catalog, no resolution, no proof, no registered type. That is what separates
// this owner from every other systems owner: `SystemsCalleePolicy` needs a resolved target,
// `SystemsHotSummaryPolicy` needs a sidecar, `SystemsTrapPolicy` needs a guard set,
// `SystemsAttributePolicy` needs a declaration — and these need only the node kind.
//
// TWO SHAPES OF ARM AND THE SPLIT IS THE PROFILE'S. Four constructs are `[hot]`-ONLY (`yield`,
// `await`, `await foreach`, `using`): owning a resource or a state machine is ordinary work
// everywhere else, so a cold function hears nothing at all — not a warning. The other four are
// POLICY findings, reported to any systems-profile function: exception control flow, delegate
// construction, boxing and metadata are things a systems program is asked about wherever it writes
// them, and a narrow `allow(...)` on the effect silences each while a `[boundary]` downgrades it.
//
// `throw` AS A STATEMENT AND `throw` AS AN EXPRESSION ARE ONE RULE, and they were two copies of it.
// The original spelled the same code, the same effect, the same two sentences and the same fix at
// both walk sites; there is exactly one door here and both sites call it. `try` keeps its own,
// because its non-hot sentence is genuinely different — a `try` is reported for review, a `throw` is
// asked to become a value.
//
// THE HOT/COLD FORK INSIDE `throw` AND `try` IS NOT A SEVERITY CHOICE. A `[hot]` function gets a
// DIFFERENT SENTENCE — a flat refusal — through the hot-only door, which no `allow(...)` waives; a
// cold systems function gets the policy sentence, which one does. Folding the two into a single
// policy report would silently make `allow(throw)` legal inside `[hot]`.
class SystemsConstructPolicy {
    sinkValue: SystemsFindingSink

    constructor(sink: SystemsFindingSink) {
        sinkValue = sink
    }

    // `yield` BUILDS A STATE MACHINE ON THE HEAP. The declaration-level twin of this rule —
    // `[hot] iterator` — lives on `SystemsAttributePolicy`, because that one is decided by the
    // signature and this one by the body; a function can reach here through a local function whose
    // own declaration carries nothing.
    func ReportYield(line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddWhenHot("NSYS010", "allocation", "[hot] cannot allocate iterator state machines", line, column, filePath, functionName, isHot, isBoundary)
    }

    // `await foreach` IS BOTH AN ASYNC BOUNDARY AND AN ASYNC DISPOSAL, and the sentence names both
    // because either one alone is enough to refuse it on a hot path.
    func ReportAwaitForEach(line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddWhenHot("NSYS090", "resource", "[hot] cannot be an async iterator or await foreach boundary", line, column, filePath, functionName, isHot, isBoundary)
    }

    // `using` DECLARES OWNERSHIP OF SOMETHING THAT MUST BE RELEASED. The rule is about the ownership,
    // not about the disposal: a hot function is asked to receive an already-open handle, not to
    // dispose more carefully.
    func ReportUsing(line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddWhenHot("NSYS090", "resource", "[hot] cannot create or open disposable resources", line, column, filePath, functionName, isHot, isBoundary)
    }

    // `await` IS DEFERRED WORK, and "deferred" is the whole sentence: the continuation runs somewhere
    // this function cannot promise anything about, so a hot path may not contain one in v1.
    func ReportAwait(line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddWhenHot("NSYS090", "resource", "[hot] async work is deferred in Systems N# v1", line, column, filePath, functionName, isHot, isBoundary)
    }

    // `throw`, WHETHER WRITTEN AS A STATEMENT OR AS AN EXPRESSION. See the header for why there is one
    // door and for why the hot arm is a different sentence rather than a different severity.
    func ReportThrow(allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if isHot {
            sinkValue.AddWhenHot("NSYS120", "throw", "[hot] cannot throw exceptions", line, column, filePath, functionName, isHot, isBoundary)
            return
        }

        sinkValue.AddForPolicy("NSYS120", "throw", "systems code must translate exception control flow into explicit Result/error values", line, column, allows.IsAllowed("throw"), filePath, functionName, isHot, isBoundary, "Catch exceptions at a [boundary] and return Result<T,E> or another explicit error value.")
    }

    // `try`. THE COLD SENTENCE IS DELIBERATELY WEAKER THAN `throw`'s — "reported on systems paths"
    // rather than "must translate" — because catching is how a boundary is written, and the fix names
    // the boundary rather than the value.
    func ReportTry(allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if isHot {
            sinkValue.AddWhenHot("NSYS120", "throw", "[hot] cannot use exception control flow", line, column, filePath, functionName, isHot, isBoundary)
            return
        }

        sinkValue.AddForPolicy("NSYS120", "throw", "exception control flow is reported on systems paths", line, column, allows.IsAllowed("throw"), filePath, functionName, isHot, isBoundary, "Keep try/catch inside a [boundary] and translate failures into explicit Result/error values.")
    }

    // A LAMBDA IS A DELEGATE AND A CAPTURE AT ONCE, and the walk records both bits from one arm. The
    // sentence says "not allowed HERE" rather than naming the profile, because the same lambda is
    // fine one `[boundary]` away and the fix is to move it, not to rewrite it.
    func ReportLambda(allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddForPolicy("NSYS030", "delegate", "delegate or closure construction is not allowed here", line, column, allows.IsAllowed("delegate"), filePath, functionName, isHot, isBoundary, "Move delegate construction behind a [boundary] or use a direct call.")
    }

    // A CAST TO `object` MAY BOX, AND "MAY" IS THE HONEST WORD: the target type is all this rule has,
    // so a reference already typed `object` is reported alongside the `int` that really boxes. Both
    // spellings of the target answer — the keyword and the framework name — and nothing else does,
    // because a cast to any other type either does not box or boxes into a shape the type family
    // decides.
    //
    // RETURNS WHETHER THE CAST BOXES, NOT WHETHER IT WAS REPORTED. The walk records `Boxes` on the
    // summary whenever the target is `object`, including when a waiver or a `[boundary]` silenced the
    // finding — the effect happened either way and the caller inherits it.
    func ReportCastToObject(targetType: TypeReference, allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool): bool {
        erased := SystemsTypeNames.ErasedName(targetType)
        if erased != "object" && erased != "System.Object" {
            return false
        }

        sinkValue.AddForPolicy("NSYS020", "boxing", "cast to object may box a value on systems paths", line, column, allows.IsAllowed("boxing"), filePath, functionName, isHot, isBoundary, "Keep values concrete or use a generic/constrained API.")
        return true
    }

    // `typeof` DEMANDS METADATA THE TRIMMER WOULD OTHERWISE REMOVE. It wears the `aot` effect and not
    // a "reflection" one, because what it costs is the target-qualified AOT fact, and the sink's AOT
    // verdict reads exactly that code at exactly that severity.
    func ReportTypeOf(allows: SystemsAllowStack, line: int, column: int, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        sinkValue.AddForPolicy("NSYS060", "aot", "typeof requires metadata and may block trimming/AOT facts", line, column, allows.IsAllowed("aot"), filePath, functionName, isHot, isBoundary, "Move reflection to a [boundary] or add an audited target-qualified summary.")
    }
}

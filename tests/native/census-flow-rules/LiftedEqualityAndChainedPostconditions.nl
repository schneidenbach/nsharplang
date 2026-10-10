namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic
import System.Linq


// CENSUS §FLOW5 — WHERE A CALL'S POSTCONDITION HAS TO REACH, AND WHAT A LIFTED BOOLEAN COMPARES TO.
//
// A `?.` INVOCATION IS A CALL. `x?.M(a, b)` resolves `M` to a method GROUP, and a method group has
// no nullable form — the LIFT belongs to the invocation, which is where the chain finally produces a
// value. Lifting the guard link itself wrapped the group in a nullable the call's dispatch matched
// nothing against, so EVERY `x?.M(...)` silently answered `unknown`: no overload resolution, no
// argument diagnostics and no postconditions. `h?.M("a", "b", "c")` reported no arity error at all.
//
// `Nullable<T>` LIFTS `==` AND `!=`. Two ABSENT values are equal, an absent one differs from every
// present one, and the answer is a plain `bool` — C# §12.12.7, and the rule `x?.TryGetValue(k, out v)
// == true` needs before it can mean anything.
//
// `c == true` IS `c`. A converter writes that spelling wherever the source compared a lifted boolean,
// and the three other spellings are its negation or its mirror. A LIFTED operand only proves the side
// the comparison DECIDED: `x?.M() == true` holds only when `x` was non-null AND the call answered
// true, so that branch carries the chain's receivers too, while its other branch is a disjunction
// that proves nothing.
//
// AND A RECEIVER'S OWN NULLABILITY ANNOTATION IS NOT A SHAPE. `doc.Symbols?.TryGetValue(k, out v)`
// hands the receiver over as `Dictionary<K, V>?`, and a receiver read out of an assembly compiled
// without a nullable context hands it over as an OBLIVIOUS shell. Both used to answer "not a generic"
// to the binder's structural walk, so the receiver contributed no type bindings and `TValue` was left
// to be bound by whichever argument came next — the `out` variable, whose own `V?` then made the
// call's postcondition say the TRUE branch leaves a maybe-null value.
class FlowSymbolInfo {
    Kind: int
    Name: string

    constructor(kind: int, name: string) {
        Kind = kind
        Name = name
    }
}

class FlowDocumentState {
    SymbolsInfo: Dictionary<string, FlowSymbolInfo>?
    SymbolLocations: Dictionary<string, List<string>>?
    Traits: Dictionary<string, List<string>>

    constructor(symbols: Dictionary<string, FlowSymbolInfo>?, locations: Dictionary<string, List<string>>?, traits: Dictionary<string, List<string>>) {
        SymbolsInfo = symbols
        SymbolLocations = locations
        Traits = traits
    }
}

// ── §2 the receiver is a PROPERTY CHAIN and the guard is on that same chain ─────────────────────

// The converted `CallHierarchyHandler.isFunctionSymbol`, verbatim in shape: the `!= null` proves the
// chain and the call on that same chain proves `symbolInfo` in the branch it returned true on.
func IsFunctionSymbol(doc: FlowDocumentState, word: string): bool {
    symbolInfo: FlowSymbolInfo? = default
    if doc.SymbolsInfo != null && doc.SymbolsInfo.TryGetValue(word, out symbolInfo) {
        return symbolInfo.Kind == 1 || symbolInfo.Kind == 2
    }

    locations: List<string>? = default
    if doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(word, out locations) {
        return locations.Any(location => location.Length > 0)
    }

    return false
}

// ── §3 `x?.TryGetValue(k, out v) == true` ──────────────────────────────────────────────────────

// The converted `SignatureHelpHandler` site: the `?.` guards the call, the `== true` decides it, and
// the right operand of the `&&` reads the value the call left behind.
func TypeNameOrNone(doc: FlowDocumentState, typeName: string): string {
    symbolInfo: FlowSymbolInfo? = default
    if doc.SymbolsInfo?.TryGetValue(typeName, out symbolInfo) == true && (symbolInfo.Kind == 1 || symbolInfo.Kind == 3) {
        return symbolInfo.Name
    }

    return "none"
}

// `== false` decides its TRUE branch, and what that branch proves is the chain's receiver — which is
// why the dictionary can be read there without a second null check.
func MissingCount(doc: FlowDocumentState, typeName: string): int {
    symbolInfo: FlowSymbolInfo? = default
    if doc.SymbolsInfo?.TryGetValue(typeName, out symbolInfo) == false {
        return doc.SymbolsInfo.Count
    }

    return -1
}

// `!= true` holds when the receiver was null OR the call answered false, so it decides its FALSE
// branch — and the `else` is where the value is readable.
func KindOrMissing(doc: FlowDocumentState, typeName: string): int {
    symbolInfo: FlowSymbolInfo? = default
    if doc.SymbolsInfo?.TryGetValue(typeName, out symbolInfo) != true {
        return -1
    }

    return symbolInfo.Kind
}

// A `?.` call IS bound now, which means its arguments are checked and its result has the callee's
// type — lifted once by the chain.
func TraitCount(doc: FlowDocumentState): int {
    return doc.SymbolLocations?.Count ?? 0
}

func ContainsSymbol(doc: FlowDocumentState, key: string): bool {
    return doc.SymbolsInfo?.ContainsKey(key) == true
}

// ── §4 a postcondition inside a TERNARY condition ──────────────────────────────────────────────

// The converted `Program.getXunitDescription`: the receiver is a property chain, the condition is a
// ternary's, and the true arm reads the value the call left behind.
func FirstTrait(doc: FlowDocumentState, key: string): string? {
    values: List<string>? = default
    return doc.Traits.TryGetValue(key, out values) ? values.FirstOrDefault() : null
}

// The same fact on the FALSE arm, so the ternary's two arms are not one rule stated once.
func TraitOrFallback(doc: FlowDocumentState, key: string): string {
    values: List<string>? = default
    return doc.Traits.TryGetValue(key, out values) ? values[0] : "fallback"
}

// ── the lifted equality family, on its own ─────────────────────────────────────────────────────

func LiftedIntEquals(left: int?, right: int): bool {
    return left == right
}

func LiftedIntNotEquals(left: int?, right: int): bool {
    return left != right
}

func BothLiftedEquals(left: int?, right: int?): bool {
    return left == right
}

func ValueOnTheLeft(left: int, right: int?): bool {
    return left == right
}

func LiftedBoolIsTrue(value: bool?): bool {
    return value == true
}

func LiftedBoolIsFalse(value: bool?): bool {
    return value == false
}

func LiftedDoubleEquals(left: double?, right: double): bool {
    return left == right
}

func LiftedCharEquals(left: char?, right: char?): bool {
    return left == right
}

enum FlowStage {
    Start,
    Middle,
    End
}

func LiftedEnumEquals(left: FlowStage?, right: FlowStage): bool {
    return left == right
}

// The operand ORDER a lifted comparison evaluates in is the source's, and a side effect is what
// proves it.
class FlowOrderLog {
    Text: string

    constructor() {
        Text = ""
    }

    func Record(mark: string, value: int): int {
        Text = Text + mark
        return value
    }
}

func LiftedOrder(log: FlowOrderLog, left: int?, right: int): bool {
    return LiftedLeft(log, left) == log.Record("R", right)
}

func LiftedLeft(log: FlowOrderLog, value: int?): int? {
    log.Record("L", 0)
    return value
}

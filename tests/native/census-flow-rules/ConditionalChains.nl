namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic


// CENSUS §FLOW3 — A `?.` CHAIN IS ONE EXPRESSION, AND EVERYTHING WRITTEN AFTER THE `?` BELONGS TO IT.
//
// `snapshot?.Units.Count` used to be read as two things: a guarded `?.Units` producing `List<int>?`,
// and then an ordinary `.Count` dereference of it. That reading produced two diagnostics the program
// does not deserve — NL905 on `Units` and, once `?? 0` was written after it, NL202 saying the left
// side of `??` is an `int` that cannot be null — and it disagreed with the emitter, which has always
// short-circuited the WHOLE chain from its outermost link.
//
// WHAT RUNS HERE IS THE SHORT CIRCUIT ITSELF. Every function is called with a null receiver and with
// a real one, so a chain that stopped guarding its continuation would throw rather than differ in
// opinion. The lift is observed the same way: the chain's result is fed to `??`, compared against
// null, and stored in a nullable local, none of which a non-lifted `int` would accept.
class Snapshot {
    Units: List<int>
    Name: string

    constructor(units: List<int>, name: string) {
        Units = units
        Name = name
    }
}

class Holder {
    Inner: Snapshot?

    constructor(inner: Snapshot?) {
        Inner = inner
    }
}

// A VALUE result is lifted to `Nullable<T>`: `?? 0` is what proves it.
func UnitCountOrZero(snapshot: Snapshot?): int {
    return snapshot?.Units.Count ?? 0
}

// The same chain assigned to a local, which then has to be nullable to be compared against null.
func UnitCountOrMinusOne(snapshot: Snapshot?): int {
    count := snapshot?.Units.Count
    if count == null {
        return -1
    }

    return must count
}

// A REFERENCE result stays its own type and becomes maybe-null.
func TrimmedNameOrDefault(snapshot: Snapshot?): string {
    return snapshot?.Name.Trim() ?? "none"
}

// A call written directly on the guard is the same rule: the invocation is the chain's result.
func TrimmedOrDefault(text: string?): string {
    return text?.Trim() ?? "none"
}

// TWO `?.` LINKS IN ONE CHAIN. The second guard sits in the first one's continuation, and the whole
// thing is still one expression with one lifted result.
func InnerUnitCountOrZero(holder: Holder?): int {
    return holder?.Inner?.Units.Count ?? 0
}

// A guard followed by a continuation that is itself indexed.
func FirstUnitOrZero(snapshot: Snapshot?): int {
    return snapshot?.Units[0] ?? 0
}

// A continuation whose own receiver is a CALL in the chain.
func TrimmedNameLengthOrZero(snapshot: Snapshot?): int {
    return snapshot?.Name.Trim().Length ?? 0
}

// A PARENTHESIS ENDS THE CHAIN, so the code after it has to do its own guarding — which is what the
// `??` inside the parentheses is for. This is the shape that must NOT silently keep chaining.
func ParenthesisedChainLength(snapshot: Snapshot?): int {
    return (snapshot?.Name ?? "").Length
}

// The chain's null result flows into an ordinary nullable local, proving the lift is a real type and
// not a suppression.
func UnitCountLocal(snapshot: Snapshot?): int? {
    count: int? = snapshot?.Units.Count
    return count
}

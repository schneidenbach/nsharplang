namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic


// `T? where T : struct` IS A REAL `Nullable<T>`, IN THE DECLARATION AND AT EVERY CALL THAT READS IT.
//
// The two readings of `T?` are decided by the parameter's own `where` clause, exactly as C# decides
// them. An UNCONSTRAINED `T?` is an annotation that erases — `FirstOrDefaultOf<DateTime>` answers a
// `DateTime` — and the sibling `GenericParameterNullability` file pins that half. A `where T :
// struct` parameter is the other half: `T?` is the CLR's `Nullable<T>` over the parameter, which is
// what the CLR itself requires of a `Nullable`'s argument.
//
// The declaration used to resolve its own return to the BARE `T`, because liftability refused every
// type parameter. Nothing complained — the declaration emitted — and the damage was all at the call
// sites, which read a `T` where the analyzer had said `T?`: `r := FirstOrNone(xs)` then `if r !=
// null` declined at `emit.if.condition`, `if FirstOrNone(xs) != null` at the same site, and
// `r.GetValueOrDefault()` reported `Int32.GetValueOrDefault` as unmodeled. The call at a position
// that ALREADY stated `int?` bound, which is what made the gap look like a call-site gap.
//
// So the contract is in three parts: the metadata the declaration writes, the answers the calls
// give at run time, and the absent case — which is the one an erased `T` could not have expressed
// at all.
class LiftedGenerics {
    static func FirstOrNone<T>(items: List<T>): T? where T: struct {
        for item in items {
            return item
        }

        return null
    }

    static func PairedOrNone<T>(items: List<T>, wanted: int): T? where T: struct {
        if items.Count == wanted {
            return items[0]
        }

        return null
    }
}

struct Weight {
    Grams: int
}

// The INFERRED local — its type is whatever the call answers, with nothing else to state it.
func FirstNumberOrMinusOne(values: List<int>): int {
    found := LiftedGenerics.FirstOrNone(values)
    if found != null {
        return found.Value
    }

    return -1
}

// The call INLINE in a condition, where the comparison's own operand type is the call's result.
func HasFirstNumber(values: List<int>): bool {
    if LiftedGenerics.FirstOrNone<int>(values) != null {
        return true
    }

    return false
}

// The lifted result flowing straight out of a lifted return position.
func FirstNumberLifted(values: List<int>): int? {
    return LiftedGenerics.FirstOrNone(values)
}

// `Nullable<T>`'s own surface on the inferred local, which only exists if the local really is one.
func FirstNumberOrDefault(values: List<int>): int {
    found := LiftedGenerics.FirstOrNone(values)
    return found.GetValueOrDefault()
}

// The same three shapes with T substituted by a struct THIS compilation declares.
func FirstWeightGrams(weights: List<Weight>): int {
    found := LiftedGenerics.FirstOrNone(weights)
    if found != null {
        return found.Value.Grams
    }

    return -1
}

func PairedWeightGrams(weights: List<Weight>, wanted: int): int {
    found := LiftedGenerics.PairedOrNone(weights, wanted)
    if found == null {
        return -1
    }

    return found.Value.Grams
}

// ── an external generic's instance member, closed over a SOURCE element, with a LAMBDA ───────────
//
// `items.Find(w => …)` on a `List<Weight>` declined at `emit.call.instance-member` while the same
// call on a `List<int>` emitted. The receiver is the whole difference: `List<int>` answers its own
// member query and `List<Weight>` answers none at all — reflection throws on a member query over an
// instantiation closed over a type this compilation is still building — and the tier a lambda
// argument reaches was the one tier that had no second door. It reads the candidates off `List<T>`
// now, closes this instantiation's arguments into every declared position, and rebinds the selected
// handle onto the instantiation, which is what the SCORED tier beside it already did.
func HeaviestUnder(weights: List<Weight>, limit: int): int {
    found := weights.Find(weight => weight.Grams < limit)
    return found.Grams
}

func CountOver(weights: List<Weight>, limit: int): int {
    return weights.FindAll(weight => weight.Grams > limit).Count
}

func IndexOfFirstOver(weights: List<Weight>, limit: int): int {
    return weights.FindIndex(weight => weight.Grams > limit)
}

func AnyOver(weights: List<Weight>, limit: int): bool {
    return weights.Exists(weight => weight.Grams > limit)
}

// ── `Nullable<T>`'S OWN SURFACE INSIDE THE DECLARATION THAT SPELLS `T?` ──────────────────────────
//
// The same `Nullable<T>` read from the other side. A type parameter is a bare name carrying nothing
// but its spelling, so every reader that asks "is this a reference type?" of `T` answers YES — and
// the `T?` of a `where T : struct` declaration therefore lost its own surface inside its own body:
// `a.HasValue` reported NL905 on a read that cannot throw and `a.GetValueOrDefault()` reported NL303
// for a member `T` certainly does not declare, while `if a == null` and the narrowed `a.Value`
// beside them were already fine. The `where` clause is the answer, and it is recorded on the scope
// that declared the parameter.
func PresenceOf<T>(a: T?): bool where T: struct {
    return a.HasValue
}

func ValueOrDefaultOf<T>(a: T?): T where T: struct {
    return a.GetValueOrDefault()
}

func ValueOrFallbackOf<T>(a: T?, fallback: T): T where T: struct {
    return a.GetValueOrDefault(fallback)
}

func GuardedValueOf<T>(a: T?, fallback: T): T where T: struct {
    if a == null {
        return fallback
    }

    return a.Value
}

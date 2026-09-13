namespace NSharpLang.CensusFlowRules.Tests

import System


// ONE SURFACE FOR EVERY `Nullable<T>`, WHATEVER `T` IS — compiled and RUN by the tip compiler.
//
// `Nullable<T>` is one declaration with one layout, so `HasValue`, `Value` and both
// `GetValueOrDefault` overloads mean the same thing for every element. Two separate lists used to
// decide otherwise:
//
//   * the ANALYZER read the nullable surface off the CLOSED CLR construction, and there is no
//     closed construction while `T` is a struct or an enum THIS COMPILATION is emitting — so
//     `money.GetValueOrDefault()` on a `Money?` reported NL303 "Member 'GetValueOrDefault' not
//     found on type 'Money'" (the name fell through to the UNWRAPPED receiver, which is the one
//     type that certainly does not declare it) while `count.GetValueOrDefault()` on an `int?` bound;
//   * the EMITTER carried a liftable element LIST — the scalars, `bool`, `char`, `decimal`,
//     `TimeSpan`, a tuple, an enum, a source struct — so `DateTime?` and `Guid?` declined at every
//     declared position with NL103 while `TimeSpan?` beside them emitted.
//
// Every function below is one of those shapes. Compiling is half the contract; the sibling
// `.tests.nl` asserts the answers at run time, and reads the emitted signatures back through
// reflection so the CLR metadata is pinned too.
struct Money {
    Amount: int

    static func operator +(a: Money, b: Money): Money => new Money { Amount: a.Amount + b.Amount }

    static func operator -(a: Money): Money => new Money { Amount: -a.Amount }

    static func operator <(a: Money, b: Money): bool => a.Amount < b.Amount

    static func operator >(a: Money, b: Money): bool => a.Amount > b.Amount
}

enum Grade {
    Low = 1,
    High = 2
}

// ── the surface, over a SOURCE struct ───────────────────────────────────────────────────────────

func MoneyPresence(m: Money?): bool {
    return m.HasValue
}

func MoneyAmountOrZero(m: Money?): int {
    return m.GetValueOrDefault().Amount
}

func MoneyAmountOrFallback(m: Money?, fallback: Money): int {
    return m.GetValueOrDefault(fallback).Amount
}

func MoneyAmountThroughValue(m: Money?): int {
    if m != null {
        return m.Value.Amount
    }

    return -1
}

// ── the surface, over a SOURCE enum ─────────────────────────────────────────────────────────────

func GradePresence(g: Grade?): bool {
    return g.HasValue
}

func GradeOrDefault(g: Grade?): Grade {
    return g.GetValueOrDefault()
}

func GradeOrFallback(g: Grade?, fallback: Grade): Grade {
    return g.GetValueOrDefault(fallback)
}

// ── the surface, over an EXTERNAL struct the old list did not have ──────────────────────────────

func MomentYearOrZero(d: DateTime?): int {
    return d.GetValueOrDefault().Year
}

func MomentPresence(d: DateTime?): bool {
    return d.HasValue
}

func IdIsEmpty(g: Guid?): bool {
    return g.GetValueOrDefault() == Guid.Empty
}

// ── `Nullable<T>` over a source struct at EVERY declared position ───────────────────────────────

class Wallet {
    Held: Money?

    constructor(held: Money?) {
        Held = held
    }

    func HeldAmount(): int {
        return Held.GetValueOrDefault().Amount
    }
}

func WrapMoney(m: Money): Money? {
    return m
}

func UnwrapLocal(amount: int): int {
    local: Money? = new Money { Amount: amount }
    return local.GetValueOrDefault().Amount
}

func AbsentLocal(): int {
    local: Money? = null
    return local.GetValueOrDefault().Amount
}

func MomentLocalYear(): int {
    moment: DateTime? = new DateTime(2031, 2, 3)
    return moment.GetValueOrDefault().Year
}

// The emitted signatures, on a declared type so reflection can read them back by name.
//
// (LIFT's user-defined `op_*` over a `?`-lifted SOURCE struct — which came for free the moment a
// source struct could be a `Nullable<T>`'s element — is pinned where the rest of the lifted-operator
// family lives, in `tests/native/census-lifted-operators`.)
class NullableSurfaceSignatures {
    func WrapStruct(m: Money): Money? => m

    func WrapMoment(d: DateTime): DateTime? => d

    func WrapId(g: Guid): Guid? => g

    func WrapGrade(g: Grade): Grade? => g

    func SumMoney(a: Money?, b: Money?): Money? => a + b
}

namespace NSharpLang.CensusLiftedOperators.Tests


// A USER-DEFINED OPERATOR ON A STRUCT THIS COMPILATION DECLARES, LIFTED.
//
// The lifting rule was always general — it reads the operator from the unlifted resolution and never
// from a table — so this file names nothing the compiler has to know about. What it could not do was
// have a `Cents?` to lift over at all: the liftable element set was a LIST that happened to carry
// `decimal` and `TimeSpan` (the external structs whose arithmetic is `op_*` methods) and, later, a
// source struct, while `DateTime` and `Guid` beside them were absent. With that list replaced by the
// CLR's own rule — a non-nullable, non-by-ref-like value type — every source struct's operators lift
// for the same reason `decimal`'s do.
struct Cents {
    Value: int

    static func operator +(a: Cents, b: Cents): Cents => new Cents { Value: a.Value + b.Value }

    static func operator -(a: Cents, b: Cents): Cents => new Cents { Value: a.Value - b.Value }

    static func operator -(a: Cents): Cents => new Cents { Value: -a.Value }

    static func operator <(a: Cents, b: Cents): bool => a.Value < b.Value

    static func operator >(a: Cents, b: Cents): bool => a.Value > b.Value

    static func operator ==(a: Cents, b: Cents): bool => a.Value == b.Value

    static func operator !=(a: Cents, b: Cents): bool => a.Value != b.Value
}

func AddCents(a: Cents?, b: Cents?): Cents? => a + b

func SubtractCents(a: Cents?, b: Cents?): Cents? => a - b

func NegateCents(a: Cents?): Cents? => -a

func AddCentsValue(a: Cents?, b: Cents): Cents? => a + b

func CentsAreLess(a: Cents?, b: Cents?): bool => a < b

func CentsAreMore(a: Cents?, b: Cents?): bool => a > b

func CentsAreEqual(a: Cents?, b: Cents?): bool => a == b

func CentsDiffer(a: Cents?, b: Cents?): bool => a != b

class LiftedSourceStructSignatures {
    func Sum(a: Cents?, b: Cents?): Cents? => a + b

    func Compare(a: Cents?, b: Cents?): bool => a < b
}

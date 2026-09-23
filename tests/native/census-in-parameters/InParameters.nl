namespace NSharpLang.CensusInParameters.Tests


// CENSUS — `in` PARAMETERS: READ-ONLY BY REFERENCE.
//
// `in x: T` passes the caller's storage by reference and promises the callee will not write to it. On
// the CLR that is `&T` plus two marks — `ParameterAttributes.In` and `[IsReadOnly]` on the parameter
// — and both have to be there: the signature alone is indistinguishable from `ref`, so a consumer
// that saw only one of them would treat the parameter as a writable alias. `InParameterShape.tests.nl`
// beside this reads both back out of the emitted assembly.
//
// THE BY-REFERENCE-NESS IS OBSERVABLE, and `AliasSeesTheWrite` is where. One local is passed twice —
// once as `in`, once as `ref` — so the callee can read through the read-only reference, write through
// the writable one, and read again. A by-value parameter answers the same number twice; a reference
// answers the new value. That row is what distinguishes this feature from an ordinary parameter with
// a promise attached, and it is why the by-value control sits beside it.
//
// The call site may write `in` or leave it out: the signature already said the argument is passed by
// reference, so there is nothing for the word to warn a reader about. `ref` and `out` are NOT
// interchangeable with it in either direction; that is a compile-time refusal and the estate's
// overload rows own it.
//
// AN INTERFACE SLOT DECLARING A BY-REFERENCE PARAMETER IS NOT COVERED HERE, AND THE REASON IS NOT
// `in`. `interface I { func M(ref v: T) }` with a matching class declines at
// `emit.declaration.interface-unimplemented` on this tip and declined before `in` existed: the
// interface member's own parameter row is not wrapped to `&T` the way a class member's is, so the slot
// and the implementation never compare equal. Measured for `ref` as a control, so the limit belongs to
// by-reference parameters in general rather than to this feature.
//
// NEITHER IS A STATIC FIELD'S ADDRESS. `f(in Shared)` and `f(ref Shared)` both decline on this tip for
// a static field of a source type, so the aliasing row uses locals — which is the stronger shape
// anyway, because nothing outside the call can be blamed for what it observes.
struct Big {
    A: long
    B: long
    C: long
    D: long
}

class InParameters {

    static func SumIn(in value: Big): long {
        return value.A + value.B + value.C + value.D
    }

    static func SumByValue(value: Big): long {
        return value.A + value.B + value.C + value.D
    }

    // The word omitted at the call, which is the ordinary spelling.
    static func CallOmitted(): long {
        local := new Big { A: 1, B: 2, C: 3, D: 4 }
        return SumIn(local)
    }

    // The word written at the call, which means exactly the same thing and is allowed to be said.
    static func CallWritten(): long {
        local := new Big { A: 1, B: 2, C: 3, D: 4 }
        return SumIn(in local)
    }

    // THE ALIASING ROW. See the file header: one local, two parameters, one of them writable.
    static func AliasSeesTheWrite(): string {
        local := new Big { A: 1, B: 2, C: 3, D: 4 }
        return ReadTwiceAround(in local, ref local)
    }

    static func ReadTwiceAround(in value: Big, ref writable: Big): string {
        before := value.A
        writable = new Big { A: 100, B: 2, C: 3, D: 4 }
        after := value.A
        return before.ToString() + "," + after.ToString()
    }

    // The same shape with a BY-VALUE first parameter, so the row above is measured against its own
    // control rather than against an expectation.
    static func ByValueDoesNotSeeTheWrite(): string {
        local := new Big { A: 1, B: 2, C: 3, D: 4 }
        return ReadTwiceAroundByValue(local, ref local)
    }

    static func ReadTwiceAroundByValue(value: Big, ref writable: Big): string {
        before := value.A
        writable = new Big { A: 100, B: 2, C: 3, D: 4 }
        after := value.A
        return before.ToString() + "," + after.ToString()
    }

    // An `in` parameter is readable everywhere a value is: arithmetic, a comparison, an argument to
    // another call, and a COPY into a local the callee may then change freely.
    static func ReadEverywhere(in value: Big): string {
        copied := new Big { A: value.A + 1, B: value.B, C: value.C, D: value.D }
        larger := value.A < copied.A
        forwarded := SumByValue(value)
        return copied.A.ToString() + "," + larger.ToString() + "," + forwarded.ToString()
    }

    // `in` beside other parameters, and not first.
    static func Mixed(label: string, in value: Big, scale: long): long {
        return value.A * scale + label.Length
    }

    static func CallMixed(): long {
        local := new Big { A: 5, B: 0, C: 0, D: 0 }
        return Mixed("ab", local, 3)
    }

    // An `in` parameter of a PRIMITIVE type, which is the shape where by-reference buys nothing and
    // has to work anyway.
    static func Doubled(in value: long): long {
        return value + value
    }

    static func CallDoubled(): long {
        n: long = 21
        return Doubled(n)
    }

    // An `in` parameter forwarded to another `in` parameter: the address travels, and neither callee
    // may write through it.
    static func Forwarded(in value: Big): long {
        return SumIn(value)
    }

    static func CallForwarded(): long {
        local := new Big { A: 2, B: 3, C: 4, D: 5 }
        return Forwarded(local)
    }
}

// An INSTANCE method takes `in` exactly as a static one does, so the modifier is a property of a
// PARAMETER rather than of one declaration form.
//
// A CONSTRUCTOR is NOT covered, and it is a measured gap rather than an oversight. `constructor(in
// seed: Big)` with `new Holder(seed)` — and with `new Holder(in seed)` — declines on this tip, while
// the `ref` control `constructor(ref seed: Big)` called `new Holder(ref seed)` emits. Constructor
// SELECTION was taught the direction column (`ColumnarConstructionPlanner.ProjectedModifierKinds`), so
// the remaining gap is in the construction path's argument append rather than in overload resolution.
// It is recorded here so the next reader does not re-derive it.
class Holder {
    total: long

    constructor(seed: Big) {
        total = seed.A + seed.B
    }

    Total: long => total

    func AddFrom(in value: Big): long {
        return total + value.C
    }
}

class HolderDriver {
    static func Drive(): long {
        seed := new Big { A: 10, B: 20, C: 30, D: 40 }
        holder := new Holder(seed)
        return holder.AddFrom(seed)
    }

    static func Seeded(): long {
        seed := new Big { A: 7, B: 8, C: 0, D: 0 }
        holder := new Holder(seed)
        return holder.Total
    }
}

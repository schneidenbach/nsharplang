namespace NSharpLang.CensusClosedGenericSourceBase.Tests

import System.Collections.Generic
import System.Text


// A MEMBER INHERITED FROM A CLOSED GENERIC SOURCE BASE IS A MEMBER OF THAT INSTANTIATION.
//
// `class IntHolder: Holder<int>` inherits `Describe` from `Holder<T>`, and the member it actually has
// is `Holder<int>::Describe` — a MemberRef on the TypeSpec `Holder<int>`. The columnar backend used to
// bind the member on the open definition (or its self-instantiation `Holder<T>`) instead, so analysis
// was clean and emission declined with NL103 ("Schema-v3 reference receiver for 'Describe' does not
// match its declaring type") for a bare call, a `this.` call, a call through an `IntHolder` value
// and a bare property read alike. A static FIELD or PROPERTY of the base was worse: it emitted a raw
// token on the open definition, and the CLR refused the method with `BadImageFormatException` the
// first time it ran.
//
// Every shape below reaches a member declared on a generic source base through a CLOSED base link,
// and the tests run it and read the answer back.
class Holder<T> {
    stored: T

    static Made: int

    constructor(value: T) {
        stored = value
    }

    Value: T => stored

    static Tally: int => Made

    func Describe(): string => "holder"

    func Echo(item: T): T => item

    static func Kind(): string => "kind:" + typeof(T).Name
}

class IntHolder: Holder<int> {
    constructor(value: int): base(value) {
    }

    func BareCall(): string => Describe()

    func ThisCall(): string => this.Describe()

    // The parameter and the result are `T` on the declaration and `int` here.
    func BareEcho(): int => Echo(41) + 1

    func BareProperty(): int => Value

    func ThisProperty(): int => this.Value

    func BaseProperty(): int => base.Value

    func BareField(): int => stored

    func BareStaticCall(): string => Kind()

    func BareStaticProperty(): int => Tally

    func BareStaticField(): int => Made

    func WriteBareStaticField(value: int) {
        Made = value
    }
}

// TWO LINKS, EACH CLOSED OVER THE ONE BELOW IT. `Leaf : Mid<string> : Holder<List<U>>` reaches
// `Holder<List<string>>`, which only a per-link substitution produces: `Mid`'s base is written in
// `Mid`'s own `U`.
class Mid<U>: Holder<List<U>> {
    constructor(value: List<U>): base(value) {
    }

    func MidCount(): int => Value.Count

    func MidKind(): string => Kind()
}

class Leaf: Mid<string> {
    constructor(items: List<string>): base(items) {
    }

    func Deep(): string => this.Describe() + "/" + Kind() + "/" + Value.Count.ToString() + "/" + stored.Count.ToString() + "/" + MidCount().ToString()

    func DeepBase(): int => base.Value.Count
}

// A GENERIC derived type names its base in its OWN type parameter: inside `Wrapper<U>` the base is
// `Holder<U>`, and that is the instantiation its own code must call through.
class Wrapper<U>: Holder<U> {
    constructor(value: U): base(value) {
    }

    func Wrapped(): string => Describe() + ":" + Kind()

    func WrappedValue(): U => Value

    func Round(item: U): U => Echo(item)
}

// THE PROGRAM, as `main` would print it: one line per shape, in order.
func Transcript(): string {
    lines := new StringBuilder()
    holder := new IntHolder(7)
    lines.AppendLine(holder.BareCall())
    lines.AppendLine(holder.ThisCall())
    lines.AppendLine(holder.Describe())
    lines.AppendLine(holder.BareEcho().ToString())
    lines.AppendLine(holder.BareProperty().ToString())
    lines.AppendLine(holder.ThisProperty().ToString())
    lines.AppendLine(holder.Value.ToString())
    lines.AppendLine(holder.BareStaticCall())
    lines.AppendLine(IntHolder.Kind())

    items := new List<string>()
    items.Add("a")
    items.Add("b")
    lines.AppendLine(new Leaf(items).Deep())
    lines.AppendLine(new Wrapper<string>("w").Wrapped())
    return lines.ToString()
}

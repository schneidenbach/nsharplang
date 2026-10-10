namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A MEMBER GENERATOR CALLS ITS OWN TYPE'S MEMBERS BY THEIR BARE NAMES.
//
// A `func*` member is lowered into a state machine, so its body runs with the MACHINE as argument 0
// and the instance the source wrote the member about sitting in the machine's `<>__this` field. A
// bare `Label()` there — and `this.Label()`, which is the same call spelled out — is a call on that
// captured instance: the declaring type's overloads are selected exactly as an ordinary member body
// selects them, and the receiver is `ldarg.0; ldfld <>__this` where an ordinary body loads `ldarg.0`.
// The body declined every such call as "an iterator body value could not be lowered".
class CensusCallBase {
    func Inherited(): string => "base member"
}

class CensusCallHost: CensusCallBase {
    Prefix: string
    Calls: int

    constructor(prefix: string) {
        Prefix = prefix
        Calls = 0
    }

    func Label(): string => Prefix + "label"

    func Describe(value: int): string => Prefix + "int " + value.ToString()

    func Describe(value: string): string => Prefix + "string " + value

    func Bump(): int {
        Calls = Calls + 1
        return Calls
    }

    func Record() {
        Calls = Calls + 10
    }

    static func Shared(): string => "static member"

    func quiet(): string => "namespace-private member"

    private func hidden(): string => "private member"

    private static func hiddenStatic(): string => "private static member"

    // The own member, bare and through `this`, as the yielded value itself.
    func* Labels(): IEnumerable<string> {
        yield Label()
        yield this.Label()
    }

    // Overloads selected by argument type, with arguments read from a parameter and a hoisted local.
    func* Descriptions(count: int): IEnumerable<string> {
        for i := 0; i < count; i += 1 {
            yield Describe(i)
        }
        word := "done"
        yield Describe(word)
    }

    // A member call whose result feeds a condition and an arithmetic operand, re-run on every resume
    // so each step observes the side effect of the one before.
    func* Counts(limit: int): IEnumerable<int> {
        while Bump() <= limit {
            yield Calls * 100 + Bump()
        }
    }

    // A void member called as a statement, observed through the field it wrote.
    func* Recorded(): IEnumerable<int> {
        Record()
        yield Calls
        this.Record()
        yield Calls
    }

    // An inherited member, a static member and a namespace-private (assembly-visible) member.
    func* Kinds(): IEnumerable<string> {
        yield Inherited()
        yield Shared()
        yield quiet()
    }

    // A `private` member is reachable because the machine is nested in the type that declares the
    // generator, as C# nests it; a top-level machine was refused at run time.
    func* Privately(): IEnumerable<string> {
        yield hidden()
        yield hiddenStatic()
    }

    // A lambda inside the generator runs on the machine too, so its bare member call reaches the same
    // captured instance.
    func* ThroughLambda(): IEnumerable<string> {
        read: Func<string> = () => Label()
        yield read()
        shout: Func<string, string> = text => Describe(text).ToUpper()
        yield shout("x")
    }

    // A lambda that captures the loop variable gets a per-iteration display of its own, which holds
    // the declaring instance in a field beside the capture; its member call dispatches on that.
    func* PerWord(words: string[]): IEnumerable<Func<string>> {
        for word in words {
            yield () => Describe(word)
        }
    }

    // A static generator has no instance; its bare static call is unaffected.
    static func* Statics(): IEnumerable<string> {
        yield Shared()
    }
}

// An EXTERNAL base's instance method, called bare from a generator of the derived type.
class CensusCallNames: List<string> {
    func* Presence(names: string[]): IEnumerable<bool> {
        for name in names {
            yield Contains(name)
        }
    }
}

// A STRUCT's member generator captures a COPY of the value it was called on, as C# does: its calls
// and reads see that copy, and a write to the original after the call does not reach it.
struct CensusCallPoint {
    X: int

    func Twice(): int => X * 2

    func* Values(): IEnumerable<int> {
        yield X
        yield Twice()
        yield this.Twice()
    }
}

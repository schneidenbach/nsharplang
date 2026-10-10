namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic
import System.Linq


// A DELEGATE READ OFF ANOTHER OBJECT, AND A METHOD GROUP BOUND TO ONE.
//
// Two shapes analysis accepted and emission declined:
//
//   * `h.Loader()` — invoking a delegate-typed FIELD through its owner — declined as
//     `emit.call.instance-member: instance call 'Loader' with 0 argument(s) on 'Holder'`. The
//     BARE-NAME form (`Loader()` inside the declaring type) had a tier and the qualified form had
//     none, so a handler read off any other object could not be called at all.
//   * `f: Func<string, string> = greeter.Greet` — a method group on an instance RECEIVER — declined
//     as `emit.typed-local.initializer`. The method-group tiers covered a bare name, a sibling, a
//     local function and a STATIC group named through its type; a group named through a VALUE binds
//     that value as the delegate's target and had no owner.
class Loader {
    Prefix: string

    constructor(prefix: string) {
        Prefix = prefix
    }

    func Greet(name: string): string {
        return Prefix + name
    }

    func Shout(name: string): string {
        return Prefix + name.ToUpperInvariant()
    }
}

class Base {
    func Describe(): string {
        return "base"
    }

    virtual func Name(): string {
        return "Base"
    }
}

class Derived: Base {
    override func Name(): string {
        return "Derived"
    }
}

// A HOLDER WHOSE MEMBERS ARE DELEGATES: a field, a read-only property, and a nullable field. Each is
// invoked through a receiver rather than by its bare name.
class Handlers {
    Load: Func<int>
    Map: Func<int, int>
    Sink: Action<int>
    Log: List<int> = new List<int>()

    Doubled: Func<int, int> => Map

    constructor(load: Func<int>, map: Func<int, int>, sink: Action<int>) {
        Load = load
        Map = map
        Sink = sink
    }
}

func NewHandlers(sink: List<int>): Handlers {
    // The three delegates are built at TYPED LOCALS rather than written inline at the constructor's
    // parameters: a lambda literal written directly at a source constructor's argument declines at
    // emit, which is a different owner's gap.
    load: Func<int> = () => 7
    map: Func<int, int> = value => value * 3
    sink2: Action<int> = value => {
        sink.Add(value)
    }
    return new Handlers(load, map, sink2)
}

func TotalThrough(handlers: Handlers): int {
    total := handlers.Load()
    total = total + handlers.Map(4)
    total = total + handlers.Doubled(2)
    handlers.Sink(total)
    return total
}

// THE SAME READ ONE HOP DEEPER: the receiver is itself a member read, not a local.
class HandlerBox {
    Inner: Handlers

    constructor(inner: Handlers) {
        Inner = inner
    }
}

func ThroughBox(box: HandlerBox): int {
    return box.Inner.Map(5)
}

// ── a method group named through an instance receiver ─────────────────────────────────────────
func GreeterDelegate(loader: Loader): Func<string, string> {
    greeting: Func<string, string> = loader.Greet
    return greeting
}

func ShoutDelegate(loader: Loader): Func<string, string> {
    return loader.Shout
}

func MappedThrough(loader: Loader, names: List<string>): List<string> {
    return names.Select(loader.Greet).ToList()
}

// A VIRTUAL target binds the method the RECEIVER actually has, which is what `ldvirtftn` is for.
func NameDelegate(value: Base): Func<string> {
    return value.Name
}

func DescribeDelegate(value: Base): Func<string> {
    return value.Describe
}

// A METHOD GROUP ON A RECEIVER FROM A REFERENCED ASSEMBLY, resolved by ordinary reflection rather
// than from the definition table.
func BuilderAppend(builder: System.Text.StringBuilder): Func<string, System.Text.StringBuilder> {
    return builder.Append
}

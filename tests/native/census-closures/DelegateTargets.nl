namespace NSharpLang.CensusClosures.Tests

import System

// A METHOD GROUP, OR A DELEGATE VALUE, WHERE THE PARAMETER IS `Delegate` ITSELF.
//
// `Delegate` has no `Invoke`, so the position says nothing about the delegate to build. C# 10 gives a
// method group a NATURAL FUNCTION TYPE — `Func<...>` / `Action<...>` inferred from its one method's
// signature — and converts that to the target by reference conversion. `d as Delegate` is a plain
// reference conversion of a delegate that already exists. This is the `app.MapGet("/x", Handler)`
// shape: the framework takes a `Delegate` and inspects it.
class Handlers {
    static func Twice(n: int): int {
        return n * 2
    }

    static func Ping() {
    }

    func Scale(n: int): int {
        return n * Factor
    }

    Factor: int

    constructor(factor: int) {
        Factor = factor
    }
}

func NameOf(d: Delegate): string {
    return d.Method.Name
}

func Invoke(d: Delegate, arg: object): int {
    return Convert.ToInt32(d.DynamicInvoke([arg]))
}

func Triple(n: int): int {
    return n * 3
}

func ReadParameterCount(d: Delegate): int {
    return d.Method.GetParameters().Length
}

func StaticGroupName(): string {
    return NameOf(Handlers.Twice)
}

func StaticGroupResult(): int {
    return Invoke(Handlers.Twice, 21)
}

func SiblingGroupResult(): int {
    return Invoke(Triple, 5)
}

func InstanceGroupResult(): int {
    handlers := new Handlers(4)
    return Invoke(handlers.Scale, 5)
}

func VoidGroupParameterCount(): int {
    return ReadParameterCount(Handlers.Ping)
}

func AsDelegateResult(): int {
    f: Func<int, int> = n => n + 1
    return Invoke(f as Delegate, 9)
}

func TypedLocalResult(): int {
    f: Func<int, int> = Handlers.Twice
    return Invoke(f, 8)
}

func NameOfMulticast(d: MulticastDelegate): string {
    return d.Method.Name
}

func MulticastGroupName(): string {
    return NameOfMulticast(Handlers.Twice)
}

func FrameworkGroupName(): string {
    return NameOf(Guid.NewGuid)
}

// A captured delegate VALUE that shares a free function's name is the value, not the group.
func Quadruple(n: int): int {
    return n * 4
}

func ShadowedByParameter(Quadruple: Func<int, int>): string {
    probe: Func<string> = () => NameOf(Quadruple)
    return probe()
}

func ShadowedByBoxedParameter(Quadruple: Func<int, int>): string {
    probe: Func<string> = () => {
        Quadruple = Handlers.Twice
        return NameOf(Quadruple)
    }
    return probe()
}

func ShadowedInsideLambdaName(): string {
    handler: Func<int, int> = Handlers.Twice
    return ShadowedByParameter(handler)
}

func ShadowedBoxedInsideLambdaName(): string {
    handler: Func<int, int> = Triple
    return ShadowedByBoxedParameter(handler)
}

// N# diagnoses the bare collision, so this explicit receiver pins the captured instance value.
class DelegateFieldShadow {
    Quadruple: Func<int, int>

    constructor() {
        Quadruple = Handlers.Twice
    }

    func Read(): string {
        probe: Func<string> = () => NameOf(this.Quadruple)
        return probe()
    }
}

func ShadowedEnclosingInstanceField(): string {
    owner := new DelegateFieldShadow()
    return owner.Read()
}

class Animal {
    virtual func Sound(): string {
        return "generic"
    }
}

class Dog: Animal {
    override func Sound(): string {
        return "bark"
    }
}

func InvokeText(d: Delegate): string {
    return must (d.DynamicInvoke(new object[](0)) as string)
}

// A virtual method group binds the runtime method the receiver has.
func VirtualGroupResult(): string {
    pet: Animal = new Dog()
    return InvokeText(pet.Sound)
}

// BETTER CONVERSION: a concrete delegate parameter beats `Delegate`, and `MulticastDelegate` beats it too.
func Pick(d: Delegate): string {
    if d == null {
        return "null"
    }
    return "delegate"
}

func Pick(f: Func<int, int>): string {
    if f == null {
        return "null"
    }
    return "func"
}

func Which(d: Delegate): string {
    if d == null {
        return "null"
    }
    return "delegate"
}

func Which(m: MulticastDelegate): string {
    if m == null {
        return "null"
    }
    return "multicast"
}

func PickFunc(): string {
    return Pick(Triple)
}

func PickDelegateValue(): string {
    d: Delegate = Triple
    return Pick(d)
}

func WhichMulticast(): string {
    return Which(Triple)
}

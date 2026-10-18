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

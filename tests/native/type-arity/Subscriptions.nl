namespace NSharpLang.TypeArity.Tests


// TWO TYPES, ONE NAME. On the CLR these are `Subscription` and `Subscription``1 — different types
// that may live side by side in one assembly, which is what every other .NET language expects and
// what a C# consumer of an N# library will see.
class Subscription {
}

class Subscription<T>: Subscription {
    Value: T

    constructor(value: T) {
        Value = value
    }
}

func MakeSubscription(): Subscription {
    return new Subscription<int>(7)
}

func MakeTypedSubscription(): Subscription<int> {
    return new Subscription<int>(9)
}

func MakePlainSubscription(): Subscription {
    return new Subscription()
}

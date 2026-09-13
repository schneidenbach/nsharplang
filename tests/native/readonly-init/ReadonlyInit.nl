namespace NSharpLang.ReadonlyInit.Tests

// Fixture types for field-initialization placement. A field initializer (`readonly Pi = 3.14159`) is
// parsed into a synthesized initializer constructor whose stores are emitted INLINE in every
// base-reaching constructor, ahead of the base constructor call — the C# order, and the only order an
// initonly store and an uninitialized `this` both allow. Each type below pins one placement shape; the
// .tests.nl file executes them, proves no `<InitializeFields>$` helper is emitted, and verifies the
// readonly attribute and initialized values.

// Readonly-only, no user constructor: the synthesized DEFAULT constructor inlines both initonly stores.
class ReadonlyOnly {
    readonly Pi: double = 3.14159
    readonly Label: string = "ro"
}

// Mutable-only initializers: inlined in the synthesized default constructor like every other store.
class MutableOnly {
    Count: int = 5
    Name: string = "m"
}

// Mixed: both the readonly and the mutable store are inlined in the constructor.
class Mixed {
    readonly Ro: int = 1
    Mut: int = 2
}

// Static readonly initializer runs in the type initializer (.cctor — itself a constructor, so verifiable);
// the instance readonly initializer inlines in the instance constructor.
class StaticAndInstance {
    static readonly Shared: int = 99
    readonly Local: double = 2.5

    constructor() {
    }
}

// The RecordsAndInterfaces.Circle shape: a readonly field with an initializer plus a readonly field the
// explicit constructor assigns. The initializer inlines ahead of the user body; both stores land in .ctor.
class ExplicitCtor {
    readonly Radius: double
    readonly Pi: double = 3.14159

    constructor(radius: double) {
        Radius = radius
    }

    func Area(): double {
        return Pi * Radius * Radius
    }
}

// Multiple constructors: the readonly initializer must inline in EACH constructor path.
class MultiCtor {
    readonly Base: int = 100
    Value: int

    constructor(v: int) {
        Value = v
    }

    constructor() {
        Value = 0
    }
}

// A `: this(...)` delegating constructor must NOT re-run the field initializer — the delegated-to
// constructor already ran it. Only the base-reaching constructor initializes Tag.
class ThisChained {
    readonly Tag: int = 42
    X: int

    constructor(x: int) {
        X = x
    }

    constructor(): this(9) {
    }
}

// Inheritance with implicit base chaining: each type inlines its OWN readonly initializer in its own ctor.
class Animal {
    readonly Legs: int = 4
}

class Dog: Animal {
    readonly Name: string = "Rex"
}

// Explicit `: base(...)` chaining: the base ctor sets its own readonly + a body field; the derived ctor
// chains to it and then inlines the derived readonly initializer.
class Shape {
    readonly Sides: int = 3
    Kind: string

    constructor(kind: string) {
        Kind = kind
    }
}

class Triangle: Shape {
    readonly Color: string = "red"

    constructor(): base("triangle") {
    }
}

// A record with a readonly field initializer: the object-initializer path uses the synthesized (primary)
// default constructor, which inlines the readonly store.
record Tagged {
    Id: int
    readonly Kind: string = "default"
}

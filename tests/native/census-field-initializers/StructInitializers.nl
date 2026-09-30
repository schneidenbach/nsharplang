namespace NSharpLang.CensusFieldInitializers.Tests


// A struct's instance field initializers run at the start of each of its DECLARED constructors —
// the same placement a class's take, minus the base call a value type does not have. The values
// that reach no constructor keep the CLR zero, which is why the rule asks for a constructor at all.
struct Measured {
    Scale: int = 3 + 4
    Label: string = "a" + "b"
    Value: int

    constructor(value: int) {
        Value = value
    }
}

// A PRIMARY constructor counts: the parameter captures and the computed initializer both run in it.
struct Sized(width: int, height: int) {
    Width: int = width
    Area: int = width * height
    Doubled: int = 2 * 5
}

// A record struct behaves the same way.
record struct Span2D(length: int) {
    Length: int = length
    Doubled: int = length * 2
}

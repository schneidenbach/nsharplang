namespace NSharpLang.TypeArity.Tests


// The same rule over VALUE types, and over a name declared at three arities: a struct `Cell`, a
// struct `Cell<T>` and a struct `Cell<TKey, TValue>` are three types.
struct Cell {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

struct Cell<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }
}

struct Cell<TKey, TValue> {
    Key: TKey
    Value: TValue

    constructor(key: TKey, value: TValue) {
        Key = key
        Value = value
    }
}

func MakeCell(): Cell {
    return new Cell(1)
}

func MakeCellOfInt(): Cell<int> {
    return new Cell<int>(2)
}

func MakeCellOfIntAndString(): Cell<int, string> {
    return new Cell<int, string>(3, "three")
}

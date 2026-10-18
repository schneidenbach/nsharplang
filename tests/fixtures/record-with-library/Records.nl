namespace NSharpLang.RecordWith.Library

// Records declared in a DIFFERENT project from the code that copies them with `with`: the copy
// and the writes are decided from this assembly's metadata, not from a source definition.
record Status {
    State: string
    Gate: string?
}

record Reading {
    Latitude: double?
    Name: string
    Count: int
}

record struct Pair {
    Left: int
    Right: int
}

// A record whose copied members are a camelCase FIELD and an `init`-only property.
record Slot {
    size: int
    init Label: string
}

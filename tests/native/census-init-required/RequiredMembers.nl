namespace NSharpLang.CensusInitRequired.Tests

import System.Diagnostics.CodeAnalysis


// The shape the docs promise: a creation must name every `required` member.
class User {
    required Id: string
    required Name: string
    Email: string = ""
}

// A `required` PROPERTY, with its own accessors, carries the same metadata a required field does.
class Endpoint {
    host: string = ""

    required Host: string {
        get {
            return host
        }
        set {
            host = value
        }
    }

    Port: int = 0
}

// `[SetsRequiredMembers]` is the constructor's promise to set them itself, and it is what lets a
// creation that names nothing be legal.
class Preset {
    required Kind: string
    Weight: int = 0

    [SetsRequiredMembers]
    constructor(kind: string) {
        Kind = kind
    }

    func Describe(): string {
        return Kind
    }
}

// A required member declared on a base type is demanded of a derived type's creations too.
class Node {
    required Key: string
}

class Leaf: Node {
    Payload: int = 0
}

// A required member on a value type.
struct Sample {
    required Value: int
    Weight: int
}

class Animal {
}
class Dog: Animal {
}
class Poodle: Dog {
}

class SpecificPreset {
    required Kind: string

    constructor(value: Animal) {
        Kind = "animal"
    }

    [SetsRequiredMembers]
    constructor(value: Dog) {
        Kind = "dog"
    }
}

class NumericPreset {
    required Kind: string

    [SetsRequiredMembers]
    constructor(value: long) {
        Kind = "long"
    }

    constructor(value: float) {
        Kind = "float"
    }
}

struct RequiredPacket<T> {
    required Value: T

    [SetsRequiredMembers]
    constructor(value: T) {
        Value = value
    }
}

record RequiredReceipt {
    required Code: string

    [SetsRequiredMembers]
    constructor(code: string) {
        Code = code
    }
}

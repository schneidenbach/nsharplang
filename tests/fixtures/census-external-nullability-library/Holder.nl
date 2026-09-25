namespace Census.Nullability

// THE SIGNATURES `tests/native/census-external-nullability` REACHES FROM ANOTHER ASSEMBLY.
//
// Every position here states its nullability in source, and the emitter writes it into metadata as
// `NullableAttribute`. The native project analyses one consumer twice -- with this file in the SAME
// project, and against this project's built assembly -- and the two must report the same NL202s.
// `tests/native/census-safe-casts` does the same with consumers that reach these classes through `as`.
class Node {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

class Holder {
    Child: Node?
    Label: string?

    constructor(child: Node?, label: string?) {
        Child = child
        Label = label
    }

    func Find(): Node? {
        return Child
    }

    static func Take(node: Node): int {
        return node.Name.Length
    }

    static func TakeMaybe(node: Node?): int {
        return node == null ? 0 : node.Name.Length
    }

    static func TakeText(text: string): int {
        return text.Length
    }
}

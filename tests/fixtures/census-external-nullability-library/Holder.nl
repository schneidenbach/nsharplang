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

    // THE THREE BY-REF DIRECTIONS. An `out` is written by the call, a `ref` is read and written, and an
    // `in` is read through a reference the callee cannot write.
    static func TryFind(key: string, out found: Node): bool {
        found = new Node(key)
        return key.Length > 0
    }

    // An OVERLOAD of the same name and arity: the out argument must not cost the call its candidates.
    static func TryFind(key: int, out found: Node): bool {
        found = new Node(key.ToString())
        return key > 0
    }

    func TryFindHere(key: string, out found: Node): bool {
        found = new Node(key)
        return Child != null
    }

    static func TryFindMaybe(key: string, out found: Node?): bool {
        found = null
        return key.Length == 0
    }

    static func Replace(ref node: Node) {
        node = new Node(node.Name + "!")
    }

    static func ReplaceMaybe(ref node: Node?) {
        if node != null {
            node = null
        }
    }

    static func Peek(in node: Node): int {
        return node.Name.Length
    }
}

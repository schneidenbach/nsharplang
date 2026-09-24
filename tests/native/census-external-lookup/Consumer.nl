namespace Census.Lookup.Consumer

import System.Collections.Generic
// THE IMPORTS ARE THE FIXTURE. Each supplies a `TypeInfo` — `System.Reflection.TypeInfo` from the
// framework and a source `Census.Lookup.Rival.TypeInfo` — and NEITHER wins: the enclosing namespace's
// `Census.Lookup.TypeInfo`, from a referenced assembly, is nearer than any import. NL010 is right that
// nothing binds through them; deleting them would delete the rivals these contracts are about.
// nlc:ignore NL010
import System.Reflection
// nlc:ignore NL010
import Census.Lookup.Rival


// Every position a bare or relatively qualified name can be written in, bound to the enclosing
// namespace's referenced-assembly types. The companion tests execute the bindings and read them back
// out of the emitted metadata.
class Consumers {
    static func Describe(info: TypeInfo): string {
        return info.Side()
    }

    static func Make(): TypeInfo {
        return TypeInfo.Make()
    }

    static func Fresh(): TypeInfo {
        return new TypeInfo()
    }

    static func Collect(): List<TypeInfo> {
        items := new List<TypeInfo>()
        items.Add(new TypeInfo())
        return items
    }

    static func IsLookup(value: object): bool {
        return value is TypeInfo
    }

    static func NodeKind(node: Ast.Node): string {
        return node.Kind()
    }

    static func FreshNode(): Ast.Node {
        return new Ast.Node()
    }

    static func LeftWho(widget: Left.Widget): string {
        return widget.Who()
    }

    static func RightWho(): string {
        return new Right.Widget().Who()
    }
}

// A base class named by its bare name, from the enclosing namespace's referenced assembly.
class Derived: Base {
    func Twice(): string {
        return Kind() + Kind()
    }
}

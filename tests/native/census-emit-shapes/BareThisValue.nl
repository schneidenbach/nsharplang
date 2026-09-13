namespace NSharpLang.CensusEmitShapes.Tests

import System

// `this` WRITTEN ON ITS OWN, as a value rather than as the `this.Member` prefix. Until this shape
// emitted, every declaration containing one declined at `parse.struct` — including the canonical
// .NET event raise, `Changed?.Invoke(this, EventArgs.Empty)`, whose first argument IS a bare `this`.
class Node {
    Label: string
    Next: Node?

    constructor(label: string) {
        Label = label
        Next = null
    }

    // The plainest form: an instance handing itself back.
    func Self(): Node {
        return this
    }

    // `this` as a call ARGUMENT, which is the shape an event's `sender` takes.
    func Describe(): string {
        return NodeLabelOf(this)
    }

    // `this` bound to a local, then read through it.
    func SelfThroughLocal(): string {
        me := this
        return me.Label
    }

    // `this` widened into an `object` parameter.
    func AsObject(): object {
        return BoxedOf(this)
    }

    // `this` written inside a LAMBDA body. A body that names nothing else is still a THIS-capturing
    // lambda, so it is placed as a private instance method on this type rather than as a static one.
    func LabelThroughLambda(): string {
        return ApplyToString(() => NodeLabelOf(this))
    }

    func LinkTo(next: Node): Node {
        Next = next
        return this
    }
}

func NodeLabelOf(node: Node): string {
    return node.Label
}

func ApplyToString(read: Func<string>): string {
    return read()
}

func BoxedOf(value: object): object {
    return value
}

// A VALUE TYPE'S argument zero is a managed POINTER to the instance, so a bare `this` in a struct
// body is a dereference rather than a load, and what it produces is a COPY.
struct Tally {
    Count: int

    func Snapshot(): Tally {
        return this
    }

    func Bumped(): Tally {
        copy := this
        copy.Count = copy.Count + 1
        return copy
    }
}

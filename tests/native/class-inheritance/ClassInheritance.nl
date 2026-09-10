namespace NSharpLang.ClassInheritance.Tests

// ABSTRACT, VIRTUAL AND OVERRIDE ON CLASSES THE PROGRAM ITSELF DECLARES.
//
// Overriding an EXTERNAL base's member has worked for a while (tests/native/external-abstract-override):
// the base is a baked `Type`, so Reflection can be asked what it declares. A base being emitted
// ALONGSIDE its subclass cannot answer that question — its `TypeBuilder` is unbaked and reports no
// methods at all — so every `override` of a member declared in the same compilation was refused with
// `emit.declaration.override-target`, and `abstract func` did not even parse (`parse.struct`), because
// the member scan demanded a body every managed member was assumed to have.
//
// These types are compiled by the real columnar pipeline, so their mere existence is half the proof.
// The other half is in the tests, which CALL them through the base type: a subclass that emitted a
// method into a NEW slot instead of the base's would build and still answer the base's implementation.

// The root of the chain. `abstract` on the class, one abstract member with no body, one virtual member
// with one.
abstract class Shape {
    readonly name: string

    constructor(name: string) {
        this.name = name
    }

    Name: string => name

    abstract func Area(): int

    virtual func Describe(): string {
        return "shape"
    }
}

// The ordinary override: both members, one of them `sealed` so no further subclass may take the slot.
class Square: Shape {
    readonly side: int

    constructor(side: int): base("square") {
        this.side = side
    }

    override func Area(): int {
        return side * side
    }

    sealed override func Describe(): string {
        return "square"
    }
}

// DECLARED BEFORE ITS BASE. Source order says nothing about which of two classes is the base, so the
// declaration pass orders types by inheritance depth; written the other way round, this class would ask
// a base that had not declared anything yet.
class Circle: Rounded {
    constructor(radius: int): base(radius) {
    }

    override func Area(): int {
        return 3 * Radius * Radius
    }
}

// An abstract class in the MIDDLE of the chain: it overrides one member and leaves the other abstract
// for its own subclasses, which is only legal because it is itself abstract.
abstract class Rounded: Shape {
    readonly radius: int

    constructor(radius: int): base("rounded") {
        this.radius = radius
    }

    Radius: int => radius

    override func Describe(): string {
        return "rounded"
    }
}

// A GENERIC SUBCLASS of a non-generic base.
class Tagged<T>: Shape {
    readonly tag: T

    constructor(tag: T): base("tagged") {
        this.tag = tag
    }

    Tag: T => tag

    override func Area(): int {
        return 0
    }

    override func Describe(): string {
        return "tagged"
    }
}

// A GENERIC BASE, with the abstract member's signature mentioning the type parameter, and a subclass
// that closes it over a concrete type.
abstract class Box<T> {
    readonly value: T

    constructor(value: T) {
        this.value = value
    }

    Value: T => value

    abstract func Render(): string

    virtual func Kind(): string {
        return "box"
    }
}

class StringBox: Box<string> {
    constructor(value: string): base(value) {
    }

    override func Render(): string {
        return "string-box-render"
    }

    override func Kind(): string {
        return "string-box"
    }
}

// A GENERIC SUBCLASS OF A GENERIC BASE, passing its own type parameter through.
class PairBox<T>: Box<T> {
    readonly other: T

    constructor(value: T, other: T): base(value) {
        this.other = other
    }

    Other: T => other

    override func Render(): string {
        return "pair"
    }
}

// The call sites. Every one of these dispatches through the STATICALLY DECLARED base type, so the
// answer is decided by the emitted vtable and not by the compiler's view of the receiver.
class Dispatch {
    static func AreaOf(shape: Shape): int {
        return shape.Area()
    }

    static func DescribeOf(shape: Shape): string {
        return shape.Describe()
    }

    static func NameOf(shape: Shape): string {
        return shape.Name
    }

    static func RenderOf(box: Box<string>): string {
        return box.Render()
    }

    static func KindOf(box: Box<string>): string {
        return box.Kind()
    }
}

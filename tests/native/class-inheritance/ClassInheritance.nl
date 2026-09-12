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

// `base.Member` — THE MEMBER THE BASE DECLARES, REACHED FROM CODE THAT REPLACED IT.
//
// An override that wants the implementation it replaced has exactly one way to say so, and the CLR
// gives it exactly one instruction: a NON-VIRTUAL `call` on a virtual method. Every other dispatch in
// this file is `callvirt`, so this is the one shape where getting it wrong does not produce a wrong
// answer — it produces infinite recursion, because a virtual `base.Render()` inside `Render` calls
// itself. That is why the chain below is THREE levels deep and each level wraps the one under it:
// the string that comes back names every level exactly once, in order, which no virtually dispatched
// version of the same source can produce.
abstract class Layer {
    readonly depth: int

    constructor(depth: int) {
        this.depth = depth
    }

    Depth: int => depth

    Label: string => "layer"

    virtual func Render(): string {
        return "root"
    }

    virtual func Wrap(text: string): string {
        return "[" + text + "]"
    }
}

class MiddleLayer: Layer {
    constructor(): base(1) {
    }

    override func Render(): string {
        return "middle(" + base.Render() + ")"
    }

    // A base call WITH arguments, so the receiver is argument zero and the written argument is
    // argument one rather than the only one.
    override func Wrap(text: string): string {
        return "m" + base.Wrap(text)
    }

    // `base.` from a method that overrides NOTHING: the word is about where the lookup starts, not
    // about being inside an override.
    func BaseLabel(): string {
        return base.Label
    }

    func BaseDepth(): int {
        return base.Depth
    }
}

class LeafLayer: MiddleLayer {
    constructor(): base() {
    }

    // The direct base is `MiddleLayer`, whose own `Render` calls ITS base. One virtual dispatch here
    // would never terminate.
    override func Render(): string {
        return "leaf(" + base.Render() + ")"
    }

    // `base.` from the LEAF reaches a member the DIRECT base does not declare either: `Label` is
    // `Layer`'s, two levels up, and the lookup walks the chain from the direct base outwards exactly
    // as an unqualified name does from the type itself.
    func BaseLabelFromLeaf(): string {
        return base.Label
    }
}

// A SUBCLASS OF A CLOSED GENERIC BASE. `base.Kind()` names `Box<string>`'s implementation, which is
// the open definition's method rebound onto the closed type.
class LoudBox: StringBox {
    constructor(value: string): base(value) {
    }

    override func Kind(): string {
        return base.Kind() + "!"
    }
}

// A BASE THAT IS NOT IN THIS COMPILATION AT ALL. `System.Object` is every class's base when none is
// written, and its members are ordinary runtime instance members reached the same way.
class RootedOnObject {
    readonly key: int

    constructor(key: int) {
        this.key = key
    }

    func BaseText(): string? {
        return base.ToString()
    }

    func BaseHash(): int {
        return base.GetHashCode()
    }
}

// The base-call sites, called through the statically declared base type exactly as `Dispatch` is.
class LayerDispatch {
    static func RenderOf(layer: Layer): string {
        return layer.Render()
    }

    static func WrapOf(layer: Layer, text: string): string {
        return layer.Wrap(text)
    }
}

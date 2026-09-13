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

// A BASE FROM A REFERENCED ASSEMBLY, CALLED WITH ARGUMENTS. `: base(...)` used to require a base that
// THIS compilation was building — the chain was resolved among the base's source constructor rows —
// so every class deriving from an external base with a parameterised constructor declined at
// `emit.ctor.base-chain-without-base`. The base's constructors are now read from its metadata and
// selected by the same rule.
class SizedList: System.Collections.Generic.List<string> {
    constructor(capacity: int): base(capacity) {
    }
}

class SeededList: System.Collections.Generic.List<string> {
    constructor(seed: System.Collections.Generic.IEnumerable<string>): base(seed) {
    }
}

class LayerError: System.Exception {
    Layer: string

    constructor(message: string): base(message) {
        Layer = ""
    }

    constructor(message: string, inner: System.Exception): base(message, inner) {
        Layer = ""
    }
}

// THE CHAIN IS CHOSEN BY THE ARGUMENTS, NOT BY ARITY ALONE. `Dictionary<string, int>` declares four
// one-argument constructors, and only the argument's type says which of them `base(...)` names.
class ComparedMap: System.Collections.Generic.Dictionary<string, int> {
    constructor(comparer: System.Collections.Generic.IEqualityComparer<string>): base(comparer) {
    }

    constructor(capacity: int, comparer: System.Collections.Generic.IEqualityComparer<string>): base(capacity, comparer) {
    }
}

// THE MEMBERS A SOURCE TYPE INHERITS FROM A BASE THIS COMPILATION DID NOT WRITE.
//
// A `:` clause naming a referenced type states a fact about the derived type: a `Names` IS a
// `List<string>`, so every member `List<string>` declares is a member `Names` has, with the base's
// type arguments already substituted. Reading that fact needs the SAME walk in four places, and each
// of them used to stop at the last SOURCE link of the chain:
//
//   * the analyzer's CLR binding, whose surrogate for any N#-declared type was `object` — so the
//     receiver contributed no binding for `T` and `names.Add("a")` reported NL402 while PRINTING
//     `Add(string item)` as the overload it could not match;
//   * emission's member walk, which answered no property and no indexer past the source chain;
//   * emission's ordinary call resolution, which is where a call with a LAMBDA or with EXPLICIT TYPE
//     ARGUMENTS lands;
//   * the conversion relation, which knew nothing of the interfaces the external base implements.
//
// The types below are the shapes those four answer for. Their members are exercised at RUNTIME by
// the tests, because a member that binds and emits the wrong `MethodInfo` still compiles.
class Names: System.Collections.Generic.List<string> {

    // An inherited member read WITHOUT a receiver is `this.Name`, and it resolves through the same
    // walk as an explicit receiver does.
    func Summary(): string {
        return Count.ToString() + " names"
    }

    // ...and `this.` and `base.` name the same inherited member, dispatched the two ways the CLR
    // distinguishes.
    func ExplicitCount(): int {
        return this.Count
    }

    func BaseCount(): int {
        return base.Count
    }
}

// DEPTH THREE: source ← source ← external. Neither derived link has a CLR base the runtime can be
// asked for while the builders are open, so the walk is the DECLARED chain rather than the reflected
// one.
class DeeperNames: Names {
}

// A GENERIC EXTERNAL BASE WITH TWO ARGUMENTS, so a member typed in the second one proves the
// substitution is by position rather than by luck.
class Counts: System.Collections.Generic.Dictionary<string, int> {
}

// An external base whose own members are the ones a derived type overrides, read unqualified from
// inside the override itself.
class TaggedError: System.Exception {
    Tag: string

    constructor(tag: string, message: string): base(message) {
        Tag = tag
    }

    override func ToString(): string {
        return Tag + ":" + Message
    }
}

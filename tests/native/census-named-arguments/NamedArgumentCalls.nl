namespace NSharpLang.CensusNamedArguments

import System
import System.Collections.Generic
import NSharpLang.CensusNamedArguments.MetadataDefaults

// A source declaration with the framework type's short name proves that explicit generic static
// lowering retains the source owner selected by semantic lookup.
class Array {
    static func Empty<T>(): string[] {
        return ["source"]
    }
}

[Obsolete(error: true, message: "named attribute", DiagnosticId = "named-id")]
class NamedAttributeTarget {
}

class SparseAttribute: Attribute {
    First: int
    Middle: int
    Last: int

    constructor(first: int = 1, middle: int = 2, last: int = 3) {
        First = first
        Middle = middle
        Last = last
    }
}

[Sparse(last: 9)]
class SparseAttributeTarget {
}

// The declarations every named-argument contract beside this file is written against. A named
// argument names a PARAMETER, so what matters about each of these is the spelling of its parameter
// list and nothing else: the tests write the same calls with the names in the declared order, out of
// it, and mixed with positional arguments, and assert the call ran the way the names say.

// The shape the census reproduced from the converted Language Server: a free function whose single
// parameter is written by name at the call (`G(flag: true)`).
func Gate(flag: bool): int {
    if flag {
        return 1
    }

    return 0
}

func Divide(numerator: int, denominator: int): int {
    return numerator / denominator
}

func GenericFirst<T>(first: T, second: T): T {
    _ = second
    return first
}

func GenericOptional<T>(first: T, second: int = 2): T {
    _ = second
    return first
}

func GenericOptionalOrder<T>(value: T, extra: int = 42): int {
    _ = value
    return extra
}

func GenericSet<T>(value: T, ref target: T): T {
    target = value
    return target
}

func GenericSetOut<T>(out target: T, value: T) {
    target = value
}

func GenericParams<T>(seed: T, params values: int[]): T {
    _ = values.Length
    return seed
}

func GenericParamsCount<T>(seed: T, params values: int[]): int {
    _ = seed
    return values.Length
}

class GenericSeedCounter {
    Count: int

    func Next(): int {
        Count = Count + 1
        return 40
    }

    func NextOrdinal(): int {
        Count = Count + 1
        return Count
    }
}

class GenericNamedRecorder {
    Value: int
    Order: List<string>

    constructor() {
        Value = 1
        Order = new List<string>()
    }

    func AddressValue(): int {
        Order.Add("value")
        Value = 9
        return 42
    }

    func Set(): int {
        return GenericSet<int>(target: ref Value, value: AddressValue())
    }
}

class GenericNamedOwner<T> {
    Order: List<string>

    constructor() {
        Order = new List<string>()
    }

    func NoteValue(name: string, value: int): int {
        Order.Add(name)
        return value
    }

    func NoteOwner(name: string, value: T): T {
        Order.Add(name)
        return value
    }

    func Pick<U>(owner: T, value: U, extra: int = 2): U {
        _ = owner
        _ = extra
        return value
    }

    func Choose<U>(owner: T, value: U): int {
        _ = owner
        _ = value
        return 1
    }

    func Choose<U>(owner: T, value: U, extra: int = 2): int {
        _ = owner
        _ = value
        _ = extra
        return 2
    }

    func OptionalOrder<U>(value: U, extra: int = 42): int {
        _ = value
        return extra
    }

    func Pack<U>(owner: T, params values: U[]): int {
        _ = owner
        return values.Length
    }

    static func StaticPick<U>(owner: T, value: U, extra: int = 2): U {
        _ = owner
        _ = extra
        return value
    }

    static func StaticChoose<U>(owner: T, value: U, extra: int = 2): int {
        _ = owner
        _ = value
        _ = extra
        return 2
    }

    static func StaticChoose<U>(owner: T, value: U): int {
        _ = owner
        _ = value
        return 1
    }

    static func StaticOptionalOrder<U>(value: U, extra: int = 42): int {
        _ = value
        return extra
    }
}

// Two parameters of the SAME type, which is the case a name is actually load-bearing for: nothing
// but the name distinguishes `Between(low: 1, high: 9)` from its reverse.
func Between(value: int, low: int, high: int): bool {
    return value >= low && value <= high
}

// A trailing default beside a named argument: `Indent(text: "x")` names the first parameter and
// leaves the second to its declaration.
func Indent(text: string, width: int = 2): string {
    return new string(' ', width) + text
}

func OptionalSlots(first: int = 1, middle: int = 2, last: int = 3): int {
    return first * 100 + middle * 10 + last
}

// THE EVALUATION-ORDER PROBE. Each call records the name it was given before answering, so a test
// can read back the order the arguments actually ran in -- which is the order they were WRITTEN,
// whatever order the signature keeps them in.
class CallRecorder {
    Order: List<string>

    constructor() {
        Order = new List<string>()
    }

    func Note(name: string, value: int): int {
        Order.Add(name)
        return value
    }
}

class Label {
    Text: string
    Width: int

    constructor(text: string, width: int) {
        Text = text
        Width = width
    }

    // A second constructor with a trailing default, reached by naming only the first parameter.
    constructor(text: string) {
        Text = text
        Width = text.Length
    }

    func Render(prefix: string, suffix: string): string {
        return prefix + Text + suffix
    }

    static func Of(text: string, width: int): Label {
        return new Label(text, width)
    }
}

class NamedOverloadPicker {
    func Pick(left: object, right: string): string {
        return left.ToString() + right + "first"
    }

    func Pick(right: string, left: int): string {
        return right + left.ToString() + "second"
    }
}

class OptionalConstructorSlots {
    Value: int

    constructor(first: int = 1, middle: int = 2, last: int = 3) {
        Value = first * 100 + middle * 10 + last
    }
}

class OptionalMethodSlots {
    func Read(first: int = 1, middle: int = 2, last: int = 3): int {
        return first * 100 + middle * 10 + last
    }
}

class OptionalStaticSlots {
    static func Read(first: int = 1, middle: int = 2, last: int = 3): int {
        return first * 100 + middle * 10 + last
    }
}

class SourceOptionalBase {
    func Pick(first: int = 1, second: int = 2): string {
        return first.ToString() + second.ToString() + "base"
    }
}

class SourceOptionalDerived: SourceOptionalBase {
    func Pick(first: int = 1, second: int = 2): string {
        return first.ToString() + second.ToString() + "derived"
    }
}

// A delegate parameter named at the call, which reaches emission through a different argument arm
// than an ordinary value does.
func ApplyTwice(value: int, mapper: Func<int, int>): int {
    return mapper(mapper(value))
}

func InvokeNamed(value: int, mapper: Func<int, int>): int {
    return mapper(arg: value)
}

func InvokeActionNamed(value: int, action: Action<int>) {
    action(obj: value)
}

func InvokeComparisonNamed(left: int, right: int, comparison: Comparison<int>): int {
    return comparison(y: right, x: left)
}

class DelegateArgumentRecorder {
    Value: int

    func Record(value: int) {
        Value = value
    }
}

func ReadParams(params values: int[]): int {
    return values[0] * 10 + values[1]
}

class SparseConstructorOrderRecorder {
    Value: int

    constructor() {
        Value = 4
    }

    func Build(): ReflectedSparseRefConstructor {
        return new ReflectedSparseRefConstructor(target: ref Value, last: Mutate())
    }

    func Mutate(): int {
        Value = 9
        return 7
    }
}

class SourceSparseOutConstructor {
    Value: int

    constructor(out target: int, middle: int = 2, last: int = 3) {
        target = middle * 10 + last
        Value = target
    }
}

// An `out` parameter named at the call: the name prefixes the whole argument, modifier included.
func TryHalve(value: int, out half: int): bool {
    half = value / 2
    return value % 2 == 0
}

class ReceiverOrderRecorder {
    Order: List<string>

    constructor() {
        Order = new List<string>()
    }

    func Receiver(): string {
        Order.Add("receiver")
        return "a,b"
    }

    func Argument(name: string, value: string): string {
        Order.Add(name)
        return value
    }
}

class ReorderedOutAlias {
    Value: int

    constructor() {
        Value = 0
    }

    func Parse(): bool {
        return Int32.TryParse(result: out Value, s: MutateThenText())
    }

    func MutateThenText(): string {
        Value = 9
        return "42"
    }
}

class SourceThisChain {
    Value: int

    constructor(first: int = 1, middle: int = 2, last: int = 3) {
        Value = first * 100 + middle * 10 + last
    }

    constructor(marker: string): this(last: 9, first: 2) {
    }
}

class SourceBaseChain: OptionalConstructorSlots {
    constructor(): base(last: 8, first: 4) {
    }
}

class ReflectedBaseChain: ReflectedChainBase {
    constructor(): base(last: 7, first: 5) {
    }
}

// ---- THE SAME OPTIONAL SLOTS, REACHED WITHOUT WRITING A SINGLE NAME ---------------------------
//
// Filling an omitted optional was only ever reachable behind a NAME: the planner entered the
// sparse tier when a call wrote a named argument the ordinary placement could not use. A purely
// POSITIONAL call that simply stopped early never got there, and a source declaration is selected
// by exact parameter count, so `Make("a")` against `Make(a: string, d: string? = null)` declined in
// the SAME compilation while the identical omission through an assembly reference already bound.
// These declarations are read positionally, with a trailing tail left out.
class PositionalDefaultRecorder {
    Order: List<string>

    constructor() {
        Order = new List<string>()
    }

    func Note(name: string, value: int): int {
        Order.Add(name)
        return value
    }

    func Seen(): string {
        return string.Join(",", Order)
    }
}

func PositionalTail(first: int, middle: int = 20, last: int = 300): int {
    return first * 10000 + middle * 100 + last
}

func PositionalNullableTail(a: string, d: string? = null): string {
    return a + (d ?? "-")
}

func PositionalAllDefaults(x: int = 1, y: int = 2): int {
    return x * 10 + y
}

class PositionalDefaultOwner {
    Tag: string

    constructor(tag: string) {
        Tag = tag
    }

    func Read(first: int, middle: int = 20, last: int = 300): string {
        return Tag + (first * 10000 + middle * 100 + last).ToString()
    }

    static func ReadStatic(first: int, middle: int = 20, last: int = 300): int {
        return first * 10000 + middle * 100 + last
    }

    static func MakeOwner(recorder: PositionalDefaultRecorder): PositionalDefaultOwner {
        recorder.Order.Add("receiver")
        return new PositionalDefaultOwner("owner")
    }
}

// An overload set where the EXACT arity must still win over the fillable one.
class PositionalDefaultOverloads {
    static func Pick(a: int): string {
        return "exact1:" + a.ToString()
    }

    static func Pick(a: int, b: int = 5): string {
        return "fill2:" + a.ToString() + ":" + b.ToString()
    }
}

// The default kinds a declaration can spell, so the filled value is checked against each rather
// than only against an `int`. A FLOATING-POINT or `long` default is absent because the DECLARATION
// itself is refused before any call site is reached — separate gaps this change neither widens nor
// closes.
func PositionalDefaultKinds(seed: int, text: string = "tail", flag: bool = true, count: int = 9, tail: string? = null): string {
    return seed.ToString() + text + flag.ToString() + count.ToString() + (tail ?? "-")
}

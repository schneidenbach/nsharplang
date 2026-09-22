namespace NSharpLang.LambdaPlacement.Tests

import System
import System.Collections.Generic
import System.Linq

// A reference type whose instance-method lambdas exercise both N#-owned non-capturing placements:
//   * a body that touches only its own parameters becomes an assembly-static method on the program type,
//     which is ldftn'd cross-type from this instance method (assembly visibility keeps that verifiable);
//   * a body that reaches the enclosing chain becomes a private instance method on this type, bound to
//     the current instance.
class Accumulator {
    seed: int

    constructor(start: int) {
        seed = start
    }

    func Increment(x: int): int {
        return x + seed
    }

    // No captures, no `this`: an assembly-static program method, ldftn'd cross-type from this instance
    // method.
    func DoubleAll(values: List<int>): List<int> {
        return values.Select(v => v * 2).ToList()
    }

    // this-capture: the lambda calls the bare instance method `Increment`, which resolves on the enclosing
    // chain, so it binds to the current instance as a private instance method on Accumulator.
    func OffsetAll(values: List<int>): List<int> {
        return values.Select(v => Increment(v)).ToList()
    }

    // A this-capture lambda held in a delegate local so a test can reflect on its exact placement and
    // invoke it. The returned string is "IsPrivate|IsStatic|DeclaringType|Invoke(5)".
    func InspectThisCapturePlacement(): string {
        adder: Func<int, int> = v => Increment(v)
        method := adder.get_Method()
        return method.get_IsPrivate().ToString() + "|" + method.get_IsStatic().ToString() + "|" + method.get_DeclaringType().get_Name() + "|" + adder(5).ToString()
    }

    // Two lambdas in one body: each gets a distinct generated identity and both run.
    func Bounds(values: List<int>): (int, int) {
        lowest := values.Select(v => v - 1).Min()
        highest := values.Select(v => v + 1).Max()
        return (lowest, highest)
    }
}

// A second reference type. The static lambda written in its method also lands on the shared program type,
// so the program-static placement is proven across more than one owning type.
class Scaler {
    func TripleAll(values: List<int>): List<int> {
        return values.Select(v => v * 3).ToList()
    }
}

// A captured-parameter lambda routes through the fenced C# display-class residual (a value capture, not
// N#-owned yet). It is included so the residual is proven unregressed alongside the N#-owned placements.
class Filter {
    func AtLeast(threshold: int, values: List<int>): List<int> {
        return values.Where(v => v >= threshold).ToList()
    }
}

// A LAMBDA THAT READS THE ENCLOSING INSTANCE'S STORAGE, in the three spellings that reach it.
//
// The placement question — static program method, or private instance method bound to `this`? — used
// to be asked only for a lambda with a DELEGATE TARGET to take its signature from. A `:=` declaration
// names no target, so its zero-parameter lambda took a signature-less static method with no receiver
// at all and any read of the enclosing instance declined at `emit.body`; `f: Func<int> = () => Value`
// emitted the very same lambda without complaint. And a lambda ARGUMENT whose body read both its own
// parameter and `this` crashed the compiler outright: the contextual return-type inference ran in the
// enclosing method's frame, where argument zero is `this`, and put the lambda's own parameter on top
// of it.
class Holder {
    Value: int

    constructor(value: int) {
        Value = value
    }

    // `:=` with no delegate target, reading the instance through `this`.
    func InferredThroughThis(): int {
        read := () => this.Value

        return read()
    }

    // ...and the same read written with no receiver at all.
    func InferredBare(): int {
        read := () => Value + 1

        return read()
    }

    // A lambda ARGUMENT whose body reads its own parameter AND the enclosing instance.
    func CountMatching(values: List<int>): int {
        return values.FindAll(v => v == this.Value).Count
    }

    // The placement of the `:=` lambda, for a test to reflect on:
    // "IsStatic|DeclaringType|Invoke()".
    func InspectInferredPlacement(): string {
        read := () => this.Value
        method := read.get_Method()

        return method.get_IsStatic().ToString() + "|" + method.get_DeclaringType().get_Name() + "|" + read().ToString()
    }
}

// AN EXPRESSION-STATEMENT LAMBDA: the body is a call whose value nothing wants, because the delegate
// it fills returns nothing. C# admits exactly the expressions that may stand as a statement here, and
// drops the value; matching the body's type against `void` instead declined every `Action<T>`
// configuration callback written the way fluent .NET APIs expect one.
class Ledger {
    readonly Entries: List<string> = new List<string>()

    // Returns the running count, which an `Action<Ledger>` caller has no use for.
    func Record(entry: string): int {
        Entries.Add(entry)
        return Entries.Count
    }
}

class LedgerRuns {
    static func Configure(ledger: Ledger, configure: Action<Ledger>) {
        configure(ledger)
    }

    // The lambda's body is a value-returning call and the delegate returns nothing: the value is
    // dropped and the side effect stands.
    static func RecordThroughVoidDelegate(ledger: Ledger, entry: string) {
        Configure(ledger, target => target.Record(entry))
    }

    // The same shape written as a block, which always worked — both must reach the same state.
    static func RecordThroughBlockLambda(ledger: Ledger, entry: string) {
        Configure(ledger, target => {
            target.Record(entry)
        })
    }

    // An object creation is a statement expression too: the instance is built for its effect on the
    // ledger the constructor writes to, and the reference is dropped.
    static func RecordThroughObjectCreation(ledger: Ledger) {
        Configure(ledger, target => new LedgerStamp(target))
    }
}

class LedgerStamp {
    constructor(ledger: Ledger) {
        ledger.Record("stamp")
    }
}

// A STATIC LAMBDA HELPER HAS A LEXICAL OWNER, NOT AN INSTANCE.
//
// A non-capturing lambda written inside a member of a type becomes a STATIC helper on that type.
// Its body holds no `this` — `hasThisCapture` has already routed every body that reaches the
// enclosing chain to a private instance method instead — but the placement planner still handed the
// body the enclosing type as its INSTANCE context while the lambda's own first parameter sat at
// argument ordinal zero. `ColumnarDirectCallPlanner` reads exactly that pair as the
// contextual-lambda PREFLIGHT frame, whose ordinal zero is synthetic, and yields the WHOLE call to
// the legacy residual — so every call in such a body was limited to the hand-written subset.
//
// The same lambda written in a STATIC member always emitted, because that door left the instance
// context null. These subjects are the two shapes that did not, and every call below is one the
// residual does not model: `string.Concat(string, string)` declined at
// `emit.call.static-member-unmodeled` and `TimeSpan.FromSeconds(double)` with it.
class StaticHelperOwner {
    Prefix: string

    constructor(prefix: string) {
        Prefix = prefix
    }

    // A non-capturing lambda written in an INSTANCE member. It reads only its own parameter, so its
    // helper is static; the enclosing instance is never touched.
    func Tag(values: List<int>): string {
        return values.Select(v => string.Concat("n", v.ToString())).First()
    }

    // The SAME lambda written in a STATIC member — the control that always emitted.
    static func TagStatic(values: List<int>): string {
        return values.Select(v => string.Concat("n", v.ToString())).First()
    }

    // An instance member's non-capturing lambda whose call is an external static with a value.
    func Millis(values: List<int>): double {
        return values.Select(v => TimeSpan.FromSeconds(v).TotalMilliseconds).First()
    }

    // The enclosing instance is still reachable from the members around the lambda.
    func PrefixedTag(values: List<int>): string {
        return Prefix + Tag(values)
    }

    // The placement of the instance member's lambda, for a test to reflect on:
    // "IsStatic|DeclaringType".
    func InspectTagPlacement(): string {
        project: Func<int, string> = v => string.Concat("n", v.ToString())
        method := project.get_Method()

        return method.get_IsStatic().ToString() + "|" + method.get_DeclaringType().get_Name()
    }
}

// A LAMBDA NESTED INSIDE A CAPTURING LAMBDA IS THE SAME CELL. The capturing outer lambda becomes an
// instance method on a display class, so the display is the enclosing marker the nested lambda's
// placement reads — and the nested helper is static on it, with its own parameter at ordinal zero.
// That is why `logger.LogInformation(...)` inside `options.OnInitialize(...)` declined as soon as the
// enclosing `options => { ... }` read a local of its own method, and emitted when it read none.
class NestedLambdaOwner {
    static func Apply(action: Action<int>) {
        action(1)
    }

    // The outer lambda CAPTURES `seed`; the nested one captures nothing and calls an external static
    // the residual does not model.
    static func Run(seed: int): string {
        collected := new List<string>()
        Apply(outer => {
            collected.Add(seed.ToString())
            Apply(inner => {
                collected.Add(string.Concat("x", inner.ToString()))
            })
        })

        return string.Join("|", collected)
    }

    // The outer lambda captures NOTHING — the control from the report, which always emitted.
    static func RunWithoutCapture(): string {
        collected := new List<string>()
        Apply(outer => {
            collected.Add("outer")
            Apply(inner => {
                collected.Add(string.Concat("x", inner.ToString()))
            })
        })

        return string.Join("|", collected)
    }
}

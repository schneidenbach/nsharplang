namespace NSharpLang.CensusEvents.Tests

import System
import System.Collections.Generic
import System.Collections.ObjectModel
import System.Collections.Specialized
import System.Reflection
import System.Runtime.Loader
import System.Threading.Tasks


// THE SUBJECTS FOR THE `on` / `off` CENSUS.
//
// Every receiver shape the census reported — a static type, a local, a parameter, a field, `this.`,
// a property chain and an indexed element — plus the two handler shapes: an inline lambda and a
// DELEGATE VALUE. Each subject counts the raises it actually observed, so a subscription that
// silently attached to nothing, or an `off` that silently detached nothing, fails the assertion
// rather than passing quietly.
//
// `ObservableCollection<T>.CollectionChanged` is the subject event because it is RAISED BY ADDING AN
// ITEM: the whole subscribe -> raise -> unsubscribe -> raise-again cycle is deterministic and
// synchronous, with no timer and no process signal.
class Counter {
    Hits: int

    constructor() {
        Hits = 0
    }

    func Bump() {
        Hits = Hits + 1
    }
}

// A SOURCE TYPE WHOSE MEMBERS ARE THE RECEIVER: a field read bare, a field read through `this.`, and
// a property chain (`holder.Items`).
class Holder {
    items: ObservableCollection<string>
    Items: ObservableCollection<string> => items

    constructor() {
        items = new ObservableCollection<string>()
    }

    // A BARE FIELD RECEIVER inside an instance method, and the handle held in an ordinary local.
    func CountThroughField(): int {
        seen := 0
        sub := on items.CollectionChanged (sender, args) => {
            seen = seen + 1
        }
        items.Add("a")
        items.Add("b")
        off sub
        items.Add("c")
        return seen
    }

    // THE SAME FIELD THROUGH `this.`.
    func CountThroughThisField(): int {
        seen := 0
        sub := on this.items.CollectionChanged (sender, args) => {
            seen = seen + 1
        }
        items.Add("d")
        off sub
        items.Add("e")
        return seen
    }

    func Count(): int {
        return items.Count
    }
}

// A LOCAL RECEIVER.
func CountThroughLocal(): int {
    seen := 0
    list := new ObservableCollection<string>()
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    list.Add("x")
    list.Add("y")
    list.Add("z")
    off sub
    list.Add("w")
    return seen
}

// A PARAMETER RECEIVER — the census probe that made the whole file's declarations vanish.
func CountThroughParameter(list: ObservableCollection<string>): int {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    list.Add("p")
    off sub
    list.Add("q")
    return seen
}

// A PROPERTY-CHAIN RECEIVER: `holder.Items` is a property whose value is the event's owner.
func CountThroughPropertyChain(holder: Holder): int {
    seen := 0
    sub := on holder.Items.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    holder.Items.Add("prop")
    off sub
    holder.Items.Add("after")
    return seen
}

// AN INDEXED RECEIVER: the event's owner is an element of a list.
func CountThroughIndexedElement(lists: List<ObservableCollection<string>>): int {
    seen := 0
    sub := on lists[0].CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    lists[0].Add("idx")
    off sub
    lists[0].Add("after")
    return seen
}

// A DELEGATE VALUE AS THE HANDLER — C#'s `x.E += handler`. The handler is named first and passed by
// name, which is the shape a `+=` on a named handler maps onto.
func CountThroughDelegateValue(list: ObservableCollection<string>, counter: Counter): int {
    handler: NotifyCollectionChangedEventHandler = (sender, args) => {
        counter.Bump()
    }
    sub := on list.CollectionChanged handler
    list.Add("h1")
    list.Add("h2")
    off sub
    list.Add("h3")
    return counter.Hits
}

// A METHOD GROUP AS THE HANDLER. A function whose signature IS the event's delegate signature
// converts to that delegate, so `on x.E Handler` needs no lambda wrapper around it.
class StaticTally {
    static Hits: int = 0
}

func TallyHandler(_sender: object?, _args: NotifyCollectionChangedEventArgs) {
    StaticTally.Hits = StaticTally.Hits + 1
}

func CountThroughMethodGroup(list: ObservableCollection<string>): int {
    sub := on list.CollectionChanged TallyHandler
    list.Add("m1")
    list.Add("m2")
    off sub
    list.Add("m3")
    return StaticTally.Hits
}

// TWO SUBSCRIPTIONS TO ONE EVENT, DETACHED INDEPENDENTLY. Each handle owns exactly the delegate it
// added, which is the property .NET's own `-=` cannot give an inline lambda.
func CountTwoIndependentSubscriptions(list: ObservableCollection<string>): (First: int, Second: int) {
    first := 0
    second := 0
    a := on list.CollectionChanged (sender, args) => {
        first = first + 1
    }
    b := on list.CollectionChanged (sender, args) => {
        second = second + 1
    }
    list.Add("both")
    off a
    list.Add("second only")
    off b
    list.Add("neither")
    return (first, second)
}

// `off` TWICE IS A NO-OP, and the second call must not detach anything else.
func CountWithDoubleOff(list: ObservableCollection<string>): int {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    list.Add("one")
    off sub
    off sub
    off sub
    list.Add("two")
    return seen
}

// A BARE `on` STATEMENT — the handle is discarded, so the handler stays attached for the life of the
// collection.
func CountWithDiscardedHandle(list: ObservableCollection<string>, counter: Counter): int {
    on list.CollectionChanged (sender, args) => {
        counter.Bump()
    }
    list.Add("kept1")
    list.Add("kept2")
    return counter.Hits
}

// THE HANDLE IS AN ORDINARY LOCAL, so a LOCAL FUNCTION closes over it exactly as it closes over any
// other name, and `off` inside that local function detaches the outer subscription.
func CountWithHandleDetachedFromLocalFunction(list: ObservableCollection<string>): int {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }

    func detach() {
        off sub
    }

    list.Add("before")
    detach()
    list.Add("after")
    return seen
}

// THE SUBSCRIPTION ITSELF INSIDE A LAMBDA BODY: `on` is an expression wherever a call is, and its
// handle is a local of that body like any other. (The handler is a delegate VALUE rather than a
// second inline lambda because a lambda nested inside a lambda is a separate columnar limit and
// would decline this file for a reason that has nothing to do with events.)
func CountWithSubscriptionInsideLambda(list: ObservableCollection<string>, counter: Counter): int {
    handler: NotifyCollectionChangedEventHandler = (sender, args) => {
        counter.Bump()
    }
    run: Action = () => {
        inner := on list.CollectionChanged handler
        list.Add("lambda")
        off inner
        list.Add("lambda after")
    }
    run()
    return counter.Hits
}

// THE SUBSCRIPTION INSIDE A LOCAL FUNCTION, with the handle local to that body. (Same reason for the
// delegate-value handler as the lambda above: a lambda WRITTEN INSIDE a local function is a separate
// columnar limit.)
func CountWithSubscriptionInsideLocalFunction(list: ObservableCollection<string>, counter: Counter): int {
    handler: NotifyCollectionChangedEventHandler = (sender, args) => {
        counter.Bump()
    }

    func watchOnce(target: ObservableCollection<string>, h: NotifyCollectionChangedEventHandler) {
        inner := on target.CollectionChanged h
        target.Add("local fn")
        off inner
        target.Add("local fn after")
    }

    watchOnce(list, handler)
    return counter.Hits
}

// AN ASYNC BODY: the handle is a hoisted local of the state machine like every other local, so a
// subscription made before a suspension is still detachable after it.
func CountInsideAsyncBody(list: ObservableCollection<string>): int {
    pending := CountInsideAsync(list)
    pending.Wait()
    return pending.Result
}

async func CountInsideAsync(list: ObservableCollection<string>): Task<int> {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    list.Add("before await")
    step := await Task.FromResult(0)
    off sub
    list.Add("after off")
    return seen + step
}

// A STATIC EVENT ON AN EXTERNAL TYPE, reached through the TYPE NAME with no receiver value at all.
// `Console.CancelKeyPress` cannot be raised from a test without signalling the process, so what is
// pinned here is that the subscription and its detach both RUN — the arm the census reported as a
// whole-class parse decline.
func SubscribeAndDetachStaticEvent(): bool {
    sub := on Console.CancelKeyPress (sender, args) => {
        args.Cancel = true
    }
    off sub
    off sub
    return sub != null
}

// A STATIC EVENT REACHED THROUGH A PROPERTY CHAIN on a static type.
func SubscribeAndDetachStaticChainEvent(): bool {
    sub := on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        Console.Out.Flush()
    }
    off sub
    return sub != null
}

// AN EVENT WHOSE HANDLER RETURNS A MAYBE-NULL REFERENCE, subscribed with a FREE FUNCTION.
//
// `AssemblyLoadContext.Resolving` is declared `event Func<AssemblyLoadContext, AssemblyName,
// Assembly?>?`, and reference nullability is METADATA ON THE EVENT rather than part of the CLR type:
// reflection answers a bare `Func`3[AssemblyLoadContext, AssemblyName, Assembly]`. Measuring a
// handler that returns `Assembly?` against that unannotated spelling reported NL318 — "this handler
// is 'FunctionTypeInfo', but the event expects 'Func`3'" — over exactly the delegate the BCL
// declares. All three handler shapes are pinned here: the maybe-null free function, a non-null one
// (the covariant direction), and an inline lambda.
//
// The event is RAISED by asking for an assembly that is not on disk, which is deterministic and
// needs no process signal: the load fails either way, and what is counted is how many times the
// resolver was consulted.
class ResolveTally {
    static Hits: int = 0
}

func tallyResolve(_context: AssemblyLoadContext, _name: AssemblyName): Assembly? {
    ResolveTally.Hits = ResolveTally.Hits + 1
    return null
}

func TryLoadMissingAssembly(name: string) {
    try {
        Assembly.Load(new AssemblyName(name))
    } catch error: Exception {
        Console.Out.Flush()
    }
}

// THE MAYBE-NULL FREE FUNCTION as the handler, counted across the subscription's life.
func CountResolveThroughFreeFunction(): int {
    ResolveTally.Hits = 0
    sub := on AssemblyLoadContext.Default.Resolving tallyResolve
    TryLoadMissingAssembly("NSharpLang.CensusEvents.Missing.One")
    off sub
    TryLoadMissingAssembly("NSharpLang.CensusEvents.Missing.Two")
    return ResolveTally.Hits
}

// A NON-NULL-RETURNING FREE FUNCTION reaches the same maybe-null delegate: the return position is
// covariant, so a handler that promises MORE than the delegate asks for is a handler.
func resolveNeverNull(_context: AssemblyLoadContext, _name: AssemblyName): Assembly {
    ResolveTally.Hits = ResolveTally.Hits + 1
    return typeof(ResolveTally).Assembly
}

func CountResolveThroughNonNullFreeFunction(): int {
    ResolveTally.Hits = 0
    sub := on AssemblyLoadContext.Default.Resolving resolveNeverNull
    TryLoadMissingAssembly("NSharpLang.CensusEvents.Missing.Three")
    off sub
    return ResolveTally.Hits
}

// AN INLINE LAMBDA against the same event, whose parameters and result are inferred from it.
func CountResolveThroughLambda(): int {
    ResolveTally.Hits = 0
    sub := on AssemblyLoadContext.Default.Resolving (context, name) => tallyResolve(context, name)
    TryLoadMissingAssembly("NSharpLang.CensusEvents.Missing.Four")
    off sub
    return ResolveTally.Hits
}

// WHAT THE EMITTER ACTUALLY BUILT: the delegate the `add_` accessor received is the event's own
// handler type, not a wrapper, which is what makes `off` able to hand the same instance back to
// `remove_`.
func ResolvingHandlerTypeName(): string {
    resolving := typeof(AssemblyLoadContext).GetEvent("Resolving")
    if resolving == null {
        return "<no event>"
    }

    handlerType := resolving.get_EventHandlerType()
    if handlerType == null {
        return "<no handler type>"
    }

    return handlerType.Name
}

// THE FIRE-AND-FORGET HANDLER, WHICH IS WHAT `async void` WOULD HAVE BEEN.
//
// An event's delegate returns `void`, and N# has no `async void` — NL334 says so and names this
// idiom. What it pins is that the discarded task really RUNS: `_ =` means "do not await HERE", not
// "drop". The awaited value completes synchronously, so the count is deterministic with no timer and
// no join.
class AsyncTally {
    Completed: int

    constructor() {
        Completed = 0
    }

    async func BumpAsync(): Task {
        step := await Task.FromResult(1)
        Completed = Completed + step
    }
}

func CountThroughDiscardedTaskHandler(list: ObservableCollection<string>, tally: AsyncTally): int {
    sub := on list.CollectionChanged (sender, args) => {
        _ = tally.BumpAsync()
    }
    list.Add("async one")
    off sub
    list.Add("async two")
    return tally.Completed
}

// ── `on` / `off` INSIDE A GENERATOR BODY ──────────────────────────────────────────────────────
//
// A subscription made before a `yield` and detached after one is the whole point: the handle is an
// ordinary local, so the machine hoists it into a field like every other local, and the two halves of
// the feature span a suspension without knowing they did. The census reported
// `emit.iterator.unsupported-shape` for the `off` statement and
// `emit.iterator.lambda-unsupported` for the block-bodied handler; both are lowered now.
class GeneratorTally {
    Hits: int

    constructor() {
        Hits = 0
    }

    func Bump() {
        Hits = Hits + 1
    }
}

// A BLOCK-BODIED handler lambda, assigning to a captured local AND calling through a captured
// receiver — the two statement forms a handler is actually written with.
func* WatchWhileYielding(list: ObservableCollection<string>, tally: GeneratorTally): IEnumerable<int> {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
        tally.Bump()
    }
    yield 1
    list.Add("during")
    yield seen
    off sub
    list.Add("after off")
    yield seen
}

func DrainWatchWhileYielding(tally: GeneratorTally): (Total: int, Hits: int) {
    list := new ObservableCollection<string>()
    total := 0
    for value in WatchWhileYielding(list, tally) {
        total = total + value
    }

    return (total, tally.Hits)
}

// A METHOD GROUP as the handler inside a generator: a top-level `func` emits as a static method, so
// the delegate is built the way a static one is (`ldnull; ldftn; newobj`).
func* WatchWithMethodGroupWhileYielding(list: ObservableCollection<string>): IEnumerable<int> {
    sub := on list.CollectionChanged TallyHandler
    yield 1
    list.Add("group")
    off sub
    list.Add("after")
    yield 2
}

func DrainWatchWithMethodGroupWhileYielding(): int {
    StaticTally.Hits = 0
    list := new ObservableCollection<string>()
    total := 0
    for value in WatchWithMethodGroupWhileYielding(list) {
        total = total + value
    }

    return total * 10 + StaticTally.Hits
}

// THE HANDLE OUTLIVES A SUSPENSION AND IS STILL THE SAME HANDLE: `off` twice from inside the
// generator is a no-op exactly as it is outside one.
func* DoubleOffWhileYielding(list: ObservableCollection<string>): IEnumerable<int> {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    list.Add("one")
    yield seen
    off sub
    yield seen
    off sub
    list.Add("two")
    yield seen
}

func DrainDoubleOffWhileYielding(): int {
    list := new ObservableCollection<string>()
    total := 0
    for value in DoubleOffWhileYielding(list) {
        total = total + value
    }

    return total
}

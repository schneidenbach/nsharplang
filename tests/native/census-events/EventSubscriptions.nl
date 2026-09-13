namespace NSharpLang.CensusEvents.Tests

import System
import System.Collections.Generic
import System.Collections.ObjectModel
import System.Collections.Specialized
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

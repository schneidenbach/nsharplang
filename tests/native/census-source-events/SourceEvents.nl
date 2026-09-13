namespace NSharpLang.CensusSourceEvents.Tests

import System

// EVENTS A SOURCE TYPE DECLARES. `event Name: DelegateType` is C#'s field-like event: private backing
// storage carrying the event's own name, `add_`/`remove_` accessors that combine and remove with
// `Interlocked.CompareExchange`, and an `EventInfo` row wiring the two together.
class Widget {
    event Changed: EventHandler
    Label: string

    constructor(label: string) {
        Label = label
    }

    // The canonical .NET raise: null-conditional, so an event with no subscribers is a no-op.
    func Raise() {
        Changed?.Invoke(this, EventArgs.Empty)
    }

    // A BARE INVOCATION IS THE C# RULE, KEPT: with no subscribers this throws NullReferenceException.
    func RaiseUnguarded() {
        Changed(this, EventArgs.Empty)
    }

    // Inside the declaring type the name IS the backing delegate, so it can be null-tested.
    func HasSubscribers(): bool {
        return Changed != null
    }
}

// A STATIC event: the storage and both accessors are static, and the `value` parameter is argument
// zero rather than argument one.
class Registry {
    static event Registered: EventHandler

    static func Announce() {
        Registry.Registered?.Invoke(null, EventArgs.Empty)
    }

    static func Listening(): bool {
        return Registry.Registered != null
    }
}

// A C#-SHAPED PAYLOAD: `EventHandler<T>` over an argument type this compilation also declares.
class PriceArgs: EventArgs {
    Amount: int

    constructor(amount: int) {
        Amount = amount
    }
}

class Ticker {

    // A GENERIC HANDLER TYPE, and a payload this compilation declares travelling through it as the
    // `EventArgs` the handler receives — the shape a converted C# type has.
    event PriceChanged: EventHandler<EventArgs>

    func Publish(amount: int) {
        PriceChanged?.Invoke(this, new PriceArgs(amount))
    }
}

// AN EVENT ON A VALUE TYPE. It declares, it emits, and the declaring struct's own body raises it; only
// subscribing THROUGH a struct receiver is refused, because that receiver is a copy.
struct Gauge {
    event Tripped: EventHandler
    Limit: int

    func Trip() {
        Tripped?.Invoke(null, EventArgs.Empty)
    }

    func Armed(): bool {
        return Tripped != null
    }
}

// VISIBILITY: the accessors take the EVENT's own word — the written one, else the name's casing —
// while the backing storage is private whatever that says. A camelCase event is package-private and a
// `private` one is private, and both are raised by the declaring type exactly like the exported one.
class Panel {
    event Resized: EventHandler
    event moved: EventHandler
    private event Closed: EventHandler

    func RaiseAll() {
        Resized?.Invoke(this, EventArgs.Empty)
        moved?.Invoke(this, EventArgs.Empty)
        Closed?.Invoke(this, EventArgs.Empty)
    }
}

// A SUBSCRIBER WRITTEN OUTSIDE THE DECLARING TYPE — the only thing an event admits there is `on`/`off`.
class Counter {
    Count: int
    Last: int

    constructor() {
        Count = 0
        Last = 0
    }

    func WatchOnce(widget: Widget) {
        subscription := on widget.Changed (sender, args) => {
            Count = Count + 1
        }
        widget.Raise()
        off subscription
        widget.Raise()
    }

    func WatchTwice(widget: Widget) {
        first := on widget.Changed (sender, args) => {
            Count = Count + 1
        }
        second := on widget.Changed (sender, args) => {
            Count = Count + 10
        }
        widget.Raise()
        off first
        widget.Raise()
        off second
        widget.Raise()
    }

    func WatchPrices(ticker: Ticker) {
        subscription := on ticker.PriceChanged (sender, args) => {
            Last = (args as PriceArgs).Amount
        }
        ticker.Publish(42)
        off subscription
        ticker.Publish(99)
    }

    func WatchRegistry() {
        subscription := on Registry.Registered (sender, args) => {
            Count = Count + 1
        }
        Registry.Announce()
        off subscription
        Registry.Announce()
    }

    // A HANDLER THAT IS ALREADY A DELEGATE VALUE — the shape C#'s `widget.Changed += handler` has.
    func Bump(_sender: object?, _args: EventArgs) {
        Count = Count + 1
    }

    func WatchWithDelegateValue(widget: Widget) {
        handler: EventHandler = Bump
        subscription := on widget.Changed handler
        widget.Raise()
        off subscription
        widget.Raise()
    }

    // And the same handler named directly, as a method group.
    func WatchWithMethodGroup(widget: Widget) {
        subscription := on widget.Changed Bump
        widget.Raise()
        off subscription
        widget.Raise()
    }
}

// A DERIVED TYPE inherits its base's event like any other member: subscribers reach it through the
// derived receiver, and the base's own code is what raises it.
class LabelledWidget: Widget {
    constructor(label: string): base(label) {
    }

    func RaiseTwice() {
        Raise()
        Raise()
    }
}

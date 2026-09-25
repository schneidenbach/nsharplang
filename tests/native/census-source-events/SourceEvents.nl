namespace NSharpLang.CensusSourceEvents.Tests

import System
import System.ComponentModel

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
            Last = (must (args as PriceArgs)).Amount
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

// ── THE THREE INHERITANCE WORDS ───────────────────────────────────────────────────────────────
//
// An event's accessors are ordinary methods, so `virtual` and `abstract` open a virtual slot for each
// and `override` reuses the base's. That is C#'s rule, and it brings C#'s consequence with it: an
// overriding field-like event keeps its OWN handler list, so a subscriber reaching it through a base
// reference runs the OVERRIDE's accessors and lands in the OVERRIDE's storage — which is exactly why
// the base's own `Base?.Invoke(...)` then sees nothing. The raise belongs with the storage, so a base
// that has to raise gives itself a `virtual func` the derived type overrides.
class Signal {
    virtual event Fired: EventHandler

    func RaiseFromBase() {
        Fired?.Invoke(this, EventArgs.Empty)
    }

    virtual func RaiseOwn() {
        Fired?.Invoke(this, EventArgs.Empty)
    }

    // Inside `Signal` the name is SIGNAL's own storage, whatever the runtime type is.
    func BaseStorageHasSubscribers(): bool {
        return Fired != null
    }
}

class LoudSignal: Signal {
    override event Fired: EventHandler

    override func RaiseOwn() {
        Fired?.Invoke(this, EventArgs.Empty)
    }

    // …and inside `LoudSignal` it is LOUDSIGNAL's.
    func OverrideStorageHasSubscribers(): bool {
        return Fired != null
    }
}

// AN ABSTRACT EVENT is a pair of slots with NO storage at all: the declaring type has nothing to
// raise, and the class filling the slots owns the handler list.
abstract class Pump {
    abstract event Ticked: EventHandler

    abstract func Tick()
}

class WaterPump: Pump {
    override event Ticked: EventHandler

    override func Tick() {
        Ticked?.Invoke(this, EventArgs.Empty)
    }
}

// SUBSCRIBING THROUGH THE BASE REFERENCE. The handler goes in through the base-typed receiver, which
// dispatches to the override's `add_` — so the derived raise sees it and the BASE's own raise, which
// reads the base's own (empty) storage, does not.
func CountThroughOverriddenEvent(): (Seen: int, BaseStorage: bool, OverrideStorage: bool) {
    seen := 0
    loud := new LoudSignal()
    asBase: Signal = loud
    sub := on asBase.Fired (sender, args) => {
        seen = seen + 1
    }
    // The virtual `RaiseOwn` lands in `LoudSignal`, which reads LoudSignal's storage — the handler is
    // there. `RaiseFromBase` is not virtual and reads SIGNAL's storage, which is empty.
    asBase.RaiseOwn()
    asBase.RaiseFromBase()
    baseStorage := loud.BaseStorageHasSubscribers()
    overrideStorage := loud.OverrideStorageHasSubscribers()
    off sub
    asBase.RaiseOwn()
    return (seen, baseStorage, overrideStorage)
}

// AN ABSTRACT SLOT, FILLED. The subscription is made through the abstract base type and the raise is
// the derived type's; both reach the same storage because both go through the same slot.
func CountThroughAbstractEvent(): int {
    seen := 0
    pump := new WaterPump()
    asPump: Pump = pump
    sub := on asPump.Ticked (sender, args) => {
        seen = seen + 1
    }
    asPump.Tick()
    off sub
    asPump.Tick()
    return seen
}

// ── AN EVENT AN INTERFACE DECLARES ────────────────────────────────────────────────────────────
//
// An interface event is a pair of ABSTRACT accessor slots plus the `EventInfo` row naming them, and
// the implementing type fills both by declaring an event of the same name and delegate type — the
// same way it fills a `func` slot by declaring that `func`. The census reported NL323 ("an interface
// cannot declare the event 'Changed' yet") for the declaration and `NL103 … parse.interface` for the
// whole file behind it.
interface INotifier {
    event Changed: EventHandler

    func Touch()

    event Ticked: Action
}

class Notifier: INotifier {
    event Changed: EventHandler
    event Ticked: Action

    func Touch() {
        Changed?.Invoke(this, EventArgs.Empty)
        Ticked?.Invoke()
    }
}

func CountThroughInterfaceReceiver(): int {
    seen := 0
    notifier := new Notifier()
    asInterface: INotifier = notifier
    sub := on asInterface.Changed (sender, args) => {
        seen = seen + 1
    }
    asInterface.Touch()
    off sub
    asInterface.Touch()
    return seen
}

// AN INTERFACE A REFERENCED ASSEMBLY DECLARES. `INotifyPropertyChanged` is the one every reader
// meets, and its slot is filled by exactly the same declaration.
class Observable: INotifyPropertyChanged {
    event PropertyChanged: PropertyChangedEventHandler

    func Rename(name: string) {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name))
    }
}

func CountThroughExternalInterfaceReceiver(): int {
    seen := 0
    observable := new Observable()
    asInterface: INotifyPropertyChanged = observable
    sub := on asInterface.PropertyChanged (sender, args) => {
        seen = seen + 1
    }
    observable.Rename("Label")
    off sub
    observable.Rename("Label")
    return seen
}

// SUBSCRIBING FROM INSIDE THE DECLARING TYPE.
//
// `on this.Changed (…) => { … }` written in the type that declares `Changed` used to report NL318
// "`on` can only subscribe to a .NET event" — about a member that IS an event — because inside the
// declaring type the name reads as the backing DELEGATE, which is what makes `Changed?.Invoke(…)`
// and `Changed == null` ordinary reads there. `on`/`off` are the one position where the name means
// the EVENT wherever it is written: C#'s `this.E += h` inside the declaring type is the field
// combine, and the two are the same operation, so one reading serves both.
//
// The two spellings are the SAME target. The parser collapses `this.Member` to the bare member read
// exactly as it does everywhere else, so `on this.Changed` and `on Changed` produce one node.
class SelfWatcher {
    event Changed: EventHandler
    static event Started: EventHandler

    Seen: int

    constructor() {
        Seen = 0
    }

    func WatchThroughThis(): int {
        subscription := on this.Changed (sender, args) => {
            Seen = Seen + 1
        }
        Raise()
        Raise()
        off subscription
        Raise()
        return Seen
    }

    func WatchThroughBareName(): int {
        subscription := on Changed (sender, args) => {
            Seen = Seen + 1
        }
        Raise()
        off subscription
        Raise()
        return Seen
    }

    // A STATIC event named bare has no receiver at all, and the same reading applies.
    func WatchStatic(): int {
        seen := 0
        subscription := on Started (sender, args) => {
            seen = seen + 1
        }
        RaiseStarted()
        off subscription
        RaiseStarted()
        return seen
    }

    func Raise() {
        Changed?.Invoke(this, EventArgs.Empty)
    }

    static func RaiseStarted() {
        Started?.Invoke(null, EventArgs.Empty)
    }
}

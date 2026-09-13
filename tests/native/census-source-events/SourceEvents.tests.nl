namespace NSharpLang.CensusSourceEvents.Tests

import System
import System.Reflection

test "an event declared by a source type is subscribed, raised and detached" {
    widget := new Widget("w")
    counter := new Counter()
    counter.WatchOnce(widget)
    assert counter.Count == 1
}

test "raising an event with no subscribers is a no-op" {
    widget := new Widget("quiet")
    assert !widget.HasSubscribers()
    widget.Raise()
    assert !widget.HasSubscribers()
}

test "two subscriptions detach independently" {
    widget := new Widget("w")
    counter := new Counter()
    counter.WatchTwice(widget)
    // both, then only the second, then neither.
    assert counter.Count == 21
}

test "the declaring type sees its own event as the backing delegate" {
    widget := new Widget("w")
    assert !widget.HasSubscribers()
    subscription := on widget.Changed (sender, args) => {
    }
    assert widget.HasSubscribers()
    off subscription
    assert !widget.HasSubscribers()
}

test "a bare invocation of an unsubscribed event throws, exactly as C# does" {
    widget := new Widget("w")
    assert throws NullReferenceException {
        widget.RaiseUnguarded()
    }
}

test "a static event subscribes, raises and detaches through the declaring type name" {
    counter := new Counter()
    assert !Registry.Listening()
    counter.WatchRegistry()
    assert counter.Count == 1
    assert !Registry.Listening()
}

test "an EventHandler<T> payload reaches the handler" {
    ticker := new Ticker()
    counter := new Counter()
    counter.WatchPrices(ticker)
    assert counter.Last == 42
}

test "a delegate value is a handler, and the handle detaches it" {
    widget := new Widget("w")
    counter := new Counter()
    counter.WatchWithDelegateValue(widget)
    assert counter.Count == 1
}

test "a method group is a handler, and the handle detaches it" {
    widget := new Widget("w")
    counter := new Counter()
    counter.WatchWithMethodGroup(widget)
    assert counter.Count == 1
}

test "an inherited event is reached through the derived receiver" {
    widget := new LabelledWidget("derived")
    seen := 0
    subscription := on widget.Changed (sender, args) => {
        seen = seen + 1
    }
    widget.RaiseTwice()
    off subscription
    widget.RaiseTwice()
    assert seen == 2
}

test "the handler receives the declaring instance as the sender" {
    widget := new Widget("sender")
    seen: object? = null
    subscription := on widget.Changed (sender, args) => {
        seen = sender
    }
    widget.Raise()
    off subscription
    assert Object.ReferenceEquals(seen, widget)
}

test "a struct-declared event raises from inside the declaring struct" {
    gauge := new Gauge()
    gauge.Limit = 3
    assert !gauge.Armed()
    gauge.Trip()
}

// ── CLR metadata ──────────────────────────────────────────────────────────────────────────────

test "the declaration emits a CLR event with both accessors wired" {
    declared := typeof(Widget).GetEvent("Changed")
    assert declared != null
    changed := declared
    assert changed.EventHandlerType == typeof(EventHandler)
    assert changed.AddMethod != null
    assert changed.RemoveMethod != null
    assert changed.AddMethod.Name == "add_Changed"
    assert changed.RemoveMethod.Name == "remove_Changed"
    assert changed.DeclaringType == typeof(Widget)
}

test "the accessors are public, special-named, and take one parameter called value" {
    changed := must typeof(Widget).GetEvent("Changed")
    adder := must changed.AddMethod
    assert adder.IsPublic
    assert adder.IsSpecialName
    assert adder.ReturnType.FullName == "System.Void"
    parameters := adder.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].ParameterType == typeof(EventHandler)
    assert parameters[0].Name == "value"
}

test "the backing field carries the event's name, is private, and is compiler generated" {
    backing := typeof(Widget).GetField("Changed", BindingFlags.NonPublic | BindingFlags.Instance)
    assert backing != null
    field := backing
    assert field.IsPrivate
    assert field.FieldType == typeof(EventHandler)
    assert field.IsDefined(typeof(System.Runtime.CompilerServices.CompilerGeneratedAttribute), false)
}

test "the backing field is not a public member of the type" {
    assert typeof(Widget).GetField("Changed") == null
}

test "a static event's accessors and storage are static" {
    registered := must typeof(Registry).GetEvent("Registered")
    adder := must registered.AddMethod
    assert adder.IsStatic
    assert adder.GetParameters().Length == 1
    backing := must typeof(Registry).GetField("Registered", BindingFlags.NonPublic | BindingFlags.Static)
    assert backing.IsStatic
    assert backing.IsPrivate
}

// THE ACCESSORS CARRY THE EVENT'S OWN VISIBILITY, AND THE STORAGE NEVER DOES. That asymmetry is C#'s
// and it is the reason a reader outside the declaring type reaches the EVENT rather than the delegate.
test "an event's accessors take its visibility and its storage stays private" {
    exported := must typeof(Panel).GetEvent("Resized")
    assert (must exported.AddMethod).IsPublic
    assert (must exported.RemoveMethod).IsPublic

    packagePrivate := must typeof(Panel).GetEvent("moved", BindingFlags.NonPublic | BindingFlags.Instance)
    assert (must packagePrivate.AddMethod).IsAssembly
    assert typeof(Panel).GetEvent("moved") == null

    hidden := must typeof(Panel).GetEvent("Closed", BindingFlags.NonPublic | BindingFlags.Instance)
    assert (must hidden.AddMethod).IsPrivate
    assert typeof(Panel).GetEvent("Closed") == null

    for name in ["Resized", "moved", "Closed"] {
        storage := must typeof(Panel).GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)
        assert storage.IsPrivate
        assert storage.IsDefined(typeof(System.Runtime.CompilerServices.CompilerGeneratedAttribute), false)
    }
}

test "a generic handler type reaches metadata closed over its written argument" {
    priceChanged := must typeof(Ticker).GetEvent("PriceChanged")
    handlerType := must priceChanged.EventHandlerType
    assert handlerType.IsGenericType
    assert handlerType.GetGenericArguments()[0] == typeof(EventArgs)
}

test "an event declared on a struct reaches metadata like any other" {
    tripped := must typeof(Gauge).GetEvent("Tripped")
    assert tripped.EventHandlerType == typeof(EventHandler)
    assert (must tripped.AddMethod).IsPublic
    backing := must typeof(Gauge).GetField("Tripped", BindingFlags.NonPublic | BindingFlags.Instance)
    assert backing.IsPrivate
}

test "a C# caller could subscribe: the add accessor combines through the event, not the field" {
    widget := new Widget("interop")
    changed := must typeof(Widget).GetEvent("Changed")
    seen := 0
    handler: EventHandler = (sender, args) => {
        seen = seen + 1
    }
    changed.AddEventHandler(widget, handler)
    widget.Raise()
    changed.RemoveEventHandler(widget, handler)
    widget.Raise()
    assert seen == 1
}

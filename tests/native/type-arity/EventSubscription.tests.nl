namespace NSharpLang.TypeArity.Tests

import System
import System.Collections.Generic


// THE ACCEPTANCE CONTRACTS FOR `EventSubscription.nl`, EXECUTED.
//
// This is the compiler compiling its own runtime's shape: a non-generic handle beside a generic one
// of the same name, the pair the whole arity feature exists to make expressible. The assertions come
// in two halves — what the subscription DOES, and what the CLR SEES — because the C# comment in
// `src/NSharpLang.Runtime/NSharpEventSubscription.cs` makes claims about both, and neither half was
// possible before.
class EventSubscriptionRecorder {
    Values: List<int>

    constructor() {
        Values = new List<int>()
    }

    func Record(value: int) {
        Values.Add(value)
    }
}

// ── what it does ──────────────────────────────────────────────────────────────────────────────

test "a handler subscribed to a real callback list is invoked until its subscription is unsubscribed" {
    publisher := new CallbackPublisher()
    recorder := new EventSubscriptionRecorder()
    handler: Action<int> = value => {
        recorder.Record(value)
    }

    subscription := publisher.Subscribe(handler)
    assert publisher.HandlerCount == 1

    publisher.Raise(1)
    assert recorder.Values.Count == 1
    assert recorder.Values[0] == 1

    subscription.Unsubscribe()
    assert publisher.HandlerCount == 0

    publisher.Raise(2)
    assert recorder.Values.Count == 1
}

// "Safe to call more than once; subsequent calls are no-ops." The second call must not remove a
// LATER subscription of the same handler, which is what an unclaimed accessor would do.
test "a second Unsubscribe is a no-op, even when the same handler subscribed again" {
    publisher := new CallbackPublisher()
    recorder := new EventSubscriptionRecorder()
    handler: Action<int> = value => {
        recorder.Record(value)
    }

    first := publisher.Subscribe(handler)
    first.Unsubscribe()
    assert publisher.HandlerCount == 0

    second := publisher.Subscribe(handler)
    assert publisher.HandlerCount == 1

    first.Unsubscribe()
    assert publisher.HandlerCount == 1

    publisher.Raise(7)
    assert recorder.Values.Count == 1
    assert recorder.Values[0] == 7

    second.Unsubscribe()
    assert publisher.HandlerCount == 0
}

test "two handlers detach independently through their own subscriptions" {
    publisher := new CallbackPublisher()
    first := new EventSubscriptionRecorder()
    second := new EventSubscriptionRecorder()
    firstHandler: Action<int> = value => {
        first.Record(value)
    }
    secondHandler: Action<int> = value => {
        second.Record(value)
    }

    firstSubscription := publisher.Subscribe(firstHandler)
    secondSubscription := publisher.Subscribe(secondHandler)
    assert publisher.HandlerCount == 2

    firstSubscription.Unsubscribe()
    publisher.Raise(3)
    assert first.Values.Count == 0
    assert second.Values.Count == 1

    secondSubscription.Unsubscribe()
    publisher.Raise(4)
    assert second.Values.Count == 1
}

// THE PARAMETER NAME IS READ OUT OF THE MESSAGE, not off `ParamName`: the property is not on the
// compiler's modeled external-member surface, so a `.ParamName` read declines emission. .NET always
// embeds the name it was given in the message ("Value cannot be null. (Parameter 'remove')"), which
// is the same fact through a different door.
test "a null constructor argument throws ArgumentNullException naming the parameter" {
    handler: Action<int> = value => {
    }
    handlers := new List<Action<int>>()

    removeMessage := ""
    try {
        _ = new NSharpEventSubscription<Action<int>>(null, handler)
    } catch error: ArgumentNullException {
        removeMessage = error.Message
    }
    assert removeMessage.Contains("remove")
    assert !removeMessage.Contains("handler")

    handlerMessage := ""
    try {
        _ = new NSharpEventSubscription<Action<int>>(new CallbackListDetach(handlers, handler), null)
    } catch error: ArgumentNullException {
        handlerMessage = error.Message
    }
    assert handlerMessage.Contains("handler")

    // The non-generic base checks its own argument, so holding the base type is not a way around it.
    baseMessage := ""
    try {
        _ = new NSharpEventSubscription(null)
    } catch error: ArgumentNullException {
        baseMessage = error.Message
    }
    assert baseMessage.Contains("remove")
}

test "the generic subscription keeps the handler it was constructed with" {
    handlers := new List<Action<int>>()
    handler: Action<int> = value => {
    }
    subscription := new NSharpEventSubscription<Action<int>>(new CallbackListDetach(handlers, handler), handler)
    assert Object.ReferenceEquals(subscription.Handler, handler)
}

// ── what the CLR sees ─────────────────────────────────────────────────────────────────────────

test "the generic subscription's CLR name is the arity name and its base is the non-generic one" {
    generic: Type = typeof(NSharpEventSubscription<Action<int>>)
    plain: Type = typeof(NSharpEventSubscription)

    assert generic.get_Name() == "NSharpEventSubscription`1"
    assert plain.get_Name() == "NSharpEventSubscription"
    assert generic.get_BaseType() == plain
    assert generic.IsSubclassOf(plain)
    assert generic.get_IsSealed()
}

test "a subscription handed back as the non-generic type is really the generic one" {
    publisher := new CallbackPublisher()
    handler: Action<int> = value => {
    }
    subscription: object = publisher.Subscribe(handler)

    assert subscription.GetType() == typeof(NSharpEventSubscription<Action<int>>)
    assert subscription.GetType().get_Name() == "NSharpEventSubscription`1"
    assert subscription.GetType().GetGenericTypeDefinition().get_Name() == "NSharpEventSubscription`1"
}

test "the open definition declares one type parameter, constrained to Delegate" {
    definition := typeof(NSharpEventSubscription<Action<int>>).GetGenericTypeDefinition()
    parameters := definition.GetGenericArguments()
    assert parameters.Length == 1
    assert parameters[0].get_Name() == "THandler"

    constraints := parameters[0].GetGenericParameterConstraints()
    assert constraints.Length == 1
    assert constraints[0] == typeof(Delegate)
}

namespace NSharpLang.TypeArity.Tests

import System
import System.Collections.Generic
import System.Reflection


// THE ACCEPTANCE CONTRACTS FOR `EventSubscription.nl`, EXECUTED.
//
// This is the compiler compiling its own runtime's shape: an ABSTRACT non-generic handle beside a
// SEALED generic one of the same name, the pair the whole arity feature exists to make expressible.
// The assertions come in two halves — what the subscription DOES, and what the CLR SEES — because the
// C# comment in `src/NSharpLang.Runtime/NSharpEventSubscription.cs` makes claims about both, and
// neither half was possible before.
class EventSubscriptionRecorder {
    Values: List<int>

    constructor() {
        Values = new List<int>()
    }

    func Record(value: int) {
        Values.Add(value)
    }
}

// Reflection answers nullable handles for a lookup by name, and every lookup below is for a member
// this project declares itself: a null means the emitter did not write it at all, which deserves its
// own sentence rather than a null dereference on the next line.
func EventSubscriptionMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no method named '" + name + "'.")
    }
    return method
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

// THE DETACH IS A NULL-CONDITIONAL CALL. `remove?.Invoke(handler)` must not reach the accessor at all
// once it has been claimed — a call that ran and did nothing would still be a call, and on the second
// `Unsubscribe` there is nothing there to call.
test "the claimed accessor is never invoked a second time" {
    detachCount := 0
    handler: Action<int> = value => {
    }
    detach: Action<Action<int>> = added => {
        detachCount = detachCount + 1
    }
    subscription := new NSharpEventSubscription<Action<int>>(detach, handler)

    subscription.Unsubscribe()
    assert detachCount == 1

    subscription.Unsubscribe()
    subscription.Unsubscribe()
    assert detachCount == 1
}

test "the generic subscription keeps the handler it was constructed with" {
    handler: Action<int> = value => {
    }
    detach: Action<Action<int>> = added => {
    }
    subscription := new NSharpEventSubscription<Action<int>>(detach, handler)
    assert Object.ReferenceEquals(subscription.Handler, handler)
}

// The C# passes `nameof(remove)` and `nameof(handler)` to `ArgumentNullException`. Reflection is the
// caller that can still hand a null to a non-nullable parameter — see the comment on
// `NSharpEventSubscriptionNullCaller` — and the name comes back on `ParamName`.
test "a null constructor argument throws ArgumentNullException naming the parameter" {
    handler: Action<int> = value => {
    }
    detach: Action<Action<int>> = added => {
    }

    assert NSharpEventSubscriptionNullCaller.RejectedParameterName(null, handler) == "remove"
    assert NSharpEventSubscriptionNullCaller.RejectedParameterName(detach, null) == "handler"

    // `remove` is checked FIRST, so a call with both missing names it and not `handler`.
    assert NSharpEventSubscriptionNullCaller.RejectedParameterName(null, null) == "remove"

    // And a well-formed pair rejects nothing.
    assert NSharpEventSubscriptionNullCaller.RejectedParameterName(detach, handler) == ""
}

// ── what the CLR sees ─────────────────────────────────────────────────────────────────────────

test "the generic subscription's CLR name is the arity name and its base is the non-generic one" {
    generic: Type = typeof(NSharpEventSubscription<Action<int>>)
    plain: Type = typeof(NSharpEventSubscription)

    assert generic.get_Name() == "NSharpEventSubscription`1"
    assert plain.get_Name() == "NSharpEventSubscription"
    assert generic.get_BaseType() == plain
    assert generic.IsSubclassOf(plain)
}

// The C# declares the base `abstract` and the subclass `sealed`, and both words are metadata a
// consumer in any .NET language reads: `abstract` is what refuses `newobj` on the base, and `sealed`
// is what refuses a further subclass.
test "the base is abstract and the generic subclass is sealed" {
    generic: Type = typeof(NSharpEventSubscription<Action<int>>)
    plain: Type = typeof(NSharpEventSubscription)

    assert plain.get_IsAbstract()
    assert !plain.get_IsSealed()
    assert generic.get_IsSealed()
    assert !generic.get_IsAbstract()
}

// `Unsubscribe` is ONE slot: the base opens it `abstract` with no body, and the subclass fills it
// with an `override` that reuses the slot. A subclass method in a NEW slot would build and would
// still leave a caller holding the base type calling nothing.
test "Unsubscribe is one virtual slot, abstract on the base and overridden on the subclass" {
    baseMethod := EventSubscriptionMethod(typeof(NSharpEventSubscription), "Unsubscribe")
    assert baseMethod.get_IsVirtual()
    assert baseMethod.get_IsAbstract()
    assert baseMethod.GetMethodBody() == null

    overridden := EventSubscriptionMethod(typeof(NSharpEventSubscription<Action<int>>), "Unsubscribe")
    assert overridden.get_IsVirtual()
    assert !overridden.get_IsAbstract()
    assert overridden.GetMethodBody() != null
    assert overridden.GetBaseDefinition() == baseMethod
    assert overridden.GetBaseDefinition().get_DeclaringType() == typeof(NSharpEventSubscription)
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

// The two fields the C# declares, with the C# types: a mutable `Action<THandler>?` remove accessor
// and a `readonly THandler` handler. Both close an external generic over the declaring type's own
// type parameter, which is the shape that used to decline at `emit.declaration.field-type`.
test "the subscription's fields carry the C# types, and the handler field is initonly" {
    definition := typeof(NSharpEventSubscription<Action<int>>).GetGenericTypeDefinition()
    fields := definition.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)

    removeFound := false
    handlerFound := false
    for field in fields {
        if field.get_Name() == "remove" {
            removeFound = true
            assert !field.get_IsInitOnly()
            assert field.get_FieldType().get_Name() == "Action`1"
        }

        if field.get_Name() == "handler" {
            handlerFound = true
            assert field.get_IsInitOnly()
            assert field.get_FieldType().get_IsGenericParameter()
            assert field.get_FieldType().get_Name() == "THandler"
        }
    }

    assert removeFound
    assert handlerFound
}

// The constructor a C# consumer sees: two parameters, in the C# order, under the C# names and with
// the C# types — `Action<THandler>` and `THandler`.
test "the constructor's parameters are the C# ones" {
    definition := typeof(NSharpEventSubscription<Action<int>>).GetGenericTypeDefinition()
    constructors := definition.GetConstructors()
    assert constructors.Length == 1

    parameters := constructors[0].GetParameters()
    assert parameters.Length == 2
    assert parameters[0].get_Name() == "remove"
    assert parameters[0].get_ParameterType().get_Name() == "Action`1"
    assert parameters[1].get_Name() == "handler"
    assert parameters[1].get_ParameterType().get_IsGenericParameter()
    assert parameters[1].get_ParameterType().get_Name() == "THandler"
}

// A NULL TEST ON A TYPE PARAMETER BOXES EXACTLY ONCE, AND THE COUNT IS THE CONTRACT.
//
// `handler == null` on a `THandler` is emitted as `box !T; ldnull; ceq`: `box` yields the reference
// itself for a reference instantiation and a fresh non-null box for a value one, which is C#'s
// reading of `T == null` for both. A SECOND `box` is not a harmless repeat — the first leaves an
// `object` where the second expects a `!T`, which is unverifiable IL ("found ref 'THandler',
// expected value 'THandler'") and, for a value-type instantiation, would box a box.
//
// The constructor is the one method in this file that asks the question, so a scan of its IL bytes
// finds the `box` opcode (0x8C) exactly once. The scan is a tripwire, not a disassembler: reflection
// hands back raw bytes, so a future token operand could in principle add a count — and would fail
// here with the number it found rather than letting a second real `box` back in.
test "a null test on the type parameter boxes exactly once" {
    definition := typeof(NSharpEventSubscription<Action<int>>).GetGenericTypeDefinition()
    constructors := definition.GetConstructors()
    assert constructors.Length == 1

    body := constructors[0].GetMethodBody()
    if body == null {
        throw new InvalidOperationException("The constructor has no IL body")
    }
    il := body.GetILAsByteArray()
    if il == null {
        throw new InvalidOperationException("The constructor body has no IL bytes")
    }

    boxCount := 0
    index := 0
    while index < il.Length {
        if il[index] == 0x8C {
            boxCount = boxCount + 1
        }
        index = index + 1
    }
    assert boxCount == 1, "box opcodes in the constructor: " + boxCount.ToString()
}

namespace NSharpLang.CensusEvents.Tests

import System.Collections.Generic
import System.Collections.ObjectModel


// RUNTIME CONTRACTS FOR `on` / `off`, ONE PER RECEIVER SHAPE THE CENSUS REPORTED.
//
// Before this slice, EVERY function in `EventSubscriptions.nl` declined the whole enclosing
// declaration at `parse.function` / `parse.struct` with NL103, so the file COMPILING is half of each
// contract. The other half is the COUNT: a subscription that attached to nothing and an `off` that
// detached nothing both compile, and only counting the raises each side actually observed tells them
// apart from a working one.
func NewList(): ObservableCollection<string> {
    return new ObservableCollection<string>()
}

test "a bare FIELD receiver subscribes, sees every raise until `off`, and nothing after it" {
    holder := new Holder()
    assert holder.CountThroughField() == 2
    // Three items were added; only the first two were observed.
    assert holder.Count() == 3
}

test "a `this.`-qualified field receiver is the same receiver" {
    holder := new Holder()
    assert holder.CountThroughThisField() == 1
    assert holder.Count() == 2
}

test "a LOCAL receiver subscribes and detaches" {
    assert CountThroughLocal() == 3
}

test "a PARAMETER receiver subscribes and detaches" {
    assert CountThroughParameter(NewList()) == 1
}

test "a PROPERTY-CHAIN receiver subscribes to the value the property answers" {
    assert CountThroughPropertyChain(new Holder()) == 1
}

test "an INDEXED element is a receiver like any other" {
    lists := new List<ObservableCollection<string>>()
    lists.Add(NewList())
    assert CountThroughIndexedElement(lists) == 1
}

test "a DELEGATE VALUE is a handler — the shape C#'s `+=` on a named handler maps onto" {
    assert CountThroughDelegateValue(NewList(), new Counter()) == 2
}

test "a METHOD GROUP is a handler — the same conversion a declared delegate local gets" {
    assert CountThroughMethodGroup(NewList()) == 2
}

test "two subscriptions to ONE event detach independently, each owning the delegate it added" {
    counts := CountTwoIndependentSubscriptions(NewList())
    assert counts.First == 1
    assert counts.Second == 2
}

test "`off` twice is a no-op" {
    assert CountWithDoubleOff(NewList()) == 1
}

test "a bare `on` statement discards the handle and leaves the handler attached" {
    assert CountWithDiscardedHandle(NewList(), new Counter()) == 2
}

test "the handle is an ordinary local, so a LOCAL FUNCTION can close over it and `off` it" {
    assert CountWithHandleDetachedFromLocalFunction(NewList()) == 1
}

test "`on` is an expression inside a LAMBDA body too" {
    assert CountWithSubscriptionInsideLambda(NewList(), new Counter()) == 1
}

test "`on` is an expression inside a LOCAL FUNCTION body too" {
    assert CountWithSubscriptionInsideLocalFunction(NewList(), new Counter()) == 1
}

test "`on` survives a suspension in an ASYNC body — the handle is a hoisted local like any other" {
    assert CountInsideAsyncBody(NewList()) == 1
}

test "a STATIC event on an external type subscribes and detaches through the type name" {
    assert SubscribeAndDetachStaticEvent()
}

test "a static event reached through a PROPERTY CHAIN on a static type subscribes and detaches" {
    assert SubscribeAndDetachStaticChainEvent()
}

test "a FREE FUNCTION returning a maybe-null reference is a handler for the event that declares one" {
    assert CountResolveThroughFreeFunction() == 1
}

test "a handler that never returns null reaches the same maybe-null delegate" {
    assert CountResolveThroughNonNullFreeFunction() == 1
}

test "an inline lambda against the same event infers its parameters and its result" {
    assert CountResolveThroughLambda() == 1
}

test "the delegate handed to `add_` is the event's own handler type" {
    assert ResolvingHandlerTypeName() == "Func`3"
}

test "a handler that starts async work and does not await it still runs that work to completion" {
    tally := new AsyncTally()
    assert CountThroughDiscardedTaskHandler(NewList(), tally) == 1
}

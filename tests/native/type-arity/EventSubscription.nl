namespace NSharpLang.TypeArity.Tests

import System
import System.Collections.Generic


// THE ACCEPTANCE CONSUMER: `src/NSharpLang.Runtime/NSharpEventSubscription.cs`, WRITTEN IN N#.
//
// That file is the reason this whole area exists. The runtime's event-subscription handle is a
// NON-GENERIC class beside a GENERIC one OF THE SAME NAME — "the non-generic base lets the compiler
// type every `on` result and every `off` target uniformly, while the generic subclass keeps the
// remove path strongly typed and reflection-free", in its own words — and until now the N# compiler
// could not express its own runtime's shape: `NSharpEventSubscription` beside
// `NSharpEventSubscription<THandler>` reported NL306, NL307 and NL207 at once, and even alone the
// generic one was emitted under the bare name `NSharpEventSubscription`, which no C# consumer can
// name. Both are fixed, and this file is compiled and executed to prove it.
//
// IT IS A TEST SOURCE, NOT A REPLACEMENT. `src/NSharpLang.Runtime/*.cs` has its own owner and is not
// touched; this is the same design under the same public names in a test namespace.
//
// FOUR THINGS DIFFER FROM THE C#, EACH BECAUSE THE COMPILER CANNOT YET SPELL THE ORIGINAL, AND NONE
// OF THEM IS ARITY-RELATED — every one reproduces on the pre-existing compiler:
//
//   (1) `Unsubscribe` is a CONCRETE member of the non-generic base rather than an `abstract` one
//       overridden by the subclass. `abstract func` on a class does not parse into columnar input
//       (`parse.struct`), and overriding a SOURCE base class's `virtual` member declines
//       (`emit.declaration.override-target`) — for a non-generic subclass too. Moving the body up
//       keeps the contract a caller sees: hold the non-generic type, call `Unsubscribe`, and the
//       subscription detaches.
//   (2) The remove callback is a non-generic `NSharpEventDetach` rather than `Action<THandler>`. A
//       BCL delegate closed over a source declaration's own type parameter is not an emittable
//       field type (`emit.declaration.field-type` on `Action<T>`), so the strongly-typed remove path
//       is carried by an interface instead of by a delegate.
//   (3) Both constructor parameters are declared NULLABLE. The C# declares them non-nullable and
//       null-checks them anyway, defensively, for callers that ignore the annotation; in a language
//       whose nullability is part of the type, "you may pass me null and I will throw
//       `ArgumentNullException`" is spelled `?` plus the check, and it is the only spelling a test
//       can actually pass null to.
//   (4) The once-only claim is a read-then-null rather than `Interlocked.Exchange`, because
//       `Interlocked.Exchange` over a reference type is not a modeled static call
//       (`emit.call.static-member-unmodeled`). The OBSERVABLE contract the C# documents — "safe to
//       call more than once; subsequent calls are no-ops" — is preserved and is asserted; the
//       atomicity under concurrent callers is not.
//
// Everything else is the original: the two names, the inheritance, the sealed generic subclass, its
// `where THandler: Delegate` constraint, the constructor's null checks with the parameter names the
// C# passes to `nameof`, and the claim-once detach.

// The event's `remove_` accessor, already bound to the event's owner — the role `Action<THandler>`
// plays in the C#.
interface NSharpEventDetach {
    func Detach()
}

// Handle returned by an N# `on` event subscription. Hold onto it and pass it to `off` to detach the
// handler again. The non-generic type is what every `on` result and every `off` target is typed as.
class NSharpEventSubscription {
    remove: NSharpEventDetach?

    public constructor(remove: NSharpEventDetach?) {
        if remove == null {
            throw new ArgumentNullException("remove")
        }

        this.remove = remove
    }

    // Detach the handler that this subscription added. Safe to call more than once; subsequent calls
    // are no-ops, because the first call CLAIMS the accessor and leaves nothing for the second.
    func Unsubscribe() {
        current := remove
        remove = null
        if current != null {
            current.Detach()
        }
    }
}

// Strongly-typed event subscription handle: it captures the event's remove accessor together with
// the handler delegate that was added. `THandler` is the event's handler delegate type.
sealed class NSharpEventSubscription<THandler>: NSharpEventSubscription where THandler: Delegate {
    readonly handler: THandler

    public constructor(remove: NSharpEventDetach?, handler: THandler?): base(remove) {
        if handler == null {
            throw new ArgumentNullException("handler")
        }

        this.handler = handler
    }

    Handler: THandler => handler
}

// The remove accessor for one handler in one callback list — what an event's `remove_` accessor is,
// reduced to the part a subscription holds.
class CallbackListDetach: NSharpEventDetach {
    readonly handlers: List<Action<int>>
    readonly handler: Action<int>

    public constructor(handlers: List<Action<int>>, handler: Action<int>) {
        this.handlers = handlers
        this.handler = handler
    }

    func Detach() {
        handlers.Remove(handler)
    }
}

// A real event-style callback list: handlers are added by `Subscribe`, invoked by `Raise`, and
// removed only through the subscription handle that `Subscribe` returned.
class CallbackPublisher {
    readonly handlers: List<Action<int>> = []

    HandlerCount: int => handlers.Count

    func Raise(value: int) {
        for handler in handlers {
            handler(value)
        }
    }

    func Subscribe(handler: Action<int>): NSharpEventSubscription {
        handlers.Add(handler)
        return new NSharpEventSubscription<Action<int>>(new CallbackListDetach(handlers, handler), handler)
    }
}

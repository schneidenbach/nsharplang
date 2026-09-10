namespace NSharpLang.TypeArity.Tests

import System
import System.Collections.Generic


// THE ACCEPTANCE CONSUMER: `src/NSharpLang.Runtime/NSharpEventSubscription.cs`, WRITTEN IN N#.
//
// That file is the reason this whole area exists. The runtime's event-subscription handle is a
// NON-GENERIC abstract class beside a GENERIC one OF THE SAME NAME — "the non-generic base lets the
// compiler type every `on` result and every `off` target uniformly, while the generic subclass keeps
// the remove path strongly typed and reflection-free", in its own words — and the N# compiler could
// not express its own runtime's shape at all: the pair reported NL306, NL307 and NL207 at once, the
// generic one was emitted under the bare name `NSharpEventSubscription` (which no C# consumer can
// name), `abstract func` on a class did not parse, `override` of a source base declined, an
// `Action<THandler>` field was not an emittable field type, and `remove?.Invoke(handler)` was a
// parse gap. Every one of those is fixed, and this file is compiled and executed to prove it.
//
// IT IS A TEST SOURCE, NOT A REPLACEMENT. `src/NSharpLang.Runtime/*.cs` has its own owner and is not
// touched; this is the same design under the same public names in a test namespace.
//
// ONE THING DIFFERS FROM THE C#, AND IT IS NOT ARITY-RELATED — it reproduces on the pre-existing
// compiler and on this one alike:
//
//   The once-only claim is a READ-THEN-NULL rather than `Interlocked.Exchange(ref remove, null)`.
//   A `ref` argument that names a FIELD now takes an address (`ldflda`), so `Fill(ref count)` and
//   `int.TryParse(text, out field)` both compile; what is still missing is `Interlocked.Exchange`
//   itself, which is a GENERIC static (`Exchange<T>(ref T, T)`) whose `ref T` parameter has to be
//   inferred from a by-ref argument — the semantic call planner types no by-ref argument at all yet,
//   so the call declines at `emit.call.static-member-unmodeled`. The OBSERVABLE contract the C#
//   documents — "safe to call more than once; subsequent calls are no-ops" — is preserved and is
//   asserted below; the ATOMICITY under concurrent callers is not.
//
// Everything else is the original: the two names, the abstract base and its abstract member, the
// sealed generic subclass, its `where THandler: Delegate` constraint, its `Action<THandler>?` remove
// field and `readonly THandler` handler field, the constructor's null checks with the parameter names
// the C# passes to `nameof`, the `override`, and the null-conditional detach.

// Handle returned by an N# `on` event subscription. Hold onto it and pass it to `off` to detach the
// handler again. Unlike .NET's native `-=`, the handle remembers the exact delegate that was added,
// so unsubscribing a lambda just works.
public abstract class NSharpEventSubscription {

    // Detach the handler that this subscription added. Safe to call more than once; subsequent calls
    // are no-ops.
    public abstract func Unsubscribe()
}

// Strongly-typed event subscription handle. Constructed by emitted IL for the `on` keyword: it
// captures the event's `remove_` accessor (already bound to the event's owner) together with the
// handler delegate that was added. `THandler` is the event's handler delegate type.
public sealed class NSharpEventSubscription<THandler>: NSharpEventSubscription where THandler: Delegate {
    remove: Action<THandler>?
    readonly handler: THandler

    public constructor(remove: Action<THandler>, handler: THandler) {
        if remove == null {
            throw new ArgumentNullException("remove")
        }

        if handler == null {
            throw new ArgumentNullException("handler")
        }

        this.remove = remove
        this.handler = handler
    }

    Handler: THandler => handler

    public override func Unsubscribe() {
        // Claim the remove accessor so a repeated off-call detaches exactly once — the second caller
        // sees null and does nothing.
        current := remove
        remove = null
        current?.Invoke(handler)
    }
}

// A real event-style callback list: handlers are added by `Subscribe`, invoked by `Raise`, and
// removed only through the subscription handle that `Subscribe` returned. The `remove_` accessor it
// hands to the subscription is an ordinary `Action<Action<int>>`, exactly as an emitted `on` would.
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
        detach: Action<Action<int>> = added => {
            handlers.Remove(added)
        }
        return new NSharpEventSubscription<Action<int>>(detach, handler)
    }
}

// THE NULL ARGUMENTS THE C# GUARDS AGAINST.
//
// Both constructor parameters are declared NON-NULLABLE, exactly as the C# declares them — and the
// C# null-checks them anyway, defensively, for callers who ignore the annotation. In N# there is no
// such caller: nullability is part of the type, definite assignment is enforced, and every route
// that would smuggle a null into a non-nullable parameter (a `T?` local, a cast from `object`, an
// unassigned field) is refused by the compiler before it runs. That is the language working, and it
// is also why the check cannot be reached from ordinary N# source.
//
// A C# consumer with nullable warnings off IS such a caller, and reflection is the same caller in N#
// terms: the constructor is invoked with an argument array, which is exactly how a language that does
// not track nullability reaches it. The check catches it, and `ArgumentNullException.ParamName`
// carries the name the C# passes to `nameof`.
class NSharpEventSubscriptionNullCaller {

    // The store is its own member because widening a delegate to `object?` happens at the CALL, where
    // the ordinary reference conversion applies; an array element store cannot widen on its own.
    static func StoreArgument(target: object?[], index: int, value: object?) {
        target[index] = value
    }

    // The parameter name the constructor rejected, or "" when it rejected nothing.
    static func RejectedParameterName(remove: object?, handler: object?): string {
        constructors := typeof(NSharpEventSubscription<Action<int>>).GetConstructors()
        arguments := new object?[](2)
        StoreArgument(arguments, 0, remove)
        StoreArgument(arguments, 1, handler)
        try {
            _ = constructors[0].Invoke(arguments)
        } catch error: Exception {
            inner := error.InnerException
            nullError := inner as ArgumentNullException
            if nullError != null {
                return nullError.ParamName ?? ""
            }

            if inner != null {
                return "unexpected: " + inner.Message
            }

            return "unexpected: " + error.Message
        }

        return ""
    }
}

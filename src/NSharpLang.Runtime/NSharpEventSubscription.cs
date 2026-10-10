using System;
using System.Threading;

namespace NSharpLang.Runtime;

/// <summary>
/// Handle returned by an N# <c>on</c> event subscription. Hold onto it and pass it to
/// <c>off</c> to detach the handler again. Unlike .NET's native <c>-=</c>, the handle
/// remembers the exact delegate that was added, so unsubscribing a lambda just works.
/// </summary>
/// <remarks>
/// The non-generic base lets the compiler type every <c>on</c> result and every <c>off</c>
/// target uniformly, while the generic subclass keeps the remove path strongly typed and
/// reflection-free.
/// </remarks>
public abstract class NSharpEventSubscription
{
    /// <summary>
    /// Detach the handler that this subscription added. Safe to call more than once;
    /// subsequent calls are no-ops.
    /// </summary>
    public abstract void Unsubscribe();
}

/// <summary>
/// Strongly-typed event subscription handle. Constructed by emitted IL for the <c>on</c>
/// keyword: it captures the event's <c>remove_</c> accessor (already bound to the event's
/// owner) together with the handler delegate that was added.
/// </summary>
/// <typeparam name="THandler">The event's handler delegate type.</typeparam>
public sealed class NSharpEventSubscription<THandler> : NSharpEventSubscription
    where THandler : Delegate
{
    private Action<THandler>? _remove;
    private readonly THandler _handler;

    /// <param name="remove">The event's <c>remove_</c> accessor, bound to the event owner.</param>
    /// <param name="handler">The handler delegate that was passed to the <c>add_</c> accessor.</param>
    public NSharpEventSubscription(Action<THandler> remove, THandler handler)
    {
        _remove = remove ?? throw new ArgumentNullException(nameof(remove));
        _handler = handler ?? throw new ArgumentNullException(nameof(handler));
    }

    /// <inheritdoc />
    public override void Unsubscribe()
    {
        // Atomically claim the remove accessor so concurrent (and repeated) off-calls detach
        // exactly once — the loser of the race sees null and does nothing.
        var remove = Interlocked.Exchange(ref _remove, null);
        remove?.Invoke(_handler);
    }
}

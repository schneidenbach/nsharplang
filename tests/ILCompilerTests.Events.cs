using System;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Probe type exercised by the <c>on</c>/<c>off</c> event-subscription IL tests. Instance
/// subscriptions use the per-instance <see cref="Source"/> counter so tests stay isolated;
/// the static event is only touched by a single test that unsubscribes before finishing.
/// </summary>
public static class EventInteropProbe
{
    public sealed class Source
    {
        public int Count;
        public event EventHandler? Ping;
        public void Fire() => Ping?.Invoke(this, EventArgs.Empty);
        public void Bump() => Count++;
    }

    public static Source NewSource() => new();

    public static int StaticCount;
    public static event EventHandler? StaticPing;
    public static void FireStatic() => StaticPing?.Invoke(null, EventArgs.Empty);
    public static void BumpStatic() => StaticCount++;
    public static void ResetStatic() => StaticCount = 0;
}

public class ILCompilerEventsTests : ILCompilerTestBase
{
    [Fact]
    public void ILCompiler_OnSubscription_InstanceEvent_FiresWhileSubscribedAndStopsAfterOff()
    {
        // The handler captures `src` (a closure) and bumps it; `off sub` must detach the exact
        // handler so the third Fire() is a no-op.
        var source = @"
import NSharpLang.Tests

func main(): int {
    src := EventInteropProbe.NewSource()
    sub := on src.Ping (sender, args) => {
        src.Bump()
    }
    src.Fire()
    src.Fire()
    off sub
    src.Fire()
    return src.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_OnSubscription_FireAndForgetStatement_Subscribes()
    {
        // `on` as a bare statement (no handle captured) still subscribes correctly.
        var source = @"
import NSharpLang.Tests

func main(): int {
    src := EventInteropProbe.NewSource()
    on src.Ping (sender, args) => {
        src.Bump()
    }
    src.Fire()
    src.Fire()
    src.Fire()
    return src.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_OnSubscription_StaticEvent_SubscribesAndUnsubscribes()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    EventInteropProbe.ResetStatic()
    sub := on EventInteropProbe.StaticPing (sender, args) => {
        EventInteropProbe.BumpStatic()
    }
    EventInteropProbe.FireStatic()
    off sub
    EventInteropProbe.FireStatic()
    return EventInteropProbe.StaticCount
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_DelegateField_CompoundAssignment_CombinesAndRemoves()
    {
        // A real delegate value (NOT an event) keeps working with `+=`/`-=`, lowering to
        // Delegate.Combine / Delegate.Remove. A multicast Func returns the last result.
        var source = @"
import System

func main(): int {
    f: Func<int, int> = x => x + 1
    g: Func<int, int> = x => x + 100
    f += g
    afterAdd := f(5)
    f -= g
    afterRemove := f(5)
    return afterAdd + afterRemove
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(111, Assert.IsType<int>(result));
    }
}

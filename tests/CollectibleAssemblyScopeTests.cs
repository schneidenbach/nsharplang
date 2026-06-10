using System;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.Loader;
using Xunit;

namespace NSharpLang.Tests;

public class CollectibleAssemblyScopeTests
{
    // The whole point of the scope: emitted test assemblies must NOT land in a context that pins
    // them for the test host's lifetime (Assembly.Load(byte[])'s behavior, which OOM-crashed the
    // host as the parity suite grew).
    [Fact]
    public void Load_UsesACollectibleNonDefaultContext()
    {
        using var scope = CollectibleAssemblyScope.Load(SelfAssemblyBytes());
        var context = AssemblyLoadContext.GetLoadContext(scope.Assembly)!;
        Assert.True(context.IsCollectible);
        Assert.NotSame(AssemblyLoadContext.Default, context);
    }

    // Disposing the scope must leave the context actually reclaimable — a rooted "collectible"
    // context (a cache, a static, a leaked delegate inside the helper) would silently regress to
    // the unbounded-pin behavior this type exists to prevent.
    [Fact]
    public void Dispose_LetsTheContextUnload()
    {
        var weakContext = LoadAndDispose(SelfAssemblyBytes());
        for (var i = 0; weakContext.IsAlive && i < 10; i++)
        {
            GC.Collect();
            GC.WaitForPendingFinalizers();
        }
        Assert.False(weakContext.IsAlive, "the collectible load context must be reclaimable after Dispose");
    }

    // No inlining: locals referencing the context must be out of scope (not extended by the JIT
    // into the caller's frame) before the unload-detecting GC runs.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static WeakReference LoadAndDispose(byte[] assemblyBytes)
    {
        var scope = CollectibleAssemblyScope.Load(assemblyBytes);
        var weakContext = new WeakReference(AssemblyLoadContext.GetLoadContext(scope.Assembly));
        scope.Dispose();
        return weakContext;
    }

    private static byte[] SelfAssemblyBytes()
        => File.ReadAllBytes(typeof(CollectibleAssemblyScopeTests).Assembly.Location);
}

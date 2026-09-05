using System;
using System.IO;
using System.Reflection;
using System.Runtime.Loader;

namespace NSharpLang.Tests;

/// <summary>
/// Loads an emitted test assembly into a collectible <see cref="AssemblyLoadContext"/> scoped by
/// <c>using</c>. <see cref="Assembly.Load(byte[])"/> pins each assembly in a fresh NON-collectible
/// context for the test host's lifetime — with hundreds of emitted parity assemblies per run (and
/// the parity suite growing every slice) that is an unbounded leak that intermittently OOM-crashes
/// the xUnit host. A pinned assembly also leaves its global types visible to later tests forever;
/// an unloaded context drops back out of that scan.
/// Keep every Type/MethodInfo/delegate obtained from <see cref="Assembly"/> inside the scope.
/// </summary>
internal sealed class CollectibleAssemblyScope : IDisposable
{
    private readonly AssemblyLoadContext _context;

    public Assembly Assembly { get; }

    private CollectibleAssemblyScope(AssemblyLoadContext context, Assembly assembly)
    {
        _context = context;
        Assembly = assembly;
    }

    public static CollectibleAssemblyScope Load(byte[] assemblyBytes)
    {
        var context = new AssemblyLoadContext("CollectibleTestAssembly", isCollectible: true);
        using var stream = new MemoryStream(assemblyBytes, writable: false);
        return new CollectibleAssemblyScope(context, context.LoadFromStream(stream));
    }

    public static CollectibleAssemblyScope LoadFromFile(string assemblyPath)
        => Load(File.ReadAllBytes(assemblyPath));

    public void Dispose() => _context.Unload();
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.Loader;
using System.Text.RegularExpressions;
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

    // The scope only helps if tests actually use it: within hours of the original conversion, new
    // dogfood slices reintroduced direct Assembly.Load calls. This guard turns the convention
    // (memory/testing.md, "Emitted Assemblies Load Into Collectible Scopes") into a failing test.
    [Fact]
    public void TestSources_HaveNoDirectAssemblyLoadCallSites()
    {
        var repoRoot = FindRepoRoot();
        var testsDirectory = Path.Combine(repoRoot, "tests");
        var offenders = new List<string>();

        foreach (var file in Directory.EnumerateFiles(testsDirectory, "*.cs", SearchOption.AllDirectories))
        {
            var relativePath = Path.GetRelativePath(repoRoot, file);
            var segments = relativePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (segments.Any(segment => segment is "bin" or "obj" or "TestResults"))
            {
                continue;
            }

            // The helper itself is the one place allowed to wrap the load APIs.
            if (Path.GetFileName(file) == "CollectibleAssemblyScope.cs")
            {
                continue;
            }

            var lines = File.ReadAllLines(file);
            for (var i = 0; i < lines.Length; i++)
            {
                if (DirectAssemblyLoadCall.IsMatch(StripLineCommentTail(lines[i])))
                {
                    offenders.Add($"{relativePath}:{i + 1}: {lines[i].Trim()}");
                }
            }
        }

        Assert.True(
            offenders.Count == 0,
            "Direct Assembly.Load / Assembly.LoadFile / Assembly.LoadFrom call sites pin emitted "
                + "assemblies in a non-collectible context for the test host's lifetime and "
                + "intermittently OOM-crash the host. Load through CollectibleAssemblyScope "
                + "(tests/CollectibleAssemblyScope.cs) instead — see memory/testing.md, "
                + "\"Emitted Assemblies Load Into Collectible Scopes\".\n"
                + string.Join("\n", offenders));
    }

    // Matches the banned static loader call sites: the "Assembly" receiver, a dot, a Load-prefixed
    // member, and an opening argument list on the same line. AssemblyLoadContext members
    // (LoadFromStream, LoadFromAssemblyPath, ...) do not match — oracle helpers may construct
    // load contexts directly.
    private static readonly Regex DirectAssemblyLoadCall =
        new(@"\bAssembly\s*\.\s*Load\w*\s*\(", RegexOptions.Compiled);

    // Comments and XML docs legitimately mention the banned APIs (this file does, and so does
    // CompilerDogfoodProjectTests); only code outside a //-comment tail counts as a call site.
    private static string StripLineCommentTail(string line)
    {
        var commentStart = line.IndexOf("//", StringComparison.Ordinal);
        return commentStart < 0 ? line : line[..commentStart];
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). "
                + $"Searched upward from {AppContext.BaseDirectory}");
    }
}

using System;
using System.Collections.Generic;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Pattern 5: a non-capturing ("static") lambda materialized as a delegate inside a loop. The N#
/// side caches the delegate in a static field, so it is constructed at most once. IL ratchet:
/// <c>Gate_StaticLambdaInLoop_ConstructsDelegateAtMostOnce</c>.
/// </summary>
[MemoryDiagnoser]
public class StaticLambdaBenchmarks
{
    private const string Source = """
import System
import System.Collections.Generic

func build(): int {
    handlers := new List<Func<int, int>>()
    for i := 0; i < 16; i = i + 1 {
        handler: Func<int, int> = (x) => x + 1
        handlers.Add(handler)
    }
    return handlers[0](41)
}
""";

    private Func<int> _nsharp = null!;

    [GlobalSetup]
    public void Setup() => _nsharp = NSharpCompiledMethod.Bind<Func<int>>(Source, "build");

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        var handlers = new List<Func<int, int>>();
        for (var i = 0; i < 16; i++)
        {
            // The C# compiler caches this non-capturing lambda in a static field too.
            Func<int, int> handler = x => x + 1;
            handlers.Add(handler);
        }

        return handlers[0](41);
    }

    [Benchmark]
    public int NSharp() => _nsharp();
}

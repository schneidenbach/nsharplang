using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Pattern 3: a small, closed, payload-free union lowered to a value struct. Constructing and
/// matching it does not box and does not allocate. IL ratchet:
/// <c>Gate_ValueStructUnion_DoesNotBox</c>.
/// </summary>
[MemoryDiagnoser]
public class ValueUnionBenchmarks
{
    private const string Source = """
union Signal {
    Stop
    Go
}

func classify(go: bool): int {
    s := new Signal.Stop
    if go {
        s = new Signal.Go
    }
    return match s {
        Signal.Stop => 0,
        Signal.Go => 1
    }
}
""";

    // Matched C# baseline: an enum is the idiomatic value-type, allocation-free equivalent.
    private enum Signal
    {
        Stop,
        Go,
    }

    private Func<bool, int> _nsharp = null!;

    [GlobalSetup]
    public void Setup() => _nsharp = NSharpCompiledMethod.Bind<Func<bool, int>>(Source, "classify");

    [Params(true, false)]
    public bool Go { get; set; }

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        var s = Signal.Stop;
        if (Go)
        {
            s = Signal.Go;
        }

        return s switch
        {
            Signal.Stop => 0,
            Signal.Go => 1,
            _ => throw new InvalidOperationException(),
        };
    }

    [Benchmark]
    public int NSharp() => _nsharp(Go);
}

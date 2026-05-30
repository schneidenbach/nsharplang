using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Pattern 2: <c>foreach</c> over <c>ReadOnlySpan&lt;T&gt;</c>. The N# side uses a
/// <c>Length</c> + indexer loop with no enumerator allocation. IL ratchet:
/// <c>Gate_ForeachOverSpan_AllocatesNoEnumerator</c>.
///
/// A span is a ref struct, so it cannot flow through <see cref="Func{T, TResult}"/>; the N# method
/// is bound to a custom by-ref-struct delegate.
/// </summary>
[MemoryDiagnoser]
public class ForeachSpanBenchmarks
{
    /// <summary>Delegate shape matching <c>func sumSpan(numbers: ReadOnlySpan&lt;int&gt;): int</c>.</summary>
    public delegate int SumSpan(ReadOnlySpan<int> numbers);

    private const string Source = """
import System

func sumSpan(numbers: ReadOnlySpan<int>): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}
""";

    private int[] _data = Array.Empty<int>();
    private SumSpan _nsharp = null!;

    [GlobalSetup]
    public void Setup()
    {
        _data = new int[1024];
        for (var i = 0; i < _data.Length; i++)
        {
            _data[i] = i;
        }

        _nsharp = NSharpCompiledMethod.Bind<SumSpan>(Source, "sumSpan");
    }

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        var sum = 0;
        foreach (var n in (ReadOnlySpan<int>)_data)
        {
            sum += n;
        }

        return sum;
    }

    [Benchmark]
    public int NSharp() => _nsharp(_data);
}

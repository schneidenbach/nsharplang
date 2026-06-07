using System.Numerics;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// RUST-PERF CEILING measurement (docs/design/systems-perf-backlog.md, item A "suggested first move"). The
/// systems-vs-native study found the checksum-sum reduction (`for i&lt;len { acc += a[i] }`) is ~8.2-8.8x
/// slower in systems-N# than C/Rust, because RyuJIT leaves it scalar while LLVM auto-vectorizes + unrolls it.
/// Before committing to a (large, correctness-critical) ILCompiler change that emits SIMD for reduction loops,
/// this quantifies the PRIZE: how much a hand-written System.Numerics.Vector&lt;int&gt; reduction beats the
/// scalar reduction under the SAME RyuJIT the N# codegen targets. The Vector&lt;int&gt; path is exactly the IL
/// the auto-vectorizing codegen would emit, so this ratio is the achievable ceiling on this machine
/// (Vector&lt;int&gt;.Count = 4 on ARM/NEON, 8 on x86/AVX2).
///
/// Reading: if Vectorized is ~Kx faster than Scalar here, auto-vectorizing the N# reduction codegen would turn
/// the ~8.8x native gap into roughly 8.8/Kx. This is a measurement only — it does not change the compiler.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class VectorReductionCeilingBenchmarks
{
    private int[] _data = System.Array.Empty<int>();

    [Params(64, 4096)]
    public int N { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _data = new int[N];
        // Deterministic non-trivial data (no Random — keep the loop the only variable).
        for (var i = 0; i < N; i++)
            _data[i] = (int)((uint)i * 2654435761u % 1009u);
    }

    // What the N# systems codegen emits today: a scalar accumulate, one add per element.
    [Benchmark(Baseline = true)]
    public int Scalar()
    {
        var acc = 0;
        var data = _data;
        for (var i = 0; i < data.Length; i++)
            acc += data[i];
        return acc;
    }

    // What an auto-vectorizing codegen would emit: Vector<int> accumulate + horizontal sum + scalar tail.
    [Benchmark]
    public int Vectorized()
    {
        var data = _data;
        var lanes = Vector<int>.Count;
        var acc = Vector<int>.Zero;
        var i = 0;
        for (; i <= data.Length - lanes; i += lanes)
            acc += new Vector<int>(data, i);
        var sum = Vector.Sum(acc);
        for (; i < data.Length; i++)
            sum += data[i];
        return sum;
    }

    // What an auto-vectorizing+unrolling codegen would emit: FOUR independent Vector<int> accumulators to hide
    // add latency (the trick LLVM uses for the ~8x). Processes 4*lanes elements per iteration. This is the
    // realistic ceiling the N# reduction codegen should target.
    [Benchmark]
    public int VectorizedUnrolled()
    {
        var data = _data;
        var lanes = Vector<int>.Count;
        var step = lanes * 4;
        var a0 = Vector<int>.Zero;
        var a1 = Vector<int>.Zero;
        var a2 = Vector<int>.Zero;
        var a3 = Vector<int>.Zero;
        var i = 0;
        for (; i <= data.Length - step; i += step)
        {
            a0 += new Vector<int>(data, i);
            a1 += new Vector<int>(data, i + lanes);
            a2 += new Vector<int>(data, i + lanes * 2);
            a3 += new Vector<int>(data, i + lanes * 3);
        }

        var sum = Vector.Sum(a0 + a1 + a2 + a3);
        for (; i < data.Length; i++)
            sum += data[i];
        return sum;
    }
}

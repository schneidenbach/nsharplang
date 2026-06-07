using System.Numerics;

namespace NSharpLang.Runtime;

/// <summary>
/// SIMD reduction helpers the N# systems codegen lowers recognized counted-reduction loops to (Rust-perf
/// roadmap P1). The compiler recognizes <c>while i &lt; end { acc = acc + a[i]; i = i + 1 }</c> on an
/// <c>int[]</c> and emits a call to <see cref="SumInt32"/> instead of the scalar loop — turning the
/// worst-case checksum-sum kernel from ~8.8× behind native to ~2× (see
/// docs/design/systems-perf-backlog.md). Keeping the vectorization here, in plain readable/testable C#,
/// rather than as hand-emitted IL, makes the codegen change trivial (load args + call) and the SIMD logic
/// auditable.
///
/// Correctness: integer wrapping addition is associative under mod 2^32, so reducing across SIMD lanes and
/// multiple accumulators is value-identical to the sequential scalar sum for ANY start/end (including
/// start &gt; 0 and lengths not a multiple of <see cref="Vector{T}.Count"/>, which the scalar tail handles).
/// </summary>
public static class SimdReductions
{
    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) — the value of
    /// the scalar loop <c>acc=0; for i in [start,end): acc += array[i]</c> — computed with unrolled SIMD.</summary>
    public static int SumInt32(int[] array, int start, int end)
    {
        var sum = 0;
        var i = start;
        var lanes = Vector<int>.Count;
        var step = lanes * 4;

        // Four independent accumulators hide add latency (the LLVM trick measured at ~4.5× vs a single
        // scalar accumulator in VectorReductionCeilingBenchmarks).
        var a0 = Vector<int>.Zero;
        var a1 = Vector<int>.Zero;
        var a2 = Vector<int>.Zero;
        var a3 = Vector<int>.Zero;
        for (; i <= end - step; i += step)
        {
            a0 += new Vector<int>(array, i);
            a1 += new Vector<int>(array, i + lanes);
            a2 += new Vector<int>(array, i + lanes * 2);
            a3 += new Vector<int>(array, i + lanes * 3);
        }

        sum += Vector.Sum(a0 + a1 + a2 + a3);

        // Scalar tail for the remaining < step elements (and the whole range when end-start < step).
        for (; i < end; i++)
            sum += array[i];

        return sum;
    }
}

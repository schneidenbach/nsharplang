using System.Numerics;

namespace NSharpLang.Runtime;

/// <summary>
/// SIMD reduction helpers the N# systems codegen lowers recognized counted-reduction loops to (Rust-perf
/// roadmap P1). The compiler recognizes <c>while i &lt; end { acc = acc + a[i]; i = i + 1 }</c> on an integer
/// array and emits a call to the matching <see cref="SumInt32"/> / <see cref="SumInt64"/> /
/// <see cref="SumUInt32"/> / <see cref="SumUInt64"/> helper instead of the scalar loop — turning the
/// worst-case checksum-sum kernel from ~8.8× behind native to ~2× (see
/// docs/design/systems-perf-backlog.md). Keeping the vectorization here, in plain readable/testable C#,
/// rather than as hand-emitted IL, makes the codegen change trivial (load args + call) and the SIMD logic
/// auditable.
///
/// Correctness: integer wrapping addition is associative under mod 2^32 (int/uint) / mod 2^64 (long/ulong),
/// so reducing across SIMD lanes and multiple accumulators is value-identical to the sequential scalar sum
/// for ANY start/end (including start &gt; 0 and lengths not a multiple of <see cref="Vector{T}.Count"/>,
/// which the scalar tail handles). float/double are deliberately NOT provided: FP addition is not associative.
///
/// Each helper is value-identical to the scalar loop <c>for (i = start; i &lt; end; i++) sum += array[i]</c>
/// for EVERY (start, end), including degenerate ones: an empty/negative range (<c>end &lt;= start</c>, e.g.
/// <c>end = int.MinValue</c>) returns the identity with no reads, and an out-of-bounds range (<c>start &lt; 0</c>
/// or <c>end &gt; array.Length</c>) throws <see cref="System.IndexOutOfRangeException"/> at the exact same
/// element the scalar loop would — the SIMD fast path is taken only over a provably in-bounds range.
/// </summary>
public static class SimdReductions
{
    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) — the value of
    /// the scalar loop <c>acc=0; for i in [start,end): acc += array[i]</c> — computed with unrolled SIMD.</summary>
    public static int SumInt32(int[] array, int start, int end)
    {
        var sum = 0;
        var i = start;

        // Empty/negative range: the scalar loop `while i < end` never runs. Returning here also prevents the
        // `end - step` bound below from being computed for a hugely-negative `end` (e.g. int.MinValue), which
        // would wrap (unchecked) to a large positive value and run the SIMD loop over elements the scalar loop
        // never touches.
        if (end <= start)
            return sum;

        // SIMD fast path only over a provably in-bounds range [start, end). If the range is out of bounds
        // (start < 0 or end > array.Length), skip it: the scalar tail below then reproduces the scalar
        // semantics exactly, including throwing IndexOutOfRangeException at the same element — whereas
        // new Vector<T>(array, i) would throw a DIFFERENT, observable type (ArgumentOutOfRangeException).
        if (start >= 0 && end <= array.Length)
        {
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
        }

        // Scalar tail for the remaining < step elements, or the whole range when the fast path was skipped.
        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) for
    /// <c>long</c> (Rust-perf P1(d)). <c>long</c> wrapping add is associative under mod 2^64, so the unrolled
    /// SIMD reduction is value-identical to the scalar loop.</summary>
    public static long SumInt64(long[] array, int start, int end)
    {
        var sum = 0L;
        var i = start;

        if (end <= start)
            return sum;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<long>.Count;
            var step = lanes * 4;

            var a0 = Vector<long>.Zero;
            var a1 = Vector<long>.Zero;
            var a2 = Vector<long>.Zero;
            var a3 = Vector<long>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<long>(array, i);
                a1 += new Vector<long>(array, i + lanes);
                a2 += new Vector<long>(array, i + lanes * 2);
                a3 += new Vector<long>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) for
    /// <c>uint</c> (Rust-perf P1(d)). Unsigned wrapping add is associative under mod 2^32.</summary>
    public static uint SumUInt32(uint[] array, int start, int end)
    {
        var sum = 0u;
        var i = start;

        if (end <= start)
            return sum;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<uint>.Count;
            var step = lanes * 4;

            var a0 = Vector<uint>.Zero;
            var a1 = Vector<uint>.Zero;
            var a2 = Vector<uint>.Zero;
            var a3 = Vector<uint>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<uint>(array, i);
                a1 += new Vector<uint>(array, i + lanes);
                a2 += new Vector<uint>(array, i + lanes * 2);
                a3 += new Vector<uint>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) for
    /// <c>ulong</c> (Rust-perf P1(d)). Unsigned wrapping add is associative under mod 2^64.</summary>
    public static ulong SumUInt64(ulong[] array, int start, int end)
    {
        var sum = 0uL;
        var i = start;

        if (end <= start)
            return sum;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<ulong>.Count;
            var step = lanes * 4;

            var a0 = Vector<ulong>.Zero;
            var a1 = Vector<ulong>.Zero;
            var a2 = Vector<ulong>.Zero;
            var a3 = Vector<ulong>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<ulong>(array, i);
                a1 += new Vector<ulong>(array, i + lanes);
                a2 += new Vector<ulong>(array, i + lanes * 2);
                a3 += new Vector<ulong>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            sum += array[i];

        return sum;
    }
}
